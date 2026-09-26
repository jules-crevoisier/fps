## test_wasteland.gd
## Wasteland v7 — greybox pur (2026-09-26, « fais la carte block que je
## puisse la tester in game »). REMPLACE le contrat v4 (LD-40..44, encore
## visible dans l'historique : symétrie miroir, hardpoints/sites/duel_zone,
## toits — tout ça a changé de forme ou a disparu en v7, voir
## `scripts/levels/maps/layouts/wasteland.gd`). Nouveau contrat vérifié ici :
##  - chaque volume de `data/maps/wasteland_plan.json` est bien construit en
##    pièce Kit, dimensions à ±1 cm (`test_every_json_volume_...`) ;
##  - les apparitions (équipe + TDM) sont sur la navmesh réellement bakée ;
##  - chaque équipe atteint les 3 fronts de couloir (`lanes[].front`) par un
##    chemin de navmesh réel.
extends GdUnitTestSuite


static func _pos2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _in_bounds(p: Vector2, bounds: Dictionary) -> bool:
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	return p.x >= mn.x and p.x <= mx.x and p.y >= mn.y and p.y <= mx.y


static func _piece_by_name(pieces: Array, nm: String) -> Dictionary:
	for p in pieces:
		if String((p as Dictionary).get("name", "")) == nm:
			return p
	return {}


# ======================================================================
#  Pur (aucun moteur) — id/bounds/palette/périmètre.
# ======================================================================
func test_id_bounds_and_asymmetric_flag() -> void:
	var data := WastelandLayout.data()
	assert_str(String(data["id"])).is_equal("wasteland")
	assert_bool((data["pieces"] as Array).is_empty()).is_false()
	assert_bool(bool(data["asymmetric"])).is_true()
	var bounds: Dictionary = data["bounds"]
	assert_vector(bounds["min"] as Vector2).is_equal(Vector2(-42, -25))
	assert_vector(bounds["max"] as Vector2).is_equal(Vector2(42, 25))


func test_declares_required_palette_keys_using_dev_grid() -> void:
	var palette: Dictionary = WastelandLayout.data()["palette"]
	for k in ["wall", "floor", "cover", "stairs", "platform", "oob", "accent"]:
		assert_bool(palette.has(k)).append_failure_message("missing palette key %s" % k).is_true()
	# §2 "un shader UNIQUE, coloré par fonction" : chaque rôle bascule vers
	# le kind canonique "dev_grid" (`Cartoon.dev_grid`, jamais une texture
	# peinte) — voir `WastelandLook.palette()`.
	for role in ["wall", "floor", "cover", "stairs", "platform", "oob"]:
		assert_str(String(palette.get("%s_kind" % role, ""))).append_failure_message("role %s should use dev_grid" % role).is_equal("dev_grid")
	assert_str(String(palette.get("wall_roof_kind", ""))).is_equal("dev_grid")


func test_perimeter_is_a_closed_rectangle_covering_the_bounds() -> void:
	var data := WastelandLayout.data()
	var pts: Array = data["perimeter"]
	assert_int(pts.size()).is_equal(4)
	var bounds: Dictionary = data["bounds"]
	for p in pts:
		assert_bool(_in_bounds(p as Vector2, bounds)).append_failure_message("perimeter point %s outside bounds" % p).is_true()


## §1 "chaque volume du JSON est présent dans la géométrie construite, cotes
## à ±1 cm" — comparaison par type de pièce Kit (box/building2 : AABB pos ±
## size/2 ; ramp/stairs : start/end/width ; fence : start/end en XZ), jamais
## une géométrie recalculée séparément : la SEULE source de vérité est
## `WastelandLayout.data()["pieces"]`, la même que celle bakée par MapSetup.
const _DIM_EPS := 0.011

func test_every_json_volume_is_built_with_matching_dimensions() -> void:
	var plan := WastelandLayout.plan()
	var pieces: Array = WastelandLayout.data()["pieces"]
	var by_name: Dictionary = {}
	for p in pieces:
		by_name[String((p as Dictionary).get("name", ""))] = p
	var checked := 0
	for entry in (plan["volumes"] as Array):
		var v: Dictionary = entry
		var modes: Array = v.get("modes", [])
		if not modes.is_empty() and not modes.has("tdm"):
			continue
		var id := String(v["id"])
		assert_bool(by_name.has(id)).append_failure_message("volume %s (kind %s) missing from built pieces" % [id, v.get("kind", "?")]).is_true()
		if not by_name.has(id):
			continue
		var p: Dictionary = by_name[id]
		match String(p.get("type", "")):
			"box", "building2":
				var pos: Vector3 = p["pos"]
				var size: Vector3 = p["size"]
				var jx: Array = v["x"]
				var jy: Array = v["y"]
				var jz: Array = v["z"]
				assert_float(pos.x - size.x * 0.5).append_failure_message("%s x0" % id).is_equal_approx(float(jx[0]), _DIM_EPS)
				assert_float(pos.x + size.x * 0.5).append_failure_message("%s x1" % id).is_equal_approx(float(jx[1]), _DIM_EPS)
				assert_float(pos.y - size.y * 0.5).append_failure_message("%s y0" % id).is_equal_approx(float(jy[0]), _DIM_EPS)
				assert_float(pos.y + size.y * 0.5).append_failure_message("%s y1" % id).is_equal_approx(float(jy[1]), _DIM_EPS)
				assert_float(pos.z - size.z * 0.5).append_failure_message("%s z0" % id).is_equal_approx(float(jz[0]), _DIM_EPS)
				assert_float(pos.z + size.z * 0.5).append_failure_message("%s z1" % id).is_equal_approx(float(jz[1]), _DIM_EPS)
			"ramp", "stairs":
				var jf: Array = v["from"]
				var jt: Array = v["to"]
				assert_vector(p["start"] as Vector3).append_failure_message("%s start" % id).is_equal_approx(Vector3(float(jf[0]), float(jf[1]), float(jf[2])), Vector3.ONE * _DIM_EPS)
				assert_vector(p["end"] as Vector3).append_failure_message("%s end" % id).is_equal_approx(Vector3(float(jt[0]), float(jt[1]), float(jt[2])), Vector3.ONE * _DIM_EPS)
				assert_float(float(p["width"])).append_failure_message("%s width" % id).is_equal_approx(float(v["w"]), _DIM_EPS)
			"fence":
				var jf2: Array = v["from"]
				var jt2: Array = v["to"]
				var st: Vector3 = p["start"]
				var en: Vector3 = p["end"]
				assert_float(st.x).append_failure_message("%s fence start.x" % id).is_equal_approx(float(jf2[0]), _DIM_EPS)
				assert_float(st.z).append_failure_message("%s fence start.z" % id).is_equal_approx(float(jf2[1]), _DIM_EPS)
				assert_float(en.x).append_failure_message("%s fence end.x" % id).is_equal_approx(float(jt2[0]), _DIM_EPS)
				assert_float(en.z).append_failure_message("%s fence end.z" % id).is_equal_approx(float(jt2[1]), _DIM_EPS)
			_:
				assert_bool(false).append_failure_message("%s: unexpected Kit piece type %s" % [id, p.get("type", "?")]).is_true()
		checked += 1
	assert_int(checked).append_failure_message("expected many volumes checked, got %d" % checked).is_greater(50)


## Aucun volume n'est passé sous silence par un `kind` non géré (le seul cas
## où `WastelandLayout._volume_to_piece` renvoie `null`) : le compte de
## pièces "tdm" égale le compte de volumes filtrés "tdm".
func test_no_volume_is_silently_dropped() -> void:
	var plan := WastelandLayout.plan()
	var expected := 0
	for entry in (plan["volumes"] as Array):
		var v: Dictionary = entry
		var modes: Array = v.get("modes", [])
		if modes.is_empty() or modes.has("tdm"):
			expected += 1
	var pieces: Array = WastelandLayout.data()["pieces"]
	assert_int(pieces.size()).append_failure_message("some JSON volumes did not produce a piece (see push_warning in the test run log)").is_equal(expected)


# ======================================================================
#  Vivant (bake réel) — même motif d'isolation que les autres suites de
#  cartes (décalage dédié pour ne jamais collisionner avec une autre map
#  bakée dans la même session de tests).
# ======================================================================
const _OFFSET := Vector3(10800, 0, 0)
const MAX_SYNC_FRAMES := 20

func _setup(map_id: String = "wasteland") -> MapSetup:
	var setup := MapSetup.new()
	setup.map_id = map_id
	setup.position = _OFFSET
	add_child(setup)
	return setup


func _teardown(setup: Node) -> void:
	remove_child(setup)
	setup.free()
	await get_tree().physics_frame


func _wait_for_path(map_rid: RID, from: Vector3, to: Vector3) -> PackedVector3Array:
	var path: PackedVector3Array = []
	for i in MAX_SYNC_FRAMES:
		path = NavigationServer3D.map_get_path(map_rid, from, to, true)
		if path.size() >= 2:
			return path
		await get_tree().physics_frame
	return path


## `tools/bake_bot_spots.gd::NAV_SYNC_FRAMES` (même valeur, même raison) :
## la carte de navigation ne fusionne sa géométrie que quelques frames
## physiques après le bake synchrone — `map_get_closest_point` (contrairement
## à `map_get_path`, qui retombe silencieusement sur "chemin vide" et se
## prête donc à une boucle de nouvelle tentative) émet une VRAIE erreur
## moteur ("query failed... made before first map synchronization") tant que
## cette fusion n'a pas eu lieu, d'où cette attente FIXE avant tout appel.
const _NAV_SYNC_FRAMES := 15

func _wait_for_nav_sync() -> void:
	for i in _NAV_SYNC_FRAMES:
		await get_tree().physics_frame


## §2 "les apparitions (équipe et TDM) sont sur la navmesh" — tolérance
## généreuse (1,5 m en XZ, 1,5 m en Y) : les positions du plan sont posées au
## sol géométrique + `metrics.marker_lift` (1 m), pas déjà "collées" au bake
## Recast (qui retombe ~0,5 m au-dessus d'un sol plat, cf. l'historique de
## `wasteland_bots.gd`).
const _SPAWN_NAV_XZ_TOLERANCE := 1.5
const _SPAWN_NAV_Y_TOLERANCE := 1.5

func test_team_and_tdm_spawns_are_on_the_real_navmesh() -> void:
	var setup := _setup()
	await _wait_for_nav_sync()
	var map_rid := setup.nav_region.get_navigation_map()
	var data := WastelandLayout.data()
	var pts: Array = []
	for team in (data["spawns"] as Dictionary).keys():
		for entry in (data["spawns"][team] as Array):
			pts.append((entry as Dictionary)["pos"] as Vector3)
	for entry in (data["tdm_spawns"] as Array):
		pts.append((entry as Dictionary)["pos"] as Vector3)
	assert_int(pts.size()).append_failure_message("expected team + tdm spawns").is_greater_equal(8 + 24)
	for p in pts:
		var q: Vector3 = (p as Vector3) + _OFFSET
		var closest := NavigationServer3D.map_get_closest_point(map_rid, q)
		var xz_gap := Vector2(closest.x - q.x, closest.z - q.z).length()
		assert_float(xz_gap).append_failure_message("spawn %s: nearest navmesh point %s (xz gap %.2f m)" % [p, closest - _OFFSET, xz_gap]).is_less_equal(_SPAWN_NAV_XZ_TOLERANCE)
		assert_float(absf(closest.y - q.y)).append_failure_message("spawn %s: vertical gap to navmesh" % p).is_less_equal(_SPAWN_NAV_Y_TOLERANCE)
	await _teardown(setup)


## §2 "chaque apparition atteint les 3 fronts de couloir par un chemin de
## navmesh réel" — `lanes[].front` (`data/maps/wasteland_plan.json`, 3
## couloirs : nord/milieu/canyon), un chemin réel depuis le PREMIER point
## d'apparition de chaque équipe.
func test_each_team_spawn_reaches_the_three_lane_fronts() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var map_rid := setup.nav_region.get_navigation_map()
	var data := WastelandLayout.data()
	var plan := WastelandLayout.plan()
	var fronts: Array = []
	for entry in (plan["lanes"] as Array):
		var ln: Dictionary = entry
		var f: Array = ln["front"]
		fronts.append(Vector3(float(f[0]), float(f[1]), float(f[2])))
	assert_int(fronts.size()).is_equal(3)
	for team in [0, 1]:
		var spawn: Vector3 = ((data["spawns"][team] as Array)[0] as Dictionary)["pos"]
		for front in fronts:
			var path := await _wait_for_path(map_rid, spawn + _OFFSET, (front as Vector3) + _OFFSET)
			assert_int(path.size()).append_failure_message("team %d spawn %s -> front %s: no real navmesh path" % [team, spawn, front]).is_greater_equal(2)
	await _teardown(setup)

# `wasteland_v3` (banc de comparaison bots v3<->v4, gelé) a été supprimé lors
# du nettoyage du prototype 2026-09-26 (« the old v3/v4 test maps ») — le
# test de chargement/bake associé est retiré avec elle.
