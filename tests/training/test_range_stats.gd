## test_range_stats.gd
## Spec (contract-r4a.md, R4-TRAIN #3) : compteur PUR touches/headshots/DPS
## glissant du stand de tir. Aucune scène/arme réelle nécessaire.
extends GdUnitTestSuite

var _stats: RangeStats


func before_test() -> void:
	_stats = RangeStats.new()


func test_starts_empty() -> void:
	assert_int(_stats.shots_hit).is_equal(0)
	assert_int(_stats.headshots).is_equal(0)
	assert_float(_stats.total_damage).is_equal(0.0)
	assert_float(_stats.headshot_ratio()).is_equal(0.0)


func test_record_hit_increments_counters() -> void:
	_stats.record_hit(25.0, false, 0.0)
	assert_int(_stats.shots_hit).is_equal(1)
	assert_int(_stats.headshots).is_equal(0)
	assert_float(_stats.total_damage).is_equal(25.0)


func test_record_headshot_increments_both() -> void:
	_stats.record_hit(50.0, true, 0.0)
	assert_int(_stats.shots_hit).is_equal(1)
	assert_int(_stats.headshots).is_equal(1)


func test_headshot_ratio() -> void:
	_stats.record_hit(10.0, true, 0.0)
	_stats.record_hit(10.0, true, 0.1)
	_stats.record_hit(10.0, false, 0.2)
	_stats.record_hit(10.0, false, 0.3)
	assert_float(_stats.headshot_ratio()).is_equal_approx(0.5, 0.001)


func test_ratio_of_zero_total() -> void:
	assert_float(RangeStats.ratio_of(0, 0)).is_equal(0.0)


func test_dps_sums_damage_in_window() -> void:
	_stats.record_hit(30.0, false, 1.0)
	_stats.record_hit(30.0, false, 2.0)
	# fenêtre de 5 s à t=3 : les deux tirs comptent (60 dégâts / 5 s).
	assert_float(_stats.dps(3.0, 5.0)).is_equal_approx(12.0, 0.001)


func test_dps_ignores_events_outside_window() -> void:
	_stats.record_hit(100.0, false, 0.0)
	_stats.record_hit(20.0, false, 9.0)
	# à t=10, fenêtre de 2 s : seul le tir à t=9 compte (20 / 2 = 10 dps).
	assert_float(_stats.dps(10.0, 2.0)).is_equal_approx(10.0, 0.001)


func test_dps_zero_with_no_events() -> void:
	assert_float(_stats.dps(5.0, 5.0)).is_equal(0.0)


func test_reset_clears_everything() -> void:
	_stats.record_hit(10.0, true, 0.0)
	_stats.reset()
	assert_int(_stats.shots_hit).is_equal(0)
	assert_int(_stats.headshots).is_equal(0)
	assert_float(_stats.total_damage).is_equal(0.0)
	assert_float(_stats.dps(1.0, 5.0)).is_equal(0.0)
