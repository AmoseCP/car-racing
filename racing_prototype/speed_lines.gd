extends Control
## Full-screen streaks that rush outward from the centre while the car is boosting.

const COUNT := 34
const INNER := 0.34
const COLOR := Color(0.86, 0.95, 1.0)

var _car: CharacterBody3D
var _angles := PackedFloat32Array()
var _radii := PackedFloat32Array()
var _lengths := PackedFloat32Array()
var _intensity := 0.0
var _rng := RandomNumberGenerator.new()


func configure(car: CharacterBody3D) -> void:
	_car = car
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_angles.resize(COUNT)
	_radii.resize(COUNT)
	_lengths.resize(COUNT)
	for index in range(COUNT):
		_respawn(index, _rng.randf_range(INNER, 1.0))


func _process(delta: float) -> void:
	if _car == null:
		return
	var top: float = maxf(1.0, _car.current_top_speed())
	var target := 0.0
	if _car.boost_time > 0.0 and _car.speed > 2.0:
		target = clampf(_car.speed / top, 0.4, 1.0)
	_intensity = lerpf(_intensity, target, 1.0 - exp(-7.0 * delta))
	if _intensity < 0.02:
		if visible:
			hide()
		return
	show()
	for index in range(COUNT):
		_radii[index] += delta * (1.4 + _lengths[index] * 4.0) * _intensity
		if _radii[index] > 1.15:
			_respawn(index, INNER)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var reach := center.length()
	for index in range(COUNT):
		var direction := Vector2.from_angle(_angles[index])
		var start := center + direction * reach * _radii[index]
		var finish := center + direction * reach * (_radii[index] + _lengths[index])
		var fade := smoothstep(INNER, INNER + 0.25, _radii[index]) * _intensity * 0.8
		draw_line(start, finish, Color(COLOR, fade), 2.6, true)


func _respawn(index: int, radius: float) -> void:
	_angles[index] = _rng.randf_range(0.0, TAU)
	_radii[index] = radius
	_lengths[index] = _rng.randf_range(0.06, 0.2)
