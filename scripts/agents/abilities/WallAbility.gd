## WallAbility — érige un mur temporaire devant le joueur (bloque tirs & passage).
## Répliqué : le mur est spawné sur TOUS les pairs (visible/bloquant pour tous).
extends Ability

func _init() -> void:
	slot = "E"
	display_name = "Mur"
	cooldown = 16.0
	charges = 1

func activate(player: PlayerController) -> void:
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null or not ctrl.has_method("cast_barrier"):
		return
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var pos := player.global_position + fwd * 3.0 + Vector3(0, 1.3, 0)
	ctrl.cast_barrier(pos, fwd, Vector3(4.0, 2.6, 0.4), 8.0, Color(0.25, 0.55, 1.0))
