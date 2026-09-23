## test_weapon_feel.gd
## Spec (contract-r3.md, R3-IN#4) : sensation d'arme pure — motif de recul
## fixe puis aléatoire, dispersion additionnelle mouvement/l'air, délai avant
## de pouvoir tirer après sprint/slide/dive, progression ADS. Fichier NOUVEAU
## dédié à ces ajouts : ne modifie aucun test existant (test_weapon_math.gd,
## test_inventory.gd... restent intacts).
extends GdUnitTestSuite


func _cfg() -> WeaponConfig:
	var c := WeaponConfig.new()
	c.recoil_pattern = PackedVector2Array([Vector2(0.0, 0.5), Vector2(0.1, 0.6), Vector2(-0.1, 0.55)])
	c.pattern_shots = 3
	c.recoil_horizontal = 0.35
	c.recoil_vertical = 0.55
	c.move_spread_add = 1.5
	c.air_spread_add = 3.0
	c.spread_hip = 2.0
	c.spread_aim = 0.3
	c.sprint_to_fire = 0.15
	c.slide_to_fire = 0.38
	c.dive_to_fire = 0.46
	c.ads_time = 0.2
	return c


func test_recoil_follows_fixed_pattern_within_pattern_shots() -> void:
	var c := _cfg()
	var kick := WeaponFeel.recoil_for_shot(c, 1)
	assert_float(kick.x).is_equal_approx(0.1, 0.0001)
	assert_float(kick.y).is_equal_approx(0.6, 0.0001)


func test_recoil_falls_back_to_random_beyond_pattern_shots() -> void:
	var c := _cfg()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var kick := WeaponFeel.recoil_for_shot(c, 10, rng)
	assert_bool(absf(kick.x) <= c.recoil_horizontal + 0.0001).is_true()
	assert_float(kick.y).is_equal_approx(c.recoil_vertical, 0.0001)


func test_recoil_first_shot_uses_pattern_index_zero() -> void:
	var c := _cfg()
	var kick := WeaponFeel.recoil_for_shot(c, 0)
	assert_float(kick.x).is_equal_approx(0.0, 0.0001)
	assert_float(kick.y).is_equal_approx(0.5, 0.0001)


func test_total_spread_adds_move_and_air() -> void:
	var c := _cfg()
	var grounded_still := WeaponFeel.total_spread_deg(c.spread_hip, c, false, false)
	var moving := WeaponFeel.total_spread_deg(c.spread_hip, c, true, false)
	var airborne := WeaponFeel.total_spread_deg(c.spread_hip, c, false, true)
	var both := WeaponFeel.total_spread_deg(c.spread_hip, c, true, true)
	assert_float(grounded_still).is_equal_approx(2.0, 0.001)
	assert_float(moving).is_equal_approx(3.5, 0.001)
	assert_float(airborne).is_equal_approx(5.0, 0.001)
	assert_float(both).is_equal_approx(6.5, 0.001)


func test_fire_delay_blocks_right_after_sprint() -> void:
	var c := _cfg()
	assert_float(WeaponFeel.fire_delay_left(c, 0.0, INF, INF)).is_equal_approx(0.15, 0.001)


func test_fire_delay_clears_after_enough_time() -> void:
	var c := _cfg()
	assert_float(WeaponFeel.fire_delay_left(c, 1.0, INF, INF)).is_equal_approx(0.0, 0.001)


func test_fire_delay_takes_the_longest_pending_penalty() -> void:
	var c := _cfg()
	# 0.1 s après un slide (délai 0.38 s -> reste 0.28) et 0.4 s après un dive
	# (délai 0.46 s -> reste 0.06) : le slide domine.
	var left := WeaponFeel.fire_delay_left(c, INF, 0.1, 0.4)
	assert_float(left).is_equal_approx(0.28, 0.001)


func test_ads_progress_moves_toward_aim_over_ads_time() -> void:
	var c := _cfg()
	var t := WeaponFeel.ads_progress(0.0, true, c.ads_time, c.ads_time)
	assert_float(t).is_equal_approx(1.0, 0.001)


func test_ads_progress_returns_toward_hip_when_not_aiming() -> void:
	var c := _cfg()
	var t := WeaponFeel.ads_progress(1.0, false, c.ads_time, c.ads_time)
	assert_float(t).is_equal_approx(0.0, 0.001)


func test_ads_progress_partial_step_is_proportional() -> void:
	var c := _cfg()
	var t := WeaponFeel.ads_progress(0.0, true, c.ads_time * 0.5, c.ads_time)
	assert_float(t).is_equal_approx(0.5, 0.001)
