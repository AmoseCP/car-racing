extends CharacterBody3D

signal impact(speed_toward_surface: float)
signal drift_finished(seconds: float, nitro_gained: float)

const Vehicles := preload("res://racing_prototype/vehicles.gd")
const RaceWeather := preload("res://racing_prototype/race_weather.gd")
const Audio := preload("res://racing_prototype/game_audio.gd")
const DrivingAudio := preload("res://racing_prototype/car_audio.gd")
const Gamepad := preload("res://racing_prototype/gamepad.gd")
const REVERSE_SPEED := 10.0
const COAST_DECELERATION := 5.0
const GRAVITY := 27.0
const DRIFT_MIN_SPEED := 11.0
const DRIFT_SLIP := 0.2
const MAX_SLIP := 0.72
const NITRO_SECONDS := 2.6
const NITRO_GAIN := 0.36
## Steering wheel speed (full lock per second): winds on gently, self-centres faster.
const STEER_IN_RATE := 2.4
const STEER_OUT_RATE := 4.0
const BLINK_PERIOD := 0.72
const INDICATOR_THRESHOLD := 0.3
const INDICATOR_HOLD := 0.7
const INDICATOR_AMBER := Color("ff9a1f")

@export var vehicle_id: StringName = Vehicles.DEFAULT
@export var livery := 0

var speed := 0.0
var speed_multiplier := 1.0
## Last drive input: positive accelerator, negative brake / reverse.
var throttle := 0.0
var rough_surface := false
## Holds the car on the grid while still letting the driver rev the engine.
var controls_locked := false
## Nitro tank, 0..1. Filled by drifting, burnt with the nitro button.
var nitro := 0.0
var nitro_active := false
## Angle between the direction of travel and the car's heading (radians).
var slip := 0.0
var drifting := false
## Eased steering input, -1 (right lock) to 1 (left lock).
var steer_angle := 0.0
## Active turn signal: -1 left, 1 right, 0 off; lit is the current blink phase.
var indicator := 0
var indicator_lit := false
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
var _audio: DrivingAudio
var _rumble_clock := 0.0
var _paints: Array[StandardMaterial3D] = []
var _factory_colors: Array[Color] = []
var _drift_time := 0.0
var _indicator_clock := 0.0
var _indicator_hold := 0.0
var _indicator_lamps := {-1: [], 1: []}
var _drift_gain := 0.0

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
	for wheel_name in ["Wheel_FL", "Wheel_FR", "Wheel_ML", "Wheel_MR", "Wheel_RL", "Wheel_RR"]:
		var wheel := _body.get_node_or_null(wheel_name) as Node3D
		if wheel:
			_wheels.append(wheel)
	for wheel in _wheels:
		_wheel_rest.append(wheel.basis)
	_tune_body_materials()
	apply_livery(livery)
	_create_headlights()
	_create_indicators()
	_audio = DrivingAudio.new()
	_audio.name = "DrivingAudio"
	add_child(_audio)


func _physics_process(delta: float) -> void:
	var drive := Input.get_axis(&"race_brake", &"race_accelerate")
	var steer := Input.get_axis(&"race_right", &"race_left")
	var manual := Input.is_action_pressed(&"race_left") or Input.is_action_pressed(&"race_right")
	if motion_steering and not manual:
		steer = motion_steering.steering
	var handbrake := Input.is_action_pressed(&"race_handbrake")
	var wants_nitro := Input.is_action_pressed(&"race_nitro")
	# Foot brake (Space / LB): slows to a stop and holds, never selects reverse.
	var footbrake := Input.get_action_strength(&"race_footbrake")
	throttle = drive
	if controls_locked:
		drive = 0.0
		steer = 0.0
		handbrake = false
		wants_nitro = false
	steer = _ease_steering(steer, delta)
	_update_indicators(delta)
	boost_time = move_toward(boost_time, 0.0, delta)
	_update_nitro(wants_nitro and drive >= 0.0 and footbrake <= 0.0, delta)
	if nitro_active:
		drive = 1.0
	if footbrake > 0.0:
		drive = 0.0
		throttle = -footbrake
	if _brake_lights:
		var running_lights := 0.48 if headlights_on else 0.22
		var braking := (drive < -0.1 and speed > 0.1) or (
			(handbrake or footbrake > 0.0) and absf(speed) > 0.1)
		_brake_lights.emission_energy_multiplier = 2.0 if braking else running_lights
	_update_speed(drive, delta)
	if footbrake > 0.0:
		var brakes: float = _profile.braking * (weather.brake_factor if weather else 1.0)
		speed = move_toward(speed, 0.0, brakes * footbrake * delta)
	if handbrake:
		speed = move_toward(speed, 0.0, (4.5 if drifting else 13.0) * delta)
	var steering_grip := clampf(absf(speed) / 7.0, 0.0, 1.0)
	var steering: Vector2 = _profile.steering
	var high_speed_grip := lerpf(steering.x, steering.y, clampf(absf(speed) / current_top_speed(), 0.0, 1.0))
	var road_grip := weather.steering_factor if weather else 1.0
	var turn := steer * signf(speed) * steering_grip * high_speed_grip * road_grip
	var sliding := speed > DRIFT_MIN_SPEED and (handbrake or drifting)
	if sliding:
		turn *= 1.55
	rotate_y(turn * delta)
	_update_slip(turn * delta, handbrake, drive, road_grip, delta)

	var travel := (-global_basis.z).rotated(Vector3.UP, slip)
	_fall_speed = 0.0 if is_on_floor() else _fall_speed - GRAVITY * delta
	velocity = travel * speed + Vector3.UP * _fall_speed
	var incoming := velocity
	move_and_slide()
	if is_on_wall():
		# Keep motion along the rail and shed the speed directed into it.
		var factor := weather.speed_factor if weather else 1.0
		speed = clampf(velocity.dot(travel), -REVERSE_SPEED * factor, _profile.boost_speed * factor)
		slip *= 0.5
		var closing_speed := 0.0
		for index in range(get_slide_collision_count()):
			var contact := get_slide_collision(index)
			var normal := contact.get_normal()
			if absf(normal.y) > 0.45:
				continue
			var other_velocity := contact.get_collider_velocity()
			var other := contact.get_collider()
			if other != null and other.has_method("traffic_velocity"):
				other_velocity = other.traffic_velocity()
			closing_speed = maxf(closing_speed, -(incoming - other_velocity).dot(normal))
		if closing_speed > 0.0:
			impact.emit(closing_speed)
			var hit := clampf(closing_speed / 30.0, 0.0, 1.0)
			if closing_speed > 2.0:
				Gamepad.rumble(0.3 + 0.7 * hit, 0.15 + 0.85 * hit, 0.12 + 0.28 * hit)
	_update_wheels(steer, delta)
	_update_rumble(delta)
	if is_physics_processing() and not get_tree().paused:
		_audio.advance(delta, throttle, steer)


func _update_rumble(delta: float) -> void:
	# Light continuous feedback for drifting, nitro and rough ground.
	_rumble_clock -= delta
	if _rumble_clock > 0.0:
		return
	var weak := 0.0
	var strong := 0.0
	if drifting:
		weak = 0.22
	if nitro_active:
		weak = maxf(weak, 0.24)
		strong = 0.12
	if rough_surface and absf(speed) > 3.0:
		weak = maxf(weak, 0.32)
		strong = maxf(strong, 0.14)
	if weak > 0.0:
		Gamepad.rumble(weak, strong, 0.14)
		_rumble_clock = 0.1


func _update_nitro(wants_nitro: bool, delta: float) -> void:
	var burning := wants_nitro and nitro > 0.0 and speed > 2.0
	if burning and not nitro_active:
		Audio.play_from(self, &"boost", -2.0, 1.15)
		Gamepad.rumble(0.25, 0.55, 0.3)
	nitro_active = burning
	if nitro_active:
		nitro = maxf(0.0, nitro - delta / NITRO_SECONDS)
		boost_time = maxf(boost_time, 0.12)


func _update_slip(yaw_step: float, handbrake: bool, drive: float, road_grip: float, delta: float) -> void:
	# The direction of travel lags behind the body; grip pulls it back in line.
	slip = clampf(slip - yaw_step, -MAX_SLIP, MAX_SLIP)
	var grip := 16.0
	if speed < DRIFT_MIN_SPEED * 0.6:
		grip = 24.0
	elif handbrake:
		grip = 1.3
	elif drifting and drive > 0.0:
		grip = 2.4
	elif drifting:
		grip = 5.0
	slip *= exp(-grip * clampf(road_grip, 0.55, 1.0) * delta)
	speed -= absf(slip) * 3.0 * delta if speed > 0.0 else 0.0
	var was_drifting := drifting
	drifting = absf(slip) > DRIFT_SLIP and speed > DRIFT_MIN_SPEED * 0.8
	if drifting:
		var gain := NITRO_GAIN * delta * clampf(absf(slip) / 0.45, 0.0, 1.0) * clampf(speed / 30.0, 0.0, 1.0)
		nitro = minf(1.0, nitro + gain)
		_drift_time += delta
		_drift_gain += gain
	elif was_drifting:
		if _drift_time >= 0.5:
			drift_finished.emit(_drift_time, _drift_gain)
		_drift_time = 0.0
		_drift_gain = 0.0


func _tune_body_materials() -> void:
	for node in _vehicle_model.find_children("*", "MeshInstance3D", true, false):
		_tune_mesh_materials(node as MeshInstance3D)


func _tune_mesh_materials(part: MeshInstance3D) -> void:
	if part.mesh == null:
		return
	for index in range(part.mesh.get_surface_count()):
		var original := part.get_active_material(index) as StandardMaterial3D
		if original == null:
			continue
		if original.resource_name.begins_with("Paint_"):
			var paint: StandardMaterial3D = original.duplicate()
			paint.clearcoat_enabled = true
			paint.clearcoat = 0.68
			paint.clearcoat_roughness = 0.24
			part.set_surface_override_material(index, paint)
			_paints.append(paint)
			_factory_colors.append(original.albedo_color)
		elif original.resource_name == "Lamp_Red":
			if _brake_lights == null:
				_brake_lights = original.duplicate()
			_brake_lights.emission_enabled = true
			_brake_lights.emission = Color("ff1e10")
			_brake_lights.emission_energy_multiplier = 0.22
			part.set_surface_override_material(index, _brake_lights)
		elif original.resource_name == "Lamp":
			if _front_lamps == null:
				_front_lamps = original.duplicate()
			_front_lamps.emission_enabled = true
			_front_lamps.emission = Color("e2efff")
			_front_lamps.emission_energy_multiplier = 0.0
			part.set_surface_override_material(index, _front_lamps)


func _create_headlights() -> void:
	var dimensions: Vector3 = _profile.collision_size
	for side in [-1.0, 1.0]:
		var light := SpotLight3D.new()
		light.name = "HeadlightLeft" if side < 0.0 else "HeadlightRight"
		light.position = Vector3(side * dimensions.x * 0.36, _profile.get("headlight_height", 0.58), -dimensions.z * 0.5 + 0.05)
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


func apply_livery(index: int) -> void:
	livery = clampi(index, 0, Vehicles.LIVERIES.size() - 1)
	for i in range(_paints.size()):
		Vehicles.paint(_paints[i], vehicle_id, _factory_colors[i], livery)


func _create_indicators() -> void:
	var dimensions: Vector3 = _profile.collision_size
	var amber := StandardMaterial3D.new()
	amber.albedo_color = INDICATOR_AMBER
	amber.emission_enabled = true
	amber.emission = INDICATOR_AMBER
	amber.emission_energy_multiplier = 4.0
	var lens := BoxMesh.new()
	lens.size = Vector3(0.2, 0.09, 0.07)
	lens.material = amber
	for side in [-1, 1]:
		for corner in [Vector3(side * dimensions.x * 0.43, 0.6, -dimensions.z * 0.5 + 0.04),
				Vector3(side * dimensions.x * 0.43, 0.74, dimensions.z * 0.5 - 0.04)]:
			var lamp := MeshInstance3D.new()
			lamp.name = "TurnSignal"
			lamp.mesh = lens
			lamp.position = corner
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lamp.visible = false
			add_child(lamp)
			_indicator_lamps[side].append(lamp)


func _ease_steering(target: float, delta: float) -> float:
	# A steering wheel takes time to wind on and self-centres a little faster.
	var winding_on := is_zero_approx(steer_angle) or (
		signf(target) == signf(steer_angle) and absf(target) > absf(steer_angle))
	var response: float = _profile.get("steering_response", 1.0)
	steer_angle = move_toward(steer_angle, target, (STEER_IN_RATE if winding_on else STEER_OUT_RATE) * response * delta)
	return steer_angle


func _update_indicators(delta: float) -> void:
	# Signal while the wheel is turned, and briefly after it straightens.
	var side := 0
	if absf(steer_angle) > INDICATOR_THRESHOLD and absf(speed) > 1.0:
		side = -1 if steer_angle > 0.0 else 1
		_indicator_hold = INDICATOR_HOLD
	elif indicator != 0 and _indicator_hold > 0.0:
		_indicator_hold -= delta
		side = indicator
	if side != indicator:
		indicator = side
		_indicator_clock = 0.0
		_set_indicator_lit(side != 0)
		return
	if indicator == 0:
		return
	_indicator_clock += delta
	var lit := fmod(_indicator_clock, BLINK_PERIOD) < BLINK_PERIOD * 0.5
	if lit != indicator_lit:
		_set_indicator_lit(lit)


func _set_indicator_lit(lit: bool) -> void:
	indicator_lit = lit
	for side: int in _indicator_lamps:
		for lamp: MeshInstance3D in _indicator_lamps[side]:
			lamp.visible = lit and side == indicator
	if indicator != 0:
		Audio.play_from(self, &"indicator", 0.0, 1.0 if lit else 0.8)


func set_headlights(active: bool) -> void:
	if headlights_on == active:
		return
	headlights_on = active
	for light in _headlights:
		light.visible = active
	if _front_lamps:
		_front_lamps.emission_energy_multiplier = 1.8 if active else 0.0


func toggle_headlights() -> void:
	set_headlights(not headlights_on)
	Audio.play_from(self, &"headlights", 0.0, 1.0 if headlights_on else 0.85)


func stop_audio() -> void:
	_audio.silence()


func _update_wheels(steer: float, delta: float) -> void:
	_wheel_angle = fposmod(_wheel_angle + speed * delta / _profile.tyre_radius, TAU)
	var roll := Basis(Vector3.RIGHT, _wheel_angle)
	var turn := Basis(Vector3.UP, steer * 0.34)
	for index in range(_wheels.size()):
		var axle := turn if index < 2 else Basis.IDENTITY
		_wheels[index].basis = axle * roll * _wheel_rest[index]


func _update_speed(drive: float, delta: float) -> void:
	var speed_limit := speed_multiplier * (weather.speed_factor if weather else 1.0)
	var acceleration: float = _profile.acceleration * (weather.acceleration_factor if weather else 1.0)
	var pull := Vehicles.power_curve(absf(speed) / _profile.top_speed)
	if is_zero_approx(drive):
		speed = move_toward(speed, 0.0, COAST_DECELERATION * delta)
	elif drive * speed < 0.0:
		var brakes: float = _profile.braking * (weather.brake_factor if weather else 1.0)
		speed = move_toward(speed, 0.0, brakes * absf(drive) * delta)
	elif drive > 0.0:
		var limit: float = _profile.boost_speed if boost_time > 0.0 else _profile.top_speed
		var boost_acceleration := 1.45 if boost_time > 0.0 else 1.0
		speed = move_toward(speed, limit * speed_limit * drive, acceleration * pull * boost_acceleration * delta)
	else:
		speed = move_toward(speed, REVERSE_SPEED * speed_limit * drive, acceleration * 0.55 * delta)


## Normalised engine speed shared by the engine sound and the tachometer:
## 0.63 at idle, about 1.62 at top speed under full load, higher while boosting.
func engine_rev() -> float:
	var reverse := speed < -0.6
	var load := maxf(0.0, -throttle if reverse else throttle)
	var ratio := clampf(absf(speed) / maxf(1.0, current_top_speed()), 0.0, 1.15)
	return 0.63 + 0.82 * ratio + 0.17 * load


func current_top_speed() -> float:
	return _profile.top_speed * speed_multiplier * (weather.speed_factor if weather else 1.0)


func front_length() -> float:
	return _profile.collision_size.z * 0.5


func front_position() -> Vector3:
	return position - basis.z * front_length()


func set_spawn(pose: Transform3D) -> void:
	_start_transform = pose
	respawn()


func activate_boost() -> void:
	var factor := weather.speed_factor if weather else 1.0
	boost_time = _profile.boost_seconds
	speed = minf(speed + _profile.boost_push * factor, _profile.boost_speed * factor)
	Audio.play_from(self, &"boost")
	Gamepad.rumble(0.3, 0.6, 0.35)


func respawn() -> void:
	global_transform = _start_transform
	velocity = Vector3.ZERO
	speed = 0.0
	boost_time = 0.0
	throttle = 0.0
	nitro = 0.0
	nitro_active = false
	slip = 0.0
	drifting = false
	_drift_time = 0.0
	_drift_gain = 0.0
	steer_angle = 0.0
	indicator = 0
	_indicator_hold = 0.0
	_set_indicator_lit(false)
	_fall_speed = 0.0
	rough_surface = false
	_wheel_angle = 0.0
	stop_audio()
	_update_wheels(0.0, 0.0)
	reset_physics_interpolation()
