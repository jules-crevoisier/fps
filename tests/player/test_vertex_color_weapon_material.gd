## Retour de test 2026-09-28 (« la moitié de l'arme est ouverte, le fond de l'arme ») : les modèles
## Tripo des quatre armes sont des coques ouvertes aux faces orientées dans les deux sens (le
## chargeur de la Rafale est entièrement retourné) — leur matériau à couleurs de sommet doit donc
## être rendu des DEUX côtés, sinon des pans entiers disparaissent selon l'angle.
extends GdUnitTestSuite

const ViewModelScript := preload("res://scripts/player/ViewModel.gd")


func test_vertex_color_material_uses_vertex_colours_as_albedo() -> void:
	var m := ViewModelScript.vertex_color_material(StandardMaterial3D.new())
	assert_bool(m.vertex_color_use_as_albedo).is_true()


func test_vertex_color_material_is_double_sided() -> void:
	var m := ViewModelScript.vertex_color_material(StandardMaterial3D.new())
	assert_int(m.cull_mode).is_equal(BaseMaterial3D.CULL_DISABLED)


func test_vertex_color_material_never_mutates_the_imported_material() -> void:
	var src := StandardMaterial3D.new()
	ViewModelScript.vertex_color_material(src)
	assert_bool(src.vertex_color_use_as_albedo).is_false()
	assert_int(src.cull_mode).is_equal(BaseMaterial3D.CULL_BACK)
