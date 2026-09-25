## test_no_peer.gd
## Spec BUG-27 (docs/audit/bugs.md, relevé par la vérification ART-31) :
## GameMode.gd:75/292 et TDMMode.gd:47-62 appelaient `multiplayer.is_server()`
## NU. Godot ne garantit ce résultat que si un pair est assigné — sinon (voir
## la doc officielle Godot "high_level_multiplayer"/OfflineMultiplayerPeer,
## et le code source `scene_multiplayer.cpp::get_unique_id`) le moteur
## journalise "No multiplayer peer is assigned. Unable to get unique ID."
## (ERR_FAIL_COND_V_MSG) ET renvoie FAUX. Deux chemins RÉELS y mènent :
##   1. un mode instancié SEUL, jamais connecté (entraînement hors ligne,
##      écran de sélection, `tools/review/ui_shots.gd` qui charge tdm_map.tscn
##      sans jamais appeler `NetworkManager.host()`/`join()`) — Godot n'a
##      alors JAMAIS assigné le moindre pair au `SceneTree.multiplayer` ;
##   2. `NetworkManager.disconnect_from_game()` (scripts/networking/
##      NetworkManager.gd) remet `multiplayer.multiplayer_peer` à `null` (au
##      lieu d'un nouvel `OfflineMultiplayerPeer`, contrairement à ce que
##      recommande la doc officielle "Terminating Network Connection").
## Dans les DEUX cas, l'ancien code (`if not multiplayer.is_server(): return`)
## traitait ce FAUX comme "je suis un client, pas le serveur" et sautait TOUTE
## la logique autoritaire (scores, minuteries, IA, reset) au lieu de la faire
## tourner — alors qu'ici l'absence de pair EST la simulation locale
## autoritaire (aucun serveur distant à attendre). Le correctif ajoute une
## garde COMMUNE, `GameMode._is_authoritative()` (pair absent OU
## `is_server()`), utilisée par GameMode ET TDMMode (voir leurs docstrings).
##
## Ce fichier réplique EXACTEMENT la condition du bug (`multiplayer.
## multiplayer_peer = null`, comme après `disconnect_from_game()` — et le cas
## le plus strict : un mode qui n'a jamais eu de pair a le même
## `multiplayer_peer` nul dès l'instanciation dans gdUnit4, voir `before_test`)
## puis vérifie, pour un mode TDM instancié sans scène/pair réel (même
## technique que test_game_mode_tiebreak.gd/test_rematch_reset.gd) :
##   - AUCUNE erreur moteur "No multiplayer peer is assigned" n'est journalisée
##     (`assert_error(...).is_success()`, voir GdUnitGodotErrorAssertImpl) ;
##   - la logique autoritaire tourne RÉELLEMENT (scores, minuterie de match,
##     changement de côté, reset) au lieu d'être silencieusement gelée — un
##     simple "pas d'erreur" ne suffirait pas à prouver que le correctif est le
##     bon (une garde qui neutraliserait juste `multiplayer.is_server()` sans
##     jamais exécuter le code ferait aussi taire l'erreur).
extends GdUnitTestSuite

const DT := 1.0 / 60.0

## Le peer par défaut du SceneTree (OfflineMultiplayerPeer, voir doc Godot
## "OfflineMultiplayerPeer" : `is_server() == true` tant que rien ne l'a
## remplacé) — sauvegardé/restauré à chaque test pour ne polluer NI les autres
## tests de cette suite NI ceux d'une suite voisine exécutée dans le même
## process gdUnit4 (mêmes précautions que test_match_config_sync.gd pour
## MatchConfig, mais ici sur l'état multijoueur partagé de l'arbre de scène).
var _saved_peer: MultiplayerPeer


func before_test() -> void:
	_saved_peer = multiplayer.multiplayer_peer


func after_test() -> void:
	multiplayer.multiplayer_peer = _saved_peer


## Reproduit précisément `NetworkManager.disconnect_from_game()` — et, de
## façon équivalente pour ce test, un mode qui n'a simplement jamais eu de
## pair (entraînement hors ligne / écran de sélection / ui_shots).
func _clear_peer() -> void:
	multiplayer.multiplayer_peer = null


func _new_tdm() -> TDMMode:
	var mode := TDMMode.new()
	add_child(mode)
	auto_free(mode)
	return mode


func _new_game_mode(time_limit: float = 0.0) -> GameMode:
	var mode := GameMode.new()
	mode.match_time_limit = time_limit
	add_child(mode)
	auto_free(mode)
	return mode


# ----------------------------------------------------------------------
#  GameMode._physics_process (minuterie de match commune) : doit avancer
#  ET amener à une décision, sans pair, exactement comme
#  test_game_mode_tiebreak.gd le prouve AVEC le pair par défaut.
# ----------------------------------------------------------------------
func test_game_mode_physics_process_runs_without_a_peer() -> void:
	_clear_peer()
	var mode := _new_game_mode()
	mode.team_scores = [4.0, 2.0]

	await assert_error(func() -> void:
		mode._physics_process(DT)
	).is_success()

	assert_float(mode.match_elapsed).is_greater(0.0)
	assert_int(mode.winner) \
		.append_failure_message("sans pair, la minuterie de match doit quand même trancher (simulation locale autoritaire)") \
		.is_equal(0)


## reset_match() de la classe de base : doit remettre scores/vainqueur à
## zéro sans pair (revanche en entraînement hors ligne / après une
## déconnexion, voir docstring d'en-tête).
func test_game_mode_reset_match_runs_without_a_peer() -> void:
	_clear_peer()
	var mode := _new_game_mode()
	mode.team_scores = [12.0, 7.0]
	mode.winner = 0

	await assert_error(func() -> void:
		mode.reset_match()
	).is_success()

	assert_int(mode.winner).is_equal(-1)
	assert_float(mode.team_scores[0]).is_equal(0.0)
	assert_float(mode.team_scores[1]).is_equal(0.0)


# ----------------------------------------------------------------------
#  TDMMode.on_kill : chemin de score direct (visé par la note du contrat,
#  TDMMode.gd:61-68 avant correctif) — le tableau des scores affiché par
#  ui_shots dépend directement de ce chemin.
# ----------------------------------------------------------------------
func test_tdm_on_kill_scores_without_a_peer() -> void:
	_clear_peer()
	var mode := _new_tdm()

	await assert_error(func() -> void:
		mode.on_kill(100, 200, 0, 1)
	).is_success()

	assert_int(mode.team_score(0)) \
		.append_failure_message("sans pair, on_kill() doit quand même créditer l'équipe du tueur") \
		.is_equal(1)
	assert_int(mode.team_score(1)).is_equal(0)


## Idem jusqu'à la victoire par score (score_to_win) : preuve que check_win()
## (appelé depuis on_kill) tranche bien, pas seulement que le compteur avance.
func test_tdm_on_kill_can_decide_the_match_without_a_peer() -> void:
	_clear_peer()
	var mode := _new_tdm()
	mode.score_to_win = 1

	await assert_error(func() -> void:
		mode.on_kill(100, 200, 0, 1)
	).is_success()

	assert_int(mode.winner).is_equal(0)


# ----------------------------------------------------------------------
#  TDMMode._physics_process : minuterie de match (hérité) + changement de
#  côté (asymmetric_map) — les deux branches gardées par
#  `multiplayer.is_server()` avant correctif (TDMMode.gd:55-59).
# ----------------------------------------------------------------------
func test_tdm_physics_process_runs_without_a_peer() -> void:
	_clear_peer()
	var mode := _new_tdm()
	mode.match_time_limit = 0.0
	mode.team_scores = [10.0, 3.0]

	await assert_error(func() -> void:
		mode._physics_process(DT)
	).is_success()

	assert_int(mode.winner) \
		.append_failure_message("sans pair, TDMMode doit hériter la même décision de fin de match que GameMode") \
		.is_equal(0)


func test_tdm_physics_process_swaps_sides_without_a_peer() -> void:
	_clear_peer()
	var mode := _new_tdm()
	mode.asymmetric_map = true
	mode.match_time_limit = 100.0
	mode.match_elapsed = 90.0  # bien passé la moitié du temps (HalfTime.should_swap).

	await assert_error(func() -> void:
		mode._physics_process(DT)
	).is_success()

	assert_bool(mode.sides_swapped) \
		.append_failure_message("sans pair, le changement de côté (carte asymétrique) doit quand même se décider") \
		.is_true()


## reset_match() surchargé par TDMMode (côté + score de base) : la revanche
## (BUG-11) doit rester intacte sans pair.
func test_tdm_reset_match_runs_without_a_peer() -> void:
	_clear_peer()
	var mode := _new_tdm()
	mode.sync_sides_swapped(true, "CHANGEMENT DE CÔTÉ")
	mode.team_scores = [40.0, 12.0]
	mode.winner = 0

	await assert_error(func() -> void:
		mode.reset_match()
	).is_success()

	assert_bool(mode.sides_swapped).is_false()
	assert_str(mode.side_swap_notice).is_equal("")
	assert_int(mode.winner).is_equal(-1)
	assert_float(mode.team_scores[0]).is_equal(0.0)
	assert_float(mode.team_scores[1]).is_equal(0.0)
