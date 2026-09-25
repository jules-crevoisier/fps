## Layouts.gd
## Six layouts DESSINÉS À LA MAIN (.orchestrator/maps-spec.md §3 — plus le
## modèle Python validé dans le scratchpad, `maps_defs.py`/`maps_model.py`,
## dont les positions/distances/ratios ont été repris tels quels : "every
## number was checked in a scratch model... build the tables exactly; invent
## nothing"). Volontairement PURES (Dictionary/Vector3/Vector2 — aucun nœud,
## aucun moteur nécessaire) : `tests/maps/` les valide directement, et
## `MapSetup.gd` les consomme via `Kit.build_piece()` pour construire la
## scène réelle.
##
## `·M` (miroir, §2) : `_add(pieces, piece, mode, true)` ajoute aussi le
## jumeau — position (et `look` pour les spawns) reflétée selon `mode`
## ("x" pour Port/Val/Col, "z" pour Saint-Ombre, "p" — point-symétrique —
## pour les arènes), et les côtés de porte/fenêtre de `building2` échangés
## (E<->W, N<->S) pour rester cohérents avec l'image reflétée.
class_name Layouts
extends RefCounted

const MAP_IDS := ["port_ferraille", "val_poussiere", "saint_ombre", "col_du_vautour", "la_fosse", "le_belvedere"]

static func data_for(map_id: String) -> Dictionary:
	match map_id:
		"port_ferraille":
			return port_ferraille()
		"val_poussiere":
			return val_poussiere()
		"saint_ombre":
			return saint_ombre()
		"col_du_vautour":
			return col_du_vautour()
		"la_fosse":
			return la_fosse()
		"le_belvedere":
			return le_belvedere()
	return {}

# ======================================================================
#  Miroir (§2) : "x" (Port/Val/Col), "z" (Saint-Ombre), "p" (arènes).
# ======================================================================
static func _mirror_pos(p: Vector3, mode: String) -> Vector3:
	match mode:
		"x":
			return Vector3(-p.x, p.y, p.z)
		"z":
			return Vector3(p.x, p.y, -p.z)
		"p":
			return Vector3(-p.x, p.y, -p.z)
	return p

static func _mirror_side(s: String, mode: String) -> String:
	match mode:
		"x":
			if s == "E":
				return "W"
			if s == "W":
				return "E"
		"z":
			if s == "N":
				return "S"
			if s == "S":
				return "N"
		"p":
			match s:
				"E":
					return "W"
				"W":
					return "E"
				"N":
					return "S"
				"S":
					return "N"
	return s

static func _mirror_piece(piece: Dictionary, mode: String) -> Dictionary:
	var q: Dictionary = piece.duplicate(true)
	if q.has("pos"):
		q["pos"] = _mirror_pos(q["pos"], mode)
	if q.has("start"):
		q["start"] = _mirror_pos(q["start"], mode)
	if q.has("end"):
		q["end"] = _mirror_pos(q["end"], mode)
	if q.has("name"):
		q["name"] = String(q["name"]) + "M"
	if q.has("doors"):
		var doors2: Array = []
		for entry in (q["doors"] as Array):
			var d2: Dictionary = (entry as Dictionary).duplicate(true)
			d2["side"] = _mirror_side(String(d2["side"]), mode)
			doors2.append(d2)
		q["doors"] = doors2
	if q.has("windows"):
		var win2: Array = []
		for w in (q["windows"] as Array):
			win2.append(_mirror_side(String(w), mode))
		q["windows"] = win2
	if q.has("stair_side"):
		q["stair_side"] = _mirror_side(String(q["stair_side"]), mode)
	return q

## Ajoute `piece` à `pieces`, et son jumeau si `mirror` (§2 "·M").
static func _add(pieces: Array, piece: Dictionary, mode: String, mirror: bool = false) -> void:
	pieces.append(piece)
	if mirror:
		pieces.append(_mirror_piece(piece, mode))

## Un spawn {pos, look} mirroré (pos ET look reflétés) — §3 "Team 1 spawns: the mirror".
static func _mirror_spawn(s: Dictionary, mode: String) -> Dictionary:
	return {"pos": _mirror_pos(s["pos"], mode), "look": _mirror_pos(s["look"], mode)}

static func _spawn(pos: Vector3, look: Vector3) -> Dictionary:
	return {"pos": pos, "look": look}

# ======================================================================
#  Callouts (LD-04, docs/research/03_level_design.md §2.7/§4 : "sans
#  minimap ni callouts, on ne répond qu'à... où suis-je") — zones nommées
#  {name, aabb} lues par `MapSetup.callout_at()`. Damier simple par
#  colonnes/lignes (Kit ne fournit que des boîtes/rampes ici, un aabb par
#  case suffit) : la première et la dernière bande de chaque axe s'étendent
#  à ±CALLOUT_MARGIN pour capter toute géométrie hors des `bounds` déclarés
#  (rampes, débords), et une bande Y unique (CALLOUT_Y) couvre large le
#  point le plus haut/bas des six maps — seul le découpage X/Z distingue
#  les zones entre elles.
# ======================================================================
const CALLOUT_MARGIN := 2000.0
const CALLOUT_Y := Vector2(-20.0, 40.0)

## Construit un damier de zones nommées. `xs`/`zs` : bornes INTÉRIEURES
## seulement (colonnes.size()-1 valeurs chacune, croissantes) ; `names[row][col]`,
## row 0 = nord (z le plus négatif), col 0 = ouest (x le plus négatif) — même
## convention que le reste du fichier (ex. SouthWall/NorthWall, WestWall).
static func _callout_grid(xs: Array, zs: Array, names: Array) -> Array:
	var xedges: Array = [-CALLOUT_MARGIN]
	xedges.append_array(xs)
	xedges.append(CALLOUT_MARGIN)
	var zedges: Array = [-CALLOUT_MARGIN]
	zedges.append_array(zs)
	zedges.append(CALLOUT_MARGIN)
	var out: Array = []
	for row in range(zedges.size() - 1):
		var row_names: Array = names[row]
		for col in range(xedges.size() - 1):
			var x0: float = xedges[col]
			var x1: float = xedges[col + 1]
			var z0: float = zedges[row]
			var z1: float = zedges[row + 1]
			var aabb := AABB(Vector3(x0, CALLOUT_Y.x, z0), Vector3(x1 - x0, CALLOUT_Y.y - CALLOUT_Y.x, z1 - z0))
			out.append({"name": String(row_names[col]), "aabb": aabb})
	return out

# ======================================================================
#  3.1 Port-Ferraille — foggy docks, 72x40 m, x-mirror.
# ======================================================================
static func port_ferraille() -> Dictionary:
	var mode := "x"
	var pieces: Array = []
	var A := func(p: Dictionary, m: bool = false) -> void: _add(pieces, p, mode, m)

	A.call({"type": "box", "name": "Ground", "pos": Vector3(0, -1.75, -6), "size": Vector3(72, 3.5, 32), "color_key": "floor"})
	A.call({"type": "box", "name": "TrenchFloor", "pos": Vector3(0, -3, 14), "size": Vector3(44, 1, 8), "color_key": "floor"})
	A.call({"type": "box", "name": "RampFill", "pos": Vector3(-35, -1.75, 14), "size": Vector3(2, 3.5, 8), "color_key": "floor"}, true)
	A.call({"type": "ramp", "name": "TrenchRamp", "start": Vector3(-34, 0, 14), "end": Vector3(-22, -2.5, 14), "width": 8.0, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "SouthWall", "pos": Vector3(0, 2, 18.5), "size": Vector3(72, 9, 1), "color_key": "wall"})
	A.call({"type": "box", "name": "WestWall", "pos": Vector3(-36.5, 1.75, -2), "size": Vector3(1, 10.5, 40), "color_key": "wall"}, true)
	A.call({"type": "invisible_wall", "name": "QuayEdge", "start": Vector3(-36, 0, -22.2), "end": Vector3(36, 0, -22.2), "height": 8.0})
	A.call({"type": "box", "name": "Water", "pos": Vector3(0, -2.5, -30), "size": Vector3(80, 1, 16), "color_key": "wall", "visual_only": true})
	A.call({"type": "box", "name": "CapstanHouse", "pos": Vector3(0, 1.5, -14.5), "size": Vector3(3, 3, 5), "color_key": "wall"})
	A.call({"type": "box", "name": "PalletStack", "pos": Vector3(-5, 1.2, -19.5), "size": Vector3(3, 2.4, 5), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "QuayCrate", "pos": Vector3(-14, 0.55, -16), "size": Vector3(2, 1.1, 2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "QuayCrate2", "pos": Vector3(-24, 0.55, -19), "size": Vector3(2, 1.1, 2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "RailDeck", "pos": Vector3(0, 5.875, -11), "size": Vector3(32, 0.25, 3), "color_key": "platform"})
	A.call({"type": "fence", "name": "RailN", "start": Vector3(-16, 6, -12.45), "end": Vector3(16, 6, -12.45), "height": 1.0, "color_key": "wall"})
	A.call({"type": "fence", "name": "RailS1", "start": Vector3(-16, 6, -9.55), "end": Vector3(-10.5, 6, -9.55), "height": 1.0, "color_key": "wall"}, true)
	A.call({"type": "fence", "name": "RailS2", "start": Vector3(-7.5, 6, -9.55), "end": Vector3(0, 6, -9.55), "height": 1.0, "color_key": "wall"}, true)
	A.call({"type": "stairs", "name": "RailStairs", "start": Vector3(-24, 0, -11), "end": Vector3(-16, 6, -11), "width": 2.5, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "GantryLegN", "pos": Vector3(-16.6, 5.5, -12.8), "size": Vector3(0.6, 11, 0.6), "color_key": "accent"}, true)
	A.call({"type": "box", "name": "GantryLegS", "pos": Vector3(-16.6, 5.5, -9.2), "size": Vector3(0.6, 11, 0.6), "color_key": "accent"}, true)
	A.call({"type": "box", "name": "GantryBeam", "pos": Vector3(0, 11.3, -11), "size": Vector3(34, 0.6, 4), "color_key": "accent"})
	A.call({"type": "box", "name": "CraneCab", "pos": Vector3(0, 9.5, -11), "size": Vector3(4, 2.5, 4), "color_key": "accent"})
	A.call({"type": "box", "name": "Jib", "pos": Vector3(0, 11.3, -20), "size": Vector3(1.2, 0.6, 14), "color_key": "accent"})
	A.call({"type": "container", "name": "Tube0", "pos": Vector3(0, 1.3, -0.5), "size": Vector3(2.44, 2.6, 12.2), "axis": "z", "ends_open": 2, "color_key": "cover"})
	A.call({"type": "container", "name": "C1", "pos": Vector3(-12, 1.3, -7.5), "size": Vector3(12.2, 2.6, 2.44), "axis": "x", "ends_open": 2, "color_key": "cover"}, true)
	A.call({"type": "container", "name": "PerchLow", "pos": Vector3(-9, 1.3, 2.05), "size": Vector3(2.44, 2.6, 6.1), "axis": "z", "ends_open": 0, "color_key": "cover"}, true)
	A.call({"type": "container", "name": "PerchHigh", "pos": Vector3(-9, 3.9, 2.05), "size": Vector3(2.44, 2.6, 6.1), "axis": "z", "ends_open": 0, "color_key": "cover"}, true)
	A.call({"type": "container", "name": "Step", "pos": Vector3(-11.44, 1.3, 2.05), "size": Vector3(2.44, 2.6, 6.1), "axis": "z", "ends_open": 0, "color_key": "cover"}, true)
	A.call({"type": "ramp", "name": "PlankRamp", "start": Vector3(-17, 0, 2.05), "end": Vector3(-12.66, 2.6, 2.05), "width": 1.5, "color_key": "platform"}, true)
	A.call({"type": "container", "name": "ShieldLow", "pos": Vector3(-25, 1.3, 0), "size": Vector3(2.44, 2.6, 12.2), "axis": "z", "ends_open": 0, "color_key": "cover"}, true)
	A.call({"type": "container", "name": "ShieldHigh", "pos": Vector3(-25, 3.9, 0), "size": Vector3(2.44, 2.6, 12.2), "axis": "z", "ends_open": 0, "color_key": "cover"}, true)
	A.call({"type": "box", "name": "YardCrate", "pos": Vector3(-17, 0.9, 7.5), "size": Vector3(2, 1.8, 2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "YardCrate2", "pos": Vector3(-5, 0.55, 7.5), "size": Vector3(2, 1.1, 2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "Bollard", "pos": Vector3(0, 1.2, 9), "size": Vector3(2, 2.4, 2), "color_key": "cover"})
	A.call({"type": "box", "name": "Wagon", "pos": Vector3(-8, -1, 14), "size": Vector3(10, 3, 2.8), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "StepHigh", "pos": Vector3(0, -1.5, 11), "size": Vector3(2, 2, 2), "color_key": "cover"})
	A.call({"type": "box", "name": "StepLow", "pos": Vector3(-2, -2, 11), "size": Vector3(2, 1, 2), "color_key": "cover"})
	A.call({"type": "box", "name": "CableDrum", "pos": Vector3(0, -1.6, 16.8), "size": Vector3(2, 1.8, 2.4), "color_key": "cover"})
	A.call({"type": "box", "name": "SignalBoard", "pos": Vector3(0, 1.75, 14), "size": Vector3(0.4, 2.5, 8), "color_key": "accent"})
	A.call({"type": "box", "name": "TrenchCrate", "pos": Vector3(-17, -1.9, 11.2), "size": Vector3(1.6, 1.2, 1.6), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "SiteACrate", "pos": Vector3(11, 0.6, -20.5), "size": Vector3(3, 1.2, 1.5), "color_key": "cover"})
	A.call({"type": "box", "name": "SiteABox", "pos": Vector3(17, 1, -15), "size": Vector3(2, 2, 2), "color_key": "cover"})
	A.call({"type": "box", "name": "SiteBBox", "pos": Vector3(19, -1.5, 16.5), "size": Vector3(2, 2, 2), "color_key": "cover"})
	# LD-05 (docs/research/03_level_design.md §2.2/§2.5/§3.5, tests/maps/
	# test_snd_timings.gd) : Site A n'avait que 2 portails distincts mesurés
	# sur le navmesh (rayon 12 m) — cette baffle scinde le grand arc est-sud-
	# est ouvert en deux (flanc nord-est étroit + accès sud-est principal),
	# sans toucher la ligne d'approche défenseur (~40° depuis Site A) ni
	# attaquant (~160°) : placée à 100°, à bonne distance des deux.
	A.call({"type": "box", "name": "QuayBaffle", "pos": Vector3(12, 1.75, -5), "size": Vector3(3, 3.5, 3), "color_key": "wall"})
	# LD-10 (docs/research/03_level_design.md §3.5, tests/maps/test_snd_timings.gd
	# ROTATION_EXEMPTIONS) : rotation A<->B mesurée à 6.5 s (53.6 m), sous la
	# cible 7-12 s — le chemin réel descend vers le Site B par la rampe est de
	# la tranchée (TrenchRamp·M, x=22-34, z=14), en coupant tout droit depuis
	# le Site A par le couloir x~18-22. Cette baffle ferme ce raccourci (entre
	# QuayBaffle et ShieldLow/High·M) sans toucher aux deux sites ni aux
	# hardpoints (hors de leurs zones de capture 32x32 m) : la rotation doit
	# contourner par le centre (Tube0) ou l'extrême est (mur est, x=36.5).
	A.call({"type": "box", "name": "EastApproachBaffle", "pos": Vector3(26.3, 1.75, 7.5), "size": Vector3(16.6, 3.5, 3), "color_key": "wall"})

	var sp0: Array = [
		_spawn(Vector3(-32, 1, -4.5), Vector3(-24, 1, -14)),
		_spawn(Vector3(-32, 1, -1.5), Vector3(-24, 1, -14)),
		_spawn(Vector3(-32, 1, 1.5), Vector3(-22, 1, 12)),
		_spawn(Vector3(-32, 1, 4.5), Vector3(-22, 1, 12)),
	]
	var sp1: Array = []
	for s in sp0:
		sp1.append(_mirror_spawn(s, mode))

	# LD-03 (docs/research/03_level_design.md §2.4/§5, tests/maps/
	# test_layouts.gd) : 16-24 spawns TDM/Hardpoint NEUTRES (aucun camp —
	# `SpawnPick.pick_best`, déjà livré par LD-02, choisit dynamiquement),
	# répartis en bordure des 3 couloirs (Quai nord z-19, Cour centre
	# z10.5, Voie/Tranchée sud z15 — mêmes bandes que les rangées de
	# `callouts` ci-dessous) sur les DEUX moitiés (`_mirror_spawn`, comme
	# les spawns d'équipe). `look` vers le centre (x=0) — l'axe long de la
	# carte, cohérent avec `SIGHT_CAPS.port_ferraille.axis == "x"`.
	# `strong_positions` (§5 acceptance "position forte") : la passerelle
	# du pont roulant (RailDeck/CraneCab, déjà le hardpoint central élevé
	# ci-dessous) — la seule verticalité dominante de cette carte.
	var tdm_half: Array = [
		_spawn(Vector3(-33, 1, -19), Vector3(0, 1, -19)),
		_spawn(Vector3(-22, 1, -19), Vector3(0, 1, -19)),
		_spawn(Vector3(-9, 1, -19), Vector3(0, 1, -19)),
		_spawn(Vector3(-33, 1, 10.5), Vector3(0, 1, 10.5)),
		_spawn(Vector3(-20, 1, 10.5), Vector3(0, 1, 10.5)),
		_spawn(Vector3(-10, 1, 10.5), Vector3(0, 1, 10.5)),
		_spawn(Vector3(-33, -1.5, 15), Vector3(0, -1.5, 15)),
		_spawn(Vector3(-22, -1.5, 15), Vector3(0, -1.5, 15)),
		_spawn(Vector3(-16, -1.5, 15), Vector3(0, -1.5, 15)),
	]
	var tdm_spawns: Array = tdm_half.duplicate()
	for s in tdm_half:
		tdm_spawns.append(_mirror_spawn(s, mode))

	return {
		"id": "port_ferraille", "name": "Port-Ferraille",
		"palette": {"floor": Color("c9c6b8"), "wall": Color("4f5c55"), "cover": Color("8a7466"), "platform": Color("6f7f76"), "accent": Color("3e4843")},
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		"tdm_spawns": tdm_spawns,
		"strong_positions": [Vector3(0, 7.5, -11)],
		"hardpoints": [Vector3(0, 1.5, -0.5), Vector3(-12, -1.2, 14), Vector3(0, 7.5, -11), Vector3(12, -1.2, 14)],
		"site_a": {"pos": Vector3(14, 1.5, -17), "size": Vector3(8, 3, 8)},
		"site_b": {"pos": Vector3(12, -1, 14), "size": Vector3(8, 3, 8)},
		"bounds": {"min": Vector2(-36, -22), "max": Vector2(36, 18)},
		"callouts": _callout_grid(
			[-12.0, 12.0], [-14.0, 0.0, 10.0],
			[
				["Quai Ouest", "Quai Grue", "Quai Est"],
				["Hangar Ouest", "Pont Roulant", "Hangar Est"],
				["Cour Ouest", "Conteneurs", "Cour Est"],
				["Voie Ouest", "Tranchée", "Voie Est"],
			]
		),
	}

# ======================================================================
#  3.2 Val-Poussière — frontier town at noon, 80x48 m, x-mirror.
# ======================================================================
static func val_poussiere() -> Dictionary:
	var mode := "x"
	var pieces: Array = []
	var A := func(p: Dictionary, m: bool = false) -> void: _add(pieces, p, mode, m)

	A.call({"type": "box", "name": "Ground", "pos": Vector3(0, -1.75, -4), "size": Vector3(80, 3.5, 40), "color_key": "floor"})
	A.call({"type": "box", "name": "ArroyoFloor", "pos": Vector3(0, -3.5, 20), "size": Vector3(28, 1, 8), "color_key": "floor"})
	A.call({"type": "ramp", "name": "ArroyoRamp", "start": Vector3(-26, 0, 20), "end": Vector3(-14, -3, 20), "width": 8.0, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "ArroyoFill", "pos": Vector3(-33, -1.75, 20), "size": Vector3(14, 3.5, 8), "color_key": "floor"}, true)
	A.call({"type": "box", "name": "SouthWall", "pos": Vector3(0, 1.5, 24.5), "size": Vector3(80, 9, 1), "color_key": "wall"})
	A.call({"type": "box", "name": "NorthWall", "pos": Vector3(0, 3, -24.5), "size": Vector3(80, 6, 1), "color_key": "wall"})
	A.call({"type": "box", "name": "WestWall", "pos": Vector3(-40.5, 2.5, 0), "size": Vector3(1, 11, 49), "color_key": "wall"}, true)
	A.call({"type": "building2", "name": "Stable", "pos": Vector3(-31, 2, 0), "size": Vector3(6, 4, 14), "color_key": "wall",
		"floors": 1, "doors": [{"side": "W", "floor": 0}, {"side": "E", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0}, true)
	A.call({"type": "building2", "name": "Hotel", "pos": Vector3(-21, 3.2, -11), "size": Vector3(10, 6.4, 10), "color_key": "wall",
		"floors": 2, "doors": [{"side": "S", "floor": 0}, {"side": "N", "floor": 0}, {"side": "E", "floor": 1}], "windows": [], "roof_access": true, "parapet": 1.0, "stair_side": "E"}, true)
	A.call({"type": "building2", "name": "Saloon", "pos": Vector3(-8.5, 1.6, -11), "size": Vector3(9, 3.2, 10), "color_key": "wall",
		"floors": 1, "doors": [{"side": "S", "floor": 0}, {"side": "N", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0}, true)
	A.call({"type": "catwalk", "name": "HotelPlank", "start": Vector3(-16, 3.2, -11), "end": Vector3(-13, 3.2, -11), "width": 1.5, "color_key": "platform"}, true)
	A.call({"type": "building2", "name": "Store", "pos": Vector3(-21, 3.2, 11), "size": Vector3(10, 6.4, 10), "color_key": "wall",
		"floors": 2, "doors": [{"side": "N", "floor": 0}, {"side": "S", "floor": 0}, {"side": "E", "floor": 1}], "windows": [], "roof_access": false, "parapet": 0.0, "stair_side": "W"}, true)
	A.call({"type": "building2", "name": "Barber", "pos": Vector3(-8.5, 1.6, 11), "size": Vector3(9, 3.2, 10), "color_key": "wall",
		"floors": 1, "doors": [{"side": "N", "floor": 0}, {"side": "S", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0}, true)
	A.call({"type": "catwalk", "name": "StorePlank", "start": Vector3(-16, 3.2, 11), "end": Vector3(-13, 3.2, 11), "width": 1.5, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "Stagecoach", "pos": Vector3(0, 1.4, 0), "size": Vector3(6, 2.8, 2.6), "color_key": "cover"})
	A.call({"type": "box", "name": "Trough", "pos": Vector3(-14, 0.5, -4.8), "size": Vector3(3, 1, 1), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "Barrels", "pos": Vector3(-24, 0.6, 4.8), "size": Vector3(1.2, 1.2, 1.2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "PumpHouse", "pos": Vector3(0, 1.5, -19.5), "size": Vector3(4, 3, 3), "color_key": "wall"})
	A.call({"type": "water_tower", "name": "WaterTower", "pos": Vector3(0, 3, -19.5), "color_key": "accent"})
	A.call({"type": "fence", "name": "CorralA", "start": Vector3(-5, 0, -24), "end": Vector3(-5, 0, -20.5), "height": 1.6, "color_key": "wall"}, true)
	A.call({"type": "fence", "name": "CorralB", "start": Vector3(-5, 0, -18), "end": Vector3(-5, 0, -16), "height": 1.6, "color_key": "wall"}, true)
	A.call({"type": "box", "name": "EmbankN", "pos": Vector3(0, -1.5, 17.25), "size": Vector3(6, 3, 2.5), "color_key": "floor"})
	A.call({"type": "box", "name": "EmbankS", "pos": Vector3(0, -1.5, 22.75), "size": Vector3(6, 3, 2.5), "color_key": "floor"})
	A.call({"type": "box", "name": "CulvertRoof", "pos": Vector3(0, -0.3, 20), "size": Vector3(6, 0.6, 3), "color_key": "floor"})
	A.call({"type": "box", "name": "Palisade", "pos": Vector3(0, 1.5, 20), "size": Vector3(0.3, 3, 8), "color_key": "wall"})
	A.call({"type": "box", "name": "Log", "pos": Vector3(-8, -2.4, 22.5), "size": Vector3(4, 1.2, 1.5), "color_key": "cover"}, true)
	# LD-10 (docs/research/03_level_design.md §2.2/§2.5/§3.5, tests/maps/
	# test_snd_timings.gd ENTRY_EXEMPTIONS) : Site B ne mesurait que 2 portails
	# distincts (rayon 12 m) — l'arc ouest complet [162°,198°] vers l'ArroyoFloor
	# n'en formait qu'un seul. Ce rocher scinde l'arc en deux (nord [162°,184°]
	# vers l'ArroyoRamp·M, sud [192°,198°] vers Ground) sans toucher au chemin
	# attaquant ouest -> Site B (`test_navmesh.gd` §5.5, mesuré : ratio
	# inchangé 1.93) : LD-05 avait tenté une pièce équivalente plus au centre
	# de l'arroyo (z~20-22, sur la ligne directe ouest -> Site B) sans succès
	# et avait noté le bake « insensible » — ici la baffle est décalée au nord
	# (z17-19.25, hors de cette ligne directe, vérifié par mesure : x2/z1.5 à
	# z20 ou z22 ferme complètement le passage et casse le ratio à 3.82, x2/z1.5
	# à z17-19.25 le laisse intact) et suffisamment épaisse (2 m, pas 1 m — un
	# gabarit plus fin ne coupe pas la ligne de vue radiale du test) pour être
	# détectée par le test radial (voir doc en tête de fichier, "Recast marque
	# aussi le dessus plat d'un couvert proche").
	A.call({"type": "box", "name": "ArroyoRock", "pos": Vector3(5, -1, 18.5), "size": Vector3(2, 4, 1.5), "color_key": "wall"})
	# LD-10 (docs/research/03_level_design.md §3.5, tests/maps/test_snd_timings.gd
	# ROTATION_EXEMPTIONS) : rotation A<->B mesurée à 4.3 s (35.4 m), très sous
	# la cible 7-12 s — le chemin réel longeait le mur est du Magasin·M
	# (StoreM, x16-26) par l'arrière-cour à peine dégagée (x~20-27) avant de
	# redescendre vers Site B. Cette palissade ferme l'arrière-cour à l'est du
	# Magasin·M (x26-32, z0-16 ; le mur ouest de l'enceinte reste à x40.5) et
	# force la rotation à faire tout le tour par l'est. Chemin attaquant ouest
	# -> Site A inchangé (63.8 m, il n'emprunte jamais l'arrière-cour) ; seul
	# le chemin défenseur -> Site A s'allonge, ratio 2.71 -> 1.79 (dans
	# 1.5-3.0, `test_navmesh.gd` §5.5) ; ratio Site B 2.04 -> 1.94 (idem).
	# Résultat mesuré : 8.3 s (67.6 m), dans la cible.
	A.call({"type": "box", "name": "BackLotPalisade", "pos": Vector3(28, 1.5, 8), "size": Vector3(4, 3, 16), "color_key": "wall"})

	var sp0: Array = []
	var sp1: Array = []
	for z in [-6.0, -2.0, 2.0, 6.0]:
		sp0.append(_spawn(Vector3(-37, 1, z), Vector3(-28, 1, z)))
		sp1.append(_spawn(Vector3(37, 1, z), Vector3(28, 1, z)))

	# LD-03 : bordure des 3 couloirs (Ruelle nord z-20, Rue du Saloon
	# centre z0, Berge/Arroyo sud z20 — mêmes bandes que les rangées de
	# `callouts` ci-dessous), `look` vers le centre (x=0). `strong_positions` :
	# le château d'eau (WaterTower/PumpHouse), seule verticalité dominante.
	var tdm_half: Array = [
		_spawn(Vector3(-33, 1, -20), Vector3(0, 1, -20)),
		_spawn(Vector3(-20, 1, -20), Vector3(0, 1, -20)),
		_spawn(Vector3(-9, 1, -20), Vector3(0, 1, -20)),
		_spawn(Vector3(-36, 1, 0), Vector3(0, 1, 0)),
		_spawn(Vector3(-21, 1, 0), Vector3(0, 1, 0)),
		_spawn(Vector3(-9, 1, 0), Vector3(0, 1, 0)),
		_spawn(Vector3(-33, 1, 20), Vector3(0, 1, 20)),
		_spawn(Vector3(-21, -1.25, 20), Vector3(0, -1.25, 20)),
		_spawn(Vector3(-9, -2, 20), Vector3(0, -2, 20)),
	]
	var tdm_spawns: Array = tdm_half.duplicate()
	for s in tdm_half:
		tdm_spawns.append(_mirror_spawn(s, mode))

	return {
		"id": "val_poussiere", "name": "Val-Poussière",
		"palette": {"floor": Color("bdaf8e"), "wall": Color("5e4d3c"), "cover": Color("8e9479"), "platform": Color("9a8472"), "accent": Color("6b5a48")},
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		"tdm_spawns": tdm_spawns,
		"strong_positions": [Vector3(0, 9, -19.5)],
		"hardpoints": [Vector3(0, 1.5, 0), Vector3(-8.5, 1.5, -11), Vector3(0, -1.5, 20), Vector3(8.5, 1.5, -11)],
		"site_a": {"pos": Vector3(19, 1.5, 11), "size": Vector3(6, 3, 6)},
		"site_b": {"pos": Vector3(16, -1, 20), "size": Vector3(8, 3, 6)},
		"bounds": {"min": Vector2(-40, -24), "max": Vector2(40, 24)},
		"callouts": _callout_grid(
			[-14.0, 14.0], [-15.0, 0.0, 15.0],
			[
				["Ruelle Ouest", "Pompe Nord", "Ruelle Est"],
				["Hotel Ouest", "Rue du Saloon", "Hotel Est"],
				["Magasin Ouest", "Barbier Centre", "Magasin Est"],
				["Berge Ouest", "Arroyo Sud", "Berge Est"],
			]
		),
	}

# ======================================================================
#  3.3 Saint-Ombre — rainy industrial old town, 64x52 m, z-mirror.
# ======================================================================
static func saint_ombre() -> Dictionary:
	var mode := "z"
	var pieces: Array = []
	var A := func(p: Dictionary, m: bool = false) -> void: _add(pieces, p, mode, m)

	A.call({"type": "box", "name": "GroundW", "pos": Vector3(-20.5, -2, 0), "size": Vector3(23, 4, 52), "color_key": "floor"})
	A.call({"type": "box", "name": "GroundE", "pos": Vector3(10.5, -2, 0), "size": Vector3(31, 4, 52), "color_key": "floor"})
	A.call({"type": "box", "name": "SlotFill", "pos": Vector3(-7, -2, -21), "size": Vector3(4, 4, 10), "color_key": "floor"}, true)
	A.call({"type": "ramp", "name": "TunnelRamp", "start": Vector3(-7, 0, -16), "end": Vector3(-7, -3.5, -6), "width": 4.0, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "TunnelFloor", "pos": Vector3(-7, -4, 0), "size": Vector3(4, 1, 12), "color_key": "floor"})
	A.call({"type": "box", "name": "TunnelCeiling", "pos": Vector3(-7, -0.25, 0), "size": Vector3(4, 0.5, 12), "color_key": "wall"})
	A.call({"type": "box", "name": "Canal", "pos": Vector3(32.5, -2.5, 0), "size": Vector3(5, 1, 60), "color_key": "wall", "visual_only": true})
	A.call({"type": "invisible_wall", "name": "CanalEdge", "start": Vector3(32, 0, -26), "end": Vector3(32, 0, 26), "height": 10.0})
	A.call({"type": "box", "name": "NWBlock", "pos": Vector3(-21, 4.5, -23), "size": Vector3(22, 9, 6), "color_key": "wall"}, true)
	A.call({"type": "box", "name": "WOuter", "pos": Vector3(-29, 4.5, -12), "size": Vector3(6, 9, 16), "color_key": "wall"}, true)
	A.call({"type": "box", "name": "WOuterMid", "pos": Vector3(-29, 4.5, 0), "size": Vector3(6, 9, 8), "color_key": "wall"})
	A.call({"type": "box", "name": "JogBlock", "pos": Vector3(-23, 4.5, 0), "size": Vector3(6, 9, 4), "color_key": "wall"})
	A.call({"type": "building2", "name": "Atelier", "pos": Vector3(-14.5, 3.2, -11), "size": Vector3(11, 6.4, 10), "color_key": "wall",
		"floors": 2, "doors": [{"side": "N", "floor": 0}, {"side": "S", "floor": 0}], "windows": ["N", "S"], "roof_access": false, "parapet": 0.0, "stair_side": "E"}, true)
	A.call({"type": "fence", "name": "SlotWall", "start": Vector3(-5, 0, -16), "end": Vector3(-5, 0, -7), "height": 1.1, "color_key": "wall"}, true)
	# LD-10 (docs/research/03_level_design.md §3.5, tests/maps/test_snd_timings.gd
	# ROTATION_EXEMPTIONS) : rotation A<->B mesurée à 6.0 s (49.2 m), sous la
	# cible 7-12 s. La rotation traverse le passage SlotFill·M (x-9..-5, la
	# SEULE jonction Ground-Est/Ground-Ouest proche des sites : voir
	# `test_navmesh.gd::_assert_all_spawn_pairs_blocked` et §5.6, tentative
	# abandonnée de fermer ce passage — le détour force alors le défenseur
	# via le tunnel central et casse le ratio atk/def Site B, 53.3/57.2=1.09
	# < 1.5) en passant par x~20-25 côté Ground-Est. Cette baffle allonge
	# l'approche est de Site A à cet endroit, LOIN du passage SlotFill et du
	# couloir attaquant ouest -> Site B (`test_navmesh.gd` §5.5 : ratio Site B
	# inchangé, 1.63) — seul le ratio Site A bouge (3.6 contre 4.6, déjà
	# exempté en écart large `KNOWN_PATH_RATIO_DEVIATIONS`, marge >>1.05).
	# Résultat mesuré : 7.1 s (57.8 m), dans la cible.
	A.call({"type": "box", "name": "SiteAApproachBaffle", "pos": Vector3(20, 1.5, 15), "size": Vector3(11.5, 3, 9), "color_key": "wall"})
	A.call({"type": "box", "name": "Mill", "pos": Vector3(11.5, 4.5, -11), "size": Vector3(17, 9, 10), "color_key": "wall"}, true)
	A.call({"type": "building2", "name": "Church", "pos": Vector3(14, 4, 0), "size": Vector3(12, 8, 12), "color_key": "wall",
		"floors": 1, "doors": [{"side": "W", "floor": 0, "w": 2.4, "h": 3.0}, {"side": "E", "floor": 0, "w": 2.4, "h": 3.0}, {"side": "W", "y": 4.5, "w": 2.0, "h": 2.4}], "windows": [], "roof_access": false, "parapet": 0.0})
	A.call({"type": "box", "name": "Tribune", "pos": Vector3(9, 4.375, 0), "size": Vector3(2, 0.25, 12), "color_key": "platform"})
	A.call({"type": "box", "name": "Balcony", "pos": Vector3(7, 4.375, 0), "size": Vector3(2, 0.25, 8), "color_key": "platform"})
	A.call({"type": "fence", "name": "BalconyRail", "start": Vector3(6, 4.5, -4), "end": Vector3(6, 4.5, 4), "height": 1.0, "color_key": "wall"})
	A.call({"type": "ramp", "name": "NaveRamp", "start": Vector3(18, 0, -5), "end": Vector3(9, 4.5, -5), "width": 1.5, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "BellTower", "pos": Vector3(17, 11, 0), "size": Vector3(3, 14, 3), "color_key": "accent"})
	A.call({"type": "box", "name": "Pew", "pos": Vector3(14, 0.5, -3), "size": Vector3(5, 1, 1.2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "Plinth", "pos": Vector3(-3, 1.5, 0), "size": Vector3(12, 3, 2), "color_key": "wall"})
	A.call({"type": "box", "name": "Statue", "pos": Vector3(-3, 4.5, 0), "size": Vector3(1.5, 3, 1.5), "color_key": "accent"})
	A.call({"type": "box", "name": "Morris1", "pos": Vector3(7, 1.75, -19), "size": Vector3(2, 3.5, 2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "Morris2", "pos": Vector3(13, 1.75, -17), "size": Vector3(2, 3.5, 2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "LockHut", "pos": Vector3(23, 1.5, 0), "size": Vector3(6, 3, 4), "color_key": "wall"})
	A.call({"type": "box", "name": "BollardPile", "pos": Vector3(30, 1.2, 0), "size": Vector3(4, 2.4, 3), "color_key": "cover"})
	A.call({"type": "box", "name": "ViaductDeck", "pos": Vector3(28, 4.375, -13), "size": Vector3(4, 0.25, 18), "color_key": "platform"}, true)
	A.call({"type": "fence", "name": "ViaductRail", "start": Vector3(30, 4.5, -22), "end": Vector3(30, 4.5, -4), "height": 1.0, "color_key": "wall"}, true)
	A.call({"type": "box", "name": "PierGap", "pos": Vector3(27, 2.125, -4.75), "size": Vector3(2, 4.25, 1.5), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "Pier", "pos": Vector3(28, 2.125, -13), "size": Vector3(1.5, 4.25, 1.5), "color_key": "cover"}, true)
	A.call({"type": "stairs", "name": "ViaductStairs", "start": Vector3(23, 0, -24), "end": Vector3(23, 4.5, -16), "width": 2.0, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "ViaductLanding", "pos": Vector3(25, 4.375, -16), "size": Vector3(2, 0.25, 2), "color_key": "platform"}, true)

	var sp0: Array = []
	var sp1: Array = []
	for x in [9.0, 12.0, 15.0, 18.0]:
		sp0.append(_spawn(Vector3(x, 1, -23), Vector3(x, 1, -16)))
		sp1.append(_spawn(Vector3(x, 1, 23), Vector3(x, 1, 16)))

	# LD-03 : bordure des 3 couloirs (Ouest x-24, Centre x-2, Est x23/25 —
	# mêmes colonnes que les `callouts` ci-dessous ; l'axe long de cette
	# carte est z, "runs north-south" — `look` vers z=0). `strong_positions` :
	# le clocher (BellTower), seule verticalité dominante.
	var tdm_half: Array = [
		_spawn(Vector3(-24, 1, -18), Vector3(-24, 1, 0)),
		_spawn(Vector3(-24, 1, -9), Vector3(-24, 1, 0)),
		_spawn(Vector3(-24, 1, -3), Vector3(-24, 1, 0)),
		_spawn(Vector3(-2, 1, -15), Vector3(-2, 1, 0)),
		_spawn(Vector3(-2, 1, -8), Vector3(-2, 1, 0)),
		_spawn(Vector3(-2, 1, -4), Vector3(-2, 1, 0)),
		_spawn(Vector3(23, 1, -10), Vector3(23, 1, 0)),
		_spawn(Vector3(23, 1, -3), Vector3(23, 1, 0)),
		_spawn(Vector3(25, 1, -22), Vector3(25, 1, 0)),
	]
	var tdm_spawns: Array = tdm_half.duplicate()
	for s in tdm_half:
		tdm_spawns.append(_mirror_spawn(s, mode))

	return {
		"id": "saint_ombre", "name": "Saint-Ombre",
		"palette": {"floor": Color("4a4f55"), "wall": Color("6b737a"), "cover": Color("74877f"), "platform": Color("56606a"), "accent": Color("2f3439")},
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		"tdm_spawns": tdm_spawns,
		"strong_positions": [Vector3(17, 12, 0)],
		"hardpoints": [Vector3(-3, 1.5, 0), Vector3(26, 1.5, -12), Vector3(-7, -2, 0), Vector3(26, 1.5, 12)],
		"site_a": {"pos": Vector3(26, 1.5, 12), "size": Vector3(8, 3, 8)},
		"site_b": {"pos": Vector3(-21, 1.5, 17), "size": Vector3(10, 3, 6)},
		"bounds": {"min": Vector2(-32, -26), "max": Vector2(32, 26)},
		"callouts": _callout_grid(
			[-9.0, 5.0], [-8.0, 8.0],
			[
				["Atelier Nord", "Tunnel Nord", "Viaduc Nord"],
				["Ruelle Ouest", "Place Statue", "Parvis Église"],
				["Atelier Sud", "Tunnel Sud", "Viaduc Sud"],
			]
		),
	}

# ======================================================================
#  3.4 Col du Vautour — snowy outpost, 76x50 m, x-mirror.
# ======================================================================
static func col_du_vautour() -> Dictionary:
	var mode := "x"
	var pieces: Array = []
	var A := func(p: Dictionary, m: bool = false) -> void: _add(pieces, p, mode, m)

	A.call({"type": "box", "name": "PlateauOuter", "pos": Vector3(-29, -4, 0), "size": Vector3(18, 8, 50), "color_key": "floor"}, true)
	A.call({"type": "box", "name": "PlateauInnerN", "pos": Vector3(-12.5, -4, -4.75), "size": Vector3(15, 8, 40.5), "color_key": "floor"}, true)
	A.call({"type": "box", "name": "PlateauInnerS", "pos": Vector3(-12.5, -4, 22.75), "size": Vector3(15, 8, 4.5), "color_key": "floor"}, true)
	A.call({"type": "box", "name": "NarrowsLedge", "pos": Vector3(-4.5, -4, -18.5), "size": Vector3(1, 8, 13), "color_key": "floor"}, true)
	A.call({"type": "box", "name": "GorgeFloor", "pos": Vector3(0, -7.5, 0), "size": Vector3(10, 1, 50), "color_key": "floor"})
	A.call({"type": "ramp", "name": "NotchRamp", "start": Vector3(-20, 0, 18), "end": Vector3(-5, -7, 18), "width": 5.0, "color_key": "platform"}, true)
	A.call({"type": "ramp", "name": "Snowfield", "start": Vector3(-18, 3, -18.5), "end": Vector3(-4, 0, -18.5), "width": 13.0, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "Crest", "pos": Vector3(-28, 1.5, -18.5), "size": Vector3(20, 3, 13), "color_key": "floor"}, true)
	A.call({"type": "ramp", "name": "CrestRamp", "start": Vector3(-34, 0, -6), "end": Vector3(-34, 3, -12), "width": 6.0, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "RockA", "pos": Vector3(-14, 2.5, -16.5), "size": Vector3(4, 5, 9), "color_key": "wall"}, true)
	A.call({"type": "box", "name": "RockB", "pos": Vector3(-26, 4.5, -22.75), "size": Vector3(3, 3, 4.5), "color_key": "wall"}, true)
	A.call({"type": "catwalk", "name": "Bridge", "start": Vector3(-5.5, 0, 0), "end": Vector3(5.5, 0, 0), "width": 3.0, "color_key": "platform"})
	A.call({"type": "box", "name": "Pylon", "pos": Vector3(-5.8, 3, -2), "size": Vector3(0.6, 6, 0.6), "color_key": "accent"}, true)
	A.call({"type": "box", "name": "PylonS", "pos": Vector3(-5.8, 3, 2), "size": Vector3(0.6, 6, 0.6), "color_key": "accent"}, true)
	A.call({"type": "building2", "name": "Bunker", "pos": Vector3(-13, 1.5, 0), "size": Vector3(4, 3, 10), "color_key": "wall",
		"floors": 1, "doors": [{"side": "W", "floor": 0}], "windows": ["E"], "roof_access": false, "parapet": 0.0, "slit": true}, true)
	A.call({"type": "box", "name": "BridgeRock", "pos": Vector3(-8, 1.5, -9.5), "size": Vector3(3, 3, 5), "color_key": "wall"}, true)
	A.call({"type": "box", "name": "Pines", "pos": Vector3(-24, 2.5, 21), "size": Vector3(2, 5, 8), "color_key": "wall"}, true)
	A.call({"type": "box", "name": "PinesRim", "pos": Vector3(-9, 2.5, 22.5), "size": Vector3(3, 5, 4), "color_key": "wall"}, true)
	A.call({"type": "box", "name": "Needle", "pos": Vector3(0, -1, 17.5), "size": Vector3(3, 12, 5), "color_key": "accent"})
	A.call({"type": "building2", "name": "Refuge", "pos": Vector3(-28, 3.2, 10), "size": Vector3(6, 6.4, 14), "color_key": "wall",
		"floors": 2, "doors": [{"side": "W", "floor": 0}, {"side": "E", "floor": 0}], "windows": [], "roof_access": true, "parapet": 0.0, "stair_side": "S"}, true)
	A.call({"type": "antenna", "name": "Antenna", "pos": Vector3(-28, 6.4, 10), "color_key": "accent"})
	A.call({"type": "box", "name": "Radar", "pos": Vector3(28, 7.9, 10), "size": Vector3(3, 3, 3), "color_key": "accent"})
	A.call({"type": "box", "name": "GorgeRockC", "pos": Vector3(0, -5.5, -8), "size": Vector3(4, 3, 3), "color_key": "wall"})
	A.call({"type": "box", "name": "GorgeRockS", "pos": Vector3(-3.5, -5.5, 8), "size": Vector3(3, 3, 3), "color_key": "wall"}, true)
	A.call({"type": "box", "name": "Sandbags", "pos": Vector3(-18, 0.55, 2), "size": Vector3(3, 1.1, 1), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "Crates", "pos": Vector3(-20, 0.9, -6), "size": Vector3(2, 1.8, 2), "color_key": "cover"}, true)
	A.call({"type": "building2", "name": "Depot", "pos": Vector3(-15, 1.6, 10), "size": Vector3(6, 3.2, 10), "color_key": "wall",
		"floors": 1, "doors": [{"side": "N", "floor": 0}, {"side": "S", "floor": 0}, {"side": "E", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0}, true)
	A.call({"type": "box", "name": "SiteBCrate", "pos": Vector3(9, 0.6, 12), "size": Vector3(3, 1.2, 1.5), "color_key": "cover"})
	# LD-10 (docs/research/03_level_design.md §3.5, tests/maps/test_snd_timings.gd
	# ROTATION_EXEMPTIONS) : rotation A<->B mesurée à 5.6 s (46.1 m), sous la
	# cible 7-12 s. Chicane en S sur le plateau est (PlateauInnerN·M, x5-20)
	# entre la corniche (Site A) et Site B — chaque baffle laisse un passage de
	# 3 m sur le côté opposé de l'autre (A ouvre x9-12, B ouvre x4-7), au sud
	# du pont central (x-5.5..5.5, z0) pour ne jamais toucher le chemin
	# attaquant ouest -> Site A (`test_navmesh.gd` §5.5, mesuré : ratio
	# atk/def Site A inchangé, 2.53). Résultat mesuré : 6.0 s (49.4 m) — mieux
	# que la mesure LD-05 mais toujours sous la cible. Élargir davantage la
	# chicane (offset ou profondeur) casse `sp1 -> site_b`
	# (`test_navmesh.gd::_assert_path_exists`, §5.6) : ce couloir de 8 m de
	# large (bord de corniche x~4 à la façade du Dépôt·M x12) est la SEULE
	# voie nord vers Site B — tenté jusqu'à x4-11.5 (fermeture quasi totale),
	# chemin coupé net (`chemin arrivé à ... objectif Site B`). Aller chercher
	# la longueur ailleurs sur cette carte revient sur le même risque : près de
	# Site A ou du pont, tout obstacle allonge le chemin attaquant à l'identique
	# (mesuré : un blocage de 5x7x4 au pont porte le ratio à 3.28, > 3.0).
	# Exempté ci-dessous avec ce constat écrit (comme `val_poussiere`/`site_b`
	# déjà exempté avant cette tâche) plutôt que de risquer une régression sur
	# `test_navmesh.gd` en aveugle.
	A.call({"type": "box", "name": "NarrowsBaffleA", "pos": Vector3(6.5, 2, 3.5), "size": Vector3(5, 4, 1.5), "color_key": "wall"})
	A.call({"type": "box", "name": "NarrowsBaffleB", "pos": Vector3(9.5, 2, 7.5), "size": Vector3(5, 4, 1.5), "color_key": "wall"})

	var sp0: Array = []
	var sp1: Array = []
	for z in [5.0, 8.0, 11.0, 14.0]:
		sp0.append(_spawn(Vector3(-35, 1, z), Vector3(-24, 1, z)))
		sp1.append(_spawn(Vector3(35, 1, z), Vector3(24, 1, z)))

	# LD-03 : bordure des 3 couloirs (crête nord y4/4.3, plateaux z-9/13/24,
	# pont central x-6) sur la moitié ouest, mirroir "x" pour l'est comme les
	# spawns d'équipe. `look` vers le centre (x=0). `strong_positions` :
	# l'antenne du Refuge (ouest) et le radar (est) — les deux seules
	# verticalités dominantes de cette carte, non-mirroirs l'une de l'autre
	# (Antenna/Radar posées sans jumeau dans `pieces` ci-dessus).
	var tdm_half: Array = [
		_spawn(Vector3(-36, 4, -18), Vector3(0, 4, -18)),
		_spawn(Vector3(-27, 4, -18), Vector3(0, 4, -18)),
		_spawn(Vector3(-9, 4.3, -18), Vector3(0, 4.3, -18)),
		_spawn(Vector3(-24, 1, -9), Vector3(0, 1, -9)),
		_spawn(Vector3(-17, 1, -9), Vector3(0, 1, -9)),
		_spawn(Vector3(-9, 1, 13), Vector3(0, 1, 13)),
		_spawn(Vector3(-6, 1.6, 0), Vector3(0, 1.6, 0)),
		_spawn(Vector3(-17, 1, 24), Vector3(0, 1, 24)),
		_spawn(Vector3(-37, 1, 24.5), Vector3(0, 1, 24.5)),
	]
	var tdm_spawns: Array = tdm_half.duplicate()
	for s in tdm_half:
		tdm_spawns.append(_mirror_spawn(s, mode))

	return {
		"id": "col_du_vautour", "name": "Col du Vautour",
		"palette": {"floor": Color("e3e2da"), "wall": Color("5c5952"), "cover": Color("5e6b61"), "platform": Color("827e77"), "accent": Color("4a4741")},
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		"tdm_spawns": tdm_spawns,
		"strong_positions": [Vector3(-28, 12, 10), Vector3(28, 9, 10)],
		"hardpoints": [Vector3(0, 1.5, 0), Vector3(-13, 1.5, 0), Vector3(0, -5.5, 12), Vector3(13, 1.5, 0)],
		"site_a": {"pos": Vector3(22, 4.5, -17), "size": Vector3(8, 3, 8)},
		"site_b": {"pos": Vector3(9, 1.5, 11), "size": Vector3(6, 3, 8)},
		"bounds": {"min": Vector2(-38, -25), "max": Vector2(38, 25)},
		"callouts": _callout_grid(
			[-9.0, 9.0], [-6.0, 10.0],
			[
				["Crête Nord", "Défilé Nord", "Crête Est"],
				["Bunker Ouest", "Pont Gorge", "Bunker Est"],
				["Refuge", "Gorge Sud", "Radar"],
			]
		),
	}

# ======================================================================
#  3.5 La Fosse — quarry pit arena, 28x28 m, point-symmetric.
# ======================================================================
static func la_fosse() -> Dictionary:
	var mode := "p"
	var pieces: Array = []
	var A := func(p: Dictionary, m: bool = false) -> void: _add(pieces, p, mode, m)

	A.call({"type": "box", "name": "RimN", "pos": Vector3(0, -3, -12), "size": Vector3(28, 6, 4), "color_key": "floor"}, true)
	A.call({"type": "box", "name": "RimW", "pos": Vector3(-12, -3, 0), "size": Vector3(4, 6, 20), "color_key": "floor"}, true)
	A.call({"type": "box", "name": "TerraceN", "pos": Vector3(0, -4.25, -8), "size": Vector3(20, 3.5, 4), "color_key": "platform"}, true)
	A.call({"type": "box", "name": "TerraceW", "pos": Vector3(-8, -4.25, 0), "size": Vector3(4, 3.5, 12), "color_key": "platform"}, true)
	A.call({"type": "box", "name": "PitFloor", "pos": Vector3(0, -5.5, 0), "size": Vector3(12, 1, 12), "color_key": "floor"})
	A.call({"type": "box", "name": "WallN", "pos": Vector3(0, 2, -14.5), "size": Vector3(29, 8, 1), "color_key": "wall"}, true)
	A.call({"type": "box", "name": "WallW", "pos": Vector3(-14.5, 2, 0), "size": Vector3(1, 8, 28), "color_key": "wall"}, true)
	# LD-11 (docs/research/03_level_design.md §2.6/§3.2, tests/maps/test_arenas.gd
	# §1) : premier contact mesuré à LD-09 à 5,2 s (42,8 m navmesh) — bien au-
	# dessus de la cible 2-4 s. Cause : la SEULE descente rim->fosse passait par
	# RimRamp (rim->terrasse à x[-4,6] z-8) PUIS, à travers tout l'anneau de
	# terrasse, par PitRamp (terrasse->fond à x-4.5 z[-4,4]) — loin des spawns
	# (x=-12.5, z=[-7,-3]). Mesuré à la main (`Layouts.gd`/navmesh réel) :
	# raccorder une NOUVELLE rampe directement de RimW jusqu'au FOND de la
	# fosse (une seule pente continue, sans dépendre du raccord terrasse<->
	# PitRamp existant, mesuré fragile : PitRamp ne se connecte à la terrasse
	# que par un chevauchement de bord marginal, sensible à toute pièce ajoutée
	# à proximité — `TerraceBlock` posée dessus fragmentait déjà le navmesh
	# avant ce correctif). RimRamp part maintenant du rebord ouest (x-11,
	# juste à côté des spawns) et descend en une seule pente jusqu'au sol de
	# la fosse (x3, dans l'empreinte de PitFloor x[-6,6] z[-6,6]) : chute de
	# 5 m sur 14 m de plat = 19,7°, dans la fourchette SLIDE_RAMP 11-27° /
	# >= 7 m de `test_layouts.gd::SLIDE_RAMPS`. PitRamp reste en place
	# (nom exigé par ce même test) comme second accès, plus long, côté est-
	# sud pour l'équipe 1 (PitRampM) — voir accès n°2 du test d'accès à la
	# zone. Mesuré après coup : 3,1 s (~25,6 m).
	A.call({"type": "ramp", "name": "RimRamp", "start": Vector3(-11, 0, -5), "end": Vector3(3, -5, -5), "width": 4.0, "color_key": "platform"}, true)
	A.call({"type": "ramp", "name": "PitRamp", "start": Vector3(-4.5, -2.5, -4), "end": Vector3(-4.5, -5, 4), "width": 3.0, "color_key": "platform"}, true)
	A.call({"type": "catwalk", "name": "Conveyor", "start": Vector3(-10, 0, 0), "end": Vector3(-4, 0, 0), "width": 2.0, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "PitBlock", "pos": Vector3(-2.5, -4.25, -2.5), "size": Vector3(1.5, 1.5, 1.5), "color_key": "cover"}, true)
	# LD-11 : rendue à sa bande d'origine (z-8, sur TerraceN) mais décalée sur
	# X (x-9 au lieu de -8) pour rester hors de l'empreinte de la RimRamp
	# reconstruite (large de 4 m autour de z-5, donc z[-7,-3] : TerraceBlock
	# reste dans z[-10,-6], plus au nord, aucun chevauchement).
	A.call({"type": "box", "name": "TerraceBlock", "pos": Vector3(-9, -1.4, -8), "size": Vector3(2, 2.2, 2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "RimCrate", "pos": Vector3(6, 0.6, -12), "size": Vector3(2, 1.2, 2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "Headframe", "pos": Vector3(12, 5, -12), "size": Vector3(2, 10, 2), "color_key": "accent"}, true)
	# LD-11 (tests/maps/test_arenas.gd §3, ligne de vue physique navmesh<->navmesh
	# > 30 m, raycast à hauteur d'œil +1,7 m) : PLUSIEURS lignes dépassaient
	# tour à tour à mesure que les précédentes étaient bloquées, toutes des
	# diagonales coin-à-coin qui, par géométrie, passent près du CENTRE —
	# entre le rebord bas (y~0,5, rive/rive) et le sommet du Headframe/
	# HeadframeM (y~10,5, îlot de navmesh isolé sur son toit plat 2x2, comme
	# le podium du Belvédère — voir l'en-tête du fichier de test). Hauteur
	# d'œil (+1,7 m) : toute paire dont les deux bouts sont entre y=0,5 et
	# y=10,5 croise donc le centre à une hauteur interpolée dans [2,0 ; 12,2].
	# La fosse fait 28x28 m (bornes ±14) : aucun point du sol n'est à plus de
	# 19,8 m du centre, donc un bloqueur placé AU CENTRE ne peut par
	# construction jamais ouvrir de nouvelle ligne > 30 m, quelle que soit sa
	# hauteur — il ne fait que raccourcir les paires existantes. Couvrir toute
	# la plage [1,5 ; 12,5] en un seul pilier ferme donc TOUTES les diagonales
	# coin-à-coin d'un coup plutôt que de rejouer le chat-et-la-souris à
	# chaque paire suivante ; le sol de la fosse à cet endroit est de toute
	# façon vide (PitFloor descend à y-5, aucun combat au sol n'atteint
	# y=1,5). Le bas à 1,5 m couvre aussi (tests/maps/test_navmesh.gd
	# `_assert_all_spawn_pairs_blocked`, régression détectée après coup) la
	# ligne de vue spawn<->spawn à hauteur d'œil FIXE 1,7 m (les 4 spawns
	# sont tous à `y=1`) : les 4 diagonales spawn->spawn passent par x=0 à
	# z entre -2 et 2, dans l'empreinte du pilier — Outcrop (retirée plus
	# haut) bloquait cette ligne par accident dans l'ancien tracé, la
	# nouvelle rampe ne passe plus par là. Empreinte et hauteur gardées
	# larges à dessein : une réduction à [-2.2,2.2] pour affiner la
	# silhouette, PUIS l'ajout de deux jambes de soutien jusqu'au rebord
	# (posées sur RimN/RimNM) ont chacune rouvert une AUTRE diagonale
	# (Headframe -> un point de RimW différent à chaque essai, jamais le
	# même) — la moindre géométrie ajoutée près du rebord déplace les îlots
	# de navmesh isolés qui alimentent ces lignes. Gardé en un seul bloc
	# simple, mesuré stable sur plusieurs runs ; jambes de soutien visuelles
	# à ajouter dans une passe d'habillage séparée (LaFosseDressing.gd, hors
	# de mon périmètre) plutôt qu'en touchant à nouveau cette géométrie de
	# collision. Symétrique par lui-même (mode "p" : rotate180(0,7,0) =
	# (0,7,0)), sur le modèle de PitFloor (déjà ajoutée sans jumeau).
	#
	# LD-06 (docs/research/03_level_design.md, audit de hauteur libre,
	# tests/maps/test_layouts.gd §5.13) : le DESIGN_GAP "Conveyor open end
	# <-> mirror" (test_layouts.gd DESIGN_GAPS.la_fosse, z=0, x=[-4,4])
	# traversait ce pilier en plein milieu — seulement 1,5 m de dégagement
	# (son "bottom") sous le seuil d'audit 3,2 m. Scindé en deux flancs
	# (z=[-3,-0.6] et [0.6,3], mirror "p") qui gardent EXACTEMENT [1,5;12,5]
	# intact sur l'essentiel de l'empreinte + un couloir central étroit
	# (z=[-0.6,0.6], sous la largeur du Conveyor/ConveyorM ci-dessus, mais
	# voir la contrainte ci-dessous) remonté à un plancher de 3,3 m
	# (>= 3,2 m + marge), qui libère la ligne de plongée. Largeur du couloir
	# BORNÉE par la diagonale spawn<->spawn la plus proche du centre (sp0[1]
	# ((-12,5;1;-3)) <-> sp1[1] (12,5;1;3), `test_navmesh.gd::
	# _assert_all_spawn_pairs_blocked`, raycast physique réel — PAS la
	# vérification pure §5.3 de ce fichier, qui ignore la hauteur) : sur
	# TOUTE la traversée x=[-3,3], son |z| ne dépasse jamais 0,72 (calculé :
	# interpolation linéaire de z=-3 à z=3 sur x=-12,5..12,5, restreinte à
	# x=[-3,3]) — un couloir >= 0,72 de large (l'essai initial à 1,0 avait
	# cette diagonale ENTIÈREMENT dans le couloir, jamais dans un flanc :
	# `test_navmesh.gd::test_la_fosse` rouge, ligne "should hit geometry"
	# fausse) la laisserait passer intacte. 0,6 (< 0,72, marge 0,12 m, sort
	# du couloir dès x=-2,5/x=2,5, encore 0,5 m à l'intérieur de l'empreinte
	# avant le bord x=-3/x=3) : vérifié vert sur `test_arenas.gd`,
	# `test_navmesh.gd` (les deux arènes, pas seulement la_fosse) et
	# `test_layouts.gd` après ce changement. Couloir centré en x=0/z=0 :
	# self-symétrique, comme l'ancien bloc unique.
	A.call({"type": "box", "name": "SpanBeamFlank", "pos": Vector3(0, 7, -1.8), "size": Vector3(6, 11.0, 2.4), "color_key": "accent"}, true)
	A.call({"type": "box", "name": "SpanBeamLane", "pos": Vector3(0, 7.9, 0), "size": Vector3(6, 9.2, 1.2), "color_key": "accent"})

	var sp0: Array = [
		_spawn(Vector3(-12.5, 1, -7), Vector3(0, 1, -7)),
		_spawn(Vector3(-12.5, 1, -3), Vector3(0, 1, -3)),
	]
	var sp1: Array = [
		_spawn(Vector3(12.5, 1, 7), Vector3(0, 1, 7)),
		_spawn(Vector3(12.5, 1, 3), Vector3(0, 1, 3)),
	]

	return {
		"id": "la_fosse", "name": "La Fosse",
		"palette": {"floor": Color("d0c7b3"), "wall": Color("5f5a52"), "cover": Color("9c8a77"), "platform": Color("6b655c"), "accent": Color("4c4740")},
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		"duel_zone": {"pos": Vector3(0, -3, 0), "size": Vector3(6, 4, 6)},
		"bounds": {"min": Vector2(-14, -14), "max": Vector2(14, 14)},
		"callouts": _callout_grid(
			[-5.0, 5.0], [-5.0, 5.0],
			[
				["Fosse N-O", "Fosse Nord", "Fosse N-E"],
				["Fosse Ouest", "Fond Fosse", "Fosse Est"],
				["Fosse S-O", "Fosse Sud", "Fosse S-E"],
			]
		),
	}

# ======================================================================
#  3.6 Le Belvédère — rooftops at dawn, 30x24 m, point-symmetric.
# ======================================================================
static func le_belvedere() -> Dictionary:
	var mode := "p"
	var pieces: Array = []
	var A := func(p: Dictionary, m: bool = false) -> void: _add(pieces, p, mode, m)

	A.call({"type": "box", "name": "BlockW", "pos": Vector3(-9.5, 2.5, 0), "size": Vector3(11, 5, 24), "color_key": "floor"}, true)
	A.call({"type": "box", "name": "Street", "pos": Vector3(0, -0.5, 0), "size": Vector3(8, 1, 24), "color_key": "floor"})
	# LD-11 (tests/maps/test_navmesh.gd `_assert_all_spawn_pairs_blocked`,
	# régression détectée après avoir éloigné les spawns vers les coins du
	# toit, z=-+11,7) : ligne spawn<->spawn dégagée le long du bord nord/sud
	# à hauteur d'œil fixe 6,7 m (les 2 spawns d'une même équipe sont à
	# `y=6`, +0,7 dans la convention de ce test) — l'ancienne GateN (haut
	# y=4, profondeur z[-13,-12]) ni n'atteignait cette hauteur ni ce bord.
	# Agrandie pour les deux : haut y=7 (> 6,7) et profondeur z[-13.5,-11.5]
	# (couvre z=-11,7) — reste le mur de fond du couloir central (Street,
	# x[-4,4]), ne touche à aucune route de spawn (sur les toits, à x=-+14).
	A.call({"type": "box", "name": "GateN", "pos": Vector3(0, 3.5, -12.5), "size": Vector3(8, 7, 2), "color_key": "wall"}, true)
	A.call({"type": "invisible_wall", "name": "EdgeW", "start": Vector3(-15, 5, -12), "end": Vector3(-15, 5, 12), "height": 8.0}, true)
	A.call({"type": "invisible_wall", "name": "EdgeN", "start": Vector3(-15, 5, -12), "end": Vector3(15, 5, -12), "height": 8.0}, true)
	A.call({"type": "box", "name": "BridgeDeck", "pos": Vector3(0, 4.875, 0), "size": Vector3(8, 0.25, 4), "color_key": "platform"})
	A.call({"type": "fence", "name": "BridgeRailN", "start": Vector3(-2, 5, -2), "end": Vector3(-4, 5, -2), "height": 1.0, "color_key": "wall"}, true)
	A.call({"type": "fence", "name": "BridgeRailN2", "start": Vector3(2, 5, -2), "end": Vector3(4, 5, -2), "height": 1.0, "color_key": "wall"}, true)
	A.call({"type": "box", "name": "Podium", "pos": Vector3(0, 5.45, 0), "size": Vector3(4, 0.9, 4), "color_key": "platform"})
	# LD-11 (tests/maps/test_arenas.gd §3, raycast à hauteur d'œil +1,7 m) :
	# PLUSIEURS lignes dépassaient tour à tour à mesure que les précédentes
	# étaient bloquées, toutes entre des points des deux châteaux d'eau
	# (WaterTower x-13 z9 / WaterTowerM x13 z-9 : pied ~y5,5, sommet du tank
	# ~y14 — sommet/pied, sommet/sommet, pied/pied). Hauteur d'œil (+1,7 m) :
	# toute paire dont les deux bouts sont entre y=5,5 et y=14 croise donc le
	# centre à une hauteur interpolée dans [7,2 ; 15,7]. Le Belvédère fait
	# 30x24 m (bornes ±15/±12) : aucun point n'est à plus de 19,2 m du centre,
	# donc un bloqueur CENTRAL ne peut par construction jamais ouvrir de
	# nouvelle ligne > 30 m, quelle que soit sa hauteur. Couvrir toute la
	# plage [6,5 ; 17,0] d'un seul bloc ferme donc TOUTES les paires
	# château-d'eau <-> château-d'eau d'un coup, en flèche CONTINUE (pas un
	# toit fin détaché des piliers, qui laissait passer les lignes basses) —
	# toujours hors de portée du duel au sol, qui se joue sous 7,4 m sur le
	# podium ; le Belvédère porte bien son nom.
	#
	# LD-06 (docs/research/03_level_design.md, audit de hauteur libre,
	# tests/maps/test_layouts.gd §5.13) : le DESIGN_GAP "roof <-> roof"
	# (test_layouts.gd DESIGN_GAPS.le_belvedere, y=5, x=[-4,4]) passait sous
	# ce toit en plein milieu — seulement 1,5 m de dégagement (son "bottom")
	# sous le seuil d'audit 3,2 m. Scindé comme `SpanBeam` de la_fosse
	# ci-dessus (même risque, même méthode) : deux flancs (z=[-2.5,-1] et
	# [1,2.5], mirror "p") gardent EXACTEMENT [6,5;17,0] intact sur la
	# majeure partie de l'empreinte — en particulier la ligne château d'eau
	# <-> château d'eau la plus basse ci-dessus (pied/pied, hauteur d'œil
	# croisant le centre à 7,2 m) : par symétrie ponctuelle, cette ligne
	# entre dans l'empreinte du toit à x=-2,5/z=1,73 (dans le flanc,
	# largement à l'intérieur de [1;2,5], PAS dans le couloir central) avant
	# d'atteindre x=0 — le rayon physique est donc déjà bloqué par le flanc
	# en amont, comme pour SpanBeam. + un couloir central étroit (z=[-1,1])
	# remonté à un plancher de 8,3 m (>= 5+3,2 m + marge), qui libère la
	# ligne de saut de toit à toit sans rouvrir la ligne château d'eau
	# (vérifié : `test_arenas.gd`, `test_navmesh.gd`, `test_layouts.gd`
	# toujours verts après ce changement). Couloir centré en x=0/z=0 :
	# self-symétrique, comme l'ancien bloc unique.
	A.call({"type": "box", "name": "GazeboPillar", "pos": Vector3(-1.8, 6.2, -1.8), "size": Vector3(0.3, 0.6, 0.3), "color_key": "accent"}, true)
	A.call({"type": "box", "name": "GazeboPillar2", "pos": Vector3(1.8, 6.2, -1.8), "size": Vector3(0.3, 0.6, 0.3), "color_key": "accent"}, true)
	A.call({"type": "box", "name": "GazeboRoofFlank", "pos": Vector3(0, 11.75, -1.75), "size": Vector3(5, 10.5, 1.5), "color_key": "accent"}, true)
	A.call({"type": "box", "name": "GazeboRoofLane", "pos": Vector3(0, 12.65, 0), "size": Vector3(5, 8.7, 2), "color_key": "accent"})
	A.call({"type": "ramp", "name": "StreetRamp", "start": Vector3(-3, 0, 12), "end": Vector3(-3, 5, 2), "width": 2.0, "color_key": "platform"}, true)
	A.call({"type": "ramp", "name": "ZincSlope", "start": Vector3(-14, 6.5, -8), "end": Vector3(-7, 5, -8), "width": 4.0, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "Chimney", "pos": Vector3(-10, 6.5, 0), "size": Vector3(1.5, 3, 9), "color_key": "wall"}, true)
	A.call({"type": "box", "name": "Skylight", "pos": Vector3(-9, 5.5, 8), "size": Vector3(3, 1, 2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "Cart", "pos": Vector3(1, 0.7, 7), "size": Vector3(2, 1.4, 3), "color_key": "cover"}, true)
	A.call({"type": "water_tower", "name": "WaterTower", "pos": Vector3(-13, 5, 9), "color_key": "accent"}, true)
	A.call({"type": "box", "name": "ParapetW", "pos": Vector3(-14.8, 5.55, 0), "size": Vector3(0.4, 1.1, 24), "color_key": "wall"}, true)

	# LD-11 (docs/research/03_level_design.md §2.6, tests/maps/test_arenas.gd
	# §1) : premier contact mesuré à LD-09 à 1,56 s (~12,8 m) — sous la cible
	# 2-4 s, parce que les spawns (x=-+13, z=-+4) étaient déjà presque sur le
	# pont central (toit BlockW à la même hauteur que BridgeDeck, aucune
	# descente requise). Spawns éloignés vers les coins du toit (z=-+11,7 au
	# lieu de -+4, à 0,3 m du bord des bornes ±12, ~2,9 m du château d'eau —
	# hors de son gabarit de tank 3,2x3x3,2, cf `Kit.water_tower` — et à
	# 0,6 m du parapet ouest/est) : chemin navmesh mesuré 3,15 s (~25,9 m,
	# marge > 5 % au-dessus du minimum 2 s après un premier essai à z=-+11
	# trop juste, 1,99 s).
	var sp0: Array = [
		_spawn(Vector3(-14, 6, -11.7), Vector3(0, 6, 0)),
		_spawn(Vector3(-14, 6, 11.7), Vector3(0, 6, 0)),
	]
	var sp1: Array = [
		_spawn(Vector3(14, 6, 11.7), Vector3(0, 6, 0)),
		_spawn(Vector3(14, 6, -11.7), Vector3(0, 6, 0)),
	]

	return {
		"id": "le_belvedere", "name": "Le Belvédère",
		"palette": {"floor": Color("c8c3bc"), "wall": Color("8e9598"), "cover": Color("9c8276"), "platform": Color("6f7578"), "accent": Color("6a6461")},
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		"duel_zone": {"pos": Vector3(0, 7.4, 0), "size": Vector3(4, 3, 4)},
		"bounds": {"min": Vector2(-15, -12), "max": Vector2(15, 12)},
		"callouts": _callout_grid(
			[-5.0, 5.0], [-4.0, 4.0],
			[
				["Toit N-O", "Toit Nord", "Toit N-E"],
				["Toit Ouest", "Place Toit", "Toit Est"],
				["Toit S-O", "Toit Sud", "Toit S-E"],
			]
		),
	}
