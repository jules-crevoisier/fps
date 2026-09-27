## test_throw_origin.gd
## Spec (retour utilisateur 2026-09-27) : le lancer part de la main, pas de l'œil
## (sinon l'arc se projette en bâton vertical au-dessus de l'anneau). Ce décalage
## ne doit jamais faire naître la grenade de l'autre côté d'un mur collé au joueur.
extends GdUnitTestSuite


func _world_with_wall(offset: Vector3) -> Node3D:
	var root_node := Node3D.new()
	root_node.position = offset
	add_child(root_node)
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 4.0, 4.0)
	col.shape = box
	body.add_child(col)
	body.position = Vector3(-0.15, 1.5, 0.0)  # paroi à gauche, à 15 cm de la tête
	root_node.add_child(body)
	return root_node


func test_origin_is_unchanged_when_nothing_is_in_the_way() -> void:
	var root_node := Node3D.new()
	root_node.position = Vector3(0, 0, 600)
	add_child(root_node)
	await get_tree().physics_frame
	var space := root_node.get_world_3d().direct_space_state
	var head := root_node.position + Vector3(0, 1.6, 0)
	var wanted := head + Vector3(-0.22, -0.2, -0.5)
	var got := UtilityThrower.clamp_origin_to_world(space, head, wanted, RID())
	assert_vector(got).is_equal_approx(wanted, Vector3.ONE * 0.001)
	remove_child(root_node)
	root_node.free()


func test_origin_stops_in_front_of_a_wall_between_head_and_hand() -> void:
	var offset := Vector3(0, 0, 700)
	var root_node := _world_with_wall(offset)
	for i in 3:
		await get_tree().physics_frame
	var space := root_node.get_world_3d().direct_space_state
	var head := offset + Vector3(0, 1.6, 0)
	var wanted := head + Vector3(-0.4, -0.2, -0.5)  # derrière la paroi
	var got := UtilityThrower.clamp_origin_to_world(space, head, wanted, RID())
	assert_float(got.x - offset.x).append_failure_message(
		"la grenade doit naître du côté du joueur, devant la paroi (x > -0.05)"
	).is_greater(-0.05)
	remove_child(root_node)
	root_node.free()
	await get_tree().physics_frame
