extends Node3D

signal finished(total_time: float)

const Courses := preload("res://racing_prototype/courses.gd")
const Vehicles := preload("res://racing_prototype/vehicles.gd")
const WeatherModes := preload("res://racing_prototype/weather_modes.gd")
const RaceWeather := preload("res://racing_prototype/race_weather.gd")
const LightingModes := preload("res://racing_prototype/lighting_modes.gd")
const RaceLighting := preload("res://racing_prototype/race_lighting.gd")
const Ui := preload("res://racing_prototype/ui_skin.gd")
const Art := preload("res://racing_prototype/track_art.gd")
const PAD_WIDTH := 1.85
const AUTO_HEADLIGHT_DARKNESS := 0.46

@export var weather_mode: StringName = WeatherModes.DYNAMIC
@export var lighting_mode: StringName = LightingModes.CYCLE

var _last_position: Vector3
var _next_gate := 0
var _lap := 0
var _elapsed := 0.0
var _best := INF
var _done := false
var _used_pads := 0
var _using_pad := false
var _lap_label: Label
var _time_label: Label
var _speed_label: Label
var _boost_label: Label
var _weather_label: Label
var _lighting_label: Label
var _controls: Label
var _manual_headlights := false

@onready var _track: Node3D = $Track
@onready var _car: CharacterBody3D = $Car
@onready var _camera: Camera3D = $ChaseCamera
@onready var _hud: CanvasLayer = $HUD
@onready var _weather: RaceWeather = $Weather
@onready var _lighting: RaceLighting = $Lighting


func _ready() -> void:
	_car.set_spawn(_track.spawn_transform())
	_camera.snap_to_car()
	_last_position = _car.position
	_apply_environment()
	_weather.configure(weather_mode)
	_car.weather = _weather
	_lighting.configure(lighting_mode)
	_update_lighting()
	_using_pad = not Input.get_connected_joypads().is_empty()
	_build_hud()


func _physics_process(delta: float) -> void:
	if _done:
		return
	if _lap > 0:
		_elapsed += delta
	_weather.advance(_elapsed, delta)
	_update_lighting()
	var here := _car.position
	if _crossed(_track.gates[_next_gate], here, _track.half_road + 1.6):
		if _next_gate == 0:
			_finish_crossed()
		else:
			_next_gate = (_next_gate + 1) % _track.gates.size()
	if not _done and _car.speed > 2.0:
		for i in range(_track.boost_pads.size()):
			var flag := 1 << i
			if (_used_pads & flag) == 0 and _crossed(_track.boost_pads[i], here, PAD_WIDTH):
				_used_pads |= flag
				_car.activate_boost()
	_last_position = here


func _process(_delta: float) -> void:
	_speed_label.text = "%03d" % roundi(absf(_car.speed) * 3.6)
	_time_label.text = "用时 %s    纪录 %s" % [Courses.time_text(_elapsed), Courses.time_text(_best)]
	_boost_label.text = "加速中" if _car.boost_time > 0.0 else ""
	_update_weather_label()
	_update_lighting_label()


func _input(event: InputEvent) -> void:
	if (event is InputEventJoypadButton and event.pressed) or (
			event is InputEventJoypadMotion and absf(event.axis_value) > 0.25):
		if not _using_pad:
			_using_pad = true
			_update_control_hint()
	elif event is InputEventKey and event.pressed and _using_pad:
		_using_pad = false
		_update_control_hint()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"race_reset"):
		restart()
	elif event.is_action_pressed(&"race_lights"):
		_manual_headlights = true
		_car.set_headlights(not _car.headlights_on)
		_update_lighting_label()
		get_viewport().set_input_as_handled()


func restart() -> void:
	_car.respawn()
	_camera.snap_to_car()
	_last_position = _car.position
	_next_gate = 0
	_lap = 0
	_elapsed = 0.0
	_done = false
	_used_pads = 0
	_weather.reset()
	_manual_headlights = false
	_update_lighting()
	_update_weather_label()
	_update_lighting_label()
	_lap_label.text = "驶过起点开始计时"


func set_record(time: float) -> void:
	_best = time


func set_hud_visible(value: bool) -> void:
	_hud.visible = value


func _update_lighting() -> void:
	_lighting.advance(_elapsed, _weather.rain_strength, _weather.snow_strength)
	if not _manual_headlights:
		_car.set_headlights(_lighting.darkness >= AUTO_HEADLIGHT_DARKNESS)


func _crossed(gate: Transform3D, here: Vector3, half_width: float) -> bool:
	var local := gate.affine_inverse()
	var previous := local * _last_position
	var current := local * here
	if previous.z <= 0.0 or current.z > 0.0:
		return false
	var crossing_x := lerpf(previous.x, current.x, previous.z / (previous.z - current.z))
	return absf(crossing_x) <= half_width


func _finish_crossed() -> void:
	if _lap == Courses.LAP_COUNT:
		_done = true
		_best = minf(_best, _elapsed)
		_lap_label.text = "比赛完成 · %s" % Courses.time_text(_elapsed)
		finished.emit(_elapsed)
		return
	_lap += 1
	_used_pads = 0
	_next_gate = 1
	_lap_label.text = "第 %d / %d 圈" % [_lap, Courses.LAP_COUNT]


func _apply_environment() -> void:
	var course: Dictionary = _track.course
	var course_id: StringName = _track.course_id
	var world: WorldEnvironment = $WorldEnvironment
	var env: Environment = world.environment.duplicate()
	var panorama := PanoramaSkyMaterial.new()
	var dusk := course_id == &"city" or course_id == &"tunnel"
	match course_id:
		&"desert": panorama.panorama = Art.WARM_SKY
		&"city", &"tunnel": panorama.panorama = Art.DUSK_SKY
		_: panorama.panorama = Art.DAY_SKY
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.sky_material = panorama
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_BG
	env.ambient_light_color = Color("b7c6d6")
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.background_energy_multiplier = 0.92
	env.fog_light_color = course.horizon.lerp(Color("9ea6af"), 0.42)
	env.fog_density = 0.007 if course_id == &"forest" else 0.0016
	env.fog_sky_affect = 0.28 if course_id == &"forest" else 0.10
	world.environment = env

	var ground: MeshInstance3D = $Ground/Surface
	ground.material_override = Art.ground(course_id, ground.mesh.size.x)
	var sun: DirectionalLight3D = $Sun
	sun.light_color = course.light
	sun.light_energy = 1.25
	sun.directional_shadow_max_distance = 104.0
	if dusk or course_id == &"desert":
		env.sky_rotation.y = deg_to_rad(22.0)
		sun.rotation_degrees.x = -24.0
	if dusk:
		env.background_energy_multiplier = 0.72
		env.ambient_light_energy = 0.32
		sun.light_energy = 0.82


func _build_hud() -> void:
	var layout := Control.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.theme = Ui.make_theme()
	_hud.add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var timing := _hud_panel(layout)
	timing.position = Vector2(24, 24)
	var timing_rows := timing.get_child(0)
	var accent: Color = _track.course.accent
	Ui.label(timing_rows, _track.course.name, 28, accent)
	Ui.label(timing_rows, Vehicles.DATA[_car.vehicle_id].name, 16, Ui.MUTED)
	_weather_label = Ui.label(timing_rows, "", 16, Ui.GREEN)
	_update_weather_label()
	_lighting_label = Ui.label(timing_rows, "", 16, Ui.MUTED)
	_update_lighting_label()
	_lap_label = Ui.label(timing_rows, "驶过起点开始计时", 20)
	_time_label = Ui.label(timing_rows, "用时 00:00.00    纪录 --:--.--", 17, Ui.MUTED)

	var speed := _hud_panel(layout)
	speed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	speed.offset_left = -176
	speed.offset_top = 24
	speed.offset_right = -24
	var speed_rows := speed.get_child(0)
	_speed_label = Ui.label(speed_rows, "000", 47, accent)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var units := Ui.label(speed_rows, "KM/H", 16, Ui.MUTED)
	units.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_boost_label = Ui.label(speed_rows, "", 18, Ui.GREEN)
	_boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var controls := _hud_panel(layout)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.offset_left = 24
	controls.offset_top = -68
	controls.offset_bottom = -24
	_controls = Ui.label(controls.get_child(0), "", 16)
	_update_control_hint()


func _update_weather_label() -> void:
	_weather_label.text = "%s  ·  极速 %d km/h" % [WeatherModes.NAMES[_weather.stage], roundi(_car.current_top_speed() * 3.6)]


func _update_lighting_label() -> void:
	var light := "车灯开" if _car.headlights_on else "车灯关"
	_lighting_label.text = "%s  ·  %s" % [_lighting.phase_name, light]


func _update_control_hint() -> void:
	if _using_pad:
		_controls.text = "RT 油门    LT 刹车 / 倒车    左摇杆 转向    X 车灯    Y 重试    菜单键 暂停"
	else:
		_controls.text = "W / ↑ 油门    S / ↓ 刹车 / 倒车    A D / ← → 转向    H 车灯    R 重试    Esc 暂停"


func _hud_panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", Ui.panel(Ui.INK, Color.TRANSPARENT))
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 1)
	panel.add_child(rows)
	parent.add_child(panel)
	return panel
