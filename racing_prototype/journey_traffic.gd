extends Node3D

signal violation(message: String)
signal overtake()

const Track := preload("res://racing_prototype/journey_track.gd")
const Road := preload("res://racing_prototype/road_control.gd")
const Vehicle := preload("res://racing_prototype/traffic_vehicle.gd")
const Units := preload("res://racing_prototype/units.gd")
const CARS_PER_LANE := 3
const BRAKING := 7.0
## Margin kept inside the legal band, and the gentle rates used to meet the
## next zone's band before its sign.
const BAND_MARGIN_MPH := 1.5
## Tighter margin used only to bridge a large limit change (45 -> 65 mph),
## where the comfortable bands of the two zones do not overlap.
const ZONE_MARGIN_MPH := 0.3
const ZONE_BRAKING := 3.0
const ZONE_ACCELERATION := 3.0
const BASE_CRUISE := 22.3
const CRUISE_SPREAD := 2.3

var vehicles: Array[Vehicle] = []
var _track: Track
var _car: CharacterBody3D
var _clock := 0.0
var _previous_nose := Vector2.ZERO
var _previous_player := Vector2.ZERO
var _stops: Dictionary[int, float] = {}
var _seen: Dictionary[Vehicle, bool] = {}
var _passed: Dictionary[Vehicle, bool] = {}
var _motions := PackedFloat32Array()
var _wrong_time := 0.0
var _wrong_reported := false


func configure(track: Track, car: CharacterBody3D) -> void:
	_track = track
	_car = car
	for lane in range(-2, 2):
		for index in range(CARS_PER_LANE):
			var vehicle := Vehicle.new()
			vehicle.configure(posmod(lane * 3 + index, Vehicle.MODELS.size()), lane, 22.3 + float(index) * 1.15)
			add_child(vehicle, true)
			vehicles.append(vehicle)
	_motions.resize(vehicles.size())
	reset()


func reset() -> void:
	_clock = 0.0
	_wrong_time = 0.0
	_wrong_reported = false
	_stops.clear()
	_seen.clear()
	_passed.clear()
	_previous_nose = _track.road_location(_car.front_position())
	_previous_player = _track.road_location(_car.position)
	for index in range(vehicles.size()):
		var vehicle := vehicles[index]
		var first: float = [97.0, 67.0, 45.0, 76.0][vehicle.lane + 2]
		_spawn(vehicle, first + float(index % CARS_PER_LANE) * 105.0, _car.headlights_on)


func advance(delta: float, dark: bool, weather_factor: float) -> String:
	_clock += delta
	var player := _track.road_location(_car.position)
	for site in _track.sites:
		site.advance(_clock)
	_check_rules(player, delta)
	_check_overtakes(player)
	_previous_player = player
	for vehicle in vehicles:
		if vehicle.progress < player.x - 155.0:
			_spawn(vehicle, _spawn_distance(vehicle.lane, player.x + 430.0, 1), dark)
		elif vehicle.progress > player.x + 560.0:
			_spawn(vehicle, _spawn_distance(vehicle.lane, player.x - 155.0, -1), dark)
	for index in range(vehicles.size()):
		_plan(index, player, delta, weather_factor)
	for index in range(vehicles.size()):
		var vehicle := vehicles[index]
		var movement := _motions[index]
		vehicle.progress += movement * vehicle.direction
		var pose := _track.road_pose(vehicle.progress, _track.lane_offset(vehicle.lane), vehicle.direction)
		vehicle.display(pose, movement, dark, vehicle.speed < _free_speed(vehicle, weather_factor) - 2.0)
	return _approach_hint(player)


func _plan(index: int, player: Vector2, delta: float, weather_factor: float) -> void:
	var car := vehicles[index]
	var space := INF
	var ahead_speed := INF
	for other in vehicles:
		var headway := (other.progress - car.progress) * car.direction
		if other != car and other.lane == car.lane and headway > 0.0:
			var gap := headway - car.half_length - other.half_length - 2.35
			if gap < space:
				space = gap
				ahead_speed = other.speed
	var player_headway := (player.x - car.progress) * car.direction
	if player_headway > 0.0 and absf(player.y - _track.lane_offset(car.lane)) < 1.85:
		var gap: float = player_headway - car.half_length - _car.front_length() - 2.60
		if gap < space:
			space = gap
			ahead_speed = absf(_car.speed) if signf(player.y) == car.direction else 0.0
	for site in _track.sites:
		var headway := (site.distance - car.direction * Road.STOP_OFFSET - car.progress) * car.direction
		if headway < 0.0 or headway > 68.0:
			continue
		var gap := headway - car.half_length - 0.75
		if _must_stop(car, site, gap, delta) and gap < space:
			space = gap
			ahead_speed = 0.0
	var free := _free_speed(car, weather_factor)
	var held := sqrt(ahead_speed * ahead_speed + maxf(space, 0.0) * (2.0 * BRAKING))
	# Still "held up" while pulling away until back at cruising pace.
	car.held_up = held < free or (car.held_up and car.speed < free - 0.3)
	var target := minf(free, held)
	var natural := move_toward(car.speed, target, (BRAKING if target < car.speed else 3.6) * delta)
	var permitted := maxf(0.0, space) + ahead_speed * delta
	_motions[index] = minf(natural * delta, permitted)
	car.speed = _motions[index] / delta


## Cruising speed (m/s). Each car keeps its own pace, but always inside the
## legal band of the zone it is in, and it meets the next zone's band before
## reaching that sign. Bad weather only slows cars within the band.
func _free_speed(vehicle: Vehicle, weather_factor: float) -> float:
	var limit := float(_track.speed_limit(vehicle.progress))
	var pace := clampf((vehicle.cruise_speed - BASE_CRUISE) / CRUISE_SPREAD, 0.0, 1.0)
	var desired := limit - 5.0 + 10.0 * pace - (1.0 - weather_factor) * 20.0
	var low := _band_floor(limit)
	var high := _band_ceiling(limit)
	# Limits change at chunk boundaries: meet the next zone's band right at its sign.
	var boundary := Track.CHUNK * (ceilf(vehicle.progress / Track.CHUNK) if vehicle.direction > 0 else (
		floorf(vehicle.progress / Track.CHUNK)))
	var distance := absf(boundary - vehicle.progress)
	var next := float(_track.speed_limit(boundary + vehicle.direction * 0.5))
	if next != limit:
		var bounds := _meet_next_zone(limit, next, distance, low, high, BAND_MARGIN_MPH)
		if bounds.x > bounds.y:
			bounds = _meet_next_zone(limit, next, distance, low, high, ZONE_MARGIN_MPH)
		low = bounds.x
		high = bounds.y
	return clampf(desired, minf(low, high), high) / Units.MPH


## Speed bounds (mph) that reach the next zone's band exactly at its sign.
## With the tight margin, the current zone's bound on the conflicting side is
## relaxed to its own tight edge so the two bands can be bridged.
func _meet_next_zone(limit: float, next: float, distance: float, low: float, high: float,
		margin: float) -> Vector2:
	var next_high := _band_ceiling(next, margin) / Units.MPH
	var next_low := _band_floor(next, margin) / Units.MPH
	high = minf(high, sqrt(next_high * next_high + 2.0 * ZONE_BRAKING * distance) * Units.MPH)
	low = maxf(low, sqrt(maxf(0.0, next_low * next_low - 2.0 * ZONE_ACCELERATION * distance)) * Units.MPH)
	if margin < BAND_MARGIN_MPH:
		if next > limit:
			high = maxf(high, minf(low, _band_ceiling(limit, margin)))
		else:
			low = minf(low, maxf(high, _band_floor(limit, margin)))
	return Vector2(low, high)


func _band_floor(limit: float, margin := BAND_MARGIN_MPH) -> float:
	return limit - Track.UNDER_LIMIT_MPH + margin


func _band_ceiling(limit: float, margin := BAND_MARGIN_MPH) -> float:
	return limit + Track.OVER_LIMIT_MPH - margin


func needs_to_slow(player: Vector2, minimum_mph: int) -> bool:
	var front: Vector2 = _track.road_location(_car.front_position())
	for site in _track.sites:
		var distance := site.distance - Road.STOP_OFFSET - front.x
		if distance < -0.5 or distance > 38.0:
			continue
		if site.kind == Road.Kind.STOP and _stops.get(site.get_instance_id(), 0.0) < 0.65:
			return true
		if site.kind == Road.Kind.SIGNAL and (site.phase != Road.Phase.GREEN or site.crossing_reserved):
			return true
	var lookahead := maxf(25.0, minimum_mph / Units.MPH * 1.6)
	for vehicle in vehicles:
		var distance := vehicle.progress - player.x
		if vehicle.direction > 0 and distance > 0.0 and distance < lookahead and (
				absf(player.y - _track.lane_offset(vehicle.lane)) < 1.9 and vehicle.speed * Units.MPH <= minimum_mph):
			return true
	return false


func _must_stop(car: Vehicle, site: Road, gap: float, delta: float) -> bool:
	match site.kind:
		Road.Kind.SIGNAL:
			return site.phase == Road.Phase.RED or (site.phase == Road.Phase.AMBER and
				car.speed * car.speed < 2.0 * BRAKING * maxf(gap, 0.0))
		Road.Kind.STOP:
			var id := site.get_instance_id()
			if car.cleared_stop == id:
				return false
			if car.speed < 0.35 and gap < 1.3:
				if car.waiting_at != id:
					car.waiting_at = id
					car.wait_time = 0.0
				car.wait_time += delta
				if car.wait_time >= 0.95:
					car.cleared_stop = id
					return false
			return true
		_:
			return site.crossing_reserved


func _spawn_distance(lane: int, initial: float, direction: int) -> float:
	var progress := initial
	for other in vehicles:
		if other.lane == lane and absf(other.progress - progress) < 34.0:
			progress = other.progress + direction * 36.0
	return progress


func _spawn(vehicle: Vehicle, progress: float, dark: bool) -> void:
	vehicle.progress = progress
	vehicle.speed = _free_speed(vehicle, _car.weather.speed_factor)
	vehicle.cleared_stop = -1
	vehicle.waiting_at = -1
	vehicle.wait_time = 0.0
	_seen.erase(vehicle)
	_passed.erase(vehicle)
	vehicle.display(_track.road_pose(progress, _track.lane_offset(vehicle.lane), vehicle.direction), 0.0, dark, false)
	vehicle.reset_physics_interpolation()


func _check_rules(player: Vector2, delta: float) -> void:
	var nose := _track.road_location(_car.front_position())
	for site in _track.sites:
		var key := site.get_instance_id()
		var line := site.distance - Road.STOP_OFFSET
		var distance := line - nose.x
		var in_road := absf(nose.y) <= Track.HALF_ROAD
		if distance > 5.0 or not in_road:
			_stops.erase(key)
		elif site.kind == Road.Kind.STOP and distance >= -0.012:
			if absf(_car.speed) <= 0.35:
				_stops[key] = _stops.get(key, 0.0) + delta
			elif _stops.get(key, 0.0) < 0.65:
				_stops.erase(key)
		if _previous_nose.x < line and nose.x >= line and in_road:
			if site.kind == Road.Kind.SIGNAL and site.phase == Road.Phase.RED:
				violation.emit("闯红灯")
			elif site.kind == Road.Kind.STOP:
				if _stops.get(key, 0.0) < 0.65:
					violation.emit("停车标志前未停稳")
				_stops.erase(key)
			elif site.pedestrians_present:
				violation.emit("未礼让行人")
	_previous_nose = nose
	var movement := player.x - _previous_player.x
	if absf(player.y) > 0.55 and absf(player.y) < Track.HALF_ROAD and movement * signf(player.y) < -delta * 2.0:
		_wrong_time += delta
		if _wrong_time >= 0.9 and not _wrong_reported:
			_wrong_reported = true
			violation.emit("逆向行驶")
	elif movement * signf(player.y) > delta or absf(player.y) >= Track.HALF_ROAD:
		_wrong_time = 0.0
		_wrong_reported = false


func _check_overtakes(player: Vector2) -> void:
	if player.y <= 0.7 or player.y >= Track.HALF_ROAD - 0.7:
		_seen.clear()
		return
	for vehicle in vehicles:
		if vehicle.direction < 0 or _passed.has(vehicle):
			continue
		var gap := player.x - vehicle.progress
		if gap < -6.0 and gap > -65.0:
			_seen[vehicle] = true
		elif gap > 6.0 and gap < 16.0 and _car.speed > vehicle.speed and _seen.has(vehicle):
			if absf(player.y - _track.lane_offset(vehicle.lane)) > 2.15:
				_passed[vehicle] = true
				overtake.emit()


func _approach_hint(player: Vector2) -> String:
	for site in _track.sites:
		var ahead := site.distance - player.x
		if ahead < 3.0 or ahead > 45.0:
			continue
		if site.kind == Road.Kind.STOP:
			return "前方 STOP · 停稳后通行"
		if site.phase == Road.Phase.RED:
			return "前方红灯 · 减速停车"
		if site.phase == Road.Phase.AMBER:
			return "前方黄灯"
		return "前方绿灯"
	return ""
