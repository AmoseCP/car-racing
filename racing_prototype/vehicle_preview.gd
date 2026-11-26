extends SubViewportContainer

const Vehicles := preload("res://racing_prototype/vehicles.gd")

var _model: Node3D
@onready var _turntable: Node3D = $Viewport/Turntable


func _ready() -> void:
	$Viewport/Camera3D.look_at(Vector3(0, 0.53, 0))
	if Engine.max_fps == 30:
		$Viewport.msaa_3d = Viewport.MSAA_DISABLED


func show_vehicle(id: StringName, livery := 0) -> void:
	if is_instance_valid(_model):
		_turntable.remove_child(_model)
		_model.queue_free()
	_turntable.rotation.y = 0.0
	_model = Vehicles.instantiate_model(id)
	Vehicles.paint_model(_model, id, livery)
	_turntable.add_child(_model)


func _process(delta: float) -> void:
	_turntable.rotate_y(delta * 0.27)
