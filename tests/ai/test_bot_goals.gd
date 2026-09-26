## test_bot_goals.gd
## Spec (BOT-01, docs/research/02_bots_ai.md §4.1/§5, tasks/backlog.yaml) :
## `bot_goal_for(team, bot_id, bot_pos)` — le but d'un bot est STABLE (ne
## change que sur ÉVÈNEMENT : kill, but atteint — ou, à défaut, au plus
## toutes les GOAL_REFRESH_INTERVAL=6 s secondes) ; TDM (seul mode restant
## après le nettoyage du prototype 2026-09-26) ne renvoie plus JAMAIS la
## position VIVANTE d'un ennemi (points de patrouille de la carte + dernière
## position connue PARTAGÉE par l'équipe, alimentée UNIQUEMENT par la
## perception réelle d'un bot) ; 60 s de simulation -> <= 12 changements de
## but par bot, 0 appel qui lit une position ennemie hors perception.
##
## Style : sous-classes de test légères (`class Foo extends Bar:`, voir
## tests/agents/test_round_props_cleanup.gd) qui surchargent `_goal_clock_now`
## pour simuler l'écoulement du temps SANS attendre en temps réel (60 s de
## simulation en quelques millisecondes de test, comme le recommande le
## contrat de la tâche).
extends GdUnitTestSuite


# ======================================================================
#  Doubles de test
# ======================================================================

## Double minimal du nœud "match" (GameWorld) : `spawn_points_root` (NodePath,
## export PUBLIC de GameWorld) est lu par GameMode._map_patrol_points ; un
## `players_root` VIDE mais VALIDE est aussi exposé pour que RoundMode._players
## (SnD/Duel) ne s'y casse pas si son propre `_enter_buy_phase` différé (
## `call_deferred`, RoundMode._ready) venait à s'exécuter pendant qu'un test de
## ce fichier laisse ce double dans le groupe "match" — jamais besoin d'un
## GameWorld réel (réseau, spawner...) pour un test de logique de but.
class _FakeWorld extends Node3D:
	var spawn_points_root: NodePath = ^"SpawnPoints"
	var players_root: NodePath = ^"Players"


## Sous-classe de test de GameMode : `_compute_bot_goal` renvoie une position
## DIFFÉRENTE à CHAQUE appel (compteur) — observe directement si `bot_goal_
## for` a RECALCULÉ ou renvoyé la valeur mise en cache, indépendamment de
## toute logique propre à un mode concret. Horloge surchargeable (`fake_now`).
class _CountingMode extends GameMode:
	var compute_calls: int = 0
	var fake_now: float = 0.0
	func _goal_clock_now() -> float:
		return fake_now
	func _compute_bot_goal(_team: int, _bot_id: int, _bot_pos: Vector3, _reached: bool = false) -> Vector3:
		compute_calls += 1
		return Vector3(float(compute_calls), 0.0, 0.0)


## TDMMode avec horloge surchargeable — simule l'écoulement du temps (cadence
## 6 s, mémoire d'ennemi 6 s) sans attendre en temps réel.
class _ClockedTDMMode extends TDMMode:
	var fake_now: float = 0.0
	func _goal_clock_now() -> float:
		return fake_now


## Un "monde" (groupe "match") avec des marqueurs de spawn aux positions
## `points` — les points de patrouille lus par GameMode._map_patrol_points.
func _make_world(points: Array) -> Node3D:
	var world := _FakeWorld.new()
	world.add_to_group("match")
	var root_node := Node3D.new()
	root_node.name = "SpawnPoints"
	world.add_child(root_node)
	var players_node := Node3D.new()
	players_node.name = "Players"
	world.add_child(players_node)
	for p in points:
		var marker := Node3D.new()
		marker.position = p
		root_node.add_child(marker)
	add_child(world)
	auto_free(world)
	return world



## BOT-31 : établit le RANG (et donc la lane, voir `TDMMode._team_rank_of`/
## `_lane_for_bot_id`) de chaque bot de `bot_ids_in_rank_order`, DANS CET
## ORDRE — le rang d'un bot est figé à sa 1ère observation par le mode, donc
## l'ordre d'appel ici DÉCIDE qui obtient quel rang. `[2, 1, 4, 3]` reproduit
## EXACTEMENT la répartition historique `bot_id % 4` de team 0 (bot 1->Nord,
## bot 2->Centre, bot 3->Sud, bot 4->Centre) pour les tests ci-dessous qui
## nomment un bot_id précis dans leurs commentaires/scénarios.
func _prime_lane_ranks(mode: TDMMode, team: int, bot_ids_in_rank_order: Array) -> void:
	for bot_id in bot_ids_in_rank_order:
		mode._lane_for_bot_id(team, bot_id)


## Compte les vecteurs DISTINCTS d'un tableau (`is_equal_approx`, comme le
## reste du fichier) — utilisé pour vérifier qu'au moins N buts diffèrent
## réellement entre eux (répartition sur des points/lanes distincts).
func _count_unique_vectors(vectors: Array) -> int:
	var uniq: Array = []
	for v in vectors:
		var found := false
		for u in uniq:
			if (v as Vector3).is_equal_approx(u as Vector3):
				found = true
				break
		if not found:
			uniq.append(v)
	return uniq.size()


# ======================================================================
#  Stabilité générique du cache (GameMode.bot_goal_for) — indépendante de
#  tout mode concret.
# ======================================================================
func test_goal_stays_identical_before_6s_and_before_reached() -> void:
	var mode := _CountingMode.new()
	add_child(mode)
	auto_free(mode)

	var first := mode.bot_goal_for(0, 1, Vector3(100, 0, 100))
	mode.fake_now += 1.0
	var second := mode.bot_goal_for(0, 1, Vector3(100, 0, 100))

	assert_int(mode.compute_calls).append_failure_message(
		"moins de 6 s après le calcul et loin du but : aucun recalcul attendu").is_equal(1)
	assert_vector(second).is_equal(first)


func test_goal_recomputes_after_refresh_interval_elapses() -> void:
	var mode := _CountingMode.new()
	add_child(mode)
	auto_free(mode)

	mode.bot_goal_for(0, 1, Vector3(100, 0, 100))
	mode.fake_now += GameMode.GOAL_REFRESH_INTERVAL
	mode.bot_goal_for(0, 1, Vector3(100, 0, 100))

	assert_int(mode.compute_calls).append_failure_message(
		"GOAL_REFRESH_INTERVAL écoulées : un recalcul est attendu").is_equal(2)


func test_goal_recomputes_immediately_once_reached() -> void:
	var mode := _CountingMode.new()
	add_child(mode)
	auto_free(mode)

	var first: Vector3 = mode.bot_goal_for(0, 1, Vector3(100, 0, 100))
	mode.fake_now += 0.1  # bien avant les 6 s
	mode.bot_goal_for(0, 1, first)  # le bot est maintenant SUR son but

	assert_int(mode.compute_calls).append_failure_message(
		"but ATTEINT : un recalcul immédiat est attendu, même avant 6 s").is_equal(2)


func test_goal_recomputes_when_invalidated_by_an_event() -> void:
	var mode := _CountingMode.new()
	add_child(mode)
	auto_free(mode)

	mode.bot_goal_for(0, 1, Vector3(100, 0, 100))
	mode.fake_now += 0.1
	mode._invalidate_bot_goals()
	mode.bot_goal_for(0, 1, Vector3(100, 0, 100))

	assert_int(mode.compute_calls).append_failure_message(
		"un évènement (_invalidate_bot_goals) doit forcer un recalcul, même avant 6 s").is_equal(2)


func test_goal_cache_is_independent_per_bot() -> void:
	var mode := _CountingMode.new()
	add_child(mode)
	auto_free(mode)

	var goal_bot_1: Vector3 = mode.bot_goal_for(0, 1, Vector3(100, 0, 100))
	var goal_bot_2: Vector3 = mode.bot_goal_for(0, 2, Vector3(100, 0, 100))

	assert_bool(goal_bot_2.is_equal_approx(goal_bot_1)).append_failure_message(
		"deux bots distincts ne doivent pas partager le même but mis en cache").is_false()


# ======================================================================
#  TDM : non-omniscience (patrouille/mémoire d'équipe, jamais l'état serveur).
# ======================================================================
func test_tdm_goal_is_a_patrol_point_when_no_sighting_reported() -> void:
	var points := [Vector3(10, 0, 0), Vector3(-10, 0, 0), Vector3(0, 0, 10)]
	_make_world(points)
	var mode := TDMMode.new()
	add_child(mode)
	auto_free(mode)

	var goal: Vector3 = mode.bot_goal_for(0, 1, Vector3(1000, 0, 1000))

	var matches_a_patrol_point := false
	for p in points:
		if (goal as Vector3).is_equal_approx(p):
			matches_a_patrol_point = true
	assert_bool(matches_a_patrol_point).append_failure_message(
		"sans info d'équipe, le but TDM doit être un point de patrouille STATIQUE de la carte"
	).is_true()


func test_tdm_never_returns_a_live_enemy_position_that_was_never_perceived() -> void:
	var points := [Vector3(10, 0, 0), Vector3(-10, 0, 0)]
	_make_world(points)
	var mode := TDMMode.new()
	add_child(mode)
	auto_free(mode)
	# Un ennemi "fantôme" existe (position arbitraire) mais n'est JAMAIS
	# signalé via `report_enemy_sighting` — comme un ennemi hors de la
	# perception (LOS/audition) de tout bot de l'équipe.
	var phantom_enemy_pos := Vector3(500, 0, 500)

	for bot_id in [1, 2, 3, 4]:
		var goal: Vector3 = mode.bot_goal_for(0, bot_id, Vector3(bot_id * 3.0, 0, 0))
		assert_bool(goal.is_equal_approx(phantom_enemy_pos)).append_failure_message(
			"BOT-01 : aucun appel ne doit lire une position ennemie hors perception").is_false()


func test_tdm_goal_follows_reported_sighting_then_reverts_after_it_expires() -> void:
	var points := [Vector3(10, 0, 0)]
	_make_world(points)
	var mode := _ClockedTDMMode.new()
	add_child(mode)
	auto_free(mode)

	var sighting := Vector3(3, 0, 4)
	mode.report_enemy_sighting(0, sighting)
	var goal: Vector3 = mode.bot_goal_for(0, 1, Vector3(1000, 0, 1000))
	assert_vector(goal).append_failure_message(
		"une info FRAÎCHE de l'équipe doit primer sur les points de patrouille").is_equal(sighting)

	mode.fake_now += GameMode.ENEMY_MEMORY_TTL + 1.0
	mode._invalidate_bot_goals()  # force le recalcul pour observer l'expiration tout de suite.
	var goal_after: Vector3 = mode.bot_goal_for(0, 1, Vector3(1000, 0, 1000))
	assert_bool(goal_after.is_equal_approx(sighting)).append_failure_message(
		"la mémoire d'équipe doit expirer (ENEMY_MEMORY_TTL) et retomber sur un point de patrouille").is_false()


# Hardpoint (zone qui tourne), Duel/Duo (zone de capture) et SnD (site de
# manche/bombe) ont été supprimés avec leurs modes lors du nettoyage du
# prototype 2026-09-26 — tests retirés avec eux ; TDM est désormais le seul
# mode couvert par ce fichier.


# ======================================================================
#  Acceptance BOT-01 : 60 s de simulation -> <= 12 changements de but par
#  bot, 0 appel qui lit une position ennemie hors perception.
# ======================================================================
func test_60s_simulation_stays_within_12_goal_changes_per_bot_and_never_leaks_unperceived_enemies() -> void:
	var points := [Vector3(10, 0, 0), Vector3(-10, 0, 0), Vector3(0, 0, 10), Vector3(0, 0, -10)]
	_make_world(points)
	var mode := _ClockedTDMMode.new()
	add_child(mode)
	auto_free(mode)

	# Ennemi "fantôme" : existe mais n'est JAMAIS signalé par un bot (hors
	# perception) — ne doit JAMAIS apparaître comme but, à AUCUN instant.
	var phantom_enemy_pos := Vector3(777, 0, 777)
	var bot_ids := [1, 2, 3, 4]
	# Bot loin de tout point de patrouille : "but atteint" ne se déclenche
	# jamais tout seul ici, on isole ainsi la cadence 6 s / les évènements.
	var bot_pos := Vector3(1000, 0, 1000)

	var previous_goal: Dictionary = {}
	var changes: Dictionary = {1: 0, 2: 0, 3: 0, 4: 0}

	var t := 0.0
	while t <= 60.0:
		mode.fake_now = t
		# Deux kills en cours de simulation (évènement BOT-01 : "kill").
		if is_equal_approx(t, 15.0) or is_equal_approx(t, 40.0):
			mode.on_kill(-1, -1, 0, 1)
		# Fenêtre où l'équipe 0 a repéré un ennemi — PERCEPTION réelle d'un
		# bot (jamais une lecture directe de l'état serveur).
		if t >= 20.0 and t < 26.0:
			mode.report_enemy_sighting(0, Vector3(2, 0, 2))

		for bot_id in bot_ids:
			var goal: Vector3 = mode.bot_goal_for(0, bot_id, bot_pos)
			assert_bool(goal.is_equal_approx(phantom_enemy_pos)).append_failure_message(
				"BOT-01 : 0 appel ne doit lire une position ennemie hors perception (t=%s, bot=%s)" % [t, bot_id]
			).is_false()
			if previous_goal.has(bot_id) and not (previous_goal[bot_id] as Vector3).is_equal_approx(goal):
				changes[bot_id] = int(changes[bot_id]) + 1
			previous_goal[bot_id] = goal
		t += 1.0

	for bot_id in bot_ids:
		assert_int(changes[bot_id]).append_failure_message(
			"bot %s : %s changements de but en 60 s de simulation (<= 12 attendu)" % [bot_id, changes[bot_id]]
		).is_less_equal(12)

