extends RefCounted

const BRIDGE_PATH := "res://racing_prototype/windows_motion.ps1"
const STARTUP_MS := 4500
const STALE_MS := 350

var _pid := -1
var _stdout: FileAccess
var _stderr: FileAccess
var _pending := ""
var _started_at := 0
var _sample_at := -1
var _gravity := Vector3.ZERO


func start(now: int) -> void:
	if not OS.has_feature("windows"):
		return
	var executable := OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	if not FileAccess.file_exists(executable):
		return
	var bridge := FileAccess.get_file_as_string(BRIDGE_PATH)
	if bridge.is_empty():
		return
	var command := "$gameProcessId = %d\n%s" % [OS.get_process_id(), bridge]
	var process := OS.execute_with_pipe(executable, ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", command], false)
	if process.is_empty():
		return
	_pid = process.pid
	_stdout = process.stdio
	_stderr = process.stderr
	_started_at = now


func poll(now: int) -> Vector3:
	if _pid < 0:
		return Vector3.ZERO
	_read_stdout(_stdout.get_buffer(1024).get_string_from_ascii(), now)
	_stderr.get_buffer(1024)
	if not OS.is_process_running(_pid):
		_pid = -1
		stop()
		return Vector3.ZERO
	if _sample_at >= 0 and now - _sample_at <= STALE_MS:
		return _gravity
	return Vector3.ZERO


func is_starting(now: int) -> bool:
	return _pid >= 0 and _sample_at < 0 and now - _started_at < STARTUP_MS


func stop() -> void:
	if _pid >= 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	_stdout = null
	_stderr = null
	_pending = ""
	_sample_at = -1
	_gravity = Vector3.ZERO


func _read_stdout(chunk: String, now: int) -> void:
	_pending += chunk
	var end := _pending.rfind("\n")
	if end < 0:
		if _pending.length() > 1024:
			_pending = ""
		return
	var lines := _pending.left(end).split("\n", false)
	_pending = _pending.substr(end + 1)
	for line in lines:
		var values := line.strip_edges().split(" ", false)
		if values.size() != 3 or not values[0].is_valid_float() or not values[1].is_valid_float() or not values[2].is_valid_float():
			continue
		var sample := Vector3(values[0].to_float(), values[1].to_float(), values[2].to_float())
		if sample.is_finite() and sample.length_squared() > 0.04:
			_gravity = sample
			_sample_at = now
