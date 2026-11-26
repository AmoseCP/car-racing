extends RefCounted

const DEFAULT := &"gt"
const ORDER := [&"gt", &"rally", &"prototype"]

const DATA := {
	&"gt": {
		"name": "GT 赛车", "type": "均衡型", "accent": Color("ffd675"),
		"description": "速度、制动和转向均衡，适合在红岩沙漠熟悉赛道和加速带。",
		"scene": preload("res://racing_prototype/gt_car.tscn"),
		"collision_size": Vector3(2.12, 1.26, 3.96), "tyre_radius": 0.322,
		"top_speed": 48.0, "acceleration": 11.5, "braking": 32.0,
		"steering": Vector2(1.55, 1.10), "boost_speed": 60.0, "boost_seconds": 1.25, "boost_push": 8.0,
		"paint_roles": {"Paint_Yellow": 0, "Paint_Red": 1},
	},
	&"rally": {
		"name": "拉力赛车", "type": "弯道型", "accent": Color("77e5bd"),
		"description": "起步快、刹车短，连续转弯更灵活。松雾森林和霓虹城区是它的主场。",
		"scene": preload("res://racing_prototype/rally_car.tscn"),
		"collision_size": Vector3(1.99, 1.26, 3.70), "tyre_radius": 0.281,
		"top_speed": 43.0, "acceleration": 14.0, "braking": 39.0,
		"steering": Vector2(1.80, 1.44), "boost_speed": 54.0, "boost_seconds": 1.05, "boost_push": 7.0,
		"paint_roles": {"Paint_White": 0, "Paint_Blue": 1, "Paint_Red": 1},
	},
	&"prototype": {
		"name": "耐力原型车", "type": "极速型", "accent": Color("9dbbff"),
		"description": "直道极速最高，加速带效果最持久。提早刹车，在风车草原的长直道追回时间。",
		"scene": preload("res://racing_prototype/prototype_car.tscn"),
		"collision_size": Vector3(2.05, 1.20, 4.36), "tyre_radius": 0.329,
		"top_speed": 56.0, "acceleration": 10.5, "braking": 27.0,
		"steering": Vector2(1.40, 0.92), "boost_speed": 70.0, "boost_seconds": 1.65, "boost_push": 10.0,
		"paint_roles": {"Paint_White": 0, "Paint_Blue": 1},
	},
}


## Paint schemes unlocked by medal points (bronze 1, silver 2, gold 3, daily run 1).
## colors = [main body, accent]; index 0 keeps each car's factory livery.
const LIVERIES := [
	{"name": "原厂涂装", "points": 0},
	{"name": "烈焰红", "points": 2, "colors": [Color("c8161f"), Color("f1f0ec")]},
	{"name": "午夜黑", "points": 4, "colors": [Color("15171b"), Color("e3b21f")]},
	{"name": "冰川白", "points": 6, "colors": [Color("eef1f4"), Color("2a78d4")]},
	{"name": "赛道橙", "points": 9, "colors": [Color("ff7417"), Color("1b1d22")]},
	{"name": "薄荷青", "points": 12, "colors": [Color("3fd3b4"), Color("152029")]},
	{"name": "霓虹紫", "points": 16, "colors": [Color("6f3cf0"), Color("ff4fa6")]},
	{"name": "冠军金", "points": 20, "colors": [Color("d6a531"), Color("121212")], "metallic": 0.78},
]


## Share of full engine pull left at a given fraction of top speed: strong off
## the line, tapering towards the top like a real car.
static func power_curve(speed_ratio: float) -> float:
	return maxf(0.28, 1.0 - 0.62 * speed_ratio * speed_ratio)


## Seconds from standstill to the given speed (m/s) on a dry road.
static func time_to(id: StringName, target_speed: float) -> float:
	var profile: Dictionary = DATA[id]
	var speed := 0.0
	var time := 0.0
	while speed < target_speed and time < 60.0:
		speed += profile.acceleration * power_curve(speed / profile.top_speed) * 0.005
		time += 0.005
	return time


static func paint(material: StandardMaterial3D, id: StringName, factory: Color, livery: int) -> void:
	var scheme: Dictionary = LIVERIES[livery]
	var role: int = DATA[id].paint_roles.get(material.resource_name, -1)
	material.albedo_color = factory if role < 0 or not scheme.has("colors") else scheme.colors[role]
	material.metallic = scheme.get("metallic", 0.0) if role >= 0 else material.metallic
	material.roughness = 0.28 if role >= 0 and scheme.has("metallic") else material.roughness


static func paint_model(model: Node3D, id: StringName, livery: int) -> void:
	var body := model.get_child(0).get_node("Body") as MeshInstance3D
	for index in range(body.mesh.get_surface_count()):
		var original := body.mesh.surface_get_material(index) as StandardMaterial3D
		if original != null and original.resource_name.begins_with("Paint_"):
			var copy: StandardMaterial3D = original.duplicate()
			paint(copy, id, original.albedo_color, livery)
			body.set_surface_override_material(index, copy)


static func instantiate_model(id: StringName) -> Node3D:
	var scene: PackedScene = DATA[id].scene
	return scene.instantiate() as Node3D
