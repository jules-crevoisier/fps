## test_rematch.gd
## Spec FUN-01 (docs/research/05_fun_retention.md §2.1 « Session (10–30 min) :
## un match, un écran de fin ... puis on rejoue », §5) : enchaînement de
## session -- un compte à rebours SERVEUR de 10 s relance automatiquement le
## MÊME mode et la MÊME carte (aucun changement de scène : seul l'état est
## remis à zéro) si la MAJORITÉ des humains connus à la fin du match n'a pas
## quitté ; sinon la revanche automatique est simplement abandonnée. Les stats
## par joueur (kills/morts) sont remises à zéro, les bots sont gardés, les
## équipes rééquilibrées.
## Prototype à interface minimale (2026-09-26) : EndPanel.gd (l'écran de fin
## qui affichait ce compte à rebours) a été supprimé avec le reste du HUD —
## les tests qui le couvraient sont partis avec lui ; ce fichier ne garde que
## la logique SERVEUR (GameWorld) du compte à rebours/rééquilibrage, qui ne
## dépend d'aucun écran.
##
## Style des doubles : `_TestGameWorld` court-circuite `_ready()` (réseau/
## télémétrie/sélection d'agent, hors sujet ici), exactement comme
## tests/networking/test_respawn_refill.gd et tests/player/test_ping.gd. Les
## « joueurs » sont des doubles légers (`_PlayerDouble`, un seul champ `team`,
## comme `_FakePlayer` de test_ping.gd) : aucune scène `player.tscn` n'est
## nécessaire pour prouver `player_info`/le rééquilibrage d'équipe/l'horodatage
## de spawn (`_spawn_time`, alimenté par `_mark_spawned` -- voir
## `respawn_all_for_round` dans GameWorld.gd, appelé SANS condition pour CHAQUE
## enfant de `players_root`, doubles compris).
##
## `rematch_countdown_s` est raccourci en test (même convention que
## `respawn_delay` dans test_respawn_refill.gd) : `_run_rematch_countdown`
## proportionne la durée d'un tic à cette valeur (voir sa doc dans
## GameWorld.gd), donc un réglage court ne coûte jamais une seconde réelle
## pleine par tic.
extends GdUnitTestSuite


## Double minimal d'un mode de jeu -- `winner`/`respawns_immediately`/
## `reset_match` sont les 3 seuls membres lus par le code de revanche
## (`_watch_for_match_end`/`reset_match` de GameWorld.gd), jamais GameMode.gd
## lui-même (hors de ma liste de fichiers). `reset_match` imite
## `GameMode.reset_match()` : remet `winner` à -1 (voir tests/modes/
## test_rematch_reset.gd pour le contrat réel sur GameMode.gd).
class _ModeDouble extends Node:
	var winner: int = -1
	func respawns_immediately() -> bool:
		return true
	func reset_match() -> void:
		winner = -1


## Double minimal d'un joueur répliqué -- `Node3D` (pas un simple `Node`) :
## `_living_enemy_positions`/`_living_ally_positions`/`_record_recent_death`
## castent chaque enfant de `players_root` en `Node3D` pour lire
## `global_position` (voir GameWorld.gd), un simple `Node` y échouerait
## silencieusement ("Nil"). Seul `team` est ensuite lu/écrit par
## `_rebalance_teams_for_rematch` (`node.set("team", ...)`) ; `respawn_all_
## for_round` gère un double sans `Health`/`Weapon`/`server_respawn` sans
## erreur (branches optionnelles, voir sa doc dans GameWorld.gd), et
## `_mark_spawned` s'exécute pour lui EXACTEMENT comme pour un vrai joueur.
class _PlayerDouble extends Node3D:
	var team: int = -1


class _TestGameWorld extends GameWorld:
	func _ready() -> void:
		set_multiplayer_authority(1)
		add_to_group("match")



func _new_world(countdown_s: float = 0.06) -> GameWorld:
	var world := _TestGameWorld.new()
	add_child(world)
	auto_free(world)
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)
	world.rematch_countdown_s = countdown_s
	return world


func _new_mode(world: GameWorld) -> _ModeDouble:
	var mode := _ModeDouble.new()
	mode.add_to_group("game_mode")
	world.add_child(mode)
	auto_free(mode)
	return mode


## Ajoute une entrée `player_info` ET un double de joueur répliqué sous
## `players_root`, comme le ferait `_spawn_player` (sans son réseau/ses RPC).
func _add_player(world: GameWorld, id: int, team: int, is_bot: bool) -> void:
	world.player_info[id] = {
		"name": ("BOT %d" % id) if is_bot else ("Joueur %d" % id),
		"team": team, "kills": 3, "deaths": 2, "is_bot": is_bot,
	}
	var node := _PlayerDouble.new()
	node.name = str(id)
	node.team = team
	world.get_node(world.players_root).add_child(node)
	auto_free(node)


## Simule la fin du match (le mode désigne un vainqueur) puis fait tourner
## UNE frame serveur -- exactement ce que `_process` ferait en jeu réel (voir
## `_watch_for_match_end`, appelé directement ici comme tests/modes/
## test_no_peer.gd appelle `mode._physics_process(DT)` directement).
func _end_match(world: GameWorld, mode: _ModeDouble, winner: int = 0) -> void:
	mode.winner = winner
	world._process(0.0)


func _wait_out_countdown(world: GameWorld, margin_ms: int = 200) -> void:
	await await_millis(int(world.rematch_countdown_s * 1000.0) + margin_ms)


# ======================================================================
#  1. Contrat : compte à rebours de 10 s par défaut.
# ======================================================================

func test_default_countdown_is_ten_seconds() -> void:
	var world := _TestGameWorld.new()
	add_child(world)
	auto_free(world)
	assert_float(world.rematch_countdown_s).append_failure_message(
		"FUN-01 : le compte à rebours par défaut doit être de 10 s"
	).is_equal_approx(10.0, 0.001)


# ======================================================================
#  2. Logique pure (aucune attente réelle) : présence humaine / majorité.
# ======================================================================

func test_human_ids_present_excludes_bots() -> void:
	var world := _new_world()
	_add_player(world, 1, 0, false)
	_add_player(world, 9101, 0, true)
	assert_array(world._human_ids_present()).is_equal([1])


func test_majority_of_humans_still_present_true_when_all_stayed() -> void:
	var world := _new_world()
	_add_player(world, 1, 0, false)
	_add_player(world, 2, 1, false)
	assert_bool(world._majority_of_humans_still_present([1, 2])).is_true()


func test_majority_of_humans_still_present_true_at_the_exact_tie() -> void:
	# 1 sur 2 encore présent = moitié = majorité "n'a pas quitté" (pas strict).
	var world := _new_world()
	_add_player(world, 1, 0, false)
	assert_bool(world._majority_of_humans_still_present([1, 2])).is_true()


func test_majority_of_humans_still_present_false_when_majority_left() -> void:
	var world := _new_world()
	_add_player(world, 1, 0, false)
	assert_bool(world._majority_of_humans_still_present([1, 2, 3])).append_failure_message(
		"1 humain restant sur 3 = minorité : pas de revanche automatique"
	).is_false()


func test_majority_of_humans_still_present_false_when_no_humans_were_present() -> void:
	var world := _new_world()
	assert_bool(world._majority_of_humans_still_present([])).append_failure_message(
		"aucun humain à la fin du match (ex. training bots seuls) : rien à relancer automatiquement"
	).is_false()


func test_rebalance_teams_alternates_by_sorted_id() -> void:
	var world := _new_world()
	_add_player(world, 3, 0, false)
	_add_player(world, 1, 0, false)
	_add_player(world, 2, 0, false)

	world._rebalance_teams_for_rematch()

	assert_int(int(world.player_info[1].team)).is_equal(0)
	assert_int(int(world.player_info[2].team)).is_equal(1)
	assert_int(int(world.player_info[3].team)).is_equal(0)


# ======================================================================
#  3. Majorité des humains restée -> revanche automatique de bout en bout.
# ======================================================================

func test_majority_stayed_triggers_automatic_rematch() -> void:
	var world := _new_world()
	var mode := _new_mode(world)
	_add_player(world, 1, 0, false)
	_add_player(world, 2, 1, false)
	var match_id_before := world._match_id

	_end_match(world, mode)
	await _wait_out_countdown(world)

	assert_int(mode.winner).append_failure_message(
		"la revanche automatique doit relancer le mode (winner remis à -1)"
	).is_equal(-1)
	assert_str(world._match_id).append_failure_message(
		"un nouveau match_id doit être généré (télémétrie FUN-01)"
	).is_not_equal(match_id_before)


func test_majority_stayed_resets_every_players_stats_to_zero() -> void:
	var world := _new_world()
	var mode := _new_mode(world)
	_add_player(world, 1, 0, false)
	_add_player(world, 2, 1, false)
	_add_player(world, 9101, 0, true)

	_end_match(world, mode)
	await _wait_out_countdown(world)

	for id in world.player_info:
		assert_int(int(world.player_info[id].kills)).append_failure_message(
			"les kills de %s doivent être remis à zéro après la revanche" % id
		).is_equal(0)
		assert_int(int(world.player_info[id].deaths)).append_failure_message(
			"les morts de %s doivent être remises à zéro après la revanche" % id
		).is_equal(0)


func test_majority_stayed_keeps_the_bots() -> void:
	var world := _new_world()
	var mode := _new_mode(world)
	_add_player(world, 1, 0, false)
	_add_player(world, 2, 1, false)
	_add_player(world, 9101, 0, true)
	_add_player(world, 9102, 1, true)

	_end_match(world, mode)
	await _wait_out_countdown(world)

	assert_bool(world.player_info.has(9101)).append_failure_message(
		"un bot ne doit jamais être retiré par la revanche automatique (« bots gardés »)"
	).is_true()
	assert_bool(world.player_info.has(9102)).is_true()
	assert_bool(bool(world.player_info[9101].is_bot)).is_true()
	assert_bool(bool(world.player_info[9102].is_bot)).is_true()


func test_majority_stayed_measures_end_to_new_spawn_within_twenty_seconds() -> void:
	var world := _new_world()
	var mode := _new_mode(world)
	_add_player(world, 1, 0, false)
	_add_player(world, 2, 1, false)

	var t_end := Time.get_unix_time_from_system()
	_end_match(world, mode)
	await _wait_out_countdown(world)

	assert_bool(world._spawn_time.has(1)).append_failure_message(
		"un nouveau spawn doit avoir été enregistré après la revanche (_mark_spawned, respawn_all_for_round)"
	).is_true()
	var delay: float = float(world._spawn_time[1]) - t_end
	assert_float(delay).append_failure_message(
		"contrat FUN-01 : délai fin -> nouveau spawn mesuré à %.2f s, doit rester <= 20 s" % delay
	).is_less_equal(20.0)


# ======================================================================
#  4. Équipes rééquilibrées (têtes, humains + bots confondus) à la revanche.
# ======================================================================

func test_majority_stayed_rebalances_team_headcounts() -> void:
	var world := _new_world()
	var mode := _new_mode(world)
	# Déséquilibre volontaire avant la revanche : 3 têtes équipe 0, 1 équipe 1.
	_add_player(world, 1, 0, false)
	_add_player(world, 9101, 0, true)
	_add_player(world, 9102, 0, true)
	_add_player(world, 2, 1, false)

	_end_match(world, mode)
	await _wait_out_countdown(world)

	var count0 := 0
	var count1 := 0
	for id in world.player_info:
		if int(world.player_info[id].team) == 0:
			count0 += 1
		else:
			count1 += 1
	assert_int(absi(count0 - count1)).append_failure_message(
		"les équipes doivent être rééquilibrées à la revanche : écart observé %d (équipe 0) / %d (équipe 1)" % [count0, count1]
	).is_less_equal(1)


func test_rebalance_also_updates_the_replicated_players_team_property() -> void:
	var world := _new_world()
	var mode := _new_mode(world)
	_add_player(world, 1, 0, false)
	_add_player(world, 9101, 0, true)
	_add_player(world, 2, 1, false)

	_end_match(world, mode)
	await _wait_out_countdown(world)

	for id in world.player_info:
		var node := world.get_node(world.players_root).get_node_or_null(str(id))
		assert_bool(node != null).append_failure_message(
			"le joueur %s doit toujours exister sous players_root après la revanche" % id
		).is_true()
		assert_int(int(node.team)).append_failure_message(
			"le champ répliqué `team` du nœud joueur %s doit suivre player_info après le rééquilibrage" % id
		).is_equal(int(world.player_info[id].team))


# ======================================================================
#  5. Majorité des humains partie (minorité restante) -> pas de revanche auto.
# ======================================================================

func test_minority_remaining_does_not_trigger_automatic_rematch() -> void:
	var world := _new_world()
	var mode := _new_mode(world)
	_add_player(world, 1, 0, false)
	_add_player(world, 2, 1, false)
	_add_player(world, 3, 0, false)

	_end_match(world, mode)
	var match_id_before := world._match_id
	# 2 humains sur 3 quittent PENDANT le compte à rebours (même effet que
	# « Menu » -> déconnexion, voir `_on_player_disconnected`) : la minorité
	# restante ne doit PAS relancer automatiquement.
	world._on_player_disconnected(2)
	world._on_player_disconnected(3)
	assert_int(world.player_info.size()).append_failure_message(
		"préalable du test : player_info ne doit garder que l'id 1 juste après les deux déconnexions : %s" % [world.player_info.keys()]
	).is_equal(1)
	await _wait_out_countdown(world)

	assert_int(mode.winner).append_failure_message(
		"la majorité des humains est partie : le mode ne doit pas être relancé automatiquement, et ne doit plus jamais l'être pour CETTE fin de match (pas de nouvel essai automatique)"
	).is_equal(0)
	assert_str(world._match_id).append_failure_message(
		"aucun nouveau match_id ne doit être généré si la revanche automatique est abandonnée"
	).is_equal(match_id_before)


## Régression : une revanche automatique ABANDONNÉE (majorité partie) ne doit
## jamais se relancer d'elle-même en boucle tant que le mode garde son
## vainqueur (bug constaté pendant le développement : `_rematch_watch_active`
## se remettait à faux même dans la branche « abandonnée », ce qui laissait
## `_watch_for_match_end` repartir pour un second compte à rebours dès la
## frame suivante — avec un `humans_at_end` capturé APRÈS le départ, pouvant à
## tort déclencher une revanche). Attente LARGEMENT plus longue que le
## compte à rebours (plusieurs cycles auraient eu le temps de retenter).
func test_abandoned_rematch_never_retries_on_subsequent_frames() -> void:
	var world := _new_world()
	var mode := _new_mode(world)
	_add_player(world, 1, 0, false)
	_add_player(world, 2, 1, false)

	_end_match(world, mode)
	world._on_player_disconnected(1)
	world._on_player_disconnected(2)  # plus aucun humain : jamais de majorité restante
	await await_millis(2000)

	assert_int(mode.winner).append_failure_message(
		"aucun humain restant : la revanche automatique doit rester abandonnée, jamais retentée en boucle"
	).is_equal(0)
	assert_bool(world.player_info.is_empty()).append_failure_message(
		"aucun bot n'a de raison d'apparaître ici (allow_bot_fill désactivé par défaut)"
	).is_true()


func test_only_bots_present_never_triggers_an_automatic_rematch() -> void:
	var world := _new_world()
	var mode := _new_mode(world)
	_add_player(world, 9101, 0, true)
	_add_player(world, 9102, 1, true)

	_end_match(world, mode)
	await _wait_out_countdown(world)

	assert_int(mode.winner).append_failure_message(
		"aucun humain présent à la fin du match : rien à relancer automatiquement"
	).is_equal(0)


# ======================================================================
#  6. Un « Rejouer » manuel pendant le compte à rebours empêche un second reset.
# ======================================================================

func test_manual_reset_during_countdown_prevents_a_second_automatic_reset() -> void:
	var world := _new_world(0.2)
	var mode := _new_mode(world)
	_add_player(world, 1, 0, false)
	_add_player(world, 2, 1, false)

	_end_match(world, mode)
	await await_millis(30)
	world.reset_match()  # « Rejouer » manuel immédiat (avant la fin du compte à rebours)
	var match_id_after_manual := world._match_id

	await _wait_out_countdown(world, 250)

	assert_str(world._match_id).append_failure_message(
		"la revanche automatique arrivée après un « Rejouer » manuel ne doit pas déclencher un second reset_match()"
	).is_equal(match_id_after_manual)


# ======================================================================
#  7. Diffusion du compte à rebours -- EndPanel.gd s'y abonne (voir plus bas).
# ======================================================================

func test_rematch_countdown_signal_ticks_down_to_zero_when_the_lone_human_stays() -> void:
	var world := _new_world()
	var mode := _new_mode(world)
	_add_player(world, 1, 0, false)
	var ticks: Array = []
	world.rematch_countdown.connect(func(seconds_left: int) -> void: ticks.append(seconds_left))

	_end_match(world, mode)
	await _wait_out_countdown(world)

	assert_bool(ticks.is_empty()).append_failure_message(
		"le compte à rebours doit démarrer dès la fin du match (au moins une diffusion)"
	).is_false()
	assert_int(ticks[ticks.size() - 1]).append_failure_message(
		"la dernière valeur diffusée doit être 0 juste avant la revanche (l'unique humain est resté)"
	).is_equal(0)


func test_rematch_countdown_signal_reports_minus_one_when_the_rematch_is_abandoned() -> void:
	var world := _new_world()
	var mode := _new_mode(world)
	_add_player(world, 1, 0, false)
	_add_player(world, 2, 1, false)
	var ticks: Array = []
	world.rematch_countdown.connect(func(seconds_left: int) -> void: ticks.append(seconds_left))

	_end_match(world, mode)
	world._on_player_disconnected(1)
	world._on_player_disconnected(2)
	await _wait_out_countdown(world)

	assert_int(ticks[ticks.size() - 1]).append_failure_message(
		"tous les humains sont partis : la dernière diffusion doit signaler l'annulation (-1)"
	).is_equal(-1)
