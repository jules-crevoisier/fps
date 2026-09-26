## wasteland.gd
## Wasteland v7 — greybox pur (2026-09-26, « fais la carte block que je
## puisse la tester in game »). RÉÉCRIT ENTIÈREMENT : `data()` ne pose plus
## AUCUNE géométrie codée en dur — elle CHARGE `data/maps/wasteland_plan.json`
## au runtime (`plan()`, `FileAccess` + `JSON.parse_string`, mis en cache) et
## convertit CHAQUE volume déclaré (`docs/maps/WASTELAND_PLAN.md`/
## `docs/maps/WASTELAND_DESIGN.md` pour le sens, `tools/maps/render_plan.py`/
## `tools/maps/check_plan.py` pour la façon dont chaque clé est interprétée —
## même lecture ici) en pièce `Kit.gd` : le plan coté ET la carte en jeu
## lisent le MÊME fichier, ils ne peuvent plus diverger. Remplace le contrat
## v4 miroir (LD-40..44, encore visible dans l'historique) : `mirror.enabled`
## vaut `false` en v7 (carte ASYMÉTRIQUE, moitiés W/C/E décrites
## explicitement dans le JSON) — aucun miroir n'est recalculé ici.
##
## TDM SEUL cette tâche (décision utilisateur : « teste-la en jeu » sur le
## greybox, priorité au mode par défaut) : `hardpoints`/`hardpoint_sizes`/
## `site_a`/`site_b`/`duel_zone` ne sont PLUS déclarés — `MapSetup
## ._build_markers`/`_build_game_mode` (hors de mon périmètre, inchangés)
## sautent alors proprement la construction de ces zones (mêmes gardes
## `data.has(...)` qu'avant), quel que soit le mode sélectionné. Écart connu
## (signalé dans le rendu de tâche) : `MapCatalog.gd` annonce encore
## Wasteland pour "hardpoint"/"snd" — une tâche ultérieure devra l'aligner
## sur "tdm" seul, hors de mon périmètre de fichiers cette manche.
##
## `WastelandLook.palette()` (réécrit en parallèle, même contrat) fournit une
## teinte PAR RÔLE (`materials.wall/floor/cover/stairs/oob/platform` du JSON)
## et bascule chaque rôle vers `Cartoon.dev_grid()` (grille triplanaire
## monde, `assets/shaders/dev_grid.gdshader`, ADDITIF dans
## `scripts/core/Cartoon.gd`) — aucune texture peinte, aucun module
## `WastelandArt` (`ART_ENABLED := false`, inchangé).
class_name WastelandLayout
extends RefCounted

const PLAN_PATH := "res://data/maps/wasteland_plan.json"

## Cache process-wide (le fichier ne change jamais en cours d'exécution) —
## partagé par `WastelandLook.palette()` ET `WastelandBots.gd` (tous deux
## appellent `plan()`, jamais une seconde lecture disque indépendante).
static var _plan_cache: Dictionary = {}

## Lecture PUBLIQUE du plan coté — source unique consommée par ce fichier,
## par `WastelandLook.palette()` et par `WastelandBots.gd` (lanes/marqueurs
## dérivés de la MÊME géométrie, jamais retranscrite).
static func plan() -> Dictionary:
	if not _plan_cache.is_empty():
		return _plan_cache
	if not FileAccess.file_exists(PLAN_PATH):
		push_error("WastelandLayout: plan introuvable %s" % PLAN_PATH)
		return {}
	var f := FileAccess.open(PLAN_PATH, FileAccess.READ)
	if f == null:
		push_error("WastelandLayout: lecture impossible %s (err=%d)" % [PLAN_PATH, FileAccess.get_open_error()])
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WastelandLayout: JSON invalide dans %s" % PLAN_PATH)
		return {}
	_plan_cache = parsed as Dictionary
	return _plan_cache

# ======================================================================
#  Volumes -> pièces Kit (tools/maps/render_plan.py::color_of / check_plan.py
#  en tête : "Géométrie : volumes via tools/maps/render_plan.py" — même
#  lecture de chaque champ ici).
# ======================================================================
static func _role_for_kind(materials: Dictionary, kind: String) -> String:
	var by_kind: Dictionary = materials.get("by_kind", {})
	return String(by_kind.get(kind, "wall"))

static func _vec3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

## Volumes posés tels quels (boîte AABB x/z/y -> pos/size Kit) : sols,
## dalles, volumes pleins/repères, murets simples, couverts, rochers,
## plateformes surélevées, limites de carte — tous des `type:"box"` Kit,
## seul le rôle (`color_key`, donc la couleur ET le kind de grille) change.
static func _box_piece(v: Dictionary, role: String) -> Dictionary:
	var x: Array = v["x"]
	var z: Array = v["z"]
	var y: Array = v["y"]
	var x0: float = float(x[0])
	var x1: float = float(x[1])
	var z0: float = float(z[0])
	var z1: float = float(z[1])
	var y0: float = float(y[0])
	var y1: float = float(y[1])
	return {
		"type": "box", "name": String(v["id"]),
		"pos": Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5),
		"size": Vector3(x1 - x0, y1 - y0, z1 - z0),
		"color_key": role,
	}

static func _fence_piece(v: Dictionary, role: String) -> Dictionary:
	var from: Array = v["from"]
	var to: Array = v["to"]
	var y: float = float(v.get("y", 0.0))
	return {
		"type": "fence", "name": String(v["id"]),
		"start": Vector3(float(from[0]), y, float(from[1])),
		"end": Vector3(float(to[0]), y, float(to[1])),
		"height": float(v.get("h", 1.0)), "color_key": role,
	}

static func _ramp_piece(v: Dictionary, role: String) -> Dictionary:
	return {
		"type": "ramp", "name": String(v["id"]),
		"start": _vec3(v["from"]), "end": _vec3(v["to"]),
		"width": float(v["w"]), "color_key": role,
	}

## `steps` dérivé de `metrics.stair.step_rise` (jamais un compte fixe) : le
## nombre de marches VISUELLES suit la dénivellation réelle du volume —
## `Kit.stairs`/`_ramp_with_treads` posent de toute façon UNE seule collision
## en rampe (§ART-71, "les joueurs n'ont pas de step-up"), `steps` n'affecte
## que le rendu.
static func _stairs_piece(v: Dictionary, metrics: Dictionary, role: String) -> Dictionary:
	var from: Array = v["from"]
	var to: Array = v["to"]
	var y0: float = float(from[1])
	var y1: float = float(to[1])
	var stair_m: Dictionary = metrics.get("stair", {})
	var step_rise: float = maxf(float(stair_m.get("step_rise", 0.2)), 0.01)
	var steps: int = maxi(2, int(round(absf(y1 - y0) / step_rise)))
	return {
		"type": "stairs", "name": String(v["id"]),
		"start": Vector3(float(from[0]), y0, float(from[2])),
		"end": Vector3(float(to[0]), y1, float(to[2])),
		"width": float(v["w"]), "steps": steps, "color_key": role,
	}

## Portes JSON (`{"side","floor","offset","type"}`) -> portes Kit
## (`{"side","offset","w","floor"}`, largeur résolue via
## `metrics.doors.<type>.w`, jamais un chiffre recopié). Fenêtres JSON
## portent un `offset` par ouverture (position exacte, pour le plan coté) —
## `Kit.building2` n'a qu'un contrat plus grossier, « ce côté a des fenêtres,
## réparties automatiquement tous les 3 m sur tout étage sans porte »
## (`Kit._bld_wall_side`) : on en retient donc seulement l'ENSEMBLE des
## côtés fenêtrés (union par bâtiment, jamais par étage — même limite que le
## Kit), écart de greybox assumé et documenté au rendu de tâche (aucun impact
## gameplay : les fenêtres ne sont pas franchissables).
static func _door_width(metrics: Dictionary, door_type: String) -> float:
	var doors_meta: Dictionary = metrics.get("doors", {})
	var entry: Dictionary = doors_meta.get(door_type, {})
	return float(entry.get("w", 1.6))

static func _building_piece(v: Dictionary, metrics: Dictionary) -> Dictionary:
	var x: Array = v["x"]
	var z: Array = v["z"]
	var y: Array = v["y"]
	var x0: float = float(x[0])
	var x1: float = float(x[1])
	var z0: float = float(z[0])
	var z1: float = float(z[1])
	var y0: float = float(y[0])
	var y1: float = float(y[1])

	var doors: Array = []
	for entry in (v.get("doors", []) as Array):
		var d: Dictionary = entry
		doors.append({
			"side": String(d.get("side", "N")),
			"offset": float(d.get("offset", 0.0)),
			"w": _door_width(metrics, String(d.get("type", "std"))),
			"floor": int(d.get("floor", 0)),
		})

	var window_sides: Array = []
	for entry in (v.get("windows", []) as Array):
		var side := String((entry as Dictionary).get("side", "N"))
		if not window_sides.has(side):
			window_sides.append(side)

	var roof_meta: Dictionary = v.get("roof", {})
	var default_pitch: float = float((metrics.get("roof", {}) as Dictionary).get("pitch_deg", 27.0))
	var roof_pitch: float = float(roof_meta.get("pitch_deg", default_pitch))

	return {
		"type": "building2", "name": String(v["id"]),
		"pos": Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5),
		"size": Vector3(x1 - x0, y1 - y0, z1 - z0),
		"floors": int(v.get("floors", 1)),
		"doors": doors, "windows": window_sides,
		"roof_access": false, "parapet": 0.0,
		"stair_side": String(v.get("stair_side", "N")),
		"color_key": "wall",
		"roof_pitch_deg": roof_pitch,
	}

## Rôles servis par une simple boîte (aucun contrat Kit supplémentaire) —
## `docs/maps/WASTELAND_DESIGN.md` "kinds" ; `barrier`/`inv_wall`/`clip` (dans
## le schéma général mais ABSENTS des volumes de cette carte, voir le plan)
## retomberaient sur le même traitement s'ils apparaissaient un jour.
const _BOX_KINDS := ["ground", "slab", "solid", "wall", "landmark", "rock",
	"platform", "boundary", "cover", "barrier", "inv_wall", "clip"]

static func _volume_to_piece(v: Dictionary, materials: Dictionary, metrics: Dictionary) -> Variant:
	var kind := String(v.get("kind", ""))
	var role := _role_for_kind(materials, kind)
	if _BOX_KINDS.has(kind):
		return _box_piece(v, role)
	match kind:
		"building":
			return _building_piece(v, metrics)
		"fence":
			return _fence_piece(v, role)
		"stairs":
			return _stairs_piece(v, metrics, role)
		"ramp":
			return _ramp_piece(v, role)
		_:
			push_warning("WastelandLayout: kind JSON non gere \"%s\" (id=%s)" % [kind, v.get("id", "?")])
			return null

# ======================================================================
#  Marqueurs (`markers.team_spawns`/`tdm_spawns`/`strong_positions`,
#  `callouts`, `bounds`) — convertis tels quels, aucune coordonnée
#  recalculée à la main.
# ======================================================================
static func _marker_lift(metrics: Dictionary) -> float:
	return float(metrics.get("marker_lift", 1.0))

## `look` JSON = direction 2D `[dx, dz]` (docs/maps/WASTELAND_PLAN.md
## "Apparitions") ; `MapSetup._build_markers` attend une position-CIBLE
## (`xf.looking_at(look, UP)` seulement si `look != pos`) — reconstruite ici
## à distance fixe le long de cette direction, jamais une coordonnée en dur.
const _LOOK_TARGET_DIST := 5.0

static func _team_spawns(plan_data: Dictionary, metrics: Dictionary) -> Dictionary:
	var lift := _marker_lift(metrics)
	var out := {0: [], 1: []}
	for entry in ((plan_data.get("markers", {}) as Dictionary).get("team_spawns", []) as Array):
		var s: Dictionary = entry
		var pos_a: Array = s["pos"]
		var pos := Vector3(float(pos_a[0]), float(pos_a[1]) + lift, float(pos_a[2]))
		var look_a: Array = s.get("look", [1.0, 0.0])
		var dir := Vector3(float(look_a[0]), 0.0, float(look_a[1]))
		var target := pos + dir * _LOOK_TARGET_DIST
		var team := int(s.get("team", 0))
		if not out.has(team):
			out[team] = []
		(out[team] as Array).append({"pos": pos, "look": target})
	return out

static func _tdm_spawns(plan_data: Dictionary, metrics: Dictionary) -> Array:
	var lift := _marker_lift(metrics)
	var out: Array = []
	for entry in ((plan_data.get("markers", {}) as Dictionary).get("tdm_spawns", []) as Array):
		var s: Dictionary = entry
		var pos_a: Array = s["pos"]
		out.append({"pos": Vector3(float(pos_a[0]), float(pos_a[1]) + lift, float(pos_a[2]))})
	return out

static func _strong_positions(plan_data: Dictionary) -> Array:
	var out: Array = []
	for entry in ((plan_data.get("markers", {}) as Dictionary).get("strong_positions", []) as Array):
		var s: Dictionary = (entry as Dictionary).duplicate(true)
		s["pos"] = _vec3(s["pos"])
		var counters: Array = []
		for c in (s.get("counters", []) as Array):
			var cc: Dictionary = (c as Dictionary).duplicate(true)
			cc["pos"] = _vec3(cc["pos"])
			counters.append(cc)
		s["counters"] = counters
		out.append(s)
	return out

static func _callouts(plan_data: Dictionary) -> Array:
	var out: Array = []
	for entry in (plan_data.get("callouts", []) as Array):
		var c: Dictionary = entry
		var x: Array = c["x"]
		var z: Array = c["z"]
		var x0: float = float(x[0])
		var x1: float = float(x[1])
		var z0: float = float(z[0])
		var z1: float = float(z[1])
		var aabb := AABB(Vector3(x0, -20.0, z0), Vector3(x1 - x0, 60.0, z1 - z0))
		out.append({"name": String(c.get("name", "")), "aabb": aabb})
	return out

## Rectangle fermé calé EXACTEMENT sur `bounds` (même convention que l'ancien
## contrat v4 : `perimeter == bounds`) — garde-fou redondant de `MapSetup
## ._build_perimeter`, en plus des falaises `CliffN/S/W/E` (kind "boundary",
## posées hors de `bounds`) qui bloquent déjà physiquement le bord jouable.
static func _perimeter(bounds: Dictionary) -> Array:
	var bx: Array = bounds.get("x", [-42.0, 42.0])
	var bz: Array = bounds.get("z", [-25.0, 25.0])
	var x0: float = float(bx[0])
	var x1: float = float(bx[1])
	var z0: float = float(bz[0])
	var z1: float = float(bz[1])
	return [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]

static func data() -> Dictionary:
	var plan_data := plan()
	if plan_data.is_empty():
		return {}
	var materials: Dictionary = plan_data.get("materials", {})
	var metrics: Dictionary = plan_data.get("metrics", {})
	var bounds: Dictionary = plan_data.get("bounds", {"x": [-42.0, 42.0], "z": [-25.0, 25.0]})

	var pieces: Array = []
	for entry in (plan_data.get("volumes", []) as Array):
		var v: Dictionary = entry
		var modes: Array = v.get("modes", [])
		if not modes.is_empty() and not modes.has(MatchConfig.mode_id):
			continue
		var piece: Variant = _volume_to_piece(v, materials, metrics)
		if piece != null:
			pieces.append(piece)

	var bx: Array = bounds.get("x", [-42.0, 42.0])
	var bz: Array = bounds.get("z", [-25.0, 25.0])

	return {
		"id": "wasteland", "name": "Wasteland",
		"palette": WastelandLook.palette(),
		"pieces": pieces,
		"spawns": _team_spawns(plan_data, metrics),
		"tdm_spawns": _tdm_spawns(plan_data, metrics),
		"strong_positions": _strong_positions(plan_data),
		"callouts": _callouts(plan_data),
		"bounds": {"min": Vector2(float(bx[0]), float(bz[0])), "max": Vector2(float(bx[1]), float(bz[1]))},
		# Carte ASYMÉTRIQUE PAR CONSTRUCTION (v7, `mirror.enabled: false`,
		# `docs/maps/WASTELAND_DESIGN.md` "Thèse") mais mesurée équilibrée
		# (`tools/maps/check_plan.py`, 23/23 contrôles OK) : l'échange de
		# côté de mi-match (`TDMMode.asymmetric_map`, hors de mon périmètre)
		# reste le bon outil pour une carte différente-mais-équitable des
		# deux côtés, exactement son cas d'usage documenté.
		"asymmetric": true,
		"perimeter": _perimeter(bounds),
	}
