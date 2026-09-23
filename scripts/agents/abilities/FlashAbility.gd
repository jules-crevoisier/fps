## FlashAbility — grenade aveuglante. Tout est calculé et validé côté SERVEUR :
## point d'impact par raycast le long d'`aim_dir` (déjà validé par
## AbilityController), puis pour chaque AUTRE joueur vivant dans `radius` : une
## ligne de vue dégagée (raycast) ET le fait de lui faire face (FacingCheck sur
## le yaw du corps, contre-jeu : tourner le dos protège) -> écran blanc côté
## victime uniquement (AbilityController.net_apply_flash), durée <= 1.5 s.
extends Ability

@export var throw_range: float = 14.0
@export var radius: float = 9.0
@export var fov_deg: float = 100.0
@export var blind_duration: float = 1.3

func _init() -> void:
	slot = "Q"
	display_name = "Éblouissement"
	description = "Grenade aveuglante lancée devant elle : les ennemis qui lui font face sont aveuglés (écran blanc, jusqu'à 1,5 s)."
	cooldown = 22.0
	charges = 1

func activate_server(player: PlayerController, aim_dir: Vector3) -> void:
	var space := player.get_world_3d().direct_space_state
	var origin: Vector3 = player.head.global_position
	var q := PhysicsRayQueryParameters3D.create(origin, origin + aim_dir * throw_range)
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	var burst_pos: Vector3 = hit.position if not hit.is_empty() else origin + aim_dir * throw_range

	var players_root := player.get_parent()
	if players_root == null:
		return
	for child in players_root.get_children():
		if child == player:
			continue
		var victim := child as CharacterBody3D
		if victim == null:
			continue
		var vhp := victim.get_node_or_null("Health") as Health
		if vhp and vhp.is_dead:
			continue
		var vhead: Node3D = victim.get_node_or_null("Head")
		var vpos: Vector3 = vhead.global_position if vhead else victim.global_position
		if vpos.distance_to(burst_pos) > radius:
			continue
		if not _has_line_of_sight(space, burst_pos, vpos, victim):
			continue
		if not FacingCheck.is_facing(victim.global_position, victim.rotation.y, burst_pos, fov_deg):
			continue
		var victim_ctrl := victim.get_node_or_null("Abilities")
		if victim_ctrl and victim_ctrl.has_method("net_apply_flash"):
			if victim.is_multiplayer_authority():
				# Victime simulée par le serveur (hôte ou bot) : appel direct,
				# il n'existe pas de pair réseau à qui envoyer le RPC.
				victim_ctrl.net_apply_flash(blind_duration)
			else:
				victim_ctrl.net_apply_flash.rpc_id(str(victim.name).to_int(), blind_duration)

func _has_line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, victim: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	return hit.is_empty() or hit.collider == victim
