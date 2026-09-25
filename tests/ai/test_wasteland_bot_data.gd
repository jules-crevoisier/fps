## test_wasteland_bot_data.gd
## LD-42 (docs/research/11_wasteland_v4_layout.md) — valide
## `WastelandBots.data()` (lanes, hotspots, hp_hold_points, nav_links,
## danger_spans, bot_knowledge) pour Wasteland v4, et le rebake de
## `resources/bot_spots/wasteland.tres`. Même schéma/mêmes familles de tests
## que LD-24/BOT-22B (§1-§2 PURS, §3+ VIVANTS sur la navmesh RÉELLE de
## `MapSetup`), recalés sur la géométrie v4 :
##  - lanes renommées `grand_rue`/`interieurs`/`canyon` (docs/research/
##    11_wasteland_v4_layout.md §5, remplace `crete`/`grand_rue`/`ravin`).
##  - zones Hardpoint P1 (Wagon)/P2 (Magasin ouest)/P3 (Gué), remplace
##    A (Chapelle)/B (Grue)/C (Hangar) — `WastelandLayout.data()["hardpoints"]`
##    est déjà dans cet ordre (LD-40).
##  - plus de dépendance à `WastelandMarkers` (positions fortes, entrées de
##    zone) : cette tâche tourne EN PARALLÈLE du renouvellement v4 de
##    `wasteland_markers.gd` (hors de mon périmètre), qui porte encore les
##    coordonnées v3 au moment d'écrire ce fichier — voir l'en-tête de
##    `WastelandBots.gd` pour le détail. Les positions fortes et les entrées
##    de zone Hardpoint sont donc vérifiées contre les fonctions LOCALES de
##    `WastelandBots` (`_pp_positions()`, `_hp_zone_entries()`), qui sont
##    elles-mêmes dérivées des pièces RÉELLES et FIXES de `WastelandLayout
##    .data()` (`wasteland.gd`, livré v4 par LD-40, immuable pour cette tâche).
extends GdUnitTestSuite

const _OFFSET := Vector3(19200, 0, 0)
const MAX_SYNC_FRAMES := 20

var _next_offset_index := 0


func _setup() -> MapSetup:
	var offset := _OFFSET + Vector3(float(_next_offset_index) * 600.0, 0.0, 0.0)
	_next_offset_index += 1
	var setup := MapSetup.new()
	setup.map_id = "wasteland"
	setup.position = offset
	add_child(setup)
	return setup


func _teardown(setup: Node) -> void:
	remove_child(setup)
	setup.free()
	await get_tree().physics_frame


func _wait_path(map_rid: RID, from: Vector3, to: Vector3) -> PackedVector3Array:
	var path: PackedVector3Array = []
	for i in MAX_SYNC_FRAMES:
		path = NavigationServer3D.map_get_path(map_rid, from, to, true)
		if path.size() >= 2:
			return path
		await get_tree().physics_frame
	return path


# ======================================================================
#  §1 — forme des données (pures, aucun moteur).
# ======================================================================
const LANE_MIN_POINTS := 8
const LANE_MAX_POINTS := 12
const EXPECTED_HOTSPOTS := 12
const HOTSPOTS_MIN_PER_LANE := 3
const EXPECTED_HP_HOLD_POINTS_PER_ZONE := 5
const EXPECTED_DANGER_SPANS_MAX := 6
const EXPECTED_NAV_LINKS := 6
const VALID_LANES := ["grand_rue", "interieurs", "canyon"]
const VALID_STANCES := ["crouch", "stand"]

func test_lanes_shape_and_point_count() -> void:
	var lanes := WastelandBots._lanes()
	assert_int(lanes.size()).is_equal(3)
	for key in VALID_LANES:
		assert_bool(lanes.has(key)).append_failure_message("lane \"%s\" manquante" % key).is_true()
		var pts: Array = lanes[key]
		assert_int(pts.size()).append_failure_message("lane \"%s\" : %d points (attendu %d-%d)" % [key, pts.size(), LANE_MIN_POINTS, LANE_MAX_POINTS]).is_between(LANE_MIN_POINTS, LANE_MAX_POINTS)
		for p in pts:
			assert_bool(p is Vector3).append_failure_message("lane \"%s\" : point non-Vector3" % key).is_true()


func test_lanes_connect_both_spawns() -> void:
	var data := WastelandLayout.data()
	var blue: Vector3 = ((data["spawns"][0][0] as Dictionary)["pos"] as Vector3)
	var red: Vector3 = ((data["spawns"][1][0] as Dictionary)["pos"] as Vector3)
	var lanes := WastelandBots._lanes()
	for key in VALID_LANES:
		var pts: Array = lanes[key]
		var first: Vector3 = pts[0]
		var last: Vector3 = pts[pts.size() - 1]
		assert_float(first.distance_to(blue)).append_failure_message("lane \"%s\" : premier point %s loin du spawn bleu %s" % [key, first, blue]).is_less_equal(2.0)
		assert_float(last.distance_to(red)).append_failure_message("lane \"%s\" : dernier point %s loin du spawn rouge %s" % [key, last, red]).is_less_equal(2.0)


func test_hotspots_shape_and_count() -> void:
	var hotspots := WastelandBots._hotspots()
	assert_int(hotspots.size()).append_failure_message("%d hotspots (attendu %d)" % [hotspots.size(), EXPECTED_HOTSPOTS]).is_equal(EXPECTED_HOTSPOTS)
	var per_lane: Dictionary = {"grand_rue": 0, "interieurs": 0, "canyon": 0}
	for entry in hotspots:
		var h: Dictionary = entry
		assert_bool(h.get("pos") is Vector3).is_true()
		var lane := String(h.get("lane", ""))
		assert_bool(lane in VALID_LANES).append_failure_message("lane inconnue \"%s\"" % lane).is_true()
		per_lane[lane] = int(per_lane[lane]) + 1
		var weight := float(h.get("weight", -1.0))
		assert_float(weight).append_failure_message("poids %s hors [0,1]" % weight).is_between(0.0, 1.0)
		assert_bool(String(h.get("callout", "")).length() > 0).append_failure_message("callout vide").is_true()
	for key in VALID_LANES:
		assert_int(int(per_lane[key])).append_failure_message("lane \"%s\" : %d hotspots (attendu >= %d)" % [key, per_lane[key], HOTSPOTS_MIN_PER_LANE]).is_greater_equal(HOTSPOTS_MIN_PER_LANE)


## PP2/PP3/PP4 (`WastelandBots._pp_positions()`) DOIVENT être repris tels
## quels dans les hotspots : jamais redéfinis à une autre coordonnée.
func test_hotspots_reuse_pp_positions_unchanged() -> void:
	var pp := WastelandBots._pp_positions()
	var hotspot_positions: Array = []
	for entry in WastelandBots._hotspots():
		hotspot_positions.append((entry as Dictionary)["pos"])
	for key in ["PP2", "PP3", "PP4"]:
		assert_bool(hotspot_positions.has(pp[key])).append_failure_message("%s (%s) absent des hotspots" % [key, pp[key]]).is_true()


func test_nav_links_shape_and_count() -> void:
	var links := WastelandBots._nav_links()
	assert_int(links.size()).append_failure_message("%d nav_links (attendu %d)" % [links.size(), EXPECTED_NAV_LINKS]).is_equal(EXPECTED_NAV_LINKS)
	for entry in links:
		var l: Dictionary = entry
		assert_bool(l.get("from") is Vector3).is_true()
		assert_bool(l.get("to") is Vector3).is_true()
		assert_bool(l.get("bidirectional") is bool).is_true()
		assert_float((l["from"] as Vector3).distance_to(l["to"] as Vector3)).append_failure_message("nav_link dégénéré (from == to)").is_greater(0.5)


func test_danger_spans_shape_and_count() -> void:
	var spans := WastelandBots._danger_spans()
	assert_int(spans.size()).append_failure_message("%d danger_spans (attendu <= %d)" % [spans.size(), EXPECTED_DANGER_SPANS_MAX]).is_less_equal(EXPECTED_DANGER_SPANS_MAX)
	for entry in spans:
		var s: Dictionary = entry
		assert_bool(s.get("a") is Vector3).is_true()
		assert_bool(s.get("b") is Vector3).is_true()
		assert_bool(String(s.get("reason", "")).length() > 0).is_true()
		assert_float((s["a"] as Vector3).distance_to(s["b"] as Vector3)).append_failure_message("tronçon dégénéré (a == b)").is_greater(2.0)


func test_data_merges_all_five_keys() -> void:
	var data := WastelandBots.data()
	for key in ["lanes", "hotspots", "hp_hold_points", "nav_links", "danger_spans"]:
		assert_bool(data.has(key)).append_failure_message("clé \"%s\" absente de data()" % key).is_true()


# ======================================================================
#  §2 — hp_hold_points (pures : conteneur de zone, distance à un couvert
#  réel, couverture des entrées). `ZONE_RADIUS`/`ZONE_Y_RANGE` : rayon XZ
#  généreux depuis le centre `WastelandLayout.data()["hardpoints"]` — déjà
#  dans l'ordre P1 (Wagon, index 0) / P2 (Magasin ouest, index 1) / P3 (Gué,
#  index 2), LD-40 — plus large que les emprises réelles (`hardpoint_sizes`)
#  parce que les couverts réels débordent légèrement de ces boîtes.
# ======================================================================
const ZONE_RADIUS := {"P1": 8.0, "P2": 7.0, "P3": 5.0}
const ZONE_Y_RANGE := Vector2(-2.5, 4.0)

## `HOLD_POINT_COVER_MAX` par zone : P1 (Wagon)/P2 (Magasin ouest) ont des
## murs réels à <= 2 m de chaque point de tenue. P3 (le Gué, bord du canyon,
## §12.4 « pas au fond ») est une zone délibérément découverte par
## construction (doc §10, risque connu « HP P3 en fosse » : la pièce qui
## bloque la vue la plus proche est le chicane de rochers/le quai de
## l'arrière-cour, à plusieurs mètres) : la marge y est donc plus large.
const HOLD_POINT_COVER_MAX := {"P1": 2.0, "P2": 2.0, "P3": 9.0}

static func _zone_centers() -> Dictionary:
	var hp: Array = WastelandLayout.data()["hardpoints"]
	return {"P1": hp[0], "P2": hp[1], "P3": hp[2]}


func test_hp_hold_points_count_per_zone() -> void:
	var points := WastelandBots._hp_hold_points()
	var per_zone: Dictionary = {"P1": 0, "P2": 0, "P3": 0}
	for entry in points:
		var p: Dictionary = entry
		var zone := String(p.get("zone", ""))
		assert_bool(zone in ["P1", "P2", "P3"]).append_failure_message("zone inconnue \"%s\"" % zone).is_true()
		per_zone[zone] = int(per_zone[zone]) + 1
		assert_bool(p.get("pos") is Vector3).is_true()
		var facing: Vector3 = p.get("facing", Vector3.ZERO)
		assert_float(facing.length()).append_failure_message("facing %s non unitaire (zone %s)" % [facing, zone]).is_between(0.9, 1.1)
		assert_bool(String(p.get("stance", "")) in VALID_STANCES).append_failure_message("stance inconnue (zone %s)" % zone).is_true()
	for zone in ["P1", "P2", "P3"]:
		assert_int(int(per_zone[zone])).append_failure_message("zone %s : %d points de tenue (attendu %d)" % [zone, per_zone[zone], EXPECTED_HP_HOLD_POINTS_PER_ZONE]).is_equal(EXPECTED_HP_HOLD_POINTS_PER_ZONE)


func test_hp_hold_points_are_within_their_zone() -> void:
	var centers := _zone_centers()
	for entry in WastelandBots._hp_hold_points():
		var p: Dictionary = entry
		var zone := String(p["zone"])
		var pos: Vector3 = p["pos"]
		var center: Vector3 = centers[zone]
		var flat := Vector2(pos.x - center.x, pos.z - center.z).length()
		var radius: float = ZONE_RADIUS[zone]
		assert_float(flat).append_failure_message("zone %s : point %s à %.2f m du centre %s (rayon %.1f)" % [zone, pos, flat, center, radius]).is_less_equal(radius)
		assert_float(pos.y).append_failure_message("zone %s : point %s hors bande Y %s" % [zone, pos, ZONE_Y_RANGE]).is_between(ZONE_Y_RANGE.x, ZONE_Y_RANGE.y)


## Distance (XZ) d'un point à un rectangle (clamp + norme) — pure, aucun
## moteur. `rmin`/`rmax` : voir `Kit.piece_footprint`.
static func _dist_point_to_rect2(p: Vector2, rmin: Vector2, rmax: Vector2) -> float:
	var cx := clampf(p.x, rmin.x, rmax.x)
	var cz := clampf(p.y, rmin.y, rmax.y)
	return Vector2(p.x - cx, p.y - cz).length()


func test_hp_hold_points_are_within_cover_range_of_real_cover() -> void:
	var pieces: Array = WastelandLayout.data()["pieces"]
	var blocking: Array = []
	for piece in pieces:
		if Kit.piece_blocks_sight(piece):
			blocking.append(piece)
	for entry in WastelandBots._hp_hold_points():
		var p: Dictionary = entry
		var pos: Vector3 = p["pos"]
		var p2 := Vector2(pos.x, pos.z)
		var best := INF
		for piece in blocking:
			var fp := Kit.piece_footprint(piece)
			var d := _dist_point_to_rect2(p2, fp["min"], fp["max"])
			if d < best:
				best = d
		var zone := String(p["zone"])
		var cover_max: float = HOLD_POINT_COVER_MAX[zone]
		assert_float(best).append_failure_message("zone %s : point %s à %.2f m du couvert le plus proche (> %.1f m)" % [zone, pos, best, cover_max]).is_less_equal(cover_max)


func test_hp_hold_points_cover_every_entry_of_their_zone() -> void:
	var entries: Dictionary = WastelandBots._hp_zone_entries()
	var points := WastelandBots._hp_hold_points()
	for zone in ["P1", "P2", "P3"]:
		var zone_entries: Array = entries[zone]
		var covered: Dictionary = {}
		for entry in points:
			var p: Dictionary = entry
			if String(p["zone"]) != zone:
				continue
			for idx in (p["covers"] as Array):
				assert_int(int(idx)).append_failure_message("zone %s : indice covers %s hors bornes (0..%d)" % [zone, idx, zone_entries.size() - 1]).is_between(0, zone_entries.size() - 1)
				covered[int(idx)] = true
		for i in zone_entries.size():
			assert_bool(covered.has(i)).append_failure_message("zone %s : entrée #%d (%s) non couverte par un hp_hold_point" % [zone, i, zone_entries[i]]).is_true()


# ======================================================================
#  §3 — lanes/hotspots/danger_spans : sur le navmesh RÉEL (bake `MapSetup`).
# ======================================================================
const NAV_FLAT_TOLERANCE := 1.5
const NAV_VERT_TOLERANCE := 2.0

func _assert_on_navmesh(label: String, map_rid: RID, world_pos: Vector3) -> void:
	var snapped := NavigationServer3D.map_get_closest_point(map_rid, world_pos)
	var flat := Vector2(snapped.x - world_pos.x, snapped.z - world_pos.z).length()
	var vert := absf(snapped.y - world_pos.y)
	assert_float(flat).append_failure_message("%s : décalage XZ %.2f m vers le navmesh (%s -> %s)" % [label, flat, world_pos, snapped]).is_less_equal(NAV_FLAT_TOLERANCE)
	assert_float(vert).append_failure_message("%s : décalage Y %.2f m vers le navmesh (%s -> %s)" % [label, vert, world_pos, snapped]).is_less_equal(NAV_VERT_TOLERANCE)


func test_lane_points_are_on_the_navmesh() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var map_rid := setup.nav_region.get_navigation_map()
	var anchor: Vector3 = ((WastelandLayout.data()["spawns"][0][0] as Dictionary)["pos"] as Vector3) + setup.position
	await _wait_path(map_rid, anchor, anchor + Vector3(0.5, 0, 0))
	var lanes := WastelandBots._lanes()
	for key in VALID_LANES:
		var pts: Array = lanes[key]
		for i in pts.size():
			var pos: Vector3 = pts[i]
			await _assert_on_navmesh("lane \"%s\" point #%d (%s)" % [key, i, pos], map_rid, pos + setup.position)
	await _teardown(setup)


func test_hotspots_are_on_the_navmesh() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var map_rid := setup.nav_region.get_navigation_map()
	var anchor: Vector3 = ((WastelandLayout.data()["spawns"][0][0] as Dictionary)["pos"] as Vector3) + setup.position
	await _wait_path(map_rid, anchor, anchor + Vector3(0.5, 0, 0))
	for entry in WastelandBots._hotspots():
		var h: Dictionary = entry
		var pos: Vector3 = h["pos"]
		await _assert_on_navmesh("hotspot \"%s\" (%s)" % [h["callout"], pos], map_rid, pos + setup.position)
	await _teardown(setup)


const HOTSPOT_TEAM_SPAWN_RADIUS := 10.0
const HOTSPOT_TDM_SPAWN_SANITY := 3.0

## Aucun hotspot à <= 10 m d'un spawn d'équipe (8 spawns, x=∓41) ; marge de
## bon sens (> 3 m) envers les 24 `tdm_spawns` neutres.
func test_hotspots_are_not_within_10m_of_a_team_spawn() -> void:
	var data := WastelandLayout.data()
	var team_spawns: Array = []
	for team in (data["spawns"] as Dictionary).values():
		for entry in (team as Array):
			team_spawns.append((entry as Dictionary)["pos"])
	var tdm_spawns: Array = []
	for entry in (data["tdm_spawns"] as Array):
		tdm_spawns.append((entry as Dictionary)["pos"])

	for entry in WastelandBots._hotspots():
		var h: Dictionary = entry
		var pos: Vector3 = h["pos"]
		for sp in team_spawns:
			var d: float = pos.distance_to(sp as Vector3)
			assert_float(d).append_failure_message("hotspot \"%s\" (%s) à %.2f m du spawn d'équipe %s (< %.0f m)" % [h["callout"], pos, d, sp, HOTSPOT_TEAM_SPAWN_RADIUS]).is_greater(HOTSPOT_TEAM_SPAWN_RADIUS)
		for sp in tdm_spawns:
			var d2: float = pos.distance_to(sp as Vector3)
			assert_float(d2).append_failure_message("hotspot \"%s\" (%s) à %.2f m du tdm_spawn neutre %s (< %.0f m)" % [h["callout"], pos, d2, sp, HOTSPOT_TDM_SPAWN_SANITY]).is_greater(HOTSPOT_TDM_SPAWN_SANITY)


func test_danger_span_endpoints_are_on_the_navmesh() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var map_rid := setup.nav_region.get_navigation_map()
	var anchor: Vector3 = ((WastelandLayout.data()["spawns"][0][0] as Dictionary)["pos"] as Vector3) + setup.position
	await _wait_path(map_rid, anchor, anchor + Vector3(0.5, 0, 0))
	for entry in WastelandBots._danger_spans():
		var s: Dictionary = entry
		await _assert_on_navmesh("danger_span.a (%s)" % (s["a"] as Vector3), map_rid, (s["a"] as Vector3) + setup.position)
		await _assert_on_navmesh("danger_span.b (%s)" % (s["b"] as Vector3), map_rid, (s["b"] as Vector3) + setup.position)
	await _teardown(setup)


# ======================================================================
#  §4 — nav_links : chaque lien franchi par un agent DE NAVIGATION simulé
#  (`NavigationAgent3D`) — un Node3D "bot" avancé pas à pas vers le point
#  d'arrivée du lien, sans avoidance (test solo). `_build_nav_links`
#  (MapSetup.gd, déjà câblé) pose le `NavigationLink3D` correspondant dès que
#  `WastelandBots.data()` est fusionnée par `_assemble_wasteland`.
# ======================================================================
const BOT_SPEED := 8.2  # sprint_speed par défaut.
const BOT_REACH_TOLERANCE := 1.5
const BOT_MAX_SECONDS := 8.0

func _simulate_bot_crosses(setup: MapSetup, from_local: Vector3, to_local: Vector3) -> Vector3:
	var from_pos := from_local + setup.position
	var to_pos := to_local + setup.position
	var map_rid := setup.nav_region.get_navigation_map()
	await _wait_path(map_rid, from_pos, to_pos)

	var bot := Node3D.new()
	bot.name = "SimulatedBot"
	bot.position = from_pos
	add_child(bot)
	var agent := NavigationAgent3D.new()
	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 0.5
	agent.radius = 0.5
	bot.add_child(agent)
	await get_tree().physics_frame
	agent.target_position = to_pos

	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var max_steps := int(BOT_MAX_SECONDS / delta)
	for _i in max_steps:
		if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
			await get_tree().physics_frame
			continue
		if agent.is_navigation_finished():
			break
		var next_pos := agent.get_next_path_position()
		var dir := bot.global_position.direction_to(next_pos)
		bot.global_position += dir * BOT_SPEED * delta
		await get_tree().physics_frame

	var reached := bot.global_position
	remove_child(bot)
	bot.free()
	return reached


func test_each_nav_link_is_crossed_by_a_simulated_bot() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	for entry in WastelandBots._nav_links():
		var l: Dictionary = entry
		var reached := await _simulate_bot_crosses(setup, l["from"] as Vector3, l["to"] as Vector3)
		var target := (l["to"] as Vector3) + setup.position
		assert_float(reached.distance_to(target)).append_failure_message(
			"nav_link %s -> %s : bot simulé arrivé à %s (cible %s)" % [l["from"], l["to"], reached, target]
		).is_less_equal(BOT_REACH_TOLERANCE)
	await _teardown(setup)


# ======================================================================
#  §5 — rebake BotSpots : bake <= 30 s, >= 95 % des points navigables ont un
#  spot couvert à <= 10 m de CHEMIN.
# ======================================================================
const BOT_SPOTS_COVERAGE_MIN := 0.95
const BOT_SPOTS_COVER_PATH_MAX := 10.0

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


func test_wasteland_bot_spots_bake_within_budget_and_coverage() -> void:
	var setup := _setup()
	for i in 15:
		await get_tree().physics_frame

	var space := setup.get_world_3d().direct_space_state
	var start_ms := Time.get_ticks_msec()
	var spots := BotSpots.bake("wasteland", setup.nav_region, space)
	var elapsed_ms := Time.get_ticks_msec() - start_ms

	assert_int(spots.spots.size()).append_failure_message("wasteland : échantillonnage BotSpots vide").is_greater(20)
	assert_int(elapsed_ms).append_failure_message("bake=%dms, budget=%dms" % [elapsed_ms, BotSpots.BAKE_BUDGET_MS]).is_less(BotSpots.BAKE_BUDGET_MS)

	var map_rid := setup.nav_region.get_navigation_map()
	var covered_count := 0
	for s in spots.spots:
		if BotSpots.is_covered(s) or _has_covered_spot_within_path(spots.spots, s, map_rid, BOT_SPOTS_COVER_PATH_MAX):
			covered_count += 1
	var ratio := float(covered_count) / float(spots.spots.size())
	assert_float(ratio).append_failure_message(
		"%d/%d points couverts à <= %.0f m (%.1f%%, attendu >= %.0f%%)" % [covered_count, spots.spots.size(), BOT_SPOTS_COVER_PATH_MAX, ratio * 100.0, BOT_SPOTS_COVERAGE_MIN * 100.0]
	).is_greater_equal(BOT_SPOTS_COVERAGE_MIN)
	await _teardown(setup)


func test_shipped_wasteland_bot_spots_resource_is_valid() -> void:
	var spots := BotSpots.load_for_map("wasteland")
	assert_that(spots).append_failure_message(
		"resources/bot_spots/wasteland.tres manquant — lancer tools/bake_bot_spots.gd -- --map=wasteland"
	).is_not_null()
	if spots == null:
		return
	assert_str(spots.map_id).is_equal("wasteland")
	assert_int(spots.spots.size()).is_greater(20)
	var sample: Dictionary = spots.spots[0]
	assert_int((sample["coverage_crouch"] as Array).size()).is_equal(BotSpots.DIRECTIONS.size())
	assert_int((sample["coverage_stand"] as Array).size()).is_equal(BotSpots.DIRECTIONS.size())


## Acceptance LD-42 (« Même schéma que LD-24/BOT-22B... >= 250 spots ») —
## mêmes seuils numériques que BOT-22, appliqués à la RESSOURCE EXPÉDIÉE
## (`resources/bot_spots/wasteland.tres`) plutôt qu'à un bake frais.
const BOT22_MIN_SPOTS := 250
const BOT22_MIN_GROUND_RATIO := 0.6
const BOT22_GROUND_Y_MAX := 1.0

func test_shipped_wasteland_bot_spots_resource_meets_bot22_thresholds() -> void:
	var spots := BotSpots.load_for_map("wasteland")
	assert_that(spots).append_failure_message(
		"resources/bot_spots/wasteland.tres manquant — lancer tools/bake_bot_spots.gd -- --map=wasteland"
	).is_not_null()
	if spots == null:
		return
	assert_int(spots.spots.size()).append_failure_message(
		"%d spots (attendu >= %d)" % [spots.spots.size(), BOT22_MIN_SPOTS]
	).is_greater_equal(BOT22_MIN_SPOTS)
	var ground_count := 0
	for s in spots.spots:
		if (s["position"] as Vector3).y < BOT22_GROUND_Y_MAX:
			ground_count += 1
	var ratio := float(ground_count) / float(spots.spots.size())
	assert_float(ratio).append_failure_message(
		"%d/%d au sol (%.1f%%, attendu >= %.0f%%)" % [ground_count, spots.spots.size(), ratio * 100.0, BOT22_MIN_GROUND_RATIO * 100.0]
	).is_greater_equal(BOT22_MIN_GROUND_RATIO)


# ======================================================================
#  §6 — bot_knowledge : clé consommée par `BotMapKnowledge.gd` (schéma
#  documenté en tête de ce fichier-là). §6.1 forme pure ; §6.2 vivant
#  (navmesh RÉELLE de `MapSetup`) — chaque point (couloirs/angles/perchoirs/
#  couvertures/tenues Hardpoint) à < 0,5 m de la navmesh ET atteignable par
#  un CHEMIN réel depuis les deux spawns d'équipe.
# ======================================================================
const BK_ZONES_MIN := 14
const BK_ANGLES_MIN := 20
const BK_PERCHES_MIN := 4
const BK_COVERS_MIN := 10
const BK_HP_ZONES := ["P1", "P2", "P3"]
const BK_HOLD_MIN_PER_ZONE := 2
const BK_WATCH_MIN_PER_ZONE := 2

func test_data_includes_bot_knowledge_key() -> void:
	var data := WastelandBots.data()
	assert_bool(data.has("bot_knowledge")).append_failure_message("clé \"bot_knowledge\" absente de data()").is_true()


func test_bot_knowledge_zones_shape_and_count() -> void:
	var zones := WastelandBots._bk_zones()
	assert_int(zones.size()).append_failure_message("%d zones (attendu >= %d)" % [zones.size(), BK_ZONES_MIN]).is_greater_equal(BK_ZONES_MIN)
	var names: Dictionary = {}
	for entry in zones:
		var z: Dictionary = entry
		var nm := String(z.get("name", ""))
		assert_bool(nm.length() > 0).is_true()
		assert_bool(names.has(nm)).append_failure_message("nom de zone dupliqué \"%s\"" % nm).is_false()
		names[nm] = true
		var zmin: Vector3 = z["min"]
		var zmax: Vector3 = z["max"]
		assert_bool(zmin.x < zmax.x and zmin.y < zmax.y and zmin.z < zmax.z).append_failure_message(
			"zone \"%s\" : min %s >= max %s" % [nm, zmin, zmax]
		).is_true()


func test_bot_knowledge_corridors_shape_and_count() -> void:
	var corridors := WastelandBots._bk_corridors()
	assert_int(corridors.size()).is_equal(3)
	for key in ["N", "C", "S"]:
		assert_bool(corridors.has(key)).append_failure_message("couloir \"%s\" manquant" % key).is_true()
		var pts: Array = corridors[key]
		assert_int(pts.size()).append_failure_message("couloir \"%s\" : %d points" % [key, pts.size()]).is_greater_equal(8)
		for p in pts:
			assert_bool(p is Vector3).is_true()


func test_bot_knowledge_angles_shape_and_count() -> void:
	var angles := WastelandBots._bk_angles()
	assert_int(angles.size()).append_failure_message("%d angles (attendu >= %d)" % [angles.size(), BK_ANGLES_MIN]).is_greater_equal(BK_ANGLES_MIN)
	for entry in angles:
		var a: Dictionary = entry
		assert_bool(a.get("pos") is Vector3).is_true()
		var dir: Vector3 = a.get("dir", Vector3.ZERO)
		var flat := Vector2(dir.x, dir.z).length()
		assert_float(flat).append_failure_message("angle %s : direction %s sans composante XZ" % [a["pos"], dir]).is_greater(0.1)


func test_bot_knowledge_perches_shape_and_count() -> void:
	var perches := WastelandBots._bk_perches()
	assert_int(perches.size()).append_failure_message("%d perchoirs (attendu >= %d)" % [perches.size(), BK_PERCHES_MIN]).is_greater_equal(BK_PERCHES_MIN)
	var names: Dictionary = {}
	for entry in perches:
		var p: Dictionary = entry
		var nm := String(p.get("name", ""))
		assert_bool(nm.length() > 0).is_true()
		assert_bool(names.has(nm)).append_failure_message("nom de perchoir dupliqué \"%s\"" % nm).is_false()
		names[nm] = true
		assert_bool(p.get("pos") is Vector3).is_true()
		assert_bool(String(p.get("watch", "")).length() > 0).append_failure_message("perchoir \"%s\" : watch vide" % nm).is_true()


func test_bot_knowledge_covers_shape_and_count() -> void:
	var covers := WastelandBots._bk_covers()
	assert_int(covers.size()).append_failure_message("%d couvertures (attendu >= %d)" % [covers.size(), BK_COVERS_MIN]).is_greater_equal(BK_COVERS_MIN)
	for entry in covers:
		var c: Dictionary = entry
		assert_bool(c.get("pos") is Vector3).is_true()
		var dir: Vector3 = c.get("dir", Vector3.ZERO)
		assert_float(dir.length()).append_failure_message("couverture %s : direction %s non unitaire" % [c["pos"], dir]).is_between(0.9, 1.1)
		assert_float(float(c.get("height", -1.0))).append_failure_message("couverture %s : hauteur invalide" % [c["pos"]]).is_greater(0.0)


func test_bot_knowledge_hp_holds_shape_and_count() -> void:
	var zones := WastelandBots._bk_hp_holds()
	assert_int(zones.size()).is_equal(BK_HP_ZONES.size())
	var seen: Dictionary = {}
	for entry in zones:
		var z: Dictionary = entry
		var nm := String(z.get("zone", ""))
		assert_bool(nm in BK_HP_ZONES).append_failure_message("zone Hardpoint inconnue \"%s\"" % nm).is_true()
		seen[nm] = true
		var hold: Array = z.get("hold", [])
		var watch: Array = z.get("watch", [])
		assert_int(hold.size()).append_failure_message("zone %s : %d position(s) hold" % [nm, hold.size()]).is_greater_equal(BK_HOLD_MIN_PER_ZONE)
		assert_int(watch.size()).append_failure_message("zone %s : %d position(s) watch" % [nm, watch.size()]).is_greater_equal(BK_WATCH_MIN_PER_ZONE)
		for p in hold:
			assert_bool(p is Vector3).is_true()
		for p in watch:
			assert_bool(p is Vector3).is_true()
	for nm in BK_HP_ZONES:
		assert_bool(seen.has(nm)).append_failure_message("zone Hardpoint \"%s\" absente" % nm).is_true()


# ----------------------------------------------------------------------
#  §6.2 — navmesh RÉELLE : < 0,5 m + atteignable depuis les deux spawns.
# ----------------------------------------------------------------------
const BK_NAV_TOLERANCE := 0.5

## Vérifie un point (déjà décalé de `setup.position`) : décalage vers la
## navmesh <= `BK_NAV_TOLERANCE`, ET un chemin RÉEL (`map_get_path`, taille
## >= 2) depuis CHACUN des deux spawns d'équipe (déjà décalés eux aussi).
func _assert_bot_knowledge_point(label: String, map_rid: RID, world_pos: Vector3, spawn0: Vector3, spawn1: Vector3) -> void:
	var snapped := NavigationServer3D.map_get_closest_point(map_rid, world_pos)
	var dist := snapped.distance_to(world_pos)
	assert_float(dist).append_failure_message(
		"%s : décalage %.2f m vers la navmesh (%s -> %s, tolérance %.1f m)" % [label, dist, world_pos, snapped, BK_NAV_TOLERANCE]
	).is_less_equal(BK_NAV_TOLERANCE)
	for entry in [["spawn bleu", spawn0], ["spawn rouge", spawn1]]:
		var spawn_name: String = entry[0]
		var spawn_pos: Vector3 = entry[1]
		var path := NavigationServer3D.map_get_path(map_rid, spawn_pos, world_pos, true)
		assert_int(path.size()).append_failure_message(
			"%s : aucun chemin réel depuis le %s (%s)" % [label, spawn_name, spawn_pos]
		).is_greater_equal(2)


## Prépare la navmesh RÉELLE d'un `MapSetup` Wasteland fraîchement chargé —
## voir la version LD-24 originale pour le détail de la synchro (plusieurs
## instances décalées de 600 m fusionnent leurs polygones dans LA MÊME carte
## de navigation partagée : on attend que `map_get_closest_point(spawn0)`
## retombe près de `spawn0` avant de considérer que CETTE région a rejoint
## la carte).
const BK_SYNC_MAX_FRAMES := 120
const BK_SYNC_TOLERANCE := 3.0

func _bk_setup() -> Dictionary:
	var setup := _setup()
	var map_rid := setup.nav_region.get_navigation_map()
	var data := WastelandLayout.data()
	var spawn0: Vector3 = ((data["spawns"][0][0] as Dictionary)["pos"] as Vector3) + setup.position
	var spawn1: Vector3 = ((data["spawns"][1][0] as Dictionary)["pos"] as Vector3) + setup.position
	for _i in BK_SYNC_MAX_FRAMES:
		var snapped := NavigationServer3D.map_get_closest_point(map_rid, spawn0)
		if snapped.distance_to(spawn0) <= BK_SYNC_TOLERANCE:
			break
		await get_tree().physics_frame
	return {"setup": setup, "map_rid": map_rid, "spawn0": spawn0, "spawn1": spawn1}


func test_bot_knowledge_corridor_points_are_on_navmesh_and_reachable_from_both_spawns() -> void:
	var ctx := await _bk_setup()
	var setup: MapSetup = ctx["setup"]
	var corridors := WastelandBots._bk_corridors()
	for key in ["N", "C", "S"]:
		var pts: Array = corridors[key]
		for i in pts.size():
			var pos: Vector3 = (pts[i] as Vector3) + setup.position
			await _assert_bot_knowledge_point("couloir \"%s\" point #%d" % [key, i], ctx["map_rid"], pos, ctx["spawn0"], ctx["spawn1"])
	await _teardown(setup)


func test_bot_knowledge_angles_are_on_navmesh_and_reachable_from_both_spawns() -> void:
	var ctx := await _bk_setup()
	var setup: MapSetup = ctx["setup"]
	for entry in WastelandBots._bk_angles():
		var a: Dictionary = entry
		var pos := (a["pos"] as Vector3) + setup.position
		await _assert_bot_knowledge_point("angle %s" % (a["pos"] as Vector3), ctx["map_rid"], pos, ctx["spawn0"], ctx["spawn1"])
	await _teardown(setup)


func test_bot_knowledge_perches_are_on_navmesh_and_reachable_from_both_spawns() -> void:
	var ctx := await _bk_setup()
	var setup: MapSetup = ctx["setup"]
	for entry in WastelandBots._bk_perches():
		var p: Dictionary = entry
		var pos := (p["pos"] as Vector3) + setup.position
		await _assert_bot_knowledge_point("perchoir \"%s\"" % p["name"], ctx["map_rid"], pos, ctx["spawn0"], ctx["spawn1"])
	await _teardown(setup)


func test_bot_knowledge_covers_are_on_navmesh_and_reachable_from_both_spawns() -> void:
	var ctx := await _bk_setup()
	var setup: MapSetup = ctx["setup"]
	for entry in WastelandBots._bk_covers():
		var c: Dictionary = entry
		var pos := (c["pos"] as Vector3) + setup.position
		await _assert_bot_knowledge_point("couverture %s" % (c["pos"] as Vector3), ctx["map_rid"], pos, ctx["spawn0"], ctx["spawn1"])
	await _teardown(setup)


func test_bot_knowledge_hp_holds_are_on_navmesh_and_reachable_from_both_spawns() -> void:
	var ctx := await _bk_setup()
	var setup: MapSetup = ctx["setup"]
	for entry in WastelandBots._bk_hp_holds():
		var z: Dictionary = entry
		var zone := String(z["zone"])
		for i in (z["hold"] as Array).size():
			var pos: Vector3 = (z["hold"][i] as Vector3) + setup.position
			await _assert_bot_knowledge_point("hp_holds %s hold #%d" % [zone, i], ctx["map_rid"], pos, ctx["spawn0"], ctx["spawn1"])
		for i in (z["watch"] as Array).size():
			var pos2: Vector3 = (z["watch"][i] as Vector3) + setup.position
			await _assert_bot_knowledge_point("hp_holds %s watch #%d" % [zone, i], ctx["map_rid"], pos2, ctx["spawn0"], ctx["spawn1"])
	await _teardown(setup)
