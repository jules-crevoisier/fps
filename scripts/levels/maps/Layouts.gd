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

	var sp0: Array = [
		_spawn(Vector3(-32, 1, -4.5), Vector3(-24, 1, -14)),
		_spawn(Vector3(-32, 1, -1.5), Vector3(-24, 1, -14)),
		_spawn(Vector3(-32, 1, 1.5), Vector3(-22, 1, 12)),
		_spawn(Vector3(-32, 1, 4.5), Vector3(-22, 1, 12)),
	]
	var sp1: Array = []
	for s in sp0:
		sp1.append(_mirror_spawn(s, mode))

	return {
		"id": "port_ferraille", "name": "Port-Ferraille",
		"palette": {"floor": Color("c9c6b8"), "wall": Color("4f5c55"), "cover": Color("8a7466"), "platform": Color("6f7f76"), "accent": Color("3e4843")},
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		"hardpoints": [Vector3(0, 1.5, -0.5), Vector3(-12, -1.2, 14), Vector3(0, 7.5, -11), Vector3(12, -1.2, 14)],
		"site_a": {"pos": Vector3(14, 1.5, -17), "size": Vector3(8, 3, 8)},
		"site_b": {"pos": Vector3(12, -1, 14), "size": Vector3(8, 3, 8)},
		"bounds": {"min": Vector2(-36, -22), "max": Vector2(36, 18)},
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

	var sp0: Array = []
	var sp1: Array = []
	for z in [-6.0, -2.0, 2.0, 6.0]:
		sp0.append(_spawn(Vector3(-37, 1, z), Vector3(-28, 1, z)))
		sp1.append(_spawn(Vector3(37, 1, z), Vector3(28, 1, z)))

	return {
		"id": "val_poussiere", "name": "Val-Poussière",
		"palette": {"floor": Color("bdaf8e"), "wall": Color("5e4d3c"), "cover": Color("8e9479"), "platform": Color("9a8472"), "accent": Color("6b5a48")},
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		"hardpoints": [Vector3(0, 1.5, 0), Vector3(-8.5, 1.5, -11), Vector3(0, -1.5, 20), Vector3(8.5, 1.5, -11)],
		"site_a": {"pos": Vector3(19, 1.5, 11), "size": Vector3(6, 3, 6)},
		"site_b": {"pos": Vector3(16, -1, 20), "size": Vector3(8, 3, 6)},
		"bounds": {"min": Vector2(-40, -24), "max": Vector2(40, 24)},
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

	return {
		"id": "saint_ombre", "name": "Saint-Ombre",
		"palette": {"floor": Color("4a4f55"), "wall": Color("6b737a"), "cover": Color("74877f"), "platform": Color("56606a"), "accent": Color("2f3439")},
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		"hardpoints": [Vector3(-3, 1.5, 0), Vector3(26, 1.5, -12), Vector3(-7, -2, 0), Vector3(26, 1.5, 12)],
		"site_a": {"pos": Vector3(26, 1.5, 12), "size": Vector3(8, 3, 8)},
		"site_b": {"pos": Vector3(-21, 1.5, 17), "size": Vector3(10, 3, 6)},
		"bounds": {"min": Vector2(-32, -26), "max": Vector2(32, 26)},
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

	var sp0: Array = []
	var sp1: Array = []
	for z in [5.0, 8.0, 11.0, 14.0]:
		sp0.append(_spawn(Vector3(-35, 1, z), Vector3(-24, 1, z)))
		sp1.append(_spawn(Vector3(35, 1, z), Vector3(24, 1, z)))

	return {
		"id": "col_du_vautour", "name": "Col du Vautour",
		"palette": {"floor": Color("e3e2da"), "wall": Color("5c5952"), "cover": Color("5e6b61"), "platform": Color("827e77"), "accent": Color("4a4741")},
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		"hardpoints": [Vector3(0, 1.5, 0), Vector3(-13, 1.5, 0), Vector3(0, -5.5, 12), Vector3(13, 1.5, 0)],
		"site_a": {"pos": Vector3(22, 4.5, -17), "size": Vector3(8, 3, 8)},
		"site_b": {"pos": Vector3(9, 1.5, 11), "size": Vector3(6, 3, 8)},
		"bounds": {"min": Vector2(-38, -25), "max": Vector2(38, 25)},
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
	A.call({"type": "ramp", "name": "RimRamp", "start": Vector3(-4, 0, -8), "end": Vector3(6, -2.5, -8), "width": 4.0, "color_key": "platform"}, true)
	A.call({"type": "ramp", "name": "PitRamp", "start": Vector3(-4.5, -2.5, -4), "end": Vector3(-4.5, -5, 4), "width": 3.0, "color_key": "platform"}, true)
	A.call({"type": "catwalk", "name": "Conveyor", "start": Vector3(-10, 0, 0), "end": Vector3(-4, 0, 0), "width": 2.0, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "Outcrop", "pos": Vector3(-10.5, 1.5, -5), "size": Vector3(1, 3, 8), "color_key": "wall"}, true)
	A.call({"type": "box", "name": "PitBlock", "pos": Vector3(-2.5, -4.25, -2.5), "size": Vector3(1.5, 1.5, 1.5), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "TerraceBlock", "pos": Vector3(-8, -1.4, -8), "size": Vector3(2, 2.2, 2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "RimCrate", "pos": Vector3(6, 0.6, -12), "size": Vector3(2, 1.2, 2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "Headframe", "pos": Vector3(12, 5, -12), "size": Vector3(2, 10, 2), "color_key": "accent"}, true)

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
	A.call({"type": "box", "name": "GateN", "pos": Vector3(0, 2, -12.5), "size": Vector3(8, 4, 1), "color_key": "wall"}, true)
	A.call({"type": "invisible_wall", "name": "EdgeW", "start": Vector3(-15, 5, -12), "end": Vector3(-15, 5, 12), "height": 8.0}, true)
	A.call({"type": "invisible_wall", "name": "EdgeN", "start": Vector3(-15, 5, -12), "end": Vector3(15, 5, -12), "height": 8.0}, true)
	A.call({"type": "box", "name": "BridgeDeck", "pos": Vector3(0, 4.875, 0), "size": Vector3(8, 0.25, 4), "color_key": "platform"})
	A.call({"type": "fence", "name": "BridgeRailN", "start": Vector3(-2, 5, -2), "end": Vector3(-4, 5, -2), "height": 1.0, "color_key": "wall"}, true)
	A.call({"type": "fence", "name": "BridgeRailN2", "start": Vector3(2, 5, -2), "end": Vector3(4, 5, -2), "height": 1.0, "color_key": "wall"}, true)
	A.call({"type": "box", "name": "Podium", "pos": Vector3(0, 5.45, 0), "size": Vector3(4, 0.9, 4), "color_key": "platform"})
	A.call({"type": "box", "name": "GazeboPillar", "pos": Vector3(-1.8, 7.1, -1.8), "size": Vector3(0.3, 2.4, 0.3), "color_key": "accent"}, true)
	A.call({"type": "box", "name": "GazeboPillar2", "pos": Vector3(1.8, 7.1, -1.8), "size": Vector3(0.3, 2.4, 0.3), "color_key": "accent"}, true)
	A.call({"type": "box", "name": "GazeboRoof", "pos": Vector3(0, 8.45, 0), "size": Vector3(5, 0.3, 5), "color_key": "accent"})
	A.call({"type": "ramp", "name": "StreetRamp", "start": Vector3(-3, 0, 12), "end": Vector3(-3, 5, 2), "width": 2.0, "color_key": "platform"}, true)
	A.call({"type": "ramp", "name": "ZincSlope", "start": Vector3(-14, 6.5, -8), "end": Vector3(-7, 5, -8), "width": 4.0, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "Chimney", "pos": Vector3(-10, 6.5, 0), "size": Vector3(1.5, 3, 9), "color_key": "wall"}, true)
	A.call({"type": "box", "name": "Skylight", "pos": Vector3(-9, 5.5, 8), "size": Vector3(3, 1, 2), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "Cart", "pos": Vector3(1, 0.7, 7), "size": Vector3(2, 1.4, 3), "color_key": "cover"}, true)
	A.call({"type": "water_tower", "name": "WaterTower", "pos": Vector3(-13, 5, 9), "color_key": "accent"}, true)
	A.call({"type": "box", "name": "ParapetW", "pos": Vector3(-14.8, 5.55, 0), "size": Vector3(0.4, 1.1, 24), "color_key": "wall"}, true)

	var sp0: Array = [
		_spawn(Vector3(-13, 6, -4), Vector3(0, 6, 0)),
		_spawn(Vector3(-13, 6, 4), Vector3(0, 6, 0)),
	]
	var sp1: Array = [
		_spawn(Vector3(13, 6, 4), Vector3(0, 6, 0)),
		_spawn(Vector3(13, 6, -4), Vector3(0, 6, 0)),
	]

	return {
		"id": "le_belvedere", "name": "Le Belvédère",
		"palette": {"floor": Color("c8c3bc"), "wall": Color("8e9598"), "cover": Color("9c8276"), "platform": Color("6f7578"), "accent": Color("6a6461")},
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		"duel_zone": {"pos": Vector3(0, 7.4, 0), "size": Vector3(4, 3, 4)},
		"bounds": {"min": Vector2(-15, -12), "max": Vector2(15, 12)},
	}
