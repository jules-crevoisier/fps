## StunTrapAbility — pose un piège invisible qui étourdit le premier ennemi qui
## marche dessus. Position calculée côté SERVEUR (raycast au sol le long
## d'`aim_dir` validé, masque PhysicsLayers.SHOT_MASK et joueurs exclus : le
## rayon de pose ignore la fumée (bloque la vue, pas les balles) et n'accepte
## que le décor, jamais la tête d'un joueur — docs/audit/bugs.md BUG-06) ;
## objet répliqué à tous pour l'affichage (AbilityController.cast_stun_trap),
## mais SEULE la copie serveur détecte le contact et envoie
## transition_to("Stun", ...) au propriétaire de la victime (contract-r2.md,
## R-B3 acceptance #2).
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
	var hit := ground_hit(space, above, above + Vector3(0, -4.0, 0), _exclude_all_players(player))
	var pos: Vector3 = hit.position if not hit.is_empty() else player.global_position + flat * throw_range
	ctrl.cast_stun_trap(pos, int(player.get("team")), trap_duration, stun_duration)

## Rayon de pose au sol : masque PhysicsLayers.SHOT_MASK (ignore la fumée,
## calque VISION) ET exclut tous les joueurs (pas seulement le lanceur) — un
## piège ne doit accepter que le décor, jamais atterrir sur la tête d'un
## joueur (docs/audit/bugs.md BUG-06). Statique et exposé pour être testable
## directement (tests/agents/test_ability_rays.gd).
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
