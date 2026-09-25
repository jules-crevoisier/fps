## SpawnPick.gd
## Sélection de spawn PURE (.orchestrator/maps-spec-v2.md §7.6) : parmi
## `points`, choisit celui qui maximise la distance au `enemies` (joueurs
## ennemis VIVANTS) le plus proche — "every respawn picks the point furthest
## from the nearest living enemy" (§5.6, la parade Wasteland au spawn-kill,
## appliquée à `GameWorld._get_spawn_position` pour TOUTES les maps : ça
## n'aggrave jamais une map symétrique, et ça corrige un vrai problème sur
## les asymétriques). Sans ennemi vivant (début de partie, aucun adversaire
## encore spawné), ou `points` vide, retombe sur `cursor` (l'ancien tourniquet
## round-robin) pour ne rien changer au comportement existant.
class_name SpawnPick
extends RefCounted

# ======================================================================
#  CÂBLAGE (LD-23, relance de la vague 24 — voir le git blame de ce bloc
#  pour l'ancien état "code mort" refusé par QA). `pick_spawn_set()` et
#  `pick_best_hardpoint()` restent PURES et INCHANGÉES depuis leur écriture
#  (38/38 verts, voir test_spawn_pick.gd) ; ce qui a changé, c'est que
#  `scripts/networking/GameWorld.gd` les appelle désormais réellement :
#    - `GameWorld._get_spawn_position` (spawn d'UN joueur — respawn après
#      mort, rejoint en cours de match) utilise `pick_best_hardpoint` au lieu
#      de `pick_best` : `zone_active` vient du mode courant (HardpointMode,
#      lu par duck-typing — hors périmètre de cette tâche) et vaut faux pour
#      tout mode sans zone (TDM, modes à manches), ce qui retombe strictement
#      sur l'ancien comportement `pick_best` (voir la propriété testée
#      `pick_best_hardpoint_zone_inactive_matches_plain_pick_best`).
#    - `GameWorld._get_team_spawn_positions` (nouveau) appelle
#      `pick_spawn_set` pour choisir EN UN LOT les spawns de plusieurs
#      joueurs de la MÊME équipe qui apparaissent à la même seconde —
#      remplissage initial des bots (`_sync_team_bots`) et respawn de manche
#      (`respawn_all_for_round`, aussi atteint par `RoundMode.
#      _respawn_all_for_round`). C'est ce lot qui corrige le bug de
#      télémétrie d'origine (4 membres d'une équipe sur le même point).
#      En zone Hardpoint active, l'appelant PRÉ-FILTRE d'abord les points
#      dangereux (`is_hardpoint_hazard`, avec repli sur la liste complète si
#      ça ne laisse pas assez de points pour tout le lot) : `pick_spawn_set`
#      elle-même ignore toujours la notion de zone (fonction pure LD-02,
#      non modifiée par cette tâche), le filtrage est un choix de l'appelant.
#    - `tools/bot_smoke.gd` agrège désormais le PREMIER `Telemetry.
#      EVENT_SPAWN` de chaque joueur (position "à t0") et `tools/review/
#      report.py` lui donne sa propre section dans le rapport.
# ======================================================================

# ======================================================================
#  score()/pick_best() — spawns dynamiques notés (LD-02, docs/research/
#  03_level_design.md §2.4/§5) : ajoute à la seule distance ennemie (voir
#  `safest` ci-dessous, laissée INCHANGÉE — tests/modes/test_halftime.gd la
#  teste directement) la ligne de vue (CoD BO7 : "avoid spawning near a
#  visible enemy"), les alliés proches et la mémoire des morts récentes,
#  comme Halo 3 (§2.4 : base 1000, allié proche +500, ennemi proche -500,
#  mort récente sur place -700 qui remonte avec l'âge). Fonctions PURES :
#  `los_fn` (Callable(point: Vector3, enemy_pos: Vector3) -> bool) est
#  injectée par l'appelant (raycast réel côté GameWorld, bouchon en test) —
#  aucun accès à l'arbre de scène ni à la physique ici.
# ======================================================================

const _BASE_SCORE := 1000.0

## Bande de pression de distance ennemie (même bande que la ligne de vue,
## voir acceptance LD-02 : "à moins de 30 m").
const _ENEMY_PRESSURE_RANGE := 30.0
const _ENEMY_PRESSURE_PENALTY := 500.0

## Ligne de vue ennemie : pénalité dominante, pour qu'un point vu par un
## ennemi vivant à moins de 30 m ne soit JAMAIS choisi s'il existe une
## alternative moins pénalisée (acceptance LD-02).
const _ENEMY_LOS_RANGE := 30.0
const _ENEMY_LOS_PENALTY := 100000.0

## Allié vivant proche : bonus de regroupement (Halo 3 §2.4).
const _ALLY_NEAR_RANGE := 20.0
const _ALLY_NEAR_BONUS := 500.0

## Mort récente d'un allié : pénalité qui décroît avec l'âge, nulle à partir
## de 5 s (acceptance LD-02 : "un allié est mort il y a moins de 5 s").
const _RECENT_DEATH_WINDOW_S := 5.0
const _RECENT_DEATH_RANGE := 10.0
const _RECENT_DEATH_PENALTY := 700.0

## Note un point de spawn candidat. `enemies`/`allies` : positions (Vector3)
## de joueurs VIVANTS. `recent_deaths` : Array de Dictionary {"pos": Vector3,
## "age": float} (secondes écoulées depuis la mort) — typiquement les morts
## de la MÊME équipe que le joueur qui va spawn (voir GameWorld). `los_fn` :
## Callable(point, enemy_pos) -> bool, vrai si l'ennemi verrait un joueur
## posté sur `point`. Une Callable invalide (`Callable()`) désactive
## simplement la pénalité de ligne de vue (repli sur la seule pression de
## distance), sans erreur.
static func score(point: Vector3, enemies: Array, allies: Array, recent_deaths: Array, los_fn: Callable) -> float:
	var s := _BASE_SCORE

	for e in enemies:
		var enemy_pos: Vector3 = e
		var d := point.distance_to(enemy_pos)
		if d < _ENEMY_PRESSURE_RANGE:
			s -= _ENEMY_PRESSURE_PENALTY * (1.0 - d / _ENEMY_PRESSURE_RANGE)
		if d < _ENEMY_LOS_RANGE and los_fn.is_valid() and bool(los_fn.call(point, enemy_pos)):
			s -= _ENEMY_LOS_PENALTY

	for a in allies:
		var ally_pos: Vector3 = a
		var d := point.distance_to(ally_pos)
		if d < _ALLY_NEAR_RANGE:
			s += _ALLY_NEAR_BONUS * (1.0 - d / _ALLY_NEAR_RANGE)

	for rd in recent_deaths:
		var age: float = float(rd.get("age", INF))
		if age >= _RECENT_DEATH_WINDOW_S:
			continue
		var death_pos: Vector3 = rd.get("pos", point)
		var dd := point.distance_to(death_pos)
		if dd < _RECENT_DEATH_RANGE:
			var proximity := 1.0 - dd / _RECENT_DEATH_RANGE
			var freshness := 1.0 - age / _RECENT_DEATH_WINDOW_S
			s -= _RECENT_DEATH_PENALTY * proximity * freshness

	return s

## Choisit, parmi `points`, l'indice qui maximise `score(...)`. Égalité (à
## 0.01 près) départagée par `cursor` — même convention que `safest`
## ci-dessous (round-robin stable plutôt qu'un choix arbitraire).
static func pick_best(points: Array, enemies: Array, allies: Array, recent_deaths: Array, los_fn: Callable, cursor: int) -> int:
	if points.is_empty():
		return 0
	var cursor_idx := cursor % points.size()
	var scores: Array = []
	var best := -INF
	for i in points.size():
		var sc := score(points[i], enemies, allies, recent_deaths, los_fn)
		scores.append(sc)
		if sc > best:
			best = sc
	if absf(scores[cursor_idx] - best) < 0.01:
		return cursor_idx
	for i in points.size():
		if absf(scores[i] - best) < 0.01:
			return i
	return cursor_idx

static func safest(points: Array, enemies: Array, cursor: int) -> int:
	if points.is_empty():
		return 0
	var cursor_idx := cursor % points.size()
	if enemies.is_empty():
		return cursor_idx
	var dists: Array = []
	var best_dist := -1.0
	for i in points.size():
		var p: Vector3 = points[i]
		var nearest := INF
		for e in enemies:
			var d: float = p.distance_to(e as Vector3)
			if d < nearest:
				nearest = d
		dists.append(nearest)
		if nearest > best_dist:
			best_dist = nearest
	# Égalité (à 1 cm près) : le tourniquet départage, comme un round-robin
	# stable plutôt qu'un choix arbitraire entre points à distance égale.
	if absf(dists[cursor_idx] - best_dist) < 0.01:
		return cursor_idx
	for i in points.size():
		if absf(dists[i] - best_dist) < 0.01:
			return i
	return cursor_idx

# ======================================================================
#  pick_spawn_set() — anti-empilement (LD-23, docs/research/09_wasteland_
#  vertical_slice.md §c.4 et R17 : « Halo 1 : un spawn se bloque à ≤ 3 m »,
#  télémétrie ayant montré les 4 membres d'une équipe apparaître sur LE
#  MÊME point). Choisit, en UNE fois, `count` points DISTINCTS parmi
#  `points` pour des spawns simultanés ("de la même seconde" — typiquement
#  les 4 joueurs d'une équipe au tout début du match) en imposant un
#  plancher DUR de `min_separation` mètres entre CHAQUE paire de points
#  choisis dans ce même lot.
#
#  Ce plancher est ce qui manque à un simple enchaînement de `pick_best` :
#  le bonus « allié proche » de `score()` récompenserait au contraire un
#  point collé au précédent — c'est la cause structurelle de l'empilement
#  observé. Parmi les points qui respectent le plancher, on retombe sur
#  `pick_best` (ennemis, alliés déjà choisis DANS CE LOT, morts récentes,
#  ligne de vue) pour départager : l'équipe reste groupée autant que le
#  plancher le permet, elle n'est pas dispersée au hasard.
#
#  Repli sans alternative (même principe que `pick_best`/`safest` face à
#  un danger partout : jamais d'échec) : si AUCUN point restant ne
#  respecte le plancher vis-à-vis des points déjà choisis, on choisit
#  celui qui maximise la distance minimale aux points déjà choisis (le
#  moins empilé) plutôt que d'échouer ou de dupliquer un indice.
#
#  Limite connue (heuristique gloutonne, PAS une recherche exhaustive) :
#  sur un nuage de points pathologique construit exprès pour piéger l'ordre
#  de sélection, un agencement valide peut exister sans que l'algorithme le
#  trouve. Sur des marqueurs de spawn réels (répartis sur des dizaines de
#  mètres, `min_separation` = 3 m), ce cas ne se produit pas — voir la
#  propriété testée en fuzz dans test_spawn_pick.gd. Une recherche exacte
#  (backtracking) serait hors de proportion avec le contrat de cette tâche.
#
#  Retourne toujours exactement `mini(count, points.size())` indices,
#  tous distincts (jamais de doublon, jamais de dépassement de `points`).
# ======================================================================
static func pick_spawn_set(points: Array, count: int, enemies: Array, allies: Array, recent_deaths: Array, los_fn: Callable, cursor: int, min_separation: float = 3.0) -> Array[int]:
	var chosen: Array[int] = []
	if points.is_empty() or count <= 0:
		return chosen
	var chosen_positions: Array = []
	var total := mini(count, points.size())
	for _n in range(total):
		var candidates: Array[int] = []
		for i in points.size():
			if i in chosen:
				continue
			var pos: Vector3 = points[i]
			var too_close := false
			for cp in chosen_positions:
				if pos.distance_to(cp) < min_separation:
					too_close = true
					break
			if not too_close:
				candidates.append(i)
		if candidates.is_empty():
			# Aucune alternative respectant le plancher : au moins choisir
			# le point le moins empilé (distance minimale aux déjà-choisis
			# la plus grande possible), jamais un doublon.
			var best_i := -1
			var best_min_dist := -1.0
			for i in points.size():
				if i in chosen:
					continue
				var pos2: Vector3 = points[i]
				var min_dist := INF
				for cp in chosen_positions:
					min_dist = minf(min_dist, pos2.distance_to(cp))
				if min_dist > best_min_dist:
					best_min_dist = min_dist
					best_i = i
			chosen.append(best_i)
			chosen_positions.append(points[best_i])
			continue
		var sub_points: Array = []
		for i in candidates:
			sub_points.append(points[i])
		var local_idx := pick_best(sub_points, enemies, allies + chosen_positions, recent_deaths, los_fn, cursor)
		var real_idx: int = candidates[local_idx]
		chosen.append(real_idx)
		chosen_positions.append(points[real_idx])
	return chosen

# ======================================================================
#  Zone active Hardpoint (LD-23, §c.4 : « Jamais dans la zone active, ni à
#  ≤ 15 m d'elle, ni en ligne de vue d'elle à ≤ 25 m [...] s'il existe une
#  alternative »). Fonctions PURES : la zone est décrite par son centre et
#  un rayon horizontal (le cercle circonscrit à sa boîte — ex. 10×4×10 m
#  => rayon ≈ 7,1 m, voir `MapSetup`/`hp_size`) ; `hp_los_fn` suit la même
#  convention que `los_fn` de `score()` (Callable(point, zone_center) ->
#  bool, injectée par l'appelant — raycast réel côté GameWorld, bouchon en
#  test), et une Callable invalide désactive simplement la pénalité de
#  ligne de vue (repli sur le seul buffer de distance).
# ======================================================================

## Distance de sécurité (buffer) autour de la zone active — R17/§c.4.
const _HP_ZONE_BUFFER := 15.0
## Portée de ligne de vue vers la zone active (§c.4, même principe que
## _ENEMY_LOS_RANGE mais appliqué à l'objectif plutôt qu'à un ennemi).
const _HP_ZONE_LOS_RANGE := 25.0
## Pénalités dominantes : plus grandes que toute combinaison possible des
## autres facteurs de `score()`, garantissant qu'un point dangereux n'est
## JAMAIS choisi s'il existe une alternative sans danger (même principe que
## `_ENEMY_LOS_PENALTY`, voir la propriété testée en fuzz).
const _HP_ZONE_PENALTY := 1000000.0
const _HP_LOS_PENALTY := 1000000.0

## Vrai si `point` est dans la zone active, à ≤ 15 m de son bord, ou en
## ligne de vue de son centre à ≤ 25 m de son bord : un point « dangereux »
## à éviter en Hardpoint s'il existe une alternative.
static func is_hardpoint_hazard(point: Vector3, zone_center: Vector3, zone_radius: float, hp_los_fn: Callable) -> bool:
	var dist_to_boundary := maxf(0.0, point.distance_to(zone_center) - zone_radius)
	if dist_to_boundary <= _HP_ZONE_BUFFER:
		return true
	if dist_to_boundary <= _HP_ZONE_LOS_RANGE and hp_los_fn.is_valid() and bool(hp_los_fn.call(point, zone_center)):
		return true
	return false

## Pénalité Hardpoint à retrancher du score() d'un point (0.0 si sûr, donc
## sans effet en dehors d'une manche Hardpoint active).
static func hardpoint_penalty(point: Vector3, zone_center: Vector3, zone_radius: float, hp_los_fn: Callable) -> float:
	var p := 0.0
	var dist_to_boundary := maxf(0.0, point.distance_to(zone_center) - zone_radius)
	if dist_to_boundary <= _HP_ZONE_BUFFER:
		p += _HP_ZONE_PENALTY
	if dist_to_boundary <= _HP_ZONE_LOS_RANGE and hp_los_fn.is_valid() and bool(hp_los_fn.call(point, zone_center)):
		p += _HP_LOS_PENALTY
	return p

## `pick_best`, complété par la pénalité Hardpoint : combine `score()`
## (LD-02 : ennemis/alliés/morts récentes/ligne de vue) et
## `hardpoint_penalty()` (LD-23 : zone active). `zone_active` à false
## désactive toute pénalité Hardpoint (repli identique à `pick_best` pur) —
## à utiliser en TDM, ou en Hardpoint hors manche active (ex. juste avant
## l'ouverture de la première zone).
static func pick_best_hardpoint(points: Array, enemies: Array, allies: Array, recent_deaths: Array, los_fn: Callable, zone_active: bool, zone_center: Vector3, zone_radius: float, hp_los_fn: Callable, cursor: int) -> int:
	if points.is_empty():
		return 0
	var cursor_idx := cursor % points.size()
	var scores: Array = []
	var best := -INF
	for i in points.size():
		var sc := score(points[i], enemies, allies, recent_deaths, los_fn)
		if zone_active:
			sc -= hardpoint_penalty(points[i], zone_center, zone_radius, hp_los_fn)
		scores.append(sc)
		if sc > best:
			best = sc
	if absf(scores[cursor_idx] - best) < 0.01:
		return cursor_idx
	for i in points.size():
		if absf(scores[i] - best) < 0.01:
			return i
	return cursor_idx
