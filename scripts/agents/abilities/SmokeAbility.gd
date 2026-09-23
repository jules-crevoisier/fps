## SmokeAbility — sphère de fumée opaque ("encre", contour dur : bloque
## réellement la vue et les tirs, pas un brouillard translucide). Position
## calculée côté SERVEUR via un raycast le long d'`aim_dir` validé ; objet
## répliqué à tous (AbilityController.cast_smoke), durée <= 12 s (contrat).
extends Ability

@export var throw_range: float = 16.0
@export var smoke_radius: float = 3.2
@export var duration: float = 10.0
@export var color: Color = Color(0.85, 0.83, 0.78)

func _init() -> void:
	slot = "Q"
	display_name = "Fumée"
	description = "Sphère de fumée opaque qui bloque la vue et les tirs à distance."
	cooldown = 20.0
	charges = 1

func activate_server(player: PlayerController, aim_dir: Vector3) -> void:
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null or not ctrl.has_method("cast_smoke"):
		return
	var origin: Vector3 = player.head.global_position
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + aim_dir * throw_range)
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	var pos: Vector3 = hit.position if not hit.is_empty() else origin + aim_dir * throw_range
	pos.y = maxf(pos.y, player.global_position.y)  # ne s'enfonce pas sous les pieds/le sol.
	ctrl.cast_smoke(pos, smoke_radius, duration, color)
