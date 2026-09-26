## Au spawn, le joueur regarde le centre de la carte (origine du monde) :
## une équipe ne doit jamais apparaître face à son mur d'enceinte.
extends GdUnitTestSuite


func _forward(yaw: float) -> Vector2:
	# Avant d'un Node3D = -Z tourné de `yaw` autour de Y : (-sin, -cos) en (x, z).
	return Vector2(-sin(yaw), -cos(yaw))


func test_north_spawn_faces_south_towards_center() -> void:
	var f := _forward(PlayerController.yaw_towards_center(Vector3(0, 0, -17.5)))
	assert_float(f.y).is_equal_approx(1.0, 0.001)


func test_south_spawn_faces_north_towards_center() -> void:
	var f := _forward(PlayerController.yaw_towards_center(Vector3(0, 0, 17.5)))
	assert_float(f.y).is_equal_approx(-1.0, 0.001)


func test_corner_spawn_points_at_the_origin() -> void:
	var pos := Vector3(-10, 0, -17.5)
	var f := _forward(PlayerController.yaw_towards_center(pos))
	var to_center := Vector2(-pos.x, -pos.z).normalized()
	assert_float(f.dot(to_center)).is_equal_approx(1.0, 0.001)


func test_center_spawn_has_no_defined_direction() -> void:
	assert_float(PlayerController.yaw_towards_center(Vector3(0, 1.5, 0))).is_equal(0.0)
