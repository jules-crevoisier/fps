## BotSpots.gd
## Données tactiques PRÉ-CALCULÉES d'une carte (BOT-05, docs/research/02_bots_ai.md
## §2.5/§2.6 : « couverture et cachettes générées automatiquement hors ligne à
## partir de la navmesh », « graphe de waypoints avec couverture par direction
## calculée hors ligne »). Une ressource par carte, sous
## `resources/bot_spots/<map_id>.tres`, produite par `tools/bake_bot_spots.gd`
## et rechargée au runtime (position-picking BOT-06, hors périmètre ici) via
## `BotSpots.load_for_map`.
##
## Un "spot" = un point échantillonné sur la navmesh, avec :
##  - `coverage_crouch` / `coverage_stand` : Array[bool] de taille
##    `DIRECTIONS.size()` — vrai si un rayon physique (calque
##    `PhysicsLayers.WORLD` uniquement, jamais VISION : une fumée ne protège
##    pas d'un vrai mur) tiré depuis ce spot, à la hauteur accroupi/debout,
##    touche du décor à moins de `COVER_RANGE` mètres dans cette direction.
##  - `sniping` : vrai si AU MOINS une des 8 directions offre une ligne de vue
##    dégagée d'au moins `SNIPE_RANGE` mètres à hauteur debout.
##  - `approach_points` : les AUTRES spots accessibles à moins de
##    `APPROACH_RANGE` mètres de CHEMIN DE NAVIGATION (BFS `NavigationServer3D.
##    map_get_path`, jamais à vol d'oiseau — Booth, GDC 2004 : la distance à
##    vol d'oiseau est « very misleading »). Le filtre à vol d'oiseau utilisé
##    plus bas n'est qu'un PRÉ-FILTRE de performance (évite une requête de
##    chemin coûteuse pour des points visiblement hors de portée) : il ne
##    décide jamais seul qu'un point est un point d'approche.
##
## `map_id="test_arena"` est une PETITE SALLE TACTIQUE SYNTHÉTIQUE construite
## par `tools/bake_bot_spots.gd` — PAS `scenes/levels/test_arena.tscn` (le
## parcours de test de mouvement d'ArenaBuilder.gd : pente, champ de piliers
## épars, trou de slide-jump...). Ce parcours a de larges zones ouvertes SANS
## aucune couverture à moins de 15 m (la Plaza de spawn, l'entrée du champ) :
## par construction, aucun choix raisonnable de portée de rayon ne peut y
## satisfaire le critère d'acceptation « >= 1 spot couvert à < 10 m de chaque
## point navigable ». La salle synthétique (murs en croix formant 4 quadrants)
## est conçue pour le satisfaire par construction ET pour couvrir des cartes
## réelles plus tard (MapSetup fournit déjà sa propre NavigationRegion3D pour
## les six maps du catalogue).
class_name BotSpots
extends Resource

## 8 directions compas (plan XZ), ordre FIXE partagé par le bake et tout
## consommateur futur (position-picking BOT-06 : score par direction face à
## une menace). Index 0/2/4/6 = cardinales pures (+Z/+X/-Z/-X), 1/3/5/7 =
## diagonales.
const DIRECTIONS: Array[Vector3] = [
	Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 0, -1),
	Vector3(0, 0, -1), Vector3(-1, 0, -1), Vector3(-1, 0, 0), Vector3(-1, 0, 1),
]

const SAMPLE_STEP := 2.0     ## pas d'échantillonnage de la navmesh (m).
const LEVEL_STEP := 1.0      ## pas vertical de la pile de sondes (BOT-22) : couvre
                              ## étages/plateformes/toits superposés à la même XZ
                              ## (dune 3.2 m, Derrick 4.5 m, CraneDeck 5.6 m, toits
                              ## 6.4-6.9 m sur Wasteland) qu'une sonde unique à
                              ## mi-hauteur d'AABB pouvait laisser hors échantillon.
                              ## `map_get_closest_point` ne renvoie QUE le point de
                              ## navmesh le plus proche en 3D d'une sonde : deux
                              ## niveaux distincts ne sont tous deux retrouvés que si
                              ## une sonde de la pile tombe plus près de CHACUN que de
                              ## l'autre (de part et d'autre de leur point médian) —
                              ## un pas plus large que l'écart le plus SERRÉ entre deux
                              ## niveaux réels (0,8 m entre les toits de Wasteland)
                              ## risquerait d'en manquer un ; 1 m garde une marge
                              ## raisonnable sans multiplier démesurément le coût du
                              ## bake (budget BAKE_BUDGET_MS, vérifié par test).
const CROUCH_EYE := 0.9      ## hauteur du rayon "accroupi" (m).
const STAND_EYE := 1.6       ## hauteur du rayon "debout" (m).
const COVER_RANGE := 6.0     ## portée : direction "couverte" si bloquée à <= cette distance.
const SNIPE_RANGE := 30.0    ## portée mini d'une ligne de vue dégagée pour le flag sniping.
const MAX_RAY_RANGE := 60.0  ## portée max testée par rayon.
const APPROACH_RANGE := 4.0  ## rayon de CHEMIN (pas à vol d'oiseau) des points d'approche.
const BAKE_BUDGET_MS := 30000 ## budget de bake (acceptance BOT-05).

const RESOURCE_DIR := "res://resources/bot_spots"

@export var map_id: String = ""
## Un spot par entrée : {"position": Vector3, "coverage_crouch": Array[bool],
## "coverage_stand": Array[bool], "sniping": bool, "approach_points": PackedVector3Array}.
@export var spots: Array[Dictionary] = []


## Un spot est "couvert" s'il a au moins une direction bloquée (accroupi OU
## debout) — utilisé par le test d'acceptation et par un futur consommateur
## (position-picking) pour distinguer un spot exposé d'un spot à couvert.
static func is_covered(spot: Dictionary) -> bool:
	for blocked in (spot["coverage_crouch"] as Array):
		if blocked:
			return true
	for blocked in (spot["coverage_stand"] as Array):
		if blocked:
			return true
	return false


## Charge la ressource bakée d'une carte, ou `null` si elle n'a pas encore été
## générée (contract BOT-05 : le câblage GameWorld -> BotSpots reste hors de
## ce périmètre, voir le rapport de tâche — ce chargeur est prêt à l'emploi).
static func load_for_map(map_id_: String) -> BotSpots:
	var path := "%s/%s.tres" % [RESOURCE_DIR, map_id_]
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as BotSpots


## --- Bake ------------------------------------------------------------------
## Échantillonne `nav_region` par pas de SAMPLE_STEP, calcule la couverture
## (rayons physiques dans `space`) et le flag sniping par spot, puis les
## points d'approche par requête de CHEMIN sur la navmesh. Fonction PURE côté
## logique (aucun accès scène hors les paramètres reçus) : directement
## appelable par les tests comme par `tools/bake_bot_spots.gd`.
static func bake(map_id_: String, nav_region: NavigationRegion3D, space: PhysicsDirectSpaceState3D) -> BotSpots:
	var result := BotSpots.new()
	result.map_id = map_id_
	var points := _sample_navmesh(nav_region)
	var built: Array[Dictionary] = []
	for p in points:
		built.append(_bake_spot(p, space))
	var map_rid := nav_region.get_navigation_map()
	for i in built.size():
		built[i]["approach_points"] = _approach_points(map_rid, points, i)
	result.spots = built
	return result


## Grille XZ au pas SAMPLE_STEP sur l'AABB (monde) des sommets de la navmesh ;
## à CHAQUE colonne XZ, une PILE de sondes verticales (pas LEVEL_STEP, du bas
## vers le haut de l'AABB — BOT-22) est projetée SUR la surface navigable
## (`map_get_closest_point`), chaque candidat retenu seulement si sa
## projection retombe près du point de grille (sinon le candidat est hors
## navmesh — mur, vide, etc.). Une seule sonde par colonne (mi-hauteur
## d'AABB) manquait les niveaux superposés d'une carte à étages (dune,
## Derrick, CraneDeck, toits) : `map_get_closest_point` renvoie le point de
## navmesh le plus proche en 3D de la sonde, donc seule la sonde la plus
## proche EN HAUTEUR d'un niveau donné le retrouve — une pile couvre tous les
## niveaux réellement superposés à cette colonne. Dédoublonné (plusieurs
## sondes, à des niveaux différents ou non, peuvent se projeter sur le même
## point de surface), puis filtré par CONNEXITÉ (`_reachable_from_lowest`) :
## Recast marque le DESSUS PLAT d'un mur comme un îlot marchable À PART
## ENTIÈRE dès qu'il est assez large, même sans rampe pour y monter — un
## point de grille juste à côté d'un mur peut donc se projeter sur ce dessus
## (plus proche en 3D) plutôt que sur le sol, en dessous. Un point non relié
## au sol par un vrai CHEMIN de navigation n'est pas un spot exploitable par
## un bot au sol.
static func _sample_navmesh(nav_region: NavigationRegion3D) -> Array[Vector3]:
	var raw: Array[Vector3] = []
	var mesh := nav_region.navigation_mesh
	if mesh == null:
		return raw
	var verts := mesh.get_vertices()
	if verts.is_empty():
		return raw
	var xf := nav_region.global_transform
	var aabb := AABB(xf * (verts[0] as Vector3), Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(xf * (v as Vector3))

	var map_rid := nav_region.get_navigation_map()
	var seen: Dictionary = {}
	var z := aabb.position.z
	while z <= aabb.end.z + 0.01:
		var x := aabb.position.x
		while x <= aabb.end.x + 0.01:
			_sample_column(map_rid, aabb, x, z, seen, raw)
			x += SAMPLE_STEP
		z += SAMPLE_STEP
	return _reachable_from_lowest(map_rid, raw)


## Pile de sondes verticales à une colonne XZ donnée : du bas (`aabb.position.y`)
## au haut (`aabb.end.y`) de l'AABB par pas LEVEL_STEP, chacune projetée sur la
## navmesh — un niveau dégénéré (AABB plate, `aabb.size.y == 0`) ne produit
## qu'une seule sonde, le comportement d'origine.
static func _sample_column(map_rid: RID, aabb: AABB, x: float, z: float, seen: Dictionary, raw: Array[Vector3]) -> void:
	var y := aabb.position.y + 0.05
	var y_end := aabb.end.y + 0.05
	while y <= y_end:
		var probe := Vector3(x, y, z)
		var snapped := NavigationServer3D.map_get_closest_point(map_rid, probe)
		var flat_offset := Vector2(snapped.x - x, snapped.z - z).length()
		if flat_offset <= SAMPLE_STEP * 0.5:
			var key := "%d_%d_%d" % [roundi(snapped.x * 20.0), roundi(snapped.y * 20.0), roundi(snapped.z * 20.0)]
			if not seen.has(key):
				seen[key] = true
				raw.append(snapped)
		y += LEVEL_STEP


## Ne garde que les points reliés PAR UN CHEMIN au point le plus BAS de
## `raw` (le sol principal est, dans nos géométries, toujours plus bas que
## tout dessus de mur ou de plateforme isolée — limite connue : une carte
## avec une fosse sous le sol principal demanderait une ancre différente).
static func _reachable_from_lowest(map_rid: RID, raw: Array[Vector3]) -> Array[Vector3]:
	if raw.is_empty():
		return raw
	var anchor := raw[0]
	for p in raw:
		if p.y < anchor.y:
			anchor = p
	var connected: Array[Vector3] = []
	for p in raw:
		if p.distance_to(anchor) <= 0.01:
			connected.append(p)
			continue
		var path := NavigationServer3D.map_get_path(map_rid, anchor, p, true)
		if path.size() >= 2 and path[path.size() - 1].distance_to(p) <= SAMPLE_STEP:
			connected.append(p)
	return connected


static func _bake_spot(pos: Vector3, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var coverage_crouch: Array[bool] = []
	var coverage_stand: Array[bool] = []
	var sniping := false
	for dir in DIRECTIONS:
		var hit_crouch := _cast(space, pos + Vector3.UP * CROUCH_EYE, dir)
		coverage_crouch.append(hit_crouch >= 0.0 and hit_crouch <= COVER_RANGE)

		var hit_stand := _cast(space, pos + Vector3.UP * STAND_EYE, dir)
		coverage_stand.append(hit_stand >= 0.0 and hit_stand <= COVER_RANGE)
		var los_dist := hit_stand if hit_stand >= 0.0 else MAX_RAY_RANGE
		if los_dist >= SNIPE_RANGE:
			sniping = true
	return {
		"position": pos,
		"coverage_crouch": coverage_crouch,
		"coverage_stand": coverage_stand,
		"sniping": sniping,
		"approach_points": PackedVector3Array(),
	}


## Distance au premier obstacle de DÉCOR (`PhysicsLayers.WORLD` uniquement —
## jamais VISION, une fumée n'offre pas de vraie couverture physique) le long
## de `dir` depuis `from`, ou -1.0 si rien touché avant MAX_RAY_RANGE.
static func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3) -> float:
	var to := from + dir.normalized() * MAX_RAY_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = PhysicsLayers.WORLD
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return -1.0
	return from.distance_to(hit["position"] as Vector3)


## Points d'approche de `points[index]` : les AUTRES points dont le CHEMIN de
## navigation (jamais à vol d'oiseau) mesure au plus APPROACH_RANGE. Le filtre
## à vol d'oiseau (2.5x large) n'élimine QUE des candidats déjà bien au-delà de
## toute portée plausible ; jamais utilisé comme verdict final.
static func _approach_points(map_rid: RID, points: Array[Vector3], index: int) -> PackedVector3Array:
	var origin := points[index]
	var out := PackedVector3Array()
	for i in points.size():
		if i == index:
			continue
		var candidate: Vector3 = points[i]
		if origin.distance_to(candidate) > APPROACH_RANGE * 2.5:
			continue
		var path := NavigationServer3D.map_get_path(map_rid, origin, candidate, true)
		if path.size() < 2:
			continue
		if _path_length(path) <= APPROACH_RANGE:
			out.append(candidate)
	return out


static func _path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total
