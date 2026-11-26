extends Node

enum Mode { SELECT, DRIVE, PAUSE, RESULTS, MOTION, VEHICLE, WEATHER, LIGHTING, CHALLENGES, CHALLENGE_RESULTS, HOME, JOURNEY_RESULTS, PAINT }

const Courses := preload("res://racing_prototype/courses.gd")
const Ui := preload("res://racing_prototype/ui_skin.gd")
const WeatherModes := preload("res://racing_prototype/weather_modes.gd")
const LightingModes := preload("res://racing_prototype/lighting_modes.gd")
const Vehicles := preload("res://racing_prototype/vehicles.gd")
const VehicleSelector := preload("res://racing_prototype/vehicle_selector.gd")
const RaceScene := preload("res://racing_prototype/red_mesa.tscn")
const JourneyScene := preload("res://racing_prototype/journey.tscn")
const Journey := preload("res://racing_prototype/journey.gd")
const MotionSteering := preload("res://racing_prototype/motion_steering.gd")
const Units := preload("res://racing_prototype/units.gd")
const WorldClock := preload("res://racing_prototype/world_clock.gd")
const DrivingChallenge := preload("res://racing_prototype/driving_challenge.gd")
const Audio := preload("res://racing_prototype/game_audio.gd")
const ChaseCamera := preload("res://racing_prototype/chase_camera.gd")
const Gamepad := preload("res://racing_prototype/gamepad.gd")
const DeviceProfile := preload("res://racing_prototype/device_profile.gd")
const TOAST_SECONDS := 3.2
const SAVE_PATH := "user://racing_records.cfg"
const FULLSCREEN_LABEL := "全屏 / 窗口    F11"
const CLOCK_SAVE_INTERVAL := 15.0

var _settings := ConfigFile.new()
var _world_clock := WorldClock.new()
var _saved_clock := 0.0
var _theme: Theme
var _quitting := false
var _mode := Mode.SELECT
var _selected: StringName = &"desert"
var _loaded: StringName
var _loaded_challenge: StringName
var _challenge_return := Mode.HOME
var _vehicle: StringName = Vehicles.DEFAULT
var _loaded_vehicle: StringName
var _vehicle_return := Mode.SELECT
var _weather_mode: StringName = WeatherModes.DYNAMIC
var _loaded_weather: StringName
var _weather_return := Mode.SELECT
var _lighting_mode: StringName = LightingModes.CYCLE
var _loaded_lighting: StringName
var _lighting_return := Mode.SELECT
var _race: Node3D
var _screen: Control
var _course_title: Label
var _course_notes: Label
var _course_target: Label
var _course_record: Label
var _weather_button: Button
var _lighting_button: Button
var _power_label: Label
var _performance := 0
var _motion_return := Mode.SELECT
var _motion_status: Label
var _motion_toggle: Button
var _motion_invert: Button
var _pad_status: Label
var _pad_live: Label
var _vibration_toggle: Button
var _toast: Label
var _toast_time := 0.0
var _livery := 0
var _paint_return := Mode.HOME
var _rivals_on := false
var _loaded_rivals := false
var _loaded_daily := false
var _rivals_button: Button

@onready var _overlay: CanvasLayer = $Overlay
@onready var _motion: MotionSteering = $MotionSteering


func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_quit_game)
	_settings.load(SAVE_PATH)
	var stored_clock: Variant = _settings.get_value("environment", "drive_seconds", 0.0)
	if (stored_clock is float or stored_clock is int) and is_finite(float(stored_clock)):
		_world_clock.seconds = maxf(0.0, float(stored_clock))
		_saved_clock = _world_clock.seconds
	var last := StringName(str(_settings.get_value("display", "last_course", "desert")))
	if Courses.DATA.has(last):
		_selected = last
	var saved_vehicle := StringName(str(_settings.get_value("garage", "vehicle", Vehicles.DEFAULT)))
	if Vehicles.DATA.has(saved_vehicle):
		_vehicle = saved_vehicle
	var saved_weather := StringName(str(_settings.get_value("race", "weather", WeatherModes.DYNAMIC)))
	if WeatherModes.NAMES.has(saved_weather):
		_weather_mode = saved_weather
	var saved_lighting := StringName(str(_settings.get_value("race", "lighting", LightingModes.CYCLE)))
	if LightingModes.NAMES.has(saved_lighting):
		_lighting_mode = saved_lighting
	_livery = clampi(int(_settings.get_value("garage", "livery", 0)), 0, Vehicles.LIVERIES.size() - 1)
	if _medal_points() < Vehicles.LIVERIES[_livery].points:
		_livery = 0
	_rivals_on = bool(_settings.get_value("race", "rivals", true))
	ChaseCamera.view = clampi(int(_settings.get_value("controls", "camera_view", 0)), 0, ChaseCamera.VIEW_NAMES.size() - 1)
	var fallback: int = DeviceProfile.default_performance()
	if bool(_settings.get_value("display", "battery_saver", false)):
		fallback = DeviceProfile.SAVER
	_performance = clampi(int(_settings.get_value("display", "performance", fallback)), 0, DeviceProfile.PRESETS.size() - 1)
	_apply_power_mode()
	Gamepad.vibration = bool(_settings.get_value("controls", "vibration", true))
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_theme = Ui.make_theme()
	_build_toast()
	_motion.state_changed.connect(_refresh_motion_settings)
	_motion.reversed = bool(_settings.get_value("controls", "motion_invert", false))
	_motion.set_enabled(bool(_settings.get_value("controls", "motion_steering", false)))
	if _has_desktop_window() and bool(_settings.get_value("display", "fullscreen", true)):
		get_window().mode = Window.MODE_FULLSCREEN
	_show_home()


func _process(delta: float) -> void:
	if _world_clock.seconds - _saved_clock >= CLOCK_SAVE_INTERVAL:
		_save_settings()
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.visible = _toast_time > 0.0
	if _mode == Mode.MOTION and is_instance_valid(_pad_live):
		_pad_status.text = Gamepad.connected_summary()
		_pad_live.text = Gamepad.live_readout()


func _notification(what: int) -> void:
	# Handheld overlay buttons, Game Bar and Cmd-Tab all steal focus: stop the race.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _mode == Mode.DRIVE and not _quitting:
		_show_pause()
		Gamepad.stop_rumble()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_show_toast("手柄已连接：%s" % Gamepad.describe(device))
	else:
		_show_toast("手柄已断开")
		if _mode == Mode.DRIVE:
			_show_pause()


func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Toast"
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_toast = Label.new()
	_toast.theme = _theme
	_toast.add_theme_font_size_override("font_size", 19)
	_toast.add_theme_stylebox_override("normal", Ui.panel(Ui.INK, Ui.GREEN, 1, 14))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_toast)
	_toast.hide()


func _show_toast(message: String) -> void:
	_toast.text = message
	_toast.reset_size()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_toast_time = TOAST_SECONDS
	_toast.show()


func _exit_tree() -> void:
	_save_world_progress()


func _quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	set_process_unhandled_input(false)
	_save_world_progress()
	get_tree().paused = false
	if is_instance_valid(_race):
		_race.queue_free()
		_race = null
	for voice in $Audio.get_children():
		if voice is AudioStreamPlayer:
			voice.stop()
			voice.stream = null
	# Let queued scene and GPU particle resources finish releasing before shutdown.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1, true, false, true).timeout
	get_tree().quit()


func _save_world_progress() -> void:
	if _world_clock.seconds > _saved_clock:
		_save_settings()


func _save_settings() -> void:
	_settings.set_value("environment", "drive_seconds", _world_clock.seconds)
	_settings.set_value("controls", "camera_view", ChaseCamera.view)
	_saved_clock = _world_clock.seconds
	_settings.save(SAVE_PATH)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"race_fullscreen"):
		if _has_desktop_window():
			_toggle_fullscreen()
		elif _mode == Mode.HOME and DisplayServer.get_name() == "embedded":
			_open_fullscreen_window()
		else:
			return
	elif _mode in [Mode.SELECT, Mode.CHALLENGES, Mode.CHALLENGE_RESULTS, Mode.JOURNEY_RESULTS] and (
			event.is_action_pressed(&"race_pause") or event.is_action_pressed(&"race_back")):
		match _mode:
			Mode.CHALLENGES: _return_from_settings(_challenge_return)
			Mode.CHALLENGE_RESULTS: _show_challenges()
			_: _show_home()
	elif _mode in [Mode.CHALLENGE_RESULTS, Mode.JOURNEY_RESULTS] and event.is_action_pressed(&"race_reset"):
		_restart()
	elif event.is_action_pressed(&"race_pause"):
		if _mode == Mode.DRIVE:
			_show_pause()
		elif _mode == Mode.PAUSE:
			_resume()
		elif _mode == Mode.MOTION:
			_close_motion_settings()
		elif _mode == Mode.VEHICLE:
			_close_vehicle_selector()
		elif _mode == Mode.WEATHER:
			_close_weather_selector()
		elif _mode == Mode.LIGHTING:
			_close_lighting_selector()
		elif _mode == Mode.PAINT:
			_close_paint_selector()
		else:
			return
	elif event.is_action_pressed(&"race_back") and _mode in [Mode.PAUSE, Mode.MOTION, Mode.VEHICLE, Mode.WEATHER, Mode.LIGHTING, Mode.PAINT]:
		if _mode == Mode.MOTION:
			_close_motion_settings()
		elif _mode == Mode.VEHICLE:
			_close_vehicle_selector()
		elif _mode == Mode.WEATHER:
			_close_weather_selector()
		elif _mode == Mode.LIGHTING:
			_close_lighting_selector()
		elif _mode == Mode.PAINT:
			_close_paint_selector()
		else:
			_resume()
	elif event.is_action_pressed(&"race_motion_center") and _motion.enabled:
		_recenter_motion()
	elif event.is_action_pressed(&"race_power") and _mode != Mode.DRIVE:
		_toggle_power_mode()
	else:
		return
	if event.is_action_pressed(&"race_pause") or event.is_action_pressed(&"race_back"):
		Audio.play_from(self, &"menu_back")
	elif event.is_action_pressed(&"race_fullscreen") or event.is_action_pressed(&"race_power") or event.is_action_pressed(&"race_motion_center"):
		Audio.play_from(self, &"menu_accept")
	get_viewport().set_input_as_handled()


func _show_home() -> void:
	_mode = Mode.HOME
	get_tree().paused = true
	_save_world_progress()
	_load_journey()
	if _race.elapsed > 0.0 or _race._done:
		_race.restart()
	_race.set_hud_visible(false)
	_build_overlay()
	var menu := _panel(396)
	menu.position = Vector2(26, 26)
	var rows := _rows(menu, 6)
	Ui.label(rows, "CAR RACING", 37)
	var daily := _daily_preset()
	var buttons: Array[Button] = [
		Ui.menu_button(rows, "开始远行", _start_journey, 48),
		Ui.menu_button(rows, "每日挑战    %s · %s" % [Courses.DATA[daily.course].name, Vehicles.DATA[daily.vehicle].name], _start_daily, 38),
		Ui.menu_button(rows, "赛车选择    %s" % Vehicles.DATA[_vehicle].name, _show_vehicle_selector, 38),
		Ui.menu_button(rows, "车漆涂装    %s" % Vehicles.LIVERIES[_livery].name, _show_paint_selector, 38),
		Ui.menu_button(rows, "天气    %s" % WeatherModes.NAMES[_weather_mode], _show_weather_selector, 38),
		Ui.menu_button(rows, "昼夜    %s" % LightingModes.NAMES[_lighting_mode], _show_lighting_selector, 38),
		Ui.menu_button(rows, "手柄与体感", _show_motion_settings, 38),
		Ui.menu_button(rows, "驾驶挑战", _show_challenges, 38),
		Ui.menu_button(rows, "赛道练习", _show_selector, 38),
	]
	if _has_desktop_window():
		buttons.append(Ui.menu_button(rows, FULLSCREEN_LABEL, _toggle_fullscreen, 38))
	elif DisplayServer.get_name() == "embedded":
		buttons.append(Ui.menu_button(rows, "在独立窗口全屏", _open_fullscreen_window, 38))
	buttons.append(Ui.menu_button(rows, "退出游戏", _quit_game, 38))
	Ui.link_vertical_buttons(buttons)
	_power_label = Ui.label(rows, "", 17, Ui.MUTED)
	_update_power_label()
	buttons[0].grab_focus()

	var overview := _panel(360)
	overview.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	overview.offset_right = -26
	overview.offset_left = -386
	overview.offset_bottom = -26
	overview.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var detail := _rows(overview, 7)
	Ui.label(detail, "公路远行", 31, Ui.GREEN)
	var note := Ui.label(detail, "一路向前，穿过不同地貌。车况降到零或燃油耗尽时结算。连续守规驾驶提升得分倍数，油量不足时驶入加油站慢行加油。", 18)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var speed_note := Ui.label(detail, "超限速 %d mph 或低于限速 %d mph 会扣分。" % [Journey.OVER_LIMIT, Journey.UNDER_LIMIT], 16, Ui.MUTED)
	speed_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Ui.label(detail, "最高分  %d" % _journey_record(), 22)
	var today := _daily_record()
	var daily_line := "每日挑战  %s · %s · %s" % [WeatherModes.NAMES[daily.weather], LightingModes.NAMES[daily.lighting],
		"今日最佳 %s" % Courses.time_text(today) if is_finite(today) else "今日未完成"]
	Ui.label(detail, daily_line, 16, Ui.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _load_journey() -> void:
	if _race is Journey and _loaded_vehicle == _vehicle and _loaded_weather == _weather_mode and _loaded_lighting == _lighting_mode:
		return
	_replace_drive(JourneyScene, _vehicle, _weather_mode, _lighting_mode)
	_race.name = "Journey"
	_race.ended.connect(_show_journey_results)
	_loaded = &""
	_loaded_challenge = &""
	_loaded_daily = false
	add_child(_race)


func _start_journey() -> void:
	_load_journey()
	_restart()


func _show_selector() -> void:
	_mode = Mode.SELECT
	get_tree().paused = true
	_build_overlay()
	var menu := _panel(420)
	menu.position = Vector2(26, 26)
	var rows := _rows(menu, 4)
	Ui.label(rows, "CAR RACING", 32)
	Ui.label(rows, "选择赛道 · 两圈计时", 22, Ui.GREEN)
	var buttons: Array[Button] = []
	var focus: Button
	for id in Courses.ORDER:
		var data: Dictionary = Courses.DATA[id]
		var button := Ui.menu_button(rows, "%s    %s" % [data.name, data.banner], _start_course.bind(id), 35)
		button.focus_entered.connect(_preview_course.bind(id))
		button.mouse_entered.connect(button.grab_focus)
		buttons.append(button)
		if id == _selected:
			focus = button
	_rivals_button = Ui.menu_button(rows, _rivals_caption(), _toggle_rivals, 35)
	buttons.append(_rivals_button)
	buttons.append(Ui.menu_button(rows, "驾驶挑战", _show_challenges, 35))
	buttons.append(Ui.menu_button(rows, "赛车选择    %s" % Vehicles.DATA[_vehicle].name, _show_vehicle_selector, 35))
	if _has_desktop_window():
		buttons.append(Ui.menu_button(rows, FULLSCREEN_LABEL, _toggle_fullscreen, 35))
	buttons.append(Ui.menu_button(rows, "手柄与体感", _show_motion_settings, 35))
	buttons.append(Ui.menu_button(rows, "返回主菜单", _show_home, 35))
	Ui.link_vertical_buttons(buttons)
	Ui.label(rows, "方向键 / 左摇杆  选择    A / Enter  确认", 17, Ui.MUTED)
	_power_label = Ui.label(rows, "", 17, Ui.MUTED)
	_update_power_label()
	_show_embedded_hint(rows)

	var detail := _panel(392)
	detail.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	detail.offset_left = -420
	detail.offset_right = -26
	detail.offset_top = -322
	detail.offset_bottom = -26
	detail.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var detail_rows := _rows(detail, 7)
	_course_title = Ui.label(detail_rows, "", 30)
	Ui.label(detail_rows, "靠右行驶，跑完两圈。违规扣分会增加结算用时。", 16, Ui.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_course_notes = Ui.label(detail_rows, "", 19, Ui.TEXT)
	_course_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_course_target = Ui.label(detail_rows, "", 18, Ui.GREEN)
	_course_record = Ui.label(detail_rows, "", 17, Ui.TEXT)
	var environment_buttons := HBoxContainer.new()
	environment_buttons.add_theme_constant_override("separation", 8)
	detail_rows.add_child(environment_buttons)
	_weather_button = Ui.menu_button(environment_buttons, "天气  %s" % WeatherModes.NAMES[_weather_mode], _show_weather_selector, 40)
	_lighting_button = Ui.menu_button(environment_buttons, LightingModes.NAMES[_lighting_mode], _show_lighting_selector, 40)
	_weather_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lighting_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for button in buttons:
		button.focus_neighbor_right = button.get_path_to(_weather_button)
	_weather_button.focus_neighbor_left = _weather_button.get_path_to(focus)
	_weather_button.focus_neighbor_right = _weather_button.get_path_to(_lighting_button)
	_lighting_button.focus_neighbor_left = _lighting_button.get_path_to(_weather_button)
	Ui.label(detail_rows, "Car models by vinish.dev · CC BY 4.0", 13, Ui.MUTED)
	_preview_course(_selected)
	focus.grab_focus()


func _preview_course(id: StringName) -> void:
	_selected = id
	var focused := get_viewport().gui_get_focus_owner()
	if focused is Button and focused != _weather_button and focused != _lighting_button and is_instance_valid(_weather_button):
		_weather_button.focus_neighbor_left = _weather_button.get_path_to(focused)
	var data: Dictionary = Courses.DATA[id]
	_course_title.text = data.tagline
	_course_title.add_theme_color_override("font_color", data.accent)
	_course_notes.text = data.description
	var target := _silver_target(id)
	_course_target.text = "金牌 %s    银牌 %s" % [Courses.time_text(Courses.gold_target(target)), Courses.time_text(target)]
	var record := _record(id)
	var medal := Courses.medal_for(record, target)
	_course_record.text = "本车纪录 %s    %s" % [Courses.time_text(record), Courses.MEDAL_NAMES[medal]]
	_course_record.add_theme_color_override("font_color", Courses.MEDAL_COLORS[medal])
	_refresh_preview.call_deferred()


func _refresh_preview() -> void:
	if _mode != Mode.SELECT:
		return
	_load_course(_selected)
	_race.set_hud_visible(false)


func _load_course(id: StringName, challenge_id: StringName = &"", daily := false) -> void:
	var preset: Dictionary = _daily_preset() if daily else DrivingChallenge.DATA.get(challenge_id, {})
	var vehicle: StringName = preset.get("vehicle", _vehicle)
	var weather: StringName = preset.get("weather", _weather_mode)
	var lighting: StringName = preset.get("lighting", _lighting_mode)
	var rivals := _rivals_on and challenge_id.is_empty()
	if _loaded == id and _loaded_challenge == challenge_id and _loaded_vehicle == vehicle and (
			_loaded_weather == weather and _loaded_lighting == lighting and is_instance_valid(_race)) and (
			_loaded_daily == daily and _loaded_rivals == rivals):
		return
	_replace_drive(RaceScene, vehicle, weather, lighting)
	_race.name = "Race"
	_race.get_node("Track").course_id = id
	_race.challenge_id = challenge_id
	_race.rivals_enabled = rivals
	_race.finished.connect(_show_results)
	_race.challenge_finished.connect(_show_challenge_results)
	_loaded = id
	_loaded_challenge = challenge_id
	_loaded_daily = daily
	_loaded_rivals = rivals
	add_child(_race)
	if daily:
		_race.set_record(_daily_record(), PackedFloat32Array())
		_race.set_ghost(_daily_ghost())
	elif challenge_id.is_empty():
		_race.set_record(_record(id), _record_splits(id))
		_race.set_ghost(_ghost(id))
	else:
		var challenge_record := _challenge_record(challenge_id)
		_race.set_record(challenge_record.get("time", INF), challenge_record.get("splits", PackedFloat32Array()))


func _replace_drive(scene: PackedScene, vehicle: StringName, weather: StringName, lighting: StringName) -> void:
	if is_instance_valid(_race):
		remove_child(_race)
		_race.queue_free()
	_race = scene.instantiate()
	_race.process_mode = Node.PROCESS_MODE_PAUSABLE
	_race.get_node("Car").motion_steering = _motion
	_race.get_node("Car").vehicle_id = vehicle
	_race.get_node("Car").livery = _livery
	_race.weather_mode = weather
	_race.lighting_mode = lighting
	_race.world_clock = _world_clock
	_loaded_vehicle = vehicle
	_loaded_weather = weather
	_loaded_lighting = lighting


func _start_course(id: StringName) -> void:
	_selected = id
	_load_course(id)
	_settings.set_value("display", "last_course", str(id))
	_save_settings()
	_restart()


func _show_challenges() -> void:
	if _mode in [Mode.HOME, Mode.SELECT]:
		_challenge_return = _mode
	_mode = Mode.CHALLENGES
	get_tree().paused = true
	if is_instance_valid(_race):
		_race.set_hud_visible(false)
	var rows := _center_menu("驾驶挑战", 630)
	Ui.label(rows, "固定车辆与路况。零违规完成才会登记挑战纪录。", 18, Ui.MUTED)
	var buttons: Array[Button] = []
	for id: StringName in DrivingChallenge.ORDER:
		var data: Dictionary = DrivingChallenge.DATA[id]
		var record: float = _challenge_record(id).get("time", INF)
		var caption := "%s · %s    %d 秒    纪录 %s" % [
			Courses.DATA[data.course].name, data.title, roundi(data.limit), Courses.time_text(record)]
		buttons.append(Ui.menu_button(rows, caption, _start_challenge.bind(id), 49))
		var detail := Ui.label(rows, data.goal, 17, Ui.TEXT)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buttons.append(Ui.menu_button(rows, "返回", _return_from_settings.bind(_challenge_return), 44))
	Ui.link_vertical_buttons(buttons)
	var previous := DrivingChallenge.ORDER.find(_loaded_challenge)
	buttons[maxi(0, previous)].grab_focus()


func _start_challenge(id: StringName) -> void:
	_load_course(DrivingChallenge.DATA[id].course, id)
	_restart()


func _restart() -> void:
	_race.restart()
	_resume()
	Audio.play_from(self, &"ignition")


func _resume() -> void:
	_mode = Mode.DRIVE
	_clear_overlay()
	_race.set_hud_visible(true)
	get_tree().paused = false


func _show_pause() -> void:
	_mode = Mode.PAUSE
	get_tree().paused = true
	_save_world_progress()
	var is_journey := _race is Journey
	var rows := _center_menu("远行暂停" if is_journey else "比赛暂停")
	var buttons: Array[Button] = [
		Ui.menu_button(rows, "继续远行" if is_journey else "继续比赛", _resume),
		Ui.menu_button(rows, "重新开始", _restart),
	]
	if _has_desktop_window():
		buttons.append(Ui.menu_button(rows, FULLSCREEN_LABEL, _toggle_fullscreen))
	buttons.append(Ui.menu_button(rows, "手柄与体感", _show_motion_settings))
	if is_journey or _loaded_daily:
		buttons.append(Ui.menu_button(rows, "返回主菜单", _show_home))
	elif _loaded_challenge.is_empty():
		buttons.append(Ui.menu_button(rows, "天气    %s" % WeatherModes.NAMES[_weather_mode], _show_weather_selector))
		buttons.append(Ui.menu_button(rows, "昼夜    %s" % LightingModes.NAMES[_lighting_mode], _show_lighting_selector))
		buttons.append(Ui.menu_button(rows, "更换赛车", _show_vehicle_selector))
		buttons.append(Ui.menu_button(rows, "更换赛道", _show_selector))
	else:
		buttons.append(Ui.menu_button(rows, "挑战列表", _show_challenges))
	Ui.label(rows, "B / 菜单键 / Esc  继续", 17, Ui.MUTED)
	_power_label = Ui.label(rows, "", 17, Ui.MUTED)
	_update_power_label()
	_show_embedded_hint(rows)
	Ui.link_vertical_buttons(buttons)
	buttons[0].grab_focus()


func _show_weather_selector() -> void:
	_weather_return = _mode
	_mode = Mode.WEATHER
	var rows := _center_menu("天气设置", 482)
	var description := Ui.label(rows, "动态天气随季节变化。雨天极速降低 15%，雪天降低 30%。", 18, Ui.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _weather_return == Mode.PAUSE:
		Ui.label(rows, "更改天气后从起点重新开始。", 16, Ui.MUTED)
	var buttons: Array[Button] = []
	var focus: Button
	for id in WeatherModes.ORDER:
		var button := Ui.menu_button(rows, WeatherModes.NAMES[id], _select_weather.bind(id))
		buttons.append(button)
		if id == _weather_mode:
			focus = button
	buttons.append(Ui.menu_button(rows, "返回", _close_weather_selector))
	Ui.link_vertical_buttons(buttons)
	focus.grab_focus()


func _select_weather(id: StringName) -> void:
	if id != _weather_mode:
		_weather_mode = id
		_settings.set_value("race", "weather", str(id))
		_save_settings()
		if _weather_return == Mode.PAUSE:
			_load_course(_loaded)
	_close_weather_selector()


func _close_weather_selector() -> void:
	_return_from_settings(_weather_return)


func _show_lighting_selector() -> void:
	_lighting_return = _mode
	_mode = Mode.LIGHTING
	var rows := _center_menu("昼夜设置", 472)
	var description := Ui.label(rows, "昼夜每 2 分 30 秒切换，季节每 10 分钟轮换。天黑自动开灯，按 H 或手柄 X 手动切换。", 18, Ui.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _lighting_return == Mode.PAUSE:
		Ui.label(rows, "更改昼夜后从起点重新开始。", 16, Ui.MUTED)
	var buttons: Array[Button] = []
	var focus: Button
	for id in LightingModes.ORDER:
		var button := Ui.menu_button(rows, LightingModes.NAMES[id], _select_lighting.bind(id))
		buttons.append(button)
		if id == _lighting_mode:
			focus = button
	buttons.append(Ui.menu_button(rows, "返回", _close_lighting_selector))
	Ui.link_vertical_buttons(buttons)
	focus.grab_focus()


func _select_lighting(id: StringName) -> void:
	if id != _lighting_mode:
		_lighting_mode = id
		_settings.set_value("race", "lighting", str(id))
		_save_settings()
		if _lighting_return == Mode.PAUSE:
			_load_course(_loaded)
	_close_lighting_selector()


func _close_lighting_selector() -> void:
	_return_from_settings(_lighting_return)


func _show_vehicle_selector() -> void:
	_vehicle_return = _mode
	_mode = Mode.VEHICLE
	var rows := _center_menu("选择赛车", 860)
	var selector := VehicleSelector.new()
	selector.name = "VehicleSelector"
	rows.add_child(selector)
	selector.chosen.connect(_select_vehicle)
	selector.cancelled.connect(_close_vehicle_selector)
	selector.setup(_vehicle, _vehicle_return == Mode.PAUSE, _livery)


func _select_vehicle(id: StringName) -> void:
	if id != _vehicle:
		_vehicle = id
		_settings.set_value("garage", "vehicle", str(id))
		_save_settings()
		if _vehicle_return == Mode.PAUSE:
			_load_course(_loaded)
	_close_vehicle_selector()


func _close_vehicle_selector() -> void:
	_return_from_settings(_vehicle_return)


func _show_motion_settings() -> void:
	_motion_return = _mode
	_mode = Mode.MOTION
	var rows := _center_menu("手柄与体感", 560)
	_pad_status = Ui.label(rows, Gamepad.connected_summary(), 18, Ui.GREEN)
	_pad_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pad_live = Ui.label(rows, Gamepad.live_readout(), 16, Ui.TEXT)
	if OS.get_name() == "macOS":
		var mac_note := Ui.label(rows, "Mac：Xbox 手柄请在“系统设置 → 蓝牙”中配对（macOS 不支持 Xbox 有线连接）。若在 Godot 编辑器中运行，请关闭“嵌入游戏”后再试。", 15, Ui.MUTED)
		mac_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vibration_toggle = Ui.menu_button(rows, "", _toggle_vibration)
	var instructions := Ui.label(rows, "体感转向：像转方向盘一样扭动掌机。按平常姿势握住后，用 R3 / G 校准中位。", 16, Ui.MUTED)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_motion_status = Ui.label(rows, "", 17, Ui.GREEN)
	_motion_toggle = Ui.menu_button(rows, "", _toggle_motion)
	var recenter := Ui.menu_button(rows, "校准中位", _recenter_motion)
	_motion_invert = Ui.menu_button(rows, "", _invert_motion)
	var back := Ui.menu_button(rows, "返回", _close_motion_settings)
	Ui.link_vertical_buttons([_vibration_toggle, _motion_toggle, recenter, _motion_invert, back])
	_refresh_motion_settings()
	_vibration_toggle.grab_focus()


func _close_motion_settings() -> void:
	_return_from_settings(_motion_return)


func _return_from_settings(screen: Mode) -> void:
	match screen:
		Mode.PAUSE: _show_pause()
		Mode.HOME: _show_home()
		_: _show_selector()


func _toggle_motion() -> void:
	_motion.set_enabled(not _motion.enabled)
	_save_motion_settings()
	_refresh_motion_settings()


func _invert_motion() -> void:
	_motion.reversed = not _motion.reversed
	_save_motion_settings()
	_refresh_motion_settings()


func _recenter_motion() -> void:
	_motion.recenter()
	if is_instance_valid(_motion_status) and _motion.state == MotionSteering.State.READY:
		_motion_status.text = "中位已校准"


func _save_motion_settings() -> void:
	_settings.set_value("controls", "motion_steering", _motion.enabled)
	_settings.set_value("controls", "motion_invert", _motion.reversed)
	_save_settings()


func _toggle_vibration() -> void:
	Gamepad.vibration = not Gamepad.vibration
	_settings.set_value("controls", "vibration", Gamepad.vibration)
	_save_settings()
	_refresh_motion_settings()
	Gamepad.rumble(0.4, 0.6, 0.25)


func _refresh_motion_settings() -> void:
	if not is_instance_valid(_motion_status):
		return
	_vibration_toggle.text = "手柄震动    开启" if Gamepad.vibration else "手柄震动    关闭"
	_motion_toggle.text = "体感转向    开启" if _motion.enabled else "体感转向    关闭"
	_motion_invert.text = "转向方向    反转" if _motion.reversed else "转向方向    正常"
	match _motion.state:
		MotionSteering.State.OFF: _motion_status.text = "开启后检测体感传感器"
		MotionSteering.State.SEARCHING: _motion_status.text = "正在检测传感器"
		MotionSteering.State.UNAVAILABLE: _motion_status.text = "未检测到可用的传感器"
		MotionSteering.State.HOLD_UPRIGHT: _motion_status.text = "请把屏幕朝向自己，再校准中位"
		MotionSteering.State.READY: _motion_status.text = "传感器已连接"


func _show_results(total: float) -> void:
	_mode = Mode.RESULTS
	get_tree().paused = true
	Audio.play_from(self, &"finish")
	if _loaded_daily:
		_show_daily_results(total)
		return
	var old_record := _record(_loaded)
	var reference := _record_splits(_loaded)
	var splits: PackedFloat32Array = _race.split_times()
	var new_record := total < old_record
	if new_record:
		_settings.set_value(_record_section(), str(_loaded), total)
		_settings.set_value(_record_section() + "_splits", str(_loaded), splits)
		var ghost: Dictionary = _race.ghost_recording()
		_settings.set_value(_record_section() + "_ghost", str(_loaded), ghost)
		_save_settings()
		_race.set_record(total, splits)
		_race.set_ghost(ghost)
	else:
		_save_world_progress()
	var data: Dictionary = Courses.DATA[_loaded]
	var target := _silver_target(_loaded)
	var medal := Courses.medal_for(total, target)
	var rows := _center_menu("比赛完成", 560)
	_add_race_position(rows)
	Ui.label(rows, "%s   %s" % [Courses.MEDAL_NAMES[medal], Courses.time_text(total)], 44, Courses.MEDAL_COLORS[medal])
	Ui.label(rows, "%s · %s · %s" % [data.name, Vehicles.DATA[_vehicle].name, WeatherModes.NAMES[_weather_mode]], 18, Ui.MUTED)
	Ui.label(rows, "驾驶分 %d / 100    违规 %d 次" % [_race.road_score, _race.violation_count], 19, Ui.TEXT)
	Ui.label(rows, "实际用时 %s    罚时 +%.1f 秒" % [
		Courses.time_text(_race.elapsed_seconds()), _race.penalty_seconds()], 17, Ui.MUTED)
	if medal != Courses.Medal.GOLD:
		var next_target := Courses.gold_target(target) if medal == Courses.Medal.SILVER else target
		Ui.label(rows, "距%s还差 %s" % [Courses.MEDAL_NAMES[medal + 1], Courses.time_text(total - next_target)], 17, Ui.MUTED)
	var caption := "刷新个人纪录" if new_record else "个人纪录  %s" % Courses.time_text(old_record)
	Ui.label(rows, caption, 18, Ui.GREEN)
	_add_result_splits(rows, splits, reference)
	var buttons: Array[Button] = [
		Ui.menu_button(rows, "再跑一次", _restart), Ui.menu_button(rows, "更换赛道", _show_selector),
	]
	Ui.link_vertical_buttons(buttons)
	buttons[0].grab_focus()


func _show_challenge_results(reason: String) -> void:
	_mode = Mode.CHALLENGE_RESULTS
	get_tree().paused = true
	var elapsed: float = _race.elapsed_seconds()
	var splits: PackedFloat32Array = _race.split_times()
	var record := _challenge_record(_loaded_challenge)
	var reference: PackedFloat32Array = record.get("splits", PackedFloat32Array())
	var previous: float = record.get("time", INF)
	var passed := reason.is_empty()
	Audio.play_from(self, &"finish" if passed else &"game_over")
	var new_record := passed and elapsed < previous
	if new_record:
		_settings.set_value("challenge_records", str(_loaded_challenge), {"time": elapsed, "splits": splits})
		_save_settings()
		_race.set_record(elapsed, splits)
	else:
		_save_world_progress()
	var rows := _center_menu("挑战完成" if passed else "挑战未通过", 560)
	Ui.label(rows, _race.challenge.profile.title, 20, Ui.MUTED)
	if passed:
		var medal: int = _race.challenge.medal(elapsed)
		Ui.label(rows, "%s   %s" % [Courses.MEDAL_NAMES[medal], Courses.time_text(elapsed)], 36, Courses.MEDAL_COLORS[medal])
		Ui.label(rows, "零违规  ·  刷新挑战纪录" if new_record else "零违规  ·  纪录 %s" % Courses.time_text(previous), 18, Ui.GREEN)
	else:
		Ui.label(rows, reason, 23, Color("ffaa9d"))
		Ui.label(rows, "用时 %s  ·  挑战纪录 %s" % [Courses.time_text(elapsed), Courses.time_text(previous)], 17, Ui.MUTED)
	_add_result_splits(rows, splits, reference)
	var buttons: Array[Button] = [
		Ui.menu_button(rows, "再试一次", _restart), Ui.menu_button(rows, "挑战列表", _show_challenges),
	]
	Ui.link_vertical_buttons(buttons)
	buttons[0].grab_focus()


func _show_journey_results(report: Dictionary) -> void:
	_mode = Mode.JOURNEY_RESULTS
	get_tree().paused = true
	Audio.play_from(self, &"game_over")
	var best := _journey_record()
	var new_record: bool = report.score > best
	if new_record:
		_settings.set_value("journey", "high_score", report.score)
		_save_settings()
	else:
		_save_world_progress()
	var rows := _center_menu("远行结束", 496)
	Ui.label(rows, report.rating, 39, Color("ffd387"))
	Ui.label(rows, report.reason, 19, Color("ffab97"))
	Ui.label(rows, "%d 分" % report.score, 41)
	Ui.label(rows, "刷新最高分" if new_record else "最高分  %d" % best, 18, Ui.GREEN)
	Ui.label(rows, "里程 %.2f mi   地貌 %d 段   用时 %s" % [
		Units.miles(report.distance), report.sections, Courses.time_text(report.time)], 18, Ui.MUTED)
	Ui.label(rows, "碰撞 %d 次   违规 %d 次   安全超车 %d 次" % [
		report.collisions, report.violations, report.overtakes], 18, Ui.MUTED)
	Ui.label(rows, "最高守规连击  ×%.2f" % report.get("best_multiplier", 1.0), 18, Ui.GREEN)
	var buttons: Array[Button] = [
		Ui.menu_button(rows, "再次出发", _restart), Ui.menu_button(rows, "返回主菜单", _show_home),
	]
	Ui.link_vertical_buttons(buttons)
	buttons[0].grab_focus()


func _show_daily_results(total: float) -> void:
	var date := Time.get_date_string_from_system()
	var preset := _daily_preset()
	var best := _daily_record()
	var new_record := total < best
	if new_record:
		_settings.set_value("daily", date, total)
		var ghost: Dictionary = _race.ghost_recording()
		ghost["date"] = date
		_settings.set_value("daily_ghost", "latest", ghost)
		_save_settings()
		_race.set_record(total)
		_race.set_ghost(ghost)
	else:
		_save_world_progress()
	var rows := _center_menu("每日挑战完成", 560)
	_add_race_position(rows)
	Ui.label(rows, Courses.time_text(total), 44, Color("ffd387"))
	Ui.label(rows, "%s · %s · %s · %s" % [Courses.DATA[preset.course].name, Vehicles.DATA[preset.vehicle].name,
		WeatherModes.NAMES[preset.weather], LightingModes.NAMES[preset.lighting]], 18, Ui.MUTED)
	Ui.label(rows, "驾驶分 %d / 100    违规 %d 次" % [_race.road_score, _race.violation_count], 19, Ui.TEXT)
	Ui.label(rows, "刷新今日最佳" if new_record else "今日最佳  %s" % Courses.time_text(best), 18, Ui.GREEN)
	Ui.label(rows, "完成每日挑战的天数计入奖牌点数，可解锁新车漆。", 16, Ui.MUTED)
	var buttons: Array[Button] = [
		Ui.menu_button(rows, "再跑一次", _restart), Ui.menu_button(rows, "返回主菜单", _show_home),
	]
	Ui.link_vertical_buttons(buttons)
	buttons[0].grab_focus()


func _add_race_position(rows: VBoxContainer) -> void:
	var position: int = _race.finishing_position()
	if position <= 0:
		return
	var colors := [Color("ffd675"), Color("c5dbf3"), Color("e2a376")]
	var color: Color = colors[position - 1] if position <= colors.size() else Ui.MUTED
	Ui.label(rows, "第 %d 名  /  %d 辆赛车" % [position, _race.racer_count()], 30, color)


func _start_daily() -> void:
	_load_course(_daily_preset().course, &"", true)
	_restart()


## Today's fixed course, car, weather and light, the same for every player on a date.
func _daily_preset() -> Dictionary:
	var date := Time.get_date_string_from_system()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("car-racing-daily-" + date)
	return {
		"date": date,
		"course": Courses.ORDER[rng.randi_range(0, Courses.ORDER.size() - 1)],
		"vehicle": Vehicles.ORDER[rng.randi_range(0, Vehicles.ORDER.size() - 1)],
		"weather": WeatherModes.ORDER[rng.randi_range(0, WeatherModes.ORDER.size() - 1)],
		"lighting": LightingModes.ORDER[rng.randi_range(0, LightingModes.ORDER.size() - 1)],
	}


func _daily_record() -> float:
	var value := float(_settings.get_value("daily", Time.get_date_string_from_system(), INF))
	return value if is_finite(value) and value > 0.0 else INF


func _daily_ghost() -> Dictionary:
	var value: Variant = _settings.get_value("daily_ghost", "latest", {})
	if value is Dictionary and value.get("date", "") == Time.get_date_string_from_system():
		return value
	return {}


func _ghost(id: StringName) -> Dictionary:
	var value: Variant = _settings.get_value(_record_section() + "_ghost", str(id), {})
	return value if value is Dictionary else {}


func _rivals_caption() -> String:
	return "对手赛车    %s" % ("3 名 · 发车倒计时" if _rivals_on else "关闭 · 单人计时")


func _toggle_rivals() -> void:
	_rivals_on = not _rivals_on
	_settings.set_value("race", "rivals", _rivals_on)
	_save_settings()
	if is_instance_valid(_rivals_button):
		_rivals_button.text = _rivals_caption()
	_refresh_preview()


## Bronze 1, silver 2, gold 3 for every course record (any car or weather) and
## challenge record, plus 1 for each day the daily challenge was completed.
func _medal_points() -> int:
	var points := 0
	for vehicle in Vehicles.ORDER:
		for weather in WeatherModes.ORDER:
			var section := _record_section_for(vehicle, weather)
			for id in Courses.ORDER:
				var time := float(_settings.get_value(section, str(id), INF))
				if is_finite(time) and time > 0.0:
					points += Courses.medal_for(time, _silver_target_for(id, weather))
	for id: StringName in DrivingChallenge.ORDER:
		var time: float = _challenge_record(id).get("time", INF)
		if is_finite(time):
			var data: Dictionary = DrivingChallenge.DATA[id]
			points += 3 if time <= data.gold else (2 if time <= data.silver else 1)
	if _settings.has_section("daily"):
		points += _settings.get_section_keys("daily").size()
	return points


func _show_paint_selector() -> void:
	_paint_return = _mode
	_mode = Mode.PAINT
	_build_overlay()
	var menu := _panel(430)
	menu.position = Vector2(26, 26)
	var rows := _rows(menu, 7)
	Ui.label(rows, "车漆涂装", 33, Ui.GREEN)
	var points := _medal_points()
	var summary := Ui.label(rows, "奖牌点数 %d    铜 1 · 银 2 · 金 3 · 每日挑战 1" % points, 16, Ui.MUTED)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var buttons: Array[Button] = []
	for index in range(Vehicles.LIVERIES.size()):
		var scheme: Dictionary = Vehicles.LIVERIES[index]
		var unlocked: bool = points >= scheme.points
		var caption: String = scheme.name if unlocked else "%s    需要 %d 点" % [scheme.name, scheme.points]
		if index == _livery:
			caption += "    ✓"
		var button := Ui.menu_button(rows, caption, _select_livery.bind(index, unlocked), 42)
		if not unlocked:
			button.add_theme_color_override("font_color", Color("7f8ea3"))
		button.focus_entered.connect(_preview_livery.bind(index))
		button.mouse_entered.connect(button.grab_focus)
		buttons.append(button)
	buttons.append(Ui.menu_button(rows, "返回", _close_paint_selector, 42))
	Ui.link_vertical_buttons(buttons)
	Ui.label(rows, "跑出奖牌、完成挑战解锁更多车漆。", 15, Ui.MUTED)
	buttons[_livery].grab_focus()


func _preview_livery(index: int) -> void:
	if is_instance_valid(_race):
		_race.get_node("Car").apply_livery(index)


func _select_livery(index: int, unlocked: bool) -> void:
	if not unlocked:
		return
	_livery = index
	_settings.set_value("garage", "livery", index)
	_save_settings()
	_close_paint_selector()


func _close_paint_selector() -> void:
	_preview_livery(_livery)
	_return_from_settings(_paint_return)


func _journey_record() -> int:
	return maxi(0, int(_settings.get_value("journey", "high_score", 0)))


func _add_result_splits(parent: Control, splits: PackedFloat32Array, reference: PackedFloat32Array) -> void:
	if splits.is_empty():
		return
	Ui.label(parent, "分段用时", 17, Ui.MUTED)
	var table := GridContainer.new()
	table.columns = 4
	table.add_theme_constant_override("h_separation", 15)
	parent.add_child(table)
	for index in range(splits.size()):
		var item := VBoxContainer.new()
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		table.add_child(item)
		Ui.label(item, "%d   %s" % [index + 1, Courses.time_text(splits[index])], 17)
		if index < reference.size():
			var difference := splits[index] - reference[index]
			Ui.label(item, "%+.2f 秒" % difference, 15, Ui.GREEN if difference <= 0.0 else Color("ffaa9d"))


func _record(id: StringName) -> float:
	var value := float(_settings.get_value(_record_section(), str(id), INF))
	return value if is_finite(value) and value > 0.0 else INF


func _record_splits(id: StringName) -> PackedFloat32Array:
	var value: Variant = _settings.get_value(_record_section() + "_splits", str(id), PackedFloat32Array())
	return value if value is PackedFloat32Array else PackedFloat32Array()


func _challenge_record(id: StringName) -> Dictionary:
	var value: Variant = _settings.get_value("challenge_records", str(id), {})
	return value if value is Dictionary else {}


func _record_section() -> String:
	return _record_section_for(_vehicle, _weather_mode)


func _record_section_for(vehicle: StringName, weather: StringName) -> String:
	var section := "long_route_records" if vehicle == Vehicles.DEFAULT else "long_route_records_%s" % vehicle
	return section if weather == WeatherModes.CLEAR else "%s_%s" % [section, weather]


func _silver_target(id: StringName) -> float:
	return _silver_target_for(id, _weather_mode)


func _silver_target_for(id: StringName, weather: StringName) -> float:
	return snappedf(Courses.DATA[id].target * WeatherModes.TIME_FACTORS[weather], 0.01)


func _has_desktop_window() -> bool:
	return DisplayServer.get_name() not in ["embedded", "headless"]


func _toggle_fullscreen() -> void:
	var window := get_window()
	var fullscreen := window.mode != Window.MODE_FULLSCREEN and window.mode != Window.MODE_EXCLUSIVE_FULLSCREEN
	window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	_settings.set_value("display", "fullscreen", fullscreen)
	_save_settings()


func _open_fullscreen_window() -> void:
	_save_world_progress()
	var process := OS.create_instance(["--path", ProjectSettings.globalize_path("res://"), "--fullscreen"])
	if process > 0:
		_quit_game()
	elif is_instance_valid(_power_label):
		_power_label.text = "无法打开独立窗口"


func _show_embedded_hint(rows: VBoxContainer) -> void:
	if DisplayServer.get_name() == "embedded":
		Ui.label(rows, "全屏请在独立游戏窗口中切换", 17, Ui.MUTED)


func _toggle_power_mode() -> void:
	_performance = (_performance + 1) % DeviceProfile.PRESETS.size()
	_apply_power_mode()
	_settings.set_value("display", "performance", _performance)
	_save_settings()
	_update_power_label()


func _apply_power_mode() -> void:
	DeviceProfile.apply(_performance, get_viewport())


func _update_power_label() -> void:
	if is_instance_valid(_power_label):
		_power_label.text = "X / P  画面模式    %s" % DeviceProfile.label(_performance)


func _clear_overlay() -> void:
	if is_instance_valid(_screen):
		_overlay.remove_child(_screen)
		_screen.queue_free()
		_screen = null
	_power_label = null
	_weather_button = null
	_lighting_button = null
	_motion_status = null
	_motion_toggle = null
	_motion_invert = null
	_pad_status = null
	_pad_live = null
	_vibration_toggle = null


func _build_overlay() -> void:
	_clear_overlay()
	_screen = Control.new()
	_screen.theme = _theme
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color("09131d4a") if _mode in [Mode.SELECT, Mode.HOME, Mode.PAINT] else Color("09131d99")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _panel(width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", Ui.panel(Ui.INK, Color("516981"), 1, 20))
	_screen.add_child(panel)
	return panel


func _center_menu(title: String, width := 384) -> VBoxContainer:
	_build_overlay()
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := _panel(width)
	panel.reparent(center, false)
	var layout := _rows(panel, 10)
	Ui.label(layout, title, 33, Ui.GREEN)
	return layout


func _rows(panel: Control, separation: int) -> VBoxContainer:
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", separation)
	panel.add_child(layout)
	return layout


