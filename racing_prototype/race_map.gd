extends Control

const Traffic := preload("res://racing_prototype/traffic.gd")
const RoadControl := preload("res://racing_prototype/road_control.gd")
const LIVE_COLORS := [Color("58e9a1"), Color("ffd16c"), Color("ff6e66")]
const MAP_MARGIN := 16.0

var _track: Node3D
var _player: Node3D
var _traffic: Traffic
var _center := Vector2.ZERO
var _span := Vector2.ONE
var _map_scale := 1.0
var _road := PackedVector2Array()
var _gates := PackedVector2Array()
var _checkpoints: Array[Transform3D]
var _finish_index := 0
var _next_gate := 0
var _refresh := 0.0
## Race opponents drawn as coloured dots.
var rivals: Array = []


func configure(track: Node3D, player: Node3D, traffic: Traffic,
		checkpoints: Array[Transform3D], finish_index: int) -> void:
	_track = track
	_player = player
	_traffic = traffic
	_checkpoints = checkpoints
	_finish_index = finish_index
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(146, 180)
	resized.connect(_fit_route)
	_fit_route()


func update_checkpoint(index: int) -> void:
	_next_gate = index


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 1.0 / 24.0
		queue_redraw()


func _fit_route() -> void:
	var centerline: PackedVector3Array = _track.centerline()
	var bounds := Rect2(_flatten(centerline[0]), Vector2.ZERO)
	for point in centerline:
		bounds = bounds.expand(_flatten(point))
	_center = bounds.get_center()
	_span = bounds.size
	var available := (size - Vector2.ONE * MAP_MARGIN * 2.0).max(Vector2.ONE)
	_map_scale = minf(available.x / _span.x, available.y / _span.y)
	_road.clear()
	for point in centerline:
		_road.append(_map_point(point))
	_road.append(_road[0])
	_gates.clear()
	for gate in _checkpoints:
		_gates.append(_map_point(gate.origin))
	queue_redraw()


func _draw() -> void:
	if _road.is_empty():
		return
	draw_polyline(_road, Color("23364a"), 12.0, true)
	draw_polyline(_road, Color("8398aa"), 6.0, true)
	for site in _traffic._sites:
		var position_on_map := _map_point(site.position)
		if site.kind == RoadControl.Kind.SIGNAL:
			draw_circle(position_on_map, 4.0, LIVE_COLORS[site.phase], true, -1.0, true)
		elif site.kind == RoadControl.Kind.STOP:
			draw_rect(Rect2(position_on_map - Vector2(3, 3), Vector2(6, 6)), Color("ffc091"))
		else:
			draw_rect(Rect2(position_on_map - Vector2(3, 3), Vector2(6, 6)), Color("dbe8ee"))
	var finish := _gates[_finish_index]
	var right := _flatten(_checkpoints[_finish_index].basis.x) * 7.0
	draw_line(finish - right, finish + right, Color.WHITE, 2.0, true)
	draw_arc(_gates[_next_gate], 7.0, 0, TAU, 20, Color("69f2ca"), 1.4, true)
	for car in _traffic._vehicles:
		var color := Color("f4b88c") if car.direction < 0 else Color("e3edf5")
		var target := _traffic.overtake_targets.has(car)
		draw_circle(_map_point(car.position), 2.6 if target else 1.7, Color("80dbff") if target else color, true, -1.0, true)
	for rival in rivals:
		draw_circle(_map_point(rival.position), 3.4, Color("101929"), true, -1.0, true)
		draw_circle(_map_point(rival.position), 2.6, rival.color, true, -1.0, true)
	var nose := _flatten(-_player.basis.z).normalized()
	var side := nose.orthogonal()
	var position_on_map := _map_point(_player.position).clamp(Vector2(9, 9), size - Vector2(9, 9))
	var arrow := PackedVector2Array([
		position_on_map + nose * 8.0, position_on_map - nose * 4.5 + side * 5.0,
		position_on_map - nose * 2.7, position_on_map - nose * 4.5 - side * 5.0,
	])
	draw_colored_polygon(arrow, Color("63f4c3"))


func _map_point(point: Vector3) -> Vector2:
	return size * 0.5 + (_flatten(point) - _center) * _map_scale


func _flatten(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)
