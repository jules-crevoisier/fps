## test_frag_math.gd
## Spec (contrat lead) : 130 dégâts au centre, chute linéaire à 0 à 6.5 m,
## uniquement avec ligne de vue, auto-dégât oui, dégâts aux coéquipiers non.
extends GdUnitTestSuite


func _cfg() -> UtilityConfig:
	return UtilityDatabase.get_by_id(UtilityDatabase.FRAG)


func test_full_damage_at_center() -> void:
	assert_float(FragMath.damage_at(0.0, _cfg())).is_equal_approx(130.0, 0.01)


func test_zero_damage_at_and_beyond_radius() -> void:
	assert_float(FragMath.damage_at(6.5, _cfg())).is_equal_approx(0.0, 0.01)
	assert_float(FragMath.damage_at(50.0, _cfg())).is_equal_approx(0.0, 0.01)


func test_linear_falloff_at_half_radius() -> void:
	assert_float(FragMath.damage_at(3.25, _cfg())).is_equal_approx(65.0, 0.01)


func test_should_damage_self_even_if_flagged_same_team() -> void:
	assert_bool(FragMath.should_damage(true, true)).is_true()


func test_should_damage_enemy() -> void:
	assert_bool(FragMath.should_damage(false, false)).is_true()


func test_should_not_damage_teammate() -> void:
	assert_bool(FragMath.should_damage(false, true)).is_false()


func test_damage_for_target_is_zero_without_line_of_sight() -> void:
	var dmg := FragMath.damage_for_target(1.0, _cfg(), false, false, false)
	assert_float(dmg).is_equal_approx(0.0, 0.01)


func test_damage_for_target_is_zero_for_teammate_even_with_los() -> void:
	var dmg := FragMath.damage_for_target(1.0, _cfg(), false, true, true)
	assert_float(dmg).is_equal_approx(0.0, 0.01)


func test_damage_for_target_applies_falloff_for_enemy_with_los() -> void:
	var dmg := FragMath.damage_for_target(0.0, _cfg(), false, false, true)
	assert_float(dmg).is_equal_approx(130.0, 0.01)


func test_damage_for_target_applies_to_self_at_close_range() -> void:
	var dmg := FragMath.damage_for_target(0.0, _cfg(), true, true, true)
	assert_float(dmg).is_equal_approx(130.0, 0.01)
