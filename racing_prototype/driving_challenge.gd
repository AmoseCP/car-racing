extends RefCounted

const Courses := preload("res://racing_prototype/courses.gd")
const CITY := &"city_clean"
const TUNNEL := &"rain_night"
const OVERTAKE := &"safe_overtake"
const ORDER := [CITY, TUNNEL, OVERTAKE]

const DATA := {
	CITY: {
		"title": "守规一圈", "course": &"city", "vehicle": &"gt", "weather": &"clear", "lighting": &"day",
		"goal": "在城市完成一圈。提前减速，按信号通行，在 STOP 前停稳。",
		"limit": 70.0, "silver": 48.0, "gold": 38.0,
	},
	TUNNEL: {
		"title": "雨夜穿行", "course": &"tunnel", "vehicle": &"rally", "weather": &"rain", "lighting": &"night",
		"goal": "开灯穿过隧道。出洞后留意湿地刹车，在 STOP 前停稳，再开过终点。",
		"limit": 40.0, "silver": 25.0, "gold": 18.0,
	},
	OVERTAKE: {
		"title": "安全超车", "course": &"grassland", "vehicle": &"gt", "weather": &"clear", "lighting": &"day",
		"goal": "超过两辆带青色标记的慢车。横向变道时留在右半幅，安全驶过终点。",
		"limit": 43.0, "silver": 24.0, "gold": 17.0,
	},
}

var id: StringName
var profile: Dictionary
var start: Transform3D
var checkpoints: Array[Transform3D] = []
var passed_count := 0

var _observed_behind := {}
var _passed := {}


func configure(challenge_id: StringName, track: Node3D) -> void:
	id = challenge_id
	profile = DATA[id]
	var finish: float = track.control_distance(0)
	var distances: Array[float]
	var start_distance := finish
	var start_lane := 0
	match id:
		CITY:
			distances = [
				track.control_distance(1), track.control_distance(2), track.control_distance(3), finish,
			]
		TUNNEL:
			var portals: Vector2 = track.tunnel_portals()
			var middle: float = portals.x + fposmod(portals.y - portals.x, track.road_length()) * 0.5
			start_distance = portals.x - 10.0
			distances = [portals.x, middle, portals.y, track.control_distance(2) + 12.0]
		OVERTAKE:
			start_lane = 1
			start_distance = finish - 35.0
			var signal_location: float = track.control_distance(1)
			distances = [finish, signal_location, signal_location + 96.0]
	start = track.road_pose(start_distance, track.lane_offset(start_lane))
	start.origin.y = 0.05
	for distance in distances:
		checkpoints.append(track.road_pose(distance))


func reset() -> void:
	_observed_behind.clear()
	_passed.clear()
	passed_count = 0


func check_position(traffic: Node3D, track: Node3D, car: CharacterBody3D) -> String:
	var location: Vector2 = traffic.player_location()
	var margin := 0.7 if id == OVERTAKE else 0.2
	if location.y < margin or location.y > track.half_road - margin:
		return "驶出右侧车道区域"
	if id != OVERTAKE:
		return ""
	var length: float = track.road_length()
	var adjacent: bool = location.y < (track.lane_offset(0) + track.lane_offset(1)) * 0.5
	for target in traffic.overtake_targets:
		if _passed.has(target):
			continue
		var gap := fposmod(location.x - target.progress + length * 0.5, length) - length * 0.5
		if gap < -5.0 and gap > -50.0:
			_observed_behind[target] = true
		if adjacent and car.speed > target.speed and gap >= 5.0 and gap <= 19.0 and _observed_behind.has(target):
			_passed[target] = true
			passed_count += 1
	return ""


func medal(seconds: float) -> Courses.Medal:
	if seconds <= profile.gold:
		return Courses.Medal.GOLD
	if seconds <= profile.silver:
		return Courses.Medal.SILVER
	return Courses.Medal.BRONZE


func add_finish_marker(parent: Node3D, half_road: float) -> void:
	if id == CITY:
		return
	var marker := Node3D.new()
	marker.name = "ChallengeFinish"
	marker.transform = checkpoints[-1]
	parent.add_child(marker)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("67ecca")
	paint.emission_enabled = true
	paint.emission = paint.albedo_color
	paint.emission_energy_multiplier = 0.45
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.16, 2.4, 0.16)
		mesh.material = paint
		post.mesh = mesh
		post.position = Vector3(side * (half_road + 0.38), 1.2, 0)
		marker.add_child(post)
	var strip := MeshInstance3D.new()
	var band := BoxMesh.new()
	band.size = Vector3(half_road - 0.5, 0.009, 0.22)
	band.material = paint
	strip.mesh = band
	strip.position = Vector3(half_road * 0.5, 0.057, 0)
	marker.add_child(strip)
	var banner := Label3D.new()
	banner.text = "FINISH"
	banner.position = Vector3(0, 3.1, 0)
	banner.font_size = 88
	banner.pixel_size = 0.011
	banner.modulate = Color("a4ffda")
	banner.outline_size = 5
	marker.add_child(banner)
