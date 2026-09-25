## test_rematch_reset.gd
## Spec (docs/audit/bugs.md, BUG-11) : sur une carte ASYMÉTRIQUE, une revanche
## (`reset_match`) doit repartir sur un match vierge — plus de changement de
## côté hérité du match précédent (bandeau "CHANGEMENT DE CÔTÉ" affiché
## d'emblée) et, pour Hardpoint, la zone qui redémarre au point 0 avec sa
## minuterie de rotation à zéro. TDMMode/HardpointMode.reset_match()
## surchargent GameMode.reset_match() (scores/vainqueur/mort subite déjà
## couverts par test_game_mode_tiebreak.gd) et remettent en plus leur propre
## état de côté/zone, répliqué comme au changement de côté lui-même.
extends GdUnitTestSuite


func _new_tdm() -> TDMMode:
	var mode := TDMMode.new()
	add_child(mode)
	auto_free(mode)
	return mode


func _new_hardpoint() -> HardpointMode:
	var mode := HardpointMode.new()
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


# ----------------------------------------------------------------------
#  HardpointMode : idem + la zone doit repartir du point 0, minuterie de
#  rotation remise à zéro (sinon la revanche reprend au point/à l'instant où
#  le match précédent s'est arrêté).
# ----------------------------------------------------------------------
func test_hardpoint_reset_match_clears_side_swap() -> void:
	var mode := _new_hardpoint()
	mode.sync_sides_swapped(true, "CHANGEMENT DE CÔTÉ")
	assert_bool(mode.sides_swapped).is_true()

	mode.reset_match()
	assert_bool(mode.sides_swapped).is_false()
	assert_str(mode.side_swap_notice).is_equal("")


func test_hardpoint_reset_match_clears_point_index_and_rotate_timer() -> void:
	var mode := _new_hardpoint()
	mode._point_index = 2
	mode._rotate_timer = 31.5

	mode.reset_match()
	assert_int(mode._point_index).is_equal(0)
	assert_float(mode._rotate_timer).is_equal(0.0)


func test_hardpoint_reset_match_also_resets_base_score_state() -> void:
	var mode := _new_hardpoint()
	mode.team_scores = [180.0, 250.0]
	mode.winner = 1

	mode.reset_match()
	assert_int(mode.winner).is_equal(-1)
	assert_float(mode.team_scores[0]).is_equal(0.0)
	assert_float(mode.team_scores[1]).is_equal(0.0)


func test_hardpoint_reset_match_survives_with_no_zone_points_configured() -> void:
	# points_path n'est jamais résolu en test unitaire (pas de scène réelle) :
	# _points reste vide -> reset_match() ne doit ni planter ni sauter la
	# remise à zéro de _point_index/_rotate_timer.
	var mode := _new_hardpoint()
	assert_bool(mode._points.is_empty()).is_true()
	mode._point_index = 1
	mode._rotate_timer = 5.0

	mode.reset_match()
	assert_int(mode._point_index).is_equal(0)
	assert_float(mode._rotate_timer).is_equal(0.0)
