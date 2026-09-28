## test_weapon_action_anim.gd
## Spec (tâche "quatre armes", 2026-09-28) : maths PURES de l'animation
## procédurale du cycle d'action (pompe/levier/verrou) et du geste
## d'insertion (chargeur/cartouche/balle) — `WeaponActionAnim.gd`, consommée
## par `ViewModel._update_action_part` (hors scène, non testée ici).
extends GdUnitTestSuite


func test_progress_is_zero_right_when_triggered() -> void:
	assert_float(WeaponActionAnim.progress(0.0, 0.9)).is_equal_approx(0.0, 0.0001)


func test_progress_is_half_at_half_duration() -> void:
	assert_float(WeaponActionAnim.progress(0.45, 0.9)).is_equal_approx(0.5, 0.0001)


func test_progress_reaches_one_at_full_duration() -> void:
	assert_float(WeaponActionAnim.progress(0.9, 0.9)).is_equal_approx(1.0, 0.0001)


func test_progress_clamps_to_one_past_duration() -> void:
	assert_float(WeaponActionAnim.progress(5.0, 0.9)).is_equal_approx(1.0, 0.0001)


func test_progress_is_one_at_rest_sentinel_t_non_positive() -> void:
	# t <= 0.0 (jamais déclenché, ou juste réinitialisé) -> repos, jamais d'animation.
	assert_float(WeaponActionAnim.progress(0.0, 0.9)).is_equal_approx(0.0, 0.0001)
	assert_float(WeaponActionAnim.progress(-1.0, 0.9)).is_equal_approx(1.0, 0.0001)


func test_progress_is_one_when_duration_is_zero_or_negative() -> void:
	# cycle_time == 0.0 (arme sans cycle dédié, ex. le Ravage) -> jamais d'animation.
	assert_float(WeaponActionAnim.progress(0.1, 0.0)).is_equal_approx(1.0, 0.0001)


func test_swing_is_zero_at_both_ends_and_peaks_at_midpoint() -> void:
	assert_float(WeaponActionAnim.swing(0.0, 1.0)).is_equal_approx(0.0, 0.0001)
	assert_float(WeaponActionAnim.swing(1.0, 1.0)).is_equal_approx(0.0, 0.0001)
	assert_float(WeaponActionAnim.swing(0.5, 1.0)).is_equal_approx(1.0, 0.0001)


func test_swing_scales_with_amount_and_keeps_its_sign() -> void:
	assert_float(WeaponActionAnim.swing(0.5, -0.05)).is_equal_approx(-0.05, 0.0001)
	assert_float(WeaponActionAnim.swing(0.5, 0.62)).is_equal_approx(0.62, 0.0001)


func test_swing_clamps_progress_outside_zero_one() -> void:
	assert_float(WeaponActionAnim.swing(-0.5, 1.0)).is_equal_approx(WeaponActionAnim.swing(0.0, 1.0), 0.0001)
	assert_float(WeaponActionAnim.swing(1.5, 1.0)).is_equal_approx(WeaponActionAnim.swing(1.0, 1.0), 0.0001)


func test_insert_offset_is_zero_when_no_insertion_is_pending() -> void:
	assert_float(WeaponActionAnim.insert_offset(-1.0, 0.03)).is_equal_approx(0.0, 0.0001)


func test_insert_offset_peaks_at_half_of_its_own_fixed_window() -> void:
	var half := WeaponActionAnim.INSERT_FLOURISH_S * 0.5
	assert_float(WeaponActionAnim.insert_offset(half, 0.03)).is_equal_approx(0.03, 0.0001)


func test_insert_offset_window_is_independent_of_cycle_duration() -> void:
	# Le geste d'insertion reste bref (INSERT_FLOURISH_S) même pour une arme
	# dont le rechargement par cartouche est rapide (Verdict, 0.4 s/balle) --
	# `insert_offset` ne prend même pas `reload_round_time` en paramètre.
	assert_float(WeaponActionAnim.INSERT_FLOURISH_S).is_less(0.4)
