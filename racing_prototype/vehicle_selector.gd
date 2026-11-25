extends HBoxContainer

signal chosen(id: StringName)
signal cancelled

const Vehicles := preload("res://racing_prototype/vehicles.gd")
const Ui := preload("res://racing_prototype/ui_skin.gd")
const Preview := preload("res://racing_prototype/vehicle_preview.tscn")

var _preview: SubViewportContainer
var _role: Label
var _description: Label
var _boost: Label
var _speed: Label
var _acceleration: Label
var _stat_bars: Array[ProgressBar] = []


func setup(selected: StringName, from_pause: bool) -> void:
	add_theme_constant_override("separation", 22)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 253
	list.add_theme_constant_override("separation", 9)
	add_child(list)
	Ui.label(list, "当前赛车  %s" % Vehicles.DATA[selected].name, 17, Ui.MUTED)
	var buttons: Array[Button] = []
	var focus: Button
	for id in Vehicles.ORDER:
		var button := Ui.menu_button(list, Vehicles.DATA[id].name, chosen.emit.bind(id))
		button.focus_entered.connect(_show_vehicle.bind(id))
		button.mouse_entered.connect(button.grab_focus)
		buttons.append(button)
		if id == selected:
			focus = button
	buttons.append(Ui.menu_button(list, "返回", cancelled.emit))
	Ui.link_vertical_buttons(buttons)
	var guide := Ui.label(list, "A / Enter  确认  ·  B / Esc  返回", 15, Ui.MUTED)
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if from_pause:
		var notice := Ui.label(list, "换车后从起点重新开始。", 16, Ui.MUTED)
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var details := VBoxContainer.new()
	details.custom_minimum_size.x = 530
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 7)
	add_child(details)
	_preview = Preview.instantiate()
	details.add_child(_preview)
	_role = Ui.label(details, "", 26)
	_description = Ui.label(details, "", 17, Ui.TEXT)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.y = 48

	var metrics := GridContainer.new()
	metrics.columns = 2
	metrics.add_theme_constant_override("h_separation", 20)
	metrics.add_theme_constant_override("v_separation", 8)
	details.add_child(metrics)
	_speed = _add_stat(metrics, "极速", 60.0)
	_acceleration = _add_stat(metrics, "0–100 km/h", 25.0)
	_add_stat(metrics, "高速转向", 2.0)
	_add_stat(metrics, "制动", 42.0)
	_boost = Ui.label(details, "", 16, Ui.MUTED)
	focus.grab_focus()


func _show_vehicle(id: StringName) -> void:
	var profile: Dictionary = Vehicles.DATA[id]
	_preview.show_vehicle(id)
	_role.text = "%s · %s" % [profile.name, profile.type]
	_role.add_theme_color_override("font_color", profile.accent)
	_description.text = profile.description
	_speed.text = "晴天极速   %d km/h" % roundi(profile.top_speed * 3.6)
	_acceleration.text = "0–100 km/h   %.2f s" % (100.0 / 3.6 / profile.acceleration)
	_boost.text = "加速带   %.2f s · %d km/h" % [profile.boost_seconds, roundi(profile.boost_speed * 3.6)]
	var values := [profile.top_speed, profile.acceleration, profile.steering.y, profile.braking]
	var fill := Ui.panel(profile.accent, Color.TRANSPARENT, 0, 0)
	for i in range(_stat_bars.size()):
		_stat_bars[i].value = values[i]
		_stat_bars[i].add_theme_stylebox_override("fill", fill)


func _add_stat(metrics: GridContainer, caption: String, maximum: float) -> Label:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 3)
	metrics.add_child(column)
	var label := Ui.label(column, caption, 15, Ui.TEXT)
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 6
	bar.max_value = maximum
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", Ui.panel(Color("26384b"), Color.TRANSPARENT, 0, 0))
	column.add_child(bar)
	_stat_bars.append(bar)
	return label
