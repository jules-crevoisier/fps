## test_smoke_blocks_bot_los.gd
## Spec (contrat lead, tâche "utilitaires") : le fumigène doit bloquer la
## ligne de vue des bots (BotPerception.has_los_to_any_point) sans bloquer les
## balles ni le déplacement des joueurs. PhysicsLayers.VISION existe déjà
## dans ce projet pour EXACTEMENT ce rôle (voir sa docstring : "objets qui
## bloquent la vue sans bloquer les corps ni les balles (fumées)") et
## `has_los_to_any_point` interroge déjà le masque PAR DÉFAUT (tous calques) —
## AUCUNE modification de BotBrain.gd/BotPerception.gd n'a donc été
## nécessaire pour cette tâche ; ce fichier le prouve avec un collider réel
## (StaticBody3D, calque VISION) plutôt que de faire confiance à la lecture du
## code seule.
##
## Géométrie : le viewer et la cible sont placés STRICTEMENT en dehors de la
## sphère de fumée (jamais dedans) — un rayon dont l'origine démarre À
## L'INTÉRIEUR d'un solide ne rapporte aucun impact par défaut
## (PhysicsRayQueryParameters3D.hit_from_inside = false), ce qui donnerait un
## faux "visible" ne mesurant rien du tout.
extends GdUnitTestSuite

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 100.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


func _teardown(root_node: Node3D) -> void:
	remove_child(root_node)
	root_node.free()
	await get_tree().physics_frame


func _spawn_smoke_blocker(parent: Node3D, center: Vector3, radius: float) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = PhysicsLayers.VISION
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)


## Centre du nuage et cible, choisis pour que NI le viewer (z=0) NI la cible
## (z=-14) ne se retrouvent à l'intérieur de la sphère (rayon 4.5, centre
## z=-7 -> distance 7 m des deux côtés, hors du volume) — seul le SEGMENT
## entre les deux la traverse.
const _CLOUD_CENTER := Vector3(0, 1.0, -7.0)
const _CLOUD_RADIUS := 4.5
const _TARGET_OFFSET := Vector3(0, 1.0, -14.0)


func test_smoke_layer_blocks_bot_line_of_sight() -> void:
	var offset := _offset()
	var root_node := Node3D.new()
	root_node.position = offset
	add_child(root_node)
	_spawn_smoke_blocker(root_node, _CLOUD_CENTER, _CLOUD_RADIUS)
	for i in 5:
		await get_tree().physics_frame
	var space := root_node.get_world_3d().direct_space_state

	var from := offset + Vector3(0, 1.0, 0)
	var target_dummy := Node3D.new()
	root_node.add_child(target_dummy)
	target_dummy.global_position = offset + _TARGET_OFFSET
	var points: Array = BotPerception.los_points(target_dummy.global_position, target_dummy.global_position, 1.8)

	var visible := BotPerception.has_los_to_any_point(space, from, points, RID(), target_dummy)
	assert_bool(visible).append_failure_message(
		"un nuage de fumée (calque VISION) doit masquer un ennemi derrière lui, exactement comme un mur"
	).is_false()

	await _teardown(root_node)


func test_smoke_layer_does_not_block_bullets() -> void:
	var offset := _offset()
	var root_node := Node3D.new()
	root_node.position = offset
	add_child(root_node)
	_spawn_smoke_blocker(root_node, _CLOUD_CENTER, _CLOUD_RADIUS)
	for i in 5:
		await get_tree().physics_frame
	var space := root_node.get_world_3d().direct_space_state

	var from := offset + Vector3(0, 1.0, 0)
	var to := offset + _TARGET_OFFSET
	var q := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.SHOT_MASK)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)

	assert_bool(hit.is_empty()).append_failure_message(
		"un tir (PhysicsLayers.SHOT_MASK) doit traverser la fumée sans obstacle"
	).is_true()

	await _teardown(root_node)


func test_without_smoke_the_same_target_is_visible() -> void:
	var offset := _offset()
	var root_node := Node3D.new()
	root_node.position = offset
	add_child(root_node)
	for i in 5:
		await get_tree().physics_frame
	var space := root_node.get_world_3d().direct_space_state

	var from := offset + Vector3(0, 1.0, 0)
	var target_dummy := Node3D.new()
	root_node.add_child(target_dummy)
	target_dummy.global_position = offset + _TARGET_OFFSET
	var points: Array = BotPerception.los_points(target_dummy.global_position, target_dummy.global_position, 1.8)

	var visible := BotPerception.has_los_to_any_point(space, from, points, RID(), target_dummy)
	assert_bool(visible).append_failure_message(
		"précondition du test : sans fumée, rien ne doit masquer la cible"
	).is_true()

	await _teardown(root_node)
