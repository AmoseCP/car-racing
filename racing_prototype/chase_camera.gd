extends Camera3D

const CHASE_OFFSET := Vector3(0.0, 3.25, 7.9)
const LOOK_OFFSET := Vector3(0.0, 0.95, -6.1)

var _heading := 0.0

@onready var _car: Node3D = $"../Car"


func _ready() -> void:
	snap_to_car()


func _process(delta: float) -> void:
	_heading = lerp_angle(_heading, _car.global_rotation.y, 1.0 - exp(-6.0 * delta))
	var desired := _car.global_position + CHASE_OFFSET.rotated(Vector3.UP, _heading)
	global_position = global_position.lerp(desired, 1.0 - exp(-9.0 * delta))
	_aim_at_track()


func snap_to_car() -> void:
	_heading = _car.global_rotation.y
	global_position = _car.global_position + CHASE_OFFSET.rotated(Vector3.UP, _heading)
	_aim_at_track()
	reset_physics_interpolation()


func _aim_at_track() -> void:
	look_at(_car.global_position + LOOK_OFFSET.rotated(Vector3.UP, _heading), Vector3.UP)
