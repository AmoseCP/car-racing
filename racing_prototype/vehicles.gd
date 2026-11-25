extends RefCounted

const DEFAULT := &"gt"
const ORDER := [&"gt", &"rally", &"prototype"]

const DATA := {
	&"gt": {
		"name": "GT 赛车", "type": "均衡型", "accent": Color("ffd675"),
		"description": "速度、制动和转向均衡，适合在红岩沙漠熟悉赛道和加速带。",
		"scene": preload("res://racing_prototype/gt_car.tscn"),
		"collision_size": Vector3(2.12, 1.26, 3.96), "tyre_radius": 0.322,
		"top_speed": 48.0, "acceleration": 19.0, "braking": 32.0,
		"steering": Vector2(1.85, 1.32), "boost_speed": 60.0, "boost_seconds": 1.25, "boost_push": 8.0,
	},
	&"rally": {
		"name": "拉力赛车", "type": "弯道型", "accent": Color("77e5bd"),
		"description": "起步快、刹车短，连续转弯更灵活。松雾森林和霓虹城区是它的主场。",
		"scene": preload("res://racing_prototype/rally_car.tscn"),
		"collision_size": Vector3(1.99, 1.26, 3.70), "tyre_radius": 0.281,
		"top_speed": 43.0, "acceleration": 23.0, "braking": 39.0,
		"steering": Vector2(2.15, 1.72), "boost_speed": 54.0, "boost_seconds": 1.05, "boost_push": 7.0,
	},
	&"prototype": {
		"name": "耐力原型车", "type": "极速型", "accent": Color("9dbbff"),
		"description": "直道极速最高，加速带效果最持久。提早刹车，在风车草原的长直道追回时间。",
		"scene": preload("res://racing_prototype/prototype_car.tscn"),
		"collision_size": Vector3(2.05, 1.20, 4.36), "tyre_radius": 0.329,
		"top_speed": 56.0, "acceleration": 17.0, "braking": 27.0,
		"steering": Vector2(1.67, 1.10), "boost_speed": 70.0, "boost_seconds": 1.65, "boost_push": 10.0,
	},
}


static func instantiate_model(id: StringName) -> Node3D:
	var scene: PackedScene = DATA[id].scene
	return scene.instantiate() as Node3D
