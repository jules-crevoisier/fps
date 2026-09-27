## test_bake_bot_spots_map.gd
## Spec (tâche "bots humains" passe 2, diagnostic lead : `bake_bot_spots.gd`
## échouait `BAKE_BOT_SPOTS_FAIL no_nav_region` sur toute carte AUTEURE
## -- Shipment comprise -- car l'ancien code instanciait un `MapSetup` NU,
## jamais posé à côté d'une VRAIE NavigationRegion3D, cf. le contrat de
## MapSetup.gd : "NavigationRegion3D... déjà présents comme enfants du nœud
## racine de la carte, frères de ce nœud"). `find_map_children` (fonction
## PURE, aucun ajout à l'arbre de scène) est la brique de recherche
## réutilisée par `_load_authored_map` pour extraire cette paire de frères
## d'une scène de carte instanciée -- testée isolément ici, sans charger de
## vraie scène ni toucher la navigation/la physique.
extends GdUnitTestSuite

const BakeToolScript := preload("res://tools/bake_bot_spots.gd")


func test_finds_nav_region_and_map_setup_among_siblings() -> void:
	var scene_root := Node3D.new()
	var deco := Node3D.new()
	var nav_region := NavigationRegion3D.new()
	var map_setup := MapSetup.new()
	scene_root.add_child(deco)
	scene_root.add_child(nav_region)
	scene_root.add_child(map_setup)

	var found := BakeToolScript.find_map_children(scene_root)

	assert_object(found.get("nav_region")).is_same(nav_region)
	assert_object(found.get("map_setup")).is_same(map_setup)

	scene_root.free()  # jamais ajouté à l'arbre : libération immédiate sûre.


func test_missing_nav_region_reports_null() -> void:
	var scene_root := Node3D.new()
	var map_setup := MapSetup.new()
	scene_root.add_child(map_setup)

	var found := BakeToolScript.find_map_children(scene_root)

	assert_object(found.get("nav_region")).is_null()
	assert_object(found.get("map_setup")).is_same(map_setup)

	scene_root.free()


func test_missing_map_setup_reports_null() -> void:
	var scene_root := Node3D.new()
	var nav_region := NavigationRegion3D.new()
	scene_root.add_child(nav_region)

	var found := BakeToolScript.find_map_children(scene_root)

	assert_object(found.get("nav_region")).is_same(nav_region)
	assert_object(found.get("map_setup")).is_null()

	scene_root.free()


func test_empty_scene_reports_both_null() -> void:
	var scene_root := Node3D.new()

	var found := BakeToolScript.find_map_children(scene_root)

	assert_object(found.get("nav_region")).is_null()
	assert_object(found.get("map_setup")).is_null()

	scene_root.free()


## Ignore les enfants du MAUVAIS type (jamais un faux positif sur un Node3D
## quelconque nommé "NavRegion"/"MapSetup" -- la recherche filtre par TYPE,
## pas par nom).
func test_ignores_wrong_typed_children_with_matching_names() -> void:
	var scene_root := Node3D.new()
	var fake_nav := Node3D.new()
	fake_nav.name = "NavRegion"
	var fake_setup := Node3D.new()
	fake_setup.name = "MapSetup"
	scene_root.add_child(fake_nav)
	scene_root.add_child(fake_setup)

	var found := BakeToolScript.find_map_children(scene_root)

	assert_object(found.get("nav_region")).is_null()
	assert_object(found.get("map_setup")).is_null()

	scene_root.free()
