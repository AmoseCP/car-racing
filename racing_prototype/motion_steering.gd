extends Node

signal state_changed

enum State { OFF, SEARCHING, UNAVAILABLE, HOLD_UPRIGHT, READY }

const WindowsMotion := preload("res://racing_prototype/windows_motion.gd")
const WINDOWS_SOURCE := -2
const NO_SOURCE := -1
const MAX_TILT := deg_to_rad(32.0)
const DEAD_ZONE := deg_to_rad(2.5)
const MIN_UPRIGHT := 0.33

var enabled := false
var reversed := false
var state := State.OFF
var steering := 0.0

var _windows := WindowsMotion.new()
var _joy := NO_SOURCE
var _source := NO_SOURCE
var _neutral := Vector2.ZERO
var _projected := Vector2.ZERO
var _filtered := Vector2.ZERO


func _ready() -> void:
	set_process(false)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	_reset_center()
	if enabled:
		_windows.start(Time.get_ticks_msec())
		_select_joypad()
		_set_state(State.SEARCHING)
	else:
		_release_sources()
		_set_state(State.OFF)
	set_process(enabled)


func recenter() -> void:
	_neutral = _projected if state == State.READY else Vector2.ZERO
	_filtered = _neutral
	steering = 0.0


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var win := _windows.poll(now)
	if not win.is_zero_approx():
		_apply_sample(win, WINDOWS_SOURCE, delta)
		return
	if _joy >= 0:
		var gravity := Input.get_joy_gravity(_joy)
		if not gravity.is_zero_approx():
			_apply_sample(gravity, _joy, delta)
			return
	_source = NO_SOURCE
	_reset_center()
	_set_state(State.SEARCHING if _windows.is_starting(now) else State.UNAVAILABLE)


func _apply_sample(gravity: Vector3, source: int, delta: float) -> void:
	if _source != source:
		_source = source
		_reset_center()
	var direction := gravity.normalized()
	_projected = Vector2(direction.x, direction.y)
	if _projected.length_squared() < MIN_UPRIGHT * MIN_UPRIGHT:
		_filtered = Vector2.ZERO
		steering = 0.0
		_set_state(State.HOLD_UPRIGHT)
		return
	if _filtered.is_zero_approx():
		_filtered = _projected
	else:
		_filtered = _filtered.lerp(_projected, 1.0 - exp(-18.0 * delta))
	if _neutral.is_zero_approx():
		_neutral = _filtered
	var angle := -_neutral.angle_to(_filtered)
	var strength := clampf(inverse_lerp(DEAD_ZONE, MAX_TILT, absf(angle)), 0.0, 1.0)
	steering = signf(angle) * pow(strength, 1.15) * (-1.0 if reversed else 1.0)
	_set_state(State.READY)


func _reset_center() -> void:
	_projected = Vector2.ZERO
	_neutral = Vector2.ZERO
	_filtered = Vector2.ZERO
	steering = 0.0


func _set_state(value: State) -> void:
	if state != value:
		state = value
		state_changed.emit()


func _select_joypad() -> void:
	if _joy >= 0 and _joy in Input.get_connected_joypads():
		return
	_joy = NO_SOURCE
	for id in Input.get_connected_joypads():
		if Input.has_joy_motion_sensors(id):
			_joy = id
			Input.set_joy_motion_sensors_enabled(id, true)
			break


func _on_joy_connection_changed(_id: int, _connected: bool) -> void:
	if enabled:
		_select_joypad()


func _release_sources() -> void:
	_windows.stop()
	if _joy >= 0 and _joy in Input.get_connected_joypads():
		Input.set_joy_motion_sensors_enabled(_joy, false)
	_joy = NO_SOURCE
	_source = NO_SOURCE


func _exit_tree() -> void:
	_release_sources()
