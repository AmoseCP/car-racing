extends RefCounted

const WorldClock := preload("res://racing_prototype/world_clock.gd")
const DYNAMIC := &"dynamic"
const CLEAR := &"clear"
const RAIN := &"rain"
const SNOW := &"snow"
const ORDER := [DYNAMIC, CLEAR, RAIN, SNOW]
const NAMES := {DYNAMIC: "动态天气", CLEAR: "晴天", RAIN: "雨天", SNOW: "雪天"}
const TIME_FACTORS := {DYNAMIC: 1.08, CLEAR: 1.0, RAIN: 1.14, SNOW: 1.29}

const PRECIPITATION_WINDOWS := [
	Vector2(65.0, 121.0), Vector2(120.0, 151.0),
	Vector2(54.0, 125.0), Vector2(44.0, 137.0),
]
const CYCLE_LENGTH := 180.0


static func at_time(mode: StringName, seconds: float) -> StringName:
	if mode != DYNAMIC:
		return mode
	var season := WorldClock.season_at(seconds)
	var phase := fposmod(fposmod(seconds, WorldClock.SEASON_SECONDS), CYCLE_LENGTH)
	var window: Vector2 = PRECIPITATION_WINDOWS[season]
	if phase < window.x or phase >= window.y:
		return CLEAR
	return SNOW if season == WorldClock.Season.WINTER else RAIN
