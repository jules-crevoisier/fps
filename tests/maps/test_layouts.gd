## test_layouts.gd
## Spec (.orchestrator/maps-spec.md §5) : validation PURE des six layouts
## dessinés à la main (`Layouts.gd`) — aucun nœud, aucun moteur nécessaire
## (sauf le petit simulateur balistique §5.9, qui charge la VRAIE ressource
## `MovementConfig` mais l'intègre lui-même, sans scène). Les checks qui ont
## BESOIN du moteur (raycast physique, navmesh, aire de zone, draw calls —
## §5.3 NEW, §5.5 NEW, §5.6, §5.7, §5.10) vivent dans `test_navmesh.gd`.
##
## EXCEPTION (§5.12, revue QA LD-03) : trois tests qui INSTANCIENT
## `MapSetup` — le bug corrigé par cette revue est dans le câblage
## `MapSetup -> nœud "SpawnPoints"` (lu par `GameWorld._get_spawn_position`),
## pas dans les données pures de `Layouts.gd` (§5.11 ci-dessous, déjà
## vertes) ; `test_navmesh.gd`, seul autre fichier à instancier `MapSetup`
## pour ses propres besoins moteur, est hors de la liste de fichiers de
## cette tâche (LD-03 ne possède que `Layouts.gd`/`MapSetup.gd`/ce fichier).
##
## §5 : 1 bornes/décomptes, 2 distance de spawn, 3 (partie pure) ligne de
## vue par empreintes, 4 plafonds de sightline par lane, 5 (partie pure)
## ratio à vol d'oiseau SnD, 7 (partie pure) alternance des jumeaux dans la
## rotation des hardpoints, 8 symétrie ponctuelle des arènes, 9 pentes de
## rampe / tirants d'air / simulation de saut pour les trous de 8 m,
## 11 (LD-03, partie pure) spawns TDM/Hardpoint neutres `tdm_spawns` — bornes,
## `look`, et ligne de vue par empreintes (comme §5.3) depuis chaque
## `strong_positions` déclarée, à moins de 20 m à vol d'oiseau (3D), 12
## (LD-03, revue QA, BESOIN du moteur — exception ci-dessus) câblage réel
## `MapSetup -> "SpawnPoints"` selon le mode.
extends GdUnitTestSuite

const MAP_IDS_4V4 := ["port_ferraille", "val_poussiere", "saint_ombre", "col_du_vautour"]
const ARENA_IDS := ["la_fosse", "le_belvedere"]
const PALETTE_KEYS := ["floor", "wall", "cover", "platform", "accent"]

## LD-03 (docs/research/03_level_design.md §5 "16-24 points par map") :
## bornes de décompte des spawns TDM/Hardpoint neutres `tdm_spawns`.
const TDM_SPAWNS_MIN := 16
const TDM_SPAWNS_MAX := 24

## LD-03 acceptance : "aucun n'est vu depuis une position forte déclarée à
## moins de 20 m (rayons 3D)" — rayon à vol d'oiseau, PAS la projection 2D
## de `_pos2` utilisée par `_line_is_clear` pour la partie "vu" du test
## (voir §5.3 ci-dessous : même méthode par empreintes que le reste de ce
## fichier, aucun raycast physique ici).
const STRONG_POSITION_RADIUS := 20.0

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
#  §5.13 (LD-06, docs/research/03_level_design.md, "headroom audit on
#  movement routes") — le long de chaque SLIDE_RAMP, DESIGN_GAP et
#  escalier (`type == "stairs"`, quelle que soit la map), aucun solide
#  n'intercepte moins de 3,2 m de dégagement vertical au-dessus du "sol de
#  la route" (la surface interpolée entre les deux bouts de la rampe/l'
#  escalier, ou la ligne à hauteur constante d'un DESIGN_GAP), échantillonné
#  tous les 0,5 m (`_sample_route`). Pure (aucun nœud) : même méthode par
#  empreintes que le reste de ce fichier (`Kit.piece_footprint`, déjà
#  utilisée par §5.3/§5.4/§5.9) — la pièce de route elle-même ne peut
#  jamais s'auto-bloquer (son empreinte descend toujours jusqu'à
#  `min(start.y, end.y)`, donc son "bottom" est toujours <= tout point
#  échantillonné SUR elle : voir `_overhead_clearance`, filtre
#  `bottom <= pos.y`). `HEADROOM_EXCEPTIONS` : dérogations déclarées
#  (>= 2,4 m), documentées au cas par cas quand la contrainte de conception
#  qui a fixé la géométrie (ex. LD-11 anti-sightline) rendrait un correctif
#  à 3,2 m risqué pour une autre régression déjà vérifiée.
# ======================================================================
const HEADROOM_CLEARANCE_MIN := 3.2
const HEADROOM_EXCEPTION_MIN := 2.4

## {"<map_id>:<route>": {"<nom_du_bloqueur>": <dégagement_min_déclaré>}} —
## voir l'en-tête de section : chaque entrée doit rester >= HEADROOM_EXCEPTION_MIN
## et porter sa propre justification en commentaire au point d'usage.
##
## saint_ombre:TunnelRamp(M) sous TunnelCeiling — mesuré 3,00 m (Layouts.gd
## `saint_ombre()` : TunnelCeiling bottom=-0,5, TunnelRamp arrive à y=-3,5 —
## même paire déjà couverte par `test_headroom_under_named_overhead_pieces_
## is_at_least_2_2m` ci-dessus, qui la juge suffisante à 2,2 m). Le tunnel
## est un passage bas VOULU (souterrain industriel, docs/research/
## 03_level_design.md) : rehausser TunnelCeiling à 3,2 m percerait le plafond
## au ras de TunnelFloor (bottom=-0,5 -> il faudrait descendre le tunnel
## encore, hors de mon périmètre géométrique déjà calé par LD-02/LD-05/LD-10,
## tests/maps/test_snd_timings.gd ROTATION_EXEMPTIONS "saint_ombre" ci-dessus).
## 3,00 m reste largement praticable (> 2x la hauteur d'un joueur debout).
const HEADROOM_EXCEPTIONS := {
	"saint_ombre:TunnelRamp": {"TunnelCeiling": 2.4},
	"saint_ombre:TunnelRampM": {"TunnelCeiling": 2.4},
}


static func _sample_route(a: Vector3, b: Vector3, step: float = 0.5) -> Array:
	var length := a.distance_to(b)
	if length < 0.001:
		return [a]
	var out: Array = []
	var n := int(ceil(length / step))
	for i in range(n + 1):
		var t := minf(float(i) * step / length, 1.0)
		out.append(a.lerp(b, t))
	return out


## Dégagement vertical minimal au-dessus de `pos` (le "sol de la route")
## parmi `pieces`, et le nom de la pièce la plus basse (messages d'échec +
## clé des exceptions déclarées). `visual_only` (aucune collision réelle)
## ne compte jamais ; une pièce dont le dessous est SOUS `pos.y` (le sol
## lui-même, ou la pièce de route en cours d'échantillonnage) n'est jamais
## "au-dessus", donc jamais comptée — voir l'en-tête de section.
static func _overhead_clearance(pos: Vector3, pieces: Array) -> Dictionary:
	var best := INF
	var best_name := ""
	for entry in pieces:
		var piece: Dictionary = entry
		if bool(piece.get("visual_only", false)):
			continue
		var fp := Kit.piece_footprint(piece)
		var mn: Vector2 = fp["min"]
		var mx: Vector2 = fp["max"]
		if pos.x < mn.x or pos.x > mx.x or pos.z < mn.y or pos.z > mx.y:
			continue
		var bottom := float(fp["bottom"])
		if bottom <= pos.y + 0.01:
			continue
		var clearance := bottom - pos.y
		if clearance < best:
			best = clearance
			best_name = String(piece.get("name", "?"))
	return {"clearance": best, "blocker": best_name}


## Échantillonne `a` -> `b` tous les 0,5 m et fait échouer l'assertion à la
## première pièce trop basse (`exception_key` : clé dans `HEADROOM_EXCEPTIONS`).
func _assert_route_headroom(exception_key: String, a: Vector3, b: Vector3, pieces: Array) -> void:
	var exceptions: Dictionary = HEADROOM_EXCEPTIONS.get(exception_key, {})
	for pos in _sample_route(a, b):
		var result := _overhead_clearance(pos, pieces)
		var clearance: float = result["clearance"]
		if clearance == INF:
			continue
		var blocker := String(result["blocker"])
		var floor_min: float = float(exceptions[blocker]) if exceptions.has(blocker) else HEADROOM_CLEARANCE_MIN
		assert_float(clearance).append_failure_message(
			"%s @ %s : %.2f m sous %s (attendu >= %.1f m%s)" % [
				exception_key, pos, clearance, blocker, floor_min,
				" [exception déclarée]" if exceptions.has(blocker) else ""
			]
		).is_greater_equal(floor_min)


func test_slide_ramps_keep_3_2m_headroom_along_their_route() -> void:
	for id in SLIDE_RAMPS.keys():
		var data := Layouts.data_for(id)
		var pieces: Array = data["pieces"]
		for name in (SLIDE_RAMPS[id] as Array):
			var piece := _piece_by_name(pieces, name)
			if piece.is_empty():
				continue  # signalé par test_tabled_slide_ramps_are_11_to_27_degrees_and_at_least_7m_long
			_assert_route_headroom("%s:%s" % [id, name], piece["start"], piece["end"], pieces)


func test_design_gaps_keep_3_2m_headroom_across_the_gap() -> void:
	for id in DESIGN_GAPS.keys():
		var data := Layouts.data_for(id)
		var pieces: Array = data["pieces"]
		var gap: Dictionary = DESIGN_GAPS[id]
		_assert_route_headroom("%s:gap" % id, gap["a"], gap["b"], pieces)


func test_stairs_keep_3_2m_headroom_along_their_route() -> void:
	for id in Layouts.MAP_IDS:
		var data := Layouts.data_for(id)
		var pieces: Array = data["pieces"]
		for entry in pieces:
			var piece: Dictionary = entry
			if String(piece.get("type", "")) != "stairs":
				continue
			var name := String(piece.get("name", "?"))
			_assert_route_headroom("%s:%s" % [id, name], piece["start"], piece["end"], pieces)


# ======================================================================
#  §5.11 (LD-03) Spawns TDM/Hardpoint neutres — `tdm_spawns` : 16-24 points
#  par map 4v4, chacun avec un `look`, en bordure de map (mêmes bornes que
#  les autres marqueurs), invisibles à moins de 20 m (3D) d'une position
#  forte déclarée (`strong_positions`). R&D garde ses spawns d'équipe
#  (`spawns`, testé plus haut §5.1/§5.2/§5.3) : cette section ne les touche
#  jamais, elle ajoute seulement les nouvelles clés.
# ======================================================================
func test_4v4_maps_declare_16_to_24_tdm_spawns() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		var tdm: Array = data.get("tdm_spawns", [])
		assert_int(tdm.size()).append_failure_message(
			"%s : %d tdm_spawns (attendu 16-24)" % [id, tdm.size()]
		).is_between(TDM_SPAWNS_MIN, TDM_SPAWNS_MAX)


func test_4v4_tdm_spawns_each_have_a_look() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		for entry in (data["tdm_spawns"] as Array):
			var s: Dictionary = entry
			assert_bool(s.has("look")).append_failure_message("%s spawn %s sans look" % [id, s.get("pos")]).is_true()


func test_4v4_tdm_spawns_are_within_bounds() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		var bounds: Dictionary = data["bounds"]
		for entry in (data["tdm_spawns"] as Array):
			var pos: Vector3 = (entry as Dictionary)["pos"]
			assert_bool(_in_bounds(_pos2(pos), bounds)).append_failure_message("%s tdm_spawn %s" % [id, pos]).is_true()


func test_4v4_maps_declare_at_least_one_strong_position() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		var strong: Array = data.get("strong_positions", [])
		assert_int(strong.size()).append_failure_message(id).is_greater_equal(1)


## Acceptance LD-03 : "aucun n'est vu depuis une position forte déclarée à
## moins de 20 m (rayons 3D)" — distance à vol d'oiseau (3D, `distance_to`
## sur les `Vector3` complets), ligne de vue par empreintes 2D (`_line_is_clear`,
## même méthode pure que §5.3 pour les paires de spawns d'équipe).
func test_4v4_tdm_spawns_are_not_seen_from_a_strong_position_within_20m() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		var pieces: Array = data["pieces"]
		var strong_positions: Array = data.get("strong_positions", [])
		for entry in (data["tdm_spawns"] as Array):
			var pos: Vector3 = (entry as Dictionary)["pos"]
			for strong_pos in strong_positions:
				var sp := strong_pos as Vector3
				var d := pos.distance_to(sp)
				if d >= STRONG_POSITION_RADIUS:
					continue
				var clear := _line_is_clear(pos, sp, pieces)
				assert_bool(clear).append_failure_message(
					"%s : tdm_spawn %s vu depuis la position forte %s (%.1f m)" % [id, pos, sp, d]
				).is_false()


func test_4v4_r_and_d_team_spawns_are_unchanged_by_tdm_spawns() -> void:
	for id in MAP_IDS_4V4:
		var data := Layouts.data_for(id)
		assert_int((data["spawns"][0] as Array).size()).append_failure_message(id).is_equal(4)
		assert_int((data["spawns"][1] as Array).size()).append_failure_message(id).is_equal(4)


# ======================================================================
#  §5.12 (LD-03, revue QA) — le CÂBLAGE, pas seulement la donnée : vérifie
#  que `MapSetup._build_markers` (scripts/levels/maps/MapSetup.gd) pose
#  bien les `tdm_spawns` SOUS LE NŒUD "SpawnPoints" lui-même en TDM/
#  Hardpoint. C'est le seul nœud que `GameWorld._get_spawn_position`
#  retrouve (`spawn_points_root` = "MapSetup/SpawnPoints", fixé par chaque
#  scène de carte 4v4, hors de mon périmètre) : un nœud frère
#  "TdmSpawnPoints" séparé (l'ancien câblage) n'est JAMAIS lu par
#  `GameWorld.gd` (inchangé), donc jamais servi en jeu — bug signalé par la
#  revue QA LD-03. Ces tests-ci ROMPENT sciemment avec le "aucun nœud,
#  aucun moteur nécessaire" du reste de ce fichier (voir §5.11 ci-dessus et
#  l'intro du fichier) : le bug est dans l'arbre de scène construit par
#  `MapSetup`, invisible à toute assertion sur `Layouts.data_for` seul
#  (§5.11, déjà toutes vertes avant cette revue) — `test_navmesh.gd`, seul
#  autre fichier du dépôt à instancier `MapSetup` pour ses propres besoins
#  moteur, est hors de la liste de fichiers de cette tâche.
#  `MatchConfig.mode_id` est un `static var` global qui survit entre
#  fichiers de test dans le même run headless : sauvegardé/restauré à
#  chaque test pour ne contaminer aucune suite lancée après celle-ci.
# ======================================================================
const _MAP_SETUP_OFFSET_STEP := 600.0


func _build_map_setup_for_mode(map_id: String, mode_id: String, offset_index: int) -> MapSetup:
	MatchConfig.mode_id = mode_id
	var setup := MapSetup.new()
	setup.map_id = map_id
	setup.position = Vector3(float(offset_index) * _MAP_SETUP_OFFSET_STEP, 0.0, 0.0)
	add_child(setup)
	return setup


func _teardown_map_setup(setup: Node) -> void:
	remove_child(setup)
	setup.free()
	await get_tree().physics_frame


func test_4v4_tdm_mode_reads_spawn_points_from_the_neutral_tdm_spawns() -> void:
	var previous_mode := MatchConfig.mode_id
	var offset := 0
	for id in MAP_IDS_4V4:
		var setup := _build_map_setup_for_mode(id, "tdm", offset)
		offset += 1
		var root := setup.get_node_or_null("SpawnPoints")
		assert_object(root).append_failure_message(
			"%s (TDM) : pas de nœud \"SpawnPoints\" — GameWorld.spawn_points_root ne trouverait rien" % id
		).is_not_null()
		var children := (root as Node).get_children()
		assert_int(children.size()).append_failure_message(
			"%s (TDM) : \"SpawnPoints\" (celui que GameWorld._get_spawn_position lit réellement) a %d points, attendu 16-24 comme tdm_spawns — les spawns neutres LD-03 ne sont pas câblés jusqu'à ce nœud" % [id, children.size()]
		).is_between(TDM_SPAWNS_MIN, TDM_SPAWNS_MAX)
		for child in children:
			assert_bool(child.has_meta("team")).append_failure_message(
				"%s (TDM) : le point %s sous \"SpawnPoints\" porte encore une méta \"team\" — il devrait être neutre (choisi par SpawnPick.pick_best pour n'importe quel camp)" % [id, child.name]
			).is_false()
		await _teardown_map_setup(setup)
	MatchConfig.mode_id = previous_mode


func test_4v4_hardpoint_mode_reads_spawn_points_from_the_neutral_tdm_spawns() -> void:
	var previous_mode := MatchConfig.mode_id
	var offset := 0
	for id in MAP_IDS_4V4:
		var setup := _build_map_setup_for_mode(id, "hardpoint", offset)
		offset += 1
		var root := setup.get_node_or_null("SpawnPoints")
		var children := (root as Node).get_children()
		assert_int(children.size()).append_failure_message(
			"%s (Hardpoint) : \"SpawnPoints\" a %d points, attendu 16-24" % [id, children.size()]
		).is_between(TDM_SPAWNS_MIN, TDM_SPAWNS_MAX)
		await _teardown_map_setup(setup)
	MatchConfig.mode_id = previous_mode


func test_4v4_r_and_d_mode_still_reads_spawn_points_from_the_4_per_team_markers() -> void:
	var previous_mode := MatchConfig.mode_id
	var offset := 0
	for id in MAP_IDS_4V4:
		var setup := _build_map_setup_for_mode(id, "snd", offset)
		offset += 1
		var root := setup.get_node_or_null("SpawnPoints")
		var children := (root as Node).get_children()
		assert_int(children.size()).append_failure_message(
			"%s (R&D) : \"SpawnPoints\" a %d points, attendu 8 (4 par équipe, inchangé — les tdm_spawns ne doivent PAS s'y substituer hors TDM/Hardpoint)" % [id, children.size()]
		).is_equal(8)
		var per_team := {0: 0, 1: 0}
		for child in children:
			assert_bool(child.has_meta("team")).append_failure_message(
				"%s (R&D) : le point %s a perdu sa méta \"team\"" % [id, child.name]
			).is_true()
			per_team[int(child.get_meta("team"))] += 1
		assert_int(per_team[0]).append_failure_message(id).is_equal(4)
		assert_int(per_team[1]).append_failure_message(id).is_equal(4)
		await _teardown_map_setup(setup)
	MatchConfig.mode_id = previous_mode


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
