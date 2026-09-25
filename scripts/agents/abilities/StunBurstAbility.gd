## StunBurstAbility — ULTIME de Choc ("Déferlante") : projectile qui étourdit
## INSTANTANÉMENT tous les ennemis dans un rayon autour du point d'impact (à la
## différence de StunTrapAbility, pas besoin de marcher dessus). Point
## d'impact et cibles calculés côté SERVEUR (raycast + TargetSelect, logique
## pure testée), stun envoyé directement à chaque victime
## (AbilityController.net_apply_stun).
##
## Armement (docs/research/10_ammo_kits_input.md §3.3, fiche Choc, ligne X) :
## un "coup de cloche" audible/visible de `arm_delay` s précède la RÉSOLUTION
## (recherche du point d'impact ET des cibles) -- contre-jeu explicite ("se
## disperser au son"). Si la résolution était instantanée avec seulement un
## VFX retardé, bouger pendant l'armement ne servirait à rien : c'est bien la
## recherche de cibles elle-même qui attend `arm_delay` avant de lire la vue
## serveur, laissant aux ennemis la fenêtre pour sortir du rayon.
extends Ability

@export var throw_range: float = 16.0
@export var burst_radius: float = 5.5
## Étourdissement des victimes (docs §3.3 : réduit de 1,8 à 1,5 s).
@export var stun_duration: float = 1.5
## Délai avant résolution (docs §3.3 : "armement de 0,4 s").
@export var arm_delay: float = 0.4

func _init() -> void:
	slot = "X"
	display_name = "Déferlante"
	description = "Coup de cloche puis étourdit instantanément tous les ennemis dans un rayon autour du point d'impact."
	is_ultimate = true
	ult_cost = 8

## Coroutine (GDScript autorise l'appel sans `await` côté appelant --
## AbilityController._server_activate ne fait qu'invoquer `ab.activate_server`
## sans attendre son retour, comme pour toute autre capacité) : reprend après
## `arm_delay` via `await create_timer(...).timeout`, JAMAIS un
## `connect(lambda capturant player)` -- voir CLAUDE.md, règle des minuteries.
func activate_server(player: PlayerController, aim_dir: Vector3) -> void:
	if arm_delay > 0.0:
		await player.get_tree().create_timer(arm_delay).timeout
		# `Ability` hérite de `Resource` (pas de propriété `multiplayer` bare,
		# contrairement à un Node) -- on passe par celle du joueur, comme
		# `is_multiplayer_authority()` ailleurs dans ce même fichier.
		if not is_instance_valid(player) or not player.multiplayer.is_server():
			return
		var hp := player.get_node_or_null("Health") as Health
		if hp and hp.is_dead:
			return  # Choc mort pendant l'armement : la Déferlante n'a plus de porteur.

	var space := player.get_world_3d().direct_space_state
	var origin: Vector3 = player.head.global_position
	var hit := trajectory_hit(space, origin, aim_dir, throw_range, [player.get_rid()])
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

## Rayon de trajectoire (point d'impact du projectile le long d'aim_dir) :
## masque PhysicsLayers.SHOT_MASK — la fumée (calque VISION) bloque la vue,
## pas les projectiles ; une Déferlante lancée à travers une fumée continue
## sa course (docs/audit/bugs.md BUG-06). Statique et exposé pour être
## testable directement (tests/agents/test_ability_rays.gd).
static func trajectory_hit(space: PhysicsDirectSpaceState3D, origin: Vector3, aim_dir: Vector3, range: float, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + aim_dir * range, PhysicsLayers.SHOT_MASK)
	q.exclude = exclude
	q.collide_with_areas = false
	return space.intersect_ray(q)
