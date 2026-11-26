extends AnimatableBody3D

const MODELS := [
	preload("res://racing_prototype/art/traffic/sedan.glb"),
	preload("res://racing_prototype/art/traffic/suv.glb"),
	preload("res://racing_prototype/art/traffic/taxi.glb"),
	preload("res://racing_prototype/art/traffic/delivery.glb"),
	preload("res://racing_prototype/art/traffic/truck.glb"),
]
const SIZES := [
	Vector3(2.10, 1.82, 3.57), Vector3(2.16, 1.87, 3.89),
	Vector3(2.10, 2.10, 3.85), Vector3(2.18, 2.39, 4.71), Vector3(2.21, 1.91, 4.34),
]
const LAYER := 2

var lane: int
var direction: int
var progress: float
var speed: float
var cruise_speed: float
## True while following a slower car or stopping for a signal, sign or crossing.
var held_up := false
var half_length: float
var cleared_stop: int = -1
var waiting_at: int = -1
var wait_time := 0.0
var _wheels: Array[Node3D] = []
var _front: StandardMaterial3D
var _rear: StandardMaterial3D
var _driven := 0.0


func configure(model_id: int, lane_index: int, desired_speed: float) -> void:
	collision_layer = LAYER
	collision_mask = 0
	sync_to_physics = false
	lane = lane_index
	direction = 1 if lane >= 0 else -1
	cruise_speed = desired_speed
	speed = cruise_speed
	var profile: Vector3 = SIZES[model_id]
	half_length = profile.z * 0.5
	var model := MODELS[model_id].instantiate() as Node3D
	model.rotation.y = PI
	model.scale = Vector3.ONE * (profile.x / 1.5)
	var turning_wheels := ["wheel-front-left", "wheel-front-right", "wheel-back-left", "wheel-back-right"]
	for wheel_name in turning_wheels:
		var wheel := model.get_node_or_null(wheel_name) as Node3D
		if wheel:
			_wheels.append(wheel)
	add_child(model)
	var bounds := BoxShape3D.new()
	bounds.size = Vector3(profile.x, profile.y * 0.86, profile.z)
	var collider := CollisionShape3D.new()
	collider.shape = bounds
	collider.position.y = bounds.size.y * 0.5
	add_child(collider)
	_front = _lamp_material(Color("fff0d8"))
	_rear = _lamp_material(Color("ee341c"))
	for side in [-1.0, 1.0]:
		_add_lamp(Vector3(side * profile.x * 0.33, 0.64, -half_length + 0.06), _front)
		_add_lamp(Vector3(side * profile.x * 0.34, 0.68, half_length - 0.06), _rear)


func display(pose: Transform3D, movement: float, braking: bool, dark: bool) -> void:
	transform = pose
	_driven = fposmod(_driven + movement, TAU * 0.39)
	for wheel in _wheels:
		wheel.rotation.x = _driven / 0.39
	_front.emission_energy_multiplier = 2.4 if dark else 0.12
	_rear.emission_energy_multiplier = 2.1 if braking else (0.7 if dark else 0.12)


func traffic_velocity() -> Vector3:
	return -global_basis.z * speed


func _lamp_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	return material


func _add_lamp(at: Vector3, material: Material) -> void:
	var bulb := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.24, 0.13, 0.10)
	mesh.material = material
	bulb.mesh = mesh
	bulb.position = at
	add_child(bulb)
