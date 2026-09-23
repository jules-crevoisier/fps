## test_economy.gd
## Spec (contract-r2.md, R-B1 "modes"): Economy is PURE (no scene tree),
## server-authoritative money for R&D (SnD): start 800, round win 3000, round
## loss on a 1/2/3+ streak = 1900/2400/2900, kill 200, plant 300, cap 9000,
## purchase validation (spend refuses when unaffordable).
extends GdUnitTestSuite


func _new_eco() -> Economy:
	return Economy.new()


func test_reset_player_grants_starting_credits() -> void:
	var eco := _new_eco()
	eco.reset_player(1)
	assert_int(eco.get_credits(1)).is_equal(800)


func test_unknown_player_has_zero_credits() -> void:
	var eco := _new_eco()
	assert_int(eco.get_credits(42)).is_equal(0)


func test_award_kill_adds_200() -> void:
	var eco := _new_eco()
	eco.reset_player(1)
	eco.award_kill(1)
	assert_int(eco.get_credits(1)).is_equal(1000)


func test_award_plant_adds_300() -> void:
	var eco := _new_eco()
	eco.reset_player(1)
	eco.award_plant(1)
	assert_int(eco.get_credits(1)).is_equal(1100)


func test_credits_are_capped_at_9000() -> void:
	var eco := _new_eco()
	eco.reset_player(1)
	for i in 50:
		eco.award_kill(1)  # 50 * 200 = 10000, largement au-dessus du plafond
	assert_int(eco.get_credits(1)).is_equal(9000)


func test_spend_succeeds_and_deducts_when_affordable() -> void:
	var eco := _new_eco()
	eco.reset_player(1)
	assert_bool(eco.spend(1, 500)).is_true()
	assert_int(eco.get_credits(1)).is_equal(300)


func test_spend_fails_and_does_not_deduct_when_unaffordable() -> void:
	var eco := _new_eco()
	eco.reset_player(1)
	assert_bool(eco.spend(1, 801)).is_false()
	assert_int(eco.get_credits(1)).is_equal(800)


func test_spend_exact_balance_succeeds_and_leaves_zero() -> void:
	var eco := _new_eco()
	eco.reset_player(1)
	assert_bool(eco.spend(1, 800)).is_true()
	assert_int(eco.get_credits(1)).is_equal(0)


func test_can_afford_matches_spend_outcome() -> void:
	var eco := _new_eco()
	eco.reset_player(1)
	assert_bool(eco.can_afford(1, 800)).is_true()
	assert_bool(eco.can_afford(1, 801)).is_false()


func test_round_ended_pays_winners_flat_3000() -> void:
	var eco := _new_eco()
	eco.reset_player(1)
	eco.reset_player(2)
	eco.round_ended([1], [2])
	assert_int(eco.get_credits(1)).is_equal(3800)


func test_round_ended_first_loss_pays_1900() -> void:
	var eco := _new_eco()
	eco.reset_player(2)
	eco.round_ended([1], [2])
	assert_int(eco.get_credits(2)).is_equal(800 + 1900)


func test_round_ended_loss_streak_escalates_1900_2400_2900() -> void:
	var eco := _new_eco()
	eco.reset_player(2)
	eco.round_ended([1], [2])  # 1re défaite : +1900
	eco.round_ended([1], [2])  # 2e défaite d'affilée : +2400
	eco.round_ended([1], [2])  # 3e défaite d'affilée : +2900
	assert_int(eco.get_credits(2)).is_equal(800 + 1900 + 2400 + 2900)


func test_round_ended_loss_streak_caps_at_2900() -> void:
	var eco := _new_eco()
	eco.reset_player(2)
	eco.credits[2] = 0  # isole le palier du plafond global de crédits (9000)
	eco._loss_streak[2] = 5  # série de défaites déjà longue (au-delà des 3 paliers)
	eco.round_ended([1], [2])
	# Toujours le DERNIER palier (2900), jamais plus, même après une longue série.
	assert_int(eco.get_credits(2)).is_equal(2900)


func test_round_ended_win_resets_loss_streak() -> void:
	var eco := _new_eco()
	eco.reset_player(2)
	eco.round_ended([1], [2])  # défaite : streak = 1 (+1900)
	eco.round_ended([2], [1])  # victoire : streak revient à 0 (+3000)
	eco.round_ended([1], [2])  # nouvelle défaite : doit repartir à +1900, pas +2400
	var expected := 800 + 1900 + 3000 + 1900
	assert_int(eco.get_credits(2)).is_equal(expected)


func test_round_ended_handles_multiple_winners_and_losers() -> void:
	var eco := _new_eco()
	for id in [1, 2, 3, 4]:
		eco.reset_player(id)
	eco.round_ended([1, 2], [3, 4])
	assert_int(eco.get_credits(1)).is_equal(3800)
	assert_int(eco.get_credits(2)).is_equal(3800)
	assert_int(eco.get_credits(3)).is_equal(800 + 1900)
	assert_int(eco.get_credits(4)).is_equal(800 + 1900)
