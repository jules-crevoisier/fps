## StunTrapAbility — pose un piège invisible qui étourdit le premier ennemi qui
## marche dessus. Position calculée côté SERVEUR (raycast au sol le long
## d'`aim_dir` validé) ; objet répliqué à tous pour l'affichage
## (AbilityController.cast_stun_trap), mais SEULE la copie serveur détecte le
## contact et envoie transition_to("Stun", ...) au propriétaire de la victime
## (contract-r2.md, R-B3 acceptance #2).
extends Ability

@export var throw_range: float = 6.0
@export var trap_duration: float = 20.0
@export var stun_duration: float = 2.2

func _init() -> void:
	slot = "Q"
	display_name = "Chausse-trape"
	description = "Piège invisible qui étourdit le premier ennemi au contact."
	cooldown = 18.0
	charges = 1

func activate_server(player: PlayerController, aim_dir: Vector3) -> void:
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null or not ctrl.has_method("cast_stun_trap"):
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
	ctrl.cast_stun_trap(pos, int(player.get("team")), trap_duration, stun_duration)
