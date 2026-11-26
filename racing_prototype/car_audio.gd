extends Node

const Audio := preload("res://racing_prototype/game_audio.gd")
const ENGINE := preload("res://racing_prototype/audio/engine.wav")
const ROAD := preload("res://racing_prototype/audio/road.wav")
const GRAVEL := preload("res://racing_prototype/audio/gravel.wav")
const SKID := preload("res://racing_prototype/audio/skid.wav")
const RAIN := preload("res://racing_prototype/audio/rain.wav")
const ENGINE_TUNING := {&"gt": 1.0, &"rally": 1.10, &"prototype": 1.23, &"truck": 0.68}

var _engine: AudioStreamPlayer
var _road: AudioStreamPlayer
var _gravel: AudioStreamPlayer
var _skid: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _tuning := 1.0
var _reverse := false
var _last_impact := -1000
var _can_play := false

@onready var _car: CharacterBody3D = get_parent()


func _ready() -> void:
	_can_play = AudioServer.get_driver_name() != "Dummy"
	_tuning = ENGINE_TUNING.get(_car.vehicle_id, 1.0)
	_engine = _loop("Engine", ENGINE)
	_road = _loop("Tires", ROAD)
	_gravel = _loop("Gravel", GRAVEL)
	_skid = _loop("Skid", SKID)
	_rain = _loop("Rain", RAIN)
	if _can_play:
		_car.impact.connect(_on_impact)


func advance(delta: float, drive: float, steer: float) -> void:
	if not _can_play:
		return
	var speed := absf(_car.speed)
	var reverse: bool = _car.speed < -0.6
	if reverse and not _reverse:
		Audio.play_from(self, &"reverse")
	_reverse = reverse
	var load := maxf(0.0, -drive if reverse else drive)
	var ratio := clampf(speed / maxf(1.0, _car.current_top_speed()), 0.0, 1.15)
	var rpm: float = _tuning * _car.engine_rev()
	var wet := float(_car.weather.audible_rain()) if _car.weather else 0.0
	var snow := float(_car.weather.snow_strength) if _car.weather else 0.0
	var roll := smoothstep(0.75, 41.0, speed)
	var rough := 1.0 if _car.rough_surface else 0.26 * snow
	var braking := maxf(0.0, drive if reverse else -drive)
	var brake_noise := braking * smoothstep(3.0, 28.0, speed)
	var lateral_noise := absf(steer) * smoothstep(12.0, 32.0, speed)
	var drift_noise := smoothstep(0.08, 0.4, absf(_car.slip)) * smoothstep(6.0, 20.0, speed)
	var scrub := maxf(maxf(brake_noise * 0.7, lateral_noise), drift_noise)
	var blend := 1.0 - exp(-8.0 * delta)
	_mix(_engine, 0.18 + 0.19 * load + 0.09 * ratio, rpm, blend)
	_mix(_road, roll * (1.0 - rough) * (0.18 + 0.12 * wet), 0.74 + roll * 0.36, blend)
	_mix(_gravel, roll * rough * 0.35, 0.85 + roll * 0.22, blend)
	_mix(_skid, scrub * (0.38 - 0.10 * snow), 0.90 + 0.17 * ratio, blend)
	_mix(_rain, wet * 0.62, 1.0, blend)


func silence() -> void:
	for player in [_engine, _road, _gravel, _skid, _rain]:
		player.stop()
		player.volume_db = -70.0
	_reverse = false


func _on_impact(speed: float) -> void:
	var now := Time.get_ticks_msec()
	if speed < 1.9 or now - _last_impact < 280:
		return
	_last_impact = now
	var intensity := smoothstep(1.9, 34.0, speed)
	Audio.play_from(self, &"impact", lerpf(-10.0, 1.5, intensity), lerpf(1.19, 0.72, intensity))


func _loop(node_name: String, source: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_begin = 0
	stream.loop_end = roundi(source.get_length() * source.mix_rate)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	player.stream = stream
	player.volume_db = -70.0
	add_child(player)
	return player


func _mix(player: AudioStreamPlayer, target_gain: float, pitch: float, blend: float) -> void:
	var gain := lerpf(db_to_linear(player.volume_db), target_gain, blend)
	player.volume_db = linear_to_db(maxf(gain, 0.00031))
	player.pitch_scale = lerpf(player.pitch_scale, pitch, blend)
	if target_gain > 0.006 and not player.playing:
		player.play()
	elif target_gain <= 0.006 and gain < 0.006 and player.playing:
		player.stop()
