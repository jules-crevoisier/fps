## bake_bot_spots.gd
## Outil headless (BOT-05) : construit la carte `--map=<id>`, s'assure que sa
## navmesh est bakée, échantillonne ses données tactiques (BotSpots.bake) et
## sauvegarde `resources/bot_spots/<id>.tres`.
##
## `--map=test_arena` (par défaut) construit une PETITE SALLE TACTIQUE
## SYNTHÉTIQUE (murs en croix formant 4 quadrants + périmètre) — PAS
## `scenes/levels/test_arena.tscn` (le parcours de test de mouvement
## d'ArenaBuilder.gd, qui a de larges zones sans couverture proche : voir
## l'en-tête de scripts/ai/BotSpots.gd pour le détail de cette décision). Tout
## autre `map_id` du catalogue (MapCatalog) utilise `MapSetup`, qui bake déjà
## sa propre NavigationRegion3D.
##
##   godot --headless --path . -s res://tools/bake_bot_spots.gd -- --map=test_arena [--out=res://resources/bot_spots]
##
## Affiche `BAKE_BOT_SPOTS_OK <map_id> spots=<n> ms=<t> path=<chemin>` puis
## quitte (0), ou `BAKE_BOT_SPOTS_SLOW ...` (budget de 30 s dépassé) /
## `BAKE_BOT_SPOTS_FAIL <raison>` (1).
extends SceneTree

const MapSetupScript := preload("res://scripts/levels/maps/MapSetup.gd")
const BOT_NAV := preload("res://scripts/ai/BotNavMesh.gd")

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
		var setup := MapSetupScript.new()
		setup.map_id = _map_id
		root.add_child(setup)
		_root_node = setup
		_nav_region = setup.nav_region
	if _nav_region == null:
		printerr("BAKE_BOT_SPOTS_FAIL no_nav_region map=%s" % _map_id)
		quit(1)
		return false
	return true


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
