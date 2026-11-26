extends AnimatableBody3D
## A race opponent: a kinematic car that the rivals director drives along the road.

const Vehicles := preload("res://racing_prototype/vehicles.gd")
const Ui := preload("res://racing_prototype/ui_skin.gd")
const LAYER := 2

var display_name := ""
var color := Color.WHITE
var skill := 1.0
var progress := 0.0
var covered := 0.0
var lateral := 0.0
var target_lateral := 0.0
var speed := 0.0
var boost_time := 0.0
var finished := false
var finish_time := INF
var direction := 1
var half_length := 2.0
# Bookkeeping read and written by Traffic.rule_gap().
var cleared_stop := -1
var waiting_at := -1
var wait_time := 0.0
var _wheels: Array[Node3D] = []
var _rest: Array[Basis] = []
var _roll := 0.0
var _tyre_radius := 0.3
var _brake_lights: StandardMaterial3D


func configure(vehicle_id: StringName, livery: int, title: String, tint: Color, pace: float) -> void:
	display_name = title
	color = tint
	skill = pace
	collision_layer = LAYER
	collision_mask = 0
	sync_to_physics = false
	var profile: Dictionary = Vehicles.DATA[vehicle_id]
	half_length = profile.collision_size.z * 0.5
	_tyre_radius = profile.tyre_radius
	var model := Vehicles.instantiate_model(vehicle_id)
	Vehicles.paint_model(model, vehicle_id, livery)
	add_child(model)
	var body := model.get_child(0).get_node("Body") as MeshInstance3D
	for wheel_name in ["Wheel_FL", "Wheel_FR", "Wheel_ML", "Wheel_MR", "Wheel_RL", "Wheel_RR"]:
		var wheel := body.get_node_or_null(wheel_name) as Node3D
		if wheel:
			_wheels.append(wheel)
			_rest.append(wheel.basis)
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null:
			continue
		for index in range(part.mesh.get_surface_count()):
			var original := part.get_active_material(index) as StandardMaterial3D
			if original != null and original.resource_name == "Lamp_Red":
				if _brake_lights == null:
					_brake_lights = original.duplicate()
					_brake_lights.emission_enabled = true
					_brake_lights.emission = Color("ff1e10")
				part.set_surface_override_material(index, _brake_lights)
	var bounds := BoxShape3D.new()
	bounds.size = profile.collision_size
	var collider := CollisionShape3D.new()
	collider.shape = bounds
	collider.position.y = bounds.size.y * 0.5
	add_child(collider)
	var tag := Label3D.new()
	tag.text = title
	tag.font = Ui.UI_FONT
	tag.font_size = 30
	tag.pixel_size = 0.0011
	tag.fixed_size = true
	tag.outline_size = 8
	tag.modulate = tint
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = profile.collision_size.y + 0.9
	add_child(tag)


func place(pose: Transform3D, movement: float, braking: bool) -> void:
	transform = pose
	_roll = fposmod(_roll + movement / _tyre_radius, TAU)
	var spin := Basis(Vector3.RIGHT, _roll)
	for index in range(_wheels.size()):
		_wheels[index].basis = spin * _rest[index]
	if _brake_lights:
		_brake_lights.emission_energy_multiplier = 2.0 if braking else 0.25


func traffic_velocity() -> Vector3:
	return -global_basis.z * speed
