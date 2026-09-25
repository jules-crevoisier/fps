## BellChargeAbility — SIGNATURE (E) de Choc, "Tape-la-cloche"
## (docs/research/10_ammo_kits_input.md §3.3, fiche Choc, fusionne l'ancienne
## Charge du C) : charge d'épaule dans l'axe de visée à plat. Le MOUVEMENT est
## client-autoritaire et prédit (`activate_local`, même patron que
## DashAbility -- "pas de côté" : la trajectoire ne suit que l'axe figé au
## moment de l'activation, jamais `wish_dir`).
##
## Le CONTACT est calculé côté SERVEUR (`activate_server`) le long du
## trajectoire :
##  - le premier ennemi capté dans le couloir de charge (rayon `capture_radius`
##    autour du segment) reçoit `hit_damage` PV, une repoussée de
##    `knockback_distance` m dans l'axe de la charge (AbilityController.
##    net_apply_impulse) et un étourdissement de `victim_stun_duration` s
##    (net_apply_stun) ;
##  - à défaut d'ennemi, un mur (décor réel, joueurs exclus -- `wall_hit`)
##    rencontré avant la fin de la charge étourdit CHOC lui-même
##    `self_stun_duration` s ("il fonce dans le mur").
## Les deux résolutions sont EXCLUSIVES : un ennemi touché avant le mur
## absorbe le choc, jamais les deux à la fois.
extends Ability

## Vitesse horizontale imprimée (m/s) -- 20 m/s * 0,5 s ≈ 10 m (docs §3.3).
@export var force: float = 20.0
## Petit décollement vertical (franchit les petits obstacles, comme DashAbility).
@export var hop: float = 1.5
## Portée totale de la charge (m).
@export var charge_distance: float = 10.0
## Rayon du couloir de capture autour du segment de charge (marge de largeur
## de joueur -- le rayon d'un raycast unique serait trop strict).
@export var capture_radius: float = 1.2
## Dégâts au premier ennemi touché (docs §3.3 : "15 dégâts").
@export var hit_damage: float = 15.0
## Repoussée dans l'axe de la charge, en m (docs §3.3 : "repoussée de 3 m").
@export var knockback_distance: float = 3.0
## Étourdissement de la VICTIME touchée (docs §3.3 : "étourdie 0,5 s").
@export var victim_stun_duration: float = 0.5
## AUTO-étourdissement de Choc s'il percute un mur sans toucher d'ennemi
## (docs §3.3 : "Contre un mur, Choc s'étourdit lui-même 0,5 s").
@export var self_stun_duration: float = 0.5

func _init() -> void:
	slot = "E"
	display_name = "Tape-la-cloche"
	description = "Charge d'épaule : étourdit et repousse le premier ennemi touché ; auto-étourdissement contre un mur."
	cooldown = 14.0
	charges = 1

## Prédit et exécuté côté PROPRIÉTAIRE (pur mouvement, comme DashAbility) :
## direction figée sur l'axe du corps à l'instant de l'activation, jamais
## `wish_dir` (docs §3.3, contre-jeu : "pas de côté").
func activate_local(player: PlayerController) -> void:
	var dir := _flat_dir(player, -player.global_transform.basis.z)
	player.velocity.x = dir.x * force
	player.velocity.z = dir.z * force
	if player.velocity.y < hop:
		player.velocity.y = hop

## Détection SERVEUR le long du trajectoire : d'abord le premier mur (décor
## réel, tous les joueurs exclus -- `wall_hit`) pour borner la portée utile,
## puis le premier ennemi capté avant cette borne (`first_hit_along_path`).
## `aim_dir` vient de la vue serveur du joueur (déjà validée -- AimValidator),
## aplati sur le plan horizontal comme le mouvement local.
func activate_server(player: PlayerController, aim_dir: Vector3) -> void:
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null:
		return
	var dir := _flat_dir(player, aim_dir)
	var origin: Vector3 = player.global_position
	var space := player.get_world_3d().direct_space_state
	var wall := wall_hit(space, origin + Vector3(0, 1.0, 0), dir, charge_distance, _exclude_all_players(player))
	var wall_dist: float = charge_distance
	if not wall.is_empty():
		wall_dist = (origin + Vector3(0, 1.0, 0)).distance_to(wall.position)

	var my_team := int(player.get("team"))
	var candidates := _enemy_candidates(player, my_team)
	var victim := first_hit_along_path(origin, dir, wall_dist, candidates, capture_radius)

	if not victim.is_empty():
		_hit_victim(victim, dir, player)
	elif not wall.is_empty():
		_self_stun(ctrl, player)

## Direction horizontale (y=0) normalisée : `base` d'abord (aim_dir côté
## serveur, orientation du corps côté propriétaire), repli sur l'orientation
## du corps si `base` est déjà verticale ou nulle une fois aplatie.
func _flat_dir(player: PlayerController, base: Vector3) -> Vector3:
	var flat := Vector3(base.x, 0.0, base.z)
	if flat.length() < 0.01:
		flat = -player.global_transform.basis.z
		flat.y = 0.0
	return flat.normalized()

## Candidats ennemis vivants (même construction que StunBurstAbility/
## RenewalAbility), déjà filtrés à l'équipe adverse (TargetSelect.enemies_of).
func _enemy_candidates(player: PlayerController, my_team: int) -> Array:
	var out: Array = []
	var players_root := player.get_parent()
	if players_root == null:
		return out
	for child in players_root.get_children():
		if child == player:
			continue
		var other := child as CharacterBody3D
		if other == null:
			continue
		var ohp := other.get_node_or_null("Health") as Health
		if ohp and ohp.is_dead:
			continue
		out.append({"id": str(other.name).to_int(), "pos": other.global_position, "team": int(other.get("team")), "node": other})
	return TargetSelect.enemies_of(out, my_team)

## Applique dégâts + repoussée + étourdissement à la VICTIME touchée. Appel
## DIRECT si la victime est simulée ICI (hôte/bot -- autorité serveur
## partagée), RPC ciblée sinon (même patron que StunBurstAbility/
## AbilityController._spawn_stun_trap).
func _hit_victim(victim: Dictionary, dir: Vector3, player: PlayerController) -> void:
	var node: CharacterBody3D = victim.node
	var hp := node.get_node_or_null("Health") as Health
	if hp:
		hp.apply_damage(hit_damage, str(player.name).to_int())
		if hp.is_dead:
			return  # achevée par les dégâts : repoussée/étourdissement inutiles sur un corps.
	var victim_ctrl := node.get_node_or_null("Abilities")
	if victim_ctrl == null:
		return
	var impulse := dir * knockback_distance
	if node.is_multiplayer_authority():
		if victim_ctrl.has_method("net_apply_impulse"):
			victim_ctrl.net_apply_impulse(impulse)
		if victim_ctrl.has_method("net_apply_stun"):
			victim_ctrl.net_apply_stun(victim_stun_duration)
	else:
		var vid: int = victim.id
		if victim_ctrl.has_method("net_apply_impulse"):
			victim_ctrl.net_apply_impulse.rpc_id(vid, impulse)
		if victim_ctrl.has_method("net_apply_stun"):
			victim_ctrl.net_apply_stun.rpc_id(vid, victim_stun_duration)

## Auto-étourdissement de CHOC lui-même (mur percuté, aucun ennemi capté
## avant). `ctrl` == le nœud "Abilities" du lanceur lui-même : même appel
## direct/RPC que pour une victime distincte, `player` étant ici sa propre cible.
func _self_stun(ctrl: Node, player: PlayerController) -> void:
	if not ctrl.has_method("net_apply_stun"):
		return
	if player.is_multiplayer_authority():
		ctrl.net_apply_stun(self_stun_duration)
	else:
		ctrl.net_apply_stun.rpc_id(str(player.name).to_int(), self_stun_duration)

## Premier ennemi capté dans le couloir de charge (segment `origin` ->
## `origin + dir * length`, rayon `radius`) -- PUR, testable sans scène
## (tests/agents/test_choc_kit.gd). `candidates` : même format que
## TargetSelect (Dictionary {id, pos, team, node...}), DÉJÀ filtrés aux
## ennemis. Trie par projection le long de `dir` (le PREMIER touché, jamais le
## plus proche de l'axe) ; un candidat derrière l'origine (t < 0) ou au-delà de
## `length` (mur ou fin de charge) est ignoré.
static func first_hit_along_path(origin: Vector3, dir: Vector3, length: float, candidates: Array, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_t := INF
	for c in candidates:
		var d: Dictionary = c
		var pos: Vector3 = d.get("pos", origin)
		var t: float = (pos - origin).dot(dir)
		if t < 0.0 or t > length:
			continue
		var closest := origin + dir * t
		if closest.distance_to(pos) <= radius and t < best_t:
			best_t = t
			best = d
	return best

## Rayon de contact SERVEUR le long de la charge : masque PhysicsLayers.
## SHOT_MASK (ignore la VISION -- une fumée n'arrête pas une charge d'épaule),
## TOUS les joueurs exclus (seul le décor arrête ce rayon -- la détection
## d'ennemi est gérée séparément par `first_hit_along_path`, en amont de la
## borne qu'il renvoie). Statique et exposé pour être testable directement,
## même patron que StunTrapAbility.ground_hit / StunBurstAbility.trajectory_hit.
static func wall_hit(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, length: float, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * length, PhysicsLayers.SHOT_MASK)
	q.exclude = exclude
	q.collide_with_areas = false
	return space.intersect_ray(q)

## Exclut le lanceur ET tous les autres joueurs de la scène (RID physique) --
## voir wall_hit ci-dessus (même motif que StunTrapAbility._exclude_all_players).
static func _exclude_all_players(player: PlayerController) -> Array[RID]:
	var rids: Array[RID] = [player.get_rid()]
	var players_root := player.get_parent()
	if players_root == null:
		return rids
	for child in players_root.get_children():
		if child == player:
			continue
		var body := child as CharacterBody3D
		if body:
			rids.append(body.get_rid())
	return rids
