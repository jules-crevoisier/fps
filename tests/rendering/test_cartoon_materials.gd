## test_cartoon_materials.gd
## Spec (design.md v2 §5/§6) : `world()` n'a pas de contour, `prop()` pose un
## contour d'encre PLAT de 2 px (viewmodel/pickups, jamais de falloff),
## `character()` pose un contour à falloff par distance pour l'allié (défaut)
## et une coque de surbrillance + une fine coque d'encre extérieure pour
## l'ennemi (`highlight_color`), `mat()` reste compatible, `set_rim()` écrit
## les instance uniforms, et `painted()` construit un matériau triplanaire à
## partir de la bibliothèque de tools/textures/gen_textures.py.
extends GdUnitTestSuite

const _INK_TOON_SHADER := preload("res://assets/shaders/ink_toon.gdshader")
const _INK_OUTLINE_SHADER := preload("res://assets/shaders/ink_outline.gdshader")


func test_world_material_uses_ink_toon_shader_and_no_outline() -> void:
	var m := Cartoon.world(Color.RED)
	assert_that(m.shader).is_equal(_INK_TOON_SHADER)
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color.RED)
	assert_that(m.next_pass).is_null()


func test_prop_material_has_flat_two_px_ink_outline() -> void:
	var m := Cartoon.prop(Color.BLUE)
	assert_that(m.next_pass).is_not_null()
	var outline := m.next_pass as ShaderMaterial
	assert_that(outline.shader).is_equal(_INK_OUTLINE_SHADER)
	assert_float(outline.get_shader_parameter("outline_width_px")).is_equal_approx(2.0, 0.001)
	assert_that(outline.get_shader_parameter("outline_color")).is_equal(Cartoon.INK)


func test_character_material_default_outline_width() -> void:
	var m := Cartoon.character(Color.GREEN)
	var outline := m.next_pass as ShaderMaterial
	assert_float(outline.get_shader_parameter("outline_width_px")).is_equal_approx(3.0, 0.001)


func test_character_material_custom_outline_width() -> void:
	var m := Cartoon.character(Color.GREEN, 6.0)
	var outline := m.next_pass as ShaderMaterial
	assert_float(outline.get_shader_parameter("outline_width_px")).is_equal_approx(6.0, 0.001)


## design.md §5 "Characters": 3 px to 10 m, 2 px at 40 m, 1.5 px floor.
func test_character_material_default_outline_has_distance_falloff() -> void:
	var m := Cartoon.character(Color.GREEN)
	var outline := m.next_pass as ShaderMaterial
	assert_bool(outline.get_shader_parameter("distance_falloff")).is_true()
	assert_float(outline.get_shader_parameter("falloff_far_px")).is_equal_approx(2.0, 0.001)
	assert_float(outline.get_shader_parameter("falloff_floor_px")).is_equal_approx(1.5, 0.001)


## design.md §5 "Enemies": a highlight hull 3.5 -> 2.5 px that "never fades"
## (floors at 2.5, doesn't thin to near-nothing like the ally's 1.5 px
## floor), plus a 1 px ink hull tracking 1 px outside it at every distance.
func test_character_material_with_highlight_builds_two_layer_enemy_hull() -> void:
	var m := Cartoon.character(Color.GREEN, 3.5, Color("ff3dc8"))
	var highlight := m.next_pass as ShaderMaterial
	assert_that(highlight.shader).is_equal(_INK_OUTLINE_SHADER)
	assert_that(highlight.get_shader_parameter("outline_color")).is_equal(Color("ff3dc8"))
	assert_float(highlight.get_shader_parameter("outline_width_px")).is_equal_approx(3.5, 0.001)
	assert_bool(highlight.get_shader_parameter("distance_falloff")).is_true()
	assert_float(highlight.get_shader_parameter("falloff_far_px")).is_equal_approx(2.5, 0.001)
	assert_float(highlight.get_shader_parameter("falloff_floor_px")).is_equal_approx(2.5, 0.001)

	var outer_ink := highlight.next_pass as ShaderMaterial
	assert_that(outer_ink).is_not_null()
	assert_that(outer_ink.get_shader_parameter("outline_color")).is_equal(Cartoon.INK)
	assert_float(outer_ink.get_shader_parameter("outline_width_px")).is_equal_approx(4.5, 0.001)
	assert_float(outer_ink.get_shader_parameter("falloff_far_px")).is_equal_approx(3.5, 0.001)
	assert_float(outer_ink.get_shader_parameter("falloff_floor_px")).is_equal_approx(3.5, 0.001)


func test_mat_is_compatible_world_material_with_no_outline() -> void:
	var m := Cartoon.mat(Color.YELLOW)
	assert_that(m is ShaderMaterial).is_true()
	assert_that((m as ShaderMaterial).shader).is_equal(_INK_TOON_SHADER)
	assert_that((m as ShaderMaterial).next_pass).is_null()


func test_mat_ignores_legacy_outline_argument() -> void:
	var m := Cartoon.mat(Color.YELLOW, 4.0)
	assert_that((m as ShaderMaterial).next_pass).is_null()


func test_set_rim_writes_instance_uniforms() -> void:
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	Cartoon.set_rim(mi, Color("3d7bff"), 1.4)
	assert_that(mi.get_instance_shader_parameter("rim_color")).is_equal(Color("3d7bff"))
	assert_float(mi.get_instance_shader_parameter("rim_strength")).is_equal_approx(1.4, 0.001)


func test_set_rim_with_null_instance_does_not_crash() -> void:
	Cartoon.set_rim(null, Color.WHITE, 1.0)


# ---------------------------------------------------------------- painted()

func test_painted_known_kind_uses_triplanar_texture() -> void:
	var m := Cartoon.painted(&"rust")
	assert_that(m.shader).is_equal(_INK_TOON_SHADER)
	assert_bool(m.get_shader_parameter("use_albedo_texture")).is_true()
	assert_bool(m.get_shader_parameter("use_triplanar")).is_true()
	assert_that(m.get_shader_parameter("albedo_texture")).is_not_null()
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color.WHITE)


func test_painted_default_tint_is_white() -> void:
	var m := Cartoon.painted(&"sand_dirt")
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color.WHITE)


func test_painted_tint_multiplies_the_tintable_container_base() -> void:
	var m := Cartoon.painted(&"container_paint", Cartoon.CONTAINER_RED)
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Cartoon.CONTAINER_RED)


func test_painted_material_with_grime_mask_enables_it() -> void:
	var m := Cartoon.painted(&"wood_planks")
	assert_bool(m.get_shader_parameter("use_grime_texture")).is_true()
	assert_that(m.get_shader_parameter("grime_texture")).is_not_null()


func test_painted_material_without_grime_mask_leaves_it_disabled() -> void:
	var m := Cartoon.painted(&"asphalt")
	assert_that(m.get_shader_parameter("use_grime_texture")).is_not_equal(true)


func test_painted_unknown_kind_falls_back_to_flat_world_material() -> void:
	var m := Cartoon.painted(&"nonexistent_kind", Color.RED)
	assert_that(m.shader).is_equal(_INK_TOON_SHADER)
	assert_that(m.get_shader_parameter("use_albedo_texture")).is_not_equal(true)
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color.RED)


# ------------------------------------------------------ kind alias table

## The props library (assets/models/props/**, manifest.json) names its
## material slots differently from tools/textures/gen_textures.py's kinds --
## painted() must accept both spellings for the same texture.
func test_painted_accepts_props_library_aliases_for_same_texture() -> void:
	var pairs := {
		&"corrugated": &"corrugated_metal",
		&"container": &"container_paint",
		&"wood": &"wood_planks",
		&"sand": &"sand_dirt",
		&"concrete": &"cracked_concrete",
		&"rubber": &"rubber_tire",
		&"glass": &"dirty_glass",
	}
	for alias in pairs:
		var canonical: StringName = pairs[alias]
		var via_alias := Cartoon.painted(alias)
		var via_canonical := Cartoon.painted(canonical)
		assert_that(via_alias.get_shader_parameter("albedo_texture")).is_equal(via_canonical.get_shader_parameter("albedo_texture"))


func test_painted_accepts_already_canonical_kinds_unchanged() -> void:
	for kind in [&"painted_metal", &"rust", &"asphalt", &"ship_deck"]:
		var m := Cartoon.painted(kind)
		assert_that(m.get_shader_parameter("use_albedo_texture")).is_true()


# ------------------------------------------------------- painted_for_slot()

func test_painted_for_slot_accepts_props_library_names() -> void:
	var m := Cartoon.painted_for_slot("container", Cartoon.CONTAINER_BLUE)
	assert_that(m is ShaderMaterial).is_true()
	assert_that((m as ShaderMaterial).get_shader_parameter("use_triplanar")).is_true()
	assert_that((m as ShaderMaterial).get_shader_parameter("albedo_color")).is_equal(Cartoon.CONTAINER_BLUE)


func test_painted_for_slot_accent_is_tintable_painted_metal() -> void:
	var m := Cartoon.painted_for_slot("accent", Color.RED) as ShaderMaterial
	assert_that(m.get_shader_parameter("use_triplanar")).is_true()
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color.RED)


## design.md v2 SS8/props: a sign's own colour (text/pictogram) must survive
## exactly -- multiplying it onto a painted texture would distort its hue.
func test_painted_for_slot_sign_keeps_its_own_color_flat() -> void:
	var m := Cartoon.painted_for_slot("sign", Color("f1e2c0")) as ShaderMaterial
	assert_that(m.shader).is_equal(_INK_TOON_SHADER)
	assert_that(m.get_shader_parameter("use_albedo_texture")).is_not_equal(true)
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color("f1e2c0"))


# --------------------------------------------------------- character_surface()

func test_character_surface_uses_flat_color_no_triplanar() -> void:
	var m := Cartoon.character_surface(&"skin", Color.RED)
	assert_that(m.shader).is_equal(_INK_TOON_SHADER)
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color.RED)
	assert_that(m.get_shader_parameter("use_triplanar")).is_not_equal(true)
	assert_that(m.get_shader_parameter("use_albedo_texture")).is_not_equal(true)


func test_character_surface_grain_varies_by_kind_within_six_percent() -> void:
	var skin := Cartoon.character_surface(&"skin", Color.WHITE)
	var gear := Cartoon.character_surface(&"gear", Color.WHITE)
	assert_float(skin.get_shader_parameter("paint_grain_strength")).is_less(gear.get_shader_parameter("paint_grain_strength"))
	assert_float(gear.get_shader_parameter("paint_grain_strength")).is_less_equal(0.06)


func test_character_surface_unknown_kind_gets_a_safe_default_grain() -> void:
	var m := Cartoon.character_surface(&"unknown_slot", Color.WHITE)
	var grain: float = m.get_shader_parameter("paint_grain_strength")
	assert_float(grain).is_greater(0.0)
	assert_float(grain).is_less_equal(0.06)


# ------------------------------------------------------- apply_team_outline()

func test_apply_team_outline_ally_sets_falling_off_ink_next_pass() -> void:
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	mi.mesh = BoxMesh.new()
	var surf := Cartoon.character_surface(&"skin", Color.BLUE)
	mi.set_surface_override_material(0, surf)
	Cartoon.apply_team_outline(mi, false)
	var outline := surf.next_pass as ShaderMaterial
	assert_that(outline).is_not_null()
	assert_that(outline.get_shader_parameter("outline_color")).is_equal(Cartoon.INK)
	assert_float(outline.get_shader_parameter("outline_width_px")).is_equal_approx(3.0, 0.001)
	assert_bool(outline.get_shader_parameter("distance_falloff")).is_true()


func test_apply_team_outline_enemy_uses_current_enemy_color_highlight() -> void:
	var orig := Settings.enemy_color
	Settings.enemy_color = 1  # citron
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	mi.mesh = BoxMesh.new()
	var surf := Cartoon.character_surface(&"outfit", Color.BLUE)
	mi.set_surface_override_material(0, surf)
	Cartoon.apply_team_outline(mi, true)
	var highlight := surf.next_pass as ShaderMaterial
	assert_that(highlight.get_shader_parameter("outline_color")).is_equal(Color("c8ff1f"))
	var outer_ink := highlight.next_pass as ShaderMaterial
	assert_that(outer_ink.get_shader_parameter("outline_color")).is_equal(Cartoon.INK)
	Settings.enemy_color = orig


func test_apply_team_outline_covers_every_surface() -> void:
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	var mesh := ArrayMesh.new()
	for i in range(2):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.add_vertex(Vector3(0, 0, 0))
		st.add_vertex(Vector3(1, 0, 0))
		st.add_vertex(Vector3(0, 1, 0))
		st.commit(mesh)
	mi.mesh = mesh
	mi.set_surface_override_material(0, Cartoon.character_surface(&"skin", Color.WHITE))
	mi.set_surface_override_material(1, Cartoon.character_surface(&"gear", Color.BLACK))
	Cartoon.apply_team_outline(mi, false)
	for i in range(2):
		assert_that(mi.get_surface_override_material(i).next_pass).is_not_null()


func test_apply_team_outline_with_null_instance_does_not_crash() -> void:
	Cartoon.apply_team_outline(null, false)


func test_apply_team_outline_with_mesh_less_instance_does_not_crash() -> void:
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	Cartoon.apply_team_outline(mi, true)
