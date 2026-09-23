## test_wasteland.gd
## Validation de WastelandLayout (.orchestrator/maps-spec-v2.md §5/§8) — même
## discipline que test_cargo_ship.gd. Map ASYMÉTRIQUE : pas de check miroir,
## à la place la parité mesurée (§8.14) + le périmètre (§7.4/§8.12).
extends GdUnitTestSuite


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
#  §8 1-10 appliqué à Wasteland (couvert autrement par §8.14, mais les
#  bornes/comptes/portée/ligne de vue restent les mêmes checks structurels).
# ======================================================================
func test_id_bounds_and_asymmetric_flag() -> void:
	var data := WastelandLayout.data()
	assert_str(String(data["id"])).is_equal("wasteland")
	assert_bool((data["pieces"] as Array).is_empty()).is_false()
	assert_bool(bool(data["asymmetric"])).is_true()
	var bounds: Dictionary = data["bounds"]
	assert_vector(bounds["min"] as Vector2).is_equal(Vector2(-40, -25))
	assert_vector(bounds["max"] as Vector2).is_equal(Vector2(40, 18))


func test_declares_required_palette_keys() -> void:
	var palette: Dictionary = WastelandLayout.data()["palette"]
	for k in ["floor", "wall", "cover", "platform", "accent", "rock", "adobe"]:
		assert_bool(palette.has(k)).append_failure_message("missing palette key %s" % k).is_true()


func test_four_spawns_per_team_within_bounds() -> void:
	var data := WastelandLayout.data()
	var bounds: Dictionary = data["bounds"]
	for team in [0, 1]:
		var pts := _all_spawn_positions(data, team)
		assert_int(pts.size()).is_equal(4)
		for p in pts:
			assert_bool(_in_bounds(_pos2(p as Vector3), bounds)).append_failure_message("spawn %s out of bounds" % p).is_true()


func test_spawns_are_73m_apart() -> void:
	# §5 "Markers" : "73 m apart" (team0 x=-36.5/-38.5, team1 x=36.5/38.5).
	var data := WastelandLayout.data()
	var a: Vector3 = _all_spawn_positions(data, 0)[0]
	var b: Vector3 = _all_spawn_positions(data, 1)[0]
	assert_float(a.distance_to(b)).is_equal_approx(73.0, 0.05)


func test_no_spawn_pair_has_a_clear_line_of_sight() -> void:
	var data := WastelandLayout.data()
	var pieces: Array = data["pieces"]
	for a in _all_spawn_positions(data, 0):
		for b in _all_spawn_positions(data, 1):
			assert_bool(_line_is_clear(a as Vector3, b as Vector3, pieces)).append_failure_message("%s<->%s should be blocked" % [a, b]).is_false()


func test_sightline_caps_x_32_z_30() -> void:
	var data := WastelandLayout.data()
	var lines := _longest_clear_lines(data)
	assert_float(lines[0]).append_failure_message("x longest clear=%.1f" % lines[0]).is_less_equal(32.0)
	assert_float(lines[1]).append_failure_message("z longest clear=%.1f" % lines[1]).is_less_equal(30.0)


func test_hardpoints_and_sites() -> void:
	var data := WastelandLayout.data()
	assert_int((data["hardpoints"] as Array).size()).is_equal(4)
	assert_vector((data["site_a"] as Dictionary)["pos"] as Vector3).is_equal(Vector3(19, 6.0, -21))
	assert_vector((data["site_b"] as Dictionary)["pos"] as Vector3).is_equal(Vector3(13, 1.5, 7))


func test_slide_ramps() -> void:
	var pieces: Array = WastelandLayout.data()["pieces"]
	# DuneSlide (blue, 15°, 12 m) et DerrickRamp (red, 22°, 11 m).
	var dune := _piece_by_name(pieces, "DuneSlide")
	assert_bool(dune.is_empty()).is_false()
	assert_float(_ramp_angle_deg(dune)).is_between(11.0, 27.0)
	assert_float(_ramp_flat_length(dune)).is_greater_equal(7.0)
	var derrick := _piece_by_name(pieces, "DerrickRamp")
	assert_bool(derrick.is_empty()).is_false()
	assert_float(_ramp_angle_deg(derrick)).is_between(11.0, 27.0)
	assert_float(_ramp_flat_length(derrick)).is_greater_equal(7.0)


func test_all_ramps_and_stairs_stay_within_walkable_slope_cap() -> void:
	for piece in (WastelandLayout.data()["pieces"] as Array):
		var t := String(piece.get("type", ""))
		if t != "ramp" and t != "stairs":
			continue
		assert_float(_ramp_angle_deg(piece)).append_failure_message("%s angle" % piece.get("name", "?")).is_less_equal(37.5)


func test_headroom_pairs_at_least_2_2m() -> void:
	var pieces: Array = WastelandLayout.data()["pieces"]
	for pair in [["FuelPlank", "Ground"], ["CanopyRoof", "Ground"]]:
		var overhead := _piece_by_name(pieces, pair[0])
		var floor_piece := _piece_by_name(pieces, pair[1])
		assert_bool(overhead.is_empty() or floor_piece.is_empty()).append_failure_message("%s/%s missing" % [pair[0], pair[1]]).is_false()
		if overhead.is_empty() or floor_piece.is_empty():
			continue
		var ofp := Kit.piece_footprint(overhead)
		var ffp := Kit.piece_footprint(floor_piece)
		var clearance: float = float(ofp["bottom"]) - float(ffp["top"])
		assert_float(clearance).append_failure_message("%s over %s clearance=%.2f" % [pair[0], pair[1], clearance]).is_greater_equal(2.2)


func test_dress_props_never_request_collision() -> void:
	for piece in (WastelandLayout.data()["pieces"] as Array):
		if String(piece.get("type", "")) == "prop" and not bool(piece.get("cover", true)):
			assert_bool(bool(piece.get("cover", true))).is_false()


func test_every_skin_used_is_not_over_scaled_when_it_has_a_real_mesh() -> void:
	for piece in (WastelandLayout.data()["pieces"] as Array):
		if not (piece.has("skin") and piece.has("size")):
			continue
		var info := PropCatalog.info(String(piece["skin"]))
		if String(info["manifest_name"]) == "":
			continue  # repli boîte -> fallback_size = la boîte Kit, ratio 1.0 garanti
		var kit_size: Vector3 = piece["size"]
		var real_size: Vector3 = info["size"]
		for axis in ["x", "y", "z"]:
			var ratio: float = float(kit_size[axis]) / float(real_size[axis])
			assert_float(ratio).append_failure_message("%s skin %s scale[%s]=%.2f" % [piece.get("name", "?"), piece["skin"], axis, ratio]).is_between(0.8, 1.25)


# ======================================================================
#  §7.4/§8.12 Périmètre — boucle fermée, 8 sommets, h20 (posé par MapSetup).
# ======================================================================
func test_perimeter_is_a_closed_polygon_covering_the_bounds() -> void:
	var data := WastelandLayout.data()
	var pts: Array = data["perimeter"]
	assert_int(pts.size()).is_greater_equal(4)
	var bounds: Dictionary = data["bounds"]
	for p in pts:
		assert_bool(_in_bounds(p as Vector2, bounds)).append_failure_message("perimeter point %s outside bounds" % p).is_true()


# ======================================================================
#  §8.14 Asymétrie mesurée (à vol d'oiseau, les chemins réels vivent dans
#  la partie "vivante" ci-dessous) — table §5.6.2, gaps <= aux limites.
# ======================================================================
func test_measured_parity_straight_line() -> void:
	var data := WastelandLayout.data()
	var blue: Vector3 = _all_spawn_positions(data, 0)[0]
	var red: Vector3 = _all_spawn_positions(data, 1)[0]
	var epaves := Vector3(0, 1.5, 7)
	var blue_d := blue.distance_to(epaves)
	var red_d := red.distance_to(epaves)
	var gap := absf(blue_d - red_d) / maxf(blue_d, red_d)
	assert_float(gap).append_failure_message("Epaves parity gap=%.3f (blue=%.1f red=%.1f)" % [gap, blue_d, red_d]).is_less_equal(0.30)


# ======================================================================
#  Vivant (bake navmesh, chemins, budget, demi-temps/parité navmesh) — même
#  motif d'isolation que test_cargo_ship.gd, décalage distinct.
# ======================================================================
const _OFFSET := Vector3(3600, 0, 0)
const MAX_SYNC_FRAMES := 20

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
	var data := WastelandLayout.data()
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


func test_snd_path_ratio_is_within_range() -> void:
	# §8.14 : "SnD path ratio 1.5-3.0 at both sites" — contractualisé pour
	# Wasteland (contrairement à Cargo, cf. test_cargo_ship.gd) : chemin
	# RÉEL sur le navmesh, pas seulement à vol d'oiseau.
	var setup := _setup()
	await get_tree().physics_frame
	var nav: NavigationRegion3D = setup.nav_region
	var data := WastelandLayout.data()
	var atk: Vector3 = (_all_spawn_positions(data, 0)[0] as Vector3) + _OFFSET
	var def: Vector3 = (_all_spawn_positions(data, 1)[0] as Vector3) + _OFFSET
	for key in ["site_a", "site_b"]:
		var site: Vector3 = ((data[key] as Dictionary)["pos"] as Vector3) + _OFFSET
		var atk_path := await _wait_for_path(nav.get_navigation_map(), atk, site)
		var def_path := await _wait_for_path(nav.get_navigation_map(), def, site)
		var atk_len := 0.0
		for i in range(1, atk_path.size()):
			atk_len += atk_path[i - 1].distance_to(atk_path[i])
		var def_len := 0.0
		for i in range(1, def_path.size()):
			def_len += def_path[i - 1].distance_to(def_path[i])
		if def_len <= 0.01:
			continue
		var ratio := atk_len / def_len
		assert_float(ratio).append_failure_message("%s ratio=%.2f (atk=%.1f def=%.1f)" % [key, ratio, atk_len, def_len]).is_between(1.5, 3.0)
	await _teardown(setup)


func test_performance_budget() -> void:
	var setup := _setup()
	await get_tree().physics_frame
	var draw_calls := 0
	var static_bodies := 0
	var stack: Array = [setup]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D or n is MultiMeshInstance3D:
			draw_calls += 1
		if n is StaticBody3D:
			static_bodies += 1
		for c in n.get_children():
			stack.append(c)
	assert_int(draw_calls).append_failure_message("draw_calls=%d (budget <=150)" % draw_calls).is_less_equal(150)
	assert_int(static_bodies).append_failure_message("static_bodies=%d (budget <=210)" % static_bodies).is_less_equal(210)
	await _teardown(setup)
