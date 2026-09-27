## test_bullet_whizz.gd
## Spec (tâche "son", 2026-09-27, point 6 "impacts/whizz") : plus courte
## distance PURE entre un point (tête du joueur local) et un segment de tir
## distant (origine -> point d'impact/portée max), puis décision "doit-on
## siffler ?" (le tir passe assez près SANS toucher). Fonctions PURES, aucune
## dépendance physique.
extends GdUnitTestSuite


func test_closest_point_on_segment_projects_onto_middle() -> void:
	var p := BulletWhizz.closest_point_on_segment(Vector3.ZERO, Vector3(10, 0, 0), Vector3(5, 3, 0))
	assert_vector(p).is_equal_approx(Vector3(5, 0, 0), Vector3.ONE * 0.001)


func test_closest_point_on_segment_clamps_before_start() -> void:
	var p := BulletWhizz.closest_point_on_segment(Vector3.ZERO, Vector3(10, 0, 0), Vector3(-5, 2, 0))
	assert_vector(p).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)


func test_closest_point_on_segment_clamps_past_end() -> void:
	var p := BulletWhizz.closest_point_on_segment(Vector3.ZERO, Vector3(10, 0, 0), Vector3(15, 2, 0))
	assert_vector(p).is_equal_approx(Vector3(10, 0, 0), Vector3.ONE * 0.001)


func test_closest_point_on_segment_degenerate_segment_is_the_single_point() -> void:
	var p := BulletWhizz.closest_point_on_segment(Vector3(3, 3, 3), Vector3(3, 3, 3), Vector3(3, 0, 3))
	assert_vector(p).is_equal_approx(Vector3(3, 3, 3), Vector3.ONE * 0.001)


func test_closest_distance_matches_perpendicular_distance() -> void:
	var d := BulletWhizz.closest_distance(Vector3.ZERO, Vector3(10, 0, 0), Vector3(5, 2.0, 0))
	assert_float(d).is_equal_approx(2.0, 0.001)


func test_should_whizz_true_within_radius() -> void:
	assert_bool(BulletWhizz.should_whizz(1.0)).is_true()
	assert_bool(BulletWhizz.should_whizz(2.49)).is_true()


func test_should_whizz_false_beyond_radius() -> void:
	assert_bool(BulletWhizz.should_whizz(2.5)).is_false()
	assert_bool(BulletWhizz.should_whizz(10.0)).is_false()


func test_should_whizz_custom_radius() -> void:
	assert_bool(BulletWhizz.should_whizz(4.0, 5.0)).is_true()
	assert_bool(BulletWhizz.should_whizz(6.0, 5.0)).is_false()
