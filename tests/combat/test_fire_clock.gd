## test_fire_clock.gd
## Spec (contract-p0.md, FireClock): fractional-remainder shot gate ticked at a
## fixed 60 Hz physics rate. First shot after idle fires immediately; while the
## trigger is held the accumulated shots over 1 s match the configured rate
## within +/-1 shot; releasing the trigger must not bank shots for later.
extends GdUnitTestSuite

const DT := 1.0 / 60.0


func _hold_for_one_second(fc: FireClock) -> int:
	var shots := 0
	for i in range(60):
		shots += fc.tick(DT, true)
	return shots


func test_first_shot_after_idle_fires_immediately() -> void:
	var fc := FireClock.new(10.0)
	assert_int(fc.tick(DT, true)).is_equal(1)


func test_rate_10_per_second_at_60hz_matches_within_one_shot() -> void:
	var fc := FireClock.new(10.0)
	var shots := _hold_for_one_second(fc)
	assert_int(shots).is_between(9, 11)


func test_rate_13_33_per_second_at_60hz_matches_within_one_shot() -> void:
	var fc := FireClock.new(13.33)
	var shots := _hold_for_one_second(fc)
	assert_int(shots).is_between(13, 14)


func test_rate_1_2_per_second_at_60hz_matches_within_one_shot() -> void:
	var fc := FireClock.new(1.2)
	var shots := _hold_for_one_second(fc)
	assert_int(shots).is_between(1, 2)


func test_releasing_trigger_does_not_bank_shots() -> void:
	var fc := FireClock.new(10.0)
	# idle for 2 full seconds with the trigger released
	for i in range(120):
		assert_int(fc.tick(DT, false)).is_equal(0)
	# pulling the trigger now must yield exactly the immediate first shot,
	# not several shots "banked" from the idle time
	assert_int(fc.tick(DT, true)).is_equal(1)
	assert_int(fc.tick(DT, true)).is_equal(0)


func test_reset_makes_the_next_shot_immediate_again() -> void:
	var fc := FireClock.new(10.0)
	assert_int(fc.tick(DT, true)).is_equal(1)
	# mid-interval, no new shot yet
	assert_int(fc.tick(DT, true)).is_equal(0)

	fc.reset()
	assert_int(fc.tick(DT, true)).is_equal(1)


func test_set_rate_changes_subsequent_shot_rate() -> void:
	var fc := FireClock.new(1.0)
	fc.tick(DT, true)  # consume the immediate first shot at the old rate
	fc.set_rate(60.0)
	var shots := _hold_for_one_second(fc)
	assert_int(shots).is_between(59, 61)
