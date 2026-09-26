## test_wasteland_bot_data.gd
## Wasteland v7 — greybox pur (2026-09-26, « fais la carte block que je
## puisse la tester in game »). REMPLACE le contrat v4 (LD-42, encore
## visible dans l'historique : lanes "grand_rue"/"interieurs"/"canyon",
## `_pp_positions`/`_hp_zone_entries` calées sur la géométrie miroir qui
## n'existe plus). `WastelandBots.gd` dérive désormais TOUT depuis
## `WastelandLayout.plan()` (`data/maps/wasteland_plan.json`) — ce fichier
## vérifie le résultat, pas une recopie indépendante des mêmes calculs.
##
## Contrat LOAD-BEARING conservé (`scripts/modes/TDMMode.gd`, hors de mon
## périmètre) : les couloirs sont exposés sous les LETTRES "N"/"C"/"S"
## (Nord/Centre/Sud), voir l'en-tête de `WastelandBots.gd`.
extends GdUnitTestSuite

const VALID_LANES := ["N", "C", "S"]
const LANE_MIN_POINTS := 6


# ======================================================================
#  §1 — forme des données (pures, aucun moteur).
# ======================================================================
func test_corridors_have_letters_n_c_s_and_enough_points() -> void:
	var bk: Dictionary = WastelandBots.data()["bot_knowledge"]
	var corridors: Dictionary = bk["corridors"]
	assert_int(corridors.size()).is_equal(3)
	for key in VALID_LANES:
		assert_bool(corridors.has(key)).append_failure_message("corridor \"%s\" missing" % key).is_true()
		var pts: Array = corridors[key]
		assert_int(pts.size()).append_failure_message("corridor \"%s\": %d points (expected >= %d)" % [key, pts.size(), LANE_MIN_POINTS]).is_greater_equal(LANE_MIN_POINTS)
		for p in pts:
			assert_bool(p is Vector3).append_failure_message("corridor \"%s\": non-Vector3 point" % key).is_true()


func test_corridors_go_west_to_east_matching_team_spawns() -> void:
	var data := WastelandLayout.data()
	var blue: Vector3 = ((data["spawns"][0] as Array)[0] as Dictionary)["pos"]
	var red: Vector3 = ((data["spawns"][1] as Array)[0] as Dictionary)["pos"]
	var corridors: Dictionary = WastelandBots.data()["bot_knowledge"]["corridors"]
	for key in VALID_LANES:
		var pts: Array = corridors[key]
		var first: Vector3 = pts[0]
		var last: Vector3 = pts[pts.size() - 1]
		assert_float(first.x).append_failure_message("corridor \"%s\": first point %s should be west (near blue spawn x=%.1f)" % [key, first, blue.x]).is_less(0.0)
		assert_float(last.x).append_failure_message("corridor \"%s\": last point %s should be east (near red spawn x=%.1f)" % [key, last, red.x]).is_greater(0.0)
		assert_float(Vector2(first.x, first.z).distance_to(Vector2(blue.x, blue.z))).append_failure_message("corridor \"%s\": first point far from blue spawn" % key).is_less_equal(8.0)
		assert_float(Vector2(last.x, last.z).distance_to(Vector2(red.x, red.z))).append_failure_message("corridor \"%s\": last point far from red spawn" % key).is_less_equal(8.0)


func test_nav_links_are_one_way_falls_from_real_parapets() -> void:
	var links: Array = WastelandBots.data()["nav_links"]
	assert_int(links.size()).append_failure_message("expected at least the 2 canyon-parapet falls").is_greater_equal(2)
	for entry in links:
		var l: Dictionary = entry
		var from: Vector3 = l["from"]
		var to: Vector3 = l["to"]
		assert_bool(bool(l.get("bidirectional", true))).append_failure_message("a fall link must be one-way").is_false()
		assert_float(from.y - to.y).append_failure_message("expected a downward fall (canyon, -2 m)").is_greater(0.5)


func test_bot_knowledge_zones_cover_every_building() -> void:
	var plan := WastelandLayout.plan()
	var expected := 0
	for entry in (plan["volumes"] as Array):
		if String((entry as Dictionary).get("kind", "")) == "building":
			expected += 1
	var zones: Array = WastelandBots.data()["bot_knowledge"]["zones"]
	assert_int(zones.size()).is_equal(expected)
	for entry in zones:
		var z: Dictionary = entry
		assert_bool(z.has("name") and z.has("min") and z.has("max")).is_true()
		var zmin: Vector3 = z["min"]
		var zmax: Vector3 = z["max"]
		assert_bool(zmax.x > zmin.x and zmax.y > zmin.y and zmax.z > zmin.z).append_failure_message("zone %s is not a real box" % z["name"]).is_true()


func test_bot_knowledge_angles_come_from_ground_floor_doors() -> void:
	var plan := WastelandLayout.plan()
	var expected := 0
	for entry in (plan["volumes"] as Array):
		var v: Dictionary = entry
		if String(v.get("kind", "")) != "building":
			continue
		for door_entry in (v.get("doors", []) as Array):
			if int((door_entry as Dictionary).get("floor", 0)) == 0:
				expected += 1
	var angles: Array = WastelandBots.data()["bot_knowledge"]["angles"]
	assert_int(angles.size()).is_equal(expected)
	for entry in angles:
		var a: Dictionary = entry
		assert_bool(a["pos"] is Vector3 and a["dir"] is Vector3).is_true()
		assert_float((a["dir"] as Vector3).length()).is_equal_approx(1.0, 0.001)


func test_bot_knowledge_perches_are_the_elevated_strong_positions() -> void:
	var plan := WastelandLayout.plan()
	var expected := 0
	for entry in ((plan["markers"] as Dictionary).get("strong_positions", []) as Array):
		if bool((entry as Dictionary).get("elevated", false)):
			expected += 1
	var perches: Array = WastelandBots.data()["bot_knowledge"]["perches"]
	assert_int(perches.size()).is_equal(expected)
	assert_int(perches.size()).append_failure_message("expected several elevated strong positions (PP1-PP7)").is_greater_equal(5)


func test_bot_knowledge_covers_come_from_real_cover_volumes() -> void:
	var plan := WastelandLayout.plan()
	var expected := 0
	for entry in (plan["volumes"] as Array):
		if String((entry as Dictionary).get("kind", "")) == "cover":
			expected += 1
	var covers: Array = WastelandBots.data()["bot_knowledge"]["covers"]
	assert_int(covers.size()).is_equal(expected)


func test_hp_holds_are_empty_tdm_only() -> void:
	# TDM seul cette tâche (wasteland.gd ne déclare plus "hardpoints") — voir
	# son en-tête. Vide plutôt qu'absent : `BotMapKnowledge.hp_holds` gère
	# les deux sans planter, vide documente explicitement l'absence de zone.
	assert_array(WastelandBots.data()["bot_knowledge"]["hp_holds"] as Array).is_empty()


func test_hotspots_reference_lane_midpoints_and_strong_positions() -> void:
	var hotspots: Array = WastelandBots.data()["hotspots"]
	assert_int(hotspots.size()).append_failure_message("expected 3 lane midpoints + several strong positions").is_greater_equal(3 + 5)
	for entry in hotspots:
		var h: Dictionary = entry
		assert_bool(h.has("pos") and h.has("lane") and h.has("weight")).is_true()


# ======================================================================
#  §2 — vivant (bake réel) : les points de couloir bots retombent près de la
#  vraie navmesh construite par MapSetup depuis les MÊMES pièces Kit.
# ======================================================================
const _OFFSET := Vector3(19200, 0, 0)
const MAX_SYNC_FRAMES := 20
## Tolérance généreuse : les points de couloir sont dérivés d'un calcul
## purement géométrique (`WastelandBots._ground_y`, rampes + sols/
## plateformes du plan), jamais une vraie requête `NavigationServer3D` (la
## navmesh n'existe pas encore au moment où `WastelandBots.data()` tourne —
## voir l'en-tête de `wasteland_bots.gd`) : cette suite est la vérification
## APRÈS COUP que l'approximation reste bien collée au bake réel.
const _LANE_POINT_XZ_TOLERANCE := 2.0
const _LANE_POINT_Y_TOLERANCE := 2.0

func _setup() -> MapSetup:
	var setup := MapSetup.new()
	setup.map_id = "wasteland"
	setup.position = _OFFSET
	add_child(setup)
	return setup


func _teardown(setup: Node) -> void:
	remove_child(setup)
	setup.free()
	await get_tree().physics_frame


## `tools/bake_bot_spots.gd::NAV_SYNC_FRAMES` (même valeur, même raison) : la
## carte de navigation ne fusionne sa géométrie que quelques frames physiques
## après le bake synchrone — `map_get_closest_point` émet une VRAIE erreur
## moteur ("query failed... made before first map synchronization") tant que
## cette fusion n'a pas eu lieu.
const _NAV_SYNC_FRAMES := 15

func test_bot_lane_points_are_close_to_the_real_navmesh() -> void:
	var setup := _setup()
	for i in _NAV_SYNC_FRAMES:
		await get_tree().physics_frame
	var map_rid := setup.nav_region.get_navigation_map()
	var corridors: Dictionary = WastelandBots.data()["bot_knowledge"]["corridors"]
	var checked := 0
	for key in VALID_LANES:
		for p in (corridors[key] as Array):
			var pos: Vector3 = p
			var q: Vector3 = pos + _OFFSET
			var closest := NavigationServer3D.map_get_closest_point(map_rid, q)
			var xz_gap := Vector2(closest.x - q.x, closest.z - q.z).length()
			assert_float(xz_gap).append_failure_message("lane %s point %s: nearest navmesh point %s (xz gap %.2f m)" % [key, pos, closest - _OFFSET, xz_gap]).is_less_equal(_LANE_POINT_XZ_TOLERANCE)
			assert_float(absf(closest.y - q.y)).append_failure_message("lane %s point %s: vertical gap to navmesh" % [key, pos]).is_less_equal(_LANE_POINT_Y_TOLERANCE)
			checked += 1
	assert_int(checked).append_failure_message("expected several lane points checked").is_greater_equal(3 * LANE_MIN_POINTS)
	await _teardown(setup)
