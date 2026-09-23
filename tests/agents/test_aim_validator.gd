## test_aim_validator.gd
## Spec (contract-r2.md, AbilityController): request_activate(i, aim_dir) — le
## serveur valide aim_dir (fini, normalisé) avant tout calcul de cible, comme
## ShotValidator le fait pour les tirs (contract-p0.md).
extends GdUnitTestSuite


func test_normalized_vector_is_valid() -> void:
	assert_bool(AimValidator.is_valid(Vector3(0, 0, -1))).is_true()
	assert_bool(AimValidator.is_valid(Vector3(1, 0, 0).normalized())).is_true()


func test_zero_vector_is_invalid() -> void:
	assert_bool(AimValidator.is_valid(Vector3.ZERO)).is_false()


func test_non_normalized_vector_is_invalid() -> void:
	assert_bool(AimValidator.is_valid(Vector3(2, 0, 0))).is_false()
	assert_bool(AimValidator.is_valid(Vector3(0.1, 0, 0))).is_false()


func test_nan_or_infinite_components_are_invalid() -> void:
	assert_bool(AimValidator.is_valid(Vector3(NAN, 0, -1))).is_false()
	assert_bool(AimValidator.is_valid(Vector3(INF, 0, -1))).is_false()


func test_diagonal_normalized_vector_is_valid() -> void:
	var d := Vector3(1, 1, 1).normalized()
	assert_bool(AimValidator.is_valid(d)).is_true()
