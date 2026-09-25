## test_wasteland_los3d.gd
## LD-40 — Wasteland v4, ligne de vue RÉELLE en 3D (raycast contre la
## collision RÉELLEMENT posée, hauteur d'œil 1,6 m), critère d'acceptation :
## "plus longue ligne de vue ≤ 41 m (Grand-Rue) et ≤ 24 m dans le canyon"
## (docs/research/11_wasteland_v4_layout.md §4/§9). REMPLACE le fichier v3
## du même nom (plafonds Crête/Rue/Ravin de l'ancien contrat, verrouillés sur
## une géométrie qui n'existe plus) — la v3 est gelée et non re-testée ici
## (voir `test_wasteland.gd::test_v3_map_is_still_loadable_...`).
extends GdUnitTestSuite

const EYE_HEIGHT := 1.6
const _OFFSET := Vector3(14400, 0, 0)

## §4 "vue max au sol : Grand-Rue ≤ 42 m ... canyon ≤ 25 m" et critère
## d'acceptation de cette tâche, arrondi au chiffre du §9 ("41 m", "24 m").
const CAP_GRAND_RUE := 41.0
const CAP_CANYON := 24.0
## Hauteur libre minimale sur une volée d'escalier/rampe (§c.7/LD-06,
## exceptions >= 2,4 m documentées séparément).
const MIN_HEADROOM := 2.4


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


## Distance de vue dégagée entre `a` et `b` (espace LOCAL à la carte, décalé
## de `_OFFSET` en interne) : renvoie la distance PLEINE si le rayon
## n'accroche rien, sinon -1.0 (ligne bloquée, ne compte pas comme une
## "ligne de vue" au sens du contrat, qui ne plafonne que les lignes
## DÉGAGÉES).
func _sight_distance(space_state: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> float:
	var from: Vector3 = a + _OFFSET
	var to: Vector3 = b + _OFFSET
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space_state.intersect_ray(query)
	if not hit.is_empty():
		return -1.0
	return a.distance_to(b)


func _longest_clear(space_state: PhysicsDirectSpaceState3D, points: Array) -> float:
	var best := 0.0
	for i in points.size():
		for j in range(i + 1, points.size()):
			var d := _sight_distance(space_state, points[i] as Vector3, points[j] as Vector3)
			if d > best:
				best = d
	return best


# ======================================================================
#  Échantillons par lane, à hauteur d'œil (`y = sol local + EYE_HEIGHT`),
#  rapprochés (3 m) pour ne rater aucune brèche.
# ======================================================================
## Grand-Rue (§5 "① Grand-Rue", z −19 à −11) : le bloc Poste + Diligence
## (x −4 à 4) coupe l'axe — segments ouest (x −38 à −4) et est (x 4 à 38)
## seulement, comme le trace réel ("la rue coude ... par deux bouches").
static func _grand_rue_points() -> Array:
	var y := EYE_HEIGHT
	var pts: Array = []
	var x := -38.0
	while x <= -4.0:
		pts.append(Vector3(x, y, -15.0))
		x += 3.0
	x = 4.0
	while x <= 38.0:
		pts.append(Vector3(x, y, -15.0))
		x += 3.0
	return pts


## Canyon (§5 "③ Canyon", z 12 à 20, sol −2) : aiguilles rocheuses en
## chicane, passages de 3,5 m — échantillonné au milieu du flanc (z 16).
static func _canyon_points() -> Array:
	var y := -2.0 + EYE_HEIGHT
	var pts: Array = []
	var x := -40.0
	while x <= 40.0:
		pts.append(Vector3(x, y, 16.0))
		x += 3.0
	return pts


func test_grand_rue_sightline_cap_41m() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var space_state := setup.get_world_3d().direct_space_state
	var longest := _longest_clear(space_state, _grand_rue_points())
	assert_float(longest).append_failure_message("Grand-Rue longest clear=%.1f (cap %.0f)" % [longest, CAP_GRAND_RUE]).is_less_equal(CAP_GRAND_RUE)
	await _teardown(setup)


func test_canyon_sightline_cap_24m() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var space_state := setup.get_world_3d().direct_space_state
	var longest := _longest_clear(space_state, _canyon_points())
	assert_float(longest).append_failure_message("Canyon longest clear=%.1f (cap %.0f)" % [longest, CAP_CANYON]).is_less_equal(CAP_CANYON)
	await _teardown(setup)


## §c.7/LD-06 "hauteur libre >= 2,4 m sur les routes de mouvement" : aucune
## autre pièce ne doit surplomber une volée d'escalier/rampe menant à une
## position forte à moins de cette hauteur.
func test_movement_route_headroom() -> void:
	var data := WastelandLayout.data()
	var pieces: Array = data["pieces"]
	var routes := ["StairImpasseW", "StairPassageW", "StairRuelleW", "StairGalerieW", "RampeCanyonW1", "RampeCanyonW2", "Descente"]
	for route_name in routes:
		var route := _piece_by_name(pieces, route_name)
		assert_bool(route.is_empty()).append_failure_message("route %s missing" % route_name).is_false()
		if route.is_empty():
			continue
		var rfp := Kit.piece_footprint(route)
		var route_top: float = float(rfp["top"])
		for other in pieces:
			if other == route:
				continue
			if String((other as Dictionary).get("type", "")) == "prop":
				continue
			var ofp := Kit.piece_footprint(other)
			var omin: Vector2 = ofp["min"]
			var omax: Vector2 = ofp["max"]
			var rmin: Vector2 = rfp["min"]
			var rmax: Vector2 = rfp["max"]
			var overlaps := rmin.x < omax.x and rmax.x > omin.x and rmin.y < omax.y and rmax.y > omin.y
			if not overlaps:
				continue
			var obottom: float = float(ofp["bottom"])
			if obottom <= route_top:
				continue  # pas un surplomb (au même niveau ou en dessous)
			var clearance := obottom - route_top
			assert_float(clearance).append_failure_message("%s surplombé par %s, clearance=%.2f" % [route_name, (other as Dictionary).get("name", "?"), clearance]).is_greater_equal(MIN_HEADROOM)


static func _piece_by_name(pieces: Array, nm: String) -> Dictionary:
	for p in pieces:
		if String((p as Dictionary).get("name", "")) == nm:
			return p
	return {}
