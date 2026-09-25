## FlashAbility — grenade aveuglante. Tout est calculé et validé côté SERVEUR :
## point d'impact par raycast le long d'`aim_dir` (déjà validé par
## AbilityController), puis pour chaque AUTRE joueur vivant dans `radius` : une
## ligne de vue dégagée (raycast) ET le fait de lui faire face (FacingCheck sur
## le yaw du corps, contre-jeu : tourner le dos protège) -> écran blanc côté
## victime uniquement (AbilityController.net_apply_flash), durée <= 1.5 s.
##
## Mèche (docs/research/10_ammo_kits_input.md §3.3, fiche Vif, AGT-03 : "ajouter
## une mèche de 0,3 s et un projectile visible") : le point d'impact
## (`burst_pos`) est fixé au lancer (trajectoire d'un projectile réel, pas
## question qu'il dépende d'une visée plus tardive), mais la RÉSOLUTION des
## victimes (ligne de vue, face à face) attend `fuse_delay` avant de lire leur
## position/orientation COURANTE -- même patron (coroutine reprise après
## `await create_timer(...).timeout`, JAMAIS un `connect(lambda capturant
## player)`, voir CLAUDE.md "règle des minuteries") que
## StunBurstAbility.activate_server (fiche Choc, AGT-04).
extends Ability

@export var throw_range: float = 14.0
@export var radius: float = 9.0
@export var fov_deg: float = 100.0
@export var blind_duration: float = 1.3
## Délai entre le lancer et l'explosion effective (§3.3 : "mèche de 0,3 s").
@export var fuse_delay: float = 0.3

func _init() -> void:
	slot = "Q"
	display_name = "Éblouissement"
	description = "Grenade aveuglante lancée devant elle (mèche de 0,3 s) : les ennemis qui lui font face sont aveuglés (écran blanc, jusqu'à 1,5 s)."
	cooldown = 18.0
	charges = 1

func activate_server(player: PlayerController, aim_dir: Vector3) -> void:
	var origin: Vector3 = player.head.global_position
	var hit := trajectory_hit(player.get_world_3d().direct_space_state, origin, aim_dir, throw_range, [player.get_rid()])
	var burst_pos: Vector3 = hit.position if not hit.is_empty() else origin + aim_dir * throw_range

	if fuse_delay > 0.0:
		await player.get_tree().create_timer(fuse_delay).timeout
		# `Ability` hérite de `Resource` (pas de propriété `multiplayer` bare,
		# contrairement à un Node) -- on passe par celle du joueur, même motif
		# que StunBurstAbility.activate_server.
		if not is_instance_valid(player) or not player.multiplayer.is_server():
			return
		var self_hp := player.get_node_or_null("Health") as Health
		if self_hp and self_hp.is_dead:
			return  # Vif mort pendant la mèche : l'éblouissement n'a plus de porteur.

	# Rayon de VUE récupéré ICI (jamais réutilisé d'avant la mèche) : un
	# `PhysicsDirectSpaceState3D` obtenu avant un `await` peut ne plus être
	# valide plusieurs frames physiques plus tard (même motif que
	# StunBurstAbility.activate_server, qui refait aussi tous ses accès
	# physiques après son propre délai d'armement).
	var space := player.get_world_3d().direct_space_state
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

## Rayon de trajectoire (point d'impact de la grenade le long d'aim_dir) :
## masque PhysicsLayers.SHOT_MASK — la fumée (calque VISION) bloque la vue,
## pas les projectiles ; un éblouissement lancé à travers une fumée continue
## sa course et atteint le point visé (docs/audit/bugs.md BUG-06). Statique
## et exposé pour être testable directement (tests/agents/test_ability_rays.gd).
static func trajectory_hit(space: PhysicsDirectSpaceState3D, origin: Vector3, aim_dir: Vector3, range: float, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + aim_dir * range, PhysicsLayers.SHOT_MASK)
	q.exclude = exclude
	q.collide_with_areas = false
	return space.intersect_ray(q)

## Rayon de VUE (pas de trajectoire) : sert à vérifier que la victime peut
## VOIR l'éclat pour être aveuglée — masque par défaut (PAS SHOT_MASK) donc
## une fumée entre le point d'impact et la victime bloque bien l'aveuglement,
## conformément à « la fumée bloque la vue, pas les balles ».
func _has_line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, victim: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	return hit.is_empty() or hit.collider == victim
