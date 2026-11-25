extends RefCounted

const INK := Color("101929f4")
const TEXT := Color("fff4dc")
const MUTED := Color("b8c6d9")
const GREEN := Color("64f5cb")
const UI_FONT := preload("res://racing_prototype/fonts/CarRacingUI.ttf")


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = UI_FONT
	theme.set_color("font_color", &"Label", TEXT)
	theme.set_color("font_color", &"Button", TEXT)
	theme.set_color("font_focus_color", &"Button", TEXT)
	theme.set_color("font_hover_color", &"Button", TEXT)
	theme.set_stylebox("normal", &"Button", panel(Color("1e3046"), Color.TRANSPARENT, 0))
	theme.set_stylebox("hover", &"Button", panel(Color("344961"), Color.TRANSPARENT, 0))
	theme.set_stylebox("pressed", &"Button", panel(Color("314c59"), GREEN, 2))
	var focus := panel(Color.TRANSPARENT, GREEN, 2)
	focus.draw_center = false
	theme.set_stylebox("focus", &"Button", focus)
	return theme


static func panel(background: Color, accent: Color, border := 0, padding := 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = accent
	style.set_border_width_all(border)
	style.set_corner_radius_all(8)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding * 0.65
	style.content_margin_bottom = padding * 0.65
	return style


static func label(parent: Node, caption: String, size: int, color := TEXT) -> Label:
	var result := Label.new()
	result.text = caption
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result


static func menu_button(parent: Control, caption: String, action: Callable, height := 53) -> Button:
	var button := Button.new()
	button.text = caption
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = height
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


static func link_vertical_buttons(buttons: Array[Button]) -> void:
	for i in range(buttons.size()):
		buttons[i].focus_neighbor_top = buttons[i].get_path_to(buttons[i - 1])
		buttons[i].focus_neighbor_bottom = buttons[i].get_path_to(buttons[(i + 1) % buttons.size()])
