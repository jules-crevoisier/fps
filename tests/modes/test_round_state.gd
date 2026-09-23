## test_round_state.gd
## Spec (contract-r2.md, R-B1 "modes"): RoundState is PURE (no scene tree),
## drives a round-based match (SnD/Duel): phases BUY/PREROUND -> LIVE -> POST,
## timers, round wins, side swap, match point, overtime. The mode (SnD/Duel)
## decides what happens on a LIVE timeout (`tick()` only reports it).
extends GdUnitTestSuite

const DT := 1.0 / 60.0


func _new_state(wins := 6, swap := 5, buy := 15.0, live := 90.0, post := 4.0) -> RoundState:
	return RoundState.new(wins, swap, buy, live, post)


func test_starts_in_buy_phase_with_buy_duration() -> void:
	var rs := _new_state(6, 5, 15.0, 90.0, 4.0)
	assert_int(rs.phase).is_equal(RoundState.Phase.BUY)
	assert_float(rs.time_left).is_equal_approx(15.0, 0.001)
	assert_int(rs.winner).is_equal(-1)
	assert_int(rs.wins[0]).is_equal(0)
	assert_int(rs.wins[1]).is_equal(0)


func test_tick_counts_down_time_left() -> void:
	var rs := _new_state()
	rs.tick(1.0)
	assert_float(rs.time_left).is_equal_approx(14.0, 0.001)


func test_tick_does_not_report_timeout_during_buy_phase() -> void:
	var rs := _new_state(6, 5, 1.0, 90.0, 4.0)
	var timed_out := false
	for i in 120:
		if rs.tick(DT):
			timed_out = true
	# La phase BUY épuisée ne doit jamais être signalée comme un "timeout" de
	# manche (c'est au mode d'appeler start_live() pour enchaîner).
	assert_bool(timed_out).is_false()


func test_start_live_switches_phase_and_resets_timer() -> void:
	var rs := _new_state(6, 5, 15.0, 90.0, 4.0)
	rs.start_live()
	assert_int(rs.phase).is_equal(RoundState.Phase.LIVE)
	assert_float(rs.time_left).is_equal_approx(90.0, 0.001)


func test_tick_reports_timeout_once_when_live_time_expires() -> void:
	var rs := _new_state(6, 5, 15.0, 1.0, 4.0)
	rs.start_live()
	var timeouts := 0
	for i in 90:  # 1.5s at 60Hz, well past the 1s round duration
		if rs.tick(DT):
			timeouts += 1
	assert_int(timeouts).is_equal(1)
	assert_float(rs.time_left).is_equal(0.0)


func test_end_round_increments_wins_and_rounds_played() -> void:
	var rs := _new_state()
	rs.start_live()
	rs.end_round(0)
	assert_int(rs.wins[0]).is_equal(1)
	assert_int(rs.wins[1]).is_equal(0)
	assert_int(rs.rounds_played).is_equal(1)
	assert_int(rs.phase).is_equal(RoundState.Phase.POST)
	assert_float(rs.time_left).is_equal_approx(4.0, 0.001)


func test_end_round_declares_winner_at_rounds_to_win() -> void:
	var rs := _new_state(6, 5, 15.0, 90.0, 4.0)
	for i in 5:
		rs.start_live()
		rs.end_round(0)
	assert_int(rs.winner).is_equal(-1)
	rs.start_live()
	rs.end_round(0)
	assert_int(rs.winner).is_equal(0)
	assert_int(rs.wins[0]).is_equal(6)


func test_end_round_ignores_invalid_team_index() -> void:
	var rs := _new_state()
	rs.end_round(-1)
	rs.end_round(2)
	assert_int(rs.wins[0]).is_equal(0)
	assert_int(rs.wins[1]).is_equal(0)
	assert_int(rs.rounds_played).is_equal(0)


func test_end_round_is_a_no_op_once_a_winner_is_set() -> void:
	var rs := _new_state(1, 5, 15.0, 90.0, 4.0)  # first to 1 for a quick winner
	rs.end_round(0)
	assert_int(rs.winner).is_equal(0)
	rs.end_round(1)  # doit être ignoré : le match est déjà terminé
	assert_int(rs.wins[1]).is_equal(0)
	assert_int(rs.winner).is_equal(0)


func test_side_swap_triggers_exactly_once_after_swap_after_rounds() -> void:
	var rs := _new_state(6, 3, 15.0, 90.0, 4.0)
	assert_bool(rs.sides_swapped).is_false()
	rs.end_round(0)
	assert_bool(rs.sides_swapped).is_false()
	rs.end_round(1)
	assert_bool(rs.sides_swapped).is_false()
	rs.end_round(0)  # 3e manche jouée -> swap
	assert_bool(rs.sides_swapped).is_true()
	rs.end_round(1)  # reste vrai (ne se déclenche qu'une fois)
	assert_bool(rs.sides_swapped).is_true()


func test_swap_after_zero_disables_side_swap() -> void:
	var rs := _new_state(6, 0, 15.0, 90.0, 4.0)
	for i in 5:
		rs.end_round(i % 2)
	assert_bool(rs.sides_swapped).is_false()


func test_is_match_point_true_one_round_from_winning() -> void:
	var rs := _new_state(6, 5, 15.0, 90.0, 4.0)
	for i in 5:
		rs.end_round(0)
	assert_bool(rs.is_match_point(0)).is_true()
	assert_bool(rs.is_match_point(1)).is_false()


func test_is_match_point_false_once_match_is_won() -> void:
	var rs := _new_state(1, 5, 15.0, 90.0, 4.0)
	rs.end_round(0)
	assert_bool(rs.is_match_point(0)).is_false()


func test_is_overtime_true_when_both_teams_tied_at_match_point() -> void:
	var rs := _new_state(6, 0, 15.0, 90.0, 4.0)
	for i in 5:
		rs.end_round(0)
	for i in 5:
		rs.end_round(1)
	assert_bool(rs.is_overtime()).is_true()


func test_is_overtime_false_before_both_teams_reach_match_point() -> void:
	var rs := _new_state(6, 0, 15.0, 90.0, 4.0)
	rs.end_round(0)
	rs.end_round(1)
	assert_bool(rs.is_overtime()).is_false()


func test_reset_restores_initial_buy_state() -> void:
	var rs := _new_state(6, 5, 15.0, 90.0, 4.0)
	rs.start_live()
	rs.end_round(0)
	rs.reset()
	assert_int(rs.phase).is_equal(RoundState.Phase.BUY)
	assert_float(rs.time_left).is_equal_approx(15.0, 0.001)
	assert_int(rs.wins[0]).is_equal(0)
	assert_int(rs.wins[1]).is_equal(0)
	assert_int(rs.winner).is_equal(-1)
	assert_int(rs.rounds_played).is_equal(0)
	assert_bool(rs.sides_swapped).is_false()


func test_duel_style_config_short_preround_and_round() -> void:
	# Duel : "manche de 40 s", "preround 3 s" -- même machine, durées différentes.
	var rs := _new_state(6, 2, 3.0, 40.0, 3.0)
	assert_float(rs.time_left).is_equal_approx(3.0, 0.001)
	rs.start_live()
	assert_float(rs.time_left).is_equal_approx(40.0, 0.001)
