## SmokeAbility — sphère de fumée opaque ("encre", contour dur : bloque
## réellement la VUE, pas un brouillard translucide) mais ne bloque NI les
## tirs NI les corps — calque physique PhysicsLayers.VISION, exclu de
## PhysicsLayers.SHOT_MASK (norme des shooters tactiques de référence : on la
## traverse et on tire au travers, docs/audit/bugs.md BUG-06). Position
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
	description = "Sphère de fumée opaque qui bloque la vue à distance (on la traverse et on tire au travers)."
	cooldown = 20.0
	charges = 1

func activate_server(player: PlayerController, aim_dir: Vector3) -> void:
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null or not ctrl.has_method("cast_smoke"):
		return
	var origin: Vector3 = player.head.global_position
	var space := player.get_world_3d().direct_space_state
	var hit := trajectory_hit(space, origin, aim_dir, throw_range, [player.get_rid()])
	var pos: Vector3 = hit.position if not hit.is_empty() else origin + aim_dir * throw_range
	pos.y = maxf(pos.y, player.global_position.y)  # ne s'enfonce pas sous les pieds/le sol.
	ctrl.cast_smoke(pos, smoke_radius, duration, color)

## Rayon de trajectoire (point d'atterrissage de la fumée le long d'aim_dir) :
## masque PhysicsLayers.SHOT_MASK — une fumée lancée à travers une fumée déjà
## posée continue sa course au lieu d'exploser sur sa surface (docs/audit/
## bugs.md BUG-06). Statique et exposé pour être testable directement
## (tests/agents/test_ability_rays.gd).
static func trajectory_hit(space: PhysicsDirectSpaceState3D, origin: Vector3, aim_dir: Vector3, range: float, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + aim_dir * range, PhysicsLayers.SHOT_MASK)
	q.exclude = exclude
	q.collide_with_areas = false
	return space.intersect_ray(q)
