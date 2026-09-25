## test_bot_spots.gd
## Spec (BOT-05, docs/research/02_bots_ai.md §2.5/§2.6, tasks/backlog.yaml) :
## une ressource de données tactiques par carte, échantillonnée sur la
## navmesh (pas ~2 m), avec couverture par direction (8 compas, accroupi ET
## debout, rayons physiques), un flag "sniping" (ligne de vue dégagée > 30 m),
## des points d'approche par CHEMIN de navigation (jamais à vol d'oiseau), et
## sur la salle tactique de test : >= 1 spot couvert à < 10 m (chemin) de
## chaque point navigable, bake < 30 s.
##
## Scènes physiques minimales et réelles (StaticBody3D ajoutés à l'arbre,
## navmesh bakée via BotNavMesh.ensure_baked, synchronisée via
## `await get_tree().physics_frame` avant toute requête), comme
## tests/maps/test_navmesh.gd / tests/agents/test_ability_rays.gd. Chaque
## test reçoit un offset XZ dédié pour ne jamais partager d'espace physique ou
## de navmesh avec un autre test (voir `_teardown` : la NavigationRegion3D
## bakée est un enfant du sous-nœud de test, libéré à la fin).
extends GdUnitTestSuite

const BakeToolScript := preload("res://tools/bake_bot_spots.gd")

## Frames physiques attendues après le bake (synchrone) avant d'interroger
## `NavigationServer3D` : voir tools/bake_bot_spots.gd::NAV_SYNC_FRAMES pour
## le détail (un compte fixe est plus robuste ici qu'une détection basée sur
## `map_get_iteration_id`, qui peut donner un faux positif AVANT que la
## géométrie de la région ne soit réellement fusionnée dans la carte).
const NAV_SYNC_FRAMES := 15

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 200.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


func _room(offset: Vector3) -> Node3D:
	var root_node := Node3D.new()
	root_node.name = "BotSpotsTestRoom"
	root_node.position = offset
	add_child(root_node)
	return root_node


func _wall(parent: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
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
	return body


## Sol de `size_x` x `size_z` centré sur `offset` (surface à offset.y).
func _floor(parent: Node3D, center: Vector3, size_x: float, size_z: float) -> void:
	_wall(parent, center + Vector3(0, -0.5, 0), Vector3(size_x, 1, size_z))


func _bake_room(root_node: Node3D) -> Dictionary:
	var nav := BotNavMesh.ensure_baked(root_node)
	for i in NAV_SYNC_FRAMES:
		await get_tree().physics_frame
	return {"nav": nav, "space": root_node.get_world_3d().direct_space_state}


func _teardown(root_node: Node3D) -> void:
	remove_child(root_node)
	root_node.free()
	await get_tree().physics_frame


## Le spot échantillonné le plus proche de `local_pos` (espace du sous-nœud
## de test, PAS espace monde — les positions bakées sont en espace monde).
static func _nearest_spot(spots: Array[Dictionary], world_pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for s in spots:
		var d: float = (s["position"] as Vector3).distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = s
	return best


# ======================================================================
#  is_covered() — pure, sans scène.
# ======================================================================
func test_is_covered_true_when_any_direction_blocked() -> void:
	var spot := {
		"coverage_crouch": [false, false, false, false, false, false, false, false],
		"coverage_stand": [false, true, false, false, false, false, false, false],
	}
	assert_bool(BotSpots.is_covered(spot)).is_true()


func test_is_covered_false_when_all_open() -> void:
	var spot := {
		"coverage_crouch": [false, false, false, false, false, false, false, false],
		"coverage_stand": [false, false, false, false, false, false, false, false],
	}
	assert_bool(BotSpots.is_covered(spot)).is_false()


func test_load_for_map_missing_returns_null() -> void:
	assert_that(BotSpots.load_for_map("__no_such_map__")).is_null()


# ======================================================================
#  Couverture par direction (8 compas) — un seul mur, une seule direction.
# ======================================================================
func test_coverage_blocks_only_the_walled_direction() -> void:
	var offset := _offset()
	var root_node := _room(offset)
	_floor(root_node, Vector3(0, 0, 0), 12, 12)
	# Mur au NORD (+Z, DIRECTIONS[0]) à 3 m, bien sous COVER_RANGE (6 m).
	_wall(root_node, Vector3(0, 2, 3), Vector3(4, 4, 0.5))
	var setup := await _bake_room(root_node)

	var spots := BotSpots.bake("coverage_test", setup["nav"], setup["space"])
	var spot := _nearest_spot(spots.spots, root_node.global_transform * Vector3(0, 0, 0))

	assert_that(spot).is_not_empty()
	var cov: Array = spot["coverage_stand"]
	assert_bool(cov[0]).append_failure_message("nord (mur à 3 m) devrait être couvert").is_true()
	assert_bool(cov[2]).append_failure_message("est (rien) devrait être ouvert").is_false()
	assert_bool(cov[4]).append_failure_message("sud (rien) devrait être ouvert").is_false()
	await _teardown(root_node)


func test_crouch_vs_stand_distinguishes_low_wall() -> void:
	var offset := _offset()
	var root_node := _room(offset)
	_floor(root_node, Vector3(0, 0, 0), 12, 12)
	# Muret à l'EST (+X, DIRECTIONS[2]) : haut de 1.5 m depuis le sol. La
	# navmesh bakée place ses points un peu AU-DESSUS du sol physique (marge
	# d'agent Recast, ~0.4 m ici) : le rayon "accroupi" part donc d'environ
	# 1.3 m réels (< 1.5 m, touche) et le rayon "debout" d'environ 2.0 m réels
	# (> 1.5 m, passe au-dessus) — large marge des deux côtés.
	_wall(root_node, Vector3(3, 0.75, 0), Vector3(0.5, 1.5, 4))
	var setup := await _bake_room(root_node)

	var spots := BotSpots.bake("crouch_test", setup["nav"], setup["space"])
	var spot := _nearest_spot(spots.spots, root_node.global_transform * Vector3(0, 0, 0))

	assert_that(spot).is_not_empty()
	var cov_c: Array = spot["coverage_crouch"]
	var cov_s: Array = spot["coverage_stand"]
	assert_bool(cov_c[2]).append_failure_message("accroupi : le muret de 1.5 m devrait bloquer").is_true()
	assert_bool(cov_s[2]).append_failure_message("debout : le rayon passe au-dessus du muret de 1.5 m").is_false()
	await _teardown(root_node)


# ======================================================================
#  Flag sniping — ligne de vue dégagée > 30 m, ou salle fermée = jamais.
# ======================================================================
func test_sniping_true_with_long_clear_sightline() -> void:
	var offset := _offset()
	var root_node := _room(offset)
	# Long couloir dégagé vers le NORD (DIRECTIONS[0]), 45 m > SNIPE_RANGE (30 m).
	_floor(root_node, Vector3(0, 0, 20), 6, 46)
	var setup := await _bake_room(root_node)

	var spots := BotSpots.bake("sniping_open_test", setup["nav"], setup["space"])
	var spot := _nearest_spot(spots.spots, root_node.global_transform * Vector3(0, 0, -1))

	assert_that(spot).is_not_empty()
	assert_bool(spot["sniping"]).append_failure_message("couloir de 45 m dégagé : sniping attendu").is_true()
	await _teardown(root_node)


func test_sniping_false_when_fully_enclosed() -> void:
	var offset := _offset()
	var root_node := _room(offset)
	_floor(root_node, Vector3(0, 0, 0), 6, 6)
	_wall(root_node, Vector3(0, 2, 3), Vector3(6, 4, 0.5))
	_wall(root_node, Vector3(0, 2, -3), Vector3(6, 4, 0.5))
	_wall(root_node, Vector3(3, 2, 0), Vector3(0.5, 4, 6))
	_wall(root_node, Vector3(-3, 2, 0), Vector3(0.5, 4, 6))
	var setup := await _bake_room(root_node)

	var spots := BotSpots.bake("sniping_closed_test", setup["nav"], setup["space"])
	var spot := _nearest_spot(spots.spots, root_node.global_transform * Vector3(0, 0, 0))

	assert_that(spot).is_not_empty()
	assert_bool(spot["sniping"]).append_failure_message("petite salle fermée 6x6 : aucune ligne de vue > 30 m").is_false()
	assert_bool(BotSpots.is_covered(spot)).append_failure_message("entourée de murs proches : devrait être couverte").is_true()
	await _teardown(root_node)


# ======================================================================
#  Points d'approche — CHEMIN de navigation, jamais à vol d'oiseau.
# ======================================================================
func test_approach_points_use_path_distance_not_euclidean() -> void:
	var offset := _offset()
	var root_node := _room(offset)
	# Deux plateformes séparées par un VIDE (x entre -1 et 1 : aucun sol) —
	# à ~3 m à vol d'oiseau l'une de l'autre (<= APPROACH_RANGE = 4 m), mais
	# reliées SEULEMENT par un long détour en U (~19 m de chemin réel).
	_floor(root_node, Vector3(-3, 0, 0), 4, 4)   # FloorA : x[-5,-1] z[-2,2]
	_floor(root_node, Vector3(3, 0, 0), 4, 4)    # FloorB : x[1,5] z[-2,2]
	_floor(root_node, Vector3(-1.5, 0, 6), 3, 8)  # montée depuis A : x[-3,0] z[2,10]
	_floor(root_node, Vector3(0, 0, 9.5), 6, 3)   # traversée : x[-3,3] z[8,11]
	_floor(root_node, Vector3(1.5, 0, 6), 3, 8)   # descente vers B : x[0,3] z[2,10]
	var setup := await _bake_room(root_node)

	var spots := BotSpots.bake("detour_test", setup["nav"], setup["space"])
	assert_int(spots.spots.size()).append_failure_message("échantillonnage vide : géométrie invalide").is_greater(4)

	# Le point de FloorA le plus proche (à vol d'oiseau) de FloorB, et vice versa.
	var spot_a := _closest_across(spots.spots, root_node, true)
	var spot_b := _closest_across(spots.spots, root_node, false)
	assert_that(spot_a).is_not_empty()
	assert_that(spot_b).is_not_empty()
	var pos_a: Vector3 = spot_a["position"]
	var pos_b: Vector3 = spot_b["position"]
	assert_float(pos_a.distance_to(pos_b)).append_failure_message(
		"le scénario suppose A/B proches à vol d'oiseau (<= 4 m)").is_less_equal(4.0)

	var approach_a: PackedVector3Array = spot_a["approach_points"]
	assert_bool(approach_a.has(pos_b)).append_failure_message(
		"A et B sont proches À VOL D'OISEAU mais à ~19 m de CHEMIN réel : "
		+ "B ne doit PAS être un point d'approche de A").is_false()

	# Cas positif : un point de FloorA proche par le VRAI chemin est bien retenu.
	var near_a := _second_nearest_on_same_floor(spots.spots, pos_a)
	assert_that(near_a).is_not_empty()
	assert_bool(approach_a.has(near_a["position"] as Vector3)).append_failure_message(
		"un point voisin ATTEIGNABLE sur la même plateforme devrait être un point d'approche").is_true()
	await _teardown(root_node)


## Point de `floor_a` (x local < -1, si `want_a`) ou `floor_b` (x local > 1)
## le plus proche de l'AUTRE plateforme, à vol d'oiseau.
static func _closest_across(spots: Array[Dictionary], root_node: Node3D, want_a: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_x := -INF if want_a else INF
	for s in spots:
		var local: Vector3 = root_node.global_transform.affine_inverse() * (s["position"] as Vector3)
		if want_a and local.x < -1.0 and local.x > best_x:
			best_x = local.x
			best = s
		elif not want_a and local.x > 1.0 and local.x < best_x:
			best_x = local.x
			best = s
	return best


## Un AUTRE spot dont la position monde est la plus proche de `pos` (hors
## `pos` lui-même) — sert à vérifier un cas d'approche valide (même plateforme).
static func _second_nearest_on_same_floor(spots: Array[Dictionary], pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for s in spots:
		var p: Vector3 = s["position"]
		if p == pos:
			continue
		var d := p.distance_to(pos)
		if d < best_d:
			best_d = d
			best = s
	return best


# ======================================================================
#  Acceptance BOT-05 : salle tactique "test_arena" — couverture <= 10 m
#  (CHEMIN, pas à vol d'oiseau) de chaque point navigable, bake < 30 s.
# ======================================================================
func test_test_arena_room_meets_cover_within_10m_acceptance() -> void:
	var offset := _offset()
	var room := BakeToolScript.build_test_arena_room()
	room.position = offset
	add_child(room)
	var setup := await _bake_room(room)

	var start_ms := Time.get_ticks_msec()
	var spots := BotSpots.bake("test_arena", setup["nav"], setup["space"])
	var elapsed_ms := Time.get_ticks_msec() - start_ms

	assert_int(spots.spots.size()).append_failure_message("salle tactique : échantillonnage vide").is_greater(10)
	assert_int(elapsed_ms).append_failure_message("bake=%dms, budget=%dms" % [elapsed_ms, BotSpots.BAKE_BUDGET_MS]).is_less(BotSpots.BAKE_BUDGET_MS)

	var map_rid := room.get_world_3d().get_navigation_map()
	var uncovered: Array = []
	for s in spots.spots:
		if BotSpots.is_covered(s):
			continue
		if not _has_covered_spot_within_path(spots.spots, s, map_rid, 10.0):
			uncovered.append(s["position"])
	assert_int(uncovered.size()).append_failure_message(
		"points sans spot couvert à < 10 m de chemin : %s" % [uncovered]).is_equal(0)
	await _teardown(room)


## Vrai s'il existe, parmi `spots`, un spot COUVERT dont le CHEMIN de
## navigation depuis `origin` mesure au plus `max_path` — pré-filtré à vol
## d'oiseau (marge x2.5) pour la performance UNIQUEMENT, jamais comme verdict.
static func _has_covered_spot_within_path(spots: Array[Dictionary], origin: Dictionary, map_rid: RID, max_path: float) -> bool:
	var origin_pos: Vector3 = origin["position"]
	for s in spots:
		if not BotSpots.is_covered(s):
			continue
		var candidate: Vector3 = s["position"]
		if origin_pos.distance_to(candidate) > max_path * 2.5:
			continue
		var path := NavigationServer3D.map_get_path(map_rid, origin_pos, candidate, true)
		if path.size() < 2:
			continue
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		if length <= max_path:
			return true
	return false


# ======================================================================
#  Ressource livrée : resources/bot_spots/test_arena.tres chargeable.
# ======================================================================
func test_shipped_test_arena_resource_is_valid() -> void:
	var spots := BotSpots.load_for_map("test_arena")
	assert_that(spots).append_failure_message(
		"resources/bot_spots/test_arena.tres manquant — lancer tools/bake_bot_spots.gd").is_not_null()
	if spots == null:
		return
	assert_str(spots.map_id).is_equal("test_arena")
	assert_int(spots.spots.size()).is_greater(10)
	var sample: Dictionary = spots.spots[0]
	assert_int((sample["coverage_crouch"] as Array).size()).is_equal(BotSpots.DIRECTIONS.size())
	assert_int((sample["coverage_stand"] as Array).size()).is_equal(BotSpots.DIRECTIONS.size())
	assert_bool(sample.has("sniping")).is_true()
	assert_bool(sample.has("approach_points")).is_true()
