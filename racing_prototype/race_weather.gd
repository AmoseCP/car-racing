extends Node3D

const Modes := preload("res://racing_prototype/weather_modes.gd")
const SURFACE_SHADER_PATH := "res://racing_prototype/weather_surface.gdshader"
const TRANSITION_SECONDS := 2.4

const RAIN_EFFECT := {
	"amount": 650, "lifetime": 0.74, "size": Vector2(0.064, 0.56),
	"extents": Vector3(13.0, 0.65, 16.5), "velocity": Vector2(19.0, 24.5),
	"direction": Vector3(0.18, -1, -0.05), "spread": 3.0, "gravity": Vector3(0, -2, 0),
	"color": Color(0.73, 0.84, 0.98, 0.49),
}
const SNOW_EFFECT := {
	"amount": 315, "lifetime": 5.1, "size": Vector2(0.15, 0.15),
	"extents": Vector3(13.0, 3.1, 17.5), "velocity": Vector2(1.55, 3.4),
	"direction": Vector3(0.35, -1, 0.19), "spread": 13.0, "gravity": Vector3(0.1, -0.14, 0),
	"color": Color(0.91, 0.96, 1.0, 0.90),
}

var stage: StringName = Modes.CLEAR
var speed_factor := 1.0
var acceleration_factor := 1.0
var brake_factor := 1.0
var steering_factor := 1.0
var rain_strength := 0.0
var snow_strength := 0.0

var _mode: StringName = Modes.DYNAMIC
var _surfaces: Array[ShaderMaterial] = []
var _rain: GPUParticles3D
var _snow: GPUParticles3D

@onready var _track: Node3D = $"../Track"
@onready var _camera: Camera3D = $"../ChaseCamera"


func configure(mode: StringName) -> void:
	_mode = mode if Modes.NAMES.has(mode) else Modes.DYNAMIC
	var shader := load(SURFACE_SHADER_PATH) as Shader
	_bind_surface(_track.get_node("Asphalt"), shader, 0.39)
	_bind_surface(_track.get_node("Shoulder"), shader, 0.92)
	_bind_surface($"../Ground/Surface", shader, 0.98)
	var falloff := _build_particle_texture()
	_rain = _make_precipitation("Rain", RAIN_EFFECT, falloff)
	_snow = _make_precipitation("Snow", SNOW_EFFECT, falloff)
	reset()


func reset() -> void:
	stage = Modes.at_time(_mode, 0.0)
	rain_strength = 1.0 if stage == Modes.RAIN else 0.0
	snow_strength = 1.0 if stage == Modes.SNOW else 0.0
	_apply_conditions()


func advance(seconds: float, delta: float) -> void:
	stage = Modes.at_time(_mode, seconds)
	var step := delta / TRANSITION_SECONDS
	var rain := move_toward(rain_strength, 1.0 if stage == Modes.RAIN else 0.0, step)
	var snow := move_toward(snow_strength, 1.0 if stage == Modes.SNOW else 0.0, step)
	if rain == rain_strength and snow == snow_strength:
		return
	rain_strength = rain
	snow_strength = snow
	_apply_conditions()


func _apply_conditions() -> void:
	var rain := rain_strength
	var snow := snow_strength
	speed_factor = 1.0 - 0.15 * rain - 0.30 * snow
	acceleration_factor = 1.0 - 0.10 * rain - 0.24 * snow
	brake_factor = 1.0 - 0.12 * rain - 0.24 * snow
	steering_factor = 1.0 - 0.08 * rain - 0.16 * snow
	for material in _surfaces:
		material.set_shader_parameter("rain", rain)
		material.set_shader_parameter("snow", snow)
	_update_precipitation()
	set_process(rain + snow > 0.015)


func _process(_delta: float) -> void:
	_update_precipitation()


func _update_precipitation() -> void:
	var camera_position := _camera.global_position
	var ahead := camera_position - _camera.global_basis.z * 9.0
	_rain.global_position = Vector3(ahead.x, 9.2, ahead.z)
	_snow.global_position = Vector3(ahead.x, 6.7, ahead.z)
	var outdoors: bool = not _track.has_overhead_cover(camera_position)
	_set_emitter(_rain, rain_strength if outdoors else 0.0)
	_set_emitter(_snow, snow_strength if outdoors else 0.0)


func _set_emitter(emitter: GPUParticles3D, strength: float) -> void:
	var active := strength > 0.015
	if emitter.emitting != active:
		emitter.emitting = active
		emitter.visible = active
	emitter.amount_ratio = strength


func _bind_surface(surface: MeshInstance3D, shader: Shader, snow_retention: float) -> void:
	var original := surface.material_override as StandardMaterial3D
	if original == null:
		original = surface.mesh.surface_get_material(0) as StandardMaterial3D
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("surface_color", original.albedo_texture)
	material.set_shader_parameter("surface_normal", original.normal_texture)
	material.set_shader_parameter("surface_roughness", original.roughness_texture)
	material.set_shader_parameter("surface_tint", original.albedo_color)
	material.set_shader_parameter("texture_scale", Vector2(original.uv1_scale.x, original.uv1_scale.y))
	material.set_shader_parameter("normal_strength", original.normal_scale)
	material.set_shader_parameter("roughness_strength", original.roughness)
	material.set_shader_parameter("base_specular", original.metallic_specular)
	material.set_shader_parameter("snow_retention", snow_retention)
	surface.material_override = material
	_surfaces.append(material)


func _build_particle_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.82), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.width = 32
	texture.height = 32
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func _make_precipitation(node_name: String, profile: Dictionary, texture: Texture2D) -> GPUParticles3D:
	var particle_material := StandardMaterial3D.new()
	particle_material.albedo_color = profile.color
	particle_material.albedo_texture = texture
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var mesh := QuadMesh.new()
	mesh.size = profile.size
	mesh.material = particle_material
	var emitter := GPUParticles3D.new()
	emitter.name = node_name
	emitter.amount = profile.amount
	emitter.lifetime = profile.lifetime
	emitter.preprocess = minf(emitter.lifetime * 0.5, 1.2)
	emitter.visibility_aabb = AABB(Vector3(-38, -27, -40), Vector3(76, 50, 80))
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.emitting = false
	emitter.visible = false
	emitter.draw_pass_1 = mesh
	# The headless display can track emission state without allocating a GPU particle shader.
	if DisplayServer.get_name() != "headless":
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = profile.extents
		process.direction = profile.direction
		process.spread = profile.spread
		process.gravity = profile.gravity
		process.initial_velocity_min = profile.velocity.x
		process.initial_velocity_max = profile.velocity.y
		emitter.process_material = process
	add_child(emitter)
	return emitter
