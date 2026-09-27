## test_flash_blocked_by_smoke.gd
## Spec (demande utilisateur 2026-09-27) : une flash ne traverse pas un fumigène.
## - joueur derrière la fumée, flash de l'autre côté -> pas ébloui ;
## - flash qui éclate DANS la fumée -> n'éblouit personne ;
## - sans fumée sur le segment -> la flash passe (le test ne mesure pas du vide).
## Collider réel (StaticBody3D, calque VISION, comme SmokeCloud côté serveur).
extends GdUnitTestSuite

const _CLOUD_CENTER := Vector3(0, 1.0, -7.0)
const _CLOUD_RADIUS := 4.5

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 100.0, 0.0, 300.0)
	_next_offset_index += 1
	return o


func _world_with_smoke(offset: Vector3) -> Node3D:
	var root_node := Node3D.new()
	root_node.position = offset
	add_child(root_node)
	var body := StaticBody3D.new()
	body.position = _CLOUD_CENTER
	body.collision_layer = PhysicsLayers.VISION
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = _CLOUD_RADIUS
	col.shape = shape
	body.add_child(col)
	root_node.add_child(body)
	return root_node


func _teardown(root_node: Node3D) -> void:
	remove_child(root_node)
	root_node.free()
	await get_tree().physics_frame


func test_smoke_between_flash_and_player_blocks_it() -> void:
	var offset := _offset()
	var root_node := _world_with_smoke(offset)
	for i in 5:
		await get_tree().physics_frame
	var space := root_node.get_world_3d().direct_space_state
	var flash_pos := offset + Vector3(0, 1.0, -14.0)
	var player_eye := offset + Vector3(0, 1.6, 0.0)
	assert_bool(UtilityThrower.smoke_between(space, flash_pos, player_eye)).append_failure_message(
		"joueur derrière la fumée, flash de l'autre côté : la fumée doit couper la flash"
	).is_true()
	await _teardown(root_node)


func test_flash_bursting_inside_smoke_blinds_nobody() -> void:
	var offset := _offset()
	var root_node := _world_with_smoke(offset)
	for i in 5:
		await get_tree().physics_frame
	var space := root_node.get_world_3d().direct_space_state
	var flash_inside := offset + _CLOUD_CENTER
	var player_eye := offset + Vector3(8.0, 1.6, -7.0)
	assert_bool(UtilityThrower.smoke_between(space, flash_inside, player_eye)).append_failure_message(
		"une flash qui éclate DANS la fumée ne doit éblouir personne (rayon parti de l'intérieur)"
	).is_true()
	await _teardown(root_node)


func test_no_smoke_on_the_segment_lets_the_flash_through() -> void:
	var offset := _offset()
	var root_node := _world_with_smoke(offset)
	for i in 5:
		await get_tree().physics_frame
	var space := root_node.get_world_3d().direct_space_state
	var flash_pos := offset + Vector3(12.0, 1.0, 0.0)
	var player_eye := offset + Vector3(0, 1.6, 0.0)
	assert_bool(UtilityThrower.smoke_between(space, flash_pos, player_eye)).append_failure_message(
		"sans fumée entre les deux, la flash doit passer"
	).is_false()
	await _teardown(root_node)
