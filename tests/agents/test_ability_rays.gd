## test_ability_rays.gd
## Spec (docs/audit/bugs.md BUG-06) : la fumée bloque la VUE (calque physique
## PhysicsLayers.VISION), jamais les balles ni les capacités. Tous les rayons
## de TRAJECTOIRE (point d'impact d'une grenade/marqueur le long d'`aim_dir`)
## et de POSE (objet posé au sol : tremplin, piège) doivent utiliser
## PhysicsLayers.SHOT_MASK (ignore VISION) ; les rayons de POSE doivent en
## plus n'accepter QUE le décor (exclure TOUS les joueurs, pas seulement le
## lanceur — sinon un piège/tremplin peut atterrir sur une tête).
##
## Scènes physiques minimales et réelles (StaticBody3D/CharacterBody3D
## ajoutés à l'arbre, synchronisés via `await get_tree().physics_frame`),
## comme tests/maps/test_navmesh.gd `_assert_all_spawn_pairs_blocked`. Chaque
## test reçoit un offset XZ dédié pour ne jamais partager d'espace physique
## avec un autre test.
extends GdUnitTestSuite

## Aucune de ces classes n'a de `class_name` global (voir FlashAbility.gd
## etc. : `extends Ability` seul) -> preload explicite, comme
## tests/maps/test_navmesh.gd (`MapSetupScript`).
const FlashAbilityScript := preload("res://scripts/agents/abilities/FlashAbility.gd")
const SmokeAbilityScript := preload("res://scripts/agents/abilities/SmokeAbility.gd")
const StunBurstAbilityScript := preload("res://scripts/agents/abilities/StunBurstAbility.gd")
const StunTrapAbilityScript := preload("res://scripts/agents/abilities/StunTrapAbility.gd")
const RevealAbilityScript := preload("res://scripts/agents/abilities/RevealAbility.gd")
const JumpPadAbilityScript := preload("res://scripts/agents/abilities/JumpPadAbility.gd")

const RANGE := 10.0

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Corps de DÉCOR opaque (mur/sol) : calque PhysicsLayers.WORLD, inclus dans
## SHOT_MASK — doit toujours bloquer un rayon physique.
func _decor_body(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = pos
	add_child(body)
	auto_free(body)
	return body


## Reproduit EXACTEMENT le corps de collision posé par
## AbilityController.cast_smoke (StaticBody3D, calque VISION, masque 0) :
## bloque la vue, jamais les balles ni les capacités (SHOT_MASK l'exclut).
func _smoke_body(pos: Vector3, radius: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.VISION
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	col.shape = shape
	body.add_child(col)
	body.position = pos
	add_child(body)
	auto_free(body)
	return body


## Corps de JOUEUR : calque par défaut de Godot (bit 0 = PhysicsLayers.WORLD),
## comme un vrai PlayerController — aucune scène du projet ne redéfinit
## collision_layer (voir scenes/player/player.tscn).
func _player_body(pos: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	col.shape = shape
	body.add_child(col)
	body.position = pos
	add_child(body)
	auto_free(body)
	return body


# ------------------------------------------------------- rayons de trajectoire

func test_flash_ray_passes_through_smoke_and_reaches_aim_point() -> void:
	# Critère d'acceptation explicite (BUG-06) : "un flash lancé à travers
	# une fumée atteint le point visé".
	var o := _offset()
	var origin := o + Vector3(0, 1.6, 0)
	var aim_dir := Vector3(0, 0, -1)
	_smoke_body(origin + aim_dir * 4.0, 2.5)  # couvre toute la largeur du trajet
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var hit := FlashAbilityScript.trajectory_hit(space, origin, aim_dir, RANGE, [])
	assert_bool(hit.is_empty()).append_failure_message(
		"le rayon d'éblouissement s'est arrêté sur la fumée au lieu d'atteindre le point visé : %s" % hit
	).is_true()


func test_flash_ray_still_stops_on_real_decor() -> void:
	# Non-régression : SHOT_MASK ignore la VISION mais pas le décor réel —
	# sinon le test précédent passerait même si le masque n'excluait rien.
	var o := _offset()
	var origin := o + Vector3(0, 1.6, 0)
	var aim_dir := Vector3(0, 0, -1)
	_decor_body(origin + aim_dir * 5.0, Vector3(4, 4, 0.5))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var hit := FlashAbilityScript.trajectory_hit(space, origin, aim_dir, RANGE, [])
	assert_bool(hit.is_empty()).append_failure_message("le rayon aurait dû toucher le mur de décor").is_false()
	assert_float(hit.position.distance_to(origin)).is_less(5.1)


func test_smoke_ray_passes_through_an_existing_smoke() -> void:
	var o := _offset()
	var origin := o + Vector3(0, 1.6, 0)
	var aim_dir := Vector3(0, 0, -1)
	_smoke_body(origin + aim_dir * 4.0, 2.5)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var hit := SmokeAbilityScript.trajectory_hit(space, origin, aim_dir, RANGE, [])
	assert_bool(hit.is_empty()).append_failure_message(
		"une fumée lancée à travers une fumée déjà posée explose sur sa surface : %s" % hit
	).is_true()


func test_stun_burst_ray_passes_through_smoke() -> void:
	var o := _offset()
	var origin := o + Vector3(0, 1.6, 0)
	var aim_dir := Vector3(0, 0, -1)
	_smoke_body(origin + aim_dir * 4.0, 2.5)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var hit := StunBurstAbilityScript.trajectory_hit(space, origin, aim_dir, RANGE, [])
	assert_bool(hit.is_empty()).append_failure_message(
		"la Déferlante s'est arrêtée sur la fumée au lieu d'atteindre le point visé : %s" % hit
	).is_true()


func test_reveal_ray_passes_through_smoke() -> void:
	var o := _offset()
	var origin := o + Vector3(0, 1.6, 0)
	var aim_dir := Vector3(0, 0, -1)
	_smoke_body(origin + aim_dir * 4.0, 2.5)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var hit := RevealAbilityScript.trajectory_hit(space, origin, aim_dir, RANGE, [])
	assert_bool(hit.is_empty()).append_failure_message(
		"le marqueur Œil s'est arrêté sur la fumée au lieu d'atteindre le point visé : %s" % hit
	).is_true()


# ------------------------------------------------------------- rayons de pose

func test_jump_pad_ground_ray_ignores_smoke_and_reaches_the_floor() -> void:
	var o := _offset()
	var above := o + Vector3(0, 5.0, 0)
	_decor_body(o + Vector3(0, -0.5, 0), Vector3(10, 1, 10))  # dessus du sol à y=0
	_smoke_body(o + Vector3(0, 2.0, 0), 2.5)  # entre `above` et le sol
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var hit := JumpPadAbilityScript.ground_hit(space, above, above + Vector3(0, -6.0, 0), [])
	assert_bool(hit.is_empty()).append_failure_message("le tremplin ne touche rien : devrait traverser la fumée").is_false()
	assert_float(hit.position.y).append_failure_message(
		"le tremplin s'est posé sur la fumée (y=%.2f) au lieu du sol (y=0)" % hit.position.y
	).is_equal_approx(o.y, 0.05)


func test_jump_pad_ground_ray_excludes_all_players() -> void:
	var o := _offset()
	var above := o + Vector3(0, 5.0, 0)
	_decor_body(o + Vector3(0, -0.5, 0), Vector3(10, 1, 10))  # sol réel à y=0
	var victim := _player_body(o + Vector3(0, 1.0, 0))  # joueur debout entre `above` et le sol
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state

	# Sans exclusion : le rayon touche bien le joueur (prouve que le test est
	# significatif — un faux positif serait possible si la géométrie ratait le joueur).
	var hit_unfiltered := JumpPadAbilityScript.ground_hit(space, above, above + Vector3(0, -6.0, 0), [])
	assert_object(hit_unfiltered.get("collider")).append_failure_message("le rayon aurait dû toucher le joueur").is_same(victim)

	# Comportement réel de JumpPadAbility (tous les joueurs exclus) : le
	# rayon traverse le joueur et atteint le décor sous ses pieds.
	var hit := JumpPadAbilityScript.ground_hit(space, above, above + Vector3(0, -6.0, 0), [victim.get_rid()])
	assert_bool(hit.is_empty()).append_failure_message("le tremplin ne touche plus rien sous le joueur").is_false()
	assert_object(hit.collider).append_failure_message("le tremplin a atterri sur la tête du joueur").is_not_same(victim)
	assert_float(hit.position.y).is_equal_approx(o.y, 0.05)


func test_stun_trap_ground_ray_ignores_smoke_and_reaches_the_floor() -> void:
	var o := _offset()
	var above := o + Vector3(0, 5.0, 0)
	_decor_body(o + Vector3(0, -0.5, 0), Vector3(10, 1, 10))
	_smoke_body(o + Vector3(0, 2.0, 0), 2.5)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var hit := StunTrapAbilityScript.ground_hit(space, above, above + Vector3(0, -6.0, 0), [])
	assert_bool(hit.is_empty()).append_failure_message("le piège ne touche rien : devrait traverser la fumée").is_false()
	assert_float(hit.position.y).append_failure_message(
		"le piège s'est posé sur la fumée (y=%.2f) au lieu du sol (y=0)" % hit.position.y
	).is_equal_approx(o.y, 0.05)


func test_stun_trap_ground_ray_excludes_all_players() -> void:
	var o := _offset()
	var above := o + Vector3(0, 5.0, 0)
	_decor_body(o + Vector3(0, -0.5, 0), Vector3(10, 1, 10))
	var victim := _player_body(o + Vector3(0, 1.0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().find_world_3d().direct_space_state
	var hit_unfiltered := StunTrapAbilityScript.ground_hit(space, above, above + Vector3(0, -6.0, 0), [])
	assert_object(hit_unfiltered.get("collider")).append_failure_message("le rayon aurait dû toucher le joueur").is_same(victim)

	var hit := StunTrapAbilityScript.ground_hit(space, above, above + Vector3(0, -6.0, 0), [victim.get_rid()])
	assert_bool(hit.is_empty()).append_failure_message("le piège ne touche plus rien sous le joueur").is_false()
	assert_object(hit.collider).append_failure_message("le piège a atterri sur la tête du joueur").is_not_same(victim)
	assert_float(hit.position.y).is_equal_approx(o.y, 0.05)
