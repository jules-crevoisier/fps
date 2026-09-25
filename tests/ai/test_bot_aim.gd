## test_bot_aim.gd
## Spec (BOT-26, docs/research/08_bots_humanlike.md §3.2 A1-A6/A9, §3.8) :
## BotAim v2 — offset d'erreur qui DÉRIVE (filtre τ=0.16s, jamais un saut,
## A2), tiré par intervalle propre à la difficulté ; magnitude scalaire
## toujours régénérée périodiquement, décroissante en suivi avec un τ propre
## à la difficulté (A3) et remontée si la cible bouge vite, si la vue PROPRE
## du bot tourne à plus de 100°/s ou s'il se déplace à plus de 50 % du sprint
## (A9) ; répartie en gaussienne 2D ANISOTROPE (σ axe = 2.2×σ perp, A3) ;
## ratio de flick N(0.97;0.05) borné [0.85;1.08] (A4) ; ressort-amortisseur
## CRITIQUE (plus de dépassement fixe) plafonné en accélération par
## difficulté (A1) ; visée en suivi retardée d'une file de perception propre
## à la difficulté (A5). Le §"Monte-Carlo" simule, avec une graine FIXE
## (résultat reproductible, jamais flaky), la précision attendue à 5/20/40 m
## par difficulté avec une arme de RÉFÉRENCE commune (dispersion 0.5°).
extends GdUnitTestSuite

const RECRUE := MatchConfig.Difficulty.RECRUE
const VETERAN := MatchConfig.Difficulty.VETERAN
const ELITE := MatchConfig.Difficulty.ELITE

# ======================================================================
#  Erreur d'angle — magnitude en degrés, décroissance par difficulté (A3),
#  majoration cible rapide (inchangé BOT-02), vue propre / déplacement (A9).
# ======================================================================

func test_max_error_deg_per_difficulty() -> void:
	assert_float(BotAim.max_error_deg(RECRUE)).is_equal_approx(5.0, 0.001)
	assert_float(BotAim.max_error_deg(VETERAN)).is_equal_approx(2.5, 0.001)
	assert_float(BotAim.max_error_deg(ELITE)).is_equal_approx(1.0, 0.001)


func test_max_error_monotonic_recrue_veteran_elite() -> void:
	assert_bool(BotAim.max_error_deg(RECRUE) > BotAim.max_error_deg(VETERAN)).is_true()
	assert_bool(BotAim.max_error_deg(VETERAN) > BotAim.max_error_deg(ELITE)).is_true()


func test_tracking_shrink_tau_per_difficulty() -> void:
	# §3.8 : τ = 1.5 / 0.8 / 0.45 s — Vétéran reste la valeur BOT-02 (0.8 s),
	# Recrue et Élite s'en écartent désormais dans des sens opposés.
	assert_float(BotAim.tracking_shrink_tau(RECRUE)).is_equal_approx(1.5, 0.001)
	assert_float(BotAim.tracking_shrink_tau(VETERAN)).is_equal_approx(0.8, 0.001)
	assert_float(BotAim.tracking_shrink_tau(ELITE)).is_equal_approx(0.45, 0.001)


func test_current_error_at_zero_tracking_equals_max() -> void:
	var fresh := BotAim.current_error_deg(VETERAN, 0.0, 0.0)
	assert_float(fresh).is_equal_approx(BotAim.max_error_deg(VETERAN), 0.0001)


func test_current_error_shrinks_while_tracking() -> void:
	var fresh := BotAim.current_error_deg(VETERAN, 0.0, 0.0)
	var tracked := BotAim.current_error_deg(VETERAN, 2.0, 0.0)
	assert_bool(tracked < fresh).is_true()


func test_current_error_tau_matches_tracking_shrink_tau() -> void:
	# À t = τ(difficulté), l'erreur doit être tombée à ~36.8 % (1/e) du max —
	# pour LES TROIS difficultés désormais (τ propre à chacune, A3).
	for d in [RECRUE, VETERAN, ELITE]:
		var tau := BotAim.tracking_shrink_tau(d)
		var at_tau := BotAim.current_error_deg(d, tau, 0.0)
		assert_float(at_tau).append_failure_message(
			"difficulté %d : erreur à t=τ (%.4f) != max×e⁻¹ (%.4f)" % [d, at_tau, BotAim.max_error_deg(d) * exp(-1.0)]
		).is_equal_approx(BotAim.max_error_deg(d) * exp(-1.0), 0.01)


func test_current_error_never_negative() -> void:
	assert_float(BotAim.current_error_deg(RECRUE, 100.0, 0.0)).is_greater_equal(0.0)


func test_current_error_is_deterministic_for_same_inputs() -> void:
	# BotAim ne mémorise aucun état de frame : deux appels avec les MÊMES
	# arguments renvoient EXACTEMENT la même magnitude — la règle "jamais
	# par frame" est garantie par l'APPELANT (BotBrain), qui ne doit
	# ré-invoquer cette fonction qu'à chaque régénération périodique.
	var a := BotAim.current_error_deg(RECRUE, 0.5, 10.0)
	var b := BotAim.current_error_deg(RECRUE, 0.5, 10.0)
	assert_float(a).is_equal_approx(b, 0.00001)


func test_fast_target_multiplies_error_by_1_5() -> void:
	var slow := BotAim.current_error_deg(VETERAN, 0.5, 60.0)
	var fast := BotAim.current_error_deg(VETERAN, 0.5, 60.0001)
	assert_float(fast).is_equal_approx(slow * 1.5, 0.001)


func test_fast_target_threshold_is_60_deg_per_s() -> void:
	var at_threshold := BotAim.current_error_deg(VETERAN, 0.5, 60.0)
	var above := BotAim.current_error_deg(VETERAN, 0.5, 61.0)
	assert_bool(above > at_threshold).is_true()

# ======================================================================
#  A9 — précision qui se dégrade : vue propre rapide (>100°/s) remonte
#  l'erreur à au moins 50 % du max ; déplacement rapide (>50 % du sprint) la
#  multiplie par 1.3.
# ======================================================================

func test_own_view_speed_floors_error_at_half_max_when_fast() -> void:
	# Erreur bien décrue par un long suivi (proche de 0) : sans le plancher A9,
	# elle resterait minuscule malgré la vue propre rapide.
	var without_fast_view := BotAim.current_error_deg(VETERAN, 3.0, 0.0, 0.0, 0.0)
	var with_fast_view := BotAim.current_error_deg(VETERAN, 3.0, 0.0, 150.0, 0.0)
	assert_bool(with_fast_view > without_fast_view).is_true()
	assert_float(with_fast_view).is_greater_equal(BotAim.max_error_deg(VETERAN) * 0.5 - 0.0001)


func test_own_view_speed_threshold_is_100_deg_per_s() -> void:
	var at_threshold := BotAim.current_error_deg(VETERAN, 3.0, 0.0, 100.0, 0.0)
	var above := BotAim.current_error_deg(VETERAN, 3.0, 0.0, 100.0001, 0.0)
	assert_bool(above > at_threshold).is_true()


func test_own_view_speed_never_lowers_error() -> void:
	# Le plancher A9 ne s'applique que si l'erreur "naturelle" est DÉJÀ sous
	# 50 % du max — au-dessus, il ne doit jamais la faire redescendre.
	var natural := BotAim.current_error_deg(VETERAN, 0.0, 0.0, 0.0, 0.0)  # = max, bien au-dessus de 50%.
	var with_fast_view := BotAim.current_error_deg(VETERAN, 0.0, 0.0, 150.0, 0.0)
	assert_float(with_fast_view).is_equal_approx(natural, 0.0001)


func test_own_movement_speed_multiplies_error_by_1_3() -> void:
	var slow := BotAim.current_error_deg(VETERAN, 0.5, 0.0, 0.0, 0.5)
	var fast := BotAim.current_error_deg(VETERAN, 0.5, 0.0, 0.0, 0.5001)
	assert_float(fast).is_equal_approx(slow * 1.3, 0.001)


func test_own_movement_speed_threshold_is_half_sprint() -> void:
	var at_rest := BotAim.current_error_deg(VETERAN, 0.5, 0.0, 0.0, 0.0)
	var at_threshold := BotAim.current_error_deg(VETERAN, 0.5, 0.0, 0.0, 0.5)
	assert_float(at_threshold).is_equal_approx(at_rest, 0.0001)

# ======================================================================
#  A2 — offset qui dérive : intervalle de régénération propre à la
#  difficulté, filtre du 1er ordre τ=0.16s (jamais un saut).
# ======================================================================

func test_offset_regen_interval_ranges_per_difficulty() -> void:
	assert_float(BotAim.offset_regen_interval_range(RECRUE).x).is_equal_approx(0.6, 0.001)
	assert_float(BotAim.offset_regen_interval_range(RECRUE).y).is_equal_approx(1.0, 0.001)
	assert_float(BotAim.offset_regen_interval_range(VETERAN).x).is_equal_approx(0.3, 0.001)
	assert_float(BotAim.offset_regen_interval_range(VETERAN).y).is_equal_approx(0.6, 0.001)
	assert_float(BotAim.offset_regen_interval_range(ELITE).x).is_equal_approx(0.15, 0.001)
	assert_float(BotAim.offset_regen_interval_range(ELITE).y).is_equal_approx(0.35, 0.001)


func test_next_regen_interval_within_difficulty_range() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for d in [RECRUE, VETERAN, ELITE]:
		var r := BotAim.offset_regen_interval_range(d)
		for i in range(300):
			var interval := BotAim.next_regen_interval(rng, d)
			assert_float(interval).is_greater_equal(r.x)
			assert_float(interval).is_less_equal(r.y)


func test_next_regen_interval_is_not_a_fixed_value() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var first := BotAim.next_regen_interval(rng, VETERAN)
	var distinct := false
	for i in range(20):
		if not is_equal_approx(BotAim.next_regen_interval(rng, VETERAN), first):
			distinct = true
			break
	assert_bool(distinct).is_true()


func test_offset_filter_step_never_jumps_to_target() -> void:
	# "Absence de saut de l'offset" (BOT-26) : un seul pas à 60 Hz ne
	# rapproche JAMAIS totalement l'offset de sa cible, quel que soit l'écart.
	var next := BotAim.offset_filter_step(0.0, 10.0, 1.0 / 60.0)
	assert_float(next).is_greater(0.0)
	assert_float(next).is_less(10.0)


func test_offset_filter_step_moves_about_10_percent_of_gap_at_60hz() -> void:
	# Doc §1 ligne 2 : "Dérive : 10% de l'écart par mise à jour (τ≈0.16s à 60Hz)".
	var next := BotAim.offset_filter_step(0.0, 10.0, 1.0 / 60.0)
	assert_float(next).is_between(0.7, 1.3)


func test_offset_filter_step_converges_without_overshoot() -> void:
	var current := 0.0
	var target := 5.0
	var delta := 1.0 / 60.0
	for i in range(600):
		var prev := current
		current = BotAim.offset_filter_step(current, target, delta)
		assert_float(current).append_failure_message("pas %d : dépassement de la cible" % i).is_less_equal(target + 0.0001)
		assert_float(current).append_failure_message("pas %d : recule au lieu d'avancer" % i).is_greater_equal(prev - 0.0001)
	assert_float(current).is_equal_approx(target, 0.01)


func test_offset_filter_step_never_moves_backward_from_negative_target() -> void:
	# Symétrie : une cible négative converge de la même façon (pas de biais de
	# signe caché dans l'implémentation du filtre).
	var current := 0.0
	var target := -5.0
	var delta := 1.0 / 60.0
	for i in range(600):
		var prev := current
		current = BotAim.offset_filter_step(current, target, delta)
		assert_float(current).is_greater_equal(target - 0.0001)
		assert_float(current).is_less_equal(prev + 0.0001)
	assert_float(current).is_equal_approx(target, 0.01)

# ======================================================================
#  A3 — forme de l'erreur : gaussienne 2D anisotrope, σ axe = 2.2×σ perp,
#  même amplitude RMS totale que la magnitude scalaire d'entrée.
# ======================================================================

func test_axis_sigma_is_2_2_times_perp_sigma() -> void:
	var perp := BotAim.perp_sigma_deg(3.0)
	var axis := BotAim.axis_sigma_deg(3.0)
	assert_float(axis / perp).is_equal_approx(BotAim.AXIS_SIGMA_RATIO, 0.0001)
	assert_float(BotAim.AXIS_SIGMA_RATIO).is_equal_approx(2.2, 0.0001)


func test_anisotropic_offset_rms_matches_input_magnitude() -> void:
	# RMS = sqrt(E[yaw² + pitch²]) doit retomber sur `error_rms_deg` (même
	# précision GLOBALE qu'avant BOT-26, seulement une répartition
	# directionnelle différente).
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var error_rms_deg := 4.0
	var sum_sq := 0.0
	var trials := 20000
	for i in range(trials):
		var offset := BotAim.sample_anisotropic_offset(error_rms_deg, 0.0, rng)
		sum_sq += offset.x * offset.x + offset.y * offset.y
	var measured_rms := sqrt(sum_sq / float(trials))
	assert_float(measured_rms).append_failure_message(
		"RMS mesuré %.4f attendu ~%.4f" % [measured_rms, error_rms_deg]
	).is_equal_approx(error_rms_deg, 0.15)


func test_anisotropic_offset_stretches_along_axis_angle() -> void:
	# Le long de l'axe (axis_angle_deg = 0 -> composante "yaw"), la variance
	# doit être nettement supérieure à la composante perpendiculaire (pitch).
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var trials := 20000
	var sum_yaw_sq := 0.0
	var sum_pitch_sq := 0.0
	for i in range(trials):
		var offset := BotAim.sample_anisotropic_offset(3.0, 0.0, rng)
		sum_yaw_sq += offset.x * offset.x
		sum_pitch_sq += offset.y * offset.y
	var ratio := sqrt(sum_yaw_sq / sum_pitch_sq)
	assert_float(ratio).append_failure_message(
		"ratio mesuré yaw/pitch %.3f attendu ~2.2" % ratio
	).is_between(1.8, 2.6)


func test_anisotropic_offset_is_reproducible_for_same_seed() -> void:
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 55
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 55
	var a := BotAim.sample_anisotropic_offset(3.0, 45.0, rng_a)
	var b := BotAim.sample_anisotropic_offset(3.0, 45.0, rng_b)
	assert_float(a.x).is_equal_approx(b.x, 0.00001)
	assert_float(a.y).is_equal_approx(b.y, 0.00001)

# ======================================================================
#  A4 — flick : ratio d'amplitude N(0.97;0.05), borné [0.85;1.08].
# ======================================================================

func test_flick_ratio_within_bounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	for i in range(2000):
		var r := BotAim.flick_ratio(rng)
		assert_float(r).is_greater_equal(BotAim.FLICK_RATIO_MIN)
		assert_float(r).is_less_equal(BotAim.FLICK_RATIO_MAX)


func test_flick_ratio_mean_near_0_97() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 271828
	var sum := 0.0
	var trials := 5000
	for i in range(trials):
		sum += BotAim.flick_ratio(rng)
	var mean := sum / float(trials)
	assert_float(mean).append_failure_message("moyenne mesurée %.4f attendue ~0.97" % mean).is_equal_approx(0.97, 0.01)


func test_flick_ratio_is_not_a_fixed_value() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var first := BotAim.flick_ratio(rng)
	var distinct := false
	for i in range(20):
		if not is_equal_approx(BotAim.flick_ratio(rng), first):
			distinct = true
			break
	assert_bool(distinct).is_true()

# ======================================================================
#  A5 — retard de perception : délai propre à la difficulté, file d'échantillons.
# ======================================================================

func test_perception_delay_per_difficulty() -> void:
	assert_float(BotAim.perception_delay_s(RECRUE)).is_equal_approx(0.25, 0.001)
	assert_float(BotAim.perception_delay_s(VETERAN)).is_equal_approx(0.20, 0.001)
	assert_float(BotAim.perception_delay_s(ELITE)).is_equal_approx(0.15, 0.001)


func test_delayed_position_empty_history_returns_fallback() -> void:
	var fallback := Vector3(1, 2, 3)
	var result := BotAim.delayed_position([], 10.0, 0.2, fallback)
	assert_bool(result.is_equal_approx(fallback)).is_true()


func test_delayed_position_before_oldest_sample_returns_oldest() -> void:
	var history := [
		{"time": 10.0, "pos": Vector3(1, 0, 0)},
		{"time": 10.1, "pos": Vector3(2, 0, 0)},
	]
	# now - delay = 9.5, avant même le plus ancien échantillon (10.0).
	var result := BotAim.delayed_position(history, 10.2, 0.7, Vector3.ZERO)
	assert_bool(result.is_equal_approx(Vector3(1, 0, 0))).is_true()


func test_delayed_position_interpolates_between_samples() -> void:
	var history := [
		{"time": 10.0, "pos": Vector3(0, 0, 0)},
		{"time": 10.2, "pos": Vector3(2, 0, 0)},
	]
	# now=10.2, delay=0.1 -> target_time=10.1 -> à mi-chemin entre les deux échantillons.
	var result := BotAim.delayed_position(history, 10.2, 0.1, Vector3.ZERO)
	assert_bool(result.is_equal_approx(Vector3(1, 0, 0))).is_true()


func test_delayed_position_beyond_newest_returns_newest() -> void:
	var history := [
		{"time": 10.0, "pos": Vector3(0, 0, 0)},
		{"time": 10.2, "pos": Vector3(2, 0, 0)},
	]
	# delay négatif ou nul : demande une position plus récente que le dernier échantillon.
	var result := BotAim.delayed_position(history, 10.2, 0.0, Vector3.ZERO)
	assert_bool(result.is_equal_approx(Vector3(2, 0, 0))).is_true()

# ======================================================================
#  Point visé — torse au-delà de 20 m, sauf Élite. Inchangé (BOT-02).
# ======================================================================

func test_aims_head_under_20m_all_difficulties() -> void:
	assert_bool(BotAim.aims_torso_beyond_range(RECRUE, 5.0)).is_false()
	assert_bool(BotAim.aims_torso_beyond_range(VETERAN, 19.9)).is_false()
	assert_bool(BotAim.aims_torso_beyond_range(ELITE, 19.9)).is_false()


func test_aims_head_at_exactly_20m() -> void:
	assert_bool(BotAim.aims_torso_beyond_range(RECRUE, 20.0)).is_false()


func test_aims_torso_beyond_20m_except_elite() -> void:
	assert_bool(BotAim.aims_torso_beyond_range(RECRUE, 20.1)).is_true()
	assert_bool(BotAim.aims_torso_beyond_range(VETERAN, 40.0)).is_true()
	assert_bool(BotAim.aims_torso_beyond_range(ELITE, 40.0)).is_false()


func test_targeted_half_width_matches_aim_point() -> void:
	assert_float(BotAim.targeted_half_width_m(RECRUE, 5.0)).is_equal_approx(BotAim.HEAD_HALF_WIDTH_M, 0.0001)
	assert_float(BotAim.targeted_half_width_m(RECRUE, 40.0)).is_equal_approx(BotAim.TORSO_HALF_WIDTH_M, 0.0001)
	assert_float(BotAim.targeted_half_width_m(ELITE, 40.0)).is_equal_approx(BotAim.HEAD_HALF_WIDTH_M, 0.0001)


func test_hitbox_half_width_deg_known_angle() -> void:
	# demi-largeur == distance -> atan(1) == 45°.
	assert_float(BotAim.hitbox_half_width_deg(10.0, 10.0)).is_equal_approx(45.0, 0.001)


func test_hitbox_half_width_deg_shrinks_with_distance() -> void:
	var near := BotAim.hitbox_half_width_deg(0.3, 5.0)
	var far := BotAim.hitbox_half_width_deg(0.3, 40.0)
	assert_bool(far < near).is_true()

# ======================================================================
#  Condition de tir. Inchangé (BOT-02).
# ======================================================================

func test_can_fire_when_error_under_allowed() -> void:
	assert_bool(BotAim.can_fire(1.0, 2.0, 0.5)).is_true()


func test_cannot_fire_when_error_over_allowed() -> void:
	assert_bool(BotAim.can_fire(5.0, 2.0, 0.5)).is_false()


func test_can_fire_is_strict_at_boundary() -> void:
	assert_bool(BotAim.can_fire(2.5, 2.0, 0.5)).is_false()

# ======================================================================
#  A1 — ressort-amortisseur CRITIQUE (plus de dépassement fixe, A4) plafonné
#  en accélération par difficulté.
# ======================================================================

func test_spring_peak_speed_per_difficulty() -> void:
	assert_float(BotAim.spring_peak_speed_deg(RECRUE)).is_equal_approx(300.0, 0.001)
	assert_float(BotAim.spring_peak_speed_deg(VETERAN)).is_equal_approx(500.0, 0.001)
	assert_float(BotAim.spring_peak_speed_deg(ELITE)).is_equal_approx(800.0, 0.001)


func test_angular_accel_cap_per_difficulty() -> void:
	assert_float(BotAim.angular_accel_cap_deg(RECRUE)).is_equal_approx(2000.0, 0.001)
	assert_float(BotAim.angular_accel_cap_deg(VETERAN)).is_equal_approx(3000.0, 0.001)
	assert_float(BotAim.angular_accel_cap_deg(ELITE)).is_equal_approx(4500.0, 0.001)


func test_spring_params_stiffer_for_higher_difficulty() -> void:
	var k_recrue: float = BotAim.spring_params(RECRUE).k
	var k_veteran: float = BotAim.spring_params(VETERAN).k
	var k_elite: float = BotAim.spring_params(ELITE).k
	assert_bool(k_recrue < k_veteran).is_true()
	assert_bool(k_veteran < k_elite).is_true()


func test_spring_step_moves_toward_target() -> void:
	var params := BotAim.spring_params(VETERAN)
	var step: Dictionary = BotAim.spring_step(0.0, 0.0, 90.0, params.k, params.d, 1.0 / 60.0)
	assert_float(step.angle).is_greater(0.0)
	assert_float(step.speed).is_greater(0.0)


func test_spring_natural_freq_keeps_2_argument_signature_for_bot_look() -> void:
	# scripts/ai/BotLook.gd (BOT-25, hors de ma liste de fichiers) appelle
	# `BotAim.spring_natural_freq(peak_speed_deg, zeta)` DIRECTEMENT avec son
	# propre ζ=0.9 — régression de compatibilité si cette signature bouge.
	var wn := BotAim.spring_natural_freq(300.0, 0.9)
	assert_float(wn).is_greater(0.0)


## Simule un "flick" (saut brusque de la cible du repos vers FLICK_REFERENCE_DEG)
## avec le ressort-amortisseur CRITIQUE calibré pour `difficulty`, plafonné en
## accélération (comme en production, BotBrain._aim_towards), à 60 Hz (le
## taux de la boucle physique de BotBrain._physics_process) pendant 3 s.
func _simulate_flick(difficulty: int) -> Dictionary:
	var params := BotAim.spring_params(difficulty)
	var max_accel := BotAim.angular_accel_cap_deg(difficulty)
	var angle := 0.0
	var speed := 0.0
	var target := BotAim.FLICK_REFERENCE_DEG
	var max_angle := 0.0
	var max_speed := 0.0
	var max_accel_seen := 0.0
	var delta := 1.0 / 60.0
	var steps := int(3.0 / delta)
	for i in range(steps):
		var prev_speed := speed
		var step: Dictionary = BotAim.spring_step(angle, speed, target, params.k, params.d, delta, max_accel)
		angle = step.angle
		speed = step.speed
		if angle > max_angle:
			max_angle = angle
		if absf(speed) > max_speed:
			max_speed = absf(speed)
		var accel_used := absf(speed - prev_speed) / delta
		if accel_used > max_accel_seen:
			max_accel_seen = accel_used
	return {"peak_speed": max_speed, "overshoot_ratio": (max_angle - target) / target, "peak_accel": max_accel_seen}


func test_critical_spring_has_no_overshoot_on_reference_flick() -> void:
	# A4 : "plus de dépassement fixe" — le ressort lui-même (ζ=1, critique) ne
	# dépasse plus JAMAIS sa cible ; le sur/sous-virage humain vient désormais
	# du ratio de flick appliqué en amont sur l'OFFSET (BotBrain._aim_towards),
	# pas du ressort.
	for difficulty in [RECRUE, VETERAN, ELITE]:
		var result := _simulate_flick(difficulty)
		assert_float(result.overshoot_ratio).append_failure_message(
			"difficulté %d : dépassement %.4f (devrait être ~0, ressort critique)" % [difficulty, result.overshoot_ratio]
		).is_less_equal(0.005)


func test_flick_accel_never_exceeds_cap() -> void:
	for difficulty in [RECRUE, VETERAN, ELITE]:
		var result := _simulate_flick(difficulty)
		var cap := BotAim.angular_accel_cap_deg(difficulty)
		assert_float(result.peak_accel).append_failure_message(
			"difficulté %d : accélération %.1f°/s² dépasse le plafond %.1f°/s²" % [difficulty, result.peak_accel, cap]
		).is_less_equal(cap * 1.001)  # marge d'arrondi Euler.


func test_flick_peak_speed_near_difficulty_target() -> void:
	# Tolérance ±25 % : l'intégration Euler à 60 Hz PLUS le plafond
	# d'accélération (A1, actif en production) dévie un peu plus du pic
	# analytique continu que le ressort seul (v1, BOT-02, ±20 %).
	for difficulty in [RECRUE, VETERAN, ELITE]:
		var target_peak := BotAim.spring_peak_speed_deg(difficulty)
		var result := _simulate_flick(difficulty)
		assert_float(result.peak_speed).append_failure_message(
			"difficulté %d : pic %.1f°/s hors de ±25%% de la cible %.0f°/s" % [difficulty, result.peak_speed, target_peak]
		).is_between(target_peak * 0.75, target_peak * 1.25)

# ======================================================================
#  Monte-Carlo — précision attendue à 5/20/40 m par difficulté.
#
#  Modèle du tir : au moment T où un tir est tenté, l'erreur courante
#  (magnitude régénérée périodiquement, `BotAim.current_error_deg`) doit
#  être sous la demi-largeur angulaire du point visé (tête sous 20 m, ou
#  Élite ; torse au-delà sinon) + la dispersion d'une arme de RÉFÉRENCE
#  commune (0.5°, milieu réaliste entre visée [0.3°] et hanche [2.0°], voir
#  WeaponConfig.spread_aim/spread_hip) : le choix d'arme lui-même (BOT-04)
#  n'est pas la variable testée ici. Les facteurs A9 (vue propre / vitesse de
#  déplacement du bot) ne sont pas modélisés ici (0 par défaut) : cette
#  simulation isole le modèle d'erreur/hitbox par difficulté ET temps de
#  suivi/vitesse de la CIBLE, indépendamment du comportement du bot lui-même.
#
#  Par tirage : `tracking_time` ~ U(0, 2.5 s) (l'instant du tir dans un
#  engagement typique, de l'acquisition à 2.5 s de suivi continu) et
#  `target_angular_speed` ~ U(0, 90 °/s) (de la cible immobile au strafe
#  rapide) — graine FIXE dérivée par cellule : résultat reproductible,
#  jamais flaky.
# ======================================================================

const MC_TRIALS := 1000
const MC_SEED := 20260924
const MC_WEAPON_SPREAD_DEG := 0.5
const MC_TRACKING_MAX := 2.5
const MC_ANGULAR_SPEED_MAX := 90.0

## Fourchettes documentées (bornes larges avec marge — le test compare aussi
## DIRECTEMENT les valeurs entre elles pour la monotonie et le 5m/40m, voir
## plus bas ; ces bornes absolues garantissent que le modèle reste dans un
## registre humain plausible, ni aimbot ni totalement aveugle). Recalibrées
## pour BOT-26 (τ de décroissance propre à chaque difficulté, A3). Recrue
## (τ 0.8s -> 1.5s, décroissance BEAUCOUP plus lente) : l'erreur plancher
## atteignable dans la fenêtre de suivi simulée ici (0-2.5 s, voir
## MC_TRACKING_MAX) est ~0.945° — MATHÉMATIQUEMENT au-dessus du seuil
## autorisé à 20/40 m (torse/tête + dispersion de référence, ~0.32-0.93°) :
## 0 tir possible à ces distances dans CETTE fenêtre, pas une rareté
## statistique (vérifié : `min_err_seen` sur 1000 tirages = l'erreur au t
## maximal de la fenêtre, systématiquement au-dessus du seuil). Un Recrue
## touche donc surtout au contact (5 m) tant qu'il n'a pas suivi sa cible
## PLUS de 2.5 s — cohérent avec la spec (un Recrue est structurellement
## faible à distance, même plus que CS Easy dont le τ documenté [S5] est
## ~4.5 s, contre 1.5 s ici). Élite (τ 0.8s -> 0.45s, décroissance plus
## rapide) : plus précis qu'avant, remonte vers le plafond [0,1] de la
## fraction mesurée.
const MC_EXPECTED_RANGES := {
	0: {5.0: [0.20, 0.40], 20.0: [0.00, 0.02], 40.0: [0.00, 0.02]},   # RECRUE
	1: {5.0: [0.65, 0.95], 20.0: [0.40, 0.75], 40.0: [0.40, 0.80]},   # VETERAN
	2: {5.0: [0.95, 1.00], 20.0: [0.85, 1.00], 40.0: [0.70, 1.00]},   # ELITE
}

## Précision Monte-Carlo (fraction des `MC_TRIALS` tirages où `BotAim.can_fire`
## est vrai) pour `difficulty` à `distance` m — graine dérivée de MC_SEED,
## `distance` et `difficulty` pour que chaque cellule de la table soit
## indépendante mais reproductible.
func _monte_carlo_precision(difficulty: int, distance: float) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = MC_SEED + difficulty * 100000 + int(distance * 10.0)
	var half_width_m := BotAim.targeted_half_width_m(difficulty, distance)
	var allowed := BotAim.hitbox_half_width_deg(half_width_m, distance)
	var hits := 0
	for i in range(MC_TRIALS):
		var tracking_time := rng.randf_range(0.0, MC_TRACKING_MAX)
		var angular_speed := rng.randf_range(0.0, MC_ANGULAR_SPEED_MAX)
		var error_deg := BotAim.current_error_deg(difficulty, tracking_time, angular_speed)
		if BotAim.can_fire(error_deg, allowed, MC_WEAPON_SPREAD_DEG):
			hits += 1
	return float(hits) / float(MC_TRIALS)


func test_monte_carlo_precision_within_documented_ranges() -> void:
	for difficulty in [RECRUE, VETERAN, ELITE]:
		for distance in [5.0, 20.0, 40.0]:
			var precision := _monte_carlo_precision(difficulty, distance)
			var bounds: Array = MC_EXPECTED_RANGES[difficulty][distance]
			assert_float(precision).append_failure_message(
				"difficulté %d à %.0f m : précision %.3f hors de [%.2f, %.2f]" % [difficulty, distance, precision, bounds[0], bounds[1]]
			).is_between(bounds[0], bounds[1])


func test_monte_carlo_precision_monotonic_recrue_veteran_elite() -> void:
	for distance in [5.0, 20.0, 40.0]:
		var p_recrue := _monte_carlo_precision(RECRUE, distance)
		var p_veteran := _monte_carlo_precision(VETERAN, distance)
		var p_elite := _monte_carlo_precision(ELITE, distance)
		assert_bool(p_recrue < p_veteran).append_failure_message(
			"à %.0f m : Recrue (%.3f) devrait être < Vétéran (%.3f)" % [distance, p_recrue, p_veteran]
		).is_true()
		assert_bool(p_veteran < p_elite).append_failure_message(
			"à %.0f m : Vétéran (%.3f) devrait être < Élite (%.3f)" % [distance, p_veteran, p_elite]
		).is_true()


func test_monte_carlo_precision_5m_at_least_40m() -> void:
	for difficulty in [RECRUE, VETERAN, ELITE]:
		var p_5m := _monte_carlo_precision(difficulty, 5.0)
		var p_40m := _monte_carlo_precision(difficulty, 40.0)
		assert_bool(p_5m >= p_40m).append_failure_message(
			"difficulté %d : précision à 5 m (%.3f) devrait être >= à 40 m (%.3f)" % [difficulty, p_5m, p_40m]
		).is_true()
