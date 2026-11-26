extends Node3D

enum Kind { SIGNAL, STOP, CROSSWALK }
enum Phase { GREEN, AMBER, RED }
const STOP_OFFSET := 4.2
const SIGNAL_PERIOD := 33.0
const PEDESTRIAN_SECONDS := 10.8
const PEDESTRIAN_LEAD := 1.4

var kind: Kind
var distance: float
var phase := Phase.GREEN
var pedestrians_present := false
var crossing_reserved := false
var _clock_offset: float
var _width: float
var _lamps: Array[StandardMaterial3D] = []
var _people: Array[Node3D] = []
var _limbs: Array[Array] = []


func configure(type: Kind, road_distance: float, half_width: float, offset: float) -> void:
	kind = type
	distance = road_distance
	_clock_offset = offset
	_width = half_width
	var paint := _material(Color("f1ead8"), 0.13)
	var pole := _material(Color("53636b"))
	var span := _width - 0.52
	for lane_mark in range(ceili(2.0 * span / 0.86)):
		var x := -span + 0.32 + lane_mark * 0.86
		if x < span - 0.18:
			_box(self, "ZebraStripe", Vector3(0.59, 0.008, 3.6), Vector3(x, 0.042, 0.0), paint)
	for direction in [1, -1]:
		var approach := Node3D.new()
		approach.rotation.y = 0.0 if direction == 1 else PI
		add_child(approach)
		_box(approach, "StopLine", Vector3(span - 0.17, 0.010, 0.31),
			Vector3((span + 0.15) * 0.5, 0.044, STOP_OFFSET), paint)
		var sidewalk := _material(Color("a0a19d"))
		_box(approach, "CrossingLanding", Vector3(2.45, 0.085, 3.6),
			Vector3(_width + 1.25, 0.045, 0), sidewalk)
		match kind:
			Kind.SIGNAL: _build_signal(approach, pole)
			Kind.STOP: _build_sign(approach, pole, true)
			Kind.CROSSWALK: _build_sign(approach, pole, false)
	if kind != Kind.STOP:
		_make_person(Color("437e8f"), Color("986448"))
		_make_person(Color("bf743f"), Color("d5aa85"))
	advance(0.0)


func advance(seconds: float) -> void:
	if kind == Kind.STOP:
		return
	var period := SIGNAL_PERIOD if kind == Kind.SIGNAL else 31.0
	var cycle := fposmod(seconds + _clock_offset, period)
	var start := 19.0 if kind == Kind.SIGNAL else 10.0
	if kind == Kind.SIGNAL:
		var next := Phase.GREEN if cycle < 14.0 else (Phase.AMBER if cycle < 17.0 else Phase.RED)
		if phase != next or _lamps[phase].emission_energy_multiplier < 1.0:
			phase = next
			for index in range(_lamps.size()):
				_lamps[index].emission_energy_multiplier = 3.0 if index == phase else 0.0
				_lamps[index].albedo_color = _lamps[index].emission if index == phase else Color("202720")
	pedestrians_present = cycle >= start and cycle < start + PEDESTRIAN_SECONDS
	crossing_reserved = cycle >= start - PEDESTRIAN_LEAD and cycle < start + PEDESTRIAN_SECONDS
	for index in range(_people.size()):
		var walker := _people[index]
		var fraction := (cycle - start - index * 0.58) / (PEDESTRIAN_SECONDS - 0.6)
		walker.visible = fraction >= 0.0 and fraction < 1.0
		if walker.visible:
			var side := 1.0 if int((seconds + _clock_offset) / period) % 2 == 0 else -1.0
			walker.position.x = lerpf(-_width - 1.3, _width + 1.3, fraction) * side
			walker.position.z = -0.65 + index * 1.15
			walker.rotation.y = side * -PI * 0.5
			var stride := sin(cycle * 10.1) * 0.42
			for limb in range(_limbs[index].size()):
				_limbs[index][limb].rotation.x = stride if limb % 2 == 0 else -stride


func _build_signal(approach: Node3D, pole: Material) -> void:
	var x := _width + 1.15
	_box(approach, "SignalPost", Vector3(0.14, 4.6, 0.14), Vector3(x, 2.30, -0.7), pole)
	_box(approach, "SignalArm", Vector3(x - 1.25, 0.14, 0.16), Vector3((x + 1.25) * 0.5, 4.48, -0.7), pole)
	var shell := _material(Color("1f282e"))
	if _lamps.is_empty():
		for color in [Color("2fff68"), Color("ffbe35"), Color("ff3034")]:
			_lamps.append(_material(color, 0.0))
	for offset in [_width * 0.26, _width * 0.72]:
		_box(approach, "SignalHousing", Vector3(0.46, 1.18, 0.28), Vector3(offset, 4.52, -0.52), shell)
		for index in range(3):
			var bulb := CylinderMesh.new()
			bulb.top_radius = 0.155
			bulb.bottom_radius = 0.155
			bulb.height = 0.09
			bulb.radial_segments = 16
			bulb.material = _lamps[index]
			var lamp := _mesh(approach, "SignalLens", bulb, Vector3(offset, 4.14 + index * 0.37, -0.34))
			lamp.rotation.x = PI * 0.5
			_box(approach, "SignalHood", Vector3(0.35, 0.073, 0.26),
				Vector3(offset, 4.31 + index * 0.37, -0.24), shell)


func _build_sign(approach: Node3D, pole: Material, stop: bool) -> void:
	var x := _width + 0.83
	var sign_at := Vector3(x, 2.65, STOP_OFFSET - 0.25)
	_box(approach, "SignPost", Vector3(0.08, 2.62, 0.09), Vector3(x, 1.31, sign_at.z), pole)
	var trim := _material(Color("f4e9d7"), 0.25)
	var face := _material(Color("c82e28") if stop else Color("18659b"), 0.42)
	if stop:
		for index in range(2):
			var plate := CylinderMesh.new()
			plate.radial_segments = 8
			plate.top_radius = 0.60 - index * 0.055
			plate.bottom_radius = plate.top_radius
			plate.height = 0.045
			plate.material = trim if index == 0 else face
			var disk := _mesh(approach, "StopSign", plate, sign_at + Vector3.BACK * index * 0.025)
			disk.basis = Basis(Vector3.BACK, PI / 8.0) * Basis(Vector3.RIGHT, PI / 2.0)
	else:
		_box(approach, "CrosswalkSign", Vector3(1.01, 0.94, 0.095), sign_at, trim)
		_box(approach, "CrosswalkSignFace", Vector3(0.89, 0.82, 0.075), sign_at + Vector3.BACK * 0.03, face)
	var caption := Label3D.new()
	caption.text = "STOP" if stop else "XING"
	caption.font_size = 72
	caption.pixel_size = 0.0037
	caption.outline_size = 0
	caption.position = sign_at + Vector3.BACK * 0.081
	approach.add_child(caption)


func _make_person(shirt: Color, skin: Color) -> void:
	var walker := Node3D.new()
	walker.visible = false
	add_child(walker)
	_people.append(walker)
	var clothing := _material(shirt, 0.035)
	var pants := _material(Color("333e4a"))
	var head := SphereMesh.new()
	head.radius = 0.121
	head.height = 0.244
	head.radial_segments = 12
	head.rings = 6
	head.material = _material(skin, 0.05)
	_mesh(walker, "Head", head, Vector3(0, 1.62, 0))
	_box(walker, "Torso", Vector3(0.37, 0.48, 0.23), Vector3(0, 1.27, 0), clothing)
	var joints: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.101, 1.01, 0)
		walker.add_child(leg)
		_box(leg, "Leg", Vector3(0.15, 0.85, 0.16), Vector3(0, -0.45, 0), pants)
		_box(leg, "Shoe", Vector3(0.16, 0.12, 0.27), Vector3(0, -0.94, -0.055), pants)
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.245, 1.46, 0.0)
		walker.add_child(arm)
		_box(arm, "Arm", Vector3(0.12, 0.49, 0.12), Vector3(0, -0.22, 0), clothing)
		joints.append(leg)
		joints.append(arm)
	_limbs.append([joints[0], joints[2], joints[3], joints[1]])


func _material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission = color
	material.emission_enabled = glow > 0.0
	material.emission_energy_multiplier = glow
	if glow == 0.0 and color.s > 0.65:
		material.emission_enabled = true
	return material


func _box(parent: Node3D, node_name: String, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	_mesh(parent, node_name, mesh, at)


func _mesh(parent: Node3D, node_name: String, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = at
	parent.add_child(instance, true)
	return instance
