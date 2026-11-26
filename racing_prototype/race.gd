extends Node3D

signal finished(total_time: float)
signal challenge_finished(reason: String)

const Courses := preload("res://racing_prototype/courses.gd")
const Vehicles := preload("res://racing_prototype/vehicles.gd")
const WeatherModes := preload("res://racing_prototype/weather_modes.gd")
const RaceWeather := preload("res://racing_prototype/race_weather.gd")
const LightingModes := preload("res://racing_prototype/lighting_modes.gd")
const RaceLighting := preload("res://racing_prototype/race_lighting.gd")
const Traffic := preload("res://racing_prototype/traffic.gd")
const WorldClock := preload("res://racing_prototype/world_clock.gd")
const RaceMap := preload("res://racing_prototype/race_map.gd")
const Dashboard := preload("res://racing_prototype/dashboard.gd")
const SpeedLines := preload("res://racing_prototype/speed_lines.gd")
const DrivingChallenge := preload("res://racing_prototype/driving_challenge.gd")
const Rivals := preload("res://racing_prototype/rivals.gd")
const Units := preload("res://racing_prototype/units.gd")
const COUNTDOWN_SECONDS := 3.0
const Ui := preload("res://racing_prototype/ui_skin.gd")
const Art := preload("res://racing_prototype/track_art.gd")
const Audio := preload("res://racing_prototype/game_audio.gd")
const PAD_WIDTH := 1.85
const AUTO_HEADLIGHT_DARKNESS := 0.46
const MAX_ROAD_SCORE := 100
const SECONDS_PER_POINT := 0.4
const VIOLATION_COLOR := Color("ffaa9d")
const GHOST_STEP := 0.1

@export var weather_mode: StringName = WeatherModes.DYNAMIC
@export var lighting_mode: StringName = LightingModes.CYCLE
## Grid start against AI opponents (ignored in driving challenges).
@export var rivals_enabled := false

var world_clock := WorldClock.new()
var challenge_id: StringName
var challenge: DrivingChallenge
var road_score := MAX_ROAD_SCORE
var violation_count := 0
var _season := -1
var _last_position: Vector3
var _next_gate := 0
var _lap := 0
var _elapsed := 0.0
var _best := INF
var _split_start := 0.0
var _splits := PackedFloat32Array()
var _reference_splits := PackedFloat32Array()
var _checkpoints: Array[Transform3D]
var _done := false
var _used_pads := 0
var _using_pad := false
var _lap_label: Label
var _time_label: Label
var _split_label: Label
var _dashboard: Dashboard
var _weather_label: Label
var _lighting_label: Label
var _score_label: Label
var _map: RaceMap
var _road_panel: PanelContainer
var _road_label: Label
var _road_hint := ""
var _violation_text := ""
var _violation_notice := 0.0
var _notice_color := VIOLATION_COLOR
var _controls: Label
## Seconds of driving with a controller; the control hint hides after a while.
var _hint_seconds := 0.0
var _manual_headlights := false
var _rivals: Rivals
var _player_covered := 0.0
var _player_progress := 0.0
var _finish_position := 0
var _countdown := 0.0
var _go_flash := 0.0
var _countdown_label: Label
var _rank_label: Label
var _ghost: Node3D
var _ghost_positions := PackedVector3Array()
var _ghost_headings := PackedFloat32Array()
var _record_positions := PackedVector3Array()
var _record_headings := PackedFloat32Array()

@onready var _track: Node3D = $Track
@onready var _car: CharacterBody3D = $Car
@onready var _camera: Camera3D = $ChaseCamera
@onready var _hud: CanvasLayer = $HUD
@onready var _weather: RaceWeather = $Weather
@onready var _lighting: RaceLighting = $Lighting
@onready var _traffic: Traffic = $Traffic


func _ready() -> void:
	var spawn: Transform3D = _track.spawn_transform()
	_checkpoints = _track.gates
	if DrivingChallenge.DATA.has(challenge_id):
		challenge = DrivingChallenge.new()
		challenge.configure(challenge_id, _track)
		spawn = challenge.start
		_checkpoints = challenge.checkpoints
		challenge.add_finish_marker(self, _track.half_road)
	_car.set_spawn(spawn)
	_camera.snap_to_car()
	_last_position = _car.position
	_apply_environment()
	_weather.configure(weather_mode, _environment_time())
	_car.weather = _weather
	_lighting.configure(lighting_mode)
	_update_season()
	_update_lighting()
	_traffic.configure(_track, _car, challenge_id == DrivingChallenge.OVERTAKE)
	_traffic.violation.connect(_apply_violation)
	if rivals_enabled and challenge == null:
		_rivals = Rivals.new()
		_rivals.name = "Rivals"
		add_child(_rivals)
		_rivals.configure(_track, _traffic, _car)
	_car.drift_finished.connect(_on_drift_finished)
	_using_pad = not Input.get_connected_joypads().is_empty()
	_build_hud()
	_start_grid()


func _physics_process(delta: float) -> void:
	if _done:
		return
	_advance_countdown(delta)
	if _lap > 0 or challenge != null:
		_elapsed += delta
	if _lap > 0 and challenge == null:
		_record_ghost_frame()
	world_clock.seconds += delta
	_update_season()
	_weather.advance(_environment_time(), delta)
	_update_lighting()
	_road_hint = _traffic.advance(delta, _weather.speed_factor, _lighting.darkness >= AUTO_HEADLIGHT_DARKNESS)
	if _rivals != null:
		var player := _traffic.player_location()
		_player_covered += fposmod(player.x - _player_progress + _track.road_length() * 0.5,
			_track.road_length()) - _track.road_length() * 0.5
		_player_progress = player.x
		_rivals.advance(delta, _weather.speed_factor, player)
	if _done:
		return
	_violation_notice = maxf(_violation_notice - delta, 0.0)
	var here := _car.position
	if challenge != null:
		_update_challenge(here)
	elif _crossed(_checkpoints[_next_gate], here, _track.half_road + 1.6):
		if _next_gate == 0:
			_finish_crossed()
		else:
			_record_split()
			_next_gate = (_next_gate + 1) % _checkpoints.size()
	if challenge == null and not _done and _car.speed > 2.0:
		for i in range(_track.boost_pads.size()):
			var flag := 1 << i
			if (_used_pads & flag) == 0 and _crossed(_track.boost_pads[i], here, PAD_WIDTH):
				_used_pads |= flag
				_car.activate_boost()
	_last_position = here


func _process(delta: float) -> void:
	_update_hint_visibility(delta)
	if challenge == null:
		_time_label.text = "用时 %s    纪录 %s" % [Courses.time_text(_elapsed), Courses.time_text(_best)]
	else:
		var remaining := maxf(0.0, challenge.profile.limit - _elapsed)
		_time_label.text = "用时 %s    剩余 %s" % [Courses.time_text(_elapsed), Courses.time_text(remaining)]
	_update_weather_label()
	_update_lighting_label()
	_update_road_hud()
	_map.update_checkpoint(_next_gate)
	_place_ghost()
	_update_race_position()


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
		Audio.play_from(self, &"ignition")
	elif event.is_action_pressed(&"race_lights"):
		_manual_headlights = true
		_car.toggle_headlights()
		_update_lighting_label()
		get_viewport().set_input_as_handled()


func restart() -> void:
	_hint_seconds = 0.0
	_car.respawn()
	_camera.snap_to_car()
	_last_position = _car.position
	_next_gate = 0
	_lap = 0
	_elapsed = 0.0
	_split_start = 0.0
	_splits.clear()
	_record_positions.clear()
	_record_headings.clear()
	_split_label.hide()
	_done = false
	_used_pads = 0
	if challenge != null:
		challenge.reset()
	_weather.reset(_environment_time())
	_manual_headlights = false
	_update_season()
	_update_lighting()
	_traffic.reset()
	_start_grid()
	road_score = MAX_ROAD_SCORE
	violation_count = 0
	_road_hint = ""
	_violation_notice = 0.0
	_update_weather_label()
	_update_lighting_label()
	_update_road_hud()
	_update_progress_label()


func set_record(time: float, splits := PackedFloat32Array()) -> void:
	_best = time
	_reference_splits = splits


## Replays a previous run as a translucent car. Empty data removes the ghost.
func set_ghost(data: Dictionary) -> void:
	_ghost_positions = data.get("positions", PackedVector3Array())
	_ghost_headings = data.get("headings", PackedFloat32Array())
	if _ghost_positions.size() < 2 or _ghost_positions.size() != _ghost_headings.size():
		_ghost_positions = PackedVector3Array()
		if is_instance_valid(_ghost):
			_ghost.queue_free()
		_ghost = null
		return
	if not is_instance_valid(_ghost):
		_ghost = Vehicles.instantiate_model(_car.vehicle_id)
		_ghost.name = "Ghost"
		add_child(_ghost)
		_fade_ghost(_ghost)
		var tag := Label3D.new()
		tag.text = "最佳纪录"
		tag.font = Ui.UI_FONT
		tag.font_size = 40
		tag.pixel_size = 0.01
		tag.modulate = Color(Ui.GREEN, 0.8)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position.y = 2.3
		_ghost.add_child(tag)
	_place_ghost()


func ghost_recording() -> Dictionary:
	return {"positions": _record_positions.duplicate(), "headings": _record_headings.duplicate()}


## Finishing position against rivals (0 when racing alone).
func finishing_position() -> int:
	return _finish_position


func racer_count() -> int:
	return 1 + (_rivals.racers.size() if _rivals != null else 0)


func split_times() -> PackedFloat32Array:
	return _splits


func set_hud_visible(value: bool) -> void:
	_hud.visible = value


func penalty_seconds() -> float:
	return (MAX_ROAD_SCORE - road_score) * SECONDS_PER_POINT


func elapsed_seconds() -> float:
	return _elapsed


func _apply_violation(message: String, points: int) -> void:
	if _done:
		return
	var deduction := mini(road_score, points)
	road_score -= deduction
	violation_count += 1
	_violation_text = "%s  −%d 分" % [message, deduction] if deduction > 0 else message
	_violation_notice = 3.2
	_notice_color = VIOLATION_COLOR
	if not message.begins_with("碰撞"):
		Audio.play_from(self, &"violation")
	if challenge != null:
		_finish_challenge(message)


func _on_drift_finished(seconds: float, gained: float) -> void:
	if _done or _violation_notice > 0.0 and _notice_color == VIOLATION_COLOR:
		return
	_violation_text = "漂移 %.1f 秒  ·  氮气 +%d%%" % [seconds, roundi(gained * 100.0)]
	_violation_notice = 1.8
	_notice_color = Ui.GREEN


func _start_grid() -> void:
	_finish_position = 0
	_go_flash = 0.0
	if _rivals == null:
		return
	_rivals.reset()
	_player_progress = _traffic.player_location().x
	_player_covered = _rivals.from_start(_player_progress)
	_countdown = COUNTDOWN_SECONDS
	_car.controls_locked = true
	if is_instance_valid(_countdown_label):
		_countdown_label.show()


func _advance_countdown(delta: float) -> void:
	if _countdown > 0.0:
		var shown := ceili(_countdown)
		_countdown -= delta
		if _countdown <= 0.0:
			_car.controls_locked = false
			_rivals.started = true
			_go_flash = 0.9
			Audio.play_from(self, &"split", 2.0, 1.6)
		elif ceili(_countdown) != shown or is_equal_approx(_countdown + delta, COUNTDOWN_SECONDS):
			Audio.play_from(self, &"split", 0.0, 0.8)
	elif _go_flash > 0.0:
		_go_flash -= delta


func _update_race_position() -> void:
	if not is_instance_valid(_countdown_label):
		return
	_countdown_label.visible = _countdown > 0.0 or _go_flash > 0.0
	if _countdown > 0.0:
		_countdown_label.text = str(ceili(_countdown))
		_countdown_label.add_theme_color_override("font_color", Ui.TEXT)
	elif _go_flash > 0.0:
		_countdown_label.text = "GO!"
		_countdown_label.add_theme_color_override("font_color", Ui.GREEN)
	if _rivals != null:
		var rank := _finish_position if _finish_position > 0 else _rivals.rank_for(_player_covered)
		_rank_label.text = "名次 %d / %d" % [rank, racer_count()]


func _record_ghost_frame() -> void:
	while _record_positions.size() * GHOST_STEP <= _elapsed:
		_record_positions.append(_car.global_position)
		_record_headings.append(_car.global_rotation.y)


func _place_ghost() -> void:
	if not is_instance_valid(_ghost):
		return
	var step := _elapsed / GHOST_STEP if _lap > 0 else 0.0
	var index := floori(step)
	if index >= _ghost_positions.size() - 1:
		_ghost.visible = false
		return
	var weight := step - index
	_ghost.visible = true
	_ghost.global_position = _ghost_positions[index].lerp(_ghost_positions[index + 1], weight)
	_ghost.global_rotation = Vector3(0.0, lerp_angle(_ghost_headings[index], _ghost_headings[index + 1], weight), 0.0)


static func _fade_ghost(node: Node) -> void:
	if node is GeometryInstance3D and not node is Label3D:
		node.transparency = 0.62
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_fade_ghost(child)


func _environment_time() -> float:
	return world_clock.seconds if challenge == null else 0.0


func _update_lighting() -> void:
	_lighting.advance(_environment_time(), _weather.rain_strength, _weather.snow_strength, _season)
	if not _manual_headlights:
		_car.set_headlights(_lighting.darkness >= AUTO_HEADLIGHT_DARKNESS)


func _update_season() -> void:
	var season := WorldClock.season_at(_environment_time())
	if season == _season:
		return
	_season = season
	_weather.set_season(season)
	_track.set_foliage_tint(WorldClock.FOLIAGE_TINT[season])


func _crossed(gate: Transform3D, here: Vector3, half_width: float) -> bool:
	var local := gate.affine_inverse()
	var previous := local * _last_position
	var current := local * here
	if previous.z <= 0.0 or current.z > 0.0:
		return false
	var crossing_x := lerpf(previous.x, current.x, previous.z / (previous.z - current.z))
	return absf(crossing_x) <= half_width


func _finish_crossed() -> void:
	if _lap > 0:
		_record_split()
	if _lap == Courses.LAP_COUNT:
		_record_positions.append(_car.global_position)
		_record_headings.append(_car.global_rotation.y)
		if _rivals != null:
			_finish_position = _rivals.final_rank(_rivals.clock + penalty_seconds())
		_done = true
		_car.stop_audio()
		var result := _elapsed + penalty_seconds()
		_best = minf(_best, result)
		_lap_label.text = "比赛完成 · %s" % Courses.time_text(result)
		finished.emit(result)
		return
	_lap += 1
	_used_pads = 0
	_next_gate = 1
	_update_progress_label()


func _update_challenge(here: Vector3) -> void:
	var verdict := challenge.check_position(_traffic, _track, _car)
	if not verdict.is_empty():
		_finish_challenge(verdict)
		return
	if _car.is_on_wall():
		_finish_challenge("碰到护栏或障碍物")
		return
	if _elapsed >= challenge.profile.limit:
		_finish_challenge("超出挑战时限")
		return
	if _crossed(_checkpoints[_next_gate], here, _track.half_road):
		_record_split()
		if _next_gate == _checkpoints.size() - 1:
			var missing_passes := challenge_id == DrivingChallenge.OVERTAKE and challenge.passed_count < 2
			_finish_challenge("抵达终点时尚未完成两次超车" if missing_passes else "")
			return
		_next_gate += 1
	_update_progress_label()


func _finish_challenge(reason: String) -> void:
	_done = true
	_car.stop_audio()
	challenge_finished.emit(reason)


func _update_progress_label() -> void:
	if challenge_id == DrivingChallenge.OVERTAKE:
		_lap_label.text = "已超车 %d / 2" % challenge.passed_count
	elif challenge != null:
		_lap_label.text = "检查点 %d / %d" % [_next_gate, _checkpoints.size()]
	elif _lap == 0:
		_lap_label.text = "等待发车" if _rivals != null else "驶过起点开始计时"
	else:
		_lap_label.text = "第 %d / %d 圈" % [_lap, Courses.LAP_COUNT]


func _record_split() -> void:
	var time := _elapsed - _split_start
	_split_start = _elapsed
	var index := _splits.size()
	_splits.append(time)
	Audio.play_from(self, &"split")
	var message := "第 %d 段  %s" % [index + 1, Courses.time_text(time)]
	var color := Ui.MUTED
	if index < _reference_splits.size():
		var difference := time - _reference_splits[index]
		message += "  %+.2f 秒" % difference
		color = Ui.GREEN if difference <= 0.0 else VIOLATION_COLOR
	_split_label.text = message
	_split_label.add_theme_color_override("font_color", color)
	_split_label.show()


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
	var streaks := SpeedLines.new()
	streaks.name = "SpeedLines"
	layout.add_child(streaks)
	streaks.configure(_car)

	var timing := _hud_panel(layout)
	timing.position = Vector2(24, 24)
	var timing_rows := timing.get_child(0)
	var accent: Color = _track.course.accent
	var title: String = _track.course.name if challenge == null else challenge.profile.title
	Ui.label(timing_rows, title, 28, accent)
	Ui.label(timing_rows, Vehicles.DATA[_car.vehicle_id].name, 16, Ui.MUTED)
	_weather_label = Ui.label(timing_rows, "", 16, Ui.GREEN)
	_update_weather_label()
	_lighting_label = Ui.label(timing_rows, "", 16, Ui.MUTED)
	_update_lighting_label()
	_score_label = Ui.label(timing_rows, "", 17, Ui.GREEN)
	_rank_label = Ui.label(timing_rows, "", 20, Ui.GREEN)
	_rank_label.visible = _rivals != null
	_lap_label = Ui.label(timing_rows, "", 20)
	_update_progress_label()
	_time_label = Ui.label(timing_rows, "用时 00:00.00    纪录 --:--.--", 17, Ui.MUTED)
	_split_label = Ui.label(timing_rows, "", 17, Ui.MUTED)
	_split_label.hide()

	_countdown_label = Ui.label(layout, "", 120)
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_countdown_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_constant_override("outline_size", 14)
	_countdown_label.add_theme_color_override("font_outline_color", Color("101929"))
	_countdown_label.hide()
	_dashboard = Dashboard.new()
	_dashboard.name = "Dashboard"
	layout.add_child(_dashboard)
	_dashboard.configure(_car, accent)
	_dashboard.dock_bottom_center(14.0)

	_road_panel = _hud_panel(layout)
	_road_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_road_panel.offset_left = -183
	_road_panel.offset_right = 183
	_road_panel.offset_top = 24
	_road_label = Ui.label(_road_panel.get_child(0), "", 21)
	_road_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_update_road_hud()

	var controls := _hud_panel(layout)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.offset_left = 24
	controls.offset_bottom = -24
	controls.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_controls = Ui.label(controls.get_child(0), "", 16)
	_update_control_hint()

	var map_panel := _hud_panel(layout)
	map_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	map_panel.offset_right = -24
	map_panel.offset_bottom = -24
	map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_map = RaceMap.new()
	_map.name = "RouteMap"
	map_panel.get_child(0).add_child(_map)
	var finish_index := 0 if challenge == null else _checkpoints.size() - 1
	_map.configure(_track, _car, _traffic, _checkpoints, finish_index)
	if _rivals != null:
		_map.rivals = _rivals.racers


func _update_weather_label() -> void:
	_weather_label.text = "%s  ·  %s  ·  极速 %d mph" % [
		WorldClock.NAMES[_season], WeatherModes.NAMES[_weather.stage], Units.mph(_car.current_top_speed())]


func _update_lighting_label() -> void:
	var light := "车灯开" if _car.headlights_on else "车灯关"
	_lighting_label.text = "%s  ·  %s" % [_lighting.phase_name, light]


func _update_road_hud() -> void:
	_score_label.text = "驾驶分 %d / %d" % [road_score, MAX_ROAD_SCORE]
	var alert := _violation_notice > 0.0
	_road_label.text = _violation_text if alert else _road_hint
	_road_label.add_theme_color_override("font_color", _notice_color if alert else Ui.TEXT)
	_road_panel.visible = not _road_label.text.is_empty()


func _update_hint_visibility(delta: float) -> void:
	# On handhelds and gamepads the hint panel only matters at the start.
	if absf(_car.speed) > 1.0:
		_hint_seconds += delta
	var panel := _controls.get_parent().get_parent() as Control
	panel.visible = not _using_pad or _hint_seconds < 8.0


func _update_control_hint() -> void:
	_hint_seconds = 0.0
	if _using_pad:
		_controls.text = "RT 油门    LT 刹车 / 倒车    LB 刹车\n左摇杆 转向    A 手刹    B 氮气\nX 车灯    视图键 视角    Y 重试    菜单键 暂停"
	else:
		_controls.text = "W / ↑ 油门    S / ↓ 刹车 / 倒车    空格 刹车\nA D / ← → 转向    Q 手刹    Shift 氮气\nH 车灯    C 视角    R 重试    Esc 暂停"


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
