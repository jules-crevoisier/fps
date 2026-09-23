## test_ability_state.gd
## Spec (contract-p0.md, AbilityState): non-ult charges/cooldown state machine
## and ult points-over-time, keyed by ability slot index. Ability instances are
## built explicitly (Ability.new()) so cooldown/charges/is_ultimate/ult_cost are
## exact and independent of any concrete ability resource.
extends GdUnitTestSuite


func _ability(cooldown: float, charges: int, is_ultimate: bool = false, ult_cost: int = 7) -> Ability:
	var a := Ability.new()
	a.cooldown = cooldown
	a.charges = charges
	a.is_ultimate = is_ultimate
	a.ult_cost = ult_cost
	return a


func test_try_activate_consumes_a_charge() -> void:
	var a := _ability(8.0, 2)
	var state := AbilityState.new([a])
	assert_int(state.charges(0)).is_equal(2)
	assert_bool(state.try_activate(0)).is_true()
	assert_int(state.charges(0)).is_equal(1)


func test_cooldown_starts_only_when_charges_were_full() -> void:
	var a := _ability(5.0, 3)
	var state := AbilityState.new([a])
	assert_float(state.cooldown_left(0)).is_equal_approx(0.0, 0.001)

	# charges were full (3) before this consume -> cooldown must start
	state.try_activate(0)
	assert_float(state.cooldown_left(0)).is_equal_approx(5.0, 0.001)


func test_second_activation_while_not_full_does_not_restart_cooldown() -> void:
	var a := _ability(5.0, 3)
	var state := AbilityState.new([a])
	state.try_activate(0)  # 3 -> 2, cooldown starts at 5.0
	state.tick(2.0)  # cooldown counts down to 3.0
	state.try_activate(0)  # 2 -> 1, charges were NOT full -> cooldown unaffected
	assert_float(state.cooldown_left(0)).is_equal_approx(3.0, 0.001)


func test_regen_one_charge_per_cooldown() -> void:
	var a := _ability(4.0, 1)
	var state := AbilityState.new([a])
	state.try_activate(0)
	assert_int(state.charges(0)).is_equal(0)

	state.tick(4.0)
	assert_int(state.charges(0)).is_equal(1)
	# back to full -> cooldown must not restart
	assert_float(state.cooldown_left(0)).is_equal_approx(0.0, 0.001)


func test_multi_charge_regen_restarts_cooldown_until_full() -> void:
	var a := _ability(2.0, 3)
	var state := AbilityState.new([a])
	state.try_activate(0)  # 3 -> 2, cooldown starts
	state.try_activate(0)  # 2 -> 1, charges were not full, cooldown unaffected

	state.tick(2.0)  # first regen: 1 -> 2, still below max -> cooldown restarts
	assert_int(state.charges(0)).is_equal(2)
	assert_float(state.cooldown_left(0)).is_equal_approx(2.0, 0.001)

	state.tick(2.0)  # second regen: 2 -> 3 (full) -> cooldown stops
	assert_int(state.charges(0)).is_equal(3)
	assert_float(state.cooldown_left(0)).is_equal_approx(0.0, 0.001)


func test_can_activate_false_and_try_activate_false_when_no_charge() -> void:
	var a := _ability(8.0, 1)
	var state := AbilityState.new([a])
	state.try_activate(0)
	assert_bool(state.can_activate(0)).is_false()
	assert_bool(state.try_activate(0)).is_false()
	assert_int(state.charges(0)).is_equal(0)


func test_ult_charges_over_time_and_caps_at_cost() -> void:
	var ult := _ability(0.0, 1, true, 7)
	var state := AbilityState.new([ult])
	state.ult_charge_rate = 0.45

	state.tick(10.0)
	assert_float(state.ult_points()).is_equal_approx(4.5, 0.001)

	state.tick(10.0)  # would be 9.0, capped at ult_cost = 7
	assert_float(state.ult_points()).is_equal_approx(7.0, 0.001)


func test_try_activate_ult_requires_full_points_and_resets_on_use() -> void:
	var ult := _ability(0.0, 1, true, 7)
	var state := AbilityState.new([ult])

	assert_bool(state.can_activate(0)).is_false()
	assert_bool(state.try_activate(0)).is_false()

	state.add_ult(7.0)
	assert_bool(state.can_activate(0)).is_true()
	assert_bool(state.try_activate(0)).is_true()
	assert_float(state.ult_points()).is_equal_approx(0.0, 0.001)


func test_add_ult_caps_at_ult_cost() -> void:
	var ult := _ability(0.0, 1, true, 7)
	var state := AbilityState.new([ult])
	state.add_ult(3.0)
	assert_float(state.ult_points()).is_equal_approx(3.0, 0.001)
	state.add_ult(100.0)
	assert_float(state.ult_points()).is_equal_approx(7.0, 0.001)


func test_can_activate_and_try_activate_false_for_bad_index() -> void:
	var a := _ability(8.0, 1)
	var state := AbilityState.new([a])
	assert_bool(state.can_activate(5)).is_false()
	assert_bool(state.try_activate(-1)).is_false()


func test_to_dict_apply_dict_round_trip() -> void:
	var a := _ability(5.0, 3)
	var ult := _ability(0.0, 1, true, 7)
	var state := AbilityState.new([a, ult])
	state.try_activate(0)  # 3 -> 2, cooldown starts at 5.0
	state.tick(2.0)  # cooldown -> 3.0
	state.add_ult(4.0)

	var d := state.to_dict()
	var restored := AbilityState.new([_ability(5.0, 3), _ability(0.0, 1, true, 7)])
	restored.apply_dict(d)

	assert_int(restored.charges(0)).is_equal(state.charges(0))
	assert_float(restored.cooldown_left(0)).is_equal_approx(state.cooldown_left(0), 0.001)
	assert_float(restored.ult_points()).is_equal_approx(state.ult_points(), 0.001)
