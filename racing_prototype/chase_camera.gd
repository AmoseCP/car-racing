extends Camera3D

const Vehicles := preload("res://racing_prototype/vehicles.gd")
const CHASE_OFFSET := Vector3(0.0, 3.25, 7.9)
const RAISED_OFFSET := Vector3(0.0, 5.2, 5.2)
const LOOK_OFFSET := Vector3(0.0, 0.95, -6.1)
const CAMERA_ANCHOR := Vector3(0.0, 1.75, 0.0)
const FAR_CHASE_OFFSET := Vector3(0.0, 4.3, 11.2)
const VIEW_NAMES := ["近距追尾", "远距追尾", "引擎盖"]
const HOOD_VIEW := 2
const SPEED_FOV := 9.0
const BOOST_FOV := 7.0

## Selected camera view, kept across races and saved by the garage.
static var view := 0

var _base_fov := 65.0
var _shake := 0.0
var _time := 0.0

var _heading := 0.0
var _raise := 0.0
var _distance := 0.0
var _probe := PhysicsShapeQueryParameters3D.new()
var _camera_profile: Dictionary = {}
var _anchor := CAMERA_ANCHOR
var _raised := RAISED_OFFSET
var _look := LOOK_OFFSET

@onready var _car: CharacterBody3D = $"../Car"


func _ready() -> void:
	_camera_profile = Vehicles.DATA[_car.vehicle_id].get("camera", {})
	_anchor = _camera_profile.get("anchor", CAMERA_ANCHOR)
	_raised = _camera_profile.get("raised", RAISED_OFFSET)
	_look = _camera_profile.get("look", LOOK_OFFSET)
	var lens := SphereShape3D.new()
	lens.radius = 0.48
	_probe.shape = lens
	_probe.collision_mask = 3
	_probe.exclude = [_car.get_rid()]
	_base_fov = fov
	_car.impact.connect(_on_impact)
	snap_to_car()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"race_camera"):
		view = (view + 1) % VIEW_NAMES.size()
		snap_to_car()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_update_feel(delta)
	if view == HOOD_VIEW:
		_place_on_hood()
		return
	_heading = lerp_angle(_heading, _car.global_rotation.y, 1.0 - exp(-6.0 * delta))
	var anchor := _car.global_position + _anchor
	var normal_arm := (_chase_offset() - _anchor).rotated(Vector3.UP, _heading)
	var safe := _clearance(anchor, normal_arm)
	var arm := normal_arm
	if safe < normal_arm.length() - 1.0 or _raise > 0.0:
		_raise = 1.0 if safe < normal_arm.length() - 1.0 else move_toward(_raise, 0.0, delta * 2.6)
		var height := _chase_offset().lerp(_raised, _raise)
		arm = (height - _anchor).rotated(Vector3.UP, _heading)
		safe = _clearance(anchor, arm)
	_distance = minf(safe, lerpf(_distance, safe, 1.0 - exp(-7.0 * delta)))
	global_position = anchor + arm.normalized() * _distance
	_aim_at_track()


func snap_to_car() -> void:
	_heading = _car.global_rotation.y
	_raise = 0.0
	_distance = (_chase_offset() - _anchor).length()
	if view == HOOD_VIEW:
		_place_on_hood()
	else:
		global_position = _car.global_position + _chase_offset().rotated(Vector3.UP, _heading)
		_aim_at_track()
	reset_physics_interpolation()


func _chase_offset() -> Vector3:
	return _camera_profile.get("far", FAR_CHASE_OFFSET) if view == 1 else _camera_profile.get("chase", CHASE_OFFSET)


func _place_on_hood() -> void:
	var size: Vector3 = _car.get_node("CollisionShape3D").shape.size
	var mount := Vector3(0.0, size.y * 0.86, -size.z * 0.5 + 0.35)
	if size.y > 2.5:
		mount = Vector3(0.0, size.y * 0.75, -size.z * 0.5 - 0.12)
	global_transform = _car.global_transform.translated_local(mount)
	rotate_object_local(Vector3.RIGHT, -0.035)


func _update_feel(delta: float) -> void:
	# Widen the lens with speed and boost, and shake it on hits.
	_time += delta
	var top: float = maxf(1.0, _car.current_top_speed())
	var rush := smoothstep(0.35, 1.05, absf(_car.speed) / top)
	var boosting := 1.0 if _car.boost_time > 0.0 else 0.0
	var base := _base_fov + (5.0 if view == HOOD_VIEW else 0.0)
	fov = lerpf(fov, base + SPEED_FOV * rush + BOOST_FOV * boosting, 1.0 - exp(-4.0 * delta))
	var rumble := 0.025 * boosting * rush + (0.018 if _car.drifting else 0.0)
	_shake = maxf(move_toward(_shake, 0.0, delta * 1.6), rumble)
	h_offset = _shake * (sin(_time * 47.0) + 0.6 * sin(_time * 31.0 + 1.3))
	v_offset = _shake * (cos(_time * 53.0) + 0.5 * sin(_time * 23.0 + 0.4))


func _on_impact(closing_speed: float) -> void:
	_shake = maxf(_shake, clampf(closing_speed / 30.0, 0.0, 1.0) * 0.32)


func _clearance(anchor: Vector3, arm: Vector3) -> float:
	_probe.transform = Transform3D(Basis.IDENTITY, anchor)
	_probe.motion = arm
	var fractions := get_world_3d().direct_space_state.cast_motion(_probe)
	var length := arm.length()
	if not fractions.is_empty() and fractions[0] < 1.0:
		return maxf(0.1, length * fractions[0] - 0.12)
	return length


func _aim_at_track() -> void:
	look_at(_car.global_position + _look.rotated(Vector3.UP, _heading), Vector3.UP)
