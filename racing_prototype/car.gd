extends CharacterBody3D

const Vehicles := preload("res://racing_prototype/vehicles.gd")
const RaceWeather := preload("res://racing_prototype/race_weather.gd")
const REVERSE_SPEED := 10.0
const COAST_DECELERATION := 5.0
const GRAVITY := 27.0

@export var vehicle_id: StringName = Vehicles.DEFAULT

var speed := 0.0
var boost_time := 0.0
var headlights_on := false
var motion_steering: Node
var weather: RaceWeather
var _fall_speed := 0.0
var _start_transform: Transform3D
var _wheel_angle := 0.0
var _wheel_rest: Array[Basis] = []
var _brake_lights: StandardMaterial3D
var _front_lamps: StandardMaterial3D
var _headlights: Array[SpotLight3D] = []
var _profile: Dictionary
var _body: MeshInstance3D
var _wheels: Array[Node3D] = []

@onready var _vehicle_model: Node3D = $CarModel
@onready var _collider: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_start_transform = global_transform
	if not Vehicles.DATA.has(vehicle_id):
		vehicle_id = Vehicles.DEFAULT
	_profile = Vehicles.DATA[vehicle_id]
	if vehicle_id != Vehicles.DEFAULT:
		_vehicle_model.free()
		_vehicle_model = Vehicles.instantiate_model(vehicle_id)
		add_child(_vehicle_model)
		var shape := BoxShape3D.new()
		shape.size = _profile.collision_size
		_collider.shape = shape
		_collider.position.y = shape.size.y * 0.5
	_body = _vehicle_model.get_child(0).get_node("Body")
	for wheel_name in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		_wheels.append(_body.get_node(wheel_name))
	for wheel in _wheels:
		_wheel_rest.append(wheel.basis)
	_tune_body_materials()
	_create_headlights()


func _physics_process(delta: float) -> void:
	var drive := Input.get_axis(&"race_brake", &"race_accelerate")
	var steer := Input.get_axis(&"race_right", &"race_left")
	var manual := Input.is_action_pressed(&"race_left") or Input.is_action_pressed(&"race_right")
	if motion_steering and not manual:
		steer = motion_steering.steering
	if _brake_lights:
		var running_lights := 0.48 if headlights_on else 0.22
		_brake_lights.emission_energy_multiplier = 2.0 if drive < -0.1 and speed > 0.1 else running_lights
	boost_time = move_toward(boost_time, 0.0, delta)
	_update_speed(drive, delta)
	var steering_grip := clampf(absf(speed) / 7.0, 0.0, 1.0)
	var steering: Vector2 = _profile.steering
	var high_speed_grip := lerpf(steering.x, steering.y, clampf(absf(speed) / current_top_speed(), 0.0, 1.0))
	var road_grip := weather.steering_factor if weather else 1.0
	rotate_y(steer * signf(speed) * steering_grip * high_speed_grip * road_grip * delta)

	var forward := -global_basis.z
	_fall_speed = 0.0 if is_on_floor() else _fall_speed - GRAVITY * delta
	velocity = forward * speed + Vector3.UP * _fall_speed
	move_and_slide()
	if is_on_wall():
		# Keep motion along the rail and shed the speed directed into it.
		var factor := weather.speed_factor if weather else 1.0
		speed = clampf(velocity.dot(forward), -REVERSE_SPEED * factor, _profile.boost_speed * factor)
	_update_wheels(steer, delta)


func _tune_body_materials() -> void:
	for index in range(_body.mesh.get_surface_count()):
		var original := _body.mesh.surface_get_material(index) as StandardMaterial3D
		if original == null:
			continue
		if original.resource_name.begins_with("Paint_"):
			var paint: StandardMaterial3D = original.duplicate()
			paint.clearcoat_enabled = true
			paint.clearcoat = 0.68
			paint.clearcoat_roughness = 0.24
			_body.set_surface_override_material(index, paint)
		elif original.resource_name == "Lamp_Red":
			_brake_lights = original.duplicate()
			_brake_lights.emission_enabled = true
			_brake_lights.emission = Color("ff1e10")
			_brake_lights.emission_energy_multiplier = 0.22
			_body.set_surface_override_material(index, _brake_lights)
		elif original.resource_name == "Lamp":
			_front_lamps = original.duplicate()
			_front_lamps.emission_enabled = true
			_front_lamps.emission = Color("e2efff")
			_front_lamps.emission_energy_multiplier = 0.0
			_body.set_surface_override_material(index, _front_lamps)


func _create_headlights() -> void:
	var dimensions: Vector3 = _profile.collision_size
	for side in [-1.0, 1.0]:
		var light := SpotLight3D.new()
		light.name = "HeadlightLeft" if side < 0.0 else "HeadlightRight"
		light.position = Vector3(side * dimensions.x * 0.36, 0.58, -dimensions.z * 0.5 + 0.05)
		light.rotation_degrees = Vector3(-8.0, -side * 5.0, 0)
		light.light_color = Color("e5efff")
		light.light_energy = 28.0
		light.spot_range = 63.0
		light.spot_angle = 26.0
		light.spot_angle_attenuation = 0.52
		light.spot_attenuation = 0.65
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_headlights.append(light)


func set_headlights(active: bool) -> void:
	if headlights_on == active:
		return
	headlights_on = active
	for light in _headlights:
		light.visible = active
	if _front_lamps:
		_front_lamps.emission_energy_multiplier = 1.8 if active else 0.0


func _update_wheels(steer: float, delta: float) -> void:
	_wheel_angle = fposmod(_wheel_angle + speed * delta / _profile.tyre_radius, TAU)
	var roll := Basis(Vector3.RIGHT, _wheel_angle)
	var turn := Basis(Vector3.UP, steer * 0.34)
	for index in range(_wheels.size()):
		var axle := turn if index < 2 else Basis.IDENTITY
		_wheels[index].basis = axle * roll * _wheel_rest[index]


func _update_speed(drive: float, delta: float) -> void:
	var speed_limit := weather.speed_factor if weather else 1.0
	var acceleration: float = _profile.acceleration * (weather.acceleration_factor if weather else 1.0)
	if is_zero_approx(drive):
		speed = move_toward(speed, 0.0, COAST_DECELERATION * delta)
	elif drive * speed < 0.0:
		var brakes: float = _profile.braking * (weather.brake_factor if weather else 1.0)
		speed = move_toward(speed, 0.0, brakes * absf(drive) * delta)
	elif drive > 0.0:
		var limit: float = _profile.boost_speed if boost_time > 0.0 else _profile.top_speed
		var boost_acceleration := 1.45 if boost_time > 0.0 else 1.0
		speed = move_toward(speed, limit * speed_limit * drive, acceleration * boost_acceleration * delta)
	else:
		speed = move_toward(speed, REVERSE_SPEED * speed_limit * drive, acceleration * 0.55 * delta)


func current_top_speed() -> float:
	return _profile.top_speed * (weather.speed_factor if weather else 1.0)


func set_spawn(pose: Transform3D) -> void:
	_start_transform = pose
	respawn()


func activate_boost() -> void:
	var factor := weather.speed_factor if weather else 1.0
	boost_time = _profile.boost_seconds
	speed = minf(speed + _profile.boost_push * factor, _profile.boost_speed * factor)


func respawn() -> void:
	global_transform = _start_transform
	velocity = Vector3.ZERO
	speed = 0.0
	boost_time = 0.0
	_fall_speed = 0.0
	_wheel_angle = 0.0
	_update_wheels(0.0, 0.0)
	reset_physics_interpolation()
