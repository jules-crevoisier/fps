## test_arc_line.gd
## Spec (retour utilisateur 2026-09-27, "la ligne de courbe de la grenade") :
## l'arc pointillé est remplacé par un ruban CONTINU — ce fichier couvre les
## deux fonctions PURES qui le construisent :
## - `_sub_path_between_distances` : tronque le chemin prédit à 0.6 m après la
##   main et 0.6 m avant l'atterrissage (remplace l'ancien `_sample_dots`) ;
## - `_ribbon_vertices` : sommets gauche/droite du ruban face caméra, largeur
##   qui va de 0.035 m (près) à 0.05 m (loin).
extends GdUnitTestSuite


func _line(length_m: float) -> Array:
	var path: Array = []
	for i in int(length_m) + 1:
		path.append(Vector3(0, 0, -float(i)))
	return path


# ---------------------------------------------------------------- sub-path

func test_sub_path_keeps_the_middle_of_a_long_line() -> void:
	var sub := UtilityThrower._sub_path_between_distances(_line(10.0), 0.6, 0.6)
	assert_int(sub.size()).is_greater(0)
	assert_vector(sub[0]).is_equal_approx(Vector3(0, 0, -0.6), Vector3.ONE * 0.001)
	assert_vector(sub[sub.size() - 1]).is_equal_approx(Vector3(0, 0, -9.4), Vector3.ONE * 0.001)


func test_sub_path_never_includes_a_point_before_the_near_skip() -> void:
	var sub := UtilityThrower._sub_path_between_distances(_line(10.0), 0.6, 0.6)
	for p in sub:
		assert_float(-(p as Vector3).z).is_greater_equal(0.6 - 0.001)


func test_sub_path_never_includes_a_point_within_the_trimmed_end() -> void:
	var sub := UtilityThrower._sub_path_between_distances(_line(10.0), 0.6, 0.6)
	for p in sub:
		assert_float(-(p as Vector3).z).is_less_equal(10.0 - 0.6 + 0.001)


func test_sub_path_is_empty_when_the_throw_is_too_short_to_leave_anything() -> void:
	var sub := UtilityThrower._sub_path_between_distances(_line(1.0), 0.6, 0.6)
	assert_int(sub.size()).is_equal(0)


func test_sub_path_is_empty_for_a_degenerate_single_point_path() -> void:
	var sub := UtilityThrower._sub_path_between_distances([Vector3.ZERO], 0.6, 0.6)
	assert_int(sub.size()).is_equal(0)


# ---------------------------------------------------------------- ribbon

func test_ribbon_has_two_vertices_per_point() -> void:
	var verts := UtilityThrower._ribbon_vertices(_line(4.0), Vector3(0, 5, 0), 0.035, 0.05)
	assert_int(verts.size()).is_equal(5)


func test_ribbon_is_empty_for_fewer_than_two_points() -> void:
	var verts := UtilityThrower._ribbon_vertices([Vector3.ZERO], Vector3(0, 5, 0), 0.035, 0.05)
	assert_int(verts.size()).is_equal(0)


func test_ribbon_width_starts_near_and_grows_far() -> void:
	var verts := UtilityThrower._ribbon_vertices(_line(4.0), Vector3(0, 5, 0), 0.035, 0.05)
	var first: Dictionary = verts[0]
	var last: Dictionary = verts[verts.size() - 1]
	var near_width: float = (first["left"] as Vector3).distance_to(first["right"])
	var far_width: float = (last["left"] as Vector3).distance_to(last["right"])
	assert_float(near_width).append_failure_message(
		"la largeur au bout PRÈS de la main doit être 0.035 m"
	).is_equal_approx(0.035, 0.001)
	assert_float(far_width).append_failure_message(
		"la largeur au bout LOIN doit être 0.05 m"
	).is_equal_approx(0.05, 0.001)


func test_ribbon_side_is_perpendicular_to_the_segment_tangent() -> void:
	# Ligne le long de -Z, caméra au-dessus (+Y) : le côté gauche/droite doit
	# être horizontal (X), jamais vertical -- sinon le ruban se projetterait de
	# nouveau en "bâton" au lieu d'un ruban plat lisible.
	var verts := UtilityThrower._ribbon_vertices(_line(4.0), Vector3(0, 5, 0), 0.035, 0.05)
	var mid: Dictionary = verts[2]
	var left: Vector3 = mid["left"]
	var right: Vector3 = mid["right"]
	assert_float(absf(left.y - right.y)).append_failure_message(
		"gauche/droite doivent être à la MÊME hauteur (côté horizontal), pas un ruban vertical"
	).is_less(0.001)
	assert_float(absf(left.x - right.x)).is_greater(0.001)
