## test_rematch_reset.gd
## Spec (docs/audit/bugs.md, BUG-11) : sur une carte ASYMÉTRIQUE, une revanche
## (`reset_match`) doit repartir sur un match vierge — plus de changement de
## côté hérité du match précédent (bandeau "CHANGEMENT DE CÔTÉ" affiché
## d'emblée). TDMMode.reset_match() surcharge GameMode.reset_match()
## (scores/vainqueur/mort subite déjà couverts par test_game_mode_tiebreak.gd)
## et remet en plus son propre état de côté, répliqué comme au changement de
## côté lui-même.
##
## Nettoyage du prototype 2026-09-26 : HardpointMode (zone/minuterie de
## rotation) a été supprimé avec les autres modes à manches/zone — TDM est
## désormais le seul mode, les tests Hardpoint de ce fichier ont été retirés.
extends GdUnitTestSuite


func _new_tdm() -> TDMMode:
	var mode := TDMMode.new()
	add_child(mode)
	auto_free(mode)
	return mode


# ----------------------------------------------------------------------
#  TDMMode : le changement de côté d'un match précédent ne doit pas
#  survivre à une revanche.
# ----------------------------------------------------------------------
func test_tdm_reset_match_clears_side_swap() -> void:
	var mode := _new_tdm()
	mode.sync_sides_swapped(true, "CHANGEMENT DE CÔTÉ")
	assert_bool(mode.sides_swapped).is_true()

	mode.reset_match()
	assert_bool(mode.sides_swapped).is_false()
	assert_str(mode.side_swap_notice).is_equal("")


func test_tdm_reset_match_also_resets_base_score_state() -> void:
	var mode := _new_tdm()
	mode.team_scores = [12.0, 7.0]
	mode.winner = 0

	mode.reset_match()
	assert_int(mode.winner).is_equal(-1)
	assert_float(mode.team_scores[0]).is_equal(0.0)
	assert_float(mode.team_scores[1]).is_equal(0.0)


func test_tdm_reset_match_without_prior_swap_stays_neutral() -> void:
	# Carte symétrique / pas encore de changement de côté : reset_match() ne
	# doit rien casser (comportement neutre déjà couvert par le défaut).
	var mode := _new_tdm()
	mode.reset_match()
	assert_bool(mode.sides_swapped).is_false()
	assert_str(mode.side_swap_notice).is_equal("")
