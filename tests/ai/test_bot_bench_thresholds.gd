## test_bot_bench_thresholds.gd
## Spec (BOT-13, docs/research/02_bots_ai.md #18 "Pas de banc de mesure" +
## tasks/backlog.yaml) : tools/bot_bench.gd héberge un banc de mesure headless
## bot-vs-bot (TDM 4v4 par difficulté + SnD "N" manches) qui exporte des
## métriques en JSON et les compare à des seuils de régression documentés.
##
## BOT-20 (docs/research/08_bots_humanlike.md) ajoute les fonctions pures
## `percentile`/`p99`, `coefficient_of_variation`, `segment_durations`,
## `is_snap_then_fire`, `max_simultaneous_events`, ainsi que
## `check_observed_thresholds` (B1-B20, seuils OBSERVÉS — avertissement
## seulement, jamais un échec — voir sa docstring dans tools/bot_bench.gd).
##
## Ce fichier ne fait tourner AUCUNE partie réelle (aucun `NetworkManager.
## host()`, aucune scène de niveau) — même convention que le reste du dépôt :
## "GameWorld n'est testé qu'au travers de fonctions PURES"
## (tests/agents/test_round_props_cleanup.gd, en-tête) et le seul autre banc
## de mesure Monte-Carlo du projet (tests/ai/test_bot_aim.gd) ne simule lui
## non plus qu'un calcul, jamais une scène. Il vérifie donc uniquement les
## fonctions PURES de `tools/bot_bench.gd` :
##   - le découpage en bandes de distance (5/20/40 m, mêmes bandes que
##     tests/ai/test_bot_aim.gd::MC_EXPECTED_RANGES, pour rester comparable) ;
##   - les petits calculs (ratio, médiane, taux par minute), avec leur
##     sentinelle "pas assez de données" (-1.0), jamais un plantage ni un NaN
##     silencieux exporté tel quel en JSON ;
##   - `check_thresholds()`, qui compare un dictionnaire de métriques (la
##     forme réellement exportée par une exécution réelle, voir
##     `empty_metrics()`) à la table de seuils documentée — y compris
##     l'exemple EXACT du contrat ("précision Vétéran 20 m entre 25 et 45 %",
##     "temps bloqué < 2 %") — et ignore (jamais un échec) une bande sans
##     assez d'échantillons (sentinelle -1.0).
## La partie réelle (démarrer une partie headless, l'exécuter, écrire le
## JSON) tourne via `godot --headless -s res://tools/bot_bench.gd -- ...`,
## documentée dans docs/TESTING.md — hors du périmètre gdUnit4 (durée d'une
## partie réelle incompatible avec la boucle rapide de la suite).
extends GdUnitTestSuite

const BENCH := preload("res://tools/bot_bench.gd")

# ======================================================================
#  Bandes de distance
# ======================================================================

func test_distance_band_close_range_is_5m() -> void:
	assert_str(BENCH.distance_band(0.0)).is_equal("5m")
	assert_str(BENCH.distance_band(5.0)).is_equal("5m")
	assert_str(BENCH.distance_band(12.4)).is_equal("5m")


func test_distance_band_mid_range_is_20m() -> void:
	assert_str(BENCH.distance_band(12.5)).is_equal("20m")
	assert_str(BENCH.distance_band(20.0)).is_equal("20m")
	assert_str(BENCH.distance_band(29.9)).is_equal("20m")


func test_distance_band_far_range_is_40m() -> void:
	assert_str(BENCH.distance_band(30.0)).is_equal("40m")
	assert_str(BENCH.distance_band(40.0)).is_equal("40m")
	assert_str(BENCH.distance_band(100.0)).is_equal("40m")


func test_distance_band_never_crashes_on_negative_distance() -> void:
	assert_str(BENCH.distance_band(-5.0)).is_equal("5m")


func test_distance_bands_match_accuracy_ranges_keys_for_every_difficulty() -> void:
	# Cohérence de schéma : chaque difficulté de ACCURACY_RANGES documente
	# EXACTEMENT les 3 bandes retournées par distance_band, ni plus ni moins.
	for diff_key in BENCH.ACCURACY_RANGES:
		var bands: Dictionary = BENCH.ACCURACY_RANGES[diff_key]
		for band in BENCH.DISTANCE_BANDS:
			assert_bool(bands.has(band)).append_failure_message(
				"ACCURACY_RANGES[%s] devrait documenter la bande %s" % [diff_key, band]).is_true()
		assert_int(bands.size()).is_equal(BENCH.DISTANCE_BANDS.size())


# ======================================================================
#  Petits calculs purs — ratio / médiane / taux par minute.
# ======================================================================

func test_ratio_computes_simple_fraction() -> void:
	assert_float(BENCH.ratio(3, 10)).is_equal_approx(0.3, 0.0001)


func test_ratio_is_sentinel_when_total_is_zero() -> void:
	assert_float(BENCH.ratio(0, 0)).is_equal_approx(-1.0, 0.0001)


func test_ratio_full_hits_is_one() -> void:
	assert_float(BENCH.ratio(5, 5)).is_equal_approx(1.0, 0.0001)


func test_median_odd_count() -> void:
	assert_float(BENCH.median([3.0, 1.0, 2.0])).is_equal_approx(2.0, 0.0001)


func test_median_even_count_averages_middle_two() -> void:
	assert_float(BENCH.median([1.0, 2.0, 3.0, 4.0])).is_equal_approx(2.5, 0.0001)


func test_median_single_value() -> void:
	assert_float(BENCH.median([7.0])).is_equal_approx(7.0, 0.0001)


func test_median_is_sentinel_when_empty() -> void:
	assert_float(BENCH.median([])).is_equal_approx(-1.0, 0.0001)


func test_median_does_not_mutate_input_array() -> void:
	var input := [5.0, 1.0, 3.0]
	BENCH.median(input)
	assert_array(input).append_failure_message(
		"median() ne doit pas trier le tableau reçu en place").is_equal([5.0, 1.0, 3.0])


func test_per_minute_computes_rate() -> void:
	assert_float(BENCH.per_minute(12, 120.0)).is_equal_approx(6.0, 0.0001)


func test_per_minute_is_sentinel_when_duration_is_zero_or_negative() -> void:
	assert_float(BENCH.per_minute(5, 0.0)).is_equal_approx(-1.0, 0.0001)
	assert_float(BENCH.per_minute(5, -1.0)).is_equal_approx(-1.0, 0.0001)


func test_per_minute_zero_count_over_real_duration_is_zero_not_sentinel() -> void:
	assert_float(BENCH.per_minute(0, 60.0)).is_equal_approx(0.0, 0.0001)


# ======================================================================
#  empty_metrics() — squelette JSON, toutes sentinelles "pas de données".
# ======================================================================

func test_empty_metrics_has_sentinel_scalars() -> void:
	var m := BENCH.empty_metrics()
	assert_float(float(m.get("stuck_time_ratio"))).is_equal_approx(-1.0, 0.0001)
	assert_float(float(m.get("goal_changes_per_min"))).is_equal_approx(-1.0, 0.0001)
	assert_float(float(m.get("ttk_median_s"))).is_equal_approx(-1.0, 0.0001)
	assert_float(float(m.get("ability_uses_per_min"))).is_equal_approx(-1.0, 0.0001)
	assert_float(float(m.get("plant_rate"))).is_equal_approx(-1.0, 0.0001)
	assert_float(float(m.get("defuse_rate"))).is_equal_approx(-1.0, 0.0001)
	assert_int(int(m.get("rounds_played"))).is_equal(0)


func test_empty_metrics_accuracy_covers_every_difficulty_and_band_with_sentinels() -> void:
	var m := BENCH.empty_metrics()
	var acc: Dictionary = m.get("accuracy", {})
	for diff_key in BENCH.ACCURACY_RANGES:
		assert_bool(acc.has(diff_key)).is_true()
		for band in BENCH.DISTANCE_BANDS:
			assert_float(float(acc[diff_key].get(band))).append_failure_message(
				"accuracy[%s][%s] devrait démarrer à la sentinelle -1.0" % [diff_key, band]
			).is_equal_approx(-1.0, 0.0001)


func test_empty_metrics_passes_every_threshold_check() -> void:
	# Squelette "aucune donnée" : check_thresholds ne doit RIEN signaler (pas
	# assez d'échantillons != régression, voir doc d'en-tête).
	var failures := BENCH.check_thresholds(BENCH.empty_metrics())
	assert_array(failures).append_failure_message(
		"un jeu de métriques entièrement vide ne doit déclencher aucun échec : %s" % [failures]
	).is_empty()


# ======================================================================
#  check_thresholds() — table de seuils documentée (docs/TESTING.md).
# ======================================================================

## Métriques "saines" : au centre de chaque fourchette documentée — doit
## toujours passer `check_thresholds` intégralement.
func _healthy_metrics() -> Dictionary:
	var m := BENCH.empty_metrics()
	m.stuck_time_ratio = 0.005
	m.goal_changes_per_min = 2.0
	m.ttk_median_s = 1.2
	m.ability_uses_per_min = 1.0
	m.plant_rate = 0.6
	m.defuse_rate = 0.3
	m.rounds_played = 10
	for diff_key in BENCH.ACCURACY_RANGES:
		for band in BENCH.DISTANCE_BANDS:
			var bounds: Array = BENCH.ACCURACY_RANGES[diff_key][band]
			m.accuracy[diff_key][band] = (float(bounds[0]) + float(bounds[1])) * 0.5
	return m


func test_healthy_metrics_pass_every_threshold() -> void:
	var failures := BENCH.check_thresholds(_healthy_metrics())
	assert_array(failures).append_failure_message(
		"des métriques saines (centre de chaque fourchette) ne devraient déclencher aucun échec : %s" % [failures]
	).is_empty()


func test_stuck_time_over_threshold_is_reported() -> void:
	var m := _healthy_metrics()
	m.stuck_time_ratio = BENCH.STUCK_TIME_MAX_RATIO + 0.01
	var failures := BENCH.check_thresholds(m)
	assert_int(failures.size()).is_equal(1)
	assert_str(str(failures[0]).to_lower()).contains("bloqu")


func test_stuck_time_sentinel_never_fails() -> void:
	var m := _healthy_metrics()
	m.stuck_time_ratio = -1.0
	assert_array(BENCH.check_thresholds(m)).is_empty()


func test_goal_changes_over_threshold_is_reported() -> void:
	var m := _healthy_metrics()
	m.goal_changes_per_min = BENCH.GOAL_CHANGES_PER_MIN_MAX + 1.0
	var failures := BENCH.check_thresholds(m)
	assert_int(failures.size()).is_equal(1)
	assert_str(str(failures[0]).to_lower()).contains("but")


## Exemple EXACT du contrat (tasks/backlog.yaml BOT-13) : "précision Vétéran
## 20 m entre 25 et 45 %".
func test_veteran_20m_accuracy_range_matches_the_contract_example() -> void:
	var bounds: Array = BENCH.ACCURACY_RANGES["veteran"]["20m"]
	assert_float(float(bounds[0])).is_equal_approx(0.25, 0.0001)
	assert_float(float(bounds[1])).is_equal_approx(0.45, 0.0001)


func test_veteran_20m_accuracy_below_25_percent_is_reported() -> void:
	var m := _healthy_metrics()
	m.accuracy["veteran"]["20m"] = 0.10
	var failures := BENCH.check_thresholds(m)
	assert_int(failures.size()).is_equal(1)
	var msg := str(failures[0]).to_lower()
	assert_bool(msg.contains("veteran") or msg.contains("vétéran")).is_true()
	assert_bool(msg.contains("20m")).is_true()


func test_veteran_20m_accuracy_above_45_percent_is_reported() -> void:
	var m := _healthy_metrics()
	m.accuracy["veteran"]["20m"] = 0.90
	assert_int(BENCH.check_thresholds(m).size()).is_equal(1)


func test_accuracy_sentinel_band_never_fails_even_if_other_bands_do() -> void:
	var m := _healthy_metrics()
	m.accuracy["veteran"]["20m"] = -1.0  # pas assez de tirs échantillonnés dans cette bande.
	assert_array(BENCH.check_thresholds(m)).is_empty()


func test_ttk_median_out_of_range_is_reported() -> void:
	var m := _healthy_metrics()
	m.ttk_median_s = BENCH.TTK_MEDIAN_MAX_S + 5.0
	assert_int(BENCH.check_thresholds(m).size()).is_equal(1)
	m = _healthy_metrics()
	m.ttk_median_s = BENCH.TTK_MEDIAN_MIN_S - 0.05
	assert_int(BENCH.check_thresholds(m).size()).is_equal(1)


func test_ttk_median_sentinel_never_fails() -> void:
	var m := _healthy_metrics()
	m.ttk_median_s = -1.0
	assert_array(BENCH.check_thresholds(m)).is_empty()


func test_ability_rate_over_threshold_is_reported() -> void:
	var m := _healthy_metrics()
	m.ability_uses_per_min = BENCH.ABILITY_PER_MIN_MAX + 1.0
	assert_int(BENCH.check_thresholds(m).size()).is_equal(1)


func test_plant_rate_out_of_range_is_reported() -> void:
	var m := _healthy_metrics()
	m.plant_rate = BENCH.PLANT_RATE_MIN - 0.05
	assert_int(BENCH.check_thresholds(m).size()).is_equal(1)


func test_defuse_rate_out_of_range_is_reported() -> void:
	var m := _healthy_metrics()
	m.defuse_rate = BENCH.DEFUSE_RATE_MAX + 0.05
	assert_int(BENCH.check_thresholds(m).size()).is_equal(1)


func test_plant_and_defuse_rate_sentinels_never_fail() -> void:
	var m := _healthy_metrics()
	m.plant_rate = -1.0
	m.defuse_rate = -1.0
	assert_array(BENCH.check_thresholds(m)).is_empty()


func test_multiple_simultaneous_violations_are_all_reported() -> void:
	var m := _healthy_metrics()
	m.stuck_time_ratio = BENCH.STUCK_TIME_MAX_RATIO + 0.05
	m.ttk_median_s = BENCH.TTK_MEDIAN_MAX_S + 5.0
	m.accuracy["elite"]["5m"] = 0.0
	var failures := BENCH.check_thresholds(m)
	assert_int(failures.size()).is_equal(3)


# ======================================================================
#  Table de seuils — monotonie Recrue <= Vétéran <= Élite (même esprit que
#  tests/ai/test_bot_aim.gd::test_monotonic_precision_by_difficulty).
# ======================================================================

func test_accuracy_ranges_are_monotonic_by_difficulty_lower_bound() -> void:
	for band in BENCH.DISTANCE_BANDS:
		var recrue_min: float = BENCH.ACCURACY_RANGES["recrue"][band][0]
		var veteran_min: float = BENCH.ACCURACY_RANGES["veteran"][band][0]
		var elite_min: float = BENCH.ACCURACY_RANGES["elite"][band][0]
		assert_bool(recrue_min <= veteran_min).append_failure_message(
			"bande %s : Recrue (%.2f) devrait être <= Vétéran (%.2f)" % [band, recrue_min, veteran_min]).is_true()
		assert_bool(veteran_min <= elite_min).append_failure_message(
			"bande %s : Vétéran (%.2f) devrait être <= Élite (%.2f)" % [band, veteran_min, elite_min]).is_true()


func test_accuracy_ranges_are_well_formed_fractions() -> void:
	for diff_key in BENCH.ACCURACY_RANGES:
		for band in BENCH.DISTANCE_BANDS:
			var bounds: Array = BENCH.ACCURACY_RANGES[diff_key][band]
			assert_float(float(bounds[0])).is_greater_equal(0.0)
			assert_float(float(bounds[1])).is_less_equal(1.0)
			assert_bool(float(bounds[0]) < float(bounds[1])).append_failure_message(
				"%s/%s : borne basse %.2f devrait être < borne haute %.2f" % [diff_key, band, bounds[0], bounds[1]]).is_true()


# ======================================================================
#  BOT-20 — fonctions pures ajoutées (docs/research/08_bots_humanlike.md §4).
# ======================================================================

## ---- percentile / p99 ----

func test_percentile_is_sentinel_when_empty() -> void:
	assert_float(BENCH.percentile([], 0.99)).is_equal_approx(-1.0, 0.0001)


func test_percentile_single_value() -> void:
	assert_float(BENCH.percentile([5.0], 0.99)).is_equal_approx(5.0, 0.0001)


func test_p99_on_one_to_hundred() -> void:
	var values: Array = []
	for i in range(1, 101):
		values.append(float(i))
	# "Plus proche rang" : ceil(0.99 * 100) = 99e valeur triée = 99.0.
	assert_float(BENCH.p99(values)).is_equal_approx(99.0, 0.0001)


func test_p99_ignores_order() -> void:
	assert_float(BENCH.p99([3.0, 1.0, 2.0])).is_equal_approx(3.0, 0.0001)


func test_percentile_p5_on_one_to_hundred() -> void:
	var values: Array = []
	for i in range(1, 101):
		values.append(float(i))
	assert_float(BENCH.percentile(values, 0.05)).is_equal_approx(5.0, 0.0001)


func test_p99_does_not_mutate_input_array() -> void:
	var input := [5.0, 1.0, 3.0]
	BENCH.p99(input)
	assert_array(input).is_equal([5.0, 1.0, 3.0])


## ---- coefficient_of_variation ----

func test_coefficient_of_variation_is_sentinel_when_fewer_than_two_values() -> void:
	assert_float(BENCH.coefficient_of_variation([])).is_equal_approx(-1.0, 0.0001)
	assert_float(BENCH.coefficient_of_variation([4.0])).is_equal_approx(-1.0, 0.0001)


func test_coefficient_of_variation_is_sentinel_when_mean_is_zero() -> void:
	assert_float(BENCH.coefficient_of_variation([-1.0, 1.0])).is_equal_approx(-1.0, 0.0001)


func test_coefficient_of_variation_is_zero_for_constant_values() -> void:
	assert_float(BENCH.coefficient_of_variation([2.0, 2.0, 2.0])).is_equal_approx(0.0, 0.0001)


func test_coefficient_of_variation_matches_known_value() -> void:
	# valeurs [2,4,4,4,5,5,7,9] : moyenne 5, écart-type population 2 -> CV 0.4
	# (exemple canonique de calcul de variance).
	var values := [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
	assert_float(BENCH.coefficient_of_variation(values)).is_equal_approx(0.4, 0.001)


## ---- segment_durations ----

func test_segment_durations_is_empty_for_empty_input() -> void:
	assert_array(BENCH.segment_durations([])).is_empty()


func test_segment_durations_splits_contiguous_runs() -> void:
	var samples := [[1, 0.1], [1, 0.1], [-1, 0.1], [-1, 0.1], [-1, 0.1], [1, 0.1]]
	var segments := BENCH.segment_durations(samples)
	assert_int(segments.size()).is_equal(3)
	assert_int(int(segments[0].state)).is_equal(1)
	assert_float(float(segments[0].duration)).is_equal_approx(0.2, 0.0001)
	assert_int(int(segments[1].state)).is_equal(-1)
	assert_float(float(segments[1].duration)).is_equal_approx(0.3, 0.0001)
	assert_int(int(segments[2].state)).is_equal(1)
	assert_float(float(segments[2].duration)).is_equal_approx(0.1, 0.0001)


func test_segment_durations_single_sample_is_one_segment() -> void:
	var segments := BENCH.segment_durations([["L", 0.05]])
	assert_int(segments.size()).is_equal(1)
	assert_str(str(segments[0].state)).is_equal("L")
	assert_float(float(segments[0].duration)).is_equal_approx(0.05, 0.0001)


func test_segment_durations_accepts_variable_dt() -> void:
	# Robustesse à un delta headless instable : PAS un pas fixe supposé.
	var segments := BENCH.segment_durations([["A", 0.016], ["A", 0.02], ["B", 0.01]])
	assert_int(segments.size()).is_equal(2)
	assert_float(float(segments[0].duration)).is_equal_approx(0.036, 0.0001)


## ---- is_snap_then_fire (B10) ----

func test_is_snap_then_fire_true_when_most_rotation_is_in_the_last_50ms() -> void:
	assert_bool(BENCH.is_snap_then_fire(45.0, 50.0)).is_true()


func test_is_snap_then_fire_false_when_rotation_is_spread_out() -> void:
	assert_bool(BENCH.is_snap_then_fire(10.0, 50.0)).is_false()


func test_is_snap_then_fire_false_when_almost_no_rotation_at_all() -> void:
	# Tir quasi immobile : rien à classer, jamais un "snap" par construction
	# (évite un ratio 0/0 ou bruité sur un tir posé).
	assert_bool(BENCH.is_snap_then_fire(0.0, 0.0)).is_false()
	assert_bool(BENCH.is_snap_then_fire(4.0, 4.0)).is_false()


func test_is_snap_then_fire_exact_threshold_counts_as_snap() -> void:
	assert_bool(BENCH.is_snap_then_fire(40.0, 50.0)).is_true()  # ratio exactement 0.8


## ---- max_simultaneous_events (B12, fenêtre de synchronisation) ----

func test_max_simultaneous_events_is_zero_when_empty() -> void:
	assert_int(BENCH.max_simultaneous_events([], 0.2)).is_equal(0)


func test_max_simultaneous_events_counts_events_within_window() -> void:
	assert_int(BENCH.max_simultaneous_events([0.0, 0.05, 0.1, 5.0], 0.2)).is_equal(3)


func test_max_simultaneous_events_is_one_when_all_spread_out() -> void:
	assert_int(BENCH.max_simultaneous_events([0.0, 0.3, 0.6, 0.9], 0.2)).is_equal(1)


func test_max_simultaneous_events_ignores_input_order() -> void:
	assert_int(BENCH.max_simultaneous_events([5.0, 0.0, 0.05], 0.2)).is_equal(2)


# ======================================================================
#  BOT-20 — check_observed_thresholds (B1-B20, seuils "observés").
# ======================================================================

func test_empty_metrics_humanity_has_sentinels() -> void:
	var m := BENCH.empty_metrics()
	var h: Dictionary = m.get("humanity", {})
	assert_float(float(h.get("b1_yaw_speed_p99_deg_s"))).is_equal_approx(-1.0, 0.0001)
	assert_int(int(h.get("b1_yaw_snap_violations"))).is_equal(0)
	assert_int(int(h.get("b9_aim_point_jumps"))).is_equal(0)
	assert_int(int(h.get("b12_shuttle_events"))).is_equal(0)
	for diff_key in BENCH.ACCURACY_RANGES:
		assert_float(float(h.get("b4_ttfs_median_s").get(diff_key))).is_equal_approx(-1.0, 0.0001)


func test_empty_metrics_passes_every_observed_threshold_check() -> void:
	var warnings := BENCH.check_observed_thresholds(BENCH.empty_metrics())
	assert_array(warnings).append_failure_message(
		"un jeu de métriques B1-B20 entièrement vide ne doit déclencher aucun avertissement : %s" % [warnings]
	).is_empty()


func test_empty_metrics_never_fails_the_blocking_check_via_humanity_fields() -> void:
	# check_thresholds reste BOT-13 uniquement — les champs "humanity" ne
	# doivent jamais influencer le résultat bloquant.
	assert_array(BENCH.check_thresholds(BENCH.empty_metrics())).is_empty()


## Métriques "humanité" saines : au centre de chaque fourchette documentée.
func _healthy_humanity_metrics() -> Dictionary:
	var m := BENCH.empty_metrics()
	var h: Dictionary = m.humanity
	h.b1_yaw_speed_p99_deg_s = 200.0
	h.b2_yaw_accel_p99_deg_s2 = 2000.0
	h.b3_look_move_divergence_ratio = 0.4
	h.b3_pitch_stddev_deg = 10.0
	for diff_key in BENCH.OBS_TTFS_MEDIAN_RANGES:
		var bounds: Array = BENCH.OBS_TTFS_MEDIAN_RANGES[diff_key]
		h.b4_ttfs_median_s[diff_key] = (float(bounds[0]) + float(bounds[1])) * 0.5
		h.b4_ttfs_cv[diff_key] = 0.5
		h.b4_ttfs_p5_s[diff_key] = 0.3
	h.b5_shots_moving_ratio = 0.6
	h.b5_moving_accuracy_ratio = 0.1
	h.b5_fast_moving_shots_ratio = 0.01
	h.b6_dodge_segment_median_s = 0.5
	h.b6_dodge_segment_max_s = 1.0
	h.b6_dodge_lateral_p99_m = 2.0
	h.b6_dodge_stop_ratio = 0.25
	h.b7_ads_toggles_p99 = 1.0
	h.b7_ads_rapid_toggle_ratio = 0.0
	h.b8_semi_auto_interval_cv = 0.3
	h.b8_semi_auto_max_rate_ratio = 0.1
	h.b9_aim_point_jumps = 0
	h.b10_snap_then_fire_ratio = 0.01
	h.b11_ally_distance_median_m = 10.0
	h.b11_close_ally_ratio = 0.05
	h.b11_far_from_all_ratio = 0.1
	h.b12_max_simultaneous_goal_changes = 1
	h.b13_spawn_presence_ratio = 0.01
	h.b14_random_jumps = 0
	h.b14_low_speed_crouches = 0
	h.b15_stuck_episodes_per_5min = 0.2
	h.b15_wall_contact_ratio = 0.01
	h.b17_trade_ratio = 0.5
	h.b18_zone_bot_count_median = 2.0
	h.b18_zone_spacing_median_m = 3.0
	h.b18_watch_bot_count_median = 1.0
	h.b18_rotation_arrival_ratio = 1.0
	h.b20_hearing_error_median_m = 4.0
	return m


func test_healthy_humanity_metrics_pass_every_observed_threshold() -> void:
	var warnings := BENCH.check_observed_thresholds(_healthy_humanity_metrics())
	assert_array(warnings).append_failure_message(
		"des métriques B1-B20 saines ne devraient déclencher aucun avertissement : %s" % [warnings]
	).is_empty()


func test_yaw_speed_over_threshold_is_observed() -> void:
	var m := _healthy_humanity_metrics()
	m.humanity.b1_yaw_speed_p99_deg_s = BENCH.OBS_YAW_SPEED_P99_MAX_DEG_S + 10.0
	var warnings := BENCH.check_observed_thresholds(m)
	assert_int(warnings.size()).is_equal(1)
	assert_str(str(warnings[0])).contains("B1")


func test_yaw_snap_violation_is_observed() -> void:
	var m := _healthy_humanity_metrics()
	m.humanity.b1_yaw_snap_violations = 3
	assert_int(BENCH.check_observed_thresholds(m).size()).is_equal(1)


func test_ttfs_median_out_of_range_is_observed_per_difficulty() -> void:
	var m := _healthy_humanity_metrics()
	m.humanity.b4_ttfs_median_s["veteran"] = 5.0
	var warnings := BENCH.check_observed_thresholds(m)
	assert_int(warnings.size()).is_equal(1)
	var msg := str(warnings[0]).to_lower()
	assert_bool(msg.contains("b4") and msg.contains("veteran")).is_true()


func test_b12_three_or_more_simultaneous_goal_changes_is_observed() -> void:
	var m := _healthy_humanity_metrics()
	m.humanity.b12_max_simultaneous_goal_changes = 3
	assert_int(BENCH.check_observed_thresholds(m).size()).is_equal(1)


func test_b17_trade_ratio_below_threshold_is_observed() -> void:
	var m := _healthy_humanity_metrics()
	m.humanity.b17_trade_ratio = 0.05
	assert_int(BENCH.check_observed_thresholds(m).size()).is_equal(1)


func test_b20_hearing_error_exactly_zero_is_always_observed() -> void:
	# "jamais 0" (§4 B20) : reste vrai TANT QUE l'ouïe n'est pas bruitée
	# (BOT-29) — la valeur mesurée aujourd'hui est justement 0 exact.
	var m := _healthy_humanity_metrics()
	m.humanity.b20_hearing_error_median_m = 0.0
	var warnings := BENCH.check_observed_thresholds(m)
	assert_int(warnings.size()).is_equal(1)
	assert_str(str(warnings[0])).contains("B20")


func test_b18_zone_bot_count_out_of_range_is_observed() -> void:
	var m := _healthy_humanity_metrics()
	m.humanity.b18_zone_bot_count_median = 5.0
	var warnings := BENCH.check_observed_thresholds(m)
	assert_int(warnings.size()).is_equal(1)
	assert_str(str(warnings[0])).contains("B18")


func test_b18_zone_spacing_and_watch_count_below_threshold_are_observed() -> void:
	var m := _healthy_humanity_metrics()
	m.humanity.b18_zone_spacing_median_m = 1.0
	m.humanity.b18_watch_bot_count_median = 0.0
	assert_int(BENCH.check_observed_thresholds(m).size()).is_equal(2)


func test_b20_hearing_sentinel_never_observed() -> void:
	var m := _healthy_humanity_metrics()
	m.humanity.b20_hearing_error_median_m = -1.0
	assert_array(BENCH.check_observed_thresholds(m)).is_empty()


func test_multiple_simultaneous_humanity_violations_are_all_observed() -> void:
	var m := _healthy_humanity_metrics()
	m.humanity.b1_yaw_speed_p99_deg_s = BENCH.OBS_YAW_SPEED_P99_MAX_DEG_S + 50.0
	m.humanity.b9_aim_point_jumps = 2
	m.humanity.b15_wall_contact_ratio = BENCH.OBS_WALL_CONTACT_RATIO_MAX + 0.5
	assert_int(BENCH.check_observed_thresholds(m).size()).is_equal(3)
