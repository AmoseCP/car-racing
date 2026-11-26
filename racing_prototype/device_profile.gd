extends RefCounted
## Platform hints: Windows handheld detection and the performance presets.

const SMOOTH := 0
const BALANCED := 1
const SAVER := 2

const PRESETS := {
	SMOOTH: {"name": "流畅", "fps": 60, "scale": 1.0, "msaa": Viewport.MSAA_2X},
	BALANCED: {"name": "均衡", "fps": 40, "scale": 0.85, "msaa": Viewport.MSAA_DISABLED},
	SAVER: {"name": "省电", "fps": 30, "scale": 0.72, "msaa": Viewport.MSAA_DISABLED},
}


## Windows handhelds (ROG Ally, Legion Go, MSI Claw…) pair a touch screen with
## built-in controls. Pass --handheld after -- on the command line to test.
static func is_handheld() -> bool:
	if "--handheld" in OS.get_cmdline_user_args():
		return true
	return OS.get_name() == "Windows" and DisplayServer.is_touchscreen_available() and (
		not Input.get_connected_joypads().is_empty())


static func default_performance() -> int:
	return BALANCED if is_handheld() else SMOOTH


static func apply(preset: int, viewport: Viewport) -> void:
	var data: Dictionary = PRESETS[preset]
	Engine.max_fps = data.fps
	viewport.scaling_3d_scale = data.scale
	viewport.msaa_3d = data.msaa


static func label(preset: int) -> String:
	var data: Dictionary = PRESETS[preset]
	return "%s %d FPS" % [data.name, data.fps]
