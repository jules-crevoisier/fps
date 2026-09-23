## test_shot_validator.gd
## Spec (contract-p0.md, ShotValidator): origin finite and within
## ORIGIN_TOLERANCE (3.0 m) of head_pos; dirs.size() == max(1, expected_pellets);
## each dir a finite Vector3 of length in [0.99, 1.01].
extends GdUnitTestSuite


func test_valid_shot_returns_true() -> void:
	var head := Vector3(0.0, 1.8, 0.0)
	var dirs: Array = [Vector3(0.0, 0.0, -1.0)]
	assert_bool(ShotValidator.is_valid(head, head, dirs, 1)).is_true()


func test_origin_too_far_from_head_returns_false() -> void:
	var head := Vector3.ZERO
	var far_origin := head + Vector3(5.0, 0.0, 0.0)
	var dirs: Array = [Vector3(0.0, 0.0, -1.0)]
	assert_bool(ShotValidator.is_valid(far_origin, head, dirs, 1)).is_false()


func test_origin_within_tolerance_returns_true() -> void:
	var head := Vector3.ZERO
	var origin := head + Vector3(ShotValidator.ORIGIN_TOLERANCE, 0.0, 0.0)
	var dirs: Array = [Vector3(0.0, 0.0, -1.0)]
	assert_bool(ShotValidator.is_valid(origin, head, dirs, 1)).is_true()


func test_nan_origin_returns_false() -> void:
	var head := Vector3.ZERO
	var dirs: Array = [Vector3(0.0, 0.0, -1.0)]
	assert_bool(ShotValidator.is_valid(Vector3(NAN, 0.0, 0.0), head, dirs, 1)).is_false()


func test_inf_origin_returns_false() -> void:
	var head := Vector3.ZERO
	var dirs: Array = [Vector3(0.0, 0.0, -1.0)]
	assert_bool(ShotValidator.is_valid(Vector3(INF, 0.0, 0.0), head, dirs, 1)).is_false()


func test_wrong_dir_count_returns_false() -> void:
	var head := Vector3.ZERO
	var two_dirs: Array = [Vector3(0.0, 0.0, -1.0), Vector3(1.0, 0.0, 0.0)]
	assert_bool(ShotValidator.is_valid(head, head, two_dirs, 1)).is_false()

	var one_dir: Array = [Vector3(0.0, 0.0, -1.0)]
	assert_bool(ShotValidator.is_valid(head, head, one_dir, 8)).is_false()


func test_non_normalized_dir_returns_false() -> void:
	var head := Vector3.ZERO
	var too_long: Array = [Vector3(2.0, 0.0, 0.0)]
	assert_bool(ShotValidator.is_valid(head, head, too_long, 1)).is_false()

	var too_short: Array = [Vector3(0.5, 0.0, 0.0)]
	assert_bool(ShotValidator.is_valid(head, head, too_short, 1)).is_false()


func test_non_vector3_element_returns_false() -> void:
	var head := Vector3.ZERO
	var bad: Array = [Vector3(0.0, 0.0, -1.0), "not a vector"]
	assert_bool(ShotValidator.is_valid(head, head, bad, 2)).is_false()


func test_shotgun_pellet_count_matches_dirs_size() -> void:
	var head := Vector3.ZERO
	var dirs: Array = []
	for i in range(8):
		dirs.append(Vector3(0.0, 0.0, -1.0))
	assert_bool(ShotValidator.is_valid(head, head, dirs, 8)).is_true()
