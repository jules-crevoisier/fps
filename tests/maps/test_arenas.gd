## test_arenas.gd
## LD-09 (docs/research/03_level_design.md §5 "Tâches" + §4.8 "Arènes Duel/Duo :
## pas de test de temps jusqu'au premier contact ni de nombre de routes vers la
## zone") : valide La Fosse et Le Belvédère sur 3 axes qu'AUCUN test existant
## ne couvre (tests/maps/test_navmesh.gd vérifie déjà, pour ces deux maps, que
## chaque spawn ATTEINT la `duel_zone` et le budget de perf — pas le TEMPS, ni
## le nombre de routes, ni les lignes de vue) :
##
##  1. Premier contact : temps de sprint (navmesh RÉEL, pas à vol d'oiseau —
##     même esprit que `.orchestrator/maps-spec-v2.md` §5.6 "Measured parity") de
##     chaque spawn au milieu (`duel_zone`, la zone qui s'ouvre en overtime,
##     `DuelMode.capture_zone_path` dans `MapSetup._build_game_mode`) est
##     2-4 s ; écart ≤ 5 % entre les deux camps (moyenne des 2 spawns du camp).
##  2. La zone d'overtime a >= 3 accès distincts : mesuré par anneau de rayons
##     physiques autour de son centre (§ méthode ci-dessous), PAS par simple
##     comptage de rampes déclarées ni par adjacence de polygones du navmesh —
##     les deux ont été essayés et rejetés (voir "Méthode accès" plus bas).
##  3. Aucune ligne de vue (raycast physique, oeil +1,7 m) entre deux points du
##     navmesh n'est libre au-delà de 30 m (doc §3.2 : "La Fosse 28x28, Belvédère
##     30x24, lignes <= 30 m").
##
## Méthode "accès" (validée empiriquement avant d'écrire les seuils, PAS
## inventée a priori — "invent nothing" comme le rappelle test_navmesh.gd) :
## un simple comptage d'arêtes de polygone du navmesh à la frontière EXACTE de
## la `duel_zone` donne 0 (Belvédère : le podium est 0,9 m plus haut que le pont,
## AU-DESSUS de `AGENT_MAX_CLIMB` 0,5 m dans MapSetup.gd — îlot de navmesh
## séparé, jamais compté comme "portail") ou 1 seul groupe (La Fosse : la
## `duel_zone` est une simple découpe arbitraire au milieu d'un sol de fosse
## continu 12x12, pas une vraie limite physique). Un anneau de rayons physiques
## autour du CENTRE de la zone, à la hauteur de SON PROPRE plancher (`duel_zone.
## pos.y - size.y/2 + 0,3`, un peu au-dessus du sol de la zone — sous cette
## hauteur on ne teste plus rien d'utile, au-dessus on rate les murets bas), à
## un rayon `max(size.x,size.z) * 1.4` (juste au-delà des murs/rambardes qui
## encerclent réellement l'accès, pas juste la boîte de zone), avec 72
## échantillons (5°) donne un résultat STABLE (mêmes arcs ouverts) sur toute la
## plage rayon x1.2-x1.6 et marge 0,15-0,5 m pour LES DEUX arènes (testé à la
## main, `tools/tasks/plan.py prompt LD-09` → scratch, avant d'écrire ce
## fichier) : 4 accès chacune (La Fosse : les 2 rampes de fosse + les 2 passages
## du convoyeur, symétriques ; Belvédère : les 4 quadrants entre les rambardes
## du pont, symétriques). Un rayon non bloqué = un accès ouvert ; les arcs
## contigus ouverts (cercle) sont comptés une seule fois chacun.
extends GdUnitTestSuite

const MapSetupScript := preload("res://scripts/levels/maps/MapSetup.gd")

const ARENA_MAP_IDS := ["la_fosse", "le_belvedere"]
const MAX_SYNC_FRAMES := 20

## §1 Premier contact (docs/research/03_level_design.md, tâche LD-09).
const FIRST_CONTACT_MIN := 2.0
const FIRST_CONTACT_MAX := 4.0
const FIRST_CONTACT_GAP_MAX := 0.05  # 5 %, même convention que maps-spec-v2.md §5.6 (Gap = (max-min)/min)

## §2 Accès à la zone — voir "Méthode accès" ci-dessus.
const MIN_ZONE_ACCESSES := 3
const ACCESS_RING_SCALE := 1.4
const ACCESS_RING_MARGIN := 0.3
const ACCESS_RING_SAMPLES := 72

## §3 Lignes de vue (docs/research/03_level_design.md §3.2 : "lignes <= 30 m").
const MAX_SIGHTLINE := 30.0
const EYE_HEIGHT := 1.7
const VANTAGE_CLUSTER_RADIUS := 2.0  # dédoublonne les centroïdes de polygones voisins

var _next_offset_index := 0


func _setup_map(map_id: String) -> Dictionary:
	var offset := Vector3(float(_next_offset_index) * 400.0, 0.0, 0.0)
	_next_offset_index += 1
	var setup := MapSetupScript.new()
	setup.map_id = map_id
	setup.position = offset
	add_child(setup)
	return {"setup": setup, "offset": offset}


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


static func _path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func test_la_fosse_arena() -> void:
	await _check_arena("la_fosse")


func test_le_belvedere_arena() -> void:
	await _check_arena("le_belvedere")


func _check_arena(map_id: String) -> void:
	var built := _setup_map(map_id)
	var setup: MapSetup = built["setup"]
	var offset: Vector3 = built["offset"]
	await get_tree().physics_frame
	var nav := setup.nav_region
	assert_that(nav).append_failure_message(map_id).is_not_null()
	var data := Layouts.data_for(map_id)
	var dz: Dictionary = data["duel_zone"]
	var mid: Vector3 = offset + (dz["pos"] as Vector3)

	var sp0_all: Array = []
	var sp1_all: Array = []
	for e in (data["spawns"][0] as Array):
		sp0_all.append(offset + ((e as Dictionary)["pos"] as Vector3))
	for e in (data["spawns"][1] as Array):
		sp1_all.append(offset + ((e as Dictionary)["pos"] as Vector3))

	await _assert_first_contact_timing(map_id, nav, sp0_all, sp1_all, mid)

	_assert_zone_has_enough_accesses(map_id, setup, mid, dz["size"] as Vector3)

	await _assert_no_long_sightline(map_id, setup, nav)

	await _teardown(setup)


# ----------------------------------------------------------------------
#  §1 Premier contact : temps de sprint spawn -> milieu, par camp.
# ----------------------------------------------------------------------
## "Milieu" = centre de la `duel_zone` (la zone d'overtime — même marqueur que
## `DuelMode.capture_zone_path`, voir `MapSetup._build_markers`/`_build_game_mode`).
## "Par camp" = moyenne des chemins RÉELS (navmesh, pas centroïde des positions
## de spawn : sur Le Belvédère, le milieu des deux spawns d'un camp tombe au-
## dessus de la rue, hors du toit — un point qui n'a rien à voir avec un
## joueur réel — d'où la moyenne des temps individuels plutôt que le temps du
## point moyen).
func _assert_first_contact_timing(map_id: String, nav: NavigationRegion3D, team0: Array, team1: Array, mid: Vector3) -> void:
	var cfg: MovementConfig = load("res://resources/movement/default_movement.tres")
	var t0 := await _camp_time(map_id, nav, team0, mid, cfg.sprint_speed)
	var t1 := await _camp_time(map_id, nav, team1, mid, cfg.sprint_speed)
	assert_float(t0).append_failure_message("%s camp 0 : premier contact %.2f s (attendu 2-4 s)" % [map_id, t0]).is_between(FIRST_CONTACT_MIN, FIRST_CONTACT_MAX)
	assert_float(t1).append_failure_message("%s camp 1 : premier contact %.2f s (attendu 2-4 s)" % [map_id, t1]).is_between(FIRST_CONTACT_MIN, FIRST_CONTACT_MAX)
	var faster := minf(t0, t1)
	var slower := maxf(t0, t1)
	var gap := (slower - faster) / faster if faster > 0.0 else 0.0
	assert_float(gap).append_failure_message("%s : écart premier contact camp0=%.2fs camp1=%.2fs (%.1f %%, max 5 %%)" % [map_id, t0, t1, gap * 100.0]).is_less_equal(FIRST_CONTACT_GAP_MAX)


func _camp_time(map_id: String, nav: NavigationRegion3D, spawns: Array, mid: Vector3, sprint_speed: float) -> float:
	var total := 0.0
	for sp in spawns:
		var from: Vector3 = sp
		var path := await _wait_for_path(nav.get_navigation_map(), from, mid)
		assert_int(path.size()).append_failure_message("%s : aucun chemin spawn %s -> milieu" % [map_id, from]).is_greater_equal(2)
		total += _path_length(path) / sprint_speed
	return total / float(spawns.size())


# ----------------------------------------------------------------------
#  §2 Accès à la zone d'overtime — voir "Méthode accès" en tête de fichier.
# ----------------------------------------------------------------------
func _assert_zone_has_enough_accesses(map_id: String, setup: MapSetup, zone_center: Vector3, zone_size: Vector3) -> void:
	var footprint := maxf(zone_size.x, zone_size.z)
	var ring_radius := footprint * ACCESS_RING_SCALE
	var height := zone_center.y - zone_size.y * 0.5 + ACCESS_RING_MARGIN
	var center := Vector3(zone_center.x, height, zone_center.z)
	var space := setup.get_world_3d().direct_space_state
	var open_flags: Array = []
	for i in ACCESS_RING_SAMPLES:
		var ang := TAU * float(i) / float(ACCESS_RING_SAMPLES)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var from: Vector3 = center + dir * ring_radius
		var query := PhysicsRayQueryParameters3D.create(from, center)
		var result := space.intersect_ray(query)
		open_flags.append(result.is_empty())
	var arcs := _count_open_arcs(open_flags)
	assert_int(arcs).append_failure_message("%s : %d accès distincts détectés autour du milieu (rayon=%.1f m, hauteur=%.2f)" % [map_id, arcs, ring_radius, height]).is_greater_equal(MIN_ZONE_ACCESSES)


## Compte les arcs (secteurs) contigus "ouverts" sur le cercle d'échantillons —
## un accès = un arc ouvert entouré d'échantillons bloqués (mur, rambarde...).
## Si tout est ouvert (aucun obstacle détecté), il n'y a qu'UN SEUL accès (la
## zone n'est défendue par aucun repli), pas `n` (un par échantillon).
static func _count_open_arcs(open_flags: Array) -> int:
	var n := open_flags.size()
	var arcs := 0
	for i in n:
		var prev: bool = open_flags[(i - 1 + n) % n]
		var cur: bool = open_flags[i]
		if cur and not prev:
			arcs += 1
	if arcs == 0 and open_flags.count(true) == n:
		return 1
	return arcs


# ----------------------------------------------------------------------
#  §3 Lignes de vue : aucune > 30 m entre deux points du navmesh.
# ----------------------------------------------------------------------
## Points de vue = centroïdes des polygones du navmesh (comme `_zone_navmesh_
## area` de test_navmesh.gd), dédoublonnés (`VANTAGE_CLUSTER_RADIUS`) pour
## éviter O(polygones²) et pour ne pas compter deux fois deux échantillons du
## même mètre carré de sol. Pour CHAQUE paire distante de plus de 30 m à hauteur
## d'oeil (+1,7 m), un raycast physique doit toucher de la géométrie — sinon la
## ligne de vue est libre et dépasse la limite de la spec (docs/research/
## 03_level_design.md §3.2).
func _assert_no_long_sightline(map_id: String, setup: MapSetup, nav: NavigationRegion3D) -> void:
	var points := _vantage_points(nav)
	var space := setup.get_world_3d().direct_space_state
	var worst := 0.0
	var worst_a := Vector3.ZERO
	var worst_b := Vector3.ZERO
	for i in points.size():
		for j in range(i + 1, points.size()):
			var a: Vector3 = points[i]
			var b: Vector3 = points[j]
			var d := a.distance_to(b)
			if d <= MAX_SIGHTLINE:
				continue
			var from: Vector3 = a + Vector3(0, EYE_HEIGHT, 0)
			var to: Vector3 = b + Vector3(0, EYE_HEIGHT, 0)
			var query := PhysicsRayQueryParameters3D.create(from, to)
			var result := space.intersect_ray(query)
			if result.is_empty() and d > worst:
				worst = d
				worst_a = a
				worst_b = b
	assert_float(worst).append_failure_message("%s : ligne de vue libre de %.1f m entre %s et %s (max 30 m)" % [map_id, worst, worst_a, worst_b]).is_equal(0.0)


## Centroïdes de polygones du navmesh, dédoublonnés à `VANTAGE_CLUSTER_RADIUS`
## (même transform monde que `_zone_navmesh_area` dans test_navmesh.gd).
static func _vantage_points(nav: NavigationRegion3D) -> Array:
	var nm := nav.navigation_mesh
	var xf := nav.global_transform
	var verts := nm.get_vertices()
	var poly_count := nm.get_polygon_count()
	var points: Array = []
	for i in poly_count:
		var poly := nm.get_polygon(i)
		if poly.size() < 3:
			continue
		var c := Vector3.ZERO
		for idx in poly:
			c += xf * (verts[idx] as Vector3)
		c /= float(poly.size())
		var merged := false
		for k in points.size():
			var q: Vector3 = points[k]
			if q.distance_to(c) <= VANTAGE_CLUSTER_RADIUS:
				merged = true
				break
		if not merged:
			points.append(c)
	return points

