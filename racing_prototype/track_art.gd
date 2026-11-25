extends RefCounted

const DESERT_BOULDER := preload("res://racing_prototype/art/models/desert_boulder.glb")
const CITY_FACADE := preload("res://racing_prototype/art/models/city_facade.glb")
const ROADSIDE_GRASS := preload("res://racing_prototype/art/models/roadside_grass.glb")
const ROADSIDE_PINE := preload("res://racing_prototype/art/models/roadside_pine.glb")
const FOREST_FIR := preload("res://racing_prototype/art/models/forest_fir.glb")
const FIR_CANOPY := preload("res://racing_prototype/art/models/fir_canopy.png")

const WARM_SKY := preload("res://racing_prototype/art/skies/kloppenheim_06_puresky.hdr")
const DAY_SKY := preload("res://racing_prototype/art/skies/kloofendal_48d_partly_cloudy_puresky.hdr")
const DUSK_SKY := preload("res://racing_prototype/art/skies/industrial_sunset_puresky.hdr")

const ASPHALT := [
	preload("res://racing_prototype/art/textures/asphalt_track_color.jpg"),
	preload("res://racing_prototype/art/textures/asphalt_track_normal.jpg"),
	preload("res://racing_prototype/art/textures/asphalt_track_roughness.jpg"),
]
const CONCRETE := [
	preload("res://racing_prototype/art/textures/concrete_slab_wall_color.jpg"),
	preload("res://racing_prototype/art/textures/concrete_slab_wall_normal.jpg"),
	preload("res://racing_prototype/art/textures/concrete_slab_wall_roughness.jpg"),
]
const SAND := [
	preload("res://racing_prototype/art/textures/red_sand_color.jpg"),
	preload("res://racing_prototype/art/textures/red_sand_normal.jpg"),
	preload("res://racing_prototype/art/textures/red_sand_roughness.jpg"),
]
const GRASS := [
	preload("res://racing_prototype/art/textures/leafy_grass_color.jpg"),
	preload("res://racing_prototype/art/textures/leafy_grass_normal.jpg"),
	preload("res://racing_prototype/art/textures/leafy_grass_roughness.jpg"),
]
const FOREST := [
	preload("res://racing_prototype/art/textures/forest_ground_04_color.jpg"),
	preload("res://racing_prototype/art/textures/forest_ground_04_normal.jpg"),
	preload("res://racing_prototype/art/textures/forest_ground_04_roughness.jpg"),
]


static func road() -> StandardMaterial3D:
	return _surface(ASPHALT, 2.0, Color("d8dce1"), 0.50)


static func concrete(tint: Color) -> StandardMaterial3D:
	return _surface(CONCRETE, 3.0, tint, 0.68)


static func ground(course_id: StringName, span: float) -> StandardMaterial3D:
	var surface: StandardMaterial3D
	match course_id:
		&"desert": surface = _surface(SAND, 4.8, Color("e3c0a8"), 0.62)
		&"grassland": surface = _surface(GRASS, 4.2, Color("a2b385"), 0.55)
		&"forest": surface = _surface(FOREST, 3.8, Color("b5ae9f"), 0.65)
		&"city": surface = _surface(CONCRETE, 8.0, Color("777a86"), 0.42)
		_: surface = _surface(CONCRETE, 7.0, Color("77818f"), 0.52)
	surface.uv1_scale *= span
	return surface


static func _surface(maps: Array, tile_metres: float, tint: Color, normal_strength: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = maps[0]
	material.normal_enabled = true
	material.normal_texture = maps[1]
	material.normal_scale = normal_strength
	material.roughness_texture = maps[2]
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.metallic_specular = 0.38
	material.uv1_scale = Vector3(1.0 / tile_metres, 1.0 / tile_metres, 1.0 / tile_metres)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material
