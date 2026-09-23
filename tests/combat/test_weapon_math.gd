## test_weapon_math.gd
## Spec (contract-p0.md, "Pure classes" / WeaponMath): damage falloff curve,
## headshot boundary, per-shot damage (headshot + pellets), shots-to-kill and
## time-to-kill. All configs below are built explicitly so every expected
## number is exact (no dependency on the .tres catalog values).
extends GdUnitTestSuite


func _cfg() -> WeaponConfig:
	var c := WeaponConfig.new()
	c.damage = 40.0
	c.damage_min = 10.0
	c.falloff_start = 10.0
	c.falloff_end = 30.0
	c.headshot_mult = 2.0
	c.fire_rate = 10.0
	c.pellets = 1
	return c


func test_damage_at_before_falloff_start_is_full_damage() -> void:
	var c := _cfg()
	assert_float(WeaponMath.damage_at(0.0, c)).is_equal_approx(40.0, 0.001)
	assert_float(WeaponMath.damage_at(10.0, c)).is_equal_approx(40.0, 0.001)


func test_damage_at_midpoint_is_linear_interpolation() -> void:
	var c := _cfg()
	# t = (20-10)/(30-10) = 0.5 -> 40 + (10-40) * 0.5 = 25.0
	assert_float(WeaponMath.damage_at(20.0, c)).is_equal_approx(25.0, 0.001)


func test_damage_at_after_falloff_end_is_damage_min() -> void:
	var c := _cfg()
	assert_float(WeaponMath.damage_at(30.0, c)).is_equal_approx(10.0, 0.001)
	assert_float(WeaponMath.damage_at(60.0, c)).is_equal_approx(10.0, 0.001)


func test_is_headshot_boundary_at_exact_head_height_is_false() -> void:
	# hit_y > body_origin_y + HEAD_HEIGHT (strictly greater) -> boundary is false.
	assert_bool(WeaponMath.is_headshot(1.4, 0.0)).is_false()
	assert_bool(WeaponMath.is_headshot(1.399, 0.0)).is_false()


func test_is_headshot_just_above_head_height_is_true() -> void:
	assert_bool(WeaponMath.is_headshot(1.401, 0.0)).is_true()


func test_shot_damage_applies_headshot_multiplier() -> void:
	var c := _cfg()
	assert_float(WeaponMath.shot_damage(c, 0.0, false)).is_equal_approx(40.0, 0.001)
	assert_float(WeaponMath.shot_damage(c, 0.0, true)).is_equal_approx(80.0, 0.001)


func test_shot_damage_multiplies_by_pellet_count() -> void:
	var c := _cfg()
	c.pellets = 8
	# all pellets hit, no headshot: 40 * 8
	assert_float(WeaponMath.shot_damage(c, 0.0, false)).is_equal_approx(320.0, 0.001)
	# headshot + pellets combine: 40 * 2.0 * 8
	assert_float(WeaponMath.shot_damage(c, 0.0, true)).is_equal_approx(640.0, 0.001)


func test_shots_to_kill_rounds_up() -> void:
	var c := _cfg()
	# shot_damage(dist=0, no headshot) = 40 -> hp 100 / 40 = 2.5 -> ceil = 3
	assert_int(WeaponMath.shots_to_kill(c, 0.0, 100.0, false)).is_equal(3)


func test_shots_to_kill_exact_division_does_not_round_up() -> void:
	var c := _cfg()
	# 80 / 40 = 2.0 exactly -> ceil = 2
	assert_int(WeaponMath.shots_to_kill(c, 0.0, 80.0, false)).is_equal(2)


func test_ttk_ms_for_one_shot_kill_is_zero() -> void:
	var c := _cfg()
	# headshot damage = 80, hp = 50 -> 1 shot to kill -> ttk = (1-1)/rate*1000 = 0
	assert_float(WeaponMath.ttk_ms(c, 0.0, 50.0, true)).is_equal_approx(0.0, 0.001)


func test_ttk_ms_for_multi_shot_kill() -> void:
	var c := _cfg()
	# 3 shots to kill (see test above), fire_rate = 10 -> (3-1)/10*1000 = 200 ms
	assert_float(WeaponMath.ttk_ms(c, 0.0, 100.0, false)).is_equal_approx(200.0, 0.001)
