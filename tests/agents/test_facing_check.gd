## test_facing_check.gd
## Spec (contract-r2.md, R-B3 acceptance #2): Éblouissement (flash) — le serveur
## vérifie que la victime fait face au point d'impact via le yaw de son corps
## (contre-jeu : tourner le dos protège). Logique pure de cône de vue, indépendante
## de la scène (yaw en radians, convention du reste du code : 0 = -Z, cf. DashAbility).
extends GdUnitTestSuite


func test_target_directly_in_front_is_facing() -> void:
	assert_bool(FacingCheck.is_facing(Vector3.ZERO, 0.0, Vector3(0, 0, -5), 100.0)).is_true()


func test_target_directly_behind_is_not_facing() -> void:
	assert_bool(FacingCheck.is_facing(Vector3.ZERO, 0.0, Vector3(0, 0, 5), 100.0)).is_false()


func test_target_outside_fov_cone_is_not_facing() -> void:
	# A 90 degres sur le cote, hors d'un FOV de 100 degres (demi-cone 50 degres).
	assert_bool(FacingCheck.is_facing(Vector3.ZERO, 0.0, Vector3(5, 0, 0), 100.0)).is_false()


func test_target_inside_fov_cone_is_facing() -> void:
	assert_bool(FacingCheck.is_facing(Vector3.ZERO, 0.0, Vector3(1, 0, -3), 100.0)).is_true()


func test_facing_check_ignores_height_difference() -> void:
	assert_bool(FacingCheck.is_facing(Vector3.ZERO, 0.0, Vector3(0, 5, -5), 100.0)).is_true()


func test_rotated_viewer_yaw_is_respected() -> void:
	# Le joueur regarde vers +X (yaw = -PI/2) ; la cible est devant lui sur +X.
	assert_bool(FacingCheck.is_facing(Vector3.ZERO, -PI / 2.0, Vector3(5, 0, 0), 100.0)).is_true()
	assert_bool(FacingCheck.is_facing(Vector3.ZERO, -PI / 2.0, Vector3(-5, 0, 0), 100.0)).is_false()


func test_target_on_top_of_viewer_counts_as_facing() -> void:
	assert_bool(FacingCheck.is_facing(Vector3(2, 0, 3), 1.2, Vector3(2, 4, 3), 100.0)).is_true()
