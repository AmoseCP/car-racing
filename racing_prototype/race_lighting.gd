extends Node

const Modes := preload("res://racing_prototype/lighting_modes.gd")
const WorldClock := preload("res://racing_prototype/world_clock.gd")
const NIGHT_PANORAMA := preload("res://racing_prototype/art/skies/qwantani_night_puresky.hdr")
const SKY_SWITCH := 0.74

var phase_name := "白天"
var darkness := -1.0

var _mode: StringName = Modes.CYCLE
var _env: Environment
var _day_sky: Sky
var _night_sky: Sky
var _daylight: Dictionary
var _last_weather := Vector2(-1, -1)
var _last_season := -1

@onready var _world: WorldEnvironment = $"../WorldEnvironment"
@onready var _sun: DirectionalLight3D = $"../Sun"


func configure(mode: StringName) -> void:
	_mode = mode if Modes.NAMES.has(mode) else Modes.CYCLE
	_env = _world.environment
	_day_sky = _env.sky
	var night_material := PanoramaSkyMaterial.new()
	night_material.panorama = NIGHT_PANORAMA
	night_material.energy_multiplier = 0.026
	_night_sky = Sky.new()
	_night_sky.radiance_size = Sky.RADIANCE_SIZE_128
	_night_sky.sky_material = night_material
	_daylight = {
		"background": _env.background_energy_multiplier,
		"ambient": _env.ambient_light_energy,
		"ambient_color": _env.ambient_light_color,
		"sky_contribution": _env.ambient_light_sky_contribution,
		"fog": _env.fog_density,
		"fog_color": _env.fog_light_color,
		"fog_sky": _env.fog_sky_affect,
		"sun": _sun.light_energy,
		"sun_color": _sun.light_color,
	}


func advance(seconds: float, rain: float, snow: float, season: WorldClock.Season) -> void:
	var phase := Modes.phase_at(_mode, seconds)
	phase_name = Modes.phase_name(phase)
	var night := Modes.darkness_at(phase)
	var weather := Vector2(rain, snow)
	if night == darkness and weather == _last_weather and season == _last_season:
		return
	darkness = night
	_last_weather = weather
	_last_season = season
	var storm := rain + snow
	var sky_brightness := 1.0 - 0.48 * rain - 0.17 * snow
	_set_sky(night, sky_brightness)
	_env.ambient_light_energy = lerpf(_daylight.ambient, 0.21, night) * (1.0 - 0.10 * rain + 0.23 * snow)
	var ambient_color: Color = _daylight.ambient_color
	_env.ambient_light_color = ambient_color.lerp(Color("a2b9e4"), night)
	_env.ambient_light_sky_contribution = _daylight.sky_contribution * (1.0 - smoothstep(0.0, SKY_SWITCH, night))
	_env.fog_density = _daylight.fog * (1.0 - storm) + 0.0105 * rain + 0.0145 * snow
	var fog_color: Color = _daylight.fog_color
	fog_color = fog_color.lerp(Color("657686"), rain).lerp(Color("bacbef"), snow)
	_env.fog_light_color = fog_color.lerp(Color("121b30"), night)
	_env.fog_sky_affect = _daylight.fog_sky * (1.0 - storm) + 0.76 * rain + 0.57 * snow
	_sun.light_energy = lerpf(_daylight.sun, 0.025, night) * (1.0 - 0.67 * rain - 0.49 * snow)
	var twilight := 4.0 * night * (1.0 - night)
	var sunlight: Color = _daylight.sun_color
	sunlight = sunlight.lerp(WorldClock.SUN_TINT[season], 0.52)
	sunlight = sunlight.lerp(Color("ffbd83"), 0.6 * twilight * (1.0 - storm))
	_sun.light_color = sunlight.lerp(Color("b7c9e9"), storm).lerp(Color("849bd5"), night * night)


func _set_sky(night: float, weather_brightness: float) -> void:
	# Switch panoramas near the darkest part of the fade so the sky does not
	# need to rebuild its reflection texture for every step of the transition.
	if night >= SKY_SWITCH:
		if _env.sky != _night_sky:
			_env.sky = _night_sky
		_env.background_energy_multiplier = weather_brightness * smoothstep(SKY_SWITCH, 1.0, night)
	else:
		if _env.sky != _day_sky:
			_env.sky = _day_sky
		_env.background_energy_multiplier = _daylight.background * weather_brightness * (1.0 - smoothstep(0.0, SKY_SWITCH, night))
