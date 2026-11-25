@tool
extends Node3D

const Courses := preload("res://racing_prototype/courses.gd")
const Art := preload("res://racing_prototype/track_art.gd")

@export var course_id: StringName = &"desert"

var course: Dictionary
var gates: Array[Transform3D] = []
var boost_pads: Array[Transform3D] = []
var half_road: float
var _wall_offset: float
var _centers: PackedVector3Array
var _outward: PackedVector3Array
var _distance: PackedFloat32Array
var _gate_indices: PackedInt32Array
var _scenery_batches: Dictionary = {}
var _roof_first := 0
var _roof_segments := 0
var _roof_half_width := 0.0


func _ready() -> void:
	course = Courses.DATA[course_id]
	half_road = course.width
	_wall_offset = half_road + 1.9
	_sample_centerline()
	_add_track()
	_add_start_grid()
	_add_boost_pads()
	match course_id:
		&"desert": _add_landscape()
		&"city": _add_city()
		&"tunnel": _add_tunnel()
		&"grassland": _add_grassland()
		&"forest": _add_forest()
	_flush_scenery()


func _sample_centerline() -> void:
	var oval: Vector3 = course.oval
	var bend: Vector2 = course.bend
	var corners := [
		Vector3(oval.x, 0, oval.y), Vector3(-oval.x, 0, oval.y),
		Vector3(-oval.x, 0, -oval.y), Vector3(oval.x, 0, -oval.y),
	]
	var middles := PackedInt32Array()
	for corner in range(corners.size()):
		for step in range(13):
			var angle := (corner + step / 12.0) * PI * 0.5
			var normal := Vector3(cos(angle), 0, sin(angle))
			_centers.append(corners[corner] + normal * oval.z)
		var straight_start := _centers[-1]
		var straight_end: Vector3 = straight_start + corners[(corner + 1) % corners.size()] - corners[corner]
		var half_segments := ceili(straight_start.distance_to(straight_end) / 6.0)
		var segments := half_segments * 2
		middles.append(_centers.size() - 1 + half_segments)
		for step in range(1, segments):
			_centers.append(straight_start.lerp(straight_end, float(step) / segments))
	for i in range(_centers.size()):
		var point := _centers[i]
		_centers[i] += Vector3(bend.x * sin(point.z * PI / oval.y), 0,
			bend.y * sin(point.x * PI / oval.x))
	_distance.append(0.0)
	for i in range(_centers.size()):
		var next := _centers[(i + 1) % _centers.size()]
		var tangent := (next - _centers[i - 1]).normalized()
		_outward.append(Vector3(tangent.z, 0, -tangent.x))
		_distance.append(_distance[i] + _centers[i].distance_to(next))
	for i in [3, 2, 1, 0]:
		_gate_indices.append(middles[i])
		gates.append(_course_transform(middles[i]))


func _course_transform(index: int) -> Transform3D:
	var right := _outward[index]
	var back := Vector3(-right.z, 0, right.x)
	return Transform3D(Basis(right, Vector3.UP, back), _centers[index])


func spawn_transform() -> Transform3D:
	var index := (_gate_indices[0] + 4) % _centers.size()
	var start := _course_transform(index)
	start.origin.y = 0.05
	return start


func _add_track() -> void:
	var asphalt := Art.road()
	var shoulder := Art.ground(course_id, 1.0)
	var chalk := _material(Color("f0ebdc"))
	var coral := _material(Color("df5235"))
	var rail := _material(Color("6b7780"))
	var reflective := _material(course.accent)
	rail.cull_mode = BaseMaterial3D.CULL_DISABLED
	rail.metallic = 0.65
	rail.roughness = 0.47
	reflective.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_strip("Shoulder", -_wall_offset - 0.3, _wall_offset + 0.3, 0.012, 0.012, shoulder)
	_add_strip("Asphalt", -half_road, half_road, 0.024, 0.024, asphalt)
	for side in [-1.0, 1.0]:
		var curb_start: float = side * half_road - 0.4
		var curb_end: float = side * half_road + 0.4
		_add_strip("WhiteCurb", curb_start, curb_end, 0.04, 0.04, chalk, 0)
		_add_strip("RedCurb", curb_start, curb_end, 0.04, 0.04, coral, 1)
		var edge: float = side * (half_road - 0.5)
		_add_strip("EdgeLine", edge - 0.055, edge + 0.055, 0.033, 0.033, chalk)
		var wall: float = side * _wall_offset
		var wall_mesh := _add_strip("Guardrail", wall, wall, 0.012, 0.88, rail)
		_add_strip("GuardrailCap", wall - 0.10, wall + 0.10, 0.88, 0.88, rail)
		_add_strip("GuardrailRib", wall - side * 0.07, wall - side * 0.07, 0.27, 0.38, rail)
		_add_strip("Reflectors", wall + side * 0.012, wall + side * 0.012,
			0.69, 0.79, reflective, 0)
		_add_strip("InsideReflectors", wall - side * 0.012, wall - side * 0.012,
			0.69, 0.79, reflective, 0)
		var barrier := StaticBody3D.new()
		barrier.name = "OuterBarrier" if side > 0 else "InnerBarrier"
		var collider := CollisionShape3D.new()
		var shape := wall_mesh.create_trimesh_shape()
		shape.backface_collision = true
		collider.shape = shape
		barrier.add_child(collider)
		add_child(barrier)


func _add_strip(node_name: String, offset_a: float, offset_b: float, height_a: float,
		height_b: float, material: Material, parity := -1, first := 0, length := -1) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	var upright := is_equal_approx(offset_a, offset_b)
	var count := _centers.size() if length < 0 else length
	for segment in range(first, first + count):
		var i := posmod(segment, _centers.size())
		if parity >= 0 and i % 2 != parity:
			continue
		var next := (i + 1) % _centers.size()
		var a := _edge_point(i, offset_a, height_a)
		var b := _edge_point(i, offset_b, height_b)
		var c := _edge_point(next, offset_b, height_b)
		var d := _edge_point(next, offset_a, height_a)
		var normal := (c - a).cross(b - a).normalized()
		var points := [a, b, c, d]
		# Project the strip in metres so tile density is independent of track width or segment count.
		var across_a := height_a if upright else offset_a
		var across_b := height_b if upright else offset_b
		var uvs := [Vector2(across_a, _distance[i]), Vector2(across_b, _distance[i]),
			Vector2(across_b, _distance[i + 1]), Vector2(across_a, _distance[i + 1])]
		for index in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(normal)
			surface.set_uv(uvs[index])
			surface.add_vertex(points[index])
	if material is BaseMaterial3D and material.normal_enabled:
		surface.generate_tangents()
	var mesh := surface.commit()
	_add_mesh(node_name, mesh, Vector3.ZERO)
	return mesh


func _edge_point(index: int, offset: float, height: float) -> Vector3:
	return _centers[index] + _outward[index] * offset + Vector3.UP * height


func _add_start_grid() -> void:
	var chalk := _material(Color("f0ebdc"))
	var ink := _material(Color("232c38"))
	var trim := _material(course.accent)
	var finish := gates[0]
	var tile_width := (half_road - 0.55) / 8.0
	for row in range(2):
		for column in range(16):
			var tile_material := chalk if (row + column) % 2 == 0 else ink
			_place_box("FinishTile", Vector3(tile_width, 0.012, 0.54), finish,
				Vector3((column - 7.5) * tile_width, 0.034, -0.27 + row * 0.54), tile_material)
	for lane in range(2):
		for slot in range(3):
			var index := (_gate_indices[0] + 2 + slot * 2 + lane) % _centers.size()
			var x := (lane * 2.0 - 1.0) * half_road * 0.44
			_place_box("GridLine", Vector3(2.55, 0.012, 0.115), _course_transform(index),
				Vector3(x, 0.034, 0), chalk)
	var post := _wall_offset + 1.1
	for x in [-post, post]:
		_place_box("GantryColumn", Vector3(0.58, 5.8, 0.7), finish, Vector3(x, 2.9, 0), ink)
		_place_box("GantryFoot", Vector3(0.77, 0.8, 0.86), finish, Vector3(x, 0.4, 0), trim)
	_place_box("GantrySign", Vector3(post * 2 + 0.6, 1.42, 0.68), finish, Vector3(0, 5.65, 0), ink)
	_place_box("GantryTrim", Vector3(post * 2 + 0.6, 0.1, 0.7), finish, Vector3(0, 6.31, 0), trim)
	var sign_text := Label3D.new()
	sign_text.name = "CircuitSign"
	sign_text.text = course.banner
	sign_text.transform = finish.translated_local(Vector3(0, 5.66, 0.36))
	sign_text.font_size = 100
	sign_text.pixel_size = 0.01
	sign_text.modulate = Color("fff1da")
	sign_text.outline_size = 0
	add_child(sign_text)


func _add_boost_pads() -> void:
	var blue := _glow(Color("178393"), 0.55)
	var mint := _glow(Color("63fcda"), 0.85)
	for placement in [Vector2i(0, -1), Vector2i(1, 1), Vector2i(3, 0)]:
		var index := posmod(_gate_indices[placement.x] - 5, _centers.size())
		var pad := _course_transform(index).translated_local(Vector3(placement.y * half_road * 0.44, 0, 0))
		boost_pads.append(pad)
		_place_box("BoostPad", Vector3(3.7, 0.018, 3.3), pad, Vector3(0, 0.046, 0), blue)
		for z in [-0.9, 0.0, 0.9]:
			for side in [-1.0, 1.0]:
				var slash := pad * Transform3D(Basis(Vector3.UP, side * 0.35), Vector3(side * 0.7, 0.062, z))
				_place_box("BoostChevron", Vector3(1.5, 0.012, 0.16), slash, Vector3.ZERO, mint)


func _add_landscape() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 311
	var brush := _material(Color("56664f"))
	var mesas := [
		Vector3(-83, 15, -102), Vector3(-52, 21, -116), Vector3(2, 13, -117),
		Vector3(35, 25, -121), Vector3(80, 17, -111), Vector3(115, 18, -67),
		Vector3(112, 23, -3), Vector3(106, 15, 62), Vector3(-102, 24, 43),
		Vector3(-107, 17, -29), Vector3(-35, 17, 111), Vector3(54, 21, 107),
	]
	for mesa in mesas:
		var width := rng.randf_range(8.0, 15.0)
		var base := Vector3(mesa.x, -1.4, mesa.z)
		_add_prop(Art.DESERT_BOULDER, base, Vector3(width, mesa.y * 0.57, width * 0.82),
			rng.randf_range(0, TAU))
		_add_prop(Art.DESERT_BOULDER, base + Vector3(width * 0.64, 0, width * 0.30),
			Vector3(width * 0.84, mesa.y * 0.26, width * 0.72), rng.randf_range(0, TAU))
	for i in range(45):
		var x := rng.randf_range(-31, 31)
		var z := rng.randf_range(-44, 44)
		var size := rng.randf_range(0.24, 1.2)
		if i % 3 == 0:
			_add_column("Scrub", size, size * 0.35, size * 0.72, Vector3(x, size * 0.36, z), brush)
		else:
			_add_prop(Art.DESERT_BOULDER, Vector3(x, -0.08, z), Vector3.ONE * size,
				rng.randf_range(0, TAU))
	for i in range(1, _centers.size(), 7):
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := _edge_point(i, side * (_wall_offset + rng.randf_range(2.4, 5.6)), -0.1)
		var size := rng.randf_range(0.72, 1.9)
		_add_prop(Art.DESERT_BOULDER, p, Vector3(size, size * 0.62, size), rng.randf_range(0, TAU))


func _add_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 416
	var concrete := _material(Color("525c74"))
	var glass := _material(Color("334662"))
	var pavement := _material(Color("858998"))
	var window_warm := _glow(Color("ffbd7e"), 0.8)
	var window_cool := _glow(Color("9bd2ff"), 0.52)
	for side in [-1.0, 1.0]:
		for i in range(2, _centers.size(), 4):
			var frame := _course_transform(i)
			var x: float = side * (_wall_offset + 1.8)
			_place_box("Sidewalk", Vector3(2.5, 0.18, 4.4), frame, Vector3(x, 0.09, 0), pavement)
			_place_box("LampPost", Vector3(0.12, 4.8, 0.12), frame, Vector3(x, 2.4, 0), glass)
			_place_box("StreetLight", Vector3(0.92, 0.16, 0.45), frame,
				Vector3(x - side * 0.28, 4.8, 0), window_warm)
	# A fixed block grid keeps façades aligned and leaves sightlines along the streets.
	for x in range(-92, 93, 17):
		for z in range(-89, 90, 17):
			var base := Vector3(x, 0, z)
			if _near_course(base, 19.0):
				continue
			var tall := rng.randf_range(9.0, 26.0)
			var width := rng.randf_range(7.0, 12.0)
			var depth := rng.randf_range(7.0, 12.0)
			var facade := glass if rng.randf() > 0.45 else concrete
			var street_front := _near_course(base, 27.0)
			_batch_scenery(Vector3(width, tall, depth), base + Vector3.UP * tall * 0.5, facade)
			_batch_scenery(Vector3(width + 0.45, 0.4, depth + 0.45),
				base + Vector3.UP * tall, concrete)
			if street_front:
				_add_city_front(base, width, depth)
			for floor_index in range(1, floori(tall / 3.0)):
				var y := floor_index * 3.0
				var lamps := window_warm if rng.randf() > 0.63 else window_cool
				for side in [-1.0, 1.0]:
					_batch_scenery(Vector3(width * 0.8, 0.53, 0.055),
						base + Vector3(0, y, side * (depth * 0.5 + 0.02)), lamps)
					if not street_front or floor_index >= 2:
						_batch_scenery(Vector3(0.055, 0.53, depth * 0.8),
							base + Vector3(side * (width * 0.5 + 0.02), y, 0), lamps)


func _add_city_front(base: Vector3, width: float, depth: float) -> void:
	for side in [-1.0, 1.0]:
		for floor_index in range(2):
			for column in range(3):
				var p := base + Vector3(side * (width * 0.5 + 0.16), floor_index * 3.0,
					side * (column / 3.0 - 0.5) * depth)
				_add_prop(Art.CITY_FACADE, p, Vector3(depth / 9.0, 1.0, 1.0), side * PI * 0.5)


func _add_tunnel() -> void:
	var concrete := Art.concrete(Color("a7b7bc"))
	var lining := Art.concrete(Color("7c9aa9"))
	var cyan := _glow(Color("71f4ee"), 1.1)
	var overhead := _glow(Color("c5e5ff"), 0.94)
	concrete.cull_mode = BaseMaterial3D.CULL_DISABLED
	lining.cull_mode = BaseMaterial3D.CULL_DISABLED
	cyan.cull_mode = BaseMaterial3D.CULL_DISABLED
	var length := 38
	var first := _gate_indices[0] - 6 - length
	var span := _wall_offset + 0.32
	_roof_first = first
	_roof_segments = length
	_roof_half_width = span
	_add_strip("TunnelCeiling", -span, span, 7.2, 7.2, concrete, -1, first, length)
	for side in [-1.0, 1.0]:
		var x: float = side * span
		_add_strip("TunnelWall", x, x, 0.0, 7.2, concrete, -1, first, length)
		_add_strip("TunnelLining", x - side * 0.03, x - side * 0.03, 0.95, 3.1,
			lining, -1, first, length)
		_add_strip("TunnelGuideLight", x - side * 0.08, x - side * 0.08, 3.0, 3.14,
			cyan, -1, first, length)
	for offset in range(0, length + 1, 4):
		var frame := _course_transform(posmod(first + offset, _centers.size()))
		_place_box("TunnelRib", Vector3(span * 2 + 0.4, 0.30, 0.65), frame,
			Vector3(0, 7.03, 0), lining)
		_place_box("TunnelCeilingLight", Vector3(span * 1.35, 0.06, 0.28), frame,
			Vector3(0, 6.85, 0), overhead)
		for side in [-1.0, 1.0]:
			_place_box("TunnelSupport", Vector3(0.42, 7.2, 0.72), frame,
				Vector3(span * side, 3.6, 0), lining)
		var lamp := OmniLight3D.new()
		lamp.position = frame * Vector3(0, 6.2, 0)
		lamp.light_color = Color("a0f4ff")
		lamp.light_energy = 1.8
		lamp.omni_range = 18.0
		add_child(lamp)
	for i in range(10):
		var frame := _course_transform(posmod(first + i * 4, _centers.size()))
		_add_prop(Art.DESERT_BOULDER, frame * Vector3(0, 7.15, 0),
			Vector3(7.0, 2.8 + i % 3, 6.0), i * 1.29)


func _add_grassland() -> void:
	var pale := _material(Color("ede6cf"))
	var dark := _material(Color("726e5d"))
	var grass := _material(Color("77924f"))
	var flowers := _material(Color("eccc64"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 332
	for point in [Vector3(17, 0, -11), Vector3(7, 0, -35), Vector3(-16, 0, -25),
			Vector3(78, 0, -47), Vector3(91, 0, -66), Vector3(80, 0, -89), Vector3(-87, 0, 18)]:
		_add_column("WindmillTower", 0.9, 0.42, 13.4, point + Vector3.UP * 6.7, pale)
		var rotor := Node3D.new()
		rotor.position = point + Vector3(0, 13.2, 0.65)
		add_child(rotor)
		for blade_index in range(3):
			var angle := TAU * blade_index / 3.0 + rng.randf_range(0, 0.28)
			var blade := _add_box("WindmillBlade", Vector3(0.56, 5.4, 0.16), Vector3.ZERO, pale)
			blade.reparent(rotor, false)
			blade.rotation.z = angle
			blade.position = Vector3.UP.rotated(Vector3.BACK, angle) * 2.72
		var hub := _add_box("WindmillHub", Vector3(0.85, 0.85, 0.48), Vector3.ZERO, dark)
		hub.reparent(rotor, false)
		if not Engine.is_editor_hint():
			var tween := rotor.create_tween().set_loops()
			tween.tween_property(rotor, "rotation:z", TAU, rng.randf_range(4.5, 6.0)).from(0.0)
	for i in range(100):
		var p := Vector3(rng.randf_range(-94, 94), 0, rng.randf_range(-95, 95))
		if not _near_course(p, _wall_offset + 1.0):
			var size := rng.randf_range(0.35, 1.7)
			_add_column("Meadow", size, size * 0.15, size * 0.42,
				p + Vector3.UP * size * 0.21, flowers if i % 7 == 0 else grass)
	for x in [-108.0, -47.0, 3.0, 61.0, 116.0]:
		_add_column("LowHill", 27, 8, 9, Vector3(x, 4.3, -121), grass)
	for i in range(0, _centers.size(), 2):
		for side in [-1.0, 1.0]:
			var p := _edge_point(i, side * (_wall_offset + rng.randf_range(0.55, 2.3)), 0)
			_add_prop(Art.ROADSIDE_GRASS, p, Vector3.ONE * rng.randf_range(0.9, 2.5), rng.randf_range(0, TAU))


func _add_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 754
	for x in range(-96, 97, 12):
		for z in range(-96, 97, 12):
			var p := Vector3(x + rng.randf_range(-3.7, 3.7), 0, z + rng.randf_range(-3.7, 3.7))
			if rng.randf() < 0.24 or _near_course(p, _wall_offset + 9.0):
				continue
			_add_distant_fir(p, rng.randf_range(5.5, 11.0))
	for i in range(2, _centers.size(), 4):
		var side := -1.0 if i % 3 == 0 else 1.0
		var p := _edge_point(i, side * (_wall_offset + rng.randf_range(2.75, 4.7)), 0)
		var tree := Art.ROADSIDE_PINE if i % 5 == 0 else Art.FOREST_FIR
		_add_prop(tree, p, Vector3.ONE * rng.randf_range(3.2, 5.7), rng.randf_range(0, TAU))
		var verge := _edge_point(i, -side * (_wall_offset + 0.75), 0)
		_add_prop(Art.ROADSIDE_GRASS, verge, Vector3.ONE * rng.randf_range(1.0, 2.1), rng.randf_range(0, TAU))


func _add_distant_fir(origin: Vector3, height: float) -> void:
	# The rendered canopy occupies 563 rows, with its base 281 pixels below the texture center.
	var tree := Sprite3D.new()
	tree.texture = Art.FIR_CANOPY
	tree.pixel_size = height / 563.0
	tree.position = origin + Vector3.UP * (281.0 * tree.pixel_size)
	tree.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tree.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	tree.alpha_scissor_threshold = 0.24
	tree.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	tree.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tree)


func _batch_scenery(size: Vector3, position_on_track: Vector3, material: Material) -> void:
	var key := material.get_instance_id()
	if not _scenery_batches.has(key):
		var mesh := BoxMesh.new()
		mesh.material = material
		_scenery_batches[key] = {"mesh": mesh, "poses": []}
	_scenery_batches[key].poses.append(Transform3D(Basis.from_scale(size), position_on_track))


func _flush_scenery() -> void:
	for batch: Dictionary in _scenery_batches.values():
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = batch.mesh
		multimesh.instance_count = batch.poses.size()
		for index in range(multimesh.instance_count):
			multimesh.set_instance_transform(index, batch.poses[index])
		var scenery := MultiMeshInstance3D.new()
		scenery.name = "Scenery"
		scenery.multimesh = multimesh
		add_child(scenery, true)
	_scenery_batches.clear()


func _near_course(point: Vector3, distance: float) -> bool:
	var squared := distance * distance
	for center in _centers:
		if center.distance_squared_to(point) < squared:
			return true
	return false


func has_overhead_cover(point: Vector3) -> bool:
	var flat := Vector2(point.x, point.z)
	var width_squared := _roof_half_width * _roof_half_width
	for segment in range(_roof_first, _roof_first + _roof_segments):
		var start := _centers[posmod(segment, _centers.size())]
		var end := _centers[posmod(segment + 1, _centers.size())]
		var closest := Geometry2D.get_closest_point_to_segment(flat, Vector2(start.x, start.z), Vector2(end.x, end.z))
		if flat.distance_squared_to(closest) <= width_squared:
			return true
	return false


func _add_prop(scene: PackedScene, origin: Vector3, size: Vector3, yaw: float) -> void:
	var prop := scene.instantiate() as Node3D
	prop.transform = Transform3D(Basis(Vector3.UP, yaw).scaled_local(size), origin)
	add_child(prop, true)


func _place_box(node_name: String, size: Vector3, frame: Transform3D, local: Vector3,
		material: Material) -> void:
	var instance := _add_box(node_name, size, frame * local, material)
	instance.basis = frame.basis


func _add_box(node_name: String, size: Vector3, position_on_track: Vector3,
		material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	return _add_mesh(node_name, mesh, position_on_track)


func _add_column(node_name: String, radius: float, top_radius: float, height: float,
		position_on_track: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 6
	mesh.rings = 0
	mesh.material = material
	return _add_mesh(node_name, mesh, position_on_track)


func _add_mesh(node_name: String, mesh: Mesh, position_on_track: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position_on_track
	add_child(instance, true)
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := _material(color)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material
