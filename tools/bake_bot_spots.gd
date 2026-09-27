## bake_bot_spots.gd
## Outil headless (BOT-05) : construit la carte `--map=<id>`, s'assure que sa
## navmesh est bakée, échantillonne ses données tactiques (BotSpots.bake) et
## sauvegarde `resources/bot_spots/<id>.tres`.
##
## `--map=test_arena` (par défaut) construit une PETITE SALLE TACTIQUE
## SYNTHÉTIQUE (murs en croix formant 4 quadrants + périmètre) — PAS
## `scenes/levels/test_arena.tscn` (le parcours de test de mouvement
## d'ArenaBuilder.gd, qui a de larges zones sans couverture proche : voir
## l'en-tête de scripts/ai/BotSpots.gd pour le détail de cette décision).
##
## Tout autre `map_id` (catalogue `MapCatalog`, ex. "shipment") CHARGE la
## vraie scène de carte (`scenes/levels/maps/<id>.tscn`) et n'EN EXTRAIT que sa
## `NavigationRegion3D` + son `MapSetup` (frères sous la racine de la carte —
## voir MapSetup.gd, "TOUS déjà présents comme enfants du nœud racine")
## reparentés sous un conteneur neuf (`_load_authored_map`) : la racine RÉELLE
## de la carte (script GameWorld.gd, HUD, MultiplayerSpawner...) n'est JAMAIS
## ajoutée à l'arbre, ce qui démarrerait un match complet (spawn joueur,
## réseau...) hors de portée d'un simple bake. Historique (avant tâche "bots
## humains" passe 2) : ce chemin instanciait un `MapSetup` NU, jamais posé à
## côté d'une VRAIE `NavigationRegion3D` -> `BAKE_BOT_SPOTS_FAIL
## no_nav_region` systématique sur toute carte authored (Shipment comprise).
##
##   godot --headless --path . -s res://tools/bake_bot_spots.gd -- --map=test_arena [--out=res://resources/bot_spots]
##   godot --headless --path . -s res://tools/bake_bot_spots.gd -- --map=shipment
##
## Affiche `BAKE_BOT_SPOTS_OK <map_id> spots=<n> ms=<t> path=<chemin>` puis
## quitte (0), ou `BAKE_BOT_SPOTS_SLOW ...` (budget de 30 s dépassé) /
## `BAKE_BOT_SPOTS_FAIL <raison>` (1).
extends SceneTree

const BOT_NAV := preload("res://scripts/ai/BotNavMesh.gd")
const MapCatalogScript := preload("res://scripts/levels/maps/MapCatalog.gd")

const DEFAULT_OUT_DIR := "res://resources/bot_spots"
## Frames physiques attendues après le bake (synchrone) avant d'interroger
## `NavigationServer3D` : la carte ne fusionne la géométrie de la région
## qu'après quelques frames — `map_get_iteration_id() != 0` devient vrai DÈS
## la synchro initiale de la carte, AVANT cette fusion (faux positif), et
## comparer le résultat d'une requête à un point connu se heurte au même
## risque quand ce point est proche de (0,0,0), la valeur de repli d'une
## requête faite trop tôt (observé empiriquement : convergence stable dès la
## frame 3). Un compte FIXE, généreux, est donc plus robuste ici qu'une
## détection — le coût (quelques ms) est négligeable face au budget de 30 s.
const NAV_SYNC_FRAMES := 15

var _map_id := "test_arena"
var _out_dir := DEFAULT_OUT_DIR
var _phase := 0
var _sync_frames := 0
var _start_ms := 0
var _root_node: Node3D
var _nav_region: NavigationRegion3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			_map_id = a.get_slice("=", 1)
		elif a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)


func _process(_delta: float) -> bool:
	match _phase:
		0:
			_start_ms = Time.get_ticks_msec()
			if not _setup_geometry():
				return true  # _setup_geometry a déjà imprimé l'échec et appelé quit().
			_phase = 1
			return false
		1:
			return _wait_nav_sync()
		2:
			return _bake_and_save()
	return true


func _setup_geometry() -> bool:
	if _map_id == "test_arena":
		_root_node = build_test_arena_room()
		root.add_child(_root_node)
		_nav_region = BOT_NAV.ensure_baked(_root_node)
	else:
		var loaded := _load_authored_map(_map_id)
		_root_node = loaded.get("container")
		_nav_region = loaded.get("nav_region")
	if _nav_region == null:
		printerr("BAKE_BOT_SPOTS_FAIL no_nav_region map=%s" % _map_id)
		quit(1)
		return false
	return true


## Charge la scène de carte du catalogue (MapCatalog) pour `map_id_` et n'EN
## EXTRAIT que sa NavigationRegion3D + son MapSetup (frères sous la racine de
## la carte, voir MapSetup.gd et `find_map_children` ci-dessous) sous un
## conteneur NEUF -- jamais la racine réelle de la carte (script GameWorld.gd),
## voir la docstring d'en-tête. Ajoute ce conteneur à `root` lui-même (au lieu
## de laisser l'appelant le faire) : c'est cet ajout qui déclenche
## `MapSetup._enter_tree()` -> le bake SYNCHRONE de la navmesh -> `nav_region`
## déjà rempli et bake dès le retour de cette fonction. `{}` si la carte est
## inconnue, sa scène introuvable, ou qu'elle n'a pas la paire NavigationRegion3D
## + MapSetup attendue (aucune carte du catalogue aujourd'hui ne devrait
## manquer l'un des deux -- voir la docstring de MapSetup.gd, "toute carte
## future qui suit la même recette").
func _load_authored_map(map_id_: String) -> Dictionary:
	var entry := MapCatalogScript.get_by_id(map_id_)
	if entry.is_empty():
		return {}
	var scene_path := String(entry.get("scene", ""))
	if not ResourceLoader.exists(scene_path):
		return {}
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return {}
	var scene_root := packed.instantiate()
	var found := find_map_children(scene_root)
	var nav_region: Node = found.get("nav_region")
	var map_setup: Node = found.get("map_setup")
	if nav_region == null or map_setup == null:
		scene_root.free()
		return {}
	var container := Node3D.new()
	container.name = "BakeBotSpotsMapRoot"
	# `owner` de chaque nœud de la scène instanciée pointe vers `scene_root`
	# (convention PackedScene.instantiate()) -- à effacer AVANT de reparenter
	# sous `container`, sinon Godot journalise "will make owner inconsistent"
	# (et fuit l'ancien propriétaire à la sortie du process, `scene_root` étant
	# libéré juste après).
	_clear_owner_recursive(nav_region)
	_clear_owner_recursive(map_setup)
	scene_root.remove_child(nav_region)
	container.add_child(nav_region)
	scene_root.remove_child(map_setup)
	container.add_child(map_setup)
	scene_root.free()  # le reste de la carte (GameWorld/HUD/spawner...) n'a jamais rejoint l'arbre -- libre sans effet de bord.
	root.add_child(container)  # déclenche MapSetup._enter_tree() -> bake synchrone.
	return {"container": container, "nav_region": (map_setup as MapSetup).nav_region}


## Efface `owner` sur `node` et toute sa descendance -- voir l'appel ci-dessus.
static func _clear_owner_recursive(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner_recursive(child)


## Recherche PURE (aucun effet de bord, ne modifie pas l'arbre) des enfants
## DIRECTS "NavigationRegion3D" et "MapSetup" de `scene_root` -- même
## convention de frères que `MapSetup._find_nav_region`. Factorisée pour être
## testée isolément (tests/tools/test_bake_bot_spots_map.gd) sans charger de
## vraie scène de carte ni toucher l'arbre de scène.
static func find_map_children(scene_root: Node) -> Dictionary:
	var nav_region: Node = null
	var map_setup: Node = null
	for child in scene_root.get_children():
		if nav_region == null and child is NavigationRegion3D:
			nav_region = child
		if map_setup == null and child is MapSetup:
			map_setup = child
	return {"nav_region": nav_region, "map_setup": map_setup}


func _wait_nav_sync() -> bool:
	_sync_frames += 1
	if _sync_frames >= NAV_SYNC_FRAMES:
		_phase = 2
	return false


func _bake_and_save() -> bool:
	var space := _root_node.get_world_3d().direct_space_state
	var spots := BotSpots.bake(_map_id, _nav_region, space)
	var elapsed_ms := Time.get_ticks_msec() - _start_ms

	var abs_dir := ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var path := "%s/%s.tres" % [_out_dir, _map_id]
	var err := ResourceSaver.save(spots, path)
	if err != OK:
		printerr("BAKE_BOT_SPOTS_FAIL save_error_%d path=%s" % [err, path])
		quit(1)
		return true

	var within_budget := elapsed_ms < BotSpots.BAKE_BUDGET_MS
	print("BAKE_BOT_SPOTS_%s %s spots=%d ms=%d path=%s" % [
		"OK" if within_budget else "SLOW", _map_id, spots.spots.size(), elapsed_ms, path])
	quit(0 if within_budget else 1)
	return true


## Salle tactique synthétique : périmètre + murs en croix (avec porte centrale
## de 3 m) formant 4 quadrants d'environ 10x10 m. Choisie pour que le pire cas
## (centre d'un quadrant) reste à ~5 m d'un mur ALIGNÉ sur l'une des 4
## directions cardinales de BotSpots.DIRECTIONS — bien sous BotSpots.COVER_RANGE
## (6 m) — garantissant par construction qu'aucun point navigable n'est loin
## de toute couverture (voir l'en-tête de scripts/ai/BotSpots.gd). `static` et
## PUBLIQUE : réutilisée telle quelle par tests/ai/test_bot_spots.gd (même
## salle que celle réellement bakée, sans dupliquer la géométrie, et sans
## instancier ce SceneTree — un appel statique n'en a pas besoin).
static func build_test_arena_room() -> Node3D:
	var arena := Node3D.new()
	arena.name = "BotSpotsTestArena"
	const H := 4.0
	# Périmètre (20x20 m intérieur).
	_wall(arena, Vector3(0, H * 0.5, -10.5), Vector3(22, H, 1))
	_wall(arena, Vector3(0, H * 0.5, 10.5), Vector3(22, H, 1))
	_wall(arena, Vector3(-10.5, H * 0.5, 0), Vector3(1, H, 22))
	_wall(arena, Vector3(10.5, H * 0.5, 0), Vector3(1, H, 22))
	# Croix intérieure (porte de 3 m au centre pour garder la navmesh connexe).
	_wall(arena, Vector3(0, H * 0.5, -5.75), Vector3(1, H, 8.5))
	_wall(arena, Vector3(0, H * 0.5, 5.75), Vector3(1, H, 8.5))
	_wall(arena, Vector3(-5.75, H * 0.5, 0), Vector3(8.5, H, 1))
	_wall(arena, Vector3(5.75, H * 0.5, 0), Vector3(8.5, H, 1))
	# Sol.
	_wall(arena, Vector3(0, -0.5, 0), Vector3(22, 1, 22))
	return arena


static func _wall(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
