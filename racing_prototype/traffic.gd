extends Node3D

signal violation(message: String, points: int)

const RoadControl := preload("res://racing_prototype/road_control.gd")
const Vehicle := preload("res://racing_prototype/traffic_vehicle.gd")
const Ui := preload("res://racing_prototype/ui_skin.gd")
const BRAKING := 6.6
const STOP_SPEED := 0.35
const STOP_SECONDS := 0.65
const APPROACH_LENGTH := 5.0
const CARS_PER_LANE := 3

var overtake_targets: Array[Vehicle] = []
## Race rivals sharing the road; traffic keeps its distance from them.
var rivals: Array[Node3D] = []
var _track: Node3D
var _car: CharacterBody3D
var _length: float
var _sites: Array[RoadControl] = []
var _vehicles: Array[Vehicle] = []
var _positions := PackedFloat32Array()
var _motions := PackedFloat32Array()
var _player_stops: Dictionary[int, float] = {}
var _previous_nose: Vector3
var _previous_player: Vector2
var _clock := 0.0
var _wrong_way_time := 0.0
var _wrong_way_reported := false
var _contact: Vehicle
var _collision_cooldown := 0.0


func configure(track: Node3D, car: CharacterBody3D, overtaking := false) -> void:
	_track = track
	_car = car
	_length = _track.road_length()
	var kinds := [RoadControl.Kind.SIGNAL, RoadControl.Kind.STOP, RoadControl.Kind.CROSSWALK]
	for index in range(kinds.size()):
		var site := RoadControl.new()
		site.name = ["TrafficLights", "StopSigns", "PedestrianCrossing"][index]
		var distance: float = _track.control_distance(index + 1)
		site.transform = _track.road_pose(distance)
		add_child(site)
		site.configure(kinds[index], distance, _track.half_road, 5.0 + index * 3.8)
		_sites.append(site)
	for lane in range(-2, 2):
		for index in range(CARS_PER_LANE):
			var car_node := Vehicle.new()
			car_node.name = "TrafficCar"
			var model := posmod(lane * 2 + index, Vehicle.MODELS.size())
			var cruise := 15.2 if lane in [-1, 0] else 12.2
			car_node.configure(model, lane, cruise + float(index) * 0.9 - (1.0 if model == 3 else 0.0))
			add_child(car_node, true)
			_vehicles.append(car_node)
			if overtaking and lane == 1 and index > 0:
				car_node.cruise_speed = 6.7 + index * 0.55
				overtake_targets.append(car_node)
				var marker := Label3D.new()
				marker.text = "目标 %d" % index
				marker.font = Ui.UI_FONT
				marker.font_size = 46
				marker.pixel_size = 0.01
				marker.modulate = Ui.GREEN
				marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				marker.position.y = 2.9
				car_node.add_child(marker)
	_positions.resize(_vehicles.size())
	_motions.resize(_vehicles.size())
	reset()


func reset() -> void:
	_clock = 0.0
	_wrong_way_time = 0.0
	_wrong_way_reported = false
	_contact = null
	_collision_cooldown = 0.0
	_previous_nose = _car.front_position()
	_previous_player = _track.road_location(_car.position)
	_player_stops.clear()
	for site in _sites:
		site.advance(_clock)
	for index in range(_vehicles.size()):
		var vehicle := _vehicles[index]
		var initial: float = [49.0, 34.0, 38.0, 53.0][vehicle.lane + 2]
		initial += float(index % CARS_PER_LANE) * _length / CARS_PER_LANE
		var target := overtake_targets.find(vehicle)
		if target >= 0:
			initial = 17.0 + target * 18.0
		vehicle.progress = fposmod(_previous_player.x + initial, _length)
		vehicle.speed = vehicle.cruise_speed
		vehicle.cleared_stop = -1
		vehicle.waiting_at = -1
		vehicle.wait_time = 0.0
		_display(vehicle, 0.0, _car.headlights_on, false)
		vehicle.reset_physics_interpolation()


func vehicles() -> Array[Vehicle]:
	return _vehicles


func player_location() -> Vector2:
	return _previous_player


func advance(delta: float, weather_factor: float, dark: bool) -> String:
	_clock += delta
	for site in _sites:
		site.advance(_clock)
	var player: Vector2 = _track.road_location(_car.position)
	var nose: Vector3 = _car.front_position()
	_check_crossings(nose, delta)
	_check_wrong_way(player, delta)
	_check_collision(delta)
	_previous_nose = nose
	_previous_player = player

	# Read every car's old location before moving any of them.
	for index in range(_vehicles.size()):
		_positions[index] = _vehicles[index].progress
	for index in range(_vehicles.size()):
		_plan_motion(index, player, delta, weather_factor)
	for index in range(_vehicles.size()):
		var vehicle := _vehicles[index]
		var movement := _motions[index]
		vehicle.progress = fposmod(vehicle.progress + vehicle.direction * movement, _length)
		_display(vehicle, movement, dark, vehicle.speed < vehicle.cruise_speed * weather_factor - 1.6)
	return _approach_info(nose)


func _plan_motion(index: int, player: Vector2, delta: float, weather_factor: float) -> void:
	var vehicle := _vehicles[index]
	var gap := INF
	var old_speed := vehicle.speed
	for other_index in range(_vehicles.size()):
		var other := _vehicles[other_index]
		if other_index == index or other.lane != vehicle.lane:
			continue
		var distance := _ahead(vehicle, _positions[other_index])
		gap = minf(gap, distance - vehicle.half_length - other.half_length - 1.45)
	var lane_center: float = _track.lane_offset(vehicle.lane)
	if absf(player.y - lane_center) < 1.8:
		gap = minf(gap, _ahead(vehicle, player.x) - vehicle.half_length - _car.front_length() - 1.3)
	if vehicle.direction > 0:
		for rival in rivals:
			if absf(rival.lateral - lane_center) < 1.9:
				gap = minf(gap, _ahead(vehicle, rival.progress) - vehicle.half_length - rival.half_length - 1.3)
	gap = minf(gap, rule_gap(vehicle, old_speed, delta))
	var heading: Transform3D = _track.road_pose(vehicle.progress)
	var ahead: Transform3D = _track.road_pose(vehicle.progress + vehicle.direction * 12.0)
	var curve := heading.basis.z.angle_to(ahead.basis.z)
	var curve_speed := lerpf(vehicle.cruise_speed, 7.4, smoothstep(0.09, 0.62, curve))
	var target := minf(curve_speed * weather_factor, sqrt(2.0 * BRAKING * maxf(gap, 0.0)))
	vehicle.speed = move_toward(old_speed, target, (BRAKING if target < old_speed else 3.3) * delta)
	_motions[index] = minf(vehicle.speed * delta, maxf(0.0, gap))
	if _motions[index] < vehicle.speed * delta:
		vehicle.speed = _motions[index] / delta


## Distance an agent may still travel before a signal, STOP sign or crosswalk
## requires it to halt (INF when nothing applies). The agent needs progress,
## direction, half_length, cleared_stop, waiting_at and wait_time.
func rule_gap(agent: Node3D, old_speed: float, delta: float) -> float:
	var gap := INF
	for site_index in range(_sites.size()):
		var site := _sites[site_index]
		var line: float = site.distance - agent.direction * RoadControl.STOP_OFFSET
		var line_ahead: float = fposmod((line - agent.progress) * agent.direction, _length)
		var space: float = line_ahead - agent.half_length - 0.62
		if site_index == agent.cleared_stop and line_ahead < _length - 12.0 and line_ahead > _length * 0.5:
			agent.cleared_stop = -1
		if line_ahead > 42.0:
			continue
		match site.kind:
			RoadControl.Kind.SIGNAL:
				var can_brake := old_speed * old_speed < 2.0 * BRAKING * maxf(space, 0.0)
				if site.phase == RoadControl.Phase.RED or (site.phase == RoadControl.Phase.AMBER and can_brake):
					gap = minf(gap, maxf(0.0, space))
			RoadControl.Kind.STOP:
				if agent.cleared_stop != site_index:
					if old_speed <= STOP_SPEED and space < 1.25:
						if agent.waiting_at != site_index:
							agent.waiting_at = site_index
							agent.wait_time = 0.0
						agent.wait_time += delta
						if agent.wait_time >= 1.0:
							agent.cleared_stop = site_index
							agent.waiting_at = -1
					if agent.cleared_stop != site_index:
						gap = minf(gap, maxf(0.0, space))
			RoadControl.Kind.CROSSWALK:
				if site.crossing_reserved:
					gap = minf(gap, maxf(0.0, space))
	return gap


func _display(vehicle: Vehicle, movement: float, dark: bool, braking: bool) -> void:
	var pose: Transform3D = _track.road_pose(vehicle.progress, _track.lane_offset(vehicle.lane), vehicle.direction)
	vehicle.display(pose, movement, braking, dark)


func _ahead(vehicle: Vehicle, to: float) -> float:
	return fposmod((to - vehicle.progress) * vehicle.direction, _length)


func _check_crossings(nose: Vector3, delta: float) -> void:
	for index in range(_sites.size()):
		var site := _sites[index]
		var inverse := site.transform.affine_inverse()
		var previous := inverse * _previous_nose
		var current := inverse * nose
		for direction: int in [1, -1]:
			var distance := current.z * direction - RoadControl.STOP_OFFSET
			var previous_distance := previous.z * direction - RoadControl.STOP_OFFSET
			var key: int = index * 2 + (0 if direction == 1 else 1)
			if site.kind == RoadControl.Kind.STOP and distance >= -0.01:
				if distance > APPROACH_LENGTH or absf(current.x) > _track.half_road:
					_player_stops.erase(key)
				elif absf(_car.speed) <= STOP_SPEED:
					_player_stops[key] = _player_stops.get(key, 0.0) + delta
				elif _player_stops.get(key, 0.0) < STOP_SECONDS:
					_player_stops.erase(key)
			if previous_distance <= 0.0 or distance > 0.0:
				continue
			var across := lerpf(previous.x, current.x, previous_distance / (previous_distance - distance))
			if absf(across) > _track.half_road + 0.4:
				continue
			if site.kind == RoadControl.Kind.SIGNAL and site.phase == RoadControl.Phase.RED:
				violation.emit("闯红灯", 15)
			elif site.kind == RoadControl.Kind.STOP:
				if _player_stops.get(key, 0.0) < STOP_SECONDS:
					violation.emit("停车标志前未停稳", 10)
				_player_stops.erase(key)
			elif site.pedestrians_present:
				violation.emit("未礼让行人", 15)


func _check_wrong_way(player: Vector2, delta: float) -> void:
	var movement := fposmod(player.x - _previous_player.x + _length * 0.5, _length) - _length * 0.5
	if absf(player.y) > 0.6 and absf(player.y) < _track.half_road and movement * signf(player.y) < -delta * 2.0:
		_wrong_way_time += delta
		if _wrong_way_time >= 0.9 and not _wrong_way_reported:
			_wrong_way_reported = true
			violation.emit("逆向行驶", 10)
	elif movement * signf(player.y) > delta * 1.3:
		_wrong_way_time = 0.0
		_wrong_way_reported = false
	elif not _wrong_way_reported:
		_wrong_way_time = maxf(0.0, _wrong_way_time - delta)


func _check_collision(delta: float) -> void:
	_collision_cooldown = maxf(0.0, _collision_cooldown - delta)
	var touching: Vehicle
	for index in range(_car.get_slide_collision_count()):
		var other := _car.get_slide_collision(index).get_collider()
		if other is Vehicle:
			touching = other
			break
	if touching != null and touching != _contact and _collision_cooldown <= 0.0:
		_collision_cooldown = 1.3
		violation.emit("碰撞其他车辆", 12)
	_contact = touching


func _approach_info(nose: Vector3) -> String:
	for site in _sites:
		var local: Vector3 = site.transform.affine_inverse() * nose
		if local.z <= 1.8 or local.z > 33.0 or absf(local.x) > _track.half_road:
			continue
		match site.kind:
			RoadControl.Kind.SIGNAL:
				match site.phase:
					RoadControl.Phase.RED: return "前方红灯 · 停车"
					RoadControl.Phase.AMBER: return "前方黄灯"
					_: return "前方绿灯"
			RoadControl.Kind.STOP:
				return "停车标志 · 在停止线前停稳"
			RoadControl.Kind.CROSSWALK:
				return "行人正在过街 · 让行" if site.pedestrians_present else "前方人行横道"
	return ""
