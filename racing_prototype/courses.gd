extends RefCounted

enum Medal { NONE, BRONZE, SILVER, GOLD }

const ORDER := [&"desert", &"city", &"tunnel", &"grassland", &"forest"]
const LAP_COUNT := 2
const MEDAL_NAMES := ["", "铜牌", "银牌", "金牌"]
const MEDAL_COLORS := [Color.WHITE, Color("e2a376"), Color("c5dbf3"), Color("ffd675")]

const DATA := {
	&"desert": {
		"name": "红岩沙漠", "banner": "RED MESA", "tagline": "干燥砂石 · 开阔弯道",
		"description": "沿着红色台地行驶，在长直道留意货车和停车标志。",
		"route": Vector2(56, 30), "width": 8.1, "target": 95.0,
		"horizon": Color("eed6b4"), "accent": Color("ffbd64"), "light": Color("ffe2b9"),
	},
	&"city": {
		"name": "霓虹城区", "banner": "NEON DISTRICT", "tagline": "林立楼群 · 城区大道",
		"description": "穿过楼群与路灯，在街口等候红灯，并礼让横穿道路的行人。",
		"route": Vector2(55, 28), "width": 8.2, "target": 97.0,
		"horizon": Color("ee9b88"), "accent": Color("ff9eaf"), "light": Color("ffc1a1"),
	},
	&"tunnel": {
		"name": "极光隧道", "banner": "AURORA TUNNEL", "tagline": "封闭隧道 · 宽缓弧线",
		"description": "跟随青色灯带穿过山体，入弯前留意对向车流。",
		"route": Vector2(49, 26), "width": 8.0, "target": 90.0,
		"horizon": Color("8d9cbb"), "accent": Color("72f4f1"), "light": Color("bddcf1"),
	},
	&"grassland": {
		"name": "风车草原", "banner": "WINDMILL PLAINS", "tagline": "开阔草场 · 高速弯",
		"description": "在风车和低丘间行驶，长弯后留意前方慢车。",
		"route": Vector2(63, 35), "width": 8.7, "target": 105.0,
		"horizon": Color("d2eaca"), "accent": Color("edf27b"), "light": Color("fff1c9"),
	},
	&"forest": {
		"name": "松雾森林", "banner": "PINEWOOD", "tagline": "松林薄雾 · 林间直路",
		"description": "在长直路上穿过高松，进入林间宽弯前留意对向车辆。",
		"route": Vector2(47, 31), "width": 7.9, "target": 94.0,
		"horizon": Color("abc9b5"), "accent": Color("a9ef94"), "light": Color("d9edcb"),
	},
}


static func gold_target(silver_target: float) -> float:
	return snappedf(silver_target * 0.85, 0.01)


static func medal_for(time: float, silver_target: float) -> Medal:
	if not is_finite(time):
		return Medal.NONE
	var centiseconds := roundi(time * 100.0)
	if centiseconds <= roundi(gold_target(silver_target) * 100.0):
		return Medal.GOLD
	if centiseconds <= roundi(silver_target * 100.0):
		return Medal.SILVER
	return Medal.BRONZE


static func time_text(seconds: float) -> String:
	if not is_finite(seconds):
		return "--:--.--"
	var centiseconds := roundi(seconds * 100.0)
	return "%02d:%02d.%02d" % [floori(centiseconds / 6000.0),
		floori((centiseconds % 6000) / 100.0), centiseconds % 100]
