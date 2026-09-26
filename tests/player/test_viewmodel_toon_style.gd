## test_viewmodel_toon_style.gd
## Style BD (2026-09-26) : l'arme viewmodel (Ravage -- seule entrée de
## WeaponDatabase.PATHS aujourd'hui) et les gants (fp_gloves.glb, portés quelle
## que soit l'arme) passent par ToonStyle.toon_material au lieu de
## Cartoon.painted_texture_prop pour toute surface marquée `_PAINTED_MATERIAL_
## MARKER` -- voir ViewModel.gd `_apply_cartoon_materials`/
## `_apply_glove_materials`. Testé en isolation (pas de PlayerController/Weapon
## réels : ces deux méthodes ne lisent que leur paramètre `model`/`glove`).
extends GdUnitTestSuite

const _TOON_SHADER := preload("res://assets/shaders/toon_bd.gdshader")


func _make_texture(color: Color = Color.WHITE) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## `mesh.material` (PrimitiveMesh), jamais `set_surface_override_material` : les
## deux méthodes lues ici (`_apply_cartoon_materials`/`_apply_glove_materials`)
## lisent `mesh.mesh.surface_get_material(i)` -- le matériau posé SUR LA
## RESSOURCE MESH elle-même, exactement ce que produit un import glTF Tripo
## (voir leur docstring), jamais un `surface_override_material` d'instance.
func _painted_mesh(material_name: String, tex: Texture2D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	var std := StandardMaterial3D.new()
	std.resource_name = material_name
	std.albedo_texture = tex
	box.material = std
	mi.mesh = box
	return mi


func test_weapon_painted_surface_uses_toon_style() -> void:
	var vm: ViewModel = auto_free(ViewModel.new())
	var model: Node3D = auto_free(Node3D.new())
	var tex := _make_texture(Color("9c6a42"))
	var mesh := _painted_mesh("body_painted", tex)
	model.add_child(mesh)

	vm._apply_cartoon_materials(model)

	var applied := mesh.get_surface_override_material(0) as ShaderMaterial
	assert_that(applied.shader).is_equal(_TOON_SHADER)
	assert_that(applied.get_shader_parameter("albedo_texture")).is_equal(tex)


func test_glove_painted_surface_uses_toon_style() -> void:
	var vm: ViewModel = auto_free(ViewModel.new())
	var glove: Node3D = auto_free(Node3D.new())
	var tex := _make_texture(Color("d2a46c"))
	var mesh := _painted_mesh("glove_painted", tex)
	glove.add_child(mesh)

	vm._apply_glove_materials(glove)

	var applied := mesh.get_surface_override_material(0) as ShaderMaterial
	assert_that(applied.shader).is_equal(_TOON_SHADER)
	assert_that(applied.get_shader_parameter("albedo_texture")).is_equal(tex)
