extends RefCounted

enum Season { SPRING, SUMMER, AUTUMN, WINTER }

const SEASON_SECONDS := 600.0
const YEAR_SECONDS := SEASON_SECONDS * 4.0
const NAMES := ["春季", "夏季", "秋季", "冬季"]
const GROUND_TINT := [
	Color("ebffea"), Color("fff1cb"), Color("ffc380"), Color("dce9f5"),
]
const FOLIAGE_TINT := [
	Color("e5ffe3"), Color("fdffd4"), Color("ffbe69"), Color("a3bac6"),
]
const SUN_TINT := [
	Color("fff2dc"), Color("ffe2a8"), Color("ffd1a3"), Color("c6dbff"),
]

var seconds := 0.0


static func season_at(time: float) -> Season:
	return floori(fposmod(time, YEAR_SECONDS) / SEASON_SECONDS) as Season
