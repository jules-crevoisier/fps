## test_training_layout.gd
## Spec (contract-r4a.md, R4-TRAIN) : sanité des données PURES du terrain
## (zones rectangulaires utilisées pour l'affichage contextuel des panneaux
## et le filtrage des touches du stand de tir ; vide "dolphin dive" exact).
## Aucun nœud/scène nécessaire — `TrainingLayout` ne produit que des
## dictionnaires/Vector3, comme `Layouts.gd` (tests/maps).
extends GdUnitTestSuite

func test_point_in_zone_inside() -> void:
	var zone := {"min": Vector2(-5, -5), "max": Vector2(5, 5)}
	assert_bool(TrainingLayout.point_in_zone(Vector2(0, 0), zone)).is_true()

func test_point_in_zone_on_edge_is_inside() -> void:
	var zone := {"min": Vector2(-5, -5), "max": Vector2(5, 5)}
	assert_bool(TrainingLayout.point_in_zone(Vector2(5, -5), zone)).is_true()

func test_point_in_zone_outside() -> void:
	var zone := {"min": Vector2(-5, -5), "max": Vector2(5, 5)}
	assert_bool(TrainingLayout.point_in_zone(Vector2(6, 0), zone)).is_false()

func test_course_zone_excludes_shooting_range() -> void:
	var course := TrainingLayout.course_zone()
	var range_center := Vector2(-35, 0)  # milieu du stand de tir
	assert_bool(TrainingLayout.point_in_zone(range_center, course)).is_false()

func test_course_zone_excludes_abilities_corner() -> void:
	var course := TrainingLayout.course_zone()
	var ability_center := Vector2(22, 0)
	assert_bool(TrainingLayout.point_in_zone(ability_center, course)).is_false()

func test_range_zone_excludes_abilities_corner() -> void:
	assert_bool(TrainingLayout.point_in_zone(Vector2(22, 0), TrainingLayout.range_zone())).is_false()

func test_ability_zone_excludes_range() -> void:
	assert_bool(TrainingLayout.point_in_zone(Vector2(-35, 0), TrainingLayout.ability_zone())).is_false()

func test_dive_gap_is_exactly_8_meters() -> void:
	var gap := TrainingLayout.DIVE_GAP_Z_NEAR - TrainingLayout.DIVE_GAP_Z_FAR
	assert_float(absf(gap)).is_equal_approx(8.0, 0.001)

func test_dive_gap_clears_step_rules_threshold() -> void:
	assert_float(absf(TrainingLayout.DIVE_GAP_Z_NEAR - TrainingLayout.DIVE_GAP_Z_FAR)).is_greater(StepRules.DIVE_GAP_MIN)

func test_checkpoints_start_at_zero_and_are_ordered_along_the_course() -> void:
	var cps := TrainingLayout.checkpoints()
	assert_int(cps.size()).is_greater_equal(2)
	assert_str(String(cps[0]["name"])).is_equal("CP0")
	var prev_z: float = (cps[0]["pos"] as Vector3).z
	for i in range(1, cps.size()):
		var z: float = (cps[i]["pos"] as Vector3).z
		assert_float(z).is_less(prev_z)
		prev_z = z

func test_static_dummies_are_in_ascending_distance_order() -> void:
	var dummies := TrainingLayout.static_dummies()
	var prev := -1
	for d in dummies:
		var dist: int = int(d["distance_m"])
		assert_int(dist).is_greater(prev)
		prev = dist
