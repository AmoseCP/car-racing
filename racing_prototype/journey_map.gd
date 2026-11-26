extends Control

const Track := preload("res://racing_prototype/journey_track.gd")
const Traffic := preload("res://racing_prototype/journey_traffic.gd")
const Road := preload("res://racing_prototype/road_control.gd")
const SIGNAL_COLORS := [Color("5eeca9"), Color("ffcc63"), Color("ff786b")]

var _track: Track
var _traffic: Traffic
var _car: Node3D
var _refresh := 0.0


func configure(track: Track, traffic: Traffic, car: Node3D) -> void:
	_track = track
	_traffic = traffic
	_car = car
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(146.0, 174.0)
	clip_contents = true


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 1.0 / 24.0
		queue_redraw()


func _draw() -> void:
	if _track == null:
		return
	var position_on_road := _track.road_location(_car.position)
	var route := PackedVector2Array()
	for offset in range(-24, 151, 5):
		var ahead := position_on_road.x + offset
		route.append(_project(ahead, _track.road_x(ahead), position_on_road.x))
	draw_polyline(route, Color("283e53"), 15.0, true)
	draw_polyline(route, Color("8296a8"), 9.0, true)
	for site in _track.sites:
		if absf(site.distance - position_on_road.x) < 150.0:
			var color: Color = Color("ffa985") if site.kind == Road.Kind.STOP else SIGNAL_COLORS[site.phase]
			draw_circle(_project(site.distance, _track.road_x(site.distance), position_on_road.x), 4.0, color)
	for vehicle in _traffic.vehicles:
		var ahead := vehicle.progress - position_on_road.x
		if ahead >= -25.0 and ahead <= 150.0:
			var color := Color("f4ad83") if vehicle.direction < 0 else Color("dfe9f2")
			draw_circle(_project(vehicle.progress, vehicle.position.x, position_on_road.x), 2.7, color, true, -1.0, true)
	var at := _project(position_on_road.x, _car.position.x, position_on_road.x)
	var heading := Vector2(-_car.basis.z.x, -_car.basis.z.z).normalized()
	var side := heading.orthogonal()
	draw_colored_polygon(PackedVector2Array([
		at + heading * 8.0, at - heading * 5.0 + side * 5.5, at - heading * 2.5, at - heading * 5.0 - side * 5.5,
	]), Color("68f4c3"))


func _project(progress: float, point_x: float, player: float) -> Vector2:
	return Vector2(size.x * 0.5 + (point_x - _track.road_x(player)) * 2.05,
		size.y - 26.0 - (progress - player) * 0.86)
