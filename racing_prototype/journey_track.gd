extends Node3D

const Art := preload("res://racing_prototype/track_art.gd")
const Courses := preload("res://racing_prototype/courses.gd")
const Weather := preload("res://racing_prototype/race_weather.gd")
const ControlSite := preload("res://racing_prototype/road_control.gd")
const CHUNK := 180.0
const STEP := 5.0
const REBASE_AFTER := 1080.0
const HALF_ROAD := 8.65
const SHOULDER := HALF_ROAD + 1.5
const ROUTE := [
	&"grassland", &"grassland", &"forest", &"forest", &"forest",
	&"city", &"city", &"city", &"tunnel", &"tunnel", &"desert", &"desert", &"desert",
]
const SECTION := [0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]
const SPEED_LIMITS := {&"grassland": 90, &"forest": 70, &"city": 50, &"tunnel": 70, &"desert": 100}
## Drive-through fuel lanes: in the right lane of every fourth chunk (none inside tunnels).
const STATION_EVERY := 4
const STATION_FROM := 60.0
const STATION_TO := 115.0

var origin := 0.0
var weather_materials: Array[ShaderMaterial] = []
var sites: Array[ControlSite] = []

var _chunks: Dictionary[int, Node3D] = {}
var _ground: Dictionary[StringName, ShaderMaterial] = {}
var _asset_meshes := {}
var _road: ShaderMaterial
var _white: StandardMaterial3D
var _yellow: StandardMaterial3D
var _rail: StandardMaterial3D
var _concrete: StandardMaterial3D
var _shell: StandardMaterial3D
var _lamp: StandardMaterial3D
var _windmill: StandardMaterial3D
var _windows: StandardMaterial3D
var _buildings: StandardMaterial3D
var _sign_ring: CylinderMesh
var _sign_face: CylinderMesh
var _sign_back: CylinderMesh


func _ready() -> void:
	_road = Weather.surface_material(Art.road(), 0.39)
	weather_materials.append(_road)
	for id in Courses.ORDER:
		_ground[id] = Weather.surface_material(Art.ground(id, 1.0), 0.98)
		weather_materials.append(_ground[id])
	_white = _material("f1eee0", 0.08)
	_yellow = _material("eab34b", 0.10)
	_rail = _material("697780")
	_rail.metallic = 0.65
	_rail.cull_mode = BaseMaterial3D.CULL_DISABLED
	_concrete = Art.concrete(Color("aab3bc"))
	_concrete.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shell = _material("274149")
	_shell.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lamp = _material("a6eef3", 1.4)
	_windmill = _material("d9e3e5")
	_windows = _material("c6d9ef", 0.14)
	_buildings = Art.concrete(Color("657384"))
	_sign_ring = _sign_disc(0.86, _material("d82424", 0.24))
	_sign_face = _sign_disc(0.70, _material("fdf9ed", 0.27))
	_sign_back = _sign_disc(0.86, _material("78828a"))
	reset()


func reset() -> void:
	if origin != 0.0:
		var shift := origin
		origin = 0.0
		for chunk in _chunks.values():
			chunk.position.z -= shift
	stream(0.0)


func biome(progress: float) -> StringName:
	return ROUTE[posmod(floori(maxf(0.0, progress) / CHUNK), ROUTE.size())]


func speed_limit(progress: float) -> int:
	return SPEED_LIMITS[biome(progress)]


func sections_reached(progress: float) -> int:
	var index := floori(maxf(progress, 0.0) / CHUNK)
	return floori(float(index) / ROUTE.size()) * 5 + SECTION[index % ROUTE.size()] + 1


func road_x(progress: float) -> float:
	return 16.0 * sin(progress * 0.0038) + 10.5 * sin(progress * 0.0073) + 5.0 * sin(progress * 0.0121)


func road_pose(progress: float, offset: float = 0.0, direction: int = 1) -> Transform3D:
	var slope := (road_x(progress + 0.5) - road_x(progress - 0.5))
	var right := Vector3(1.0, 0.0, slope).normalized() * direction
	return Transform3D(Basis(right, Vector3.UP, Vector3(-right.z, 0, right.x)),
		Vector3(road_x(progress) + offset, 0.0, origin - progress))


func road_location(point: Vector3) -> Vector2:
	var progress := origin - point.z
	return Vector2(progress, point.x - road_x(progress))


func lane_offset(lane: int) -> float:
	return (lane + 0.5) * 4.0


func has_station(index: int) -> bool:
	return index >= 2 and index % STATION_EVERY == 2 and ROUTE[index % ROUTE.size()] != &"tunnel"


func in_station(location: Vector2) -> bool:
	var index := floori(location.x / CHUNK)
	var local := location.x - index * CHUNK
	return has_station(index) and local >= STATION_FROM and local <= STATION_TO and (
		location.y > 3.6 and location.y < HALF_ROAD)


## Distance along the road to the start of the next fuel lane (0 while inside one).
func next_station(progress: float) -> float:
	var index := floori(maxf(progress, 0.0) / CHUNK)
	for next in range(index, index + 16):
		if not has_station(next):
			continue
		var entry := next * CHUNK + STATION_FROM
		if progress <= next * CHUNK + STATION_TO:
			return maxf(0.0, entry - progress)
	return INF


func has_overhead_cover(point: Vector3) -> bool:
	var location := road_location(point)
	var stage := fposmod(location.x, CHUNK * ROUTE.size()) - 8.0 * CHUNK
	return location.x >= 0.0 and stage >= 30.0 and stage < 325.0 and absf(location.y) < SHOULDER + 0.4


func stream(progress: float) -> float:
	var index := floori(maxf(progress, 0.0) / CHUNK)
	var shift := 0.0
	if absf(progress - origin) >= REBASE_AFTER:
		var new_origin := index * CHUNK
		shift = new_origin - origin
		origin = new_origin
		for chunk in _chunks.values():
			chunk.position.z += shift
	for previous in _chunks.keys():
		if previous < index - 1 or previous > index + 3:
			var chunk := _chunks[previous]
			for site in sites.duplicate():
				if site.get_parent() == chunk:
					sites.erase(site)
			remove_child(chunk)
			chunk.queue_free()
			_chunks.erase(previous)
	for next in range(maxi(index - 1, -1), index + 4):
		if not _chunks.has(next):
			_add_chunk(next)
	return shift


func _add_chunk(index: int) -> void:
	var start := index * CHUNK
	var id := biome(start)
	var chunk := Node3D.new()
	chunk.name = "Road_%d" % index
	chunk.position.z = origin - start
	add_child(chunk)
	_chunks[index] = chunk
	_strip(chunk, start, -155.0, 155.0, 0.0, 0.0, _ground[id])
	_strip(chunk, start, -HALF_ROAD, HALF_ROAD, 0.025, 0.025, _road)
	_strip(chunk, start, -0.18, -0.066, 0.035, 0.035, _yellow)
	_strip(chunk, start, 0.066, 0.18, 0.035, 0.035, _yellow)
	for side: float in [-1.0, 1.0]:
		var edge := side * (HALF_ROAD - 0.35)
		_strip(chunk, start, edge - 0.055, edge + 0.055, 0.035, 0.035, _white)
		var lane := side * 4.0
		_strip(chunk, start, lane - 0.055, lane + 0.055, 0.036, 0.036, _white, 0.0, CHUNK, true)
		if id != &"city":
			_barrier(chunk, start, side * SHOULDER)
		else:
			var inset := side * (HALF_ROAD + 0.35)
			var outside := side * (HALF_ROAD + 3.65)
			_strip(chunk, start, minf(inset, outside), maxf(inset, outside), 0.12, 0.12, _concrete)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42671 + index * 25117
	match id:
		&"grassland": _grassland(chunk, start, rng)
		&"forest": _forest(chunk, start, rng)
		&"city": _city(chunk, start, index, rng)
		&"tunnel": _tunnel(chunk, start, posmod(index, ROUTE.size()) == 8)
		&"desert": _desert(chunk, start, rng)
	if index == 0 or (index > 0 and biome(start - 1.0) != id):
		_region_sign(chunk, start, id)
	if has_station(index):
		_fuel_station(chunk, start)
	var sign_offset := 29.0 if index == 0 else 0.0
	_speed_limit_sign(chunk, start, sign_offset, 1)
	_speed_limit_sign(chunk, start, sign_offset, -1)


func _fuel_station(chunk: Node3D, start: float) -> void:
	var lane_paint := _material("1b8f86", 0.35)
	var stripe := _material("7ff5dc", 0.9)
	var canopy := _material("e9eef0")
	var trim := _material("12b8a0", 0.6)
	_strip(chunk, start, 4.15, HALF_ROAD - 0.5, 0.031, 0.031, lane_paint, STATION_FROM, STATION_TO)
	_strip(chunk, start, 4.15, 4.35, 0.034, 0.034, stripe, STATION_FROM, STATION_TO, true)
	var middle := (STATION_FROM + STATION_TO) * 0.5
	var length := STATION_TO - STATION_FROM - 10.0
	var x := road_x(start + middle)
	_box(chunk, Vector3(12.5, 0.45, length), Vector3(x + SHOULDER + 0.6, 5.4, -middle), canopy)
	_box(chunk, Vector3(12.6, 0.16, length + 0.1), Vector3(x + SHOULDER + 0.6, 5.12, -middle), trim)
	for z: float in [middle - length * 0.4, middle, middle + length * 0.4]:
		var post_x := road_x(start + z) + SHOULDER + 5.8
		_box(chunk, Vector3(0.36, 5.2, 0.36), Vector3(post_x, 2.6, -z), _rail)
		var pump_x := road_x(start + z) + SHOULDER + 1.6
		_box(chunk, Vector3(0.8, 1.6, 0.55), Vector3(pump_x, 0.8, -z), trim)
		_box(chunk, Vector3(0.82, 0.4, 0.57), Vector3(pump_x, 1.75, -z), canopy)
	var banner := Label3D.new()
	banner.text = "加油站  FUEL"
	banner.font = preload("res://racing_prototype/fonts/CarRacingUI.ttf")
	banner.font_size = 96
	banner.pixel_size = 0.012
	banner.modulate = Color("0f6f64")
	banner.outline_size = 0
	banner.position = Vector3(x + SHOULDER + 0.6, 5.42, -STATION_FROM - 4.7)
	chunk.add_child(banner)


func _strip(chunk: Node3D, start: float, left: float, right: float, low: float, high: float,
		material: Material, from: float = 0.0, to: float = CHUNK, dashed := false) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	for segment in range(roundi(from / STEP), roundi(to / STEP)):
		if dashed and segment % 2 != 0:
			continue
		var z := segment * STEP
		var x1 := road_x(start + z)
		var x2 := road_x(start + z + STEP)
		var a := Vector3(x1 + left, low, -z)
		var b := Vector3(x1 + right, high, -z)
		var c := Vector3(x2 + right, high, -z - STEP)
		var d := Vector3(x2 + left, low, -z - STEP)
		var vertices := [a, b, c, d]
		var normal := (b - a).cross(c - a).normalized()
		for vertex_index in [0, 2, 1, 0, 3, 2]:
			var vertex: Vector3 = vertices[vertex_index]
			surface.set_normal(normal)
			surface.set_uv(Vector2(vertex.x if left != right else vertex.y, start - vertex.z))
			surface.add_vertex(vertex)
	if material is ShaderMaterial or (material is StandardMaterial3D and material.normal_enabled):
		surface.generate_tangents()
	var mesh := surface.commit()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(instance)
	return mesh


func _barrier(chunk: Node3D, start: float, x: float) -> void:
	var mesh := _strip(chunk, start, x, x, 0.0, 0.82, _rail)
	_strip(chunk, start, x - 0.12, x + 0.12, 0.82, 0.82, _rail)
	var body := StaticBody3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	chunk.add_child(body)


func _grassland(chunk: Node3D, start: float, rng: RandomNumberGenerator) -> void:
	var placement: Array[Transform3D] = []
	for i in range(48):
		var scale_factor := rng.randf_range(0.8, 2.1)
		placement.append(_scatter(start, rng, 11.4, 33.0, Vector3.ONE * scale_factor))
	_add_asset_batch(chunk, Art.ROADSIDE_GRASS, placement)
	var hills: Array[Transform3D] = []
	var meadow := SphereMesh.new()
	meadow.radial_segments = 24
	meadow.rings = 8
	meadow.material = _ground[&"grassland"]
	for side: float in [-1.0, 1.0]:
		for i in range(3):
			var along := 27.0 + i * 57.0
			var width := rng.randf_range(44.0, 88.0)
			var p := Vector3(road_x(start + along) + side * (width * 0.5 + rng.randf_range(23.0, 49.0)), -1.8, -along)
			hills.append(Transform3D(Basis.from_scale(Vector3(width, rng.randf_range(11.0, 24.0), 64.0)), p))
	_batch(chunk, meadow, hills)
	for i in range(2):
		var along := 40.0 + i * 91.0
		var side := -1.0 if i == 0 else 1.0
		var p := Vector3(road_x(start + along) + side * rng.randf_range(27.0, 62.0), 0.0, -along)
		var tower := CylinderMesh.new()
		tower.top_radius = 0.36
		tower.bottom_radius = 0.69
		tower.height = 12.7
		tower.material = _windmill
		_mesh(chunk, tower, p + Vector3.UP * 6.35)
		var rotor := Node3D.new()
		rotor.position = p + Vector3(0, 12.5, 0.38)
		chunk.add_child(rotor)
		for blade in range(3):
			var angle := TAU * blade / 3.0
			var panel := _box(rotor, Vector3(0.53, 4.65, 0.11), Vector3.UP.rotated(Vector3.BACK, angle) * 2.45, _windmill)
			panel.rotation.z = angle
		var spin := rotor.create_tween().set_loops()
		spin.tween_property(rotor, "rotation:z", TAU, rng.randf_range(4.8, 7.0)).from(0.0)


func _forest(chunk: Node3D, start: float, rng: RandomNumberGenerator) -> void:
	var trees: Array[Transform3D] = []
	var fern: Array[Transform3D] = []
	for i in range(94):
		trees.append(_scatter(start, rng, 13.2, 110.0, Vector3.ONE * rng.randf_range(3.5, 9.7)))
	for i in range(45):
		fern.append(_scatter(start, rng, 11.3, 20.1, Vector3.ONE * rng.randf_range(0.8, 2.3)))
	_add_asset_batch(chunk, Art.FOREST_FIR, trees)
	_add_asset_batch(chunk, Art.ROADSIDE_GRASS, fern)


func _city(chunk: Node3D, start: float, index: int, rng: RandomNumberGenerator) -> void:
	var towers: Array[Transform3D] = []
	var windows: Array[Transform3D] = []
	var fronts: Array[Transform3D] = []
	for side: float in [-1.0, 1.0]:
		for slot in range(8):
			var offset := 9.0 + slot * 23.0
			if absf(offset - 84.0) < 12.0:
				continue
			var h := rng.randf_range(9.8, 27.0)
			var x := road_x(start + offset) + side * rng.randf_range(20.5, 28.0)
			var width := rng.randf_range(9.0, 13.0)
			var depth := rng.randf_range(13.0, 19.0)
			towers.append(Transform3D(Basis.from_scale(Vector3(width, h, depth)), Vector3(x, h * 0.5, -offset)))
			var face := x - side * (width * 0.5 + 0.08)
			fronts.append(Transform3D(Basis(Vector3.UP, -side * PI * 0.5).scaled_local(Vector3(depth * 0.105, 1.2, 1)),
				Vector3(face, 0.03, -offset)))
			for floor_index in range(2, floori(h / 2.9)):
				for column in range(4):
					var p := Vector3(face, floor_index * 2.9, -offset + (column - 1.5) * depth * 0.21)
					windows.append(Transform3D(Basis.from_scale(Vector3(0.10, 0.82, depth * 0.15)), p))
	_add_box_batch(chunk, _buildings, towers)
	_add_box_batch(chunk, _windows, windows)
	_add_asset_batch(chunk, Art.CITY_FACADE, fronts)
	var kind := ControlSite.Kind.STOP if posmod(index, ROUTE.size()) == 6 else ControlSite.Kind.SIGNAL
	var site := ControlSite.new()
	var position_on_road := start + 84.0
	var pose := road_pose(position_on_road)
	pose.origin.z = -84.0
	site.transform = pose
	chunk.add_child(site)
	site.configure(kind, position_on_road, HALF_ROAD, 7.0)
	sites.append(site)


func _tunnel(chunk: Node3D, start: float, first: bool) -> void:
	var from := 30.0 if first else 0.0
	var to := CHUNK if first else 145.0
	var span := SHOULDER + 0.5
	_strip(chunk, start, -span, span, 6.4, 6.4, _concrete, from, to)
	for side: float in [-1.0, 1.0]:
		_strip(chunk, start, side * span, side * span, 0.0, 6.4, _concrete, from, to)
		_strip(chunk, start, side * (span - 0.06), side * (span - 0.06), 1.50, 3.05, _shell, from, to)
	for z in range(roundi(from) + 8, roundi(to), 24):
		var p := Vector3(road_x(start + z), 6.1, -z)
		_box(chunk, Vector3(13.5, 0.11, 0.24), p, _lamp)
		var light := OmniLight3D.new()
		light.position = p + Vector3.DOWN * 0.62
		light.light_color = Color("a0e1ff")
		light.light_energy = 2.9
		light.omni_range = 21.0
		chunk.add_child(light)
	var boulders: Array[Transform3D] = []
	for z in range(12, 174, 19):
		for side: float in [-1.0, 1.0]:
			var p := Vector3(road_x(start + z) + side * 22.0, -0.75, -z)
			boulders.append(Transform3D(Basis(Vector3.UP, z * 0.3).scaled_local(Vector3(17, 11, 19)), p))
	_add_asset_batch(chunk, Art.DESERT_BOULDER, boulders)


func _desert(chunk: Node3D, start: float, rng: RandomNumberGenerator) -> void:
	var boulders: Array[Transform3D] = []
	for i in range(26):
		var size_factor := rng.randf_range(0.9, 3.8)
		boulders.append(_scatter(start, rng, 12.3, 39.0, Vector3.ONE * size_factor))
	for i in range(17):
		var width := rng.randf_range(11.0, 26.0)
		boulders.append(_scatter(start, rng, 36.5, 113.0, Vector3(width, width * 0.78, width)))
	_add_asset_batch(chunk, Art.DESERT_BOULDER, boulders)


func _scatter(start: float, rng: RandomNumberGenerator, low: float, high: float, scale: Vector3) -> Transform3D:
	var z := rng.randf_range(1.0, CHUNK - 1.0)
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var p := Vector3(road_x(start + z) + side * rng.randf_range(low, high), 0, -z)
	return Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled_local(scale), p)


func _region_sign(chunk: Node3D, start: float, id: StringName) -> void:
	var accent := _material("1f3b47", 0.14)
	var x := road_x(start + 16.0) + SHOULDER + 1.95
	_box(chunk, Vector3(0.13, 2.45, 0.13), Vector3(x, 1.22, -16), _rail)
	_box(chunk, Vector3(3.65, 1.0, 0.13), Vector3(x, 2.42, -16), accent)
	var sign_label := Label3D.new()
	sign_label.text = Courses.DATA[id].banner
	sign_label.font_size = 69
	sign_label.pixel_size = 0.004
	sign_label.outline_size = 2
	sign_label.position = Vector3(x, 2.42, -15.91)
	chunk.add_child(sign_label)


func _speed_limit_sign(chunk: Node3D, start: float, offset: float, direction: int) -> void:
	var progress := start + offset
	var limit := speed_limit(progress + direction * 0.1)
	var sign := Node3D.new()
	sign.name = "SpeedLimit_%d_%s" % [limit, "Forward" if direction > 0 else "Oncoming"]
	var pose := road_pose(progress, direction * (SHOULDER + 0.62), direction)
	pose.origin.z = -offset
	sign.transform = pose
	chunk.add_child(sign)
	_box(sign, Vector3(0.10, 2.55, 0.10), Vector3(0, 1.275, 0), _rail)
	var outer := _mesh(sign, _sign_ring, Vector3(0, 2.77, 0))
	var inner := _mesh(sign, _sign_face, Vector3(0, 2.77, 0.045))
	var back := _mesh(sign, _sign_back, Vector3(0, 2.77, -0.015))
	outer.rotation.x = PI * 0.5
	inner.rotation.x = PI * 0.5
	back.rotation.x = PI * 0.5
	var caption := Label3D.new()
	caption.text = str(limit)
	caption.font_size = 100
	caption.pixel_size = 0.0079
	caption.modulate = Color("15171d")
	caption.outline_size = 0
	caption.position = Vector3(0, 2.77, 0.086)
	sign.add_child(caption)


func _sign_disc(radius: float, material: Material) -> CylinderMesh:
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.06
	disc.radial_segments = 36
	disc.material = material
	return disc


func _add_asset_batch(chunk: Node3D, scene: PackedScene, placements: Array[Transform3D]) -> void:
	if not _asset_meshes.has(scene):
		var asset := scene.instantiate()
		var parts: Array = []
		_collect_meshes(asset, Transform3D.IDENTITY, parts)
		_asset_meshes[scene] = parts
		asset.free()
	for part in _asset_meshes[scene]:
		var poses: Array[Transform3D] = []
		for placement in placements:
			poses.append(placement * part.transform)
		_batch(chunk, part.mesh, poses)


func _collect_meshes(node: Node, parent: Transform3D, parts: Array) -> void:
	var pose := parent
	if node is Node3D:
		pose = parent * node.transform
	if node is MeshInstance3D and node.mesh != null:
		parts.append({"mesh": node.mesh, "transform": pose})
	for child in node.get_children():
		_collect_meshes(child, pose, parts)


func _add_box_batch(chunk: Node3D, material: Material, poses: Array[Transform3D]) -> void:
	var mesh := BoxMesh.new()
	mesh.material = material
	_batch(chunk, mesh, poses)


func _batch(chunk: Node3D, mesh: Mesh, poses: Array[Transform3D]) -> void:
	var data := MultiMesh.new()
	data.transform_format = MultiMesh.TRANSFORM_3D
	data.mesh = mesh
	data.instance_count = poses.size()
	for i in range(poses.size()):
		data.set_instance_transform(i, poses[i])
	var multi := MultiMeshInstance3D.new()
	multi.multimesh = data
	chunk.add_child(multi)


func _material(html: String, glow: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(html)
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = glow
	return material


func _box(parent: Node3D, dimensions: Vector3, point: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = material
	return _mesh(parent, mesh, point)


func _mesh(parent: Node3D, mesh: Mesh, point: Vector3) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = point
	parent.add_child(item)
	return item
