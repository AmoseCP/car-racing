extends Node

const GROUP := &"car_racing_audio"
const CUES := {
	&"menu_move": [preload("res://racing_prototype/audio/menu_move.wav"), -17.0],
	&"menu_accept": [preload("res://racing_prototype/audio/menu_accept.wav"), -14.0],
	&"menu_back": [preload("res://racing_prototype/audio/menu_back.wav"), -15.0],
	&"ignition": [preload("res://racing_prototype/audio/ignition.wav"), -7.0],
	&"headlights": [preload("res://racing_prototype/audio/headlights.wav"), -10.0],
	&"reverse": [preload("res://racing_prototype/audio/reverse.wav"), -15.0],
	&"impact": [preload("res://racing_prototype/audio/impact.wav"), -6.0],
	&"violation": [preload("res://racing_prototype/audio/violation.wav"), -10.0],
	&"overtake": [preload("res://racing_prototype/audio/overtake.wav"), -12.0],
	&"region": [preload("res://racing_prototype/audio/region.wav"), -13.0],
	&"split": [preload("res://racing_prototype/audio/split.wav"), -14.0],
	&"boost": [preload("res://racing_prototype/audio/boost.wav"), -12.0],
	&"indicator": [preload("res://racing_prototype/audio/indicator.wav"), -17.0],
	&"finish": [preload("res://racing_prototype/audio/finish.wav"), -8.0],
	&"game_over": [preload("res://racing_prototype/audio/game_over.wav"), -9.0],
}

var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _last_menu_move := -1000
var _last_menu_transition := -1000


func _ready() -> void:
	if AudioServer.get_driver_name() == "Dummy":
		return
	add_to_group(GROUP)
	_last_menu_transition = Time.get_ticks_msec()
	for index in range(6):
		var voice := AudioStreamPlayer.new()
		voice.name = "Effect%d" % (index + 1)
		add_child(voice)
		_voices.append(voice)


static func play_from(source: Node, cue: StringName, gain_db: float = 0.0, pitch: float = 1.0) -> void:
	if not source.is_inside_tree():
		return
	var audio := source.get_tree().get_first_node_in_group(GROUP)
	if audio != null:
		audio.play_cue(cue, gain_db, pitch)


func play_cue(cue: StringName, gain_db: float = 0.0, pitch: float = 1.0) -> void:
	if _voices.is_empty():
		return
	var now := Time.get_ticks_msec()
	if cue == &"menu_move":
		if now - _last_menu_move < 58 or now - _last_menu_transition < 105:
			return
		_last_menu_move = now
	elif cue in [&"menu_accept", &"menu_back", &"finish", &"game_over", &"ignition"]:
		_last_menu_transition = now
	var choice := _next_voice
	for offset in range(_voices.size()):
		var index := (_next_voice + offset) % _voices.size()
		if not _voices[index].playing:
			choice = index
			break
	_next_voice = (choice + 1) % _voices.size()
	var voice := _voices[choice]
	var settings: Array = CUES[cue]
	voice.stop()
	voice.stream = settings[0]
	voice.volume_db = settings[1] + gain_db
	voice.pitch_scale = pitch
	voice.play()
