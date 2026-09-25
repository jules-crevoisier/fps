## test_callouts.gd
## LD-04 (docs/research/03_level_design.md §2.7/§4 : « sans minimap ni
## callouts, on ne répond qu'à... où suis-je », tasks/backlog.yaml) :
##  - chaque map de `Layouts.MAP_IDS` déclare 8-14 zones {name, aabb} ;
##  - les noms sont uniques PAR MAP et <= 14 caractères ;
##  - `MapSetup.callout_at(pos) -> String` résout des points connus (sites,
##    hardpoints, zone de duel) vers une zone déclarée ;
##  - au moins 95% des polygones du navmesh RÉEL (bake synchrone, comme
##    `tests/maps/test_navmesh.gd`) tombent dans une zone (centroïde du
##    polygone testé via `callout_at`).
extends GdUnitTestSuite

const MapSetupScript := preload("res://scripts/levels/maps/MapSetup.gd")

const MIN_ZONES := 8
const MAX_ZONES := 14
const MAX_NAME_LEN := 14
const MIN_COVERAGE := 0.95

var _next_offset_index := 0


## Même isolation que `test_navmesh.gd::_setup_map` (un décalage monde par
## instance) : `callout_at`/les positions de `Layouts.gd` restent en espace
## LOCAL au nœud, donc indépendantes de ce décalage — il ne sert qu'à éviter
## toute interférence physique entre deux maps construites l'une après
## l'autre dans la même scène de test.
func _setup_map(map_id: String) -> MapSetup:
	var offset := Vector3(float(_next_offset_index) * 400.0, 0.0, 0.0)
	_next_offset_index += 1
	var setup := MapSetupScript.new()
	setup.map_id = map_id
	setup.position = offset
	add_child(setup)
	return setup


func _teardown(setup: Node) -> void:
	remove_child(setup)
	setup.free()
	await get_tree().physics_frame


## §1 — données pures (`Layouts.data_for`, aucun moteur requis) : forme des
## zones, unicité et longueur des noms.
func test_callouts_data_shape() -> void:
	for map_id in Layouts.MAP_IDS:
		var data := Layouts.data_for(map_id)
		assert_bool(data.has("callouts")).append_failure_message("%s : pas de clé \"callouts\"" % map_id).is_true()
		var callouts: Array = data.get("callouts", [])
		assert_int(callouts.size()).append_failure_message("%s : %d zones déclarées" % [map_id, callouts.size()]).is_between(MIN_ZONES, MAX_ZONES)

		var seen: Dictionary = {}
		for entry in callouts:
			var zone: Dictionary = entry
			assert_bool(zone.has("name")).append_failure_message("%s : une zone n'a pas de \"name\"" % map_id).is_true()
			assert_bool(zone.has("aabb")).append_failure_message("%s : une zone n'a pas de \"aabb\"" % map_id).is_true()
			var zone_name := String(zone.get("name", ""))
			assert_int(zone_name.length()).append_failure_message("%s : \"%s\" fait %d caractères (> %d)" % [map_id, zone_name, zone_name.length(), MAX_NAME_LEN]).is_less_equal(MAX_NAME_LEN)
			assert_bool(seen.has(zone_name)).append_failure_message("%s : nom \"%s\" dupliqué" % [map_id, zone_name]).is_false()
			seen[zone_name] = true
			assert_bool(zone.get("aabb") is AABB).append_failure_message("%s : \"aabb\" de \"%s\" n'est pas un AABB" % [map_id, zone_name]).is_true()


## §2 — API d'instance : les points connus déclarés par chaque map (sites A/B,
## zone de duel, hardpoints) doivent résoudre vers UNE zone (jamais "").
func test_callout_at_known_points() -> void:
	for map_id in Layouts.MAP_IDS:
		var setup := _setup_map(map_id)
		await get_tree().physics_frame
		var data := Layouts.data_for(map_id)

		var probes: Array = []
		if data.has("site_a"):
			probes.append((data["site_a"] as Dictionary)["pos"])
		if data.has("site_b"):
			probes.append((data["site_b"] as Dictionary)["pos"])
		if data.has("duel_zone"):
			probes.append((data["duel_zone"] as Dictionary)["pos"])
		for h in (data.get("hardpoints", []) as Array):
			probes.append(h)

		for p in probes:
			var pos: Vector3 = p
			var zone_name := setup.callout_at(pos)
			assert_str(zone_name).append_failure_message("%s : aucune zone pour %s" % [map_id, pos]).is_not_equal("")

		await _teardown(setup)


## §3 — hors de toute map (loin dans le vide) : aucune zone, `callout_at`
## renvoie "" au lieu de planter ou d'inventer un nom.
func test_callout_at_outside_returns_empty() -> void:
	var setup := _setup_map("port_ferraille")
	await get_tree().physics_frame
	var zone_name := setup.callout_at(Vector3(50000.0, 0.0, 50000.0))
	assert_str(zone_name).is_equal("")
	await _teardown(setup)


## §4 — couverture du navmesh RÉEL (bake synchrone en `_enter_tree`, comme
## `test_navmesh.gd`) : au moins 95% des polygones ont leur centroïde dans
## une zone déclarée.
func test_navmesh_coverage() -> void:
	for map_id in Layouts.MAP_IDS:
		var setup := _setup_map(map_id)
		await get_tree().physics_frame
		var nav := setup.nav_region
		assert_that(nav).append_failure_message(map_id).is_not_null()
		var nm := nav.navigation_mesh
		var verts := nm.get_vertices()
		var total := nm.get_polygon_count()
		var matched := 0
		for i in total:
			var poly := nm.get_polygon(i)
			if poly.size() < 3:
				continue
			var centroid := Vector3.ZERO
			for idx in poly:
				centroid += (verts[idx] as Vector3)
			centroid /= float(poly.size())
			if setup.callout_at(centroid) != "":
				matched += 1
		var ratio := float(matched) / float(maxi(total, 1))
		assert_float(ratio).append_failure_message("%s : %d/%d polygones dans une zone (%.1f%%)" % [map_id, matched, total, ratio * 100.0]).is_greater_equal(MIN_COVERAGE)
		await _teardown(setup)
