## test_level_look.gd
## Spec (design.md v2 §4/§7) : l'Environment "peint au soleil" appliqué par
## LevelLook — ciel stylisé PAR CARTE, tonemap filmique + un soupçon de
## saturation, ambiance depuis le ciel à 25%, brouillard chaud léger, PAS de
## glow. Fonctions statiques pures (aucun nœud requis) pour rester testables
## sans arbre de scène. Sans `map_id` (comme tous ces appels), on exerce la
## carte par défaut (Cartoon._DEFAULT_MAP_ID = "wasteland").
extends GdUnitTestSuite

const _SKY_SHADER := preload("res://assets/shaders/ink_sky.gdshader")


func test_environment_uses_sky_background() -> void:
	var env := LevelLook.build_environment()
	assert_int(env.background_mode).is_equal(Environment.BG_SKY)
	assert_that(env.sky).is_not_null()


func test_environment_uses_filmic_tonemap() -> void:
	var env := LevelLook.build_environment()
	assert_int(env.tonemap_mode).is_equal(Environment.TONE_MAPPER_FILMIC)


func test_environment_has_no_glow() -> void:
	var env := LevelLook.build_environment()
	assert_bool(env.glow_enabled).is_false()


func test_environment_has_light_fog_enabled() -> void:
	var env := LevelLook.build_environment()
	assert_bool(env.fog_enabled).is_true()
	assert_float(env.fog_density).is_less(0.02)


func test_environment_ambient_comes_from_sky_at_quarter_energy() -> void:
	var env := LevelLook.build_environment()
	assert_int(env.ambient_light_source).is_equal(Environment.AMBIENT_SOURCE_SKY)
	assert_float(env.ambient_light_energy).is_equal_approx(0.25, 0.001)


func test_environment_has_a_touch_of_extra_saturation() -> void:
	var env := LevelLook.build_environment()
	assert_bool(env.adjustment_enabled).is_true()
	assert_float(env.adjustment_saturation).is_greater(1.0)


func test_sky_material_uses_ink_sky_shader() -> void:
	var m := LevelLook.build_sky_material()
	assert_that(m.shader).is_equal(_SKY_SHADER)


func test_environment_sky_uses_ink_sky_material() -> void:
	var env := LevelLook.build_environment()
	var sky_mat := env.sky.sky_material as ShaderMaterial
	assert_that(sky_mat).is_not_null()
	assert_that(sky_mat.shader).is_equal(_SKY_SHADER)


# --------------------------------------------------------- per-map presets

func test_sky_material_uses_map_specific_zenith_color() -> void:
	var port := LevelLook.build_sky_material("port_ferraille")
	var vautour := LevelLook.build_sky_material("col_du_vautour")
	assert_that(port.get_shader_parameter("sky_zenith_color")).is_equal(Color("4a8fe0"))
	assert_that(vautour.get_shader_parameter("sky_zenith_color")).is_equal(Color("1f63d0"))
	assert_that(port.get_shader_parameter("sky_zenith_color")).is_not_equal(vautour.get_shader_parameter("sky_zenith_color"))


## Fog is warmed toward the sun colour, not the raw pale horizon blue on its
## own (lead review: "no blue veil in the first 60 m") -- see
## LevelLook.build_environment()'s fog_light_color comment.
func test_environment_fog_color_follows_map_horizon() -> void:
	var env := LevelLook.build_environment("saint_ombre")
	var palette: Dictionary = Cartoon.map_palette("saint_ombre")
	var expected: Color = palette["sky_horizon"].lerp(palette["sun_color"], 0.4)
	assert_that(env.fog_light_color).is_equal(expected)
	# Still recognisably closer to the horizon colour than to the sun --
	# a warm TINT, not a full swap.
	var dist_to_horizon: float = _color_dist(env.fog_light_color, palette["sky_horizon"])
	var dist_to_sun: float = _color_dist(env.fog_light_color, palette["sun_color"])
	assert_float(dist_to_horizon).is_less(dist_to_sun)


static func _color_dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func test_unknown_map_id_falls_back_to_default_palette() -> void:
	var unknown := LevelLook.build_sky_material("does_not_exist")
	var default := LevelLook.build_sky_material()
	assert_that(unknown.get_shader_parameter("sky_zenith_color")).is_equal(default.get_shader_parameter("sky_zenith_color"))


func test_sun_direction_matches_map_elevation() -> void:
	# design.md v2 §7: La Fosse's sun sits at 50 degrees elevation, the
	# steepest of the eight maps -- its direction should point further
	# downward (more negative Y) than the default (Wasteland, 32 degrees).
	var steep := LevelLook._sun_direction(50.0)
	var shallow := LevelLook._sun_direction(32.0)
	assert_float(steep.y).is_less(shallow.y)


func test_sun_direction_at_45_degrees_matches_v1_reference_vector() -> void:
	var dir := LevelLook._sun_direction(45.0)
	assert_float(dir.x).is_equal_approx(0.5, 0.01)
	assert_float(dir.y).is_equal_approx(-0.70711, 0.01)
	assert_float(dir.z).is_equal_approx(0.5, 0.01)
