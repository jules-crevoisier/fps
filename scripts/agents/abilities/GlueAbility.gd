## GlueAbility — signature (E) de Verrou : refonte de la Chausse-trape,
## conforme au lore (la glu des dendrobates — docs/research/
## 10_ammo_kits_input.md §3.3). Une plaque collante posée au sol (position
## calculée côté SERVEUR, même motif de rayon que StunTrapAbility.ground_hit :
## masque PhysicsLayers.SHOT_MASK — ignore la fumée, calque VISION — et
## exclut TOUS les joueurs, jamais seulement le lanceur, docs/audit/bugs.md
## BUG-06), mais qui, contrairement à un piège à déclenchement UNIQUE, reste
## ACTIVE `duration` s et ralentit TOUS les ennemis vivants qui s'y trouvent
## EN MÊME TEMPS ("plusieurs victimes", critère d'acceptation AGT-08) : -50 %
## de vitesse, saut/glissade/plongeon verrouillés, effet qui dure encore
## `linger` s après la sortie.
##
## `spawn_zone` (statique) est réutilisée telle quelle par BastionAbility.gd
## (ultime de Verrou, "mur ET Glu au même endroit").
##
## Réseau : SEULE la copie SERVEUR de la zone (`_GlueZone._physics_process`,
## gardé par `multiplayer.is_server()`, même garde que HealZone.gd) détecte
## le contact et applique l'effet, via les méthodes DÉJÀ PUBLIQUES et testées
## d'AbilityController (`server_apply_speed_mult`/`server_apply_jump_lock`,
## AGT-01 — ce contrat ne modifie PAS AbilityController.gd, hors périmètre).
## Ces méthodes gèrent déjà elles-mêmes la poussée <= 1 tick au propriétaire
## (bot/hôte : appel direct : pair distant : RPC interne à `_push_status`) :
## aucun `rpc_id` supplémentaire n'est nécessaire ici. La zone n'est PAS
## répliquée visuellement à tous les pairs (cast_barrier/cast_smoke/
## cast_stun_trap le sont via un RPC d'AbilityController.gd, hors périmètre
## de ce contrat) : seul son EFFET DE JEU (ralentissement/verrous, déjà
## répliqué au propriétaire concerné par le socle AGT-01) est garanti par ce
## contrat — voir blocked_on du rendu AGT-08.
extends Ability

## Distance de pose (m), depuis la vue serveur du joueur — même borne que
## l'ancienne Chausse-trape.
@export var throw_range: float = 6.0
## Rayon de la plaque (m).
@export var radius: float = 2.5
## Durée de vie de la plaque (s).
@export var duration: float = 20.0
## Multiplicateur de vitesse infligé (0.5 = -50 %).
@export var slow_mult: float = 0.5
## Durée (s) réappliquée à CHAQUE tick de contact : la minuterie décroît
## naturellement une fois hors de la zone (AbilityController._physics_process
## fait déjà avancer StatusEffects.tick() en continu), ce qui donne l'effet
## "+1.5 s après la sortie" sans minuterie de sortie séparée.
@export var linger: float = 1.5
@export var color: Color = Color(0.25, 0.55, 0.85)

func _init() -> void:
	slot = "E"
	display_name = "Glu"
	description = "Plaque collante persistante : -50 % de vitesse, ni saut ni glissade ni plongeon, encore 1,5 s après la sortie."
	cooldown = 18.0
	charges = 1

func activate_server(player: PlayerController, aim_dir: Vector3) -> void:
	var scene := player.get_tree().current_scene
	if scene == null:
		return
	var flat := Vector3(aim_dir.x, 0.0, aim_dir.z)
	if flat.length() < 0.01:
		flat = -player.global_transform.basis.z
	flat = flat.normalized()
	var above := player.global_position + flat * throw_range + Vector3(0, 1.0, 0)
	var space := player.get_world_3d().direct_space_state
	var hit := ground_hit(space, above, above + Vector3(0, -4.0, 0), _exclude_all_players(player))
	var pos: Vector3 = hit.position if not hit.is_empty() else player.global_position + flat * throw_range
	spawn_zone(scene, pos, int(player.get("team")), radius, duration, slow_mult, linger, color)

## Pose une plaque de Glu PERSISTANTE (Area3D) à `pos`, ralentissant TOUT
## ennemi vivant qui s'y trouve — voir docstring du fichier pour le détail du
## réseau. Réutilisée par BastionAbility.gd (ultime de Verrou).
static func spawn_zone(scene: Node, pos: Vector3, owner_team: int, radius: float, duration: float,
		slow_mult: float, linger: float, color: Color) -> void:
	var zone := _GlueZone.new()
	zone.add_to_group("round_props")  # BUG-03 : nettoyé au passage en achat / au reset, comme les autres props posés.
	zone.owner_team = owner_team
	zone.radius = radius
	zone.slow_mult = slow_mult
	zone.linger = linger
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 1.6  # assez haut pour couvrir un joueur debout entièrement, comme le calque de contact.
	col.shape = shape
	zone.add_child(col)
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.06
	mesh.mesh = cm
	mesh.material_override = Cartoon.prop(color)
	zone.add_child(mesh)
	scene.add_child(zone)
	zone.global_position = pos
	var t := scene.get_tree().create_timer(duration)
	t.timeout.connect(zone.queue_free)

## Rayon de pose au sol (copie du motif de StunTrapAbility.ground_hit,
## docs/audit/bugs.md BUG-06 — dupliqué plutôt qu'importé : StunTrapAbility.gd
## est hors périmètre de ce contrat) : masque SHOT_MASK (ignore la fumée) ET
## exclut tous les joueurs.
static func ground_hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.SHOT_MASK)
	q.exclude = exclude
	q.collide_with_areas = false
	return space.intersect_ray(q)

## Exclut le lanceur ET tous les autres joueurs de la scène (RID physique) —
## voir ground_hit ci-dessus.
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

## Zone persistante : Area3D dont la détection ET l'effet ne tournent QUE
## côté SERVEUR (comme HealZone.gd) — ralentit + verrouille saut/glissade/
## plongeon de TOUS les ennemis vivants overlappés, à CHAQUE tick physique,
## en réappliquant `linger` s de durée (voir docstring du fichier pour le
## détail de l'effet "+1.5 s après la sortie").
class _GlueZone extends Area3D:
	var owner_team: int = 0
	var radius: float = 2.5
	var slow_mult: float = 0.5
	var linger: float = 1.5

	func _physics_process(_delta: float) -> void:
		if not multiplayer.is_server():
			return
		for body in get_overlapping_bodies():
			if not (body is PlayerController):
				continue
			if int(body.get("team")) == owner_team:
				continue  # ne ralentit jamais son propre camp (le lanceur inclus).
			var hp := body.get_node_or_null("Health") as Health
			if hp and hp.is_dead:
				continue
			var victim_ctrl := body.get_node_or_null("Abilities")
			if victim_ctrl == null:
				continue
			if victim_ctrl.has_method("server_apply_speed_mult"):
				victim_ctrl.server_apply_speed_mult(slow_mult, linger)
			if victim_ctrl.has_method("server_apply_jump_lock"):
				victim_ctrl.server_apply_jump_lock(linger)
