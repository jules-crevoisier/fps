## test_audio_occlusion.gd
## Spec (tâche "son", 2026-09-27, point 3 "occlusion") : décision PURE
## d'occlusion depuis un résultat de raycast déjà résolu par l'appelant
## (`PhysicsDirectSpaceState3D.intersect_ray`, {} = rien touché), puis
## assombrissement du filtre + atténuation supplémentaire (dB) quand occlus.
## Aucune dépendance à l'arbre de scène ni à la physique réelle.
extends GdUnitTestSuite


func test_is_occluded_from_hit_false_when_ray_clear() -> void:
	assert_bool(AudioOcclusion.is_occluded_from_hit({})).is_false()


func test_is_occluded_from_hit_true_when_something_hit() -> void:
	assert_bool(AudioOcclusion.is_occluded_from_hit({"position": Vector3.ZERO, "normal": Vector3.UP})).is_true()


func test_occluded_cutoff_hz_lowers_when_occluded() -> void:
	assert_float(AudioOcclusion.occluded_cutoff_hz(true, 5000.0)).is_equal_approx(1200.0, 0.001)


func test_occluded_cutoff_hz_keeps_open_value_when_not_occluded() -> void:
	assert_float(AudioOcclusion.occluded_cutoff_hz(false, 5000.0)).is_equal_approx(5000.0, 0.001)


func test_occluded_cutoff_hz_custom_closed_value() -> void:
	assert_float(AudioOcclusion.occluded_cutoff_hz(true, 8000.0, 900.0)).is_equal_approx(900.0, 0.001)


func test_occluded_volume_offset_db_is_negative_when_occluded() -> void:
	assert_float(AudioOcclusion.occluded_volume_offset_db(true)).is_equal_approx(-5.0, 0.001)


func test_occluded_volume_offset_db_is_zero_when_clear() -> void:
	assert_float(AudioOcclusion.occluded_volume_offset_db(false)).is_equal_approx(0.0, 0.001)


func test_occluded_volume_offset_db_custom_amount() -> void:
	assert_float(AudioOcclusion.occluded_volume_offset_db(true, -6.0)).is_equal_approx(-6.0, 0.001)
