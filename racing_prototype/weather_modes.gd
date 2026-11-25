extends RefCounted

const DYNAMIC := &"dynamic"
const CLEAR := &"clear"
const RAIN := &"rain"
const SNOW := &"snow"
const ORDER := [DYNAMIC, CLEAR, RAIN, SNOW]
const NAMES := {DYNAMIC: "动态天气", CLEAR: "晴天", RAIN: "雨天", SNOW: "雪天"}
const TIME_FACTORS := {DYNAMIC: 1.08, CLEAR: 1.0, RAIN: 1.14, SNOW: 1.29}

const RAIN_START := 12.0
const SNOW_START := 28.0
const CYCLE_LENGTH := 50.0


static func at_time(mode: StringName, seconds: float) -> StringName:
	if mode != DYNAMIC:
		return mode
	var phase := fposmod(seconds, CYCLE_LENGTH)
	if phase < RAIN_START:
		return CLEAR
	if phase < SNOW_START:
		return RAIN
	return SNOW
