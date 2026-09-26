## test_toon_style.gd
## Style "BD façon Borderlands" (2026-09-26) : ToonStyle.gd est la SEULE porte
## d'entrée vers art/style/toon_style.json v2 (source unique de vérité) --
## voir la docstring de ToonStyle.gd pour la portée exacte (Verrou/Ravage+gants/
## Shipment, jamais le reste du jeu). Les valeurs numériques ci-dessous sont
## recopiées du JSON verrouillé (pas depuis ToonStyle.gd) : un test qui relisait
## le JSON pour le comparer à lui-même ne prouverait rien (même piège documenté
## par tests/rendering/test_ink_toon_params.gd, même famille de shader).
##
## Comme test_ink_toon_params.gd/test_cartoon_painted_props.gd (même moteur/
## version) : `ShaderMaterial.get_shader_parameter()` ne renvoie une valeur non
## nulle QUE si `set_shader_parameter` a été appelé explicitement sur CETTE
## instance -- jamais le défaut GLSL implicite. `ToonStyle.toon_material()` pose
## explicitement chaque paramètre (voir son code) : ce test peut donc lire
## `get_shader_parameter()` en confiance.
extends GdUnitTestSuite

const _TOON_SHADER := preload("res://assets/shaders/toon_bd.gdshader")
const _OUTLINE_SHADER := preload("res://assets/shaders/toon_bd_outline.gdshader")


func _make_texture(color: Color = Color.WHITE) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


# ============================================================================
#  JSON chargé (art/style/toon_style.json v2)
# ============================================================================

func test_style_json_loads_and_is_not_empty() -> void:
	assert_that(ToonStyle.style()).is_not_empty()


func test_style_json_has_expected_top_level_sections() -> void:
	var s := ToonStyle.style()
	for key in ["shading", "shadow_tint", "rim", "specular", "halftone", "outline", "light", "grading", "palette"]:
		assert_bool(s.has(key)).append_failure_message("section manquante : %s" % key).is_true()


func test_style_json_version_is_2() -> void:
	assert_int(int(ToonStyle.style().get("version", -1))).is_equal(2)


# ============================================================================
#  toon_material() -- ingrédients 3/4 (éclairage) + albédo/texture
# ============================================================================

func test_toon_material_uses_toon_bd_shader() -> void:
	var m := ToonStyle.toon_material(null, Color.WHITE)
	assert_that(m.shader).is_equal(_TOON_SHADER)


func test_toon_material_default_tint_is_passed_through() -> void:
	var m := ToonStyle.toon_material(null, Color("c8322b"))
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color("c8322b"))


func test_null_texture_never_enables_albedo_texture() -> void:
	var m := ToonStyle.toon_material(null, Color.RED)
	assert_that(m.get_shader_parameter("use_albedo_texture")).is_not_equal(true)


func test_texture_is_kept_and_enables_use_albedo_texture() -> void:
	var tex := _make_texture(Color("9c6a42"))
	var m := ToonStyle.toon_material(tex, Color.WHITE)
	assert_bool(m.get_shader_parameter("use_albedo_texture")).is_true()
	assert_that(m.get_shader_parameter("albedo_texture")).is_equal(tex)


## Valeurs verrouillées par art/style/toon_style.json v2 "shading"/"shadow_tint".
func test_shading_params_reach_the_material() -> void:
	var m := ToonStyle.toon_material(null, Color.WHITE)
	assert_float(m.get_shader_parameter("wrap")).is_equal_approx(0.1, 0.0001)
	assert_float(m.get_shader_parameter("terminator")).is_equal_approx(0.45, 0.0001)
	assert_float(m.get_shader_parameter("sharpness")).is_equal_approx(0.12, 0.0001)
	assert_float(m.get_shader_parameter("shadow_value")).is_equal_approx(0.42, 0.0001)
	assert_float(m.get_shader_parameter("shadow_hue_shift_deg")).is_equal_approx(-8.0, 0.0001)
	assert_float(m.get_shader_parameter("shadow_saturation_mult")).is_equal_approx(1.25, 0.0001)


## Valeurs verrouillées par art/style/toon_style.json v2 "rim"/"specular".
func test_rim_and_specular_params_reach_the_material() -> void:
	var m := ToonStyle.toon_material(null, Color.WHITE)
	assert_bool(m.get_shader_parameter("rim_enabled")).is_true()
	assert_float(m.get_shader_parameter("rim_power")).is_equal_approx(4.0, 0.0001)
	assert_float(m.get_shader_parameter("rim_threshold")).is_equal_approx(0.55, 0.0001)
	assert_float(m.get_shader_parameter("rim_intensity")).is_equal_approx(0.25, 0.0001)
	assert_that(m.get_shader_parameter("rim_tint")).is_equal(Color("#FFE9B8"))
	assert_bool(m.get_shader_parameter("rim_lit_side_only")).is_true()
	assert_bool(m.get_shader_parameter("specular_enabled")).is_true()
	assert_float(m.get_shader_parameter("specular_size")).is_equal_approx(0.18, 0.0001)
	assert_float(m.get_shader_parameter("specular_intensity")).is_equal_approx(0.25, 0.0001)


## toon_style.json v2 "halftone.enabled": false -- désactivé par défaut, code
## présent mais inerte (voir toon_bd.gdshader `_halftone_mask`/`halftone_enabled`).
func test_halftone_is_off_by_default() -> void:
	var m := ToonStyle.toon_material(null, Color.WHITE)
	assert_bool(m.get_shader_parameter("halftone_enabled")).is_not_equal(true)
	assert_float(m.get_shader_parameter("halftone_cell_px")).is_equal_approx(7.0, 0.0001)


## `assert_that(...).is_not_equal(...)` compare par CONTENU pour un Object en
## gdUnit4 (deux ShaderMaterial aux mêmes paramètres sont "égaux" bien que
## distincts) -- `is_same` (identité de référence, natif GDScript) est le seul
## test correct de "pas la même ressource partagée par erreur".
func test_two_calls_never_share_the_same_material_instance() -> void:
	var a := ToonStyle.toon_material(null, Color.WHITE)
	var b := ToonStyle.toon_material(null, Color.WHITE)
	assert_bool(is_same(a, b)).is_false()


# ============================================================================
#  apply_to() -- conserve la texture d'albédo (glTF peint) ou la teinte plate
#  (géométrie procédurale, ex. shipment.tscn) tout en changeant le matériau.
# ============================================================================

func test_apply_to_keeps_albedo_texture_from_a_standard_material_surface() -> void:
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	mi.mesh = BoxMesh.new()
	var std := StandardMaterial3D.new()
	var tex := _make_texture(Color("9c6a42"))
	std.albedo_texture = tex
	std.albedo_color = Color("d2a46c")
	mi.set_surface_override_material(0, std)

	ToonStyle.apply_to(mi)

	var applied := mi.get_surface_override_material(0) as ShaderMaterial
	assert_that(applied).is_not_null()
	assert_that(applied.shader).is_equal(_TOON_SHADER)
	assert_that(applied.get_shader_parameter("albedo_texture")).is_equal(tex)
	assert_bool(applied.get_shader_parameter("use_albedo_texture")).is_true()
	assert_that(applied.get_shader_parameter("albedo_color")).is_equal(Color("d2a46c"))


## Géométrie procédurale (shipment.tscn) : un bloc n'a pas de surface nommée,
## sa couleur vit dans `material_override` -- `apply_to` doit aussi couvrir ce
## chemin (voir la doc de `_swap_mesh_materials`), sans texture à conserver.
func test_apply_to_keeps_flat_color_on_material_override() -> void:
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	mi.mesh = BoxMesh.new()
	var flat := ShaderMaterial.new()
	flat.shader = preload("res://assets/shaders/dev_grid.gdshader")
	flat.set_shader_parameter("albedo_color", Color(0.55, 0.25, 0.18, 1.0))
	mi.material_override = flat

	ToonStyle.apply_to(mi)

	var applied := mi.material_override as ShaderMaterial
	assert_that(applied).is_not_null()
	assert_that(applied.shader).is_equal(_TOON_SHADER)
	assert_that(applied.get_shader_parameter("albedo_color")).is_equal(Color(0.55, 0.25, 0.18, 1.0))
	assert_bool(applied.get_shader_parameter("use_albedo_texture")).is_not_equal(true)


## `apply_to` doit descendre récursivement (un modèle glTF importé est presque
## toujours plusieurs MeshInstance3D imbriqués, jamais un seul nœud plat).
func test_apply_to_walks_the_whole_subtree() -> void:
	var root: Node3D = auto_free(Node3D.new())
	var child_a: MeshInstance3D = MeshInstance3D.new()
	child_a.mesh = BoxMesh.new()
	root.add_child(child_a)
	var nested := Node3D.new()
	root.add_child(nested)
	var child_b: MeshInstance3D = MeshInstance3D.new()
	child_b.mesh = BoxMesh.new()
	nested.add_child(child_b)

	ToonStyle.apply_to(root)

	assert_that((child_a.get_surface_override_material(0) as ShaderMaterial).shader).is_equal(_TOON_SHADER)
	assert_that((child_b.get_surface_override_material(0) as ShaderMaterial).shader).is_equal(_TOON_SHADER)


func test_apply_to_does_not_crash_on_null_or_meshless_nodes() -> void:
	ToonStyle.apply_to(null)
	var empty_mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	ToonStyle.apply_to(empty_mi)  # mesh == null : ne doit jamais planter.


# ============================================================================
#  Environnement / soleil (art/style/toon_style.json v2 "light"/"grading")
# ============================================================================

func test_environment_uses_grading_saturation_and_contrast_from_json() -> void:
	var env := ToonStyle.environment()
	assert_bool(env.adjustment_enabled).is_true()
	assert_float(env.adjustment_saturation).is_equal_approx(1.25, 0.0001)
	assert_float(env.adjustment_contrast).is_equal_approx(1.12, 0.0001)


func test_apply_sun_sets_color_and_energy_from_json() -> void:
	var sun: DirectionalLight3D = auto_free(DirectionalLight3D.new())
	ToonStyle.apply_sun(sun)
	assert_that(sun.light_color).is_equal(Color("#FFF1DC"))
	assert_float(sun.light_energy).is_equal_approx(1.0, 0.0001)
	assert_bool(sun.shadow_enabled).is_true()


func test_setup_environment_configures_both_world_environment_and_sun() -> void:
	var we: WorldEnvironment = auto_free(WorldEnvironment.new())
	var sun: DirectionalLight3D = auto_free(DirectionalLight3D.new())
	ToonStyle.setup_environment(we, sun)
	assert_that(we.environment).is_not_null()
	assert_float(sun.light_energy).is_equal_approx(1.0, 0.0001)


func test_setup_environment_tolerates_a_missing_sun() -> void:
	var we: WorldEnvironment = auto_free(WorldEnvironment.new())
	ToonStyle.setup_environment(we, null)  # ne doit jamais planter.
	assert_that(we.environment).is_not_null()


# ============================================================================
#  Contour post-traitement (art/style/toon_style.json v2 "outline")
# ============================================================================

func test_outline_params_match_json() -> void:
	var p := ToonStyle.outline_params()
	assert_that(p["outline_color"]).is_equal(Color("#0E0A12"))
	assert_float(p["width_px_at_1080p"]).is_equal_approx(1.5, 0.0001)
	assert_float(p["min_width_px"]).is_equal_approx(1.0, 0.0001)
	assert_float(p["depth_threshold"]).is_equal_approx(0.015, 0.0001)
	assert_float(p["normal_threshold_deg"]).is_equal_approx(30.0, 0.0001)
	assert_float(p["fade_start_m"]).is_equal_approx(25.0, 0.0001)
	assert_float(p["fade_end_m"]).is_equal_approx(70.0, 0.0001)


func test_add_outline_pass_attaches_a_quad_to_the_camera() -> void:
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	var quad := ToonStyle.add_outline_pass(camera)
	assert_that(quad).is_not_null()
	assert_that(quad.get_parent()).is_equal(camera)
	var mat := quad.material_override as ShaderMaterial
	assert_that(mat.shader).is_equal(_OUTLINE_SHADER)
	assert_that(mat.get_shader_parameter("outline_color")).is_equal(Color("#0E0A12"))


func test_add_outline_pass_is_idempotent() -> void:
	var camera: Camera3D = auto_free(Camera3D.new())
	add_child(camera)
	var first := ToonStyle.add_outline_pass(camera)
	var second := ToonStyle.add_outline_pass(camera)
	assert_that(first).is_equal(second)
	var quads := 0
	for child in camera.get_children():
		if child is ToonOutlineQuad:
			quads += 1
	assert_int(quads).is_equal(1)


func test_add_outline_pass_tolerates_a_null_camera() -> void:
	assert_that(ToonStyle.add_outline_pass(null)).is_null()
