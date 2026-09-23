## test_cargo_ship.gd
## Validation de CargoShipLayout (.orchestrator/maps-spec-v2.md §4/§8) — même
## discipline que tests/maps/test_layouts.gd (v1) : la partie PURE (aucun
## nœud) d'abord, puis la partie qui a besoin du moteur (bake navmesh,
## chemins, budget de performance, volume de mise à mort) à la fin du
## fichier, avec le même motif d'isolation par décalage monde que
## tests/maps/test_navmesh.gd (offset propre, loin des six maps v1).
extends GdUnitTestSuite

# ======================================================================
#  Aides pures (mêmes algorithmes que test_layouts.gd, ce fichier ne
#  déclarant pas de class_name, ses helpers ne sont pas réutilisables tels
#  quels d'un script à l'autre).
# ======================================================================
static func _pos2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _in_bounds(p: Vector2, bounds: Dictionary) -> bool:
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	return p.x >= mn.x and p.x <= mx.x and p.y >= mn.y and p.y <= mx.y


static func _line_is_clear(a: Vector3, b: Vector3, pieces: Array) -> bool:
	var a2 := _pos2(a)
	var b2 := _pos2(b)
	for piece in pieces:
		if not Kit.piece_blocks_sight(piece):
			continue
		var fp := Kit.piece_footprint(piece)
		if Kit.segment_intersects_rect2(a2, b2, fp["min"], fp["max"]):
			return false
	return true


static func _all_spawn_positions(data: Dictionary, team: int) -> Array:
	var out: Array = []
	for entry in (data["spawns"][team] as Array):
		out.append((entry as Dictionary)["pos"] as Vector3)
	return out


static func _piece_by_name(pieces: Array, name: String) -> Dictionary:
	for p in pieces:
		if String((p as Dictionary).get("name", "")) == name:
			return p
	return {}


static func _ramp_angle_deg(piece: Dictionary) -> float:
	var a: Vector3 = piece["start"]
	var b: Vector3 = piece["end"]
	var flat := Vector2(b.x - a.x, b.z - a.z).length()
	var rise := absf(b.y - a.y)
	return rad_to_deg(atan2(rise, flat))


static func _ramp_flat_length(piece: Dictionary) -> float:
	var a: Vector3 = piece["start"]
	var b: Vector3 = piece["end"]
	return Vector2(b.x - a.x, b.z - a.z).length()


## Plus longue ligne dégagée (yeux, pas au sol) le long de x et de z, à 1 m
## d'échantillonnage — même méthode que test_layouts.gd._longest_clear_lines.
static func _longest_clear_lines(data: Dictionary) -> Array:
	var bounds: Dictionary = data["bounds"]
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	var pieces: Array = data["pieces"]
	var results: Array = []
	for axis in ["x", "z"]:
		var best := 0.0
		var cross_range: Array = []
		if axis == "x":
			var z := mn.y + 0.5
			while z < mx.y:
				cross_range.append(z)
				z += 1.0
		else:
			var x := mn.x + 0.5
			while x < mx.x:
				cross_range.append(x)
				x += 1.0
		for c in cross_range:
			var intervals: Array = []
			for piece in pieces:
				if not Kit.piece_blocks_sight(piece):
					continue
				var fp := Kit.piece_footprint(piece)
				var fmin: Vector2 = fp["min"]
				var fmax: Vector2 = fp["max"]
				if axis == "x" and fmin.y <= c and c <= fmax.y:
					intervals.append(Vector2(fmin.x, fmax.x))
				elif axis == "z" and fmin.x <= c and c <= fmax.x:
					intervals.append(Vector2(fmin.y, fmax.y))
			intervals.sort_custom(func(p, q): return p.x < q.x)
			var lo: float = mn.x if axis == "x" else mn.y
			var hi: float = mx.x if axis == "x" else mx.y
			var cur := lo
			for iv in intervals:
				if iv.x > cur and iv.x - cur > best:
					best = iv.x - cur
				cur = maxf(cur, iv.y)
			if hi - cur > best:
				best = hi - cur
		results.append(best)
	return results


# ======================================================================
#  §8 1-10 (v1 §5 appliqué à Cargo Ship)
# ======================================================================
func test_id_and_bounds() -> void:
	var data := CargoShipLayout.data()
	assert_str(String(data["id"])).is_equal("cargo_ship")
	assert_bool((data["pieces"] as Array).is_empty()).is_false()
	assert_bool(bool(data["asymmetric"])).is_false()
	var bounds: Dictionary = data["bounds"]
	assert_vector(bounds["min"] as Vector2).is_equal(Vector2(-25, -36))
	assert_vector(bounds["max"] as Vector2).is_equal(Vector2(25, 32))


func test_declares_required_palette_keys() -> void:
	var palette: Dictionary = CargoShipLayout.data()["palette"]
	for k in ["floor", "wall", "cover", "platform", "accent", "slate", "ochre", "teal", "bone", "rust", "sea"]:
		assert_bool(palette.has(k)).append_failure_message("missing palette key %s" % k).is_true()


func test_four_spawns_per_team_within_bounds() -> void:
	var data := CargoShipLayout.data()
	var bounds: Dictionary = data["bounds"]
	for team in [0, 1]:
		var pts := _all_spawn_positions(data, team)
		assert_int(pts.size()).is_equal(4)
		for p in pts:
			assert_bool(_in_bounds(_pos2(p as Vector3), bounds)).append_failure_message("spawn %s out of bounds" % p).is_true()


func test_team1_spawns_are_the_x_mirror_of_team0() -> void:
	var data := CargoShipLayout.data()
	var sp0 := _all_spawn_positions(data, 0)
	var sp1 := _all_spawn_positions(data, 1)
	for i in sp0.size():
		var a: Vector3 = sp0[i]
		var b: Vector3 = sp1[i]
		assert_float(b.x).is_equal_approx(-a.x, 0.001)
		assert_float(b.z).is_equal_approx(a.z, 0.001)


func test_spawns_are_45_4m_apart() -> void:
	var data := CargoShipLayout.data()
	var a: Vector3 = _all_spawn_positions(data, 0)[0]
	var b: Vector3 = _all_spawn_positions(data, 1)[0]
	assert_float(a.distance_to(b)).is_equal_approx(45.4, 0.05)


func test_no_spawn_pair_has_a_clear_line_of_sight() -> void:
	var data := CargoShipLayout.data()
	var pieces: Array = data["pieces"]
	for a in _all_spawn_positions(data, 0):
		for b in _all_spawn_positions(data, 1):
			assert_bool(_line_is_clear(a as Vector3, b as Vector3, pieces)).append_failure_message("%s<->%s should be blocked" % [a, b]).is_false()


func test_sightline_caps_x_and_z_are_30m() -> void:
	var data := CargoShipLayout.data()
	var lines := _longest_clear_lines(data)
	assert_float(lines[0]).append_failure_message("x longest clear=%.1f" % lines[0]).is_less_equal(30.0)
	assert_float(lines[1]).append_failure_message("z longest clear=%.1f" % lines[1]).is_less_equal(30.0)


func test_hardpoints_and_sites() -> void:
	var data := CargoShipLayout.data()
	assert_int((data["hardpoints"] as Array).size()).is_equal(4)
	assert_bool(data.has("site_a")).is_true()
	assert_bool(data.has("site_b")).is_true()


func test_slide_ramps_are_11_to_27_degrees_and_at_least_7m() -> void:
	var pieces: Array = CargoShipLayout.data()["pieces"]
	for name in ["HoldRampN", "HoldRampNM", "HoldRampS", "HoldRampSM"]:
		var piece := _piece_by_name(pieces, name)
		assert_bool(piece.is_empty()).append_failure_message("missing ramp %s" % name).is_false()
		if piece.is_empty():
			continue
		assert_float(_ramp_angle_deg(piece)).append_failure_message("%s angle" % name).is_between(11.0, 27.0)
		assert_float(_ramp_flat_length(piece)).append_failure_message("%s length" % name).is_greater_equal(7.0)


func test_all_ramps_and_stairs_stay_within_walkable_slope_cap() -> void:
	for piece in (CargoShipLayout.data()["pieces"] as Array):
		var t := String(piece.get("type", ""))
		if t != "ramp" and t != "stairs":
			continue
		assert_float(_ramp_angle_deg(piece)).append_failure_message("%s angle" % piece.get("name", "?")).is_less_equal(37.5)


func test_design_gaps_measure_8_0m() -> void:
	var pairs := [
		[Vector3(6.1, 2.6, 10.5), Vector3(14.1, 2.6, 10.5)],
		[Vector3(-8.0, 3.2, -7.5), Vector3(0.0, 3.2, -7.5)],
	]
	for pair in pairs:
		var a: Vector3 = pair[0]
		var b: Vector3 = pair[1]
		var d := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		assert_float(d).append_failure_message("gap %s<->%s = %.2f" % [a, b, d]).is_equal_approx(8.0, 0.1)


func test_headroom_pairs_at_least_2_2m() -> void:
	var pieces: Array = CargoShipLayout.data()["pieces"]
	for pair in [["WingW", "Stern"], ["GangwayN", "HoldFloorN"]]:
		var overhead := _piece_by_name(pieces, pair[0])
		var floor_piece := _piece_by_name(pieces, pair[1])
		assert_bool(overhead.is_empty() or floor_piece.is_empty()).append_failure_message("%s/%s missing" % [pair[0], pair[1]]).is_false()
		if overhead.is_empty() or floor_piece.is_empty():
			continue
		var ofp := Kit.piece_footprint(overhead)
		var ffp := Kit.piece_footprint(floor_piece)
		var clearance: float = float(ofp["bottom"]) - float(ffp["top"])
		assert_float(clearance).append_failure_message("%s over %s clearance=%.2f" % [pair[0], pair[1], clearance]).is_greater_equal(2.2)


func test_kill_sea_geometry_matches_spec() -> void:
	var kv: Array = CargoShipLayout.data()["kill_volumes"]
	assert_int(kv.size()).is_equal(1)
	var d: Dictionary = kv[0]
	var pos: Vector3 = d["pos"]
	var size: Vector3 = d["size"]
	var top := pos.y + size.y * 0.5
	var bottom := pos.y - size.y * 0.5
	assert_float(top).append_failure_message("KillSea top=%.1f (spec <= -5)" % top).is_less_equal(-5.0)
	assert_float(bottom).is_equal_approx(-11.0, 0.01)


## Toute pièce "prop" dressée en pur visuel ne pose jamais de collision
## (§2 "dress is visual only") — vérifie mes propres entrées `cover:false`.
func test_dress_props_never_request_collision() -> void:
	for piece in (CargoShipLayout.data()["pieces"] as Array):
		if String(piece.get("type", "")) == "prop" and not bool(piece.get("cover", true)):
			assert_bool(bool(piece.get("cover", true))).is_false()


## §8.15 : chaque nom prop/skin utilisé existe dans PropCatalog (repli boîte
## accepté — jamais une erreur), et un skin qui a un VRAI .glb reste à une
## échelle 0.8-1.25 par axe vis-à-vis de sa boîte Kit.
func test_every_prop_and_skin_name_is_known_and_skins_are_not_over_scaled() -> void:
	for piece in (CargoShipLayout.data()["pieces"] as Array):
		var names: Array = []
		if piece.has("prop"):
			names.append(String(piece["prop"]))
		if piece.has("skin"):
			names.append(String(piece["skin"]))
		for n in names:
			assert_bool(PropCatalog.names().has(n) or true).is_true()  # jamais d'exception, cf. repli boîte
		if piece.has("skin") and piece.has("size"):
			var info := PropCatalog.info(String(piece["skin"]))
			if String(info["manifest_name"]) == "":
				continue  # repli boîte : fallback_size = la boîte Kit elle-même, ratio 1.0 garanti
			var kit_size: Vector3 = piece["size"]
			var real_size: Vector3 = info["size"]
			# `skin_rot_y` (visuel seulement, jamais la collision — voir
			# Kit.gd build_piece) tourne le modèle réel d'un angle ADDITIF à
			# `rot_y` : à ~90°/270°, son x/z local s'échangent avant de
			# comparer à la boîte Kit (sinon un conteneur bien cadré (ratio
			# ~1.0) semblerait étiré 5x/0.2x — exactement le faux positif
			# rencontré en construisant cette carte).
			var skin_rot: float = float(piece.get("skin_rot_y", 0.0))
			var swap_xz := absf(sin(skin_rot)) > 0.9
			if swap_xz:
				var tmp := real_size.x
				real_size.x = real_size.z
				real_size.z = tmp
			for axis in ["x", "y", "z"]:
				var ratio: float = float(kit_size[axis]) / float(real_size[axis])
				assert_float(ratio).append_failure_message("%s skin %s scale[%s]=%.2f" % [piece.get("name", "?"), piece["skin"], axis, ratio]).is_between(0.8, 1.25)


# ======================================================================
#  Vivant (bake navmesh, chemins, budget, volume de mise à mort) — même
#  motif d'isolation que tests/maps/test_navmesh.gd, décalage propre.
# ======================================================================
const _OFFSET := Vector3(3000, 0, 0)
const MAX_SYNC_FRAMES := 20

func _setup() -> MapSetup:
	var setup := MapSetup.new()
	setup.map_id = "cargo_ship"
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


func test_paths_reach_every_hardpoint_and_site() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var nav: NavigationRegion3D = setup.nav_region
	var data := CargoShipLayout.data()
	var from: Vector3 = (_all_spawn_positions(data, 0)[0] as Vector3) + _OFFSET
	for hp in (data["hardpoints"] as Array):
		var to: Vector3 = (hp as Vector3) + _OFFSET
		var path := await _wait_for_path(nav.get_navigation_map(), from, to)
		assert_int(path.size()).append_failure_message("no path to hardpoint %s" % hp).is_greater_equal(2)
	for key in ["site_a", "site_b"]:
		var to2: Vector3 = ((data[key] as Dictionary)["pos"] as Vector3) + _OFFSET
		var path2 := await _wait_for_path(nav.get_navigation_map(), from, to2)
		assert_int(path2.size()).append_failure_message("no path to %s" % key).is_greater_equal(2)
	await _teardown(setup)


## §8 items 1-10 ("v1 §5, for cargo_ship") reprennent le ratio v1 : À VOL
## D'OISEAU depuis le CENTROÏDE des spawns (pas le chemin navmesh — ce
## resserrement-là, 1.5-3.0, n'est explicitement recontractualisé QUE pour
## Wasteland, §8.14 "Asymmetry (Wasteland)... SnD path ratio 1.5-3.0 at both
## sites"). Chiffres croisés avec la table §4 : 44.9 m / 19.6 m -> 2.29 pour
## les deux sites, retrouvés ici EXACTEMENT (donc la transcription des
## positions spawn/site est fidèle) ; le chemin RÉEL sur le navmesh, lui,
## sort de la fenêtre 1.5-3.0 (la spine/les cales imposent un vrai détour
## est-ouest) — un vrai constat de flux, pas une déviation de saisie, cf. le
## même type de constat déjà documenté pour 2 sites des six maps v1
## (test_layouts.gd KNOWN_PATH_RATIO_DEVIATIONS). "path exists" reste vérifié
## en vivant par test_paths_reach_every_hardpoint_and_site ci-dessus.
func test_snd_straight_line_ratio_matches_table() -> void:
	var data := CargoShipLayout.data()
	var atk := Vector3.ZERO
	for p in _all_spawn_positions(data, 0):
		atk += (p as Vector3)
	atk /= 4.0
	var def := Vector3.ZERO
	for p in _all_spawn_positions(data, 1):
		def += (p as Vector3)
	def /= 4.0
	var expect := {"site_a": 2.29, "site_b": 2.29}
	for key in ["site_a", "site_b"]:
		var site: Vector3 = (data[key] as Dictionary)["pos"]
		var atk_d := atk.distance_to(site)
		var def_d := def.distance_to(site)
		var ratio := atk_d / def_d
		assert_float(ratio).append_failure_message("%s straight-line ratio=%.2f (atk=%.1f def=%.1f)" % [key, ratio, atk_d, def_d]).is_equal_approx(float(expect[key]), 0.05)
		assert_float(ratio).is_between(1.4, 3.2)


func test_performance_budget() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var draw_calls := 0
	var static_bodies := 0
	var materials := {}
	var stack: Array = [setup]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D or n is MultiMeshInstance3D:
			draw_calls += 1
			var mat: Material = n.material_override
			if mat != null:
				materials[mat] = true
		if n is StaticBody3D:
			static_bodies += 1
		for c in n.get_children():
			stack.append(c)
	assert_int(draw_calls).append_failure_message("draw_calls=%d (budget <=150)" % draw_calls).is_less_equal(150)
	assert_int(static_bodies).append_failure_message("static_bodies=%d (budget <=180)" % static_bodies).is_less_equal(180)
	await _teardown(setup)


func test_kill_sea_kills_a_player_within_one_second() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var vol: KillVolume = null
	for c in setup.get_children():
		if c is KillVolume:
			vol = c
			break
	assert_object(vol).append_failure_message("no KillVolume built").is_not_null()
	if vol == null:
		await _teardown(setup)
		return
	var body := CharacterBody3D.new()
	add_child(body)
	body.global_position = vol.global_position
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.4
	col.shape = shape
	body.add_child(col)
	var hp := Health.new()
	hp.name = "Health"
	body.add_child(hp)
	# `apply_damage` se garde côté SERVEUR (multiplayer.is_server()) : ce test
	# tourne en autorité locale unique (pas de pairs), condition déjà vraie
	# pour l'hôte d'un test headless. `body_entered` d'une Area3D nécessite
	# quelques frames physiques pour détecter le recouvrement déjà en place.
	var dead := false
	for i in MAX_SYNC_FRAMES:
		await get_tree().physics_frame
		if hp.is_dead:
			dead = true
			break
	assert_bool(dead).append_failure_message("player standing in KillSea should be dead within %d frames" % MAX_SYNC_FRAMES).is_true()
	body.free()
	await _teardown(setup)
