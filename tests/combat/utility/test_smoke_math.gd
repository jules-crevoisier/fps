## test_smoke_math.gd
## Spec (contrat lead) : détonation à 1.4s après relâchement OU au contact du
## sol après 0.8s (le premier des deux) ; nuage 0->4.5m sur 1s, tenue 12s,
## fondu 1.5s.
extends GdUnitTestSuite


func _cfg() -> UtilityConfig:
	return UtilityDatabase.get_by_id(UtilityDatabase.SMOKE)


func test_detonates_at_full_fuse_time_in_the_air() -> void:
	assert_bool(SmokeMath.should_detonate(1.4, false, _cfg())).is_true()
	assert_bool(SmokeMath.should_detonate(1.39, false, _cfg())).is_false()


func test_detonates_early_on_ground_contact_after_arm_delay() -> void:
	assert_bool(SmokeMath.should_detonate(0.8, true, _cfg())).is_true()
	assert_bool(SmokeMath.should_detonate(0.5, true, _cfg())).append_failure_message(
		"le fumigène ne doit pas détoner au sol avant le délai d'armement (0.8 s)"
	).is_false()


func test_does_not_detonate_early_while_still_airborne() -> void:
	assert_bool(SmokeMath.should_detonate(0.9, false, _cfg())).is_false()


func test_cloud_radius_zero_before_detonation() -> void:
	assert_float(SmokeMath.cloud_radius(-0.1, _cfg())).is_equal_approx(0.0, 0.001)


func test_cloud_radius_grows_linearly_to_full_size() -> void:
	assert_float(SmokeMath.cloud_radius(0.0, _cfg())).is_equal_approx(0.0, 0.001)
	assert_float(SmokeMath.cloud_radius(0.5, _cfg())).is_equal_approx(2.25, 0.01)
	assert_float(SmokeMath.cloud_radius(1.0, _cfg())).is_equal_approx(4.5, 0.01)


func test_cloud_radius_holds_full_size_during_hold_window() -> void:
	assert_float(SmokeMath.cloud_radius(7.0, _cfg())).is_equal_approx(4.5, 0.01)
	assert_float(SmokeMath.cloud_radius(13.0, _cfg())).is_equal_approx(4.5, 0.01)


func test_cloud_radius_fades_out_after_hold_window() -> void:
	# grow(1) + hold(12) = 13 ; fade dure 1.5s -> mi-fondu à 13.75.
	assert_float(SmokeMath.cloud_radius(13.75, _cfg())).is_equal_approx(2.25, 0.05)
	assert_float(SmokeMath.cloud_radius(14.5, _cfg())).is_equal_approx(0.0, 0.01)
	assert_float(SmokeMath.cloud_radius(20.0, _cfg())).is_equal_approx(0.0, 0.01)


func test_cloud_alpha_tracks_radius_fraction() -> void:
	assert_float(SmokeMath.cloud_alpha(0.5, _cfg())).is_equal_approx(0.5, 0.01)
	assert_float(SmokeMath.cloud_alpha(7.0, _cfg())).is_equal_approx(1.0, 0.01)
	assert_float(SmokeMath.cloud_alpha(20.0, _cfg())).is_equal_approx(0.0, 0.01)


func test_total_lifetime_sums_all_three_phases() -> void:
	assert_float(SmokeMath.total_lifetime(_cfg())).is_equal_approx(14.5, 0.01)
