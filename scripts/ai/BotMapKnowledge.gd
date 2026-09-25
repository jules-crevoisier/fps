## BotMapKnowledge.gd
## Lecteur PUR (BOT-22, docs/research/08_bots_humanlike.md §3.7 "Connaissance
## de Wasteland (K)") de la clé `"bot_knowledge"` d'une carte — quel que soit
## le format exact que `MapSetup`/`<Layout>.data()` finira par exposer sous ce
## nom, cette classe ne dépend d'AUCUNE scène ni d'aucun nom de carte : elle
## reçoit le Dictionary de connaissance en constructeur (comme `BotSpots.bake`
## reçoit ses paramètres explicitement) et se contente de le lire.
##
## ÉCART CONNU (signalé dans le rendu de tâche, blocked_on) : au moment
## d'écrire ce fichier, aucune carte du dépôt n'expose encore de clé
## `"bot_knowledge"` — `scripts/levels/maps/layouts/wasteland.gd` (qui la
## porterait) et `scripts/levels/maps/layouts/wasteland_bots.gd` (5 clés
## `lanes`/`hotspots`/`hp_hold_points`/`nav_links`/`danger_spans`, un schéma
## PLUS ANCIEN et différent, docs/research/09_wasteland_vertical_slice.md §e)
## sont hors de la liste de fichiers de cette tâche. Le schéma lu ci-dessous
## est celui décrit par le brouillon §3.7 et par les critères d'acceptation
## de BOT-22 ; les tests de `tests/ai/test_bot_map_knowledge.gd` l'exercent
## avec un jeu de données FIXTURE repris des coordonnées RÉELLES du brouillon
## (zones, couloirs, angles, perchoirs, couvertures, tenues Hardpoint), prêt
## à être branché tel quel dès qu'un `"bot_knowledge"` conforme existera.
##
## Schéma attendu du Dictionary `data` passé au constructeur :
##  - `"zones"` : Array[Dictionary] `{"name": String, "min": Vector3, "max":
##    Vector3}` — boîte AABB nommée (>= 14 sur Wasteland, §3.7 : FuelPlank,
##    FuelHouse, Garage, Réservoir, Chapelle, Hangar-grue, CraneDeck, Derrick,
##    GasOffice, WestBlock, Entrepôt, SouthBlock, Shack, champ de dune...).
##  - `"corridors"` : Dictionary `{"N"|"C"|"S": Array[Vector3]}` — un couloir
##    par lettre, points dans l'ordre OUEST -> EST (équipe 0) ; `lane_goals`
##    inverse cet ordre pour l'équipe 1 (§3.7 : "trajet de l'ouest vers l'est,
##    inversé pour l'équipe 1").
##  - `"angles"` : Array[Dictionary] `{"pos": Vector3, "dir": Vector3}` —
##    angle à pré-viser (>= 20 sur Wasteland, §3.7 "22 points").
##  - `"perches"` : Array[Dictionary] `{"name": String, "pos": Vector3,
##    "watch": String}` — perchoir (>= 4, §3.7 "tenue de U(5;10) s").
##  - `"covers"` : Array[Dictionary] `{"pos": Vector3, "dir": Vector3,
##    "height": float}` — couverture, `dir` = direction protégée, `height` en
##    mètres (>= 10).
##  - `"hp_holds"` : Array[Dictionary], une entrée par zone Hardpoint (4 sur
##    Wasteland : HP1 rue/voitures, HP2 réservoir, HP3 toit du hangar, HP4
##    entrepôt), chacune `{"zone": String, "hold": Array[Vector3] (>= 2
##    positions DANS la zone), "watch": Array[Vector3] (>= 2 positions de
##    surveillance des entrées)}`.
class_name BotMapKnowledge
extends RefCounted

## Rôle d'un point de tenue Hardpoint DANS la zone (voir `hp_holds`).
const ROLE_HOLD := "hold"
## Rôle d'un point de tenue Hardpoint qui surveille une entrée à distance.
const ROLE_WATCH := "watch"

## Portée par défaut d'`angles_near` (§3.7/BOT-22 : "25 m").
const DEFAULT_ANGLE_RANGE := 25.0
## Demi-angle de cône par défaut d'`angles_near` (§3.7/BOT-22 : "±60°").
const DEFAULT_HALF_ANGLE_DEG := 60.0

## En dessous de cette distance (m), la direction bot -> angle n'est plus
## fiable (quasi nulle) : l'angle est retenu sans test de cône, il est de
## toute façon "sur" le bot.
const _DEGENERATE_DIST := 0.01

var _data: Dictionary


func _init(data: Dictionary) -> void:
	_data = data


## Nom de la zone (§3.7 AABB) qui contient `pos`, ou `""` si aucune ne
## correspond (première zone trouvée dans l'ordre déclaré, les zones ne se
## chevauchent pas dans les données de carte réelles).
func area_of(pos: Vector3) -> String:
	for entry in (_data.get("zones", []) as Array):
		var zone: Dictionary = entry
		var zmin: Vector3 = zone["min"]
		var zmax: Vector3 = zone["max"]
		if pos.x < zmin.x or pos.x > zmax.x:
			continue
		if pos.y < zmin.y or pos.y > zmax.y:
			continue
		if pos.z < zmin.z or pos.z > zmax.z:
			continue
		return String(zone["name"])
	return ""


## Points du couloir `lane` ("N"/"C"/"S") dans l'ordre de progression de
## `team` — tel quel (ouest -> est) pour l'équipe 0, inversé pour l'équipe 1
## (§3.7 : "inversé pour l'équipe 1"). Tableau vide si le couloir est inconnu.
func lane_goals(team: int, lane: String) -> Array:
	var corridors: Dictionary = _data.get("corridors", {})
	if not corridors.has(lane):
		return []
	var points: Array = (corridors[lane] as Array).duplicate()
	if team == 1:
		points.reverse()
	return points


## Angles à pré-viser à moins de `range_m` de `pos` ET dans un cône de
## `half_angle_deg` de part et d'autre de `fwd` (plan XZ — un bot ne juge pas
## ces angles par le tangage). Un angle exactement sur `pos` est retenu sans
## test de cône (direction bot -> angle indéfinie). `fwd` quasi vertical (pas
## de composante XZ) ne peut définir aucun cône : tableau vide.
func angles_near(pos: Vector3, fwd: Vector3, range_m: float = DEFAULT_ANGLE_RANGE, half_angle_deg: float = DEFAULT_HALF_ANGLE_DEG) -> Array:
	var out: Array = []
	var fwd_flat := Vector3(fwd.x, 0.0, fwd.z)
	if fwd_flat.length() < _DEGENERATE_DIST:
		return out
	fwd_flat = fwd_flat.normalized()

	for entry in (_data.get("angles", []) as Array):
		var angle: Dictionary = entry
		var to_angle := (angle["pos"] as Vector3) - pos
		var flat := Vector3(to_angle.x, 0.0, to_angle.z)
		var dist := flat.length()
		if dist > range_m:
			continue
		if dist < _DEGENERATE_DIST:
			out.append(angle)
			continue
		var cos_angle := fwd_flat.dot(flat / dist)
		var deg := rad_to_deg(acos(clampf(cos_angle, -1.0, 1.0)))
		if deg <= half_angle_deg:
			out.append(angle)
	return out


## Positions de tenue Hardpoint de la zone `index` (0-based) pour le rôle
## `role` (`ROLE_HOLD` = dans la zone, `ROLE_WATCH` = surveillance d'entrée).
## Tableau vide si `index` est hors bornes ou si le rôle est absent.
func hp_holds(index: int, role: String) -> Array:
	var zones: Array = _data.get("hp_holds", [])
	if index < 0 or index >= zones.size():
		return []
	var zone: Dictionary = zones[index]
	return (zone.get(role, []) as Array).duplicate()
