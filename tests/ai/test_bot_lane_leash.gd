## test_bot_lane_leash.gd
## BOT-31 (« laisse de couloir », décision du lead 2026-09-25) — diagnostic de
## la passe 1 (bloquée, tout annulé) : (a) les DEUX équipes doublaient la
## MÊME lane (Centre) car `bot_id % 4` retombe sur les mêmes restes quel que
## soit le bloc d'ids de chaque équipe ; (b) les réactions T2/T3 mobilisaient
## des bots de TOUTES les lanes vers la dernière info (boucle de rétroaction
## qui fait "gagner" une lane entière), alors qu'un confinement STRICT à la
## lane propre (testé en passe 1) tuait le combat (1,67 kill/min, contact
## médian 52 s — reports/bot_bench/bot31_after.json / bot31_after_run2.json).
##
## Ce fichier couvre les DEUX correctifs du contrat :
##  1. Index de lane PAR ÉQUIPE (`TDMMode._lane_for_bot_id`/`_team_rank_of`) :
##     team 0 double le Centre (verrou 2 Centre/1 Nord/1 Sud INCHANGÉ, déjà
##     couvert par tests/ai/test_bot_goals.gd), team 1 double le Canyon.
##  2. Laisse de couloir (`_maybe_trigger_sighting_reaction`/
##     `_maybe_trigger_kill_reaction`) : un bot de la MÊME lane que
##     l'évènement reste mobilisable sans restriction nouvelle ; un bot
##     D'UNE AUTRE lane ne l'est plus qu'au travers de la laisse — au plus
##     UN par évènement, le plus proche (`SIGHTING_MOBILIZE_RANGE_OUT_OF_
##     LANE`/`KILL_MOBILIZE_RANGE_OUT_OF_LANE`) — et revient à sa propre
##     lane après `LANE_HOLD_MAX` s sans nouveau contact.
##
## Style : mêmes doubles LOCAUX que tests/ai/test_bot_goals.gd (`_ClockedTDMMode`,
## `_FakeMapSetup`/`_wasteland_mode`, `_prime_lane_ranks`) — hors de ma liste de
## fichiers, non modifié, dupliqués ici comme le fait déjà
## tests/ai/test_bot_goals_hardpoint.gd pour ses propres doubles.
extends GdUnitTestSuite


# ======================================================================
#  Doubles de test (voir tests/ai/test_bot_goals.gd pour l'original).
# ======================================================================

## TDMMode avec horloge surchargeable — simule l'écoulement du temps sans
## attendre en temps réel.
class _ClockedTDMMode extends TDMMode:
	var fake_now: float = 0.0
	func _goal_clock_now() -> float:
		return fake_now


## Double MINIMAL d'un nœud "MapSetup" : seul `map_id` compte (voir
## `GameMode._current_map_id`).
class _FakeMapSetup extends Node3D:
	var map_id: String = "wasteland"


## Construit `mode` comme enfant d'un `_FakeMapSetup(map_id="wasteland")` —
## reçoit la VRAIE connaissance bots de Wasteland (`WastelandBots.data()`).
func _wasteland_mode(mode: GameMode) -> GameMode:
	var setup := _FakeMapSetup.new()
	add_child(setup)
	auto_free(setup)
	setup.add_child(mode)
	return mode


## Établit le RANG (et donc la lane, voir `TDMMode._team_rank_of`/
## `_lane_for_bot_id`) de chaque bot de `bot_ids_in_rank_order`, DANS CET
## ORDRE — le rang est figé à la 1ère observation, donc l'ordre d'appel ici
## DÉCIDE qui obtient quel rang. `[2, 1, 4, 3]` reproduit la répartition
## historique de team 0 (bot 1->Nord, bot 2->Centre, bot 3->Sud, bot 4->Centre,
## verrouillée par tests/ai/test_bot_goals.gd) ; team 1 utilise des bot_ids
## disjoints (101-104) pour ne jamais partager de rang avec team 0 (le
## registre `_team_rank` est indexé par bot_id SEUL, comme en jeu réel où les
## ids de bot sont globalement uniques entre les deux équipes).
func _prime_lane_ranks(mode: TDMMode, team: int, bot_ids_in_rank_order: Array) -> void:
	for bot_id in bot_ids_in_rank_order:
		mode._lane_for_bot_id(team, bot_id)


# ======================================================================
#  (1) Index de lane PAR ÉQUIPE : team 0 double le Centre (verrou existant),
#  team 1 double le Canyon (nouveau) — jamais la MÊME lane pour les deux.
# ======================================================================
func test_team0_doubles_centre_and_team1_doubles_canyon_with_disjoint_bot_ids() -> void:
	var mode: TDMMode = _wasteland_mode(TDMMode.new())

	var counts_team0 := {"N": 0, "C": 0, "S": 0}
	for bot_id in [1, 2, 3, 4]:
		var lane := mode._lane_for_bot_id(0, bot_id)
		counts_team0[lane] = int(counts_team0[lane]) + 1

	var counts_team1 := {"N": 0, "C": 0, "S": 0}
	for bot_id in [101, 102, 103, 104]:
		var lane := mode._lane_for_bot_id(1, bot_id)
		counts_team1[lane] = int(counts_team1[lane]) + 1

	assert_int(counts_team0["C"]).append_failure_message(
		"team 0 : 2 bots attendus au Centre (verrou existant, vu : %s)" % [counts_team0]).is_equal(2)
	assert_int(counts_team1["S"]).append_failure_message(
		"BOT-31 : team 1 doit doubler le CANYON, pas le Centre (vu : %s)" % [counts_team1]).is_equal(2)
	assert_int(counts_team1["N"]).append_failure_message(
		"team 1 : 1 seul bot attendu au Nord (vu : %s)" % [counts_team1]).is_equal(1)
	assert_int(counts_team1["C"]).append_failure_message(
		"team 1 : 1 seul bot attendu au Centre (vu : %s)" % [counts_team1]).is_equal(1)


func test_the_two_teams_never_double_the_same_lane() -> void:
	var mode: TDMMode = _wasteland_mode(TDMMode.new())
	var doubled_lane_team0 := ""
	var counts0 := {"N": 0, "C": 0, "S": 0}
	for bot_id in [1, 2, 3, 4]:
		var lane := mode._lane_for_bot_id(0, bot_id)
		counts0[lane] = int(counts0[lane]) + 1
	for lane in counts0.keys():
		if int(counts0[lane]) == 2:
			doubled_lane_team0 = lane

	var doubled_lane_team1 := ""
	var counts1 := {"N": 0, "C": 0, "S": 0}
	for bot_id in [101, 102, 103, 104]:
		var lane := mode._lane_for_bot_id(1, bot_id)
		counts1[lane] = int(counts1[lane]) + 1
	for lane in counts1.keys():
		if int(counts1[lane]) == 2:
			doubled_lane_team1 = lane

	assert_str(doubled_lane_team0).append_failure_message("team 0 doit doubler EXACTEMENT une lane").is_not_equal("")
	assert_str(doubled_lane_team1).append_failure_message("team 1 doit doubler EXACTEMENT une lane").is_not_equal("")
	assert_str(doubled_lane_team1).append_failure_message(
		"diagnostic (a) : les deux équipes doublaient la MÊME lane — désormais team 0 (%s) != team 1 (%s)"
		% [doubled_lane_team0, doubled_lane_team1]
	).is_not_equal(doubled_lane_team0)


# ======================================================================
#  (2) Laisse de couloir — sighting (T2).
# ======================================================================
func test_out_of_lane_bot_within_range_is_mobilized_by_a_sighting_in_another_lane() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # bot 1 -> Nord (rang historique).
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var sighting: Vector3 = (know.lane_goals(0, "C") as Array)[5]  # Place, lane Centre.

	mode.report_enemy_sighting(0, sighting)
	# bot 1 (Nord) à 8 m de la Place (Nord[5] = (0, 0.5, -9), Place = (0, 0.5, -1)).
	var nord_bot_pos: Vector3 = (know.lane_goals(0, "N") as Array)[5]
	mode.bot_goal_for(0, 1, nord_bot_pos)  # 1er contact : démarre son délai (hors-lane, dans le rayon).

	mode.fake_now += TDMMode.SIGHTING_DELAY_MAX + 0.1
	var after: Vector3 = mode.bot_goal_for(0, 1, nord_bot_pos)

	assert_bool(after.distance_to(sighting) <= 3.5).append_failure_message(
		"laisse de couloir : l'UNIQUE bot hors-lane à portée doit être mobilisé (décalé vers une couverture, <= 3 m)"
	).is_true()


func test_out_of_lane_bot_beyond_the_out_of_lane_range_is_not_mobilized_by_a_sighting() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # bot 3 -> Sud (rang historique).
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var sighting: Vector3 = (know.lane_goals(0, "C") as Array)[5]  # Place, lane Centre.

	mode.report_enemy_sighting(0, sighting)
	# bot 3 (Sud) à 60 m de la Place : bien au-delà de
	# SIGHTING_MOBILIZE_RANGE_OUT_OF_LANE (= SIGHTING_MOBILIZE_RANGE, 25 m).
	var sud_bot_pos: Vector3 = sighting + Vector3(60.0, 0.0, 0.0)
	var sud_goal: Vector3 = mode.bot_goal_for(0, 3, sud_bot_pos)

	mode.fake_now += TDMMode.SIGHTING_DELAY_MAX + 0.1
	var after: Vector3 = mode.bot_goal_for(0, 3, sud_goal)

	assert_vector(after).append_failure_message(
		"laisse de couloir : un bot hors-lane AU-DELÀ du rayon dédié ne doit pas être mobilisé"
	).is_equal(sud_goal)


func test_out_of_lane_sighting_leash_mobilizes_only_the_closest_of_two_out_of_lane_bots() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # bot 1 -> Nord, bot 3 -> Sud (rang historique).
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var sighting: Vector3 = (know.lane_goals(0, "C") as Array)[5]  # Place, lane Centre.
	mode.report_enemy_sighting(0, sighting)

	# bot 1 (Nord) à 12 m : 1er à réclamer la laisse (seul candidat pour l'instant).
	var far_pos := sighting + Vector3(12.0, 0.0, 0.0)
	mode.bot_goal_for(0, 1, far_pos)
	# bot 3 (Sud) à 5 m : plus proche, lui prend la place de titulaire unique.
	var near_pos := sighting + Vector3(5.0, 0.0, 0.0)
	mode.bot_goal_for(0, 3, near_pos)

	mode.fake_now += TDMMode.SIGHTING_DELAY_MAX + 0.1
	var bot1_after: Vector3 = mode.bot_goal_for(0, 1, far_pos)
	var bot3_after: Vector3 = mode.bot_goal_for(0, 3, near_pos)

	assert_bool(bot3_after.distance_to(sighting) <= 3.5).append_failure_message(
		"le bot hors-lane le PLUS PROCHE (5 m) doit être l'unique titulaire mobilisé"
	).is_true()
	assert_bool(bot1_after.distance_to(sighting) <= 3.5).append_failure_message(
		"le bot hors-lane déplacé (12 m, moins proche) ne doit plus être mobilisé — au plus UN par évènement"
	).is_false()


func test_out_of_lane_bot_returns_to_its_own_lane_after_lane_hold_max_without_new_contact() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # bot 1 -> Nord (rang historique).
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var sighting: Vector3 = (know.lane_goals(0, "C") as Array)[5]
	var nord_points: Array = know.lane_goals(0, "N")
	var nord_bot_pos: Vector3 = nord_points[5]

	mode.report_enemy_sighting(0, sighting)
	mode.bot_goal_for(0, 1, nord_bot_pos)
	mode.fake_now += TDMMode.SIGHTING_DELAY_MAX + 0.1
	var mobilized: Vector3 = mode.bot_goal_for(0, 1, nord_bot_pos)
	assert_bool(mobilized.distance_to(sighting) <= 3.5).append_failure_message(
		"prérequis : le bot hors-lane doit d'abord être mobilisé"
	).is_true()

	# Aucun nouveau contact ensuite (pas de nouveau report_enemy_sighting) :
	# passé LANE_HOLD_MAX s, le bot doit revenir à sa PROPRE lane (Nord),
	# jamais rester bloqué près de l'info d'une autre lane.
	mode.fake_now += TDMMode.LANE_HOLD_MAX + 1.0
	var returned: Vector3 = mode.bot_goal_for(0, 1, mobilized)

	assert_bool(returned.distance_to(sighting) <= 3.5).append_failure_message(
		"BOT-31 : passé LANE_HOLD_MAX s sans nouveau contact, le bot doit avoir quitté le point mobilisé"
	).is_false()
	var matches_a_nord_point := false
	for p in nord_points:
		if returned.is_equal_approx(p as Vector3):
			matches_a_nord_point = true
	assert_bool(matches_a_nord_point).append_failure_message(
		"BOT-31 : le bot doit revenir patrouiller sa PROPRE lane (Nord), pas rester sur l'ancien point mobilisé"
	).is_true()


# ======================================================================
#  (2) Laisse de couloir — kill (T3), même contrat.
# ======================================================================
func test_out_of_lane_bot_within_range_is_mobilized_by_a_kill_in_another_lane() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # bot 1 -> Nord (rang historique).
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var kill_pos: Vector3 = (know.lane_goals(0, "C") as Array)[5]  # Place, lane Centre.
	var nord_bot_pos: Vector3 = (know.lane_goals(0, "N") as Array)[5]  # 8 m de la Place.

	mode.report_enemy_sighting(0, kill_pos)  # position APPROXIMATIVE du kill (T3, comme _register_targeted_kill).
	mode.on_kill(-1, -1, 0, 1)
	mode.bot_goal_for(0, 1, nord_bot_pos)  # 1er contact.

	mode.fake_now += TDMMode.KILL_DELAY_MAX + 0.1
	var after: Vector3 = mode.bot_goal_for(0, 1, nord_bot_pos)

	assert_bool(after.distance_to(kill_pos) <= 3.5).append_failure_message(
		"laisse de couloir (T3) : l'UNIQUE bot hors-lane à portée d'un kill doit être mobilisé"
	).is_true()


func test_out_of_lane_kill_leash_mobilizes_only_the_closest_of_two_out_of_lane_bots() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # bot 1 -> Nord, bot 3 -> Sud (rang historique).
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var kill_pos: Vector3 = (know.lane_goals(0, "C") as Array)[5]

	mode.report_enemy_sighting(0, kill_pos)
	mode.on_kill(-1, -1, 0, 1)

	var far_pos := kill_pos + Vector3(14.0, 0.0, 0.0)   # candidat le plus loin, observé en 1er.
	mode.bot_goal_for(0, 1, far_pos)
	var near_pos := kill_pos + Vector3(4.0, 0.0, 0.0)    # candidat le plus proche, observé ensuite : prend la place.
	mode.bot_goal_for(0, 3, near_pos)

	mode.fake_now += TDMMode.KILL_DELAY_MAX + 0.1
	var bot1_after: Vector3 = mode.bot_goal_for(0, 1, far_pos)
	var bot3_after: Vector3 = mode.bot_goal_for(0, 3, near_pos)

	assert_bool(bot3_after.distance_to(kill_pos) <= 3.5).append_failure_message(
		"le bot hors-lane le PLUS PROCHE du kill doit être l'unique titulaire mobilisé"
	).is_true()
	assert_bool(bot1_after.distance_to(kill_pos) <= 3.5).append_failure_message(
		"le bot hors-lane déplacé (moins proche) ne doit plus être mobilisé par ce kill — au plus UN par évènement"
	).is_false()


# ======================================================================
#  Non-régression : la lane PROPRE reste mobilisable SANS la restriction de
#  laisse (seuils SIGHTING_MOBILIZE_RANGE/KILL_MOBILIZE_RANGE inchangés,
#  déjà couvert en détail par tests/ai/test_bot_goals.gd — vérifié ici
#  seulement pour la répartition PAR ÉQUIPE de team 1, jamais exercée
#  là-bas).
# ======================================================================
func test_same_lane_bot_of_team1_is_mobilized_by_a_sighting_without_the_out_of_lane_leash_restriction() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	# team 1 double le Canyon (BOT-31) : bot 101 -> Canyon (rang 0).
	_prime_lane_ranks(mode, 1, [101])
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var canyon_points: Array = know.lane_goals(1, "S")
	var sighting: Vector3 = canyon_points[3]  # loin de tout point Canyon "proche" (> 25 m pour certains).

	mode.report_enemy_sighting(1, sighting)
	mode.bot_goal_for(1, 101, Vector3(1000, 0, 1000))  # "inactif" (jamais patrouillé) -> éligible même lane.

	mode.fake_now += TDMMode.SIGHTING_DELAY_MAX + 0.1
	var after: Vector3 = mode.bot_goal_for(1, 101, Vector3(1000, 0, 1000))

	assert_bool(after.distance_to(sighting) <= 3.5).append_failure_message(
		"un bot INACTIF de la MÊME lane que l'info doit rester mobilisable sans la restriction hors-lane"
	).is_true()


# ======================================================================
#  BOT-31 (retour vérificateur, 2026-09-25) : le bot SEUL d'une lane doublée
#  par l'équipe ADVERSE démarre sa patrouille avancé vers le centre disputé
#  (`_opponent_doubles_lane`/`LONE_BOT_START_BIAS`), et perd sa progression de
#  couloir/son but d'investigation à la mort (`on_kill` sur `_victim_id`) —
#  voir la docstring de `SIGHTING_MOBILIZE_RANGE_OUT_OF_LANE` pour le
#  diagnostic complet (contact médian mesuré à 31,8-45,8 s, très au-dessus du
#  plafond de 9 s, avant ce correctif).
# ======================================================================
func test_lone_bot_on_an_opponent_doubled_lane_starts_advanced_toward_the_contested_centre() -> void:
	var mode: TDMMode = _wasteland_mode(TDMMode.new())
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # bot 3 -> Sud/Canyon (rang 3, SEUL — team 1 double le Canyon).
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var canyon_points: Array = know.lane_goals(0, "S")

	var first: Vector3 = mode.bot_goal_for(0, 3, canyon_points[1])

	assert_vector(first).append_failure_message(
		"le bot SEUL d'une lane doublée par l'équipe adverse ne doit plus démarrer à l'extrémité la plus proche de son spawn (point %s)" % [canyon_points[1]]
	).is_not_equal(canyon_points[1])
	# Indice avancé = MÊME formule que `TDMMode._corridor_goal`/
	# `LONE_BOT_START_BIAS` (1/3 du tronçon [1, upper]) — calculé ICI depuis
	# la longueur RÉELLE du couloir plutôt qu'un indice fixe, pour ne jamais
	# dépendre du nombre de points d'une géométrie de carte précise (v7 : 25
	# points sur "S"/Canyon, contre une géométrie plus courte auparavant).
	var upper := canyon_points.size() - 2
	var advanced_idx := 1 + int(round(float(upper - 1) * (1.0 / 3.0)))
	assert_vector(first).append_failure_message(
		"démarrage attendu au point avancé d'1/3 du tronçon vers le centre (indice %d, %s), obtenu %s" % [advanced_idx, canyon_points[advanced_idx], first]
	).is_equal(canyon_points[advanced_idx])


func test_lone_bot_on_a_lane_nobody_doubles_still_starts_at_the_lane_edge() -> void:
	var mode: TDMMode = _wasteland_mode(TDMMode.new())
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # bot 1 -> Nord (rang 1, SEUL — Nord n'est doublé par AUCUNE équipe).
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var nord_points: Array = know.lane_goals(0, "N")

	var first: Vector3 = mode.bot_goal_for(0, 1, nord_points[1])

	assert_vector(first).append_failure_message(
		"non-régression T1 : une lane que personne ne double garde son démarrage à l'extrémité proche du spawn"
	).is_equal(nord_points[1])


func test_victim_lane_progress_resets_on_death_so_its_next_life_restarts_from_the_advanced_point() -> void:
	var mode: _ClockedTDMMode = _wasteland_mode(_ClockedTDMMode.new())
	_prime_lane_ranks(mode, 0, [2, 1, 4, 3])  # bot 3 -> Sud/Canyon (rang 3, SEUL).
	var know := BotMapKnowledge.new(WastelandBots.data()["bot_knowledge"])
	var canyon_points: Array = know.lane_goals(0, "S")

	# 1re vie : but initial avancé (indice 4, voir le test dédié ci-dessus).
	var first: Vector3 = mode.bot_goal_for(0, 3, canyon_points[1])
	# Atteint ce but, tenue écoulée : progresse au point SUIVANT (indice 5) —
	# le bot s'éloigne du point de démarrage "avancé".
	mode.fake_now += 1.0
	mode.bot_goal_for(0, 3, first)
	mode.fake_now += TDMMode.LANE_HOLD_MAX + 1.0
	var advanced: Vector3 = mode.bot_goal_for(0, 3, first)
	assert_vector(advanced).append_failure_message(
		"prérequis : le bot doit avoir progressé au-delà de son but initial avant sa mort simulée"
	).is_not_equal(first)

	# Mort RÉELLE (`_victim_id` = 3, pas le `-1` des autres tests de ce
	# fichier) : la progression de couloir de la victime doit être remise à
	# zéro, sans quoi elle réapparaîtrait à son spawn en gardant `advanced`
	# comme but — un trajet complet à retraverser à CHAQUE vie plutôt qu'une
	# fois pour tout le match (voir la docstring d'`on_kill`).
	mode.on_kill(-1, 3, 1, 0)

	# 2e vie : le bot réapparaît à son spawn ; sans nouvel évènement d'équipe,
	# son but recalculé doit repartir du MÊME point avancé qu'à la 1re vie
	# (pas rester bloqué sur `advanced`, ni reprendre pile où il en était).
	var respawned_goal: Vector3 = mode.bot_goal_for(0, 3, canyon_points[0])

	assert_vector(respawned_goal).append_failure_message(
		"BOT-31 : la mort doit remettre à zéro la progression de couloir de la victime (attendu le but avancé %s, obtenu %s, ancien but non réinitialisé %s)"
		% [first, respawned_goal, advanced]
	).is_equal(first)
