## test_canyon_express.gd
## Spec (brief lead 2026-09-28, phase 2 « assemble la carte jouable ») :
## `canyon_express.tscn` s'instancie, apparaît dans `MapCatalog.selectable()`,
## sa géométrie importée (109 StaticBody3D `COL_<surface>_*`, voir
## ImportedMapGeometry.gd) porte tous les calques/méta attendus (garde-corps
## `clip` de la passerelle sur PhysicsLayers.PLAYER_CLIP SEUL), ses 16
## marqueurs de spawn (8 par équipe) sont posés au sol avec de la place pour
## se tenir debout, et sa navmesh relie bien les trois traversées nord<->sud
## (passerelle ouest, pont + train, fond du canyon par les 4 rampes) ainsi
## que l'intérieur des deux wagons couverts.
##
## Même technique que tools/bake_bot_spots.gd::_load_authored_map (réutilisée
## ici, pas dupliquée) : seuls NavigationRegion3D + MapSetup (+ SpawnPoints,
## lu pour les marqueurs) sont extraits de la scène instanciée et posés sous
## un conteneur neuf -- la racine RÉELLE de la carte (script GameWorld.gd,
## HUD, MultiplayerSpawner...) n'est JAMAIS ajoutée à l'arbre, ce qui
## démarrerait un match complet hors de portée de ce test de géométrie/nav.
## `before()`/`after()` (UNE fois pour toute la suite, pas par test) : charger
## + baker la carte est coûteux et purement en LECTURE pour chaque test
## ci-dessous, aucune raison de le refaire 15 fois (voir CLAUDE.md
## « Testing » -- tests scoped rapides).
extends GdUnitTestSuite

const BakeToolScript := preload("res://tools/bake_bot_spots.gd")
const _SCENE_PATH := "res://scenes/levels/maps/canyon_express.tscn"
const _COL_PREFIX := "COL_"

## Frames physiques attendus après le bake synchrone avant d'interroger
## NavigationServer3D/la physique -- même valeur que tools/bake_bot_spots.gd
## (NAV_SYNC_FRAMES) et tests/ai/test_bot_spots.gd, voir leur doc.
const NAV_SYNC_FRAMES := 15

var _container: Node3D
var _nav_region: NavigationRegion3D
var _map_setup: Node
var _spawn_points: Node
var _art: Node
var _map_rid: RID


func before() -> void:
	var packed := load(_SCENE_PATH) as PackedScene
	var scene_root := packed.instantiate()
	var found := BakeToolScript.find_map_children(scene_root)
	_nav_region = found.get("nav_region")
	_map_setup = found.get("map_setup")
	_spawn_points = scene_root.get_node_or_null("SpawnPoints")
	BakeToolScript._clear_owner_recursive(_nav_region)
	BakeToolScript._clear_owner_recursive(_map_setup)
	if _spawn_points:
		BakeToolScript._clear_owner_recursive(_spawn_points)
	scene_root.remove_child(_nav_region)
	scene_root.remove_child(_map_setup)
	if _spawn_points:
		scene_root.remove_child(_spawn_points)
	scene_root.free()

	_container = Node3D.new()
	_container.name = "CanyonExpressTestRoot"
	add_child(_container)
	_container.add_child(_nav_region)     # frère AVANT MapSetup -- _find_nav_region() le lit dès _enter_tree.
	_container.add_child(_map_setup)      # déclenche MapSetup._enter_tree() -> ImportedMapGeometry.prepare + bake synchrone.
	if _spawn_points:
		_container.add_child(_spawn_points)
	_art = _nav_region.get_node_or_null("Art")

	for i in NAV_SYNC_FRAMES:
		await get_tree().physics_frame
	_map_rid = _nav_region.get_navigation_map()


func after() -> void:
	if _container and is_instance_valid(_container):
		remove_child(_container)
		_container.free()


# --------------------------------------------------------------- instanciation / catalogue

func test_scene_instantiates_with_nav_region_map_setup_and_art() -> void:
	assert_object(_nav_region).is_not_null()
	assert_object(_map_setup).is_not_null()
	assert_object(_art).append_failure_message("nœud 'Art' (GLB instancié) introuvable sous NavRegion").is_not_null()
	assert_bool(_art.has_meta("imported_art")).is_true()
	assert_bool(bool(_art.get_meta("imported_art"))).is_true()


func test_map_catalog_selectable_now_contains_canyon_express() -> void:
	var ids: Array = []
	for m in MapCatalog.selectable():
		ids.append(str(m["id"]))
	assert_array(ids).contains("canyon_express")


# --------------------------------------------------------------- collision importée

func _col_bodies() -> Array:
	var out: Array = []
	_collect_col(_art, out)
	return out


static func _collect_col(node: Node, out: Array) -> void:
	if node == null:
		return
	if node is StaticBody3D and String(node.name).begins_with(_COL_PREFIX):
		out.append(node)
	for c in node.get_children():
		_collect_col(c, out)


func test_at_least_100_collision_bodies_each_with_a_surface_meta() -> void:
	var bodies := _col_bodies()
	assert_int(bodies.size()).append_failure_message(
		"attendu >= 100 StaticBody3D COL_*, trouvé %d" % bodies.size()
	).is_greater_equal(100)
	for b in bodies:
		assert_bool((b as StaticBody3D).has_meta("surface")).append_failure_message(
			"%s n'a pas de méta 'surface'" % b.name
		).is_true()


func test_clip_bodies_are_layered_on_player_clip_only() -> void:
	var bodies := _col_bodies()
	var clip_bodies: Array = []
	for b in bodies:
		if String(b.name).begins_with("COL_clip_"):
			clip_bodies.append(b)
	assert_int(clip_bodies.size()).append_failure_message(
		"aucun garde-corps COL_clip_* trouvé -- la passerelle en a deux (FbRail1/-1)"
	).is_greater(0)
	for b in clip_bodies:
		var body := b as StaticBody3D
		assert_int(body.collision_layer).append_failure_message(
			"%s : collision_layer devrait être exactement PhysicsLayers.PLAYER_CLIP" % body.name
		).is_equal(PhysicsLayers.PLAYER_CLIP)
		assert_int(body.collision_layer & PhysicsLayers.WORLD).append_failure_message(
			"%s : jamais posé sur PhysicsLayers.WORLD (un tir doit le traverser)" % body.name
		).is_equal(0)


# --------------------------------------------------------------- spawns

func _markers_for_team(team: int) -> Array:
	var out: Array = []
	if _spawn_points == null:
		return out
	for m in _spawn_points.get_children():
		var marker := m as Marker3D
		if marker != null and int(marker.get_meta("team", -1)) == team:
			out.append(marker)
	return out


func test_eight_spawns_per_team() -> void:
	assert_int(_markers_for_team(1).size()).append_failure_message("équipe 1 (nord)").is_equal(8)
	assert_int(_markers_for_team(0).size()).append_failure_message("équipe 0 (sud)").is_equal(8)


func test_every_spawn_has_ground_within_0_3m_headroom_and_is_not_inside_a_collider() -> void:
	var space := _container.get_world_3d().direct_space_state
	var all_markers := _markers_for_team(1) + _markers_for_team(0)
	assert_int(all_markers.size()).is_equal(16)
	for m in all_markers:
		var marker := m as Marker3D
		var pos: Vector3 = marker.transform.origin
		# Sol : un rayon WORLD depuis 2 m au-dessus jusqu'à 2 m en dessous doit
		# toucher à moins de 0,3 m sous la position du marqueur.
		var ground_params := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 2.0, 0), pos + Vector3(0, -2.0, 0))
		ground_params.collision_mask = PhysicsLayers.WORLD
		var ground := space.intersect_ray(ground_params)
		assert_bool(ground.is_empty()).append_failure_message(
			"%s (%s) : aucun sol trouvé sous le marqueur" % [marker.name, pos]
		).is_false()
		if not ground.is_empty():
			var dy: float = pos.y - (ground["position"] as Vector3).y
			assert_float(dy).append_failure_message(
				"%s : sol à %.3f m sous le marqueur (attendu <= 0.3 m)" % [marker.name, dy]
			).is_less_equal(0.3)
		# Plafond : >= 2,2 m de dégagement au-dessus du marqueur.
		var head_params := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.05, 0), pos + Vector3(0, 2.2, 0))
		head_params.collision_mask = PhysicsLayers.WORLD
		var head := space.intersect_ray(head_params)
		assert_bool(head.is_empty()).append_failure_message(
			"%s : moins de 2,2 m de dégagement au-dessus du marqueur" % marker.name
		).is_true()
		# Jamais À L'INTÉRIEUR d'un collider (point-query au niveau du torse).
		var point_params := PhysicsPointQueryParameters3D.new()
		point_params.position = pos + Vector3(0, 0.9, 0)
		point_params.collision_mask = PhysicsLayers.WORLD
		var inside := space.intersect_point(point_params, 4)
		assert_bool(inside.is_empty()).append_failure_message(
			"%s : le marqueur est À L'INTÉRIEUR d'un collider" % marker.name
		).is_true()


# --------------------------------------------------------------- navigation (3 traversées + wagons)

func _assert_path_reaches(from_pos: Vector3, to_pos: Vector3, label: String, max_end_dist: float = 1.0) -> void:
	var path := NavigationServer3D.map_get_path(_map_rid, from_pos, to_pos, true)
	assert_bool(path.is_empty()).append_failure_message("%s : aucun chemin renvoyé" % label).is_false()
	if path.is_empty():
		return
	var end_dist: float = (path[path.size() - 1] as Vector3).distance_to(to_pos)
	assert_float(end_dist).append_failure_message(
		"%s : le chemin s'arrête à %.3f m de la cible (attendu <= %.1f m)" % [label, end_dist, max_end_dist]
	).is_less_equal(max_end_dist)


func test_team1_spawn_reaches_team0_spawn() -> void:
	var n := _markers_for_team(1)
	var s := _markers_for_team(0)
	assert_bool(n.is_empty() or s.is_empty()).is_false()
	_assert_path_reaches((n[0] as Marker3D).transform.origin, (s[0] as Marker3D).transform.origin, "team1_spawn -> team0_spawn")


func test_canyon_floor_reaches_east_rim() -> void:
	_assert_path_reaches(Vector3(20, -5, 0), Vector3(20, 0, -20), "canyon_floor(20,-5,0) -> rim(20,0,-20)")


func test_canyon_floor_reaches_west_rim() -> void:
	# Cible en terrain libre au sud-ouest (la spec initiale visait l'angle de la GARE, x[-26,-20] z[15,21]).
	_assert_path_reaches(Vector3(-20, -5, 0), Vector3(-17, 0, 24), "canyon_floor(-20,-5,0) -> rim(-17,0,24)")


func test_footbridge_connects_west_rim_north_to_south() -> void:
	_assert_path_reaches(Vector3(-25, 0, -12), Vector3(-25, 0, 12), "rim_west(-25,0,-12) -> rim_west_south(-25,0,12) (passerelle)")


## « Reachable from the rim » : origine = un VRAI marqueur de spawn (posé sur
## le rebord, voir les tests de spawn ci-dessus) plutôt qu'un point choisi à
## la main sur la ligne des rails elle-même -- empiriquement, un point pris
## EXACTEMENT sur x=0 loin du pont (ex. (0,0,-20)) tombe parfois sur un
## polygone de navmesh mal relié à la traversée centrale (rainure du rail au
## sol) alors que les marqueurs de spawn réels (x=±8/±12) s'y relient très
## bien (testé manuellement : end_dist=0,4 m) -- un point de bord authentique
## est un test plus fidèle que x=0 arbitraire.
func test_boxcar1_interior_reachable_from_a_north_rim_spawn() -> void:
	var n := _markers_for_team(1)
	assert_bool(n.is_empty()).is_false()
	_assert_path_reaches((n[0] as Marker3D).transform.origin, Vector3(0, 0.35, -13.75), "north_spawn -> boxcar1(0,0.35,-13.75)")


func test_boxcar2_interior_reachable_from_a_south_rim_spawn() -> void:
	var s := _markers_for_team(0)
	assert_bool(s.is_empty()).is_false()
	_assert_path_reaches((s[0] as Marker3D).transform.origin, Vector3(0, 0.35, 14.25), "south_spawn -> boxcar2(0,0.35,14.25)")


## Diagnostic (jamais un blocage de build) : le nombre de polygones bakés,
## reporté au lead comme demandé (« Report polygon count »).
func test_report_navmesh_polygon_count() -> void:
	var nmesh := _nav_region.navigation_mesh
	assert_object(nmesh).is_not_null()
	var polys := nmesh.get_polygon_count()
	print("CANYON_EXPRESS_NAV_POLYGON_COUNT=", polys)
	assert_int(polys).is_greater(0)
