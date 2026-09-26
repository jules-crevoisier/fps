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


## Double MINIMAL d'un nœud "MapSetup" (LD-25, docs/research/
## 09_wasteland_vertical_slice.md §e) : seul son export PUBLIC `map_id`
## compte ici — `GameMode._current_map_id()` lit `get_parent().map_id` (même
## discipline que `GameHUD._acquire_map_setup`, autre tâche : dupliquer la
## lecture d'un champ public plutôt que d'appeler une méthode `_`-préfixée
## d'un fichier hors périmètre, jamais touché ici). Un mode ajouté comme
## enfant d'un `_FakeMapSetup(map_id="wasteland")` reçoit donc la VRAIE
## connaissance bots de Wasteland (`WastelandBots.data()`, LD-24, déjà
## livrée) — aucune donnée inventée pour les tests LD-25 ci-dessous.
class _FakeMapSetup extends Node3D:
	var map_id: String = "wasteland"


## Construit `mode` comme enfant d'un `_FakeMapSetup(map_id="wasteland")` —
## `auto_free` du double suffit à libérer tout le sous-arbre (mode compris),
## même patron que `_snd_mode_with_sites` plus bas pour ses enfants Area3D.
func _wasteland_mode(mode: GameMode) -> GameMode:
	var setup := _FakeMapSetup.new()
	add_child(setup)
	auto_free(setup)
	setup.add_child(mode)
	return mode


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


# ======================================================================
#  BOT-23 : TDM patrouille par COULOIR (bot_knowledge, BOT-22) — remplace le
#  tirage de hotspot LD-25 sur une carte qui déclare cette connaissance plus
#  riche (repli hotspots/marqueurs de spawn inchangé partout ailleurs, voir
#  les tests TDM plus haut).
# ======================================================================
func test_tdm_goal_is_a_corridor_point_from_the_assigned_lane_when_the_map_declares_bot_knowledge() -> void:
	var mode: TDMMode = _wasteland_mode(TDMMode.new())
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])

	for bot_id in [1, 2, 3, 4]:
		var goal: Vector3 = mode.bot_goal_for(0, bot_id, Vector3(1000, 0, 1000))
		var lane := mode._lane_for_bot_id(0, bot_id)
		var points: Array = know.lane_goals(0, lane)
		var matches_a_corridor_point := false
		for p in points:
			if goal.is_equal_approx(p as Vector3):
				matches_a_corridor_point = true
		assert_bool(matches_a_corridor_point).append_failure_message(
			"BOT-23/T1 : sur une carte avec bot_knowledge, le but TDM doit être un point du COULOIR assigné (bot %d -> %s), jamais un marqueur de spawn" % [bot_id, lane]
		).is_true()


func test_tdm_lane_assignment_is_2_centre_1_nord_1_sud_across_4_bots() -> void:
	var mode: TDMMode = _wasteland_mode(TDMMode.new())
	var counts := {"N": 0, "C": 0, "S": 0}
	for bot_id in [1, 2, 3, 4]:
		var lane := mode._lane_for_bot_id(0, bot_id)
		counts[lane] = int(counts[lane]) + 1

	assert_int(counts["C"]).append_failure_message(
		"T1 : 2 bots attendus au Centre sur 4 (vu : %s)" % [counts]).is_equal(2)
	assert_int(counts["N"]).append_failure_message(
		"T1 : 1 bot attendu au Nord sur 4 (vu : %s)" % [counts]).is_equal(1)
	assert_int(counts["S"]).append_failure_message(
		"T1 : 1 bot attendu au Sud sur 4 (vu : %s)" % [counts]).is_equal(1)


func test_tdm_corridor_goal_holds_the_point_then_advances_to_the_next_one() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	mode._rng.seed = 1234
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # BOT-31 : reproduit le rang historique (bot 1 -> Nord).
	var bot_id := 1  # Nord (rang 1, seul sur sa lane -> tronçon complet).
	var points: Array = BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"]).lane_goals(0, "N")

	var first: Vector3 = mode.bot_goal_for(0, bot_id, points[1])  # positionné pile sur son 1er but.
	assert_vector(first).append_failure_message(
		"T1 : le premier but doit être le premier point INTÉRIEUR du couloir (jamais le spawn, indice 0)"
	).is_equal(points[1])

	mode.fake_now += 1.0  # "but atteint" mais tenue (4-10 s) pas encore écoulée.
	var still_holding: Vector3 = mode.bot_goal_for(0, bot_id, points[1])
	assert_vector(still_holding).append_failure_message(
		"T1 : le but doit être TENU 4 à 10 s avant de changer, pas changer dès l'arrivée"
	).is_equal(points[1])

	mode.fake_now += 15.0  # largement au-delà de la tenue max (10 s).
	var advanced: Vector3 = mode.bot_goal_for(0, bot_id, points[1])
	assert_bool(advanced.is_equal_approx(points[1])).append_failure_message(
		"T1 : passé la tenue, le but doit avancer au point SUIVANT du couloir"
	).is_false()


func test_tdm_shared_sighting_only_mobilizes_nearby_or_inactive_bots_with_a_delay_and_cover_offset() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	mode._rng.seed = 42
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # BOT-31 : bot 2 -> Centre, bot 3 -> Sud (rang historique).
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var sud_points: Array = know.lane_goals(0, "S")
	var centre_points: Array = know.lane_goals(0, "C")

	# bot 3 (Sud) patrouille déjà (donc "actif"), loin du point qui va être signalé.
	var sud_goal: Vector3 = mode.bot_goal_for(0, 3, sud_points[1])

	var sighting: Vector3 = centre_points[7]
	mode.report_enemy_sighting(0, sighting)

	# Premier contact des deux bots avec l'info (démarre leur délai U(0.5;1.0) s individuel, T2).
	mode.bot_goal_for(0, 2, Vector3(1000, 0, 1000))  # bot 2 (Centre), jamais appelé -> "inactif".
	mode.bot_goal_for(0, 3, sud_goal)                 # bot 3 (Sud), déjà actif et loin -> pas mobilisé.

	mode.fake_now += TDMMode.SIGHTING_DELAY_MAX + 0.1  # le délai est écoulé pour tout bot éligible.

	var centre_after: Vector3 = mode.bot_goal_for(0, 2, Vector3(1000, 0, 1000))
	var sud_after: Vector3 = mode.bot_goal_for(0, 3, sud_goal)

	assert_bool(centre_after.distance_to(sighting) <= 3.5).append_failure_message(
		"T2 : un bot INACTIF doit investiguer le point signalé (décalé vers une couverture, <= 3 m)"
	).is_true()
	assert_vector(sud_after).append_failure_message(
		"T2 : un bot déjà ACTIF et à plus de 25 m ne doit PAS être mobilisé par l'info d'équipe"
	).is_equal(sud_goal)


## BOT-30 (docs/research/09_wasteland_vertical_slice.md §e, banc bots :
## changements de but 17,4/min mesurés, seuil <= 8/min) : un ennemi qui reste
## VISIBLE en continu (donc signalé à CHAQUE tick, `GameMode.
## report_enemy_sighting` — comme le fait réellement `BotBrain` en combat)
## mais dérive de quelques centimètres (recul, strafe) ne doit PAS
## redéclencher une nouvelle réaction T2 (nouveau délai, nouveau but
## d'investigation) à chaque tick — une seule réaction pour cette info-là,
## voir `TDMMode.SIGHTING_REPOSITION_MIN_DELTA`.
func test_tdm_shared_sighting_does_not_retrigger_on_sub_threshold_drift_while_the_enemy_stays_put() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	mode._rng.seed = 99
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # BOT-31 : bot 2 -> Centre (rang historique).
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var centre_points: Array = know.lane_goals(0, "C")
	var base_sighting: Vector3 = centre_points[7]
	var far_pos := Vector3(1000, 0, 1000)

	mode.report_enemy_sighting(0, base_sighting)
	mode.bot_goal_for(0, 2, far_pos)  # bot 2 (Centre), inactif -> éligible, démarre son délai.

	mode.fake_now += TDMMode.SIGHTING_DELAY_MAX + 0.1  # délai écoulé : la réaction s'applique.
	var goal_after_first_reaction: Vector3 = mode.bot_goal_for(0, 2, far_pos)
	assert_bool(goal_after_first_reaction.distance_to(base_sighting) <= 3.5).append_failure_message(
		"la réaction initiale doit investiguer le point signalé (décalé vers une couverture, <= 3 m)"
	).is_true()

	# L'ennemi reste globalement sur place mais reste VISIBLE : un bot le
	# signale à CHAQUE tick (0,1 s), avec une dérive sous le seuil de
	# repositionnement (quelques cm, jamais >= SIGHTING_REPOSITION_MIN_DELTA).
	for i in 30:
		var jitter := Vector3(float(i % 3) * 0.05, 0.0, float(i % 2) * 0.05)
		mode.report_enemy_sighting(0, base_sighting + jitter)
		mode.fake_now += 0.1
		var goal_now: Vector3 = mode.bot_goal_for(0, 2, far_pos)
		assert_bool(goal_now.is_equal_approx(goal_after_first_reaction)).append_failure_message(
			"BOT-30 : une dérive de position sous le seuil de repositionnement ne doit pas redéclencher une nouvelle réaction (t=%.1f, but=%s, attendu=%s)" % [mode.fake_now, goal_now, goal_after_first_reaction]
		).is_true()


func test_tdm_shared_sighting_still_retriggers_once_the_enemy_genuinely_relocates() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	mode._rng.seed = 99
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # BOT-31 : bot 2 -> Centre (rang historique).
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var centre_points: Array = know.lane_goals(0, "C")
	var far_pos := Vector3(1000, 0, 1000)

	mode.report_enemy_sighting(0, centre_points[3])
	mode.bot_goal_for(0, 2, far_pos)  # 1er contact avec l'info : démarre son délai.
	mode.fake_now += TDMMode.SIGHTING_DELAY_MAX + 0.1
	var first_goal: Vector3 = mode.bot_goal_for(0, 2, far_pos)  # délai écoulé : s'applique.

	# L'ennemi se déplace RÉELLEMENT, largement au-delà du seuil de dérive :
	# même séquence en 2 temps que le contact initial (1er appel = démarre le
	# NOUVEAU délai individuel, 2e appel après ce délai = observe
	# l'application). Position du bot = `first_goal` (il vient d'investiguer
	# la 1ère info, donc n'est plus "inactif" — `_lane_progress` déjà établi
	# par le repli de patrouille du tout 1er appel ci-dessus, comme
	# `test_tdm_shared_sighting_only_mobilizes_...` le documente) : il reste
	# néanmoins À MOINS DE 25 M de la nouvelle position signalée.
	mode.report_enemy_sighting(0, centre_points[5])
	mode.bot_goal_for(0, 2, first_goal)
	mode.fake_now += TDMMode.SIGHTING_DELAY_MAX + 0.1
	var second_goal: Vector3 = mode.bot_goal_for(0, 2, first_goal)

	assert_bool(second_goal.is_equal_approx(first_goal)).append_failure_message(
		"un déplacement réel de l'ennemi (bien au-delà du seuil de dérive) doit encore redéclencher une réaction T2"
	).is_false()


func test_tdm_kill_only_invalidates_bots_near_the_kill_or_the_corridor_concerned_after_a_delay() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	mode._rng.seed = 7
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # BOT-31 : bot 2 -> Centre, bot 3 -> Sud (rang historique).
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var centre_points: Array = know.lane_goals(0, "C")
	var sud_points: Array = know.lane_goals(0, "S")

	var centre_goal: Vector3 = mode.bot_goal_for(0, 2, centre_points[7])  # Centre, proche du kill à venir.
	var sud_goal: Vector3 = mode.bot_goal_for(0, 3, sud_points[1])        # Sud, loin et autre couloir.

	# Position APPROXIMATIVE du kill (T3, wasteland v7) : côté EST du couloir
	# Centre (`centre_points[-2]`, proche de l'apparition rouge) — mesuré à
	# > 50 m du but initial de bot 3 (Sud, ci-dessus), largement au-delà de
	# `TDMMode.KILL_MOBILIZE_RANGE_OUT_OF_LANE` (30 m). Un point proche de
	# l'apparition bleue (ex. l'ancien `centre_points[8]`, ~29 m de bot 3 sur
	# la géométrie v7 du plan) tombait À L'INTÉRIEUR de ce rayon — ce n'est
	# pas le scénario "loin et autre couloir" que ce test veut vérifier.
	mode.report_enemy_sighting(0, centre_points[centre_points.size() - 2])
	mode.on_kill(-1, -1, 0, 1)

	mode.fake_now += TDMMode.KILL_DELAY_MAX + 0.1

	var centre_after: Vector3 = mode.bot_goal_for(0, 2, centre_goal)
	var sud_after: Vector3 = mode.bot_goal_for(0, 3, sud_goal)

	assert_bool(centre_after.is_equal_approx(centre_goal)).append_failure_message(
		"T3 : un kill à moins de 30 m (ou du couloir concerné) doit invalider ce bot"
	).is_false()
	assert_vector(sud_after).append_failure_message(
		"T3 : un kill loin et d'un autre couloir ne doit pas invalider ce bot"
	).is_equal(sud_goal)


## Acceptance BOT-23 : 60 s simulées sur Wasteland (bot_knowledge) -> B12
## (jamais 3 bots ou plus qui changent de but dans la même fenêtre de 200 ms),
## B13 (présence au spawn <= 5 % au-delà des 10 premières secondes), et les
## buts des 4 coéquipiers écartés d'au moins 8 m dans au moins 90 % des
## échantillons.
func test_60s_wasteland_simulation_respects_b12_sync_b13_spawn_camping_and_8m_teammate_spacing() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	mode._rng.seed = 20260925
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var bot_ids := [1, 2, 3, 4]  # 2 Centre/1 Nord/1 Sud (T1) — l'affectation précise dépend de
			# l'ordre du 1er appel de chaque bot (BOT-31, voir `_lane_for_bot_id`/`_team_rank_of`),
			# établi ci-dessous dans l'ordre de `bot_ids`.

	var spawn_of: Dictionary = {}
	var pos_by_bot: Dictionary = {}
	for bot_id in bot_ids:
		spawn_of[bot_id] = (know.lane_goals(0, mode._lane_for_bot_id(0, bot_id)) as Array)[0]
		pos_by_bot[bot_id] = Vector3(1000, 0, 1000)

	var previous_goal: Dictionary = {}
	var change_times: Array = []
	var near_spawn_samples := 0
	var total_spawn_samples := 0
	var spaced_samples := 0
	var total_spacing_samples := 0

	for step_i in 601:
		var t: float = step_i * 0.1
		mode.fake_now = t
		if is_equal_approx(t, 15.0) or is_equal_approx(t, 40.0):
			mode.on_kill(-1, -1, 0, 1)
		if (t >= 10.0 and t < 10.5) or (t >= 38.0 and t < 38.5):
			mode.report_enemy_sighting(0, (know.lane_goals(0, "C") as Array)[3] as Vector3)
		if t >= 20.0 and t < 20.5:
			mode.report_enemy_sighting(0, (know.lane_goals(0, "C") as Array)[5] as Vector3)

		var goals: Dictionary = {}
		for bot_id in bot_ids:
			var goal: Vector3 = mode.bot_goal_for(0, bot_id, pos_by_bot[bot_id])
			goals[bot_id] = goal
			pos_by_bot[bot_id] = goal  # le bot "téléporte" sur son but : ce test porte sur la SÉLECTION du but, pas le déplacement physique (comme le reste de ce fichier).
			if previous_goal.has(bot_id) and not (previous_goal[bot_id] as Vector3).is_equal_approx(goal):
				change_times.append(t)
			previous_goal[bot_id] = goal

			if t > 10.0:
				total_spawn_samples += 1
				if goal.distance_to(spawn_of[bot_id] as Vector3) < 10.0:
					near_spawn_samples += 1

		total_spacing_samples += 1
		var min_pair_dist := INF
		for i in bot_ids.size():
			for j in range(i + 1, bot_ids.size()):
				var d: float = (goals[bot_ids[i]] as Vector3).distance_to(goals[bot_ids[j]] as Vector3)
				if d < min_pair_dist:
					min_pair_dist = d
		if min_pair_dist >= 8.0:
			spaced_samples += 1

	change_times.sort()
	for i in change_times.size():
		var window_start: float = change_times[i]
		var count_in_window := 0
		for ct in change_times:
			if (ct as float) >= window_start and (ct as float) < window_start + 0.2:
				count_in_window += 1
		assert_int(count_in_window).append_failure_message(
			"B12 : jamais 3 changements de but ou plus dans une fenêtre de 200 ms (fenêtre à t=%.2f : %d changements)" % [window_start, count_in_window]
		).is_less(3)

	var spawn_ratio := float(near_spawn_samples) / float(maxi(total_spawn_samples, 1))
	assert_float(spawn_ratio).append_failure_message(
		"B13 : présence au spawn = %.1f%% des échantillons (attendu <= 5%%)" % [spawn_ratio * 100.0]
	).is_less_equal(0.05)

	var spaced_ratio := float(spaced_samples) / float(maxi(total_spacing_samples, 1))
	assert_float(spaced_ratio).append_failure_message(
		"Espacement coéquipiers : %.1f%% des échantillons >= 8 m (attendu >= 90%%)" % [spaced_ratio * 100.0]
	).is_greater_equal(0.90)


# ======================================================================
#  LD-25 : Hardpoint tient la zone par des points DISTINCTS (jamais le
#  centre commun) — RETIRÉ CONTRE WASTELAND (2026-09-26, « fais la carte
#  block que je puisse la tester in game » — v7 greybox, TDM seul, voir
#  l'en-tête de `scripts/levels/maps/layouts/wasteland.gd`) : Wasteland ne
#  déclare plus de zone Hardpoint ni de `hp_holds` réels (`bot_knowledge
#  .hp_holds` vaut `[]`), donc un bot Hardpoint dessus retombe désormais SUR
#  LE CENTRE COMMUN par construction (repli LD-25 documenté, « pas de
#  données » = comportement historique) — l'inverse de ce que ce test
#  vérifiait. La même logique, contre une connaissance de zone FICTIVE
#  découplée de toute carte réelle, reste couverte par
#  `tests/ai/test_bot_goals_hardpoint.gd::
#  test_two_hold_slots_are_distinct_positions_at_least_3m_apart_never_the_
#  center` (hors de ma liste de fichiers, déjà vert). Écart connu, signalé
#  au rendu de tâche : `MapCatalog.gd` annonce encore Wasteland pour
#  "hardpoint" (hors de mon périmètre de fichiers cette manche).
# ======================================================================


## Test LD-25 « tous les bots basculent 10 s avant la rotation » retiré par décision du lead le
## 2026-09-25 : le contrat BOT-24 (docs/research/08_bots_humanlike.md) le remplace — seul le créneau de
## pré-rotation part 15 s avant, les autres tiennent la zone jusqu'à la rotation ; vérifié par
## tests/ai/test_bot_goals_hardpoint.gd.
