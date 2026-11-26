extends SubViewportContainer

const Vehicles := preload("res://racing_prototype/vehicles.gd")

var _model: Node3D
@onready var _turntable: Node3D = $Viewport/Turntable


func _ready() -> void:
	$Viewport/Camera3D.look_at(Vector3(0, 0.53, 0))
	if Engine.max_fps < 60:
		$Viewport.msaa_3d = Viewport.MSAA_DISABLED


func show_vehicle(id: StringName, livery := 0) -> void:
	if is_instance_valid(_model):
		_turntable.remove_child(_model)
		_model.queue_free()
	_turntable.rotation.y = 0.0
	_model = Vehicles.instantiate_model(id)
	Vehicles.paint_model(_model, id, livery)
	_turntable.add_child(_model)
	var dimensions: Vector3 = Vehicles.DATA[id].collision_size
	var scale_factor := maxf(1.0, dimensions.z / 4.4)
	$Viewport/Camera3D.size = 4.05 * scale_factor
	$Viewport/Camera3D.position = Vector3(5.6, 3.3, -5.7) * scale_factor
	$Viewport/Camera3D.look_at(Vector3(0, dimensions.y * 0.43, 0))
	$Viewport/Platform.scale = Vector3(scale_factor, 1.0, scale_factor)


func _process(delta: float) -> void:
	_turntable.rotate_y(delta * 0.27)
