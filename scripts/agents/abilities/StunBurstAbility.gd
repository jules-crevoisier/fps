## StunBurstAbility — ULTIME de Choc ("Déferlante") : projectile qui étourdit
## INSTANTANÉMENT tous les ennemis dans un rayon autour du point d'impact (à la
## différence de StunTrapAbility, pas besoin de marcher dessus). Point
## d'impact et cibles calculés côté SERVEUR (raycast + TargetSelect, logique
## pure testée), stun envoyé directement à chaque victime
## (AbilityController.net_apply_stun).
extends Ability

@export var throw_range: float = 16.0
@export var burst_radius: float = 5.5
@export var stun_duration: float = 1.8

func _init() -> void:
	slot = "X"
	display_name = "Déferlante"
	description = "Projectile qui étourdit instantanément tous les ennemis dans un rayon autour du point d'impact."
	is_ultimate = true
	ult_cost = 8

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
	var my_team := int(player.get("team"))
	var candidates: Array = []
	for child in players_root.get_children():
		if child == player:
			continue
		var other := child as CharacterBody3D
		if other == null:
			continue
		var ohp := other.get_node_or_null("Health") as Health
		if ohp and ohp.is_dead:
			continue
		candidates.append({"id": str(other.name).to_int(), "pos": other.global_position, "team": int(other.get("team")), "node": other})
	var hit_list := TargetSelect.within_radius(burst_pos, TargetSelect.enemies_of(candidates, my_team), burst_radius)
	for h in hit_list:
		var victim: CharacterBody3D = h.node
		var victim_ctrl := victim.get_node_or_null("Abilities")
		if victim_ctrl and victim_ctrl.has_method("net_apply_stun"):
			if victim.is_multiplayer_authority():
				victim_ctrl.net_apply_stun(stun_duration)  # hôte ou bot : appel direct
			else:
				victim_ctrl.net_apply_stun.rpc_id(h.id, stun_duration)
