## test_grenade_audio.gd
## Spec (tâche "son", 2026-09-27, point 5 "grenades") : volume PUR du rebond
## selon la vitesse d'impact, anti-rafale (rebonds trop rapprochés), et
## courbe d'assourdissement (lowpass) du joueur ébloui — pleine coupure
## pendant l'éblouissement, puis retour linéaire à l'ouverture sur
## FlashMath.RECOVERY_S. Aucune dépendance à l'arbre de scène.
extends GdUnitTestSuite


func test_bounce_volume_db_is_quiet_below_min_speed() -> void:
	assert_float(GrenadeAudio.bounce_volume_db(0.2)).is_equal_approx(-18.0, 0.001)


func test_bounce_volume_db_is_full_above_max_speed() -> void:
	assert_float(GrenadeAudio.bounce_volume_db(20.0)).is_equal_approx(0.0, 0.001)


func test_bounce_volume_db_interpolates_between() -> void:
	var mid := GrenadeAudio.bounce_volume_db(5.25)  # milieu de [0.5, 10.0] par défaut.
	assert_float(mid).is_between(-18.0, 0.0)


func test_bounce_volume_db_custom_range() -> void:
	assert_float(GrenadeAudio.bounce_volume_db(1.0, 1.0, 2.0, -10.0, 0.0)).is_equal_approx(-10.0, 0.001)
	assert_float(GrenadeAudio.bounce_volume_db(2.0, 1.0, 2.0, -10.0, 0.0)).is_equal_approx(0.0, 0.001)


func test_can_play_bounce_true_after_minimum_interval() -> void:
	assert_bool(GrenadeAudio.can_play_bounce(0.09)).is_true()
	assert_bool(GrenadeAudio.can_play_bounce(1.0)).is_true()


func test_can_play_bounce_false_within_minimum_interval() -> void:
	assert_bool(GrenadeAudio.can_play_bounce(0.01)).is_false()


func test_can_play_bounce_custom_interval() -> void:
	assert_bool(GrenadeAudio.can_play_bounce(0.2, 0.3)).is_false()
	assert_bool(GrenadeAudio.can_play_bounce(0.31, 0.3)).is_true()


func test_muffle_cutoff_hz_fully_muffled_during_blind() -> void:
	assert_float(GrenadeAudio.muffle_cutoff_hz(0.0, 2.2, 0.6)).is_equal_approx(500.0, 0.001)
	assert_float(GrenadeAudio.muffle_cutoff_hz(2.1, 2.2, 0.6)).is_equal_approx(500.0, 0.001)


func test_muffle_cutoff_hz_sweeps_open_during_recovery() -> void:
	var mid := GrenadeAudio.muffle_cutoff_hz(2.2 + 0.3, 2.2, 0.6)  # milieu du fondu (0.3 / 0.6 s).
	assert_float(mid).is_between(500.0, 20000.0)


func test_muffle_cutoff_hz_fully_open_after_recovery() -> void:
	assert_float(GrenadeAudio.muffle_cutoff_hz(2.2 + 0.6, 2.2, 0.6)).is_equal_approx(20000.0, 0.001)
	assert_float(GrenadeAudio.muffle_cutoff_hz(99.0, 2.2, 0.6)).is_equal_approx(20000.0, 0.001)


func test_muffle_cutoff_hz_zero_blind_duration_is_open() -> void:
	assert_float(GrenadeAudio.muffle_cutoff_hz(0.0, 0.0, 0.6)).is_equal_approx(20000.0, 0.001)
