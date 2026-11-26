extends SceneTree
## Rebuilds res://racing_prototype/truck_car.tscn from Kenney Car Kit's
## "delivery-flat" (CC0): a cab-over flatbed with a low tarp load, so the cab
## stays visible from the chase camera. Run from the project root:
##   godot --headless -s racing_prototype/art/truck/build_truck_scene.gd
##
## The meshes are turned 180 degrees in their vertex data (Kenney faces +Z,
## the game faces -Z) instead of rotating a node, so wheel roll keeps the same
## sign as the other vehicles.

const SOURCE := "res://racing_prototype/art/truck/delivery-flat.glb"
const TEXTURE := "res://racing_prototype/art/truck/Textures/colormap.png"
const PLATE := "res://racing_prototype/license_plate.tscn"
const OUTPUT := "res://racing_prototype/truck_car.tscn"
## Kenney units to metres: 1.5 wide -> 3.15 m, 3.3 long -> 6.9 m.
const SCALE := 2.1
## Second rear axle, behind Kenney's single one (body-local, after turning).
const TANDEM_OFFSET := 0.62


func _initialize() -> void:
	var kit: Node3D = load(SOURCE).instantiate()
	var paint := StandardMaterial3D.new()
	paint.resource_name = "Colormap"
	paint.albedo_texture = load(TEXTURE)
	paint.roughness = 0.7

	var root := Node3D.new()
	root.name = "CarModel"
	var truck := Node3D.new()
	truck.name = "Truck"
	truck.scale = Vector3.ONE * SCALE
	_add(root, truck)

	var source_body: MeshInstance3D = kit.get_node("body")
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _turned(source_body.mesh, paint)
	body.position = _turn(source_body.position)
	_add(truck, body)

	var wheels := {
		"Wheel_FL": "wheel-front-left", "Wheel_FR": "wheel-front-right",
		"Wheel_ML": "wheel-back-left", "Wheel_MR": "wheel-back-right",
		"Wheel_RL": "wheel-back-left", "Wheel_RR": "wheel-back-right",
	}
	for wheel_name: String in wheels:
		var source: MeshInstance3D = kit.get_node(wheels[wheel_name])
		var pivot := Node3D.new()
		pivot.name = wheel_name
		pivot.position = _turn(source.position) - body.position
		if wheel_name.begins_with("Wheel_R"):
			pivot.position.z += TANDEM_OFFSET
		_add(body, pivot)
		var tire := MeshInstance3D.new()
		tire.name = "Tire"
		tire.mesh = _turned(source.mesh, paint)
		_add(pivot, tire)

	# Low tarp load on the chassis: stays well below the cab roof (1.2).
	_box(body, "Load", Vector3(1.30, 0.40, 1.96), Vector3(0.0, 0.55, 0.60), _material("Paint_Cargo", Color("2f6f9e"), 0.85))
	var strap := _material("Paint_Strap", Color("f0a030"), 0.6)
	for z in [0.12, 0.60, 1.08]:
		_box(body, "Strap", Vector3(1.34, 0.42, 0.07), Vector3(0.0, 0.55, z), strap)
	var tail := _material("Lamp_Red", Color("b01515"), 0.4)
	for x in [-0.56, 0.56]:
		_box(body, "TailLamp", Vector3(0.22, 0.10, 0.04), Vector3(x, 0.24, 1.645), tail)
	var lamp := _material("Lamp", Color("e9eef4"), 0.3)
	for x in [-0.60, 0.60]:
		_box(body, "HeadLamp", Vector3(0.16, 0.10, 0.03), Vector3(x, 0.50, -1.635), lamp)

	var plate: PackedScene = load(PLATE)
	var rear: Node3D = plate.instantiate()
	rear.name = "RearPlate"
	rear.position = Vector3(0.0, 0.66, 3.50)
	_add(root, rear)
	var front: Node3D = plate.instantiate()
	front.name = "FrontPlate"
	front.position = Vector3(0.0, 0.62, -3.55)
	front.rotation_degrees = Vector3(0, 180, 0)
	_add(root, front)

	var scene := PackedScene.new()
	scene.pack(root)
	var error := ResourceSaver.save(scene, OUTPUT)
	print("saved %s: %s" % [OUTPUT, error_string(error)])
	kit.free()
	root.free()
	quit(error)


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = parent if parent.owner == null else parent.owner


func _turn(point: Vector3) -> Vector3:
	return Vector3(-point.x, point.y, -point.z)


func _turned(mesh: Mesh, material: Material) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(vertices.size()):
			vertices[i] = _turn(vertices[i])
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in range(normals.size()):
				normals[i] = _turn(normals[i])
			arrays[Mesh.ARRAY_NORMAL] = normals
		if arrays[Mesh.ARRAY_TANGENT] != null:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for i in range(0, tangents.size(), 4):
				tangents[i] = -tangents[i]
				tangents[i + 2] = -tangents[i + 2]
			arrays[Mesh.ARRAY_TANGENT] = tangents
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, material)
	return result


func _box(parent: Node3D, part_name: String, size: Vector3, at: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = box
	part.position = at
	_add(parent, part)


func _material(title: String, color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = title
	material.albedo_color = color
	material.roughness = roughness
	return material
