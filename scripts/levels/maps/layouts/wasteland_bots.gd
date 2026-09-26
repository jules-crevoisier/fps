## wasteland_bots.gd
## Wasteland v7 — greybox pur (2026-09-26, « fais la carte block que je
## puisse la tester in game »). RÉÉCRIT ENTIÈREMENT : données bots PURES
## (Dictionary/Vector3, aucun nœud), DÉRIVÉES de la SOURCE UNIQUE
## `data/maps/wasteland_plan.json` (via `WastelandLayout.plan()`, mis en
## cache — jamais une seconde lecture disque indépendante), jamais
## retranscrites à la main. Remplace le contrat v4 (LD-42, encore visible
## dans l'historique, lanes "grand_rue"/"interieurs"/"canyon" calées sur la
## géométrie miroir qui n'existe plus).
##
## Contrat LOAD-BEARING (hors de mon périmètre de fichiers, NE PAS CASSER) :
## `scripts/modes/TDMMode.gd` (`_LANE_BY_RANK_TEAM0/1`) assigne les bots aux
## lanes par les LETTRES "N"/"C"/"S" (Nord/Centre/Sud), lues via
## `BotMapKnowledge.lane_goals(team, lane)` sur `data()["bot_knowledge"]
## ["corridors"]` — ce fichier doit donc TOUJOURS produire ces 3 clés
## exactement, dans l'ordre ouest -> est pour l'équipe 0 (`BotMapKnowledge
## .lane_goals` inverse lui-même pour l'équipe 1). Table de correspondance
## avec les 3 lanes du plan (`docs/maps/WASTELAND_PLAN.md` "Couloirs") :
## "nord" (1 - Grand-Rue / les Voies) -> "N", "milieu" (2 - Place / le Quai)
## -> "C", "canyon" (3 - Ravin / la Tranchee) -> "S".
##
## Chaque couloir complet ouest -> est est reconstruit à partir de
## `lanes[].route_w` (spawn ouest -> front, déjà dans le bon sens) et
## `lanes[].route_e` (spawn est -> front, RENVERSÉ ici moins son dernier
## point — le "front" partagé, déjà la fin de `route_w`). Les points du plan
## sont 2D (x, z) : la hauteur (y) est recalculée PUREMENT depuis la même
## géométrie (rampes + sols/plateformes du JSON, même principe que
## `tools/maps/check_plan.py::ground_y`) plutôt que supposée — TESTÉE contre
## la vraie navmesh bakée (`NavigationServer3D.map_get_closest_point`,
## tolérance métrique) dans `tests/ai/test_wasteland_bot_data.gd`, même
## discipline que l'ancien fichier (ses `_GROUND_Y`/`_CANYON_Y` étaient déjà
## de simples constantes vérifiées par sonde, jamais une vraie requête de
## navmesh au moment de construire les données — `data()` tourne AVANT que
## `MapSetup` ne construise/bake la `NavigationRegion3D`, voir
## `MapSetup._assemble_wasteland`/`_enter_tree`).
class_name WastelandBots
extends RefCounted

## Nord/Centre/Sud (voir en-tête) <- id de lane du plan JSON.
const _LANE_LETTER := {"nord": "N", "milieu": "C", "canyon": "S"}
const _LANE_LABEL := {"N": "nord", "C": "milieu", "S": "canyon"}

# ======================================================================
#  Hauteur du sol (PURE, sans navmesh) — même lecture que
#  `tools/maps/check_plan.py::ground_y`/`in_ramp` : une rampe l'emporte si le
#  point est dedans, sinon le dessus le plus haut des surfaces "ground"/
#  "platform" qui couvrent (x, z).
# ======================================================================
const _NO_HIT := -9999.0

static func _in_ramp_y(v: Dictionary, x: float, z: float) -> float:
	var from: Array = v["from"]
	var to: Array = v["to"]
	var xa: float = float(from[0])
	var ya: float = float(from[1])
	var za: float = float(from[2])
	var xb: float = float(to[0])
	var yb: float = float(to[1])
	var zb: float = float(to[2])
	var length := Vector2(xb - xa, zb - za).length()
	if length < 0.0001:
		return _NO_HIT
	var ux := (xb - xa) / length
	var uz := (zb - za) / length
	var t := ((x - xa) * ux + (z - za) * uz) / length
	var s := -(x - xa) * uz + (z - za) * ux
	var w: float = float(v.get("w", 2.0))
	if t < -0.02 or t > 1.02 or absf(s) > w * 0.5 + 0.05:
		return _NO_HIT
	return ya + (yb - ya) * clampf(t, 0.0, 1.0)

static func _ground_y(plan_data: Dictionary, x: float, z: float) -> float:
	for entry in (plan_data.get("volumes", []) as Array):
		var v: Dictionary = entry
		if String(v.get("kind", "")) == "ramp":
			var y := _in_ramp_y(v, x, z)
			if y > _NO_HIT + 1.0:
				return y
	var best := -1000.0
	var found := false
	for entry in (plan_data.get("volumes", []) as Array):
		var v: Dictionary = entry
		var k := String(v.get("kind", ""))
		if (k != "ground" and k != "platform") or not v.has("x"):
			continue
		var xr: Array = v["x"]
		var zr: Array = v["z"]
		if x < float(xr[0]) - 0.02 or x > float(xr[1]) + 0.02 or z < float(zr[0]) - 0.02 or z > float(zr[1]) + 0.02:
			continue
		var top: float = float((v["y"] as Array)[1])
		if not found or top > best:
			best = top
			found = true
	return best if found else 0.0

# ======================================================================
#  Couloirs (lanes) N/C/S — voir en-tête pour le contrat de lettres.
# ======================================================================
static func _full_corridor(route_w: Array, route_e: Array) -> Array:
	var out: Array = route_w.duplicate()
	var rev: Array = (route_e as Array).slice(0, route_e.size() - 1)
	rev.reverse()
	out.append_array(rev)
	return out

static func _corridors(plan_data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for entry in (plan_data.get("lanes", []) as Array):
		var ln: Dictionary = entry
		var lid := String(ln.get("id", ""))
		if not _LANE_LETTER.has(lid):
			continue
		var route_w: Array = ln.get("route_w", [])
		var route_e: Array = ln.get("route_e", [])
		if route_w.is_empty() or route_e.is_empty():
			continue
		var pts2d := _full_corridor(route_w, route_e)
		var pts3: Array = []
		for p in pts2d:
			var pp: Array = p
			var x: float = float(pp[0])
			var z: float = float(pp[1])
			pts3.append(Vector3(x, _ground_y(plan_data, x, z), z))
		out[_LANE_LETTER[lid]] = pts3
	return out

# ======================================================================
#  hotspots (repli LD-25 pour toute carte SANS bot_knowledge — Wasteland en
#  déclare un, donc ignoré par `TDMMode._compute_bot_goal`, voir son
#  commentaire "CONSERVÉ tel quel" ; gardé pour la forme/les tests) : le
#  point central de chaque couloir + les positions fortes SURÉLEVÉES du
#  plan (`markers.strong_positions[].elevated`).
# ======================================================================
static func _hotspots(plan_data: Dictionary, corridors: Dictionary) -> Array:
	var out: Array = []
	for letter in ["N", "C", "S"]:
		if not corridors.has(letter):
			continue
		var pts: Array = corridors[letter]
		if pts.size() < 3:
			continue
		var mid: Vector3 = pts[pts.size() / 2]
		out.append({"pos": mid, "lane": _LANE_LABEL[letter], "weight": 0.7, "callout": "Front %s" % _LANE_LABEL[letter]})
	for entry in ((plan_data.get("markers", {}) as Dictionary).get("strong_positions", []) as Array):
		var s: Dictionary = entry
		if not bool(s.get("elevated", false)):
			continue
		var p: Array = s["pos"]
		out.append({
			"pos": Vector3(float(p[0]), float(p[1]), float(p[2])),
			"lane": String(s.get("lane", "milieu")), "weight": 0.85,
			"callout": String(s.get("label", s.get("id", "PP"))),
		})
	return out

# ======================================================================
#  nav_links — raccourcis hors de portée du bake automatique (chute de
#  parapet -> canyon, dénivelé 2 m, sous le seuil d'étourdissement
#  `metrics.player.fall_stun_min`, 6 m). Seuls `ParapetW1`/`ParapetW2`
#  (`docs/maps/WASTELAND_PLAN.md` "Couverts, murets, rochers") bordent le
#  ravin SANS escalier/rampe juste à cet endroit précis (contrairement au
#  reste du pourtour, toujours couvert par une rampe) : aucun équivalent
#  côté est n'est déclaré dans le plan (moitié EST asymétrique, sans
#  parapet à cet endroit), donc aucun n'est inventé ici.
# ======================================================================
static func _nav_links(plan_data: Dictionary) -> Array:
	var by_id: Dictionary = {}
	for entry in (plan_data.get("volumes", []) as Array):
		var v: Dictionary = entry
		by_id[String(v.get("id", ""))] = v
	var out: Array = []
	for pid in ["ParapetW1", "ParapetW2"]:
		if not by_id.has(pid):
			continue
		var v: Dictionary = by_id[pid]
		var from_xz: Array = v["from"]
		var to_xz: Array = v["to"]
		var cx: float = (float(from_xz[0]) + float(to_xz[0])) * 0.5
		var fz: float = float(from_xz[1])
		out.append({
			"from": Vector3(cx, 0.0, fz - 0.4),
			"to": Vector3(cx, -2.0, fz + 1.4),
			"bidirectional": false,
		})
	return out

# ======================================================================
#  danger_spans — segments intérieurs (jamais l'extrémité côté spawn) des
#  couloirs Nord/Centre/Sud, exposés de bout en bout par construction (voir
#  `docs/maps/WASTELAND_DESIGN.md` "Équilibre" : vues internes mesurées
#  24-30 m par `check_plan.py`).
# ======================================================================
static func _danger_spans(corridors: Dictionary) -> Array:
	var out: Array = []
	for letter in ["N", "C", "S"]:
		if not corridors.has(letter):
			continue
		var pts: Array = corridors[letter]
		if pts.size() < 4:
			continue
		out.append({
			"a": pts[1], "b": pts[pts.size() - 2],
			"reason": "couloir %s, segment interieur expose" % _LANE_LABEL[letter],
		})
	return out

# ======================================================================
#  bot_knowledge (BOT-22B, `BotMapKnowledge.gd`) — zones/couloirs/angles/
#  perchoirs/couvertures dérivés des pièces RÉELLES du plan. `hp_holds`
#  VIDE : aucune zone Hardpoint cette tâche (TDM seul, voir wasteland.gd).
# ======================================================================
static func _zones(plan_data: Dictionary) -> Array:
	var out: Array = []
	var margin := 0.5
	for entry in (plan_data.get("volumes", []) as Array):
		var v: Dictionary = entry
		if String(v.get("kind", "")) != "building":
			continue
		var x: Array = v["x"]
		var z: Array = v["z"]
		var y: Array = v["y"]
		out.append({
			"name": String(v["id"]),
			"min": Vector3(float(x[0]) - margin, float(y[0]) - margin, float(z[0]) - margin),
			"max": Vector3(float(x[1]) + margin, float(y[1]) + margin, float(z[1]) + margin),
		})
	return out

static func _door_pos(v: Dictionary, d: Dictionary) -> Vector3:
	var x: Array = v["x"]
	var z: Array = v["z"]
	var y: Array = v["y"]
	var x0: float = float(x[0])
	var x1: float = float(x[1])
	var z0: float = float(z[0])
	var z1: float = float(z[1])
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var off: float = float(d.get("offset", 0.0))
	match String(d.get("side", "N")):
		"N":
			return Vector3(cx + off, float(y[0]) + 0.5, z0)
		"S":
			return Vector3(cx + off, float(y[0]) + 0.5, z1)
		"W":
			return Vector3(x0, float(y[0]) + 0.5, cz + off)
		_:
			return Vector3(x1, float(y[0]) + 0.5, cz + off)

static func _door_dir(side: String) -> Vector3:
	match side:
		"N":
			return Vector3(0, 0, -1)
		"S":
			return Vector3(0, 0, 1)
		"W":
			return Vector3(-1, 0, 0)
		_:
			return Vector3(1, 0, 0)

## Angles à pré-viser — portes RÉELLES de chaque bâtiment, REZ-DE-CHAUSSÉE
## seulement (même discipline que l'ancien contrat v4 : un angle d'étage
## n'a pas la même valeur tactique qu'une porte au sol, sur un couloir de
## patrouille au sol).
static func _angles(plan_data: Dictionary) -> Array:
	var out: Array = []
	for entry in (plan_data.get("volumes", []) as Array):
		var v: Dictionary = entry
		if String(v.get("kind", "")) != "building":
			continue
		for door_entry in (v.get("doors", []) as Array):
			var d: Dictionary = door_entry
			if int(d.get("floor", 0)) != 0:
				continue
			out.append({"pos": _door_pos(v, d), "dir": _door_dir(String(d.get("side", "N")))})
	return out

## Perchoirs — positions fortes SURÉLEVÉES du plan (`PP1..PP7`,
## `markers.strong_positions[].elevated`).
static func _perches(plan_data: Dictionary) -> Array:
	var out: Array = []
	for entry in ((plan_data.get("markers", {}) as Dictionary).get("strong_positions", []) as Array):
		var s: Dictionary = entry
		if not bool(s.get("elevated", false)):
			continue
		var p: Array = s["pos"]
		out.append({
			"name": String(s.get("id", "PP")),
			"pos": Vector3(float(p[0]), float(p[1]), float(p[2])),
			"watch": String(s.get("label", "")),
		})
	return out

## Couvertures — une tenue au flanc SUD de chaque volume "cover" du plan
## (position de bon sens, à côté du couvert réel plutôt que dans son
## solide) ; `height` = hauteur réelle de la pièce (§ écart de greybox
## assumé : toutes les tenues ne visent pas forcément le meilleur flanc
## exact — non consommé par le code de jeu actuel, voir le rendu de tâche).
static func _covers(plan_data: Dictionary) -> Array:
	var out: Array = []
	for entry in (plan_data.get("volumes", []) as Array):
		var v: Dictionary = entry
		if String(v.get("kind", "")) != "cover":
			continue
		var x: Array = v["x"]
		var z: Array = v["z"]
		var y: Array = v["y"]
		var cx: float = (float(x[0]) + float(x[1])) * 0.5
		var stand_z: float = float(z[1]) + 0.6
		out.append({
			"pos": Vector3(cx, 0.5, stand_z),
			"dir": Vector3(0, 0, -1),
			"height": float(y[1]) - float(y[0]),
		})
	return out

static func _bot_knowledge(plan_data: Dictionary, corridors: Dictionary) -> Dictionary:
	return {
		"zones": _zones(plan_data),
		"corridors": corridors,
		"angles": _angles(plan_data),
		"perches": _perches(plan_data),
		"covers": _covers(plan_data),
		"hp_holds": [],
	}

static func data() -> Dictionary:
	var plan_data := WastelandLayout.plan()
	if plan_data.is_empty():
		return {}
	var corridors := _corridors(plan_data)
	return {
		"lanes": corridors,
		"hotspots": _hotspots(plan_data, corridors),
		"hp_hold_points": [],
		"nav_links": _nav_links(plan_data),
		"danger_spans": _danger_spans(corridors),
		"bot_knowledge": _bot_knowledge(plan_data, corridors),
	}
