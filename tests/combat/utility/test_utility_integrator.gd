## test_utility_integrator.gd
## Spec (contrat lead, tâche "utilitaires") : intégrateur PUR et déterministe
## — un pas de gravité, un rebond (restitution ~0.35 + frottement) contre la
## géométrie du monde, arrêt sous un seuil de vitesse. Couvre vol libre,
## rebond et mise au repos — même patron de salle physique minimale que
## tests/ai/test_bot_spots.gd (StaticBody3D réels, `await get_tree().
## physics_frame` avant toute requête).
extends GdUnitTestSuite

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 100.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


func _floor_room(offset: Vector3, floor_y: float = 0.0) -> Node3D:
	var root_node := Node3D.new()
	root_node.name = "UtilityIntegratorTestRoom"
	root_node.position = offset
	add_child(root_node)

	var body := StaticBody3D.new()
	body.position = Vector3(0.0, floor_y - 0.5, 0.0)
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20.0, 1.0, 20.0)
	col.shape = shape
	body.add_child(col)
	root_node.add_child(body)
	return root_node


func _teardown(root_node: Node3D) -> void:
	remove_child(root_node)
	root_node.free()
	await get_tree().physics_frame


func _frag_cfg() -> UtilityConfig:
	return UtilityDatabase.get_by_id(UtilityDatabase.FRAG)


# ---------------------------------------------------------------- Vol libre

func test_integrate_free_falls_under_gravity_and_keeps_horizontal_speed() -> void:
	var res := UtilityIntegrator.integrate_free(Vector3.ZERO, Vector3(5.0, 0.0, 0.0), 1.0)
	assert_float(res["velocity"].y).is_equal_approx(-UtilityIntegrator.GRAVITY, 0.001)
	assert_float(res["velocity"].x).is_equal_approx(5.0, 0.001)
	# position intègre la vitesse APRÈS le pas de gravité (semi-implicite).
	assert_float(res["position"].y).is_equal_approx(-UtilityIntegrator.GRAVITY, 0.001)
	assert_float(res["position"].x).is_equal_approx(5.0, 0.001)


func test_step_without_space_is_free_flight_never_at_rest() -> void:
	var cfg := _frag_cfg()
	var res := UtilityIntegrator.step(Vector3.ZERO, Vector3(1.0, 5.0, 0.0), 0.1, cfg)
	assert_bool(res["bounced"]).is_false()
	assert_bool(res["at_rest"]).is_false()


# ---------------------------------------------------------------- Rebond (formule pure)

func test_straight_drop_bounces_straight_up_scaled_by_restitution() -> void:
	var vel := Vector3(0.0, -10.0, 0.0)
	var out := UtilityIntegrator.reflect_with_restitution_and_friction(vel, Vector3.UP, 0.35, 0.0)
	assert_float(out.y).is_equal_approx(3.5, 0.001)
	assert_float(out.x).is_equal_approx(0.0, 0.001)
	assert_float(out.z).is_equal_approx(0.0, 0.001)


func test_friction_reduces_only_the_tangential_component() -> void:
	var vel := Vector3(10.0, -1.0, 0.0)
	var out := UtilityIntegrator.reflect_with_restitution_and_friction(vel, Vector3.UP, 0.35, 0.4)
	# normale : -(-1)*0.35 = 0.35
	assert_float(out.y).is_equal_approx(0.35, 0.001)
	# tangentielle : 10 * (1 - 0.4) = 6.0
	assert_float(out.x).is_equal_approx(6.0, 0.001)


func test_zero_restitution_absorbs_all_normal_speed() -> void:
	var out := UtilityIntegrator.reflect_with_restitution_and_friction(Vector3(0.0, -8.0, 0.0), Vector3.UP, 0.0, 0.0)
	assert_float(out.y).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------- Rebond contre le monde réel

func test_step_bounces_off_real_floor_and_reverses_vertical_velocity() -> void:
	var offset := _offset()
	var room := _floor_room(offset, 0.0)
	for i in 3:
		await get_tree().physics_frame
	var space := room.get_world_3d().direct_space_state
	var cfg := _frag_cfg()

	var start := offset + Vector3(0.0, 0.05, 0.0)
	var res := UtilityIntegrator.step(start, Vector3(0.0, -6.0, 0.0), 0.05, cfg, space, [])

	assert_bool(res["bounced"]).append_failure_message(
		"un pas qui traverse le sol réel (StaticBody3D, calque WORLD) doit rebondir"
	).is_true()
	assert_float(res["velocity"].y).append_failure_message(
		"la composante verticale doit s'inverser (rebond), pas continuer vers le bas"
	).is_greater(0.0)

	await _teardown(room)


func test_step_settles_to_rest_when_bounce_speed_drops_below_threshold() -> void:
	var offset := _offset()
	var room := _floor_room(offset, 0.0)
	for i in 3:
		await get_tree().physics_frame
	var space := room.get_world_3d().direct_space_state
	var cfg := _frag_cfg()

	# Vitesse d'impact choisie pour que le rebond résultant (restitution 0.35)
	# tombe SOUS rest_speed (0.4) : 0.998 m/s d'impact -> 0.35 m/s après rebond.
	var start := offset + Vector3(0.0, 0.001, 0.0)
	var res := UtilityIntegrator.step(start, Vector3(0.0, -0.9, 0.0), 0.01, cfg, space, [])

	assert_bool(res["at_rest"]).append_failure_message(
		"une vitesse de rebond résultante sous rest_speed doit marquer l'objet immobile"
	).is_true()
	assert_that(res["velocity"]).is_equal(Vector3.ZERO)

	await _teardown(room)


func test_simulate_path_ends_at_rest_within_max_time_for_a_dropped_grenade() -> void:
	var offset := _offset()
	var room := _floor_room(offset, 0.0)
	for i in 3:
		await get_tree().physics_frame
	var space := room.get_world_3d().direct_space_state
	var cfg := _frag_cfg()

	var start := offset + Vector3(0.0, 2.0, 0.0)
	var path: Array = UtilityIntegrator.simulate_path(start, Vector3(2.0, 0.0, 0.0), cfg, space, [], 4.0)

	assert_array(path).append_failure_message(
		"simulate_path doit toujours renvoyer au moins la position de départ"
	).is_not_empty()
	var last: Vector3 = path[path.size() - 1]
	assert_float(last.y).append_failure_message(
		"une grenade lâchée au-dessus d'un sol doit finir posée dessus (rebonds amortis), pas en l'air"
	).is_less(start.y)

	await _teardown(room)
