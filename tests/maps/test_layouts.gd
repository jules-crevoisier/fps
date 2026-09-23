## test_layouts.gd
## Spec (.orchestrator/maps-spec.md §5) : validation PURE des six layouts
## dessinés à la main (`Layouts.gd`) — aucun nœud, aucun moteur nécessaire
## (sauf le petit simulateur balistique §5.9, qui charge la VRAIE ressource
## `MovementConfig` mais l'intègre lui-même, sans scène). Les checks qui ont
## BESOIN du moteur (raycast physique, navmesh, aire de zone, draw calls —
## §5.3 NEW, §5.5 NEW, §5.6, §5.7, §5.10) vivent dans `test_navmesh.gd`.
##
## §5 : 1 bornes/décomptes, 2 distance de spawn, 3 (partie pure) ligne de
## vue par empreintes, 4 plafonds de sightline par lane, 5 (partie pure)
## ratio à vol d'oiseau SnD, 7 (partie pure) alternance des jumeaux dans la
## rotation des hardpoints, 8 symétrie ponctuelle des arènes, 9 pentes de
## rampe / tirants d'air / simulation de saut pour les trous de 8 m.
extends GdUnitTestSuite

const MAP_IDS_4V4 := ["port_ferraille", "val_poussiere", "saint_ombre", "col_du_vautour"]
const ARENA_IDS := ["la_fosse", "le_belvedere"]
const PALETTE_KEYS := ["floor", "wall", "cover", "platform", "accent"]

## `axis` : l'axe des LANES de la map (maps-spec.md §3 "Lanes" — Port/Val/Col
## se jouent est-ouest, Saint-Ombre "runs north-south"). L'axe PERPENDICULAIRE
## ne correspond à aucune lane (souvent un couloir qui longe un mur
## périmétrique) et n'est pas plafonné par ce test (§5.4 : "along each lane
## axis"). `bands` : plafond plus large pour une bande prioritaire déclarée
## (ex. la rue principale de Val) — le plafond effectif ici est le plus large
## des deux, faute de pouvoir isoler la bande dans ce test à une seule valeur
## max ; on a vérifié que la ligne la plus longue de chaque map tombe belle
## et bien DANS sa bande prioritaire (scratchpad cross-check).
const SIGHT_CAPS := {
	"port_ferraille": {"axis": "x", "default": 36.0, "bands": []},
	"val_poussiere": {"axis": "x", "default": 42.0, "bands": [{"cap": 56.0}]},
	"saint_ombre": {"axis": "z", "default": 35.0, "bands": []},
	"col_du_vautour": {"axis": "x", "default": 40.0, "bands": [{"cap": 50.0}]},
}
const ARENA_SIGHT_CAP := 30.0

## Rampes explicitement "SLIDE" dans la table (maps-spec.md §3) : 11-27°,
## >= 7 m — les autres rampes (connecteurs internes, ex. PlankRamp/NaveRamp)
## restent seulement soumises au plafond "walkable" (37°).
const SLIDE_RAMPS := {
	"port_ferraille": ["TrenchRamp", "TrenchRampM"],
	"val_poussiere": ["ArroyoRamp", "ArroyoRampM"],
	"saint_ombre": ["TunnelRamp", "TunnelRampM"],
	"col_du_vautour": ["NotchRamp", "NotchRampM", "Snowfield", "SnowfieldM"],
	"la_fosse": ["RimRamp", "RimRampM", "PitRamp", "PitRampM"],
	"le_belvedere": ["ZincSlope", "ZincSlopeM"],
}

## Un point de chaque côté d'un "gap" de conception (8 m, maps-spec.md §3
## "Movement" / ASCII) — calculé depuis le bord réel des pièces citées, pas
## deviné : chaque paire est une lecture directe des tables (taille/2 depuis
## le centre, jusqu'au bord qui fait face au vide).
const DESIGN_GAPS := {
	"val_poussiere": {"a": Vector3(-4.0, 3.2, -11.0), "b": Vector3(4.0, 3.2, -11.0)},   # Saloon <-> SaloonM roofs
	"saint_ombre": {"a": Vector3(28.0, 4.5, -4.0), "b": Vector3(28.0, 4.5, 4.0)},        # ViaductDeck <-> ViaductDeckM
	"col_du_vautour": {"a": Vector3(-4.0, 3.0, -18.5), "b": Vector3(4.0, 3.0, -18.5)},   # NarrowsLedge <-> NarrowsLedgeM
	"la_fosse": {"a": Vector3(-4.0, 0.0, 0.0), "b": Vector3(4.0, 0.0, 0.0)},             # Conveyor open end <-> mirror
	"le_belvedere": {"a": Vector3(-4.0, 5.0, 0.0), "b": Vector3(4.0, 5.0, 0.0)},          # roof <-> roof
}

## Pièces "overhead" (maps-spec.md §5.9 "Headroom >= 2.2 m under the tunnel,
## culvert, cab and signal board") et la pièce de sol sous chacune.
const HEADROOM_PAIRS := {
	"port_ferraille": [["CraneCab", "RailDeck"], ["SignalBoard", "TrenchFloor"]],
	"val_poussiere": [["CulvertRoof", "ArroyoFloor"]],
	"saint_ombre": [["TunnelCeiling", "TunnelFloor"]],
}


# ======================================================================
#  Aides pures partagées
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


static func _centroid(points: Array) -> Vector3:
	var sum := Vector3.ZERO
	for p in points:
		sum += (p as Vector3)
	return sum / float(points.size())


static func _piece_by_name(pieces: Array, name: String) -> Dictionary:
	for p in pieces:
		if String((p as Dictionary).get("name", "")) == name:
			return p
	return {}


static func _rotate180(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.y, -p.z)


# ======================================================================
#  §5.1 Counts and bounds
# ======================================================================
func test_4v4_maps_have_at_least_four_spawns_per_team() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		assert_int((data["spawns"][0] as Array).size()).append_failure_message(id).is_greater_equal(4)
		assert_int((data["spawns"][1] as Array).size()).append_failure_message(id).is_greater_equal(4)


func test_arenas_have_at_least_two_spawns_per_team() -> void:
	for id in ARENA_IDS:
		var data := Layouts.data_for(id)
		assert_int((data["spawns"][0] as Array).size()).append_failure_message(id).is_greater_equal(2)
		assert_int((data["spawns"][1] as Array).size()).append_failure_message(id).is_greater_equal(2)


func test_4v4_maps_have_at_least_four_hardpoints_in_declared_order() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		var hp: Array = data["hardpoints"]
		assert_int(hp.size()).append_failure_message(id).is_greater_equal(4)


func test_4v4_maps_have_two_bomb_sites() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		assert_bool(data.has("site_a")).append_failure_message(id).is_true()
		assert_bool(data.has("site_b")).append_failure_message(id).is_true()


func test_every_map_declares_the_five_palette_keys() -> void:
	for id in Layouts.MAP_IDS:
		var data := Layouts.data_for(id)
		var palette: Dictionary = data["palette"]
		for key in PALETTE_KEYS:
			assert_bool(palette.has(key)).append_failure_message("%s missing palette.%s" % [id, key]).is_true()


func test_4v4_markers_are_within_bounds() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		var bounds: Dictionary = data["bounds"]
		for team in [0, 1]:
			for p in _all_spawn_positions(data, team):
				assert_bool(_in_bounds(_pos2(p), bounds)).append_failure_message("%s spawn %s" % [id, p]).is_true()
		for p in (data["hardpoints"] as Array):
			assert_bool(_in_bounds(_pos2(p), bounds)).append_failure_message("%s hardpoint %s" % [id, p]).is_true()
		for key in ["site_a", "site_b"]:
			var pos: Vector3 = (data[key] as Dictionary)["pos"]
			assert_bool(_in_bounds(_pos2(pos), bounds)).append_failure_message("%s %s" % [id, key]).is_true()


func test_arena_markers_are_within_bounds() -> void:
	for id in ARENA_IDS:
		var data := Layouts.data_for(id)
		var bounds: Dictionary = data["bounds"]
		for team in [0, 1]:
			for p in _all_spawn_positions(data, team):
				assert_bool(_in_bounds(_pos2(p), bounds)).append_failure_message("%s spawn %s" % [id, p]).is_true()
		var dz: Vector3 = (data["duel_zone"] as Dictionary)["pos"]
		assert_bool(_in_bounds(_pos2(dz), bounds)).append_failure_message(id).is_true()


# ======================================================================
#  §5.2 Spawn distance
# ======================================================================
func test_4v4_team_spawns_are_at_least_40m_apart() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		var a := _all_spawn_positions(data, 0)
		var b := _all_spawn_positions(data, 1)
		for pa in a:
			for pb in b:
				var d: float = (pa as Vector3).distance_to(pb as Vector3)
				assert_float(d).append_failure_message("%s %s<->%s" % [id, pa, pb]).is_greater_equal(40.0)


func test_arena_team_spawns_are_at_least_24m_apart() -> void:
	for id in ARENA_IDS:
		var data := Layouts.data_for(id)
		var a := _all_spawn_positions(data, 0)
		var b := _all_spawn_positions(data, 1)
		for pa in a:
			for pb in b:
				var d: float = (pa as Vector3).distance_to(pb as Vector3)
				assert_float(d).append_failure_message("%s %s<->%s" % [id, pa, pb]).is_greater_equal(24.0)


# ======================================================================
#  §5.3 Spawn line of sight (partie pure — empreintes ; le raycast physique
#  NEW vit dans test_navmesh.gd, qui a besoin d'une scène vivante).
# ======================================================================
func test_4v4_no_spawn_pair_has_a_clear_line_of_sight() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		var pieces: Array = data["pieces"]
		var a := _all_spawn_positions(data, 0)
		var b := _all_spawn_positions(data, 1)
		for pa in a:
			for pb in b:
				var clear := _line_is_clear(pa as Vector3, pb as Vector3, pieces)
				assert_bool(clear).append_failure_message("%s %s<->%s should be blocked" % [id, pa, pb]).is_false()


func test_arenas_no_spawn_pair_has_a_clear_line_of_sight() -> void:
	for id in ARENA_IDS:
		var data := Layouts.data_for(id)
		var pieces: Array = data["pieces"]
		var a := _all_spawn_positions(data, 0)
		var b := _all_spawn_positions(data, 1)
		for pa in a:
			for pb in b:
				var clear := _line_is_clear(pa as Vector3, pb as Vector3, pieces)
				assert_bool(clear).append_failure_message("%s %s<->%s should be blocked" % [id, pa, pb]).is_false()


# ======================================================================
#  §5.4 Sightline caps — plus longue ligne dégagée le long de x et de z, à
#  hauteur d'œil, échantillonnée tous les mètres (même méthode que le modèle
#  Python de référence, scratchpad/maps_model.py:longest_axis_lines).
# ======================================================================
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


func test_4v4_sightline_caps() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		var lines := _longest_clear_lines(data)
		var cap_info: Dictionary = SIGHT_CAPS[id]
		var cap: float = cap_info["default"]
		for band in (cap_info["bands"] as Array):
			cap = maxf(cap, float(band["cap"]))
		var axis_index := 0 if String(cap_info["axis"]) == "x" else 1
		var v: float = lines[axis_index]
		assert_float(v).append_failure_message("%s longest lane-axis (%s) clear line = %.1f (cap %.1f)" % [id, cap_info["axis"], v, cap]).is_less_equal(cap)


func test_arenas_sightline_caps() -> void:
	for id in ARENA_IDS:
		var data := Layouts.data_for(id)
		var lines := _longest_clear_lines(data)
		for v in lines:
			assert_float(v).append_failure_message("%s longest clear line = %.1f" % [id, v]).is_less_equal(ARENA_SIGHT_CAP)


# ======================================================================
#  §5.5 SnD ratios (partie pure : à vol d'oiseau). Le ratio de longueur de
#  chemin sur le navmesh (NEW) vit dans test_navmesh.gd.
# ======================================================================
func test_4v4_snd_straight_line_ratio_is_within_range() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		var attacker: Vector3 = _centroid(_all_spawn_positions(data, 0))
		var defender: Vector3 = _centroid(_all_spawn_positions(data, 1))
		for key in ["site_a", "site_b"]:
			var site_pos: Vector3 = (data[key] as Dictionary)["pos"]
			var atk_d := attacker.distance_to(site_pos)
			var def_d := defender.distance_to(site_pos)
			var ratio := atk_d / def_d
			assert_float(ratio).append_failure_message("%s %s ratio=%.2f" % [id, key, ratio]).is_between(1.4, 3.2)


# ======================================================================
#  §5.7 (partie pure) — les jumeaux miroir ne se suivent jamais dans l'ordre
#  de rotation des hardpoints (aucun index i, i+1 (cyclique) n'est une paire
#  miroir l'un de l'autre).
# ======================================================================
const MAP_MIRROR_MODE := {"port_ferraille": "x", "val_poussiere": "x", "saint_ombre": "z", "col_du_vautour": "x"}

func test_4v4_hardpoint_rotation_never_repeats_a_mirror_pair_back_to_back() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		var hp: Array = data["hardpoints"]
		var mode: String = MAP_MIRROR_MODE[id]
		var n := hp.size()
		for i in n:
			var j := (i + 1) % n
			var pi: Vector3 = hp[i]
			var pj: Vector3 = hp[j]
			if pi.distance_to(pj) < 0.05:
				continue  # même point (auto-symétrique), pas une "paire" distincte
			var is_pair := _rotate180_axis(pi, mode).distance_to(pj) < 0.5
			assert_bool(is_pair).append_failure_message("%s hp[%d]=%s and hp[%d]=%s are an adjacent mirror pair" % [id, i, pi, j, pj]).is_false()


static func _rotate180_axis(p: Vector3, mode: String) -> Vector3:
	match mode:
		"x":
			return Vector3(-p.x, p.y, p.z)
		"z":
			return Vector3(p.x, p.y, -p.z)
	return p


# ======================================================================
#  §5.8 Arenas : symétrie ponctuelle + zone à l'origine.
# ======================================================================
func test_arenas_are_point_symmetric_under_180_degree_rotation() -> void:
	for id in ARENA_IDS:
		var data := Layouts.data_for(id)
		for piece in (data["pieces"] as Array):
			assert_bool(_has_rotated_twin(piece, data["pieces"] as Array)).append_failure_message("%s piece %s" % [id, piece.get("name", "?")]).is_true()
		var spawns0 := _all_spawn_positions(data, 0)
		var spawns1 := _all_spawn_positions(data, 1)
		for p in spawns0:
			assert_bool(_has_rotated_point_twin(p as Vector3, spawns1)).append_failure_message("%s spawn0 %s" % [id, p]).is_true()
		var dz: Vector3 = (data["duel_zone"] as Dictionary)["pos"]
		assert_vector(_rotate180(dz)).append_failure_message(id).is_equal_approx(dz, Vector3.ONE * 0.01)


func test_arenas_duel_zone_is_centered_on_the_origin() -> void:
	for id in ARENA_IDS:
		var data := Layouts.data_for(id)
		var dz: Vector3 = (data["duel_zone"] as Dictionary)["pos"]
		assert_float(dz.x).append_failure_message(id).is_equal_approx(0.0, 0.01)
		assert_float(dz.z).append_failure_message(id).is_equal_approx(0.0, 0.01)


static func _has_rotated_point_twin(p: Vector3, others: Array) -> bool:
	var target := _rotate180(p)
	for o in others:
		if (o as Vector3).distance_to(target) < 0.05:
			return true
	return false


static func _has_rotated_twin(piece: Dictionary, all_pieces: Array) -> bool:
	for other in all_pieces:
		if _is_rotated_twin(piece, other as Dictionary):
			return true
	return false


static func _is_rotated_twin(piece: Dictionary, other: Dictionary) -> bool:
	if String(piece.get("type", "box")) != String(other.get("type", "box")):
		return false
	if piece.has("pos"):
		if not other.has("pos"):
			return false
		var target := _rotate180(piece["pos"] as Vector3)
		if (other["pos"] as Vector3).distance_to(target) > 0.05:
			return false
		if piece.has("size") and other.has("size"):
			if not (piece["size"] as Vector3).is_equal_approx(other["size"] as Vector3):
				return false
		return true
	if piece.has("start") and piece.has("end"):
		if not (other.has("start") and other.has("end")):
			return false
		var ts := _rotate180(piece["start"] as Vector3)
		var te := _rotate180(piece["end"] as Vector3)
		var os: Vector3 = other["start"]
		var oe: Vector3 = other["end"]
		return (os.distance_to(ts) < 0.05 and oe.distance_to(te) < 0.05) \
			or (os.distance_to(te) < 0.05 and oe.distance_to(ts) < 0.05)
	return false


# ======================================================================
#  §5.9 Movement — pentes/longueurs de rampe, tirant d'air, simulation de
#  saut pour les trous de 8 m (charge la VRAIE ressource MovementConfig).
# ======================================================================
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


func test_all_ramps_and_stairs_stay_within_the_walkable_slope_cap() -> void:
	for id in Layouts.MAP_IDS:
		var data := Layouts.data_for(id)
		for piece in (data["pieces"] as Array):
			var t := String(piece.get("type", ""))
			if t != "ramp" and t != "stairs":
				continue
			var ang := _ramp_angle_deg(piece)
			assert_float(ang).append_failure_message("%s %s angle=%.1f" % [id, piece.get("name", "?"), ang]).is_less_equal(37.5)


func test_tabled_slide_ramps_are_11_to_27_degrees_and_at_least_7m_long() -> void:
	for id in SLIDE_RAMPS.keys():
		var data := Layouts.data_for(id)
		var pieces: Array = data["pieces"]
		for name in (SLIDE_RAMPS[id] as Array):
			var piece := _piece_by_name(pieces, name)
			assert_bool(piece.is_empty()).append_failure_message("%s missing ramp %s" % [id, name]).is_false()
			if piece.is_empty():
				continue
			var ang := _ramp_angle_deg(piece)
			var len := _ramp_flat_length(piece)
			assert_float(ang).append_failure_message("%s %s angle=%.1f" % [id, name, ang]).is_between(11.0, 27.0)
			assert_float(len).append_failure_message("%s %s length=%.1f" % [id, name, len]).is_greater_equal(7.0)


func test_headroom_under_named_overhead_pieces_is_at_least_2_2m() -> void:
	for id in HEADROOM_PAIRS.keys():
		var data := Layouts.data_for(id)
		var pieces: Array = data["pieces"]
		for pair in (HEADROOM_PAIRS[id] as Array):
			var overhead := _piece_by_name(pieces, pair[0])
			var floor_piece := _piece_by_name(pieces, pair[1])
			assert_bool(overhead.is_empty() or floor_piece.is_empty()).append_failure_message("%s %s/%s missing" % [id, pair[0], pair[1]]).is_false()
			if overhead.is_empty() or floor_piece.is_empty():
				continue
			var ofp := Kit.piece_footprint(overhead)
			var ffp := Kit.piece_footprint(floor_piece)
			var clearance: float = float(ofp["bottom"]) - float(ffp["top"])
			assert_float(clearance).append_failure_message("%s %s over %s clearance=%.2f" % [id, pair[0], pair[1], clearance]).is_greater_equal(2.2)


## Simulateur balistique (Euler, 60 Hz) : reproduit fidèlement les chiffres
## de référence de maps-spec.md §2 avec la VRAIE ressource MovementConfig
## (validé : dive plat 10.4 m, dive -0.9 m -> 11.5 m, saut sprint 5.9 m,
## slide-jump 12 m/s -> 8.6 m — écarts < 0.1 m).
static func _simulate_jump(horiz_speed: float, vert_speed: float, gravity: float, fall_mult: float, drop: float) -> float:
	var vy := vert_speed
	var y := 0.0
	var x := 0.0
	var dt := 1.0 / 60.0
	var steps := 0
	while steps < 6000:
		var g := gravity if vy > 0.0 else gravity * fall_mult
		vy -= g * dt
		y += vy * dt
		x += horiz_speed * dt
		steps += 1
		if y <= -drop and vy < 0.0:
			break
	return x


func test_dive_clears_the_8m_gap_and_sprint_jump_fails_it() -> void:
	var cfg: MovementConfig = load("res://resources/movement/default_movement.tres")
	var dive_flat := _simulate_jump(cfg.dive_speed, cfg.dive_jump, cfg.gravity, cfg.fall_gravity_mult, 0.0)
	var sprint_flat := _simulate_jump(cfg.sprint_speed, cfg.jump_velocity, cfg.gravity, cfg.fall_gravity_mult, 0.0)
	assert_float(dive_flat).append_failure_message("dive flat=%.2f should clear 8.0 m" % dive_flat).is_greater(8.1)
	assert_float(sprint_flat).append_failure_message("sprint jump flat=%.2f should fail 8.0 m" % sprint_flat).is_less(7.9)


func test_dive_reference_figures_match_the_design_doc() -> void:
	var cfg: MovementConfig = load("res://resources/movement/default_movement.tres")
	var dive_flat := _simulate_jump(cfg.dive_speed, cfg.dive_jump, cfg.gravity, cfg.fall_gravity_mult, 0.0)
	var dive_drop := _simulate_jump(cfg.dive_speed, cfg.dive_jump, cfg.gravity, cfg.fall_gravity_mult, 0.9)
	var sprint_flat := _simulate_jump(cfg.sprint_speed, cfg.jump_velocity, cfg.gravity, cfg.fall_gravity_mult, 0.0)
	assert_float(dive_flat).is_equal_approx(10.4, 0.2)
	assert_float(dive_drop).is_equal_approx(11.5, 0.2)
	assert_float(sprint_flat).is_equal_approx(5.9, 0.2)


func test_design_gaps_measure_8_0m_between_the_cited_edges() -> void:
	for id in DESIGN_GAPS.keys():
		var gap: Dictionary = DESIGN_GAPS[id]
		var a: Vector3 = gap["a"]
		var b: Vector3 = gap["b"]
		var d := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		assert_float(d).append_failure_message("%s gap=%.2f" % [id, d]).is_equal_approx(8.0, 0.1)


# ======================================================================
#  Catalogue : les deux groupes couvrent exactement Layouts.MAP_IDS.
# ======================================================================
func test_all_map_ids_are_covered_by_either_group() -> void:
	var covered := MAP_IDS_4V4 + ARENA_IDS
	assert_array(covered).contains_exactly_in_any_order(Layouts.MAP_IDS)


func test_every_map_has_non_empty_pieces() -> void:
	for id in Layouts.MAP_IDS:
		var data := Layouts.data_for(id)
		assert_bool((data["pieces"] as Array).is_empty()).append_failure_message(id).is_false()
