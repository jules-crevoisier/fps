## test_duel_stalemate.gd
## Spec (docs/audit/bugs.md, BUG-12) : Duel 1v1 / Duo 2v2, impasse sur la zone
## de capture centrale (le temps de manche s'écoule sans élimination totale) —
## sans garde-fou, la manche ne se terminait JAMAIS si personne ne tenait seul
## la zone (`DuelMode.gd:76-127` avant ce correctif : aucune limite après
## `_capture_active`). Couvre les deux volets du critère d'acceptation :
##   1. 45 s après l'activation de la zone sans capture -> mort subite : le
##      PROCHAIN kill décide la manche, même sans élimination totale de
##      l'équipe adverse (utile en Duo 2v2, où il peut rester un survivant de
##      chaque côté hors zone, qui bloquerait `_team_all_dead`) ;
##   2. si toujours rien 20 s de plus (65 s au total depuis l'activation) ->
##      décision forcée à la somme des PV restants de chaque équipe, égalité
##      -> victoire des défenseurs (`attacking_team()`).
##
## Technique : DuelMode instancié et piloté par appel DIRECT de ses méthodes
## (`_on_round_timeout`, `_tick_capture`, `on_kill`...), jamais son `_ready()`/
## le moteur livrés à eux-mêmes — même choix que tests/modes/
## test_game_mode_tiebreak.gd (GameMode) et tests/agents/
## test_round_props_cleanup.gd (RoundMode), pour éviter tout aléa de
## `call_deferred` (RoundMode._ready -> `_enter_buy_phase` différé). Joueurs
## factices minimaux (Node3D + `team` + enfant "Health" RÉEL) pour peupler
## `RoundMode._players()`/`_team_all_dead` sans scène de joueur réelle — même
## esprit que le `_FakeWorld` de tests/ai/test_bot_goals.gd. La zone de
## capture elle-même (Area3D, contestation) n'est pas modifiée par ce
## correctif et n'est donc pas retestée ici : seule la garantie de fin de
## manche après coup l'est.
extends GdUnitTestSuite

const SUDDEN_DEATH_DELAY := DuelMode.STALEMATE_SUDDEN_DEATH_DELAY       # 45 s
const FORCED_DECISION_DELAY := DuelMode.STALEMATE_FORCED_DECISION_DELAY # 20 s
const TOTAL_TO_FORCED_DECISION := SUDDEN_DEATH_DELAY + FORCED_DECISION_DELAY # 65 s


## Double minimal du nœud "match" (GameWorld) : seul `players_root` est lu par
## RoundMode._players()/_team_all_dead (voir sa doc d'en-tête).
class _FakeWorld extends Node3D:
	var players_root: NodePath = ^"Players"


## Joueur factice minimal : un `team` (lu par `int(child.get("team"))`, comme
## un vrai PlayerController) — l'enfant "Health" réel est ajouté séparément.
class _FakePlayer extends Node3D:
	var team: int = 0


func _make_world() -> Node3D:
	var world := _FakeWorld.new()
	world.add_to_group("match")
	var players_node := Node3D.new()
	players_node.name = "Players"
	world.add_child(players_node)
	add_child(world)
	auto_free(world)
	return world


## Ajoute un joueur factice de `team` avec `hp` PV restants (mort si <= 0) au
## monde `world`. Renvoie son composant Health (autoritaire, voir Health.gd)
## pour d'éventuelles manipulations supplémentaires par l'appelant.
func _add_player(world: Node3D, id: int, team: int, hp: float) -> Health:
	var player := _FakePlayer.new()
	player.name = str(id)
	player.team = team
	var health := Health.new()
	health.name = "Health"
	player.add_child(health)
	world.get_node("Players").add_child(player)
	auto_free(player)
	health.current_health = hp
	health.is_dead = hp <= 0.0
	return health


func _new_mode() -> DuelMode:
	var mode := DuelMode.new()
	add_child(mode)
	auto_free(mode)
	# Un seul round décide directement le match : simplifie les assertions sur
	# `mode.winner` (sinon `end_round()` n'incrémenterait que `round_state.
	# wins[team]`, sans vainqueur de MATCH avant `rounds_to_win` manches).
	mode.round_state.rounds_to_win = 1
	mode.round_state.start_live()  # on_kill/_tick_capture n'agissent qu'en phase LIVE.
	return mode


# ======================================================================
#  Activation de la zone : remise à zéro de l'horloge d'impasse.
# ======================================================================
func test_zone_activation_starts_the_stalemate_clock_at_zero() -> void:
	var mode := _new_mode()

	mode._on_round_timeout()

	assert_bool(mode._capture_active).is_true()
	assert_float(mode._capture_active_elapsed).is_equal(0.0)
	assert_bool(mode._stalemate_sudden_death).append_failure_message(
		"la mort subite ne doit pas être engagée dès l'activation de la zone"
	).is_false()


# ======================================================================
#  Avant 45 s : comportement normal (non-régression) — un kill sans
#  élimination totale de l'équipe adverse ne doit PAS terminer la manche.
# ======================================================================
func test_kill_without_full_team_wipe_before_45s_does_not_end_the_round() -> void:
	var world := _make_world()
	# Équipe adverse (1) façon Duo : un mort, un survivant -> pas d'élimination totale.
	_add_player(world, 101, 1, 0.0)
	_add_player(world, 102, 1, 60.0)
	var mode := _new_mode()
	mode._on_round_timeout()

	mode._tick_capture(SUDDEN_DEATH_DELAY - 0.1)
	assert_bool(mode._stalemate_sudden_death).append_failure_message(
		"préalable du test : la mort subite ne doit pas encore être engagée avant 45 s"
	).is_false()

	mode.on_kill(1, 101, 0, 1)

	assert_int(mode.winner).append_failure_message(
		"avant 45 s, un kill sans élimination totale de l'équipe adverse ne doit pas décider la manche"
	).is_equal(-1)


# ======================================================================
#  BUG-12, volet 1 : 45 s après l'activation sans capture -> mort subite,
#  le PROCHAIN kill décide même sans élimination totale de l'équipe adverse.
# ======================================================================
func test_45s_after_zone_activation_engages_sudden_death() -> void:
	var mode := _new_mode()
	mode._on_round_timeout()

	mode._tick_capture(SUDDEN_DEATH_DELAY)

	assert_bool(mode._stalemate_sudden_death).append_failure_message(
		"45 s après l'activation de la zone sans capture : la mort subite doit être engagée"
	).is_true()
	assert_int(mode.winner).append_failure_message(
		"la mort subite ne décide rien à elle seule : il faut encore un kill"
	).is_equal(-1)


func test_next_kill_after_sudden_death_engaged_wins_the_round_without_full_team_wipe() -> void:
	var world := _make_world()
	# Duo : équipe 1 garde un survivant (102) -> _team_all_dead(1) resterait
	# faux sans la mort subite (BUG-12 : la manche resterait bloquée).
	_add_player(world, 101, 1, 0.0)
	_add_player(world, 102, 1, 60.0)
	var mode := _new_mode()
	mode._on_round_timeout()
	mode._tick_capture(SUDDEN_DEATH_DELAY)

	mode.on_kill(1, 101, 0, 1)  # tueur équipe 0, victime équipe 1 — 102 reste en vie.

	assert_int(mode.winner).append_failure_message(
		"BUG-12 : passé la mort subite, le PROCHAIN kill doit décider la manche même sans élimination totale"
	).is_equal(0)


func test_kill_for_the_same_team_never_ends_the_round_even_during_sudden_death() -> void:
	var mode := _new_mode()
	mode._on_round_timeout()
	mode._tick_capture(SUDDEN_DEATH_DELAY)

	mode.on_kill(1, 2, 0, 0)  # tueur et victime dans la même équipe (tir ami) : ignoré.

	assert_int(mode.winner).is_equal(-1)


# ======================================================================
#  BUG-12, volet 2 : 65 s (45 + 20) après l'activation, toujours aucun
#  vainqueur -> décision forcée à la somme des PV restants de chaque équipe.
# ======================================================================
func test_65s_without_a_winner_forces_a_decision_for_the_team_with_more_remaining_health() -> void:
	var world := _make_world()
	_add_player(world, 201, 0, 80.0)
	_add_player(world, 202, 0, 40.0)  # équipe 0 : 120 PV restants au total.
	_add_player(world, 203, 1, 50.0)
	_add_player(world, 204, 1, 30.0)  # équipe 1 : 80 PV restants au total.
	var mode := _new_mode()
	mode._on_round_timeout()

	mode._tick_capture(TOTAL_TO_FORCED_DECISION)

	assert_int(mode.winner).append_failure_message(
		"BUG-12 : 65 s sans vainqueur -> décision forcée pour l'équipe qui a le plus de PV restants"
	).is_equal(0)


func test_65s_without_a_winner_forces_a_decision_for_the_other_team_when_it_has_more_health() -> void:
	var world := _make_world()
	_add_player(world, 201, 0, 20.0)
	_add_player(world, 203, 1, 90.0)
	var mode := _new_mode()
	mode._on_round_timeout()

	mode._tick_capture(TOTAL_TO_FORCED_DECISION)

	assert_int(mode.winner).is_equal(1)


func test_65s_without_a_winner_and_tied_health_goes_to_the_defenders() -> void:
	var world := _make_world()
	_add_player(world, 201, 0, 50.0)
	_add_player(world, 203, 1, 50.0)  # égalité de PV restants.
	var mode := _new_mode()
	mode.sides_swapped = false  # attaquants = équipe 0 -> défenseurs = équipe 1.
	mode._on_round_timeout()

	mode._tick_capture(TOTAL_TO_FORCED_DECISION)

	assert_int(mode.winner).append_failure_message(
		"BUG-12 : égalité de PV restants à la décision forcée -> victoire des défenseurs"
	).is_equal(1)


func test_65s_without_a_winner_and_tied_health_follows_the_defending_side_after_a_swap() -> void:
	var world := _make_world()
	_add_player(world, 201, 0, 50.0)
	_add_player(world, 203, 1, 50.0)  # égalité de PV restants.
	var mode := _new_mode()
	mode.sides_swapped = true  # attaquants = équipe 1 -> défenseurs = équipe 0.
	mode._on_round_timeout()

	mode._tick_capture(TOTAL_TO_FORCED_DECISION)

	assert_int(mode.winner).append_failure_message(
		"la définition des défenseurs doit suivre attacking_team(), pas rester figée sur l'équipe 1"
	).is_equal(0)


func test_between_45s_and_65s_no_forced_decision_yet_without_a_kill() -> void:
	var world := _make_world()
	_add_player(world, 201, 0, 80.0)
	_add_player(world, 203, 1, 20.0)
	var mode := _new_mode()
	mode._on_round_timeout()

	mode._tick_capture(TOTAL_TO_FORCED_DECISION - 0.1)

	assert_int(mode.winner).append_failure_message(
		"avant 65 s pleins, la décision forcée aux PV ne doit pas encore être tombée"
	).is_equal(-1)


# ======================================================================
#  Une nouvelle manche remet l'horloge d'impasse à zéro (pas de mort subite
#  héritée de la manche précédente).
# ======================================================================
func test_new_round_resets_the_stalemate_clock_and_sudden_death_flag() -> void:
	var mode := _new_mode()
	mode._on_round_timeout()
	mode._tick_capture(SUDDEN_DEATH_DELAY)
	assert_bool(mode._stalemate_sudden_death).is_true()

	mode._on_new_round()

	assert_float(mode._capture_active_elapsed).is_equal(0.0)
	assert_bool(mode._stalemate_sudden_death).append_failure_message(
		"une nouvelle manche ne doit pas hériter de la mort subite de la précédente"
	).is_false()
	assert_bool(mode._capture_active).is_false()
