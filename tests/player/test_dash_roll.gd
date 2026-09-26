## Dash (V) dans toutes les directions + roulade fluide (demande 2026-09-26).
extends GdUnitTestSuite

const DiveState := preload("res://scripts/player/states/Dive.gd")


func test_dash_follows_the_movement_keys() -> void:
	var left := Vector3(-1.0, 0.0, 0.0)
	var d: Vector3 = DiveState.dash_direction(left, Vector3(0.0, 0.0, -1.0))
	assert_float(d.x).is_equal_approx(-1.0, 0.0001)
	assert_float(d.z).is_equal_approx(0.0, 0.0001)


func test_dash_without_keys_goes_where_you_look() -> void:
	var d: Vector3 = DiveState.dash_direction(Vector3.ZERO, Vector3(0.0, -0.3, -2.0))
	assert_float(d.y).is_equal_approx(0.0, 0.0001)
	assert_float(d.z).is_equal_approx(-1.0, 0.0001)


func test_local_dash_dir_maps_keys_to_roll_direction() -> void:
	# ZQSD : avant = y négatif dans Input.get_vector ; le sens local a +y = avant.
	assert_vector(DiveState.local_dash_dir(Vector2(0.0, -1.0))).is_equal(Vector2(0.0, 1.0))
	assert_vector(DiveState.local_dash_dir(Vector2(0.0, 1.0))).is_equal(Vector2(0.0, -1.0))
	assert_vector(DiveState.local_dash_dir(Vector2(1.0, 0.0))).is_equal(Vector2(1.0, 0.0))
	assert_vector(DiveState.local_dash_dir(Vector2.ZERO)).is_equal(Vector2(0.0, 1.0))
