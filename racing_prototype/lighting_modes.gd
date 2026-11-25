extends RefCounted

const CYCLE := &"cycle"
const DAY := &"day"
const NIGHT := &"night"
const ORDER := [CYCLE, DAY, NIGHT]
const NAMES := {CYCLE: "昼夜循环", DAY: "白天", NIGHT: "夜晚"}

const DUSK_START := 9.0
const NIGHT_START := 19.0
const DAWN_START := 38.0
const DAY_START := 48.0
const CYCLE_LENGTH := 54.0


static func phase_at(mode: StringName, seconds: float) -> float:
	match mode:
		DAY: return 0.0
		NIGHT: return NIGHT_START
		_: return fposmod(seconds, CYCLE_LENGTH)


static func darkness_at(phase: float) -> float:
	return smoothstep(DUSK_START, NIGHT_START, phase) * (1.0 - smoothstep(DAWN_START, DAY_START, phase))


static func phase_name(phase: float) -> String:
	if phase >= DAY_START or phase < DUSK_START:
		return "白天"
	if phase < NIGHT_START:
		return "黄昏"
	if phase < DAWN_START:
		return "夜晚"
	return "黎明"
