extends RefCounted

enum Medal { NONE, BRONZE, SILVER, GOLD }

const ORDER := [&"desert", &"city", &"tunnel", &"grassland", &"forest"]
const LAP_COUNT := 2
const MEDAL_NAMES := ["", "铜牌", "银牌", "金牌"]
const MEDAL_COLORS := [Color.WHITE, Color("e2a376"), Color("c5dbf3"), Color("ffd675")]

const DATA := {
	&"desert": {
		"name": "红岩沙漠", "banner": "RED MESA", "tagline": "干燥砂石 · 开阔弯道",
		"description": "沿着红色台地疾驰。长直道后的宽弯适合练习刹车入弯。",
		"oval": Vector3(26, 40, 21), "bend": Vector2.ZERO, "width": 6.6, "target": 66.0,
		"horizon": Color("eed6b4"), "accent": Color("ffbd64"), "light": Color("ffe2b9"),
	},
	&"city": {
		"name": "霓虹城区", "banner": "NEON DISTRICT", "tagline": "黄昏街道 · 直角弯",
		"description": "穿过楼群与路灯，利用直道加速带，在紧凑的街角提前减速。",
		"oval": Vector3(38, 33, 13), "bend": Vector2(0, 0), "width": 6.1, "target": 63.0,
		"horizon": Color("ee9b88"), "accent": Color("ff9eaf"), "light": Color("ffc1a1"),
	},
	&"tunnel": {
		"name": "极光隧道", "banner": "AURORA TUNNEL", "tagline": "封闭隧道 · 连续弯道",
		"description": "跟随青色灯带穿过山体，留意隧道内提前出现的弯道。",
		"oval": Vector3(22, 35, 17), "bend": Vector2(-4.5, 0), "width": 6.8, "target": 56.0,
		"horizon": Color("8d9cbb"), "accent": Color("72f4f1"), "light": Color("bddcf1"),
	},
	&"grassland": {
		"name": "风车草原", "banner": "WINDMILL PLAINS", "tagline": "开阔草场 · 高速弯",
		"description": "在风车和低丘间跑出高速圈，寻找长弯出口的加速带。",
		"oval": Vector3(36, 44, 25), "bend": Vector2(5, 7), "width": 7.4, "target": 75.0,
		"horizon": Color("d2eaca"), "accent": Color("edf27b"), "light": Color("fff1c9"),
	},
	&"forest": {
		"name": "松雾森林", "banner": "PINEWOOD", "tagline": "松林薄雾 · 窄路变向",
		"description": "在高松和弯曲小路之间穿行。路线较窄，过弯时控制油门。",
		"oval": Vector3(25, 35, 16), "bend": Vector2(8, -6.5), "width": 5.6, "target": 64.0,
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
