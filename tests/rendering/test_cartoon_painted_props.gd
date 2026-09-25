## test_cartoon_painted_props.gd
## ART-80 (docs/art/WASTELAND_ART_RESET.md, tools/blender/ai_import_painted.py) :
## `Cartoon.painted_texture_prop()` construit un ink_toon avec `use_albedo_texture`
## + le contour habituel, à partir d'une Texture2D DÉJÀ EXTRAITE d'un matériau
## importé — jamais un nom de kind de la bibliothèque partagée `_PAINTED`
## (chaque repère Tripo porte sa PROPRE texture bakée, unique). Couvre aussi
## `texture_from_imported_material()`, qui fait cette extraction depuis un
## `StandardMaterial3D` (ce que l'import glTF de Godot construit pour un
## repère peint).
extends GdUnitTestSuite

const _INK_TOON_SHADER := preload("res://assets/shaders/ink_toon.gdshader")
const _INK_OUTLINE_SHADER := preload("res://assets/shaders/ink_outline.gdshader")


func _make_texture(color: Color = Color.WHITE) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


# --------------------------------------------------- painted_texture_prop()

func test_uses_ink_toon_shader() -> void:
	var m := Cartoon.painted_texture_prop(_make_texture())
	assert_that(m.shader).is_equal(_INK_TOON_SHADER)


func test_enables_albedo_texture_and_sets_it() -> void:
	var tex := _make_texture()
	var m := Cartoon.painted_texture_prop(tex)
	assert_bool(m.get_shader_parameter("use_albedo_texture")).is_true()
	assert_that(m.get_shader_parameter("albedo_texture")).is_equal(tex)


func test_never_triplanar_uv_baked_by_hand_like_prop_uv() -> void:
	# STYLE_BIBLE.md v3 §7.7 : jamais triplanaire pour un prop peint en UV
	# Blender (à la différence de painted(), réservé au terrain) — même
	# convention que prop_uv().
	var m := Cartoon.painted_texture_prop(_make_texture())
	assert_that(m.get_shader_parameter("use_triplanar")).is_not_equal(true)


func test_default_tint_is_white() -> void:
	var m := Cartoon.painted_texture_prop(_make_texture())
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color.WHITE)


func test_tint_multiplies_the_albedo_color() -> void:
	var m := Cartoon.painted_texture_prop(_make_texture(), Color("c8322b"))
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color("c8322b"))


## design.md §5 « Viewmodel et pickups : 2 px d'encre » — même contour plat
## que prop(), pas de falloff par distance (contrairement à character()).
func test_has_flat_two_px_ink_outline_like_prop() -> void:
	var m := Cartoon.painted_texture_prop(_make_texture())
	assert_that(m.next_pass).is_not_null()
	var outline := m.next_pass as ShaderMaterial
	assert_that(outline.shader).is_equal(_INK_OUTLINE_SHADER)
	assert_float(outline.get_shader_parameter("outline_width_px")).is_equal_approx(2.0, 0.001)
	assert_that(outline.get_shader_parameter("outline_color")).is_equal(Cartoon.INK)
	assert_bool(outline.get_shader_parameter("distance_falloff")).is_not_equal(true)


func test_null_albedo_falls_back_to_flat_world_material_without_crashing() -> void:
	var m := Cartoon.painted_texture_prop(null, Color.RED)
	assert_that(m.shader).is_equal(_INK_TOON_SHADER)
	assert_that(m.get_shader_parameter("use_albedo_texture")).is_not_equal(true)
	assert_that(m.get_shader_parameter("albedo_color")).is_equal(Color.RED)
	# Le contour reste posé même sans texture (repère de décor, pas un warning bloquant).
	assert_that(m.next_pass).is_not_null()


func test_two_different_landmarks_get_independent_materials() -> void:
	# Deux repères Tripo distincts (ex. wl_water_tower vs wl_oil_derrick) ne
	# doivent jamais partager accidentellement le même ShaderMaterial —
	# chacun sa propre Texture2D, jamais mélangée.
	var tex_a := _make_texture(Color.RED)
	var tex_b := _make_texture(Color.BLUE)
	var mat_a := Cartoon.painted_texture_prop(tex_a)
	var mat_b := Cartoon.painted_texture_prop(tex_b)
	assert_that(mat_a.get_shader_parameter("albedo_texture")).is_equal(tex_a)
	assert_that(mat_b.get_shader_parameter("albedo_texture")).is_equal(tex_b)
	assert_that(mat_a).is_not_equal(mat_b)


# ---------------------------------------------- texture_from_imported_material()

func test_extracts_albedo_texture_from_standard_material() -> void:
	var std := StandardMaterial3D.new()
	var tex := _make_texture()
	std.albedo_texture = tex
	assert_that(Cartoon.texture_from_imported_material(std)).is_equal(tex)


func test_returns_null_for_standard_material_without_texture() -> void:
	var std := StandardMaterial3D.new()
	assert_that(Cartoon.texture_from_imported_material(std)).is_null()


func test_returns_null_for_non_standard_material() -> void:
	var shader_mat := Cartoon.world(Color.WHITE)
	assert_that(Cartoon.texture_from_imported_material(shader_mat)).is_null()


func test_returns_null_for_null_material_without_crashing() -> void:
	assert_that(Cartoon.texture_from_imported_material(null)).is_null()


# ------------------------------------------------------------------ bout-en-bout

## Le flux réel (ART-82, hors périmètre de cette tâche) : un MeshInstance3D
## importé depuis un repère `assets/models/props/wasteland/tripo/*.glb` porte
## un StandardMaterial3D par surface ; ce test vérifie que la chaîne complète
## (extraction -> reconstruction ink_toon) fonctionne sur une surface simulée
## de cette forme, sans dépendre d'un vrai fichier .glb sur disque.
func test_end_to_end_from_a_standard_material_surface() -> void:
	var mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	mi.mesh = BoxMesh.new()
	var std := StandardMaterial3D.new()
	var tex := _make_texture(Color("9c6a42"))
	std.albedo_texture = tex
	mi.set_surface_override_material(0, std)

	var imported_tex := Cartoon.texture_from_imported_material(mi.get_surface_override_material(0))
	var painted := Cartoon.painted_texture_prop(imported_tex)
	mi.set_surface_override_material(0, painted)

	var applied := mi.get_surface_override_material(0) as ShaderMaterial
	assert_that(applied.get_shader_parameter("albedo_texture")).is_equal(tex)
	assert_bool(applied.get_shader_parameter("use_albedo_texture")).is_true()
	assert_that(applied.next_pass).is_not_null()
