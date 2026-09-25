## test_level_look.gd
## Spec (docs/STYLE_BIBLE.md §7.5 v3 "Environment WYSIWYG") : l'Environment
## "peint au soleil" appliqué par LevelLook — ciel stylisé PAR CARTE, tonemap
## **LINÉAIRE** (exposition 1,0, aucun ajustement de post) pour que l'albédo
## peint reste WYSIWYG (sonde de calibration `tools/look_probe.gd`, CHK-01),
## ambiance depuis le ciel à 0,18, SSAO 0,8/1,0/1,5 + contact 0,15 en plein
## soleil, brouillard chaud léger, PAS de glow, ombres du soleil calibrées
## (pénombre, portée 120 m, PSSM 4). Fonctions statiques pures (aucun nœud
## requis) pour rester testables sans arbre de scène. Sans `map_id` (comme
## tous ces appels), on exerce la carte par défaut (Cartoon._DEFAULT_MAP_ID
## = "wasteland").
extends GdUnitTestSuite

const _SKY_SHADER := preload("res://assets/shaders/ink_sky.gdshader")


func test_environment_uses_sky_background() -> void:
	var env := LevelLook.build_environment()
	assert_int(env.background_mode).is_equal(Environment.BG_SKY)
	assert_that(env.sky).is_not_null()


func test_environment_uses_linear_tonemap_at_neutral_exposure() -> void:
	# §7.5 : LINEAR (pas FILMIC) à exposition 1,0 -- c'est ce qui rend la
	# sonde de calibration WYSIWYG possible (albédo -> pixel sans compression
	# ni ré-exposition intermédiaires).
	var env := LevelLook.build_environment()
	assert_int(env.tonemap_mode).is_equal(Environment.TONE_MAPPER_LINEAR)
	assert_float(env.tonemap_exposure).is_equal_approx(1.0, 0.001)


func test_environment_has_no_post_color_adjustment() -> void:
	# §7.5 : adjustment_enabled → false. La saturation/contraste de post (v2)
	# cassait le WYSIWYG -- la saturation se règle dans l'albédo, jamais en
	# post-traitement global.
	var env := LevelLook.build_environment()
	assert_bool(env.adjustment_enabled).is_false()


func test_environment_has_no_glow() -> void:
	var env := LevelLook.build_environment()
	assert_bool(env.glow_enabled).is_false()


func test_environment_has_light_fog_enabled() -> void:
	var env := LevelLook.build_environment()
	assert_bool(env.fog_enabled).is_true()
	assert_float(env.fog_density).is_less(0.02)


func test_environment_ambient_comes_from_sky_at_calibrated_energy() -> void:
	# §7.5 : 0,25 → 0,18, calibré à la sonde CHK-01 (tools/look_probe.gd).
	var env := LevelLook.build_environment()
	assert_int(env.ambient_light_source).is_equal(Environment.AMBIENT_SOURCE_SKY)
	assert_float(env.ambient_light_energy).is_equal_approx(0.18, 0.001)


func test_environment_ssao_matches_style_bible_table() -> void:
	# §7.5 : 0,5/1,2/1,0 → 0,8/1,0/1,5 ; ssao_light_affect 0 → 0,15 (nouveau) :
	# contacts doux mais nets, un peu de contact même au soleil.
	var env := LevelLook.build_environment()
	assert_bool(env.ssao_enabled).is_true()
	assert_float(env.ssao_radius).is_equal_approx(0.8, 0.001)
	assert_float(env.ssao_intensity).is_equal_approx(1.0, 0.001)
	assert_float(env.ssao_power).is_equal_approx(1.5, 0.001)
	assert_float(env.ssao_light_affect).is_equal_approx(0.15, 0.001)


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


# --------------------------------------------------- ombre du soleil (§7.5)

## `_apply_key_light` fonctionne sur un nœud hors-arbre (voir son commentaire :
## `look_at_from_position` ne dépend pas de `global_position`), donc ces tests
## restent des tests unitaires purs, sans WorldEnvironment ni arbre de scène.
func test_key_light_matches_style_bible_shadow_table() -> void:
	var look := LevelLook.new()
	var light := DirectionalLight3D.new()
	look._apply_key_light(light)
	assert_float(light.light_angular_distance).is_equal_approx(0.5, 0.001)
	assert_float(light.directional_shadow_max_distance).is_equal_approx(120.0, 0.001)
	assert_int(light.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_bool(light.shadow_enabled).is_true()
	look.free()
	light.free()
