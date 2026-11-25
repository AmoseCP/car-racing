extends Node

enum Mode { SELECT, DRIVE, PAUSE, RESULTS, MOTION, VEHICLE, WEATHER, LIGHTING }

const Courses := preload("res://racing_prototype/courses.gd")
const Ui := preload("res://racing_prototype/ui_skin.gd")
const WeatherModes := preload("res://racing_prototype/weather_modes.gd")
const LightingModes := preload("res://racing_prototype/lighting_modes.gd")
const Vehicles := preload("res://racing_prototype/vehicles.gd")
const VehicleSelector := preload("res://racing_prototype/vehicle_selector.gd")
const RaceScene := preload("res://racing_prototype/red_mesa.tscn")
const MotionSteering := preload("res://racing_prototype/motion_steering.gd")
const SAVE_PATH := "user://racing_records.cfg"
const FULLSCREEN_LABEL := "全屏 / 窗口    F11"

var _settings := ConfigFile.new()
var _theme: Theme
var _mode := Mode.SELECT
var _selected: StringName = &"desert"
var _loaded: StringName
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
var _low_power := false
var _motion_return := Mode.SELECT
var _motion_status: Label
var _motion_toggle: Button
var _motion_invert: Button

@onready var _overlay: CanvasLayer = $Overlay
@onready var _motion: MotionSteering = $MotionSteering


func _ready() -> void:
	_settings.load(SAVE_PATH)
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
	_low_power = bool(_settings.get_value("display", "battery_saver", false))
	_apply_power_mode()
	_theme = Ui.make_theme()
	_motion.state_changed.connect(_refresh_motion_settings)
	_motion.reversed = bool(_settings.get_value("controls", "motion_invert", false))
	_motion.set_enabled(bool(_settings.get_value("controls", "motion_steering", false)))
	var fullscreen_default := OS.has_feature("windows") and not OS.has_feature("editor")
	if _has_desktop_window() and bool(_settings.get_value("display", "fullscreen", fullscreen_default)):
		get_window().mode = Window.MODE_FULLSCREEN
	_show_selector()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"race_fullscreen") and _has_desktop_window():
		_toggle_fullscreen()
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
		else:
			return
	elif event.is_action_pressed(&"race_back") and _mode in [Mode.PAUSE, Mode.MOTION, Mode.VEHICLE, Mode.WEATHER, Mode.LIGHTING]:
		if _mode == Mode.MOTION:
			_close_motion_settings()
		elif _mode == Mode.VEHICLE:
			_close_vehicle_selector()
		elif _mode == Mode.WEATHER:
			_close_weather_selector()
		elif _mode == Mode.LIGHTING:
			_close_lighting_selector()
		else:
			_resume()
	elif event.is_action_pressed(&"race_motion_center") and _motion.enabled:
		_recenter_motion()
	elif event.is_action_pressed(&"race_power") and _mode != Mode.DRIVE:
		_toggle_power_mode()
	else:
		return
	get_viewport().set_input_as_handled()


func _show_selector() -> void:
	_mode = Mode.SELECT
	get_tree().paused = true
	_build_overlay()
	var menu := _panel(420)
	menu.position = Vector2(26, 26)
	var rows := _rows(menu, 7)
	Ui.label(rows, "CAR RACING", 37)
	Ui.label(rows, "选择赛道 · 两圈计时", 22, Ui.GREEN)
	var buttons: Array[Button] = []
	var focus: Button
	for id in Courses.ORDER:
		var data: Dictionary = Courses.DATA[id]
		var button := Ui.menu_button(rows, "%s    %s" % [data.name, data.banner], _start_course.bind(id), 46)
		button.focus_entered.connect(_preview_course.bind(id))
		button.mouse_entered.connect(button.grab_focus)
		buttons.append(button)
		if id == _selected:
			focus = button
	buttons.append(Ui.menu_button(rows, "赛车选择    %s" % Vehicles.DATA[_vehicle].name, _show_vehicle_selector, 46))
	if _has_desktop_window():
		buttons.append(Ui.menu_button(rows, FULLSCREEN_LABEL, _toggle_fullscreen, 46))
	buttons.append(Ui.menu_button(rows, "体感设置", _show_motion_settings, 46))
	buttons.append(Ui.menu_button(rows, "退出游戏", get_tree().quit, 46))
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
	Ui.label(detail_rows, "从起点出发，跑完两圈。压过青色箭头可短暂加速。", 16, Ui.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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


func _load_course(id: StringName) -> void:
	if _loaded == id and _loaded_vehicle == _vehicle and _loaded_weather == _weather_mode and _loaded_lighting == _lighting_mode and is_instance_valid(_race):
		return
	if is_instance_valid(_race):
		remove_child(_race)
		_race.queue_free()
	_race = RaceScene.instantiate()
	_race.name = "Race"
	_race.process_mode = Node.PROCESS_MODE_PAUSABLE
	_race.get_node("Track").course_id = id
	_race.get_node("Car").motion_steering = _motion
	_race.get_node("Car").vehicle_id = _vehicle
	_race.weather_mode = _weather_mode
	_race.lighting_mode = _lighting_mode
	_race.finished.connect(_show_results)
	_loaded = id
	_loaded_vehicle = _vehicle
	_loaded_weather = _weather_mode
	_loaded_lighting = _lighting_mode
	add_child(_race)
	_race.set_record(_record(id))


func _start_course(id: StringName) -> void:
	_selected = id
	_load_course(id)
	_settings.set_value("display", "last_course", str(id))
	_settings.save(SAVE_PATH)
	_restart()


func _restart() -> void:
	_race.restart()
	_resume()


func _resume() -> void:
	_mode = Mode.DRIVE
	_clear_overlay()
	_race.set_hud_visible(true)
	get_tree().paused = false


func _show_pause() -> void:
	_mode = Mode.PAUSE
	get_tree().paused = true
	var rows := _center_menu("比赛暂停")
	var buttons: Array[Button] = [
		Ui.menu_button(rows, "继续比赛", _resume), Ui.menu_button(rows, "重新开始", _restart),
	]
	if _has_desktop_window():
		buttons.append(Ui.menu_button(rows, FULLSCREEN_LABEL, _toggle_fullscreen))
	buttons.append(Ui.menu_button(rows, "体感设置", _show_motion_settings))
	buttons.append(Ui.menu_button(rows, "天气    %s" % WeatherModes.NAMES[_weather_mode], _show_weather_selector))
	buttons.append(Ui.menu_button(rows, "昼夜    %s" % LightingModes.NAMES[_lighting_mode], _show_lighting_selector))
	buttons.append(Ui.menu_button(rows, "更换赛车", _show_vehicle_selector))
	buttons.append(Ui.menu_button(rows, "更换赛道", _show_selector))
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
	var description := Ui.label(rows, "动态天气会在赛中变换。雨天极速降低 15%，雪天降低 30%。", 18, Ui.MUTED)
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
		_settings.save(SAVE_PATH)
		if _weather_return == Mode.PAUSE:
			_load_course(_loaded)
	_close_weather_selector()


func _close_weather_selector() -> void:
	if _weather_return == Mode.PAUSE:
		_show_pause()
	else:
		_show_selector()


func _show_lighting_selector() -> void:
	_lighting_return = _mode
	_mode = Mode.LIGHTING
	var rows := _center_menu("昼夜设置", 472)
	var description := Ui.label(rows, "天黑时车灯会自动亮起。比赛中按 H 或手柄 X 手动开关。", 18, Ui.MUTED)
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
		_settings.save(SAVE_PATH)
		if _lighting_return == Mode.PAUSE:
			_load_course(_loaded)
	_close_lighting_selector()


func _close_lighting_selector() -> void:
	if _lighting_return == Mode.PAUSE:
		_show_pause()
	else:
		_show_selector()


func _show_vehicle_selector() -> void:
	_vehicle_return = _mode
	_mode = Mode.VEHICLE
	var rows := _center_menu("选择赛车", 860)
	var selector := VehicleSelector.new()
	selector.name = "VehicleSelector"
	rows.add_child(selector)
	selector.chosen.connect(_select_vehicle)
	selector.cancelled.connect(_close_vehicle_selector)
	selector.setup(_vehicle, _vehicle_return == Mode.PAUSE)


func _select_vehicle(id: StringName) -> void:
	if id != _vehicle:
		_vehicle = id
		_settings.set_value("garage", "vehicle", str(id))
		_settings.save(SAVE_PATH)
		if _vehicle_return == Mode.PAUSE:
			_load_course(_loaded)
	_close_vehicle_selector()


func _close_vehicle_selector() -> void:
	if _vehicle_return == Mode.PAUSE:
		_show_pause()
	else:
		_show_selector()


func _show_motion_settings() -> void:
	_motion_return = _mode
	_mode = Mode.MOTION
	var rows := _center_menu("体感转向", 470)
	var instructions := Ui.label(rows, "像转方向盘一样扭动掌机。按平常姿势握住后，用 R3 / G 校准中位。", 18, Ui.MUTED)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_motion_status = Ui.label(rows, "", 18, Ui.GREEN)
	_motion_toggle = Ui.menu_button(rows, "", _toggle_motion)
	var recenter := Ui.menu_button(rows, "校准中位", _recenter_motion)
	_motion_invert = Ui.menu_button(rows, "", _invert_motion)
	var back := Ui.menu_button(rows, "返回", _close_motion_settings)
	Ui.link_vertical_buttons([_motion_toggle, recenter, _motion_invert, back])
	_refresh_motion_settings()
	_motion_toggle.grab_focus()


func _close_motion_settings() -> void:
	if _motion_return == Mode.PAUSE:
		_show_pause()
	else:
		_show_selector()


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
	_settings.save(SAVE_PATH)


func _refresh_motion_settings() -> void:
	if not is_instance_valid(_motion_status):
		return
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
	var old_record := _record(_loaded)
	var new_record := total < old_record
	if new_record:
		_settings.set_value(_record_section(), str(_loaded), total)
		_settings.save(SAVE_PATH)
		_race.set_record(total)
	var data: Dictionary = Courses.DATA[_loaded]
	var target := _silver_target(_loaded)
	var medal := Courses.medal_for(total, target)
	var rows := _center_menu("比赛完成")
	Ui.label(rows, "%s   %s" % [Courses.MEDAL_NAMES[medal], Courses.time_text(total)], 44, Courses.MEDAL_COLORS[medal])
	Ui.label(rows, "%s · %s · %s" % [data.name, Vehicles.DATA[_vehicle].name, WeatherModes.NAMES[_weather_mode]], 18, Ui.MUTED)
	if medal != Courses.Medal.GOLD:
		var next_target := Courses.gold_target(target) if medal == Courses.Medal.SILVER else target
		Ui.label(rows, "距%s还差 %s" % [Courses.MEDAL_NAMES[medal + 1], Courses.time_text(total - next_target)], 17, Ui.MUTED)
	var caption := "刷新个人纪录" if new_record else "个人纪录  %s" % Courses.time_text(old_record)
	Ui.label(rows, caption, 18, Ui.GREEN)
	var buttons: Array[Button] = [
		Ui.menu_button(rows, "再跑一次", _restart), Ui.menu_button(rows, "更换赛道", _show_selector),
	]
	Ui.link_vertical_buttons(buttons)
	buttons[0].grab_focus()


func _record(id: StringName) -> float:
	var value := float(_settings.get_value(_record_section(), str(id), INF))
	return value if is_finite(value) and value > 0.0 else INF


func _record_section() -> String:
	var section := "records" if _vehicle == Vehicles.DEFAULT else "records_%s" % _vehicle
	return section if _weather_mode == WeatherModes.CLEAR else "%s_%s" % [section, _weather_mode]


func _silver_target(id: StringName) -> float:
	return snappedf(Courses.DATA[id].target * WeatherModes.TIME_FACTORS[_weather_mode], 0.01)


func _has_desktop_window() -> bool:
	return DisplayServer.get_name() not in ["embedded", "headless"]


func _toggle_fullscreen() -> void:
	var window := get_window()
	var fullscreen := window.mode != Window.MODE_FULLSCREEN and window.mode != Window.MODE_EXCLUSIVE_FULLSCREEN
	window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	_settings.set_value("display", "fullscreen", fullscreen)
	_settings.save(SAVE_PATH)


func _show_embedded_hint(rows: VBoxContainer) -> void:
	if DisplayServer.get_name() == "embedded":
		Ui.label(rows, "全屏请在独立游戏窗口中切换", 17, Ui.MUTED)


func _toggle_power_mode() -> void:
	_low_power = not _low_power
	_apply_power_mode()
	_settings.set_value("display", "battery_saver", _low_power)
	_settings.save(SAVE_PATH)
	_update_power_label()


func _apply_power_mode() -> void:
	Engine.max_fps = 30 if _low_power else 60
	get_viewport().scaling_3d_scale = 0.72 if _low_power else 1.0
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if _low_power else Viewport.MSAA_2X


func _update_power_label() -> void:
	if is_instance_valid(_power_label):
		var state := "省电 30 FPS" if _low_power else "流畅 60 FPS"
		_power_label.text = "X / P  切换帧率    %s" % state


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


func _build_overlay() -> void:
	_clear_overlay()
	_screen = Control.new()
	_screen.theme = _theme
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color("09131d4a") if _mode == Mode.SELECT else Color("09131d99")
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


