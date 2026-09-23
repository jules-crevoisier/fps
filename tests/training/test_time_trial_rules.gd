## test_time_trial_rules.gd
## Spec (contract-r4a.md, R4-TRAIN #2) : progression des checkpoints, calcul
## de médaille et formatage du temps — logique PURE, aucune scène.
extends GdUnitTestSuite

# ---- checkpoints ----

func test_advance_checkpoint_on_expected_index() -> void:
	assert_int(TimeTrialRules.advance_checkpoint(0, 0, 5)).is_equal(1)

func test_advance_checkpoint_ignores_wrong_index() -> void:
	assert_int(TimeTrialRules.advance_checkpoint(0, 2, 5)).is_equal(0)

func test_advance_checkpoint_ignores_already_passed() -> void:
	assert_int(TimeTrialRules.advance_checkpoint(3, 1, 5)).is_equal(3)

func test_advance_checkpoint_caps_at_total() -> void:
	assert_int(TimeTrialRules.advance_checkpoint(4, 4, 5)).is_equal(5)

func test_is_finished_true_at_total() -> void:
	assert_bool(TimeTrialRules.is_finished(5, 5)).is_true()

func test_is_finished_false_before_total() -> void:
	assert_bool(TimeTrialRules.is_finished(3, 5)).is_false()

# ---- médailles ----

func test_medal_gold_under_threshold() -> void:
	assert_str(TimeTrialRules.medal_for_time(18.0, 20.0, 25.0, 30.0)).is_equal(TimeTrialRules.MEDAL_GOLD)

func test_medal_gold_at_exact_threshold() -> void:
	assert_str(TimeTrialRules.medal_for_time(20.0, 20.0, 25.0, 30.0)).is_equal(TimeTrialRules.MEDAL_GOLD)

func test_medal_silver_between_thresholds() -> void:
	assert_str(TimeTrialRules.medal_for_time(23.0, 20.0, 25.0, 30.0)).is_equal(TimeTrialRules.MEDAL_SILVER)

func test_medal_bronze_between_thresholds() -> void:
	assert_str(TimeTrialRules.medal_for_time(28.0, 20.0, 25.0, 30.0)).is_equal(TimeTrialRules.MEDAL_BRONZE)

func test_medal_none_over_bronze() -> void:
	assert_str(TimeTrialRules.medal_for_time(40.0, 20.0, 25.0, 30.0)).is_equal(TimeTrialRules.MEDAL_NONE)

# ---- meilleur temps ----

func test_is_new_best_when_no_previous_record() -> void:
	assert_bool(TimeTrialRules.is_new_best(30.0, -1.0)).is_true()

func test_is_new_best_when_faster() -> void:
	assert_bool(TimeTrialRules.is_new_best(19.0, 20.0)).is_true()

func test_is_new_best_false_when_slower() -> void:
	assert_bool(TimeTrialRules.is_new_best(21.0, 20.0)).is_false()

func test_is_new_best_false_when_equal() -> void:
	assert_bool(TimeTrialRules.is_new_best(20.0, 20.0)).is_false()

# ---- formatage du temps ----

func test_format_time_basic() -> void:
	assert_str(TimeTrialRules.format_time(65.5)).is_equal("01:05.50")

func test_format_time_zero() -> void:
	assert_str(TimeTrialRules.format_time(0.0)).is_equal("00:00.00")

func test_format_time_sub_minute_with_centis() -> void:
	assert_str(TimeTrialRules.format_time(9.234)).is_equal("00:09.23")

func test_format_time_never_negative() -> void:
	assert_str(TimeTrialRules.format_time(-4.0)).is_equal("00:00.00")
