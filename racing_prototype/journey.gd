extends Node3D

signal ended(report: Dictionary)

const Track := preload("res://racing_prototype/journey_track.gd")
const Traffic := preload("res://racing_prototype/journey_traffic.gd")
const JourneyMap := preload("res://racing_prototype/journey_map.gd")
const Courses := preload("res://racing_prototype/courses.gd")
const Art := preload("res://racing_prototype/track_art.gd")
const Ui := preload("res://racing_prototype/ui_skin.gd")
const Weather := preload("res://racing_prototype/race_weather.gd")
const WeatherModes := preload("res://racing_prototype/weather_modes.gd")
const Lighting := preload("res://racing_prototype/race_lighting.gd")
const LightingModes := preload("res://racing_prototype/lighting_modes.gd")
const Clock := preload("res://racing_prototype/world_clock.gd")
const Audio := preload("res://racing_prototype/game_audio.gd")
const Dashboard := preload("res://racing_prototype/dashboard.gd")
const SpeedLines := preload("res://racing_prototype/speed_lines.gd")
const HIT_THRESHOLD := 2.8
const OVER_LIMIT := 11
const UNDER_LIMIT := 10
const SPEED_CHECK_SECONDS := 1.2
const SPEED_REPEAT_SECONDS := 4.0
const START_GRACE_SECONDS := 3.5
const TRAFFIC_GRACE_SECONDS := 2.5
## Metres per tank at gentle throttle; full throttle and nitro burn faster.
const FUEL_RANGE := 3000.0
const REFUEL_PER_SECOND := 0.34
const REFUEL_SPEED_KMH := 30.0
const STREAK_STEP := 400.0
const STREAK_LEVELS := 8

enum SpeedState { LEGAL, FAST, SLOW }

var world_clock := Clock.new()
var weather_mode: StringName = WeatherModes.DYNAMIC
var lighting_mode: StringName = LightingModes.CYCLE
var health := 100.0
var distance := 0.0
var elapsed := 0.0
var violations := 0
var collisions := 0
var overtakes := 0
var fuel := 1.0
var streak_bonus := 0.0
var best_multiplier := 1.0
var _clean_distance := 0.0
var _refueling := false
var _done := false
var _manual_lights := false
var _using_pad := false
var _season := -1
var _current_biome: StringName
var _notice := ""
var _notice_color := Ui.GREEN
var _notice_time := 0.0
var _road_hint := ""
var _impact_cooldown := 0.0
var _speed_limit := 0
var _speed_state := SpeedState.LEGAL
var _speed_check_time := 0.0
var _slow_grace := START_GRACE_SECONDS
var _distance_label: Label
var _biome_label: Label
var _score_label: Label
var _health_label: Label
var _streak_label: Label
var _health_bar: ProgressBar
var _conditions: Label
var _dashboard: Dashboard
var _controls: Label
var _alert_panel: PanelContainer
var _alert: Label
var _condition_display := StyleBoxFlat.new()

@onready var _car: CharacterBody3D = $Car
@onready var _track: Track = $Track
@onready var _traffic: Traffic = $Traffic
@onready var _camera: Camera3D = $ChaseCamera
@onready var _weather: Weather = $Weather
@onready var _lighting: Lighting = $Lighting
@onready var _hud: CanvasLayer = $HUD


func _ready() -> void:
	_configure_environment()
	_weather.configure(weather_mode, world_clock.seconds, _track.weather_materials)
	_lighting.configure(lighting_mode)
	_car.weather = _weather
	_car.impact.connect(_on_impact)
	_car.drift_finished.connect(_on_drift_finished)
	_car.set_spawn(_spawn_pose())
	_traffic.configure(_track, _car)
	_traffic.violation.connect(_on_violation)
	_traffic.overtake.connect(_on_overtake)
	_using_pad = not Input.get_connected_joypads().is_empty()
	_update_climate(0.0)
	_current_biome = _track.biome(0.0)
	_speed_limit = _track.speed_limit(0.0)
	_camera.snap_to_car()
	_build_hud()


func _physics_process(delta: float) -> void:
	if _done:
		return
	elapsed += delta
	world_clock.seconds += delta
	_notice_time = maxf(0.0, _notice_time - delta)
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	var location := _track.road_location(_car.position)
	var shift := _track.stream(location.x)
	if shift != 0.0:
		_car.position.z += shift
		_car.reset_physics_interpolation()
	_update_climate(delta)
	_road_hint = _traffic.advance(delta, _lighting.darkness >= 0.46, _weather.speed_factor)
	var previous_distance := distance
	_update_progress(location)
	_update_streak(distance - previous_distance)
	_update_fuel(location, delta)
	_check_speed_limit(location, delta)
	var departure := absf(location.y) - Track.HALF_ROAD
	_car.speed_multiplier = lerpf(0.63, 1.0, health * 0.01) if fuel > 0.0 else 0.0
	_car.rough_surface = departure > 0.55
	if _car.rough_surface:
		_car.speed_multiplier *= 0.48
		_road_hint = "驶离路面 · 车况下降"
		if departure > 2.1 or absf(_car.speed) > 8.0:
			health = maxf(0.0, health - delta * (9.0 if departure > 5.0 else 4.0))
			if health <= 0.0:
				_finish("车辆驶离公路后严重损坏")
	if fuel <= 0.0 and absf(_car.speed) < 0.5:
		_finish("燃油耗尽，车辆停在路边")
	if location.x < -155.0 or absf(location.y) > 135.0 or _car.position.y < -3.0:
		health = 0.0
		_finish("车辆冲出了公路范围")


func _process(_delta: float) -> void:
	_refresh_hud()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and _using_pad:
		_using_pad = false
		_update_controls()
	elif not _using_pad and ((event is InputEventJoypadButton and event.pressed) or (
			event is InputEventJoypadMotion and absf(event.axis_value) > 0.25)):
		_using_pad = true
		_update_controls()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"race_lights"):
		_manual_lights = true
		_car.toggle_headlights()
		get_viewport().set_input_as_handled()


func restart() -> void:
	_track.reset()
	_car.set_spawn(_spawn_pose())
	_car.speed_multiplier = 1.0
	_car.set_physics_process(true)
	_traffic.reset()
	_camera.snap_to_car()
	health = 100.0
	distance = 0.0
	elapsed = 0.0
	violations = 0
	collisions = 0
	overtakes = 0
	fuel = 1.0
	streak_bonus = 0.0
	best_multiplier = 1.0
	_clean_distance = 0.0
	_refueling = false
	_impact_cooldown = 0.0
	_speed_limit = _track.speed_limit(0.0)
	_speed_state = SpeedState.LEGAL
	_speed_check_time = 0.0
	_slow_grace = START_GRACE_SECONDS
	_notice_time = 0.0
	_road_hint = ""
	_current_biome = _track.biome(0.0)
	_done = false
	_manual_lights = false
	_weather.reset(world_clock.seconds)
	_update_climate(0.0)
	_refresh_hud()


func set_hud_visible(value: bool) -> void:
	_hud.visible = value


func score() -> int:
	return maxi(0, floori(distance) + (_track.sections_reached(distance) - 1) * 120 +
		overtakes * 35 - violations * 60 - collisions * 30 + floori(streak_bonus))


## Score multiplier earned by driving without violations or collisions.
func streak_multiplier() -> float:
	return 1.0 + mini(STREAK_LEVELS, floori(_clean_distance / STREAK_STEP)) * 0.25


func _spawn_pose() -> Transform3D:
	var pose := _track.road_pose(0.0, _track.lane_offset(0))
	pose.origin.y = 0.05
	return pose


func _update_progress(location: Vector2) -> void:
	if absf(location.y) <= Track.HALF_ROAD:
		distance = maxf(distance, location.x)
	var biome := _track.biome(location.x)
	if biome != _current_biome:
		_current_biome = biome
		_notify("驶入%s" % Courses.DATA[biome].name, Ui.GREEN)
		Audio.play_from(self, &"region")


func _check_speed_limit(location: Vector2, delta: float) -> void:
	var limit := _track.speed_limit(location.x)
	if limit != _speed_limit:
		_speed_limit = limit
		_speed_state = SpeedState.LEGAL
		_speed_check_time = 0.0
	var minimum := limit - UNDER_LIMIT
	var on_road := absf(location.y) <= Track.HALF_ROAD
	var speed_kmh := absf(_car.speed) * 3.6
	var next_limit := _track.speed_limit(location.x + 30.0)
	var slowing_for_sign := next_limit < limit and speed_kmh >= next_limit - UNDER_LIMIT
	var near_station := _track.next_station(location.x) < 70.0 and (fuel < 0.98 or _refueling)
	if on_road and distance >= 2.0:
		if slowing_for_sign or near_station or _traffic.needs_to_slow(location, minimum):
			_slow_grace = TRAFFIC_GRACE_SECONDS
		else:
			_slow_grace = maxf(0.0, _slow_grace - delta)
	var state := SpeedState.LEGAL
	if on_road:
		if speed_kmh >= limit + OVER_LIMIT:
			state = SpeedState.FAST
		elif speed_kmh <= minimum and distance >= 2.0 and _slow_grace <= 0.0 and _car.speed >= 0.0 and (
				_car.current_top_speed() * 3.6 > minimum):
			state = SpeedState.SLOW
	if state != _speed_state:
		_speed_state = state
		_speed_check_time = SPEED_CHECK_SECONDS
	if state != SpeedState.LEGAL:
		_speed_check_time -= delta
		if _speed_check_time <= 0.00001:
			var difference := roundi(absf(speed_kmh - limit))
			var label := "超速" if state == SpeedState.FAST else "低于限速"
			_on_violation("%s %d km/h" % [label, difference])
			_speed_check_time = SPEED_REPEAT_SECONDS
	if _road_hint.is_empty():
		var ahead := _track.speed_limit(location.x + 62.0)
		if ahead < limit:
			_road_hint = "前方限速 %d km/h" % ahead


func _on_drift_finished(seconds: float, gained: float) -> void:
	if _notice_time <= 0.0:
		_notify("漂移 %.1f 秒  ·  氮气 +%d%%" % [seconds, roundi(gained * 100.0)], Ui.GREEN)


func _update_streak(gained: float) -> void:
	if gained <= 0.0:
		return
	var before := streak_multiplier()
	streak_bonus += gained * (before - 1.0)
	_clean_distance += gained
	var after := streak_multiplier()
	if after > before:
		best_multiplier = maxf(best_multiplier, after)
		_notify("守规连击  ×%.2f" % after, Ui.GREEN)
		Audio.play_from(self, &"overtake", 0.0, 1.25)


func _break_streak() -> void:
	if streak_multiplier() > 1.0:
		_notice += "  ·  连击中断"
	_clean_distance = 0.0


func _update_fuel(location: Vector2, delta: float) -> void:
	var burn := absf(_car.speed) * delta / FUEL_RANGE * (1.0 + 0.6 * maxf(0.0, _car.throttle))
	if _car.nitro_active:
		burn *= 2.2
	fuel = maxf(0.0, fuel - burn)
	var refueling := _track.in_station(location) and absf(_car.speed) * 3.6 < REFUEL_SPEED_KMH and fuel < 1.0
	if refueling:
		fuel = minf(1.0, fuel + REFUEL_PER_SECOND * delta)
		if fuel >= 1.0:
			_notify("油箱已加满", Ui.GREEN)
			Audio.play_from(self, &"split")
	_refueling = refueling
	if not _road_hint.is_empty():
		return
	if _refueling:
		_road_hint = "加油中  %d%%" % floori(fuel * 100.0)
	elif _track.in_station(location) and fuel < 0.98:
		_road_hint = "减速到 %d km/h 以下加油" % roundi(REFUEL_SPEED_KMH)
	elif fuel < 0.55:
		var ahead := _track.next_station(location.x)
		if ahead < 320.0:
			_road_hint = "前方 %d m 加油站 · 驶入右侧车道" % roundi(ahead)
		elif fuel < 0.18:
			_road_hint = "燃油不足"


func _on_impact(closing_speed: float) -> void:
	if _done or closing_speed < HIT_THRESHOLD or (_impact_cooldown > 0.0 and closing_speed < 32.0):
		return
	_impact_cooldown = 0.52
	collisions += 1
	var damage := clampf(ceilf(100.0 * pow((closing_speed - HIT_THRESHOLD) / 31.5, 1.55)), 3.0, 100.0)
	health = maxf(0.0, health - damage)
	_notify("碰撞 · 车况 −%d%%" % roundi(damage), Color("ff9d8a"))
	_break_streak()
	if health <= 0.0:
		_finish("高速碰撞，车辆报废" if damage >= 100.0 else "车辆累积损坏后报废")


func _on_violation(message: String) -> void:
	violations += 1
	_notify("%s  −60 分" % message, Color("ffae96"))
	_break_streak()
	Audio.play_from(self, &"violation")


func _on_overtake() -> void:
	overtakes += 1
	_notify("安全超车  +35 分", Ui.GREEN)
	Audio.play_from(self, &"overtake")


func _notify(message: String, color: Color) -> void:
	_notice = message
	_notice_color = color
	_notice_time = 3.2


func _finish(reason: String) -> void:
	if _done:
		return
	_done = true
	_update_progress(_track.road_location(_car.position))
	_car.speed = 0.0
	_car.velocity = Vector3.ZERO
	_car.set_physics_process(false)
	_car.stop_audio()
	var points := score()
	var rating := "初试公路"
	if points >= 3400 and violations <= 2:
		rating = "长途行家"
	elif points >= 1900:
		rating = "公路熟手"
	elif points >= 700:
		rating = "稳步前行"
	_refresh_hud()
	ended.emit({
		"reason": reason, "score": points, "rating": rating, "distance": distance,
		"sections": _track.sections_reached(distance), "time": elapsed, "violations": violations,
		"collisions": collisions, "overtakes": overtakes, "best_multiplier": best_multiplier,
	})


func _configure_environment() -> void:
	var world: WorldEnvironment = $WorldEnvironment
	var environment := world.environment.duplicate() as Environment
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = Art.DAY_SKY
	sky.sky_material = panorama
	environment.sky = sky
	world.environment = environment


func _update_climate(delta: float) -> void:
	var season := Clock.season_at(world_clock.seconds)
	if season != _season:
		_season = season
		_weather.set_season(season)
	_weather.advance(world_clock.seconds, delta)
	_lighting.advance(world_clock.seconds, _weather.rain_strength, _weather.snow_strength, season)
	if not _manual_lights:
		_car.set_headlights(_lighting.darkness >= 0.46)


func _build_hud() -> void:
	var layout := Control.new()
	layout.theme = Ui.make_theme()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var streaks := SpeedLines.new()
	streaks.name = "SpeedLines"
	layout.add_child(streaks)
	streaks.configure(_car)

	var dashboard := _panel(layout)
	dashboard.position = Vector2(24, 24)
	var rows := dashboard.get_child(0)
	_biome_label = Ui.label(rows, "", 28, Ui.GREEN)
	_distance_label = Ui.label(rows, "", 22)
	_score_label = Ui.label(rows, "", 19, Ui.MUTED)
	_streak_label = Ui.label(rows, "", 17, Ui.GREEN)
	_health_label = Ui.label(rows, "", 19)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(202, 9)
	_health_bar.show_percentage = false
	_health_bar.add_theme_stylebox_override("background", Ui.panel(Color("30394d"), Color.TRANSPARENT, 0, 0))
	_condition_display.set_corner_radius_all(5)
	_health_bar.add_theme_stylebox_override("fill", _condition_display)
	rows.add_child(_health_bar)
	_conditions = Ui.label(rows, "", 16, Ui.MUTED)

	_dashboard = Dashboard.new()
	_dashboard.name = "Dashboard"
	layout.add_child(_dashboard)
	_dashboard.configure(_car, Ui.GREEN)
	_dashboard.dock_bottom_center(14.0)

	_alert_panel = _panel(layout)
	_alert_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_alert_panel.offset_left = -158
	_alert_panel.offset_right = 158
	_alert_panel.offset_top = 24
	_alert = Ui.label(_alert_panel.get_child(0), "", 21)
	_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var control_panel := _panel(layout)
	control_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	control_panel.offset_left = 24
	control_panel.offset_bottom = -24
	control_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_controls = Ui.label(control_panel.get_child(0), "", 16, Ui.MUTED)
	_update_controls()

	var map_panel := _panel(layout)
	map_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	map_panel.offset_right = -24
	map_panel.offset_bottom = -24
	map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var map := JourneyMap.new()
	map.name = "HighwayMap"
	map_panel.get_child(0).add_child(map)
	map.configure(_track, _traffic, _car)
	_refresh_hud()


func _refresh_hud() -> void:
	_biome_label.text = Courses.DATA[_current_biome].name
	_distance_label.text = "里程 %.2f km" % (distance * 0.001)
	_score_label.text = "得分 %d     安全超车 %d" % [score(), overtakes]
	var multiplier := streak_multiplier()
	if multiplier >= 1.0 + STREAK_LEVELS * 0.25:
		_streak_label.text = "守规连击 ×%.2f  ·  已满级" % multiplier
	else:
		var to_next := STREAK_STEP - fmod(_clean_distance, STREAK_STEP)
		_streak_label.text = "守规连击 ×%.2f  ·  再 %d m 升级" % [multiplier, ceili(to_next)]
	_streak_label.add_theme_color_override("font_color", Ui.GREEN if multiplier > 1.0 else Ui.MUTED)
	_dashboard.fuel = fuel
	_health_label.text = "车况 %d%%" % ceili(health)
	_health_bar.value = health
	_condition_display.bg_color = Ui.GREEN.lerp(Color("ff705e"), 1.0 - health * 0.01)
	_conditions.text = "%s · %s · %s" % [Clock.NAMES[_season], WeatherModes.NAMES[_weather.stage], _lighting.phase_name]
	_dashboard.speed_limit = _speed_limit
	_dashboard.speed_warning = _speed_state != SpeedState.LEGAL
	var message := _notice if _notice_time > 0.0 else _road_hint
	if _alert.text != message:
		_alert.text = message
		_alert.add_theme_color_override("font_color", _notice_color if _notice_time > 0.0 else Ui.TEXT)
	_alert_panel.visible = not message.is_empty()


func _update_controls() -> void:
	if _using_pad:
		_controls.text = "RT 油门    LT 刹车 / 倒车    左摇杆 转向\nA 手刹    B 氮气    X 车灯    视图键 视角    菜单键 暂停"
	else:
		_controls.text = "W / ↑ 油门    S / ↓ 刹车 / 倒车    A D / ← → 转向\n空格 手刹    Shift 氮气    H 车灯    C 视角    Esc 暂停"


func _panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", Ui.panel(Ui.INK, Color.TRANSPARENT))
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 4)
	panel.add_child(rows)
	parent.add_child(panel)
	return panel
