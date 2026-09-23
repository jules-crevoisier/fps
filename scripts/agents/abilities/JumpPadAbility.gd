## JumpPadAbility — pose un tremplin au sol qui propulse vers le haut quiconque
## marche dessus. Position calculée côté SERVEUR (raycast au sol le long
## d'`aim_dir` validé, borné à `throw_range`) ; objet répliqué à tous
## (AbilityController.cast_jump_pad). La poussée n'est appliquée QUE par la
## machine du joueur concerné (mouvement local-autoritaire, cf. contract-p0.md).
extends Ability

@export var throw_range: float = 6.0
@export var duration: float = 14.0
@export var boost: float = 11.0

func _init() -> void:
	slot = "E"
	display_name = "Tremplin"
	description = "Pose un tremplin au sol qui propulse vers le haut."
	cooldown = 18.0
	charges = 1

func activate_server(player: PlayerController, aim_dir: Vector3) -> void:
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null or not ctrl.has_method("cast_jump_pad"):
		return
	var flat := Vector3(aim_dir.x, 0.0, aim_dir.z)
	if flat.length() < 0.01:
		flat = -player.global_transform.basis.z
	flat = flat.normalized()
	var above := player.global_position + flat * throw_range + Vector3(0, 1.0, 0)
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(above, above + Vector3(0, -4.0, 0))
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	var pos: Vector3 = hit.position if not hit.is_empty() else player.global_position + flat * throw_range
	ctrl.cast_jump_pad(pos, duration, boost)
