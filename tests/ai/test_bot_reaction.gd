## test_bot_reaction.gd
## Spec (BOT-26, docs/research/08_bots_humanlike.md §3.2 A6, §3.8) : délai de
## réaction par difficulté tiré d'une loi EX-GAUSSIENNE (μ/σ/τ, §3.8), pas
## une constante (BOT-02) — médianes ~475/330/230 ms, +120 ms si la cible est
## à plus de 35° du centre à l'acquisition, +250/80/0 ms de délai d'ouverture
## du feu au tout premier tir d'un engagement, plancher à 150 ms dans tous
## les cas.
extends GdUnitTestSuite

const RECRUE := MatchConfig.Difficulty.RECRUE
const VETERAN := MatchConfig.Difficulty.VETERAN
const ELITE := MatchConfig.Difficulty.ELITE

# ======================================================================
#  Paramètres de la loi et délai d'ouverture du feu — valeurs §3.8.
# ======================================================================

func test_fire_delay_per_difficulty() -> void:
	assert_float(BotReaction.fire_delay_s(RECRUE)).is_equal_approx(0.250, 0.0001)
	assert_float(BotReaction.fire_delay_s(VETERAN)).is_equal_approx(0.080, 0.0001)
	assert_float(BotReaction.fire_delay_s(ELITE)).is_equal_approx(0.0, 0.0001)


func test_expected_median_matches_table_values() -> void:
	# §3.8 : médianes documentées ~475/330/230 ms (approximation μ + τ·ln2).
	assert_float(BotReaction.expected_median_s(RECRUE)).is_equal_approx(0.475, 0.005)
	assert_float(BotReaction.expected_median_s(VETERAN)).is_equal_approx(0.330, 0.005)
	assert_float(BotReaction.expected_median_s(ELITE)).is_equal_approx(0.230, 0.005)

# ======================================================================
#  Nouveaux tests (BOT-26) : médiane et coefficient de variation de la
#  réaction — Monte-Carlo, graine FIXE, jamais flaky.
# ======================================================================

const MC_TRIALS := 4000

func _median(values: Array) -> float:
	var sorted: Array = values.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n % 2 == 1:
		return sorted[n / 2]
	return (float(sorted[n / 2 - 1]) + float(sorted[n / 2])) * 0.5


func _mean(values: Array) -> float:
	var sum := 0.0
	for v in values:
		sum += float(v)
	return sum / float(values.size())


func _sample_base_reactions(difficulty: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var samples: Array = []
	for i in range(MC_TRIALS):
		samples.append(BotReaction.sample_base_reaction_s(difficulty, rng))
	return samples


func test_reaction_median_matches_ex_gaussian_table() -> void:
	# La distribution de BASE (sans hors-centre/premier tir/plancher, voir
	# `sample_base_reaction_s`) doit retomber sur les médianes §3.8.
	var expected := {RECRUE: 0.475, VETERAN: 0.330, ELITE: 0.230}
	for d in [RECRUE, VETERAN, ELITE]:
		var samples := _sample_base_reactions(d, 5000 + d)
		var med := _median(samples)
		assert_float(med).append_failure_message(
			"difficulté %d : médiane mesurée %.4f attendue ~%.4f" % [d, med, expected[d]]
		).is_equal_approx(expected[d], 0.035)


func test_reaction_coefficient_of_variation_is_meaningfully_variable() -> void:
	# La constante BOT-02 avait un CV de 0 (aucune variance) — la loi
	# ex-gaussienne doit produire une VRAIE dispersion pour chaque difficulté.
	for d in [RECRUE, VETERAN, ELITE]:
		var samples := _sample_base_reactions(d, 9000 + d)
		var mean := _mean(samples)
		var sum_sq := 0.0
		for v in samples:
			sum_sq += (float(v) - mean) * (float(v) - mean)
		var stddev := sqrt(sum_sq / float(samples.size()))
		var cv := stddev / mean
		assert_float(cv).append_failure_message(
			"difficulté %d : coefficient de variation %.4f hors de [0.10, 0.40]" % [d, cv]
		).is_between(0.10, 0.40)


func test_reaction_samples_are_not_constant() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	var first := BotReaction.sample_base_reaction_s(VETERAN, rng)
	var distinct := false
	for i in range(30):
		if not is_equal_approx(BotReaction.sample_base_reaction_s(VETERAN, rng), first):
			distinct = true
			break
	assert_bool(distinct).is_true()

# ======================================================================
#  Réaction complète : hors-centre, premier tir, plancher.
# ======================================================================

func test_higher_difficulty_reacts_faster_on_average() -> void:
	var recrue := _mean(_sample_base_reactions(RECRUE, 111))
	var veteran := _mean(_sample_base_reactions(VETERAN, 111))
	var elite := _mean(_sample_base_reactions(ELITE, 111))
	assert_bool(recrue > veteran).is_true()
	assert_bool(veteran > elite).is_true()


func test_off_center_target_adds_penalty() -> void:
	# Même graine, même séquence de tirages internes : seule diffère l'entrée
	# `target_offset_deg` -> l'écart doit être EXACTEMENT OFF_CENTER_PENALTY_S.
	var rng_centered := RandomNumberGenerator.new()
	rng_centered.seed = 123
	var rng_off_center := RandomNumberGenerator.new()
	rng_off_center.seed = 123
	var centered := BotReaction.reaction_time(VETERAN, rng_centered, 10.0, false)
	var off_center := BotReaction.reaction_time(VETERAN, rng_off_center, 40.0, false)
	assert_float(off_center - centered).is_equal_approx(BotReaction.OFF_CENTER_PENALTY_S, 0.0001)


func test_off_center_threshold_is_35_deg() -> void:
	var rng_at := RandomNumberGenerator.new()
	rng_at.seed = 456
	var rng_above := RandomNumberGenerator.new()
	rng_above.seed = 456
	var at_threshold := BotReaction.reaction_time(VETERAN, rng_at, 35.0, false)
	var above := BotReaction.reaction_time(VETERAN, rng_above, 35.0001, false)
	assert_float(above - at_threshold).is_equal_approx(BotReaction.OFF_CENTER_PENALTY_S, 0.0001)


func test_first_shot_adds_fire_delay() -> void:
	for d in [RECRUE, VETERAN, ELITE]:
		var rng_first := RandomNumberGenerator.new()
		rng_first.seed = 789
		var rng_reacquire := RandomNumberGenerator.new()
		rng_reacquire.seed = 789
		var first := BotReaction.reaction_time(d, rng_first, 0.0, true)
		var reacquire := BotReaction.reaction_time(d, rng_reacquire, 0.0, false)
		assert_float(first - reacquire).append_failure_message(
			"difficulté %d : écart premier tir %.4f != fire_delay %.4f" % [d, first - reacquire, BotReaction.fire_delay_s(d)]
		).is_equal_approx(BotReaction.fire_delay_s(d), 0.0001)


func test_reaction_time_never_below_floor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for d in [RECRUE, VETERAN, ELITE]:
		for i in range(2000):
			var t := BotReaction.reaction_time(d, rng, 0.0, false)
			assert_float(t).is_greater_equal(BotReaction.REACTION_FLOOR_S)


func test_reaction_time_floor_is_150ms() -> void:
	assert_float(BotReaction.REACTION_FLOOR_S).is_equal_approx(0.15, 0.0001)
