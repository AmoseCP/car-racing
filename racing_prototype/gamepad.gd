extends RefCounted
## Controller helpers shared by the menus and the car: rumble, names and a
## live readout for the controller check screen.

## Player preference, loaded and saved by the garage.
static var vibration := true


static func rumble(weak: float, strong: float, seconds: float) -> void:
	if not vibration:
		return
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), seconds)


static func stop_rumble() -> void:
	for device in Input.get_connected_joypads():
		Input.stop_joy_vibration(device)


static func describe(device: int) -> String:
	var title := Input.get_joy_name(device).strip_edges()
	if title.is_empty():
		title = "未知手柄"
	return title if Input.is_joy_known(device) else "%s（未识别按键布局）" % title


static func connected_summary() -> String:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return "未检测到手柄"
	var names: PackedStringArray = []
	for device in pads:
		names.append(describe(device))
	return "已连接：" + "，".join(names)


## One line of live input from every controller, used to prove input arrives.
static func live_readout() -> String:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return "按任意手柄按键后，这里会显示实时输入。"
	var device: int = pads[0]
	var pressed: PackedStringArray = []
	var names := {
		JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_BACK: "视图", JOY_BUTTON_START: "菜单",
		JOY_BUTTON_DPAD_LEFT: "←", JOY_BUTTON_DPAD_RIGHT: "→", JOY_BUTTON_DPAD_UP: "↑", JOY_BUTTON_DPAD_DOWN: "↓",
	}
	for button: int in names:
		if Input.is_joy_button_pressed(device, button):
			pressed.append(names[button])
	return "左摇杆 %+.2f    RT %.2f    LT %.2f    按键 %s" % [
		Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT),
		Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT),
		" ".join(pressed) if not pressed.is_empty() else "—",
	]
