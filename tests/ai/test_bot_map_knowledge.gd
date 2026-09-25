## test_bot_map_knowledge.gd
## BOT-22 (docs/research/08_bots_humanlike.md §3.7 "Connaissance de Wasteland
## (K)") — deux familles de tests :
##  - §1 BotMapKnowledge, PUR (Dictionary/Vector3, aucun moteur) : exercé
##    contre une fixture `_bot_knowledge_fixture()` reprenant des coordonnées
##    RÉELLES du brouillon §3.7 (zones, couloirs, angles, perchoirs,
##    couvertures, tenues Hardpoint) — voir l'en-tête de BotMapKnowledge.gd
##    pour l'écart connu (aucune carte n'expose encore cette clé sous
##    `WastelandLayout.data()["bot_knowledge"]`, LD-24, hors de ma liste de
##    fichiers). Cette fixture n'est PAS une prétention de données de jeu
##    finales : uniquement de quoi exercer chaque branche du lecteur pur.
##  - §2 BotSpots (acceptance BOT-22) : `_sample_navmesh` échantillonne
##    plusieurs niveaux (pile de rayons verticaux, scène physique minimale
##    réelle comme tests/ai/test_bot_spots.gd), et le rebake du niveau
##    "wasteland" atteint les seuils BOT-22 (>= 250 spots, >= 60 % au sol,
##    < 50 % en sniping) sans écrire `resources/bot_spots/wasteland.tres`
##    (ce fichier est hors de ma liste — voir rendu de tâche).
extends GdUnitTestSuite


# ======================================================================
#  §1 — Fixture bot_knowledge (coordonnées du brouillon §3.7).
# ======================================================================
static func _zones() -> Array:
	return [
		{"name": "FuelPlank", "min": Vector3(-24, 2.7, -9), "max": Vector3(-18, 3.7, -6)},
		{"name": "FuelHouse", "min": Vector3(-31, 2.7, -9.5), "max": Vector3(-24, 6.9, -6)},
		{"name": "Garage", "min": Vector3(-22, -0.5, -8.5), "max": Vector3(-16.5, 0.5, -3.5)},
		{"name": "Reservoir", "min": Vector3(-13, -0.5, -6), "max": Vector3(-9, 3.7, -3)},
		{"name": "Chapelle", "min": Vector3(-9.5, -0.5, -4), "max": Vector3(-5.5, 0.5, 4)},
		{"name": "HangarGrue", "min": Vector3(-1, -0.5, -10), "max": Vector3(8, 3.7, -4)},
		{"name": "CraneDeck", "min": Vector3(0, 5.1, -12.5), "max": Vector3(3, 6.1, -10.5)},
		{"name": "Derrick", "min": Vector3(12, 3.7, -22), "max": Vector3(27, 5.1, -16)},
		{"name": "GasOffice", "min": Vector3(21.5, -0.5, -8), "max": Vector3(28, 3.7, -3.5)},
		{"name": "WestBlock", "min": Vector3(15.5, -0.5, -3.5), "max": Vector3(22, 0.5, -0.5)},
		{"name": "Entrepot", "min": Vector3(7.5, -0.5, 1.5), "max": Vector3(19, 0.5, 11)},
		{"name": "SouthBlock", "min": Vector3(22, -0.5, 5.5), "max": Vector3(27, 0.5, 9.5)},
		{"name": "Shack", "min": Vector3(-32, -0.5, 0.5), "max": Vector3(-28, 0.5, 4.5)},
		{"name": "DuneField", "min": Vector3(-26, 2.7, -13.5), "max": Vector3(-13, 3.7, -10.5)},
	]


## Couloirs N/C/S, points OUEST -> EST (équipe 0) — `lane_goals` les inverse
## pour l'équipe 1.
static func _corridors() -> Dictionary:
	return {
		"N": [
			Vector3(-25, 0, -12), Vector3(-17, 3.2, -12), Vector3(-14, 3.2, -12.25),
			Vector3(1, 0, -17), Vector3(15, 0, -7), Vector3(19, 4.5, -19),
		],
		"C": [
			Vector3(-24, 0, 1), Vector3(-17.5, 0, -4.5), Vector3(-11.5, 0, 0),
			Vector3(-7.5, 0, 0), Vector3(8, 0, -2), Vector3(17, 0, -2), Vector3(24, 0, 2),
		],
		"S": [
			Vector3(-30, 0, 2.5), Vector3(-17.5, 0, 4.5), Vector3(-1, 0, 4.5),
			Vector3(4, 0, 9.5), Vector3(13, 0, 7), Vector3(16, 0, 13), Vector3(24, 0, 7.5),
		],
	}


## 23 angles à pré-viser (brouillon §3.7, direction = variante illustrative
## pour cette fixture — l'auteur final des données choisira la direction
## réelle vers la menace la plus probable).
static func _angles() -> Array:
	return [
		{"pos": Vector3(-21, 3.2, -7.5), "dir": Vector3(1, 0, 0)},
		{"pos": Vector3(-27, 3.2, -7.5), "dir": Vector3(1, 0, 0)},
		{"pos": Vector3(-17.5, 0, -4.5), "dir": Vector3(0, 0, 1)},
		{"pos": Vector3(-21, 0, -7.5), "dir": Vector3(-1, 0, 0)},
		{"pos": Vector3(-11.5, 3.2, -5), "dir": Vector3(0, 0, 1)},
		{"pos": Vector3(-10.5, 0, -5), "dir": Vector3(0, 0, 1)},
		{"pos": Vector3(-7.5, 0, -3), "dir": Vector3(0, 0, -1)},
		{"pos": Vector3(-7.5, 0, 3), "dir": Vector3(0, 0, 1)},
		{"pos": Vector3(0.75, 3.2, -5.5), "dir": Vector3(0, 0, 1)},
		{"pos": Vector3(3.5, 0, -5.5), "dir": Vector3(0, 0, 1)},
		{"pos": Vector3(7, 0, -9.5), "dir": Vector3(1, 0, 0)},
		{"pos": Vector3(1.5, 5.6, -11.5), "dir": Vector3(0, 0, 1)},
		{"pos": Vector3(15, 4.5, -17), "dir": Vector3(1, 0, 0)},
		{"pos": Vector3(25, 4.5, -19), "dir": Vector3(-1, 0, 0)},
		{"pos": Vector3(26.5, 0, -4.5), "dir": Vector3(0, 0, 1)},
		{"pos": Vector3(23, 0, -7), "dir": Vector3(-1, 0, 0)},
		{"pos": Vector3(24.5, 3.2, -4.5), "dir": Vector3(0, 0, 1)},
		{"pos": Vector3(17, 0, -2), "dir": Vector3(-1, 0, 0)},
		{"pos": Vector3(20.5, 0, -2), "dir": Vector3(1, 0, 0)},
		{"pos": Vector3(9, 0, 7), "dir": Vector3(-1, 0, 0)},
		{"pos": Vector3(17, 0, 7), "dir": Vector3(1, 0, 0)},
		{"pos": Vector3(13, 0, 3), "dir": Vector3(0, 0, -1)},
		{"pos": Vector3(24, 0, 7.5), "dir": Vector3(0, 0, -1)},
	]


static func _perches() -> Array:
	return [
		{"name": "CraneDeck", "pos": Vector3(1.5, 5.6, -11.5), "watch": "rue et centre"},
		{"name": "Derrick", "pos": Vector3(19, 4.5, -21), "watch": "couloir Nord"},
		{"name": "ToitFuelHouse", "pos": Vector3(-30, 6.4, -7.5), "watch": "cour FUEL"},
		{"name": "ToitGasOffice", "pos": Vector3(26.5, 3.2, -7), "watch": "cour GAS"},
		{"name": "HautResStair", "pos": Vector3(-11.5, 3.2, -5), "watch": "centre-ouest"},
	]


static func _covers() -> Array:
	return [
		{"pos": Vector3(-19, 0, 5.25), "dir": Vector3(0, 0, -1), "height": 1.6},
		{"pos": Vector3(-16, 0, 5.25), "dir": Vector3(0, 0, -1), "height": 1.6},
		{"pos": Vector3(-24, 0, -1), "dir": Vector3(0, 0, 1), "height": 3.0},
		{"pos": Vector3(-1, 0, 4.5), "dir": Vector3(0, 0, -1), "height": 1.4},
		{"pos": Vector3(4, 0, 9.5), "dir": Vector3(0, 0, -1), "height": 1.8},
		{"pos": Vector3(2.5, 0, 13), "dir": Vector3(0, 0, -1), "height": 1.6},
		{"pos": Vector3(8, 0, -2), "dir": Vector3(0, 0, 1), "height": 1.8},
		{"pos": Vector3(16, 0, 13), "dir": Vector3(0, 0, -1), "height": 1.8},
		{"pos": Vector3(24, 0, 2), "dir": Vector3(-1, 0, 0), "height": 1.2},
		{"pos": Vector3(22.5, 0, 5), "dir": Vector3(-1, 0, 0), "height": 1.8},
		{"pos": Vector3(27, 0, 1), "dir": Vector3(-1, 0, 0), "height": 3.5},
	]


## 4 zones Hardpoint (HP1..HP4, brouillon §3.7) — `hold` = dans la zone,
## `watch` = surveillance d'une entrée.
static func _hp_holds() -> Array:
	return [
		{
			"zone": "HP1_rue", "hold": [Vector3(-1.5, 0, 7.5), Vector3(2.5, 0, 9)],
			"watch": [Vector3(-7.5, 0, 3.5), Vector3(9, 0, 7), Vector3(0.75, 3.2, -5.5)],
		},
		{
			"zone": "HP2_reservoir", "hold": [Vector3(-13, 0, -2), Vector3(-10.5, 0, 0.5)],
			"watch": [Vector3(-17.5, 0, -4), Vector3(-16, 0, 4.5), Vector3(-11.5, 3.2, -5)],
		},
		{
			"zone": "HP3_hangar", "hold": [Vector3(0.8, 3.2, -12.5), Vector3(2.5, 3.2, -7)],
			"watch": [Vector3(1.5, 5.6, -11.5), Vector3(0.75, 0, 0)],
		},
		{
			"zone": "HP4_entrepot", "hold": [Vector3(10, 0, 4), Vector3(16, 0, 10)],
			"watch": [Vector3(17, 0, -2), Vector3(16, 0, 13), Vector3(22.5, 0, 5)],
		},
	]


static func _fixture() -> Dictionary:
	return {
		"zones": _zones(),
		"corridors": _corridors(),
		"angles": _angles(),
		"perches": _perches(),
		"covers": _covers(),
		"hp_holds": _hp_holds(),
	}


static func _knowledge() -> BotMapKnowledge:
	return BotMapKnowledge.new(_fixture())


# ======================================================================
#  §1.1 — area_of()
# ======================================================================
func test_area_of_finds_the_zone_containing_the_point() -> void:
	var k := _knowledge()
	assert_str(k.area_of(Vector3(-21, 3.2, -7.5))).is_equal("FuelPlank")
	assert_str(k.area_of(Vector3(-17, 3.2, -12))).is_equal("DuneField")
	assert_str(k.area_of(Vector3(13, 0, 3))).is_equal("Entrepot")


func test_area_of_returns_empty_string_outside_every_zone() -> void:
	var k := _knowledge()
	assert_str(k.area_of(Vector3(0, 50, 0))).is_equal("")


# ======================================================================
#  §1.2 — lane_goals(team, lane)
# ======================================================================
func test_lane_goals_keeps_west_to_east_order_for_team_zero() -> void:
	var k := _knowledge()
	var expected: Array = _corridors()["N"]
	assert_array(k.lane_goals(0, "N")).is_equal(expected)


func test_lane_goals_reverses_order_for_team_one() -> void:
	var k := _knowledge()
	var forward: Array = _corridors()["S"]
	var reversed_pts: Array = forward.duplicate()
	reversed_pts.reverse()
	assert_array(k.lane_goals(1, "S")).is_equal(reversed_pts)


func test_lane_goals_does_not_mutate_the_source_data() -> void:
	var k := _knowledge()
	var before: Array = (_corridors()["C"] as Array).duplicate()
	k.lane_goals(1, "C")
	assert_array(k.lane_goals(0, "C")).is_equal(before)


func test_lane_goals_unknown_lane_returns_empty_array() -> void:
	var k := _knowledge()
	assert_array(k.lane_goals(0, "Ouest")).is_empty()


# ======================================================================
#  §1.3 — angles_near(pos, fwd, range, half_angle_deg)
# ======================================================================
func test_angles_near_includes_a_point_ahead_and_in_range() -> void:
	var k := _knowledge()
	var pos := Vector3(-7.5, 0, -8)
	var fwd := Vector3(0, 0, 1)
	var found := k.angles_near(pos, fwd, 25.0, 60.0)
	var positions: Array = []
	for a in found:
		positions.append((a as Dictionary)["pos"])
	assert_bool(positions.has(Vector3(-7.5, 0, -3))).append_failure_message(
		"la porte N de la chapelle est à 5 m pile devant : devrait être retenue").is_true()


func test_angles_near_excludes_a_point_beyond_range() -> void:
	var k := _knowledge()
	# Derrick (25,4.5,-19) est à > 25 m de la porte S de la chapelle.
	var pos := Vector3(-7.5, 0, 3)
	var fwd := Vector3(1, 0, 0)
	var found := k.angles_near(pos, fwd, 25.0, 60.0)
	for a in found:
		assert_vector((a as Dictionary)["pos"]).append_failure_message(
			"un angle à plus de 25 m ne devrait jamais être retenu").is_not_equal(Vector3(25, 4.5, -19))


func test_angles_near_excludes_a_point_behind_the_bot() -> void:
	var k := _knowledge()
	var pos := Vector3(-7.5, 0, 0)
	var fwd := Vector3(0, 0, -1)   # le bot regarde vers le nord.
	var found := k.angles_near(pos, fwd, 25.0, 60.0)
	for a in found:
		assert_vector((a as Dictionary)["pos"]).append_failure_message(
			"la porte S (3,5 m plein SUD, donc plein derrière) ne devrait pas être dans le cône avant").is_not_equal(Vector3(-7.5, 0, 3))


func test_angles_near_uses_default_range_and_half_angle_when_omitted() -> void:
	var k := _knowledge()
	var pos := Vector3(-7.5, 0, -8)
	var fwd := Vector3(0, 0, 1)
	assert_array(k.angles_near(pos, fwd)).is_equal(k.angles_near(pos, fwd, BotMapKnowledge.DEFAULT_ANGLE_RANGE, BotMapKnowledge.DEFAULT_HALF_ANGLE_DEG))


func test_angles_near_returns_empty_when_forward_has_no_flat_component() -> void:
	var k := _knowledge()
	var found := k.angles_near(Vector3(-7.5, 0, -8), Vector3(0, 1, 0), 25.0, 60.0)
	assert_array(found).is_empty()


# ======================================================================
#  §1.4 — hp_holds(index, role)
# ======================================================================
func test_hp_holds_hold_role_has_at_least_two_positions_per_zone() -> void:
	var k := _knowledge()
	for i in 4:
		var pts := k.hp_holds(i, BotMapKnowledge.ROLE_HOLD)
		assert_int(pts.size()).append_failure_message("zone HP #%d : %d position(s) \"hold\" (attendu >= 2)" % [i, pts.size()]).is_greater_equal(2)


func test_hp_holds_watch_role_has_at_least_two_positions_per_zone() -> void:
	var k := _knowledge()
	for i in 4:
		var pts := k.hp_holds(i, BotMapKnowledge.ROLE_WATCH)
		assert_int(pts.size()).append_failure_message("zone HP #%d : %d position(s) \"watch\" (attendu >= 2)" % [i, pts.size()]).is_greater_equal(2)


func test_hp_holds_out_of_bounds_index_returns_empty_array() -> void:
	var k := _knowledge()
	assert_array(k.hp_holds(4, BotMapKnowledge.ROLE_HOLD)).is_empty()
	assert_array(k.hp_holds(-1, BotMapKnowledge.ROLE_HOLD)).is_empty()


func test_hp_holds_unknown_role_returns_empty_array() -> void:
	var k := _knowledge()
	assert_array(k.hp_holds(0, "sprint")).is_empty()


# ======================================================================
#  §2 — BotSpots : pile de rayons verticaux (BOT-22).
#  Scène physique minimale réelle, même discipline que tests/ai/test_bot_spots
#  .gd : StaticBody3D ajoutés à l'arbre, navmesh bakée via BotNavMesh
#  .ensure_baked, synchronisée avant toute requête NavigationServer3D.
# ======================================================================
const _ROOM_OFFSET_BASE := Vector3(84000, 0, 0)
const NAV_SYNC_FRAMES := 15

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := _ROOM_OFFSET_BASE + Vector3(float(_next_offset_index) * 200.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


func _room(offset: Vector3) -> Node3D:
	var root_node := Node3D.new()
	root_node.name = "BotMapKnowledgeTestRoom"
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


func _teardown_room(root_node: Node3D) -> void:
	remove_child(root_node)
	root_node.free()
	await get_tree().physics_frame


## Deux niveaux SUPERPOSÉS à la même colonne XZ (rez-de-chaussée y=0, palier
## élevé y=2.3, comme un bâtiment à étage de Wasteland — FuelHouse rez ->
## toit) reliés par un escalier en 5 marches de 0.46 m (<= agent_max_climb =
## 0.6 m, BotNavMesh.gd) : Recast les fusionne en UNE navmesh connectée avec
## deux niveaux distincts échantillonnables à la même colonne XZ.
func test_sample_navmesh_finds_both_stacked_levels_at_the_same_column() -> void:
	var offset := _offset()
	var root_node := _room(offset)
	_floor(root_node, Vector3(0, 0, 0), 10, 10)          # rez-de-chaussée : x[-5,5] z[-5,5].
	var step_rise := 2.3 / 5.0
	for i in 5:
		var step_y := step_rise * float(i + 1)
		_floor(root_node, Vector3(5.5 + float(i) * 1.0, step_y, 0), 1.0, 4.0)
	# Palier élevé x[10,18] z[-5,5] : démarre PILE où finit la dernière marche
	# (x=10, y=2.3) — jamais avant, sinon son volume recouvre les marches
	# précédentes (dalle solide au-dessus de leur surface praticable, sans
	# dégagement d'agent) et casse la connexité de l'escalier.
	_floor(root_node, Vector3(14, 2.3, 0), 8, 10)
	var setup := await _bake_room(root_node)

	var spots := BotSpots.bake("stacked_levels_test", setup["nav"], setup["space"])
	assert_int(spots.spots.size()).append_failure_message("échantillonnage vide : géométrie invalide").is_greater(4)

	var found_ground := false
	var found_elevated := false
	for s in spots.spots:
		var local: Vector3 = root_node.global_transform.affine_inverse() * (s["position"] as Vector3)
		if absf(local.y) <= 0.5:
			found_ground = true
		if absf(local.y - 2.3) <= 0.5:
			found_elevated = true
	assert_bool(found_ground).append_failure_message("aucun spot au niveau du rez-de-chaussée (y proche de 0)").is_true()
	assert_bool(found_elevated).append_failure_message("aucun spot au niveau du palier élevé (y proche de 2.3) : la pile de sondes verticales ne les trouve pas").is_true()
	await _teardown_room(root_node)


# ======================================================================
#  §2.2 — rebake "wasteland" : seuils numériques BOT-22 (>= 250 spots,
#  >= 60 % au sol, < 50 % en sniping), sans écrire wasteland.tres (hors de
#  ma liste de fichiers — le rendu de tâche signale qui doit le regénérer).
# ======================================================================
const _WASTELAND_OFFSET := Vector3(96000, 0, 0)
const MIN_SPOTS := 250
const MIN_GROUND_RATIO := 0.6
const MAX_SNIPING_RATIO := 0.5
const GROUND_Y_MAX := 1.0

func test_wasteland_rebake_meets_bot22_ground_and_sniping_thresholds() -> void:
	var setup := MapSetup.new()
	setup.map_id = "wasteland"
	setup.position = _WASTELAND_OFFSET
	add_child(setup)
	for i in NAV_SYNC_FRAMES:
		await get_tree().physics_frame

	var space := setup.get_world_3d().direct_space_state
	var start_ms := Time.get_ticks_msec()
	var spots := BotSpots.bake("wasteland", setup.nav_region, space)
	var elapsed_ms := Time.get_ticks_msec() - start_ms

	assert_int(elapsed_ms).append_failure_message("bake=%dms, budget=%dms" % [elapsed_ms, BotSpots.BAKE_BUDGET_MS]).is_less(BotSpots.BAKE_BUDGET_MS)
	assert_int(spots.spots.size()).append_failure_message("%d spots (attendu >= %d)" % [spots.spots.size(), MIN_SPOTS]).is_greater_equal(MIN_SPOTS)

	var ground_count := 0
	var sniping_count := 0
	for s in spots.spots:
		var local_y: float = (s["position"] as Vector3).y - _WASTELAND_OFFSET.y
		if local_y < GROUND_Y_MAX:
			ground_count += 1
		if s["sniping"]:
			sniping_count += 1
	var ground_ratio := float(ground_count) / float(spots.spots.size())
	var sniping_ratio := float(sniping_count) / float(spots.spots.size())
	assert_float(ground_ratio).append_failure_message(
		"%d/%d au sol (%.1f%%, attendu >= %.0f%%)" % [ground_count, spots.spots.size(), ground_ratio * 100.0, MIN_GROUND_RATIO * 100.0]
	).is_greater_equal(MIN_GROUND_RATIO)
	assert_float(sniping_ratio).append_failure_message(
		"%d/%d en sniping (%.1f%%, attendu < %.0f%%)" % [sniping_count, spots.spots.size(), sniping_ratio * 100.0, MAX_SNIPING_RATIO * 100.0]
	).is_less(MAX_SNIPING_RATIO)

	remove_child(setup)
	setup.free()
	await get_tree().physics_frame
