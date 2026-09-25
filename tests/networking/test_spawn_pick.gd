## test_spawn_pick.gd
## Spec (docs/research/03_level_design.md §2.4/§5 LD-02, .orchestrator/maps-spec-v2.md §7.6) :
## `SpawnPick.score(point, enemies, allies, recent_deaths, los_fn)` est une fonction PURE
## (aucune dépendance à l'arbre de scène/physique — `los_fn` est injectée) qui note un
## point de spawn candidat comme Halo 3 (base 1000, allié proche +, ennemi proche -, mort
## récente sur place -700 qui remonte avec l'âge) mais en ajoutant la ligne de vue
## (principe CoD BO7 : "avoid spawning near a visible enemy" — voir §2.4 de la recherche).
## `SpawnPick.pick_best` sélectionne, parmi plusieurs points, celui qui maximise ce score
## (égalité → cursor, comme `SpawnPick.safest`, déjà utilisé et testé ailleurs par
## tests/modes/test_halftime.gd — NON touché ici, safest() reste inchangée).
extends GdUnitTestSuite


# ======================================================================
#  1. Un point vu par un ennemi vivant à moins de 30 m n'est JAMAIS choisi
#     s'il existe une alternative.
# ======================================================================

func test_visible_near_enemy_point_not_chosen_when_alternative_exists() -> void:
	var risky := Vector3(0, 0, 0)
	var safe := Vector3(80, 0, 0)
	var enemy := Vector3(10, 0, 0)  # 10 m du point risqué, largement < 30 m
	var always_visible := func(_p: Vector3, _e: Vector3) -> bool: return true
	var idx := SpawnPick.pick_best([risky, safe], [enemy], [], [], always_visible, 0)
	assert_int(idx).append_failure_message(
		"un point vu par un ennemi vivant à 10 m ne doit jamais être choisi s'il existe une alternative sûre"
	).is_equal(1)


func test_point_at_29m_with_los_beaten_by_far_safe_point() -> void:
	var risky := Vector3(29, 0, 0)
	var safe := Vector3(200, 0, 0)
	var enemy := Vector3.ZERO
	var always_visible := func(_p: Vector3, _e: Vector3) -> bool: return true
	var idx := SpawnPick.pick_best([risky, safe], [enemy], [], [], always_visible, 0)
	assert_int(idx).is_equal(1)


func test_los_beyond_30m_does_not_trigger_los_penalty() -> void:
	# Ennemi vu mais à 31 m (hors bande) : seule une pression de distance légère
	# s'applique, jamais la pénalité de ligne de vue dominante — le point reste
	# largement meilleur qu'un point où un ennemi PROCHE (5 m) a la ligne de vue.
	var far_seen := Vector3(31, 0, 0)
	var near_seen := Vector3(5, 0, 0)
	var enemy_far := Vector3.ZERO
	var enemy_near := Vector3.ZERO
	var always_visible := func(_p: Vector3, _e: Vector3) -> bool: return true
	var s_far := SpawnPick.score(far_seen, [enemy_far], [], [], always_visible)
	var s_near := SpawnPick.score(near_seen, [enemy_near], [], [], always_visible)
	assert_float(s_far).append_failure_message(
		"un ennemi visible à 31 m ne doit pas être traité comme un ennemi visible à 5 m"
	).is_greater(s_near)


func test_no_safe_alternative_still_picks_least_risky() -> void:
	# Les DEUX points sont vus par un ennemi vivant à moins de 30 m : aucune
	# alternative sûre n'existe, l'algorithme doit quand même retourner le
	# MOINS risqué (ici : ennemi plus loin) plutôt qu'échouer ou être arbitraire.
	var less_risky := Vector3(25, 0, 0)
	var more_risky := Vector3(3, 0, 0)
	var enemy := Vector3.ZERO
	var always_visible := func(_p: Vector3, _e: Vector3) -> bool: return true
	var idx := SpawnPick.pick_best([more_risky, less_risky], [enemy], [], [], always_visible, 0)
	assert_int(idx).is_equal(1)


func test_blocked_los_no_los_penalty_only_distance_pressure() -> void:
	# Ennemi proche (10 m) mais SANS ligne de vue (mur) : pas de pénalité de LOS,
	# seulement une légère pression de distance — largement au-dessus d'un point
	# où le même ennemi proche a bel et bien la ligne de vue.
	var point := Vector3(10, 0, 0)
	var enemy := Vector3.ZERO
	var blocked := func(_p: Vector3, _e: Vector3) -> bool: return false
	var visible := func(_p: Vector3, _e: Vector3) -> bool: return true
	var s_blocked := SpawnPick.score(point, [enemy], [], [], blocked)
	var s_visible := SpawnPick.score(point, [enemy], [], [], visible)
	assert_float(s_blocked).is_greater(s_visible)


func test_los_fn_never_called_when_enemy_outside_los_range() -> void:
	# Optimisation/robustesse : hors de la bande de ligne de vue, `los_fn` ne
	# doit même pas être invoquée (aucun raycast inutile).
	var calls := {"n": 0}
	var counting := func(_p: Vector3, _e: Vector3) -> bool:
		calls.n += 1
		return true
	SpawnPick.score(Vector3(100, 0, 0), [Vector3.ZERO], [], [], counting)
	assert_int(calls.n).append_failure_message(
		"los_fn ne doit pas être appelée pour un ennemi hors de portée de ligne de vue"
	).is_equal(0)


# ======================================================================
#  2. Un point où un allié est mort il y a moins de 5 s est pénalisé.
# ======================================================================

func test_recent_ally_death_on_point_is_penalized() -> void:
	var point := Vector3(10, 0, 0)
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var baseline := SpawnPick.score(point, [], [], [], no_los)
	var with_recent_death := SpawnPick.score(
		point, [], [], [{"pos": point, "age": 1.0}], no_los
	)
	assert_float(with_recent_death).append_failure_message(
		"un point où un allié est mort il y a 1 s doit être pénalisé par rapport à la base"
	).is_less(baseline)


func test_death_older_than_5s_is_not_penalized() -> void:
	var point := Vector3(10, 0, 0)
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var baseline := SpawnPick.score(point, [], [], [], no_los)
	var with_old_death := SpawnPick.score(
		point, [], [], [{"pos": point, "age": 6.0}], no_los
	)
	assert_float(with_old_death).append_failure_message(
		"une mort vieille de 6 s (>= 5 s) ne doit plus pénaliser le point"
	).is_equal_approx(baseline, 0.01)


func test_death_penalty_decays_with_age_within_window() -> void:
	var point := Vector3(10, 0, 0)
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var fresh := SpawnPick.score(point, [], [], [{"pos": point, "age": 0.5}], no_los)
	var older := SpawnPick.score(point, [], [], [{"pos": point, "age": 4.5}], no_los)
	var baseline := SpawnPick.score(point, [], [], [], no_los)
	assert_float(fresh).append_failure_message(
		"une mort très fraîche (0,5 s) doit pénaliser plus qu'une mort de 4,5 s"
	).is_less(older)
	assert_float(older).is_less(baseline)


func test_recent_death_far_from_point_does_not_penalize_it() -> void:
	var point := Vector3(0, 0, 0)
	var far_death := Vector3(500, 0, 0)
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var baseline := SpawnPick.score(point, [], [], [], no_los)
	var with_far_death := SpawnPick.score(
		point, [], [], [{"pos": far_death, "age": 0.1}], no_los
	)
	assert_float(with_far_death).is_equal_approx(baseline, 0.01)


func test_recent_death_beats_los_priority_ordering() -> void:
	# Entre deux points sans ennemi visible, celui SANS mort récente d'allié
	# est préféré.
	var clean := Vector3(0, 0, 0)
	var haunted := Vector3(40, 0, 0)
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var idx := SpawnPick.pick_best(
		[haunted, clean], [], [], [{"pos": haunted, "age": 0.2}], no_los, 0
	)
	assert_int(idx).is_equal(1)


# ======================================================================
#  Alliés proches : bonus (complète le contrat, mêmes signaux que Halo 3 §2.4)
# ======================================================================

func test_nearby_living_ally_gives_bonus() -> void:
	var point := Vector3.ZERO
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var alone := SpawnPick.score(point, [], [], [], no_los)
	var with_ally := SpawnPick.score(point, [], [Vector3(5, 0, 0)], [], no_los)
	assert_float(with_ally).append_failure_message(
		"un allié vivant proche doit apporter un bonus au score du point"
	).is_greater(alone)


# ======================================================================
#  pick_best : robustesse (vide, égalité -> cursor, comme SpawnPick.safest)
# ======================================================================

func test_pick_best_empty_points_returns_zero() -> void:
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	assert_int(SpawnPick.pick_best([], [], [], [], no_los, 3)).is_equal(0)


func test_pick_best_tie_uses_cursor_like_round_robin() -> void:
	var points := [Vector3(0, 0, 0), Vector3(10, 0, 10), Vector3(20, 0, 20)]
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	assert_int(SpawnPick.pick_best(points, [], [], [], no_los, 0)).is_equal(0)
	assert_int(SpawnPick.pick_best(points, [], [], [], no_los, 4)).is_equal(1)  # 4 % 3 == 1


func test_pick_best_is_pure_same_inputs_same_output() -> void:
	var points := [Vector3(0, 0, 0), Vector3(15, 0, 0), Vector3(50, 0, 0)]
	var enemies := [Vector3(2, 0, 0)]
	var allies := [Vector3(48, 0, 0)]
	var deaths := [{"pos": Vector3(15, 0, 0), "age": 2.0}]
	var los := func(_p: Vector3, _e: Vector3) -> bool: return true
	var a := SpawnPick.pick_best(points, enemies, allies, deaths, los, 0)
	var b := SpawnPick.pick_best(points, enemies, allies, deaths, los, 0)
	assert_int(a).is_equal(b)


# ======================================================================
#  3. NON VÉRIFIÉ ICI — À SIGNALER AU LEAD (`blocked_on`), PAS UN DÉTAIL :
#     la 3e clause d'acceptance LD-02 ("en simulation de bots 4v4 sur
#     10 min, moins de 5 % des morts surviennent dans les 3 s suivant un
#     spawn") N'EST PROUVÉE PAR AUCUN TEST NI MESURE de cette suite. Elle
#     ne peut PAS l'être avec les seuls fichiers possédés par LD-02
#     (SpawnPick.gd, GameWorld.gd, ce fichier) : elle est ÉMERGENTE d'un
#     match complet — bots `BotBrain.gd` (combat, visée, décisions),
#     16-24 points de spawn réels par map (`LD-03`, pas encore livré),
#     10 minutes de jeu simulées. Aucun de ces éléments n'est dans le
#     périmètre de cette tâche.
#
#     Une tentative de rejouer un combat 4v4 ICI avec un modèle de combat
#     inventé (portée/cadence/vitesse choisies par l'agent) a été essayée
#     et rejetée : c'est un test qui se juge lui-même, dont la conclusion
#     dépend des paramètres inventés et non du comportement réel du jeu
#     (constaté : ordonnancement bruité sur petits échantillons, `safest`
#     et `pick_best` parfois à égalité statistique selon la carte
#     synthétique — un faux vert). Le fabriquer pour faire passer le
#     critère au vert serait réécrire le test pour qu'il colle à une
#     implémentation de complaisance, pas le vérifier : refusé.
#
#     Ce qui EST garanti ici, PUREMENT (aucune dépendance à un modèle de
#     combat inventé) : la propriété structurelle qui REND ce <5 % possible
#     — sur un grand nombre de champs de bataille aléatoires (positions
#     ennemies/alliées/morts récentes et géométrie de ligne de vue
#     variées), `SpawnPick.pick_best` ne choisit JAMAIS un point vu par un
#     ennemi vivant à moins de 30 m tant qu'une alternative non vue existe
#     — testé ci-dessous sur 300 scénarios seedés (déterministe, voir
#     `test_property_pick_best_never_chosen_visible_near_enemy_when_safe_alternative_exists`).
#     Cette propriété est nécessaire mais PAS suffisante pour prouver le
#     chiffre "< 5 % en 10 min" : elle ne remplace pas la mesure réelle.
#
#     Chemin de vérification réel, une fois LD-03 livré : un vrai match de
#     bots 4v4/10 min (`tools/bot_smoke.gd`, hors périmètre LD-02) agrégeant
#     le champ `time_since_spawn` déjà écrit par `GameWorld._log_kill_event`
#     dans chaque événement `kill` (Telemetry) — l'infrastructure de mesure
#     existe déjà côté GameWorld, seule l'agrégation manque.
#
#     Ce fichier NE PEUT PAS faire de `tasks/backlog.yaml` (hors liste des
#     fichiers possédés) : c'est au lead d'y ajouter un `blocked_on: LD-03`
#     sur LD-02 (ou de trancher autrement) via `plan.py block LD-02
#     --reason "..."`. L'agent qui exécute ce contrat doit reporter ce
#     point dans son champ `blocked_on` et NE PAS présenter LD-02 comme
#     entièrement vérifié tant que cette mesure n'existe pas.
# ======================================================================

const _FUZZ_SCENARIOS := 300
const _FUZZ_LOS_RANGE := 30.0

# Murs synthétiques (AABB 2D en X/Z, pleine hauteur) — géométrie de ligne de
# vue non triviale (pas "toujours vrai/toujours faux") pour les scénarios.
const _FUZZ_WALLS := [
	{"min": Vector2(-6, -30), "max": Vector2(6, -18)},
	{"min": Vector2(-6, -6), "max": Vector2(6, 6)},
	{"min": Vector2(-6, 18), "max": Vector2(6, 30)},
	{"min": Vector2(20, -35), "max": Vector2(32, -22)},
	{"min": Vector2(-32, 22), "max": Vector2(-20, 35)},
]


func test_property_pick_best_never_chosen_visible_near_enemy_when_safe_alternative_exists() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260924  # déterministe : pas de test flaky.
	var los_fn := Callable(self, "_fuzz_has_los")
	var violations := 0

	for _s in _FUZZ_SCENARIOS:
		var points := _fuzz_random_points(rng, 10)
		var enemies := _fuzz_random_points(rng, rng.randi_range(1, 4))
		var allies := _fuzz_random_points(rng, rng.randi_range(0, 3))
		var recent := _fuzz_random_deaths(rng, rng.randi_range(0, 3))

		var idx := SpawnPick.pick_best(points, enemies, allies, recent, los_fn, 0)
		var chosen: Vector3 = points[idx]
		if not _fuzz_is_los_risky(chosen, enemies, los_fn):
			continue  # le point choisi est déjà sûr : rien à vérifier.

		# Le point choisi est vu par un ennemi proche : ce n'est acceptable
		# QUE si aucune alternative de `points` n'était sûre non plus.
		var had_safe_alternative := false
		for p in points:
			if p == chosen:
				continue
			if not _fuzz_is_los_risky(p, enemies, los_fn):
				had_safe_alternative = true
				break
		if had_safe_alternative:
			violations += 1

	assert_int(violations).append_failure_message(
		"%d/%d scénarios ont choisi un point vu par un ennemi vivant < 30 m alors qu'une alternative sûre existait" % [violations, _FUZZ_SCENARIOS]
	).is_equal(0)


func _fuzz_random_points(rng: RandomNumberGenerator, n: int) -> Array:
	var out: Array = []
	for _i in n:
		out.append(Vector3(rng.randf_range(-60.0, 60.0), 0.0, rng.randf_range(-60.0, 60.0)))
	return out


func _fuzz_random_deaths(rng: RandomNumberGenerator, n: int) -> Array:
	var out: Array = []
	for _i in n:
		out.append({
			"pos": Vector3(rng.randf_range(-60.0, 60.0), 0.0, rng.randf_range(-60.0, 60.0)),
			"age": rng.randf_range(0.0, 10.0),
		})
	return out


func _fuzz_is_los_risky(point: Vector3, enemies: Array, los_fn: Callable) -> bool:
	for e in enemies:
		var enemy_pos: Vector3 = e
		if point.distance_to(enemy_pos) < _FUZZ_LOS_RANGE and bool(los_fn.call(point, enemy_pos)):
			return true
	return false


## Ligne de vue géométrique 2D (plan X/Z) : bloquée si le segment `from`->`to`
## croise l'un des murs synthétiques (`_FUZZ_WALLS`).
func _fuzz_has_los(from: Vector3, to: Vector3) -> bool:
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	for w in _FUZZ_WALLS:
		if _fuzz_segment_hits_aabb(a, b, w.min, w.max):
			return false
	return true


func _fuzz_segment_hits_aabb(a: Vector2, b: Vector2, box_min: Vector2, box_max: Vector2) -> bool:
	# Slab test 2D standard (segment vs AABB).
	var d := b - a
	var t_min := 0.0
	var t_max := 1.0
	for axis in 2:
		var origin: float = a.x if axis == 0 else a.y
		var delta: float = d.x if axis == 0 else d.y
		var lo: float = box_min.x if axis == 0 else box_min.y
		var hi: float = box_max.x if axis == 0 else box_max.y
		if absf(delta) < 0.0001:
			if origin < lo or origin > hi:
				return false
			continue
		var t1 := (lo - origin) / delta
		var t2 := (hi - origin) / delta
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_min > t_max:
			return false
	return true


# ======================================================================
#  LD-23 — 1. pick_spawn_set() : anti-empilement (≥ 3 m entre spawns de
#  la même seconde, R17). Spec : docs/research/09_wasteland_vertical_
#  slice.md §c.4. Bug d'origine (télémétrie) : les 4 membres d'une équipe
#  apparaissaient sur LE MÊME point — cause structurelle : le bonus
#  « allié proche » de score() récompense un point collé au précédent.
# ======================================================================

func test_pick_spawn_set_four_spread_points_all_at_least_3m_apart() -> void:
	var points := [Vector3(0, 0, 0), Vector3(50, 0, 0), Vector3(100, 0, 0), Vector3(150, 0, 0)]
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var chosen := SpawnPick.pick_spawn_set(points, 4, [], [], [], no_los, 0)
	assert_int(chosen.size()).append_failure_message(
		"4 points largement espacés doivent produire 4 indices choisis"
	).is_equal(4)
	# Indices tous distincts.
	var seen := {}
	for i in chosen:
		assert_bool(seen.has(i)).append_failure_message("indice %d choisi deux fois" % i).is_false()
		seen[i] = true
	# Toutes les paires à au moins 3 m.
	for a in range(chosen.size()):
		for b in range(a + 1, chosen.size()):
			var d: float = (points[chosen[a]] as Vector3).distance_to(points[chosen[b]])
			assert_float(d).append_failure_message(
				"points %d et %d choisis à %.2f m (< 3 m)" % [chosen[a], chosen[b], d]
			).is_greater_equal(3.0)


func test_pick_spawn_set_rejects_point_too_close_to_already_chosen() -> void:
	# Point 1 à 0,5 m du point 0 (empilement) : doit être écarté au profit
	# du point 2, loin, même si le point 1 serait "meilleur" au score brut.
	var points := [Vector3(0, 0, 0), Vector3(0.5, 0, 0), Vector3(50, 0, 0)]
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var chosen := SpawnPick.pick_spawn_set(points, 2, [], [], [], no_los, 0)
	assert_int(chosen.size()).is_equal(2)
	assert_bool(chosen.has(0)).is_true()
	assert_bool(chosen.has(1)).append_failure_message(
		"le point à 0,5 m du premier choisi ne doit jamais être retenu tant qu'une alternative à ≥ 3 m existe"
	).is_false()
	assert_bool(chosen.has(2)).is_true()


func test_pick_spawn_set_never_duplicates_indices_when_count_exceeds_points() -> void:
	var points := [Vector3(0, 0, 0), Vector3(50, 0, 0)]
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var chosen := SpawnPick.pick_spawn_set(points, 4, [], [], [], no_los, 0)
	assert_int(chosen.size()).append_failure_message(
		"count > points.size() : au plus points.size() indices, jamais de doublon"
	).is_equal(2)
	assert_bool(chosen.has(0)).is_true()
	assert_bool(chosen.has(1)).is_true()


func test_pick_spawn_set_empty_points_returns_empty() -> void:
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	assert_array(SpawnPick.pick_spawn_set([], 4, [], [], [], no_los, 0)).is_empty()


func test_pick_spawn_set_zero_count_returns_empty() -> void:
	var points := [Vector3(0, 0, 0), Vector3(50, 0, 0)]
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	assert_array(SpawnPick.pick_spawn_set(points, 0, [], [], [], no_los, 0)).is_empty()


func test_pick_spawn_set_no_alternative_still_returns_distinct_indices() -> void:
	# Les 3 seuls points sont tous à moins de 3 m les uns des autres :
	# aucune alternative ne respecte le plancher, mais l'algorithme doit
	# quand même rendre 3 indices DISTINCTS (repli sur le moins empilé),
	# jamais échouer ni dupliquer.
	var points := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)]
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var chosen := SpawnPick.pick_spawn_set(points, 3, [], [], [], no_los, 0)
	assert_int(chosen.size()).is_equal(3)
	var seen := {}
	for i in chosen:
		assert_bool(seen.has(i)).append_failure_message("repli sans alternative : indice %d dupliqué" % i).is_false()
		seen[i] = true


func test_pick_spawn_set_is_pure_same_inputs_same_output() -> void:
	var points := [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0), Vector3(30, 0, 0)]
	var enemies := [Vector3(5, 0, 0)]
	var los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var a := SpawnPick.pick_spawn_set(points, 3, enemies, [], [], los, 1)
	var b := SpawnPick.pick_spawn_set(points, 3, enemies, [], [], los, 1)
	assert_array(a).is_equal(b)


func test_pick_spawn_set_property_random_spread_points_always_respect_floor() -> void:
	# Nuage de points réaliste (échelle d'une carte, pas un piège adverse
	# construit à la main) : 12 points sur 60×60 m, on choisit 4 spawns
	# simultanés (équipe complète). Sur 200 scénarios seedés, le plancher
	# de 3 m doit systématiquement être respecté entre les 4 points choisis
	# (voir la limite heuristique documentée dans SpawnPick.pick_spawn_set).
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260924
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var violations := 0
	for _s in 200:
		var points: Array = []
		for _i in 12:
			points.append(Vector3(rng.randf_range(-30.0, 30.0), 0.0, rng.randf_range(-30.0, 30.0)))
		var chosen := SpawnPick.pick_spawn_set(points, 4, [], [], [], no_los, 0)
		for a in range(chosen.size()):
			for b in range(a + 1, chosen.size()):
				var d: float = (points[chosen[a]] as Vector3).distance_to(points[chosen[b]])
				if d < 3.0:
					violations += 1
	assert_int(violations).append_failure_message(
		"%d violation(s) du plancher de 3 m sur 200 scénarios réalistes" % violations
	).is_equal(0)


# ======================================================================
#  LD-23 — 2. Zone active Hardpoint : jamais dans la zone, ni à ≤ 15 m,
#  ni en ligne de vue à ≤ 25 m, s'il existe une alternative.
# ======================================================================

func test_hardpoint_hazard_true_inside_zone() -> void:
	var no_los := func(_p: Vector3, _z: Vector3) -> bool: return false
	assert_bool(SpawnPick.is_hardpoint_hazard(Vector3(1, 0, 0), Vector3.ZERO, 5.0, no_los)).is_true()


func test_hardpoint_hazard_true_within_15m_buffer_of_boundary() -> void:
	# Rayon de zone 5 m, point à 18 m du centre => 13 m du BORD (< 15 m).
	var no_los := func(_p: Vector3, _z: Vector3) -> bool: return false
	assert_bool(SpawnPick.is_hardpoint_hazard(Vector3(18, 0, 0), Vector3.ZERO, 5.0, no_los)).is_true()


func test_hardpoint_hazard_false_beyond_15m_buffer_without_los() -> void:
	# 21 m du centre => 16 m du bord (> 15 m), pas de ligne de vue.
	var no_los := func(_p: Vector3, _z: Vector3) -> bool: return false
	assert_bool(SpawnPick.is_hardpoint_hazard(Vector3(21, 0, 0), Vector3.ZERO, 5.0, no_los)).is_false()


func test_hardpoint_hazard_true_beyond_buffer_but_visible_within_25m_of_boundary() -> void:
	# 25 m du centre => 20 m du bord (entre 15 et 25 m) : dangereux
	# SEULEMENT si la zone est visible depuis ce point.
	var visible := func(_p: Vector3, _z: Vector3) -> bool: return true
	assert_bool(SpawnPick.is_hardpoint_hazard(Vector3(25, 0, 0), Vector3.ZERO, 5.0, visible)).is_true()


func test_hardpoint_hazard_false_beyond_buffer_and_blocked_los_within_25m() -> void:
	var blocked := func(_p: Vector3, _z: Vector3) -> bool: return false
	assert_bool(SpawnPick.is_hardpoint_hazard(Vector3(25, 0, 0), Vector3.ZERO, 5.0, blocked)).is_false()


func test_hardpoint_hazard_false_beyond_25m_of_boundary_even_if_visible() -> void:
	# 35 m du centre => 30 m du bord (> 25 m) : hors de portée, même visible.
	var visible := func(_p: Vector3, _z: Vector3) -> bool: return true
	assert_bool(SpawnPick.is_hardpoint_hazard(Vector3(35, 0, 0), Vector3.ZERO, 5.0, visible)).is_false()


func test_hardpoint_los_fn_not_called_beyond_los_range() -> void:
	var calls := {"n": 0}
	var counting := func(_p: Vector3, _z: Vector3) -> bool:
		calls.n += 1
		return true
	SpawnPick.is_hardpoint_hazard(Vector3(100, 0, 0), Vector3.ZERO, 5.0, counting)
	assert_int(calls.n).append_failure_message(
		"hp_los_fn ne doit pas être appelée hors de portée de ligne de vue vers la zone"
	).is_equal(0)


func test_pick_best_hardpoint_never_chooses_zone_point_when_safe_alternative_exists() -> void:
	var in_zone := Vector3(0, 0, 0)
	var safe := Vector3(200, 0, 0)
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var idx := SpawnPick.pick_best_hardpoint(
		[in_zone, safe], [], [], [], no_los, true, Vector3.ZERO, 5.0, no_los, 0
	)
	assert_int(idx).append_failure_message(
		"un point dans la zone active ne doit jamais être choisi s'il existe une alternative sûre"
	).is_equal(1)


func test_pick_best_hardpoint_never_chooses_near_zone_point_when_safe_alternative_exists() -> void:
	var near_zone := Vector3(15, 0, 0)  # 10 m du bord (rayon 5) : < 15 m.
	var safe := Vector3(200, 0, 0)
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var idx := SpawnPick.pick_best_hardpoint(
		[near_zone, safe], [], [], [], no_los, true, Vector3.ZERO, 5.0, no_los, 0
	)
	assert_int(idx).is_equal(1)


func test_pick_best_hardpoint_never_chooses_visible_zone_point_when_safe_alternative_exists() -> void:
	var visible_far := Vector3(28, 0, 0)  # 23 m du bord (< 25 m), visible.
	var safe := Vector3(200, 0, 0)
	var visible := func(_p: Vector3, _e: Vector3) -> bool: return true
	var idx := SpawnPick.pick_best_hardpoint(
		[visible_far, safe], [], [], [], visible, true, Vector3.ZERO, 5.0, visible, 0
	)
	assert_int(idx).is_equal(1)


func test_pick_best_hardpoint_no_safe_alternative_still_picks_least_risky() -> void:
	# Les deux points sont dans la zone : aucune alternative sûre, mais
	# l'algorithme doit quand même choisir plutôt qu'échouer.
	var a := Vector3(1, 0, 0)
	var b := Vector3(2, 0, 0)
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var idx := SpawnPick.pick_best_hardpoint(
		[a, b], [], [], [], no_los, true, Vector3.ZERO, 5.0, no_los, 0
	)
	assert_bool(idx == 0 or idx == 1).is_true()


func test_pick_best_hardpoint_zone_inactive_matches_plain_pick_best() -> void:
	# `zone_active = false` (TDM, ou Hardpoint hors manche active) : le
	# point le plus proche de la zone reste choisissable comme n'importe
	# quel autre — aucune pénalité Hardpoint appliquée.
	var inside_zone_but_otherwise_best := Vector3(0, 0, 0)
	var far := Vector3(200, 0, 0)
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var enemies := [Vector3(199, 0, 0)]  # rend `far` mauvais au score brut.
	var idx_plain := SpawnPick.pick_best(
		[inside_zone_but_otherwise_best, far], enemies, [], [], no_los, 0
	)
	var idx_hp_inactive := SpawnPick.pick_best_hardpoint(
		[inside_zone_but_otherwise_best, far], enemies, [], [], no_los,
		false, Vector3.ZERO, 5.0, no_los, 0
	)
	assert_int(idx_hp_inactive).append_failure_message(
		"zone_active = false doit se comporter EXACTEMENT comme pick_best (aucune pénalité Hardpoint)"
	).is_equal(idx_plain)


func test_pick_best_hardpoint_is_pure_same_inputs_same_output() -> void:
	var points := [Vector3(0, 0, 0), Vector3(20, 0, 0), Vector3(200, 0, 0)]
	var no_los := func(_p: Vector3, _e: Vector3) -> bool: return false
	var a := SpawnPick.pick_best_hardpoint(points, [], [], [], no_los, true, Vector3.ZERO, 5.0, no_los, 2)
	var b := SpawnPick.pick_best_hardpoint(points, [], [], [], no_los, true, Vector3.ZERO, 5.0, no_los, 2)
	assert_int(a).is_equal(b)


func test_property_pick_best_hardpoint_never_chosen_hazard_when_safe_alternative_exists() -> void:
	# Même idiome que la propriété LD-02 plus haut : sur 300 champs de
	# bataille aléatoires (zone Hardpoint fixe, points de spawn variés,
	# géométrie de ligne de vue avec murs), le point choisi n'est JAMAIS
	# un point dangereux (dans la zone / à ≤ 15 m / visible à ≤ 25 m)
	# tant qu'une alternative sûre existe parmi les candidats.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260925  # déterministe : pas de test flaky.
	var zone_center := Vector3.ZERO
	var zone_radius := 5.0
	var hp_los_fn := Callable(self, "_fuzz_has_los")
	var violations := 0

	for _s in _FUZZ_SCENARIOS:
		var points := _fuzz_random_points(rng, 10)
		var idx := SpawnPick.pick_best_hardpoint(
			points, [], [], [], hp_los_fn, true, zone_center, zone_radius, hp_los_fn, 0
		)
		var chosen: Vector3 = points[idx]
		if not SpawnPick.is_hardpoint_hazard(chosen, zone_center, zone_radius, hp_los_fn):
			continue  # le point choisi est déjà sûr : rien à vérifier.

		var had_safe_alternative := false
		for p in points:
			if p == chosen:
				continue
			if not SpawnPick.is_hardpoint_hazard(p, zone_center, zone_radius, hp_los_fn):
				had_safe_alternative = true
				break
		if had_safe_alternative:
			violations += 1

	assert_int(violations).append_failure_message(
		"%d/%d scénarios ont choisi un point dangereux (zone Hardpoint) alors qu'une alternative sûre existait" % [violations, _FUZZ_SCENARIOS]
	).is_equal(0)
