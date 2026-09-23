## test_bot_reaction.gd
## Spec (contract-r3.md, R3-IN#2) : délai de réaction et erreur de visée par
## difficulté (Recrue ~450 ms, Vétéran ~300 ms, Élite ~200 ms), l'erreur
## rétrécissant pendant le suivi continu d'une cible.
extends GdUnitTestSuite


func test_reaction_time_recrue() -> void:
	assert_float(BotReaction.reaction_time(MatchConfig.Difficulty.RECRUE)).is_equal_approx(0.45, 0.001)


func test_reaction_time_veteran() -> void:
	assert_float(BotReaction.reaction_time(MatchConfig.Difficulty.VETERAN)).is_equal_approx(0.3, 0.001)


func test_reaction_time_elite() -> void:
	assert_float(BotReaction.reaction_time(MatchConfig.Difficulty.ELITE)).is_equal_approx(0.2, 0.001)


func test_higher_difficulty_reacts_faster() -> void:
	var recrue := BotReaction.reaction_time(MatchConfig.Difficulty.RECRUE)
	var veteran := BotReaction.reaction_time(MatchConfig.Difficulty.VETERAN)
	var elite := BotReaction.reaction_time(MatchConfig.Difficulty.ELITE)
	assert_bool(recrue > veteran).is_true()
	assert_bool(veteran > elite).is_true()


func test_aim_error_at_zero_tracking_equals_max() -> void:
	var d := MatchConfig.Difficulty.VETERAN
	var fresh := BotReaction.aim_error_for(d, 0.0)
	assert_float(fresh).is_equal_approx(BotReaction.max_aim_error(d), 0.0001)


func test_aim_error_shrinks_while_tracking() -> void:
	var d := MatchConfig.Difficulty.VETERAN
	var fresh := BotReaction.aim_error_for(d, 0.0)
	var tracked := BotReaction.aim_error_for(d, 2.0)
	assert_bool(tracked < fresh).is_true()


func test_aim_error_never_negative() -> void:
	var d := MatchConfig.Difficulty.RECRUE
	assert_float(BotReaction.aim_error_for(d, 100.0)).is_greater_equal(0.0)


func test_elite_more_precise_than_recrue() -> void:
	var recrue := BotReaction.max_aim_error(MatchConfig.Difficulty.RECRUE)
	var elite := BotReaction.max_aim_error(MatchConfig.Difficulty.ELITE)
	assert_bool(elite < recrue).is_true()
