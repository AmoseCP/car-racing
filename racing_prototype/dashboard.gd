extends Control
## Bottom-centre instrument cluster: tachometer with drive state, speedometer,
## optional speed-limit sign, headlight / boost lamps and pedal input bars.

const Ui := preload("res://racing_prototype/ui_skin.gd")
const Vehicles := preload("res://racing_prototype/vehicles.gd")
const SIZE := Vector2(400, 146)
const RADIUS := 60.0
const TACH_CENTER := Vector2(84, 76)
const SPEEDO_CENTER := Vector2(316, 76)
const COLUMN_X := 200.0
const START_ANGLE := PI * 0.75
const SWEEP := PI * 1.5
const IDLE_RPM := 900.0
const TOP_RPM := 7000.0
const REDLINE_RPM := 7500.0
const MAX_RPM := 8000.0
const IDLE_REV := 0.63
const TOP_REV := 1.62
const WARNING := Color("ff8f78")
const RING := Color("3a4a5f")
const FACE := Color("070d16b0")
const LAMP_OFF := Color("27344a")
const HEADLIGHT := Color("8fc8ff")
const NITRO := Color("5fb8ff")
const FUEL := Color("ffc861")

## Posted limit in km/h; 0 hides the sign and the dial marker.
var speed_limit := 0
## Colours the speed readout as a warning (e.g. outside the legal band).
var speed_warning := false
## Fuel level 0..1; negative hides the fuel bar.
var fuel := -1.0

var _car: CharacterBody3D
var _accent := Ui.GREEN
var _dial_max := 240.0
var _boost_seconds := 1.0
var _speed_shown := 0.0
var _rpm_shown := IDLE_RPM
var _time := 0.0
var _font: Font = Ui.UI_FONT
var _backdrop := Ui.panel(Ui.INK, Color.TRANSPARENT)


func configure(car: CharacterBody3D, accent: Color) -> void:
	_car = car
	_accent = accent
	var profile: Dictionary = Vehicles.DATA[car.vehicle_id]
	_dial_max = ceilf(profile.boost_speed * 3.6 / 40.0) * 40.0
	_boost_seconds = profile.boost_seconds
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func dock_bottom_center(margin: float) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -SIZE.x * 0.5
	offset_right = SIZE.x * 0.5
	offset_top = -SIZE.y - margin
	offset_bottom = -margin


func _process(delta: float) -> void:
	if _car == null or not is_visible_in_tree():
		return
	_time += delta
	_speed_shown = lerpf(_speed_shown, absf(_car.speed) * 3.6, 1.0 - exp(-14.0 * delta))
	var rpm: float = IDLE_RPM + (_car.engine_rev() - IDLE_REV) / (TOP_REV - IDLE_REV) * (TOP_RPM - IDLE_RPM)
	if absf(_car.speed) < 0.3:
		rpm += sin(_time * 21.0) * 30.0
	_rpm_shown = lerpf(_rpm_shown, clampf(rpm, 0.0, MAX_RPM), 1.0 - exp(-10.0 * delta))
	queue_redraw()


func _draw() -> void:
	if _car == null:
		return
	draw_style_box(_backdrop, Rect2(Vector2.ZERO, size))
	_draw_tachometer()
	_draw_speedometer()
	_draw_column()


func _draw_tachometer() -> void:
	var center := TACH_CENTER
	var fraction := _rpm_shown / MAX_RPM
	var hot := _rpm_shown >= REDLINE_RPM
	_draw_face(center)
	draw_arc(center, RADIUS - 6.0, _angle(REDLINE_RPM / MAX_RPM), _angle(1.0), 10, WARNING, 4.0, true)
	for step in range(17):
		var major := step % 2 == 0
		var thousand := step * 500.0
		var color := WARNING if thousand >= REDLINE_RPM else Ui.MUTED
		_draw_tick(center, step / 16.0, 10.0 if major else 5.0, color, 2.0 if major else 1.0)
		if major:
			_draw_centered(_polar(center, RADIUS - 20.0, _angle(step / 16.0)), str(step / 2), 12, color)
	_draw_value_arc(center, fraction, WARNING if hot else _accent)
	_draw_pointer(center, fraction, WARNING if hot else Ui.TEXT)
	_draw_centered(center + Vector2(0, 2), _gear(), 30, WARNING if hot else Ui.TEXT)
	_draw_centered(center + Vector2(0, 50), "×1000 RPM", 10, Ui.MUTED)


func _draw_speedometer() -> void:
	var center := SPEEDO_CENTER
	var fraction := _speed_shown / _dial_max
	var color := WARNING if speed_warning else _accent
	_draw_face(center)
	var steps := roundi(_dial_max / 10.0)
	for step in range(steps + 1):
		var major := step % 2 == 0
		_draw_tick(center, float(step) / steps, 10.0 if major else 5.0, Ui.MUTED, 2.0 if major else 1.0)
		if step % 4 == 0:
			_draw_centered(_polar(center, RADIUS - 20.0, _angle(float(step) / steps)), str(step * 10), 11, Ui.MUTED)
	if speed_limit > 0:
		var mark := _angle(speed_limit / _dial_max)
		var direction := Vector2.from_angle(mark)
		var side := direction.orthogonal() * 4.0
		var tip := center + direction * (RADIUS + 1.0)
		draw_colored_polygon(PackedVector2Array([
			tip, tip + direction * 8.0 + side, tip + direction * 8.0 - side]), WARNING)
	_draw_value_arc(center, fraction, color)
	_draw_pointer(center, fraction, color if speed_warning else Ui.TEXT)
	_draw_centered(center + Vector2(0, 2), "%03d" % roundi(_speed_shown), 28, color)
	_draw_centered(center + Vector2(0, 50), "KM/H", 10, Ui.MUTED)


func _draw_column() -> void:
	var y := 40.0
	if speed_limit > 0:
		var sign_center := Vector2(COLUMN_X, 30)
		draw_circle(sign_center, 20.0, Color("f7f3ea"), true, -1.0, true)
		draw_arc(sign_center, 17.5, 0.0, TAU, 40, Color("e2332a"), 4.5, true)
		_draw_centered(sign_center, str(speed_limit), 16 if speed_limit < 100 else 13, Color("15171c"))
		y = 56.0
	var boost := clampf(_car.boost_time / _boost_seconds, 0.0, 1.0)
	if _car.nitro_active:
		boost = 1.0
	_draw_lamp(Vector2(COLUMN_X - 26.0, y + 10.0), "车灯", HEADLIGHT, 1.0 if _car.headlights_on else 0.0)
	_draw_lamp(Vector2(COLUMN_X + 26.0, y + 10.0), "加速", Ui.GREEN, boost)
	y += 26.0
	var nitro_caption := "漂移" if _car.drifting else "氮气"
	var nitro_color := NITRO.lightened(0.35) if _car.nitro >= 1.0 or _car.drifting else NITRO
	_draw_bar(y, nitro_caption, nitro_color, _car.nitro, Ui.GREEN if _car.drifting else Ui.MUTED)
	y += 15.0
	if fuel >= 0.0:
		var low := fuel < 0.2
		_draw_bar(y, "燃油", WARNING if low else FUEL, fuel, WARNING if low else Ui.MUTED)
		y += 15.0
	_draw_bar(y, "油门", Ui.GREEN, maxf(0.0, _car.throttle), Ui.MUTED, 6.0)
	_draw_bar(y + 12.0, "刹车", WARNING, maxf(0.0, -_car.throttle), Ui.MUTED, 6.0)


func _draw_face(center: Vector2) -> void:
	draw_circle(center, RADIUS + 3.0, FACE, true, -1.0, true)
	draw_arc(center, RADIUS, START_ANGLE, START_ANGLE + SWEEP, 64, RING, 3.0, true)


func _draw_tick(center: Vector2, fraction: float, length: float, color: Color, width: float) -> void:
	var angle := _angle(fraction)
	draw_line(_polar(center, RADIUS - 2.0 - length, angle), _polar(center, RADIUS - 2.0, angle), color, width, true)


func _draw_value_arc(center: Vector2, fraction: float, color: Color) -> void:
	if fraction > 0.004:
		draw_arc(center, RADIUS, START_ANGLE, _angle(fraction), 48, color, 4.0, true)


func _draw_pointer(center: Vector2, fraction: float, color: Color) -> void:
	var angle := _angle(fraction)
	draw_line(_polar(center, RADIUS * 0.52, angle), _polar(center, RADIUS + 2.0, angle), color, 3.0, true)


func _draw_lamp(center: Vector2, caption: String, color: Color, level: float) -> void:
	var rect := Rect2(center - Vector2(23, 9), Vector2(46, 18))
	var lit := level > 0.0
	var fill := LAMP_OFF.lerp(color.darkened(0.35), level) if lit else LAMP_OFF
	draw_rect(rect, fill, true, -1.0, true)
	if lit:
		draw_rect(rect, color, false, 1.5, true)
	_draw_centered(center, caption, 12, Ui.TEXT if lit else Color("6f7d90"))


func _draw_bar(top: float, caption: String, color: Color, level: float, caption_color: Color,
		thickness := 8.0) -> void:
	var left := COLUMN_X - 49.0
	_draw_text(Vector2(left, top + 9.0), caption, 11, caption_color)
	var bar := Rect2(left + 27.0, top + (12.0 - thickness) * 0.5 + 1.0, 71.0, thickness)
	draw_rect(bar, LAMP_OFF, true, -1.0, true)
	if level > 0.01:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(level, 0.0, 1.0), bar.size.y)), color, true, -1.0, true)


func _gear() -> String:
	if _car.speed < -0.3:
		return "R"
	if absf(_car.speed) < 0.3 and absf(_car.throttle) < 0.05:
		return "N"
	return "D"


func _angle(fraction: float) -> float:
	return START_ANGLE + SWEEP * clampf(fraction, 0.0, 1.0)


func _polar(center: Vector2, radius: float, angle: float) -> Vector2:
	return center + Vector2.from_angle(angle) * radius


func _draw_centered(center: Vector2, text: String, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := center.y + (_font.get_ascent(font_size) - _font.get_descent(font_size)) * 0.5
	draw_string(_font, Vector2(center.x - width * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_text(baseline: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
