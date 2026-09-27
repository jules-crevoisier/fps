## test_smoke_math.gd
## Spec (demande utilisateur 2026-09-27, remplace l'amorce en vol de 1.4 s) : le fumigène tombe
## par gravité et se déploie au PREMIER CONTACT AVEC LE SOL (armé après 0.25 s), jamais en plein
## vol ; `fuse_time` (6 s) n'est qu'un filet de sécurité s'il ne retrouve jamais le sol.
## Nuage 0->4.5m sur 1s, tenue 12s, fondu 1.5s.
extends GdUnitTestSuite

const SmokeCloud := preload("res://scripts/combat/utility/SmokeCloud.gd")


func _cfg() -> UtilityConfig:
	return UtilityDatabase.get_by_id(UtilityDatabase.SMOKE)


func test_never_detonates_in_the_air_on_a_long_throw() -> void:
	assert_bool(SmokeMath.should_detonate(1.4, false, _cfg())).is_false()
	assert_bool(SmokeMath.should_detonate(3.0, false, _cfg())).is_false()


func test_detonates_on_first_floor_contact_once_armed() -> void:
	assert_bool(SmokeMath.should_detonate(0.25, true, _cfg())).is_true()
	assert_bool(SmokeMath.should_detonate(0.1, true, _cfg())).append_failure_message(
		"le fumigène ne doit pas détoner avant le délai d'armement (0.25 s, lâché dans les pieds)"
	).is_false()


func test_safety_fuse_if_it_never_finds_the_floor() -> void:
	assert_bool(SmokeMath.should_detonate(6.0, false, _cfg())).is_true()


func test_cloud_settles_down_from_above_then_rests() -> void:
	assert_float(SmokeCloud.settle_offset(0.0, 1.6)).is_equal_approx(1.0, 0.001)
	assert_float(SmokeCloud.settle_offset(0.8, 1.6)).is_between(0.0, 1.0)
	assert_float(SmokeCloud.settle_offset(1.6, 1.6)).is_equal_approx(0.0, 0.001)


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
