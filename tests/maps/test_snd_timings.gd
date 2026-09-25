## test_snd_timings.gd
## LD-05 (docs/research/03_level_design.md §3.5/§5, tâche "Mesure automatique
## des timings R&D") : mesure GÉOMÉTRIQUE, sur le navmesh RÉEL bâti (comme
## `test_navmesh.gd`, mais dédié à ces deux métriques), pour les 4 maps 4v4
## qui déclarent `site_a`/`site_b` (Port-Ferraille, Val-Poussière, Saint-Ombre,
## Col du Vautour — La Fosse/Le Belvédère sont des arènes Duel/Duo sans site,
## couvertes par LD-09).
##
## 1. Rotation A<->B au sprint : longueur du CHEMIN de navigation (pas à vol
##    d'oiseau) entre les deux sites, divisée par `MovementConfig.sprint_speed`
##    (8,2 m/s par défaut, lu depuis la vraie ressource — pas deviné). Cible
##    §3.5 : 7-12 s (15-27 % de notre bombe de 45 s, contre 10-15 s / 40 s
##    côté CS). Le point de départ/arrivée exact n'est PAS le marqueur brut de
##    `site_a`/`site_b` (`Layouts.gd`, centre vertical de la zone — souvent
##    ~1,5 m au-dessus du sol) mais sa projection RÉELLE ET ATTEIGNABLE au
##    sol, via `_grounded()` : voir sa doc, "Recast marque aussi le dessus
##    plat d'un couvert proche comme un îlot marchable À PART ENTIÈRE"
##    (`BotSpots.gd::_sample_navmesh`) — un point de requête assez proche en
##    hauteur d'un de ces îlots isolés s'y accroche si on l'utilise tel quel
##    comme DÉPART d'un chemin (aucun voisin, chemin qui reste sur place).
## 2. Entrées par site : un site a besoin d'au moins 3 accès distincts
##    (§2.2/§2.5 : "chaque position forte a besoin d'au moins 3 entrées").
##    Mesuré en échantillonnant un cercle de rayon 12 m autour du site (pas de
##    2°) et en projetant chaque point sur le navmesh via
##    `NavigationServer3D.map_get_closest_point` — même technique que
##    `BotSpots._sample_navmesh`. Un point est "sur le navmesh" si sa
##    projection retombe presque au même endroit en XZ (ENTRY_FLAT_TOLERANCE)
##    ET à une hauteur proche du site (ENTRY_HEIGHT_TOLERANCE, pour ignorer un
##    étage différent qui passerait par le même XZ). Chaque arc CONTINU de
##    points "sur le navmesh" (>= ENTRY_MIN_RUN échantillons, pour ignorer le
##    bruit d'un seul échantillon en bord de zone) est un portail distinct ;
##    un cercle entièrement ouvert (aucun mur autour du site) ne compte que
##    comme UN SEUL portail continu — un site sans aucun couvert n'a pas de
##    "3 entrées" au sens gameplay, il est simplement à l'air libre partout.
##
## Les deux mesures ne codent en dur AUCUNE porte ni position : elles
## réagissent directement à tout changement de géométrie dans `Layouts.gd`.
## Une map qui échoue est soit corrigée dans `Layouts.gd`, soit exemptée ici
## avec une justification écrite (même discipline que
## `test_navmesh.gd::KNOWN_PATH_RATIO_DEVIATIONS`) — jamais l'assertion
## affaiblie pour coller au résultat.
extends GdUnitTestSuite

const MapSetupScript := preload("res://scripts/levels/maps/MapSetup.gd")
const DEFAULT_MOVEMENT_PATH := "res://resources/movement/default_movement.tres"

const ROTATION_MIN_S := 7.0
const ROTATION_MAX_S := 12.0

const ENTRY_RADIUS := 12.0
const ENTRY_ANGLE_STEP_DEG := 2.0
const ENTRY_FLAT_TOLERANCE := 0.5
const ENTRY_HEIGHT_TOLERANCE := 2.5
const ENTRY_MIN_RUN := 2
const MIN_ENTRIES := 3

const MAX_SYNC_FRAMES := 20

## Exemptions écrites — historique LD-05 (2026-09-24) puis LD-10 (2026-09-24,
## même jour, vague suivante) qui reprend chaque écart mesuré par LD-05 et le
## corrige dans `Layouts.gd` par une pièce locale (jamais en déplaçant un
## site, un spawn ou un hardpoint, et toujours revérifié vert contre
## `test_navmesh.gd`/`test_layouts.gd`) :
##   port_ferraille   6.5 s (53.6 m) -> CORRIGÉ (`EastApproachBaffle`, 7.2 s)
##   val_poussiere    4.3 s (35.4 m) -> CORRIGÉ (`BackLotPalisade`, 8.3 s)
##   saint_ombre      6.0 s (49.2 m) -> CORRIGÉ (`SiteAApproachBaffle`, 7.1 s)
##   col_du_vautour   5.6 s (46.1 m) -> AMÉLIORÉ sans atteindre la cible
##     (`NarrowsBaffleA`/`B`, 6.0 s) — reste exempté ci-dessous.
## Col du Vautour reste exempté : le seul couloir nord vers Site B (bord de
## corniche x~4 à la façade du Dépôt·M x12, 8 m de large) est aussi le SEUL
## chemin `sp1 -> site_b` que verrouille `test_navmesh.gd` §5.6 — l'élargir
## davantage (testé jusqu'à quasi-fermeture, x4-11.5) casse ce chemin
## (`chemin arrivé à ... objectif Site B`) ; et toute pièce ajoutée près du
## pont central (x-5.5..5.5, z0, seule jonction est-ouest) ou de Site A
## allonge le chemin attaquant ouest -> Site A À L'IDENTIQUE du chemin de
## rotation (mesuré : ratio 2.53 -> 3.28, > 3.0, `test_navmesh.gd` §5.5) sans
## alternative de contournement sur cette carte. Voir le commentaire à côté
## de `NarrowsBaffleA`/`B` dans `Layouts.gd` pour le détail des tentatives.
## Exempté ICI, PAS DANS LE CODE : le test reste strict (7-12 s) pour toute
## future map.
const ROTATION_EXEMPTIONS := {
	"col_du_vautour": true,
}

## Entrées par site — Port-Ferraille Site A (LD-05, `QuayBaffle`) et
## Val-Poussière Site B (LD-10, `ArroyoRock` : scinde l'arc ouest complet de
## l'arroyo, [162°,198°], en deux portails distincts au lieu d'un seul — voir
## le commentaire à côté de la pièce dans `Layouts.gd`, y compris pourquoi la
## première tentative de LD-05, centrée sur la ligne directe attaquant ouest
## -> Site B, cassait le ratio atk/def de `test_navmesh.gd`) sont maintenant
## toutes deux corrigées. Aucune exemption d'entrées à ce jour.
const ENTRY_EXEMPTIONS := {}

var _next_offset_index := 0
var _sprint_speed: float = 8.2


func before() -> void:
	# Vitesse de sprint lue depuis la VRAIE ressource (MovementConfig,
	# LD-01/docs/MOVEMENT.md) plutôt que recopiée : reste correct si la
	# ressource change un jour de valeur.
	if ResourceLoader.exists(DEFAULT_MOVEMENT_PATH):
		var cfg: Resource = load(DEFAULT_MOVEMENT_PATH)
		if cfg != null:
			var v: Variant = cfg.get("sprint_speed")
			if v != null:
				_sprint_speed = float(v)


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


## Projection RÉELLE ET ATTEIGNABLE de `target` au sol, en chemin depuis
## `anchor` (un point sûr — un spawn, toujours au sol et connecté, cf.
## `test_navmesh.gd` qui l'atteste déjà pour chaque site). Une requête de
## chemin qui ARRIVE sur `target` retombe, via Detour, sur le point RÉEL le
## plus proche dans le COMPOSANT CONNEXE de `anchor` (chemin partiel si
## `target` lui-même n'est pas exactement dessus) — contrairement à une
## requête qui PARTIRAIT de `target` telle quelle (voir en-tête de fichier) :
## on n'utilise donc cette fonction que dans le sens sûr (vers le site).
func _grounded(map_rid: RID, anchor: Vector3, target: Vector3) -> Vector3:
	var path := await _wait_for_path(map_rid, anchor, target)
	if path.size() < 2:
		return target
	return path[path.size() - 1]


## Compte les portails distincts (arcs continus "sur le navmesh") sur un
## cercle de rayon ENTRY_RADIUS autour de `center` — voir en-tête de fichier.
static func _count_entries(map_rid: RID, center: Vector3) -> int:
	var n := int(360.0 / ENTRY_ANGLE_STEP_DEG)
	var walkable: Array[bool] = []
	walkable.resize(n)
	for i in n:
		var theta := deg_to_rad(float(i) * ENTRY_ANGLE_STEP_DEG)
		var probe := center + Vector3(cos(theta), 0.0, sin(theta)) * ENTRY_RADIUS
		var snapped := NavigationServer3D.map_get_closest_point(map_rid, probe)
		var flat_offset := Vector2(snapped.x - probe.x, snapped.z - probe.z).length()
		walkable[i] = flat_offset <= ENTRY_FLAT_TOLERANCE and absf(snapped.y - center.y) <= ENTRY_HEIGHT_TOLERANCE
	return _count_runs(walkable, ENTRY_MIN_RUN)


## Compte les runs circulaires de `true` de longueur >= `min_run` dans
## `flags` (le run à cheval sur la fin/le début du tableau est traité comme
## UN SEUL run, puisque le cercle n'a pas de coupure à l'index 0).
static func _count_runs(flags: Array[bool], min_run: int) -> int:
	var n := flags.size()
	if n == 0:
		return 0
	var start := 0
	while start < n and flags[start]:
		start += 1
	if start == n:
		return 1  # aucune coupure : cercle ouvert en continu, un seul portail
	var runs := 0
	var run_len := 0
	for steps in n:
		var idx := (start + steps) % n
		if flags[idx]:
			run_len += 1
		else:
			if run_len >= min_run:
				runs += 1
			run_len = 0
	if run_len >= min_run:
		runs += 1
	return runs


func test_port_ferraille() -> void:
	await _check_map("port_ferraille")


func test_val_poussiere() -> void:
	await _check_map("val_poussiere")


func test_saint_ombre() -> void:
	await _check_map("saint_ombre")


func test_col_du_vautour() -> void:
	await _check_map("col_du_vautour")


func _check_map(map_id: String) -> void:
	var built := _setup_map(map_id)
	var setup: MapSetup = built["setup"]
	var offset: Vector3 = built["offset"]
	await get_tree().physics_frame
	var nav := setup.nav_region
	assert_that(nav).append_failure_message(map_id).is_not_null()
	var data := Layouts.data_for(map_id)
	var map_rid := nav.get_navigation_map()

	var site_a: Vector3 = offset + (data["site_a"] as Dictionary)["pos"]
	var site_b: Vector3 = offset + (data["site_b"] as Dictionary)["pos"]
	# Ancres sûres (test_navmesh.gd atteste déjà sp0->site_a et sp1->site_b) :
	# la première position de spawn de chaque équipe.
	var sp0_anchor: Vector3 = offset + ((data["spawns"][0] as Array)[0] as Dictionary)["pos"]
	var sp1_anchor: Vector3 = offset + ((data["spawns"][1] as Array)[0] as Dictionary)["pos"]

	var site_a_ground := await _grounded(map_rid, sp0_anchor, site_a)
	var site_b_ground := await _grounded(map_rid, sp1_anchor, site_b)

	# 1. Rotation A<->B au sprint (chemin réel, pas à vol d'oiseau, entre les
	# deux projections AU SOL des sites — voir _grounded()).
	var path := await _wait_for_path(map_rid, site_a_ground, site_b_ground)
	assert_int(path.size()).append_failure_message("%s : aucun chemin site A -> site B" % map_id).is_greater_equal(2)
	var length := _path_length(path)
	var seconds := length / _sprint_speed
	if not (map_id in ROTATION_EXEMPTIONS):
		assert_float(seconds).append_failure_message(
			"%s rotation A<->B = %.1f s (chemin %.1f m @ %.1f m/s, cible %.0f-%.0f s)" % [map_id, seconds, length, _sprint_speed, ROTATION_MIN_S, ROTATION_MAX_S]
		).is_between(ROTATION_MIN_S, ROTATION_MAX_S)

	# 2. Entrées par site (>= 3 portails navmesh distincts, rayon 12 m ; centre
	# XZ du marqueur déclaré, hauteur RÉELLE au sol — même raison qu'au-dessus,
	# sinon le cercle se met à mi-hauteur d'un îlot isolé voisin au lieu du sol).
	var grounded_by_key := {"site_a": site_a_ground, "site_b": site_b_ground}
	for key in ["site_a", "site_b"]:
		var raw: Vector3 = offset + (data[key] as Dictionary)["pos"]
		var ground: Vector3 = grounded_by_key[key]
		var center := Vector3(raw.x, ground.y, raw.z)
		var entries := _count_entries(map_rid, center)
		var exempt_sites: Array = ENTRY_EXEMPTIONS.get(map_id, [])
		if not (key in exempt_sites):
			assert_int(entries).append_failure_message(
				"%s %s : %d portail(s) détecté(s) (rayon %.0f m, cible >= %d)" % [map_id, key, entries, ENTRY_RADIUS, MIN_ENTRIES]
			).is_greater_equal(MIN_ENTRIES)

	await _teardown(setup)
