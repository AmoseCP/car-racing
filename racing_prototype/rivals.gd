extends Node3D
## Race director for the opponents. Rivals take their pace from the player's car,
## brake for corners, obey signals and STOP signs, change lanes around slower
## cars and use the boost pads.

const Rival := preload("res://racing_prototype/rival.gd")
const Vehicles := preload("res://racing_prototype/vehicles.gd")
const Courses := preload("res://racing_prototype/courses.gd")
const ROSTER := [
	{"name": "疾风", "color": Color("ff9b70"), "pace": 0.93, "grid": 2, "lane": 0, "livery": 1},
	{"name": "银狐", "color": Color("a7d4ff"), "pace": 0.975, "grid": 3, "lane": 1, "livery": 3},
	{"name": "赤焰", "color": Color("ffd166"), "pace": 1.02, "grid": 5, "lane": 1, "livery": 7},
]
const BRAKING := 24.0
const LANE_SHIFT_SPEED := 3.4
const CORNER_SAMPLE := 12.0
const CORNER_REACH := 6
const BOOST_SECONDS := 1.2
const BOOST_GAIN := 1.18
const LANE_WIDTH_HALF := 1.9

var racers: Array[Rival] = []
var started := false
## Seconds since the green light.
var clock := 0.0
## Rivals in the order they took the chequered flag.
var finish_order: Array[Rival] = []

var _track: Node3D
var _traffic: Node3D
var _car: CharacterBody3D
var _length := 1.0
var _start := 0.0
var _top_speed := 40.0
var _acceleration := 18.0
var _turn_rate := 1.3
var _pads: Array[Vector2] = []


func configure(track: Node3D, traffic: Node3D, car: CharacterBody3D) -> void:
	_track = track
	_traffic = traffic
	_car = car
	_length = track.road_length()
	_start = track.control_distance(0)
	var profile: Dictionary = Vehicles.DATA[car.vehicle_id]
	_top_speed = profile.top_speed
	_acceleration = profile.acceleration
	_turn_rate = profile.steering.y
	for pad: Transform3D in track.boost_pads:
		_pads.append(track.road_location(pad.origin))
	var first := Vehicles.ORDER.find(car.vehicle_id)
	for index in range(ROSTER.size()):
		var entry: Dictionary = ROSTER[index]
		var rival := Rival.new()
		rival.name = "Rival%d" % (index + 1)
		var vehicle: StringName = Vehicles.ORDER[(first + index + 1) % Vehicles.ORDER.size()]
		rival.configure(vehicle, entry.livery, entry.name, entry.color, entry.pace)
		add_child(rival)
		racers.append(rival)
	traffic.rivals.assign(racers)
	reset()


func reset() -> void:
	started = false
	clock = 0.0
	finish_order.clear()
	for index in range(racers.size()):
		var rival := racers[index]
		var entry: Dictionary = ROSTER[index]
		rival.progress = _track.grid_progress(entry.grid)
		rival.lateral = _track.lane_offset(entry.lane)
		rival.target_lateral = rival.lateral
		rival.covered = from_start(rival.progress)
		rival.speed = 0.0
		rival.boost_time = 0.0
		rival.finished = false
		rival.finish_time = INF
		rival.cleared_stop = -1
		rival.waiting_at = -1
		rival.wait_time = 0.0
		rival.place(_track.road_pose(rival.progress, rival.lateral), 0.0, false)
		rival.reset_physics_interpolation()


## Signed distance from the start line, negative behind it.
func from_start(progress: float) -> float:
	return fposmod(progress - _start + _length * 0.5, _length) - _length * 0.5


func advance(delta: float, weather_factor: float, player: Vector2) -> void:
	if not started:
		return
	clock += delta
	for rival in racers:
		_drive(rival, delta, weather_factor, player)


## 1-based position of a racer that has covered the given distance.
func rank_for(player_covered: float) -> int:
	var rank := 1
	for rival in racers:
		if rival.finished or rival.covered > player_covered:
			rank += 1
	return rank


## Final position for a player whose race time (from the green light, penalties
## included) is known; unfinished rivals are projected to the line at race pace.
func final_rank(player_time: float) -> int:
	var rank := 1
	for rival in racers:
		var eta := rival.finish_time
		if not rival.finished:
			var remaining := Courses.LAP_COUNT * _length - rival.covered
			eta = clock + remaining / maxf(_top_speed * rival.skill * 0.75, 1.0)
		if eta < player_time:
			rank += 1
	return rank


func _drive(rival: Rival, delta: float, weather_factor: float, player: Vector2) -> void:
	var old_speed := rival.speed
	rival.boost_time = maxf(0.0, rival.boost_time - delta)
	var pace := _top_speed * rival.skill * weather_factor
	if rival.boost_time > 0.0:
		pace *= BOOST_GAIN
	if rival.finished:
		pace *= 0.7
	var target := minf(pace, _corner_limit(rival.progress) * weather_factor)
	_choose_lane(rival, target, player)
	var rule_gap: float = _traffic.rule_gap(rival, old_speed, delta)
	target = minf(target, sqrt(2.0 * BRAKING * maxf(rule_gap, 0.0)))
	for lane in [rival.lateral, rival.target_lateral]:
		var blocker := _nearest_ahead(rival, lane, player)
		target = minf(target, sqrt(blocker.y * blocker.y + 2.0 * BRAKING * maxf(blocker.x - 1.5, 0.0)))
	var pull := Vehicles.power_curve(old_speed / _top_speed)
	var rate := BRAKING if target < old_speed else _acceleration * pull * (1.45 if rival.boost_time > 0.0 else 1.0)
	rival.speed = move_toward(old_speed, target, rate * delta)
	var movement := minf(rival.speed * delta, maxf(rule_gap, 0.0))
	var previous_lateral := rival.lateral
	rival.lateral = move_toward(rival.lateral, rival.target_lateral, LANE_SHIFT_SPEED * delta)
	_check_pads(rival, movement)
	rival.progress = fposmod(rival.progress + movement, _length)
	rival.covered += movement
	if not rival.finished and rival.covered >= Courses.LAP_COUNT * _length:
		rival.finished = true
		rival.finish_time = clock
		finish_order.append(rival)
	var pose: Transform3D = _track.road_pose(rival.progress, rival.lateral)
	var drift := atan2((rival.lateral - previous_lateral) / delta, maxf(rival.speed, 4.0))
	pose.basis = pose.basis.rotated(Vector3.UP, -drift)
	rival.place(pose, movement, target < old_speed - 0.5)


func _corner_limit(progress: float) -> float:
	# Slowest speed that still lets the car brake for every bend in sight.
	var limit := INF
	var previous: Vector3 = _track.road_pose(progress).basis.z
	for step in range(1, CORNER_REACH + 1):
		var heading: Vector3 = _track.road_pose(progress + step * CORNER_SAMPLE).basis.z
		var bend := previous.angle_to(heading)
		previous = heading
		if bend < 0.01:
			continue
		var corner_speed := _turn_rate * 0.92 * CORNER_SAMPLE / bend
		var room := (step - 1) * CORNER_SAMPLE
		limit = minf(limit, sqrt(corner_speed * corner_speed + 2.0 * BRAKING * room))
	return limit


func _choose_lane(rival: Rival, target: float, player: Vector2) -> void:
	if absf(rival.target_lateral - rival.lateral) > 0.2:
		return
	var blocker := _nearest_ahead(rival, rival.lateral, player)
	if blocker.x > 38.0 or blocker.y > target - 1.0:
		return
	var inner: float = _track.lane_offset(0)
	var outer: float = _track.lane_offset(1)
	var other := outer if absf(rival.lateral - inner) < absf(rival.lateral - outer) else inner
	if _lane_clear(rival, other, player):
		rival.target_lateral = other


## Gap to and speed of the nearest car ahead in a lane: Vector2(gap, speed).
func _nearest_ahead(rival: Rival, lane: float, player: Vector2) -> Vector2:
	var best := Vector2(INF, 0.0)
	for other in _obstacles(player):
		if absf(other.lateral - lane) > LANE_WIDTH_HALF or other.agent == rival:
			continue
		var ahead := fposmod(other.progress - rival.progress, _length)
		if ahead > 90.0:
			continue
		var gap: float = ahead - rival.half_length - other.half_length
		if gap < best.x:
			best = Vector2(gap, other.speed)
	return best


func _lane_clear(rival: Rival, lane: float, player: Vector2) -> bool:
	for other in _obstacles(player):
		if absf(other.lateral - lane) > LANE_WIDTH_HALF or other.agent == rival:
			continue
		var offset := fposmod(other.progress - rival.progress + _length * 0.5, _length) - _length * 0.5
		if offset > -10.0 and offset < 32.0:
			return false
	return true


func _obstacles(player: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = [{
		"agent": _car, "progress": player.x, "lateral": player.y,
		"half_length": _car.front_length(), "speed": maxf(_car.speed, 0.0),
	}]
	for vehicle in _traffic.vehicles():
		if vehicle.direction > 0:
			result.append({
				"agent": vehicle, "progress": vehicle.progress, "lateral": _track.lane_offset(vehicle.lane),
				"half_length": vehicle.half_length, "speed": vehicle.speed,
			})
	for other in racers:
		result.append({
			"agent": other, "progress": other.progress, "lateral": other.lateral,
			"half_length": other.half_length, "speed": other.speed,
		})
	return result


func _check_pads(rival: Rival, movement: float) -> void:
	for pad in _pads:
		var ahead := fposmod(pad.x - rival.progress, _length)
		if ahead <= movement and absf(pad.y - rival.lateral) < 2.0:
			rival.boost_time = BOOST_SECONDS
