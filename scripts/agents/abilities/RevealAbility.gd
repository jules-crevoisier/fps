## RevealAbility — révèle des ennemis pour l'équipe du lanceur (marqueurs "!"
## visibles à travers les murs, <= 3 s — contract-r2.md, R-B3 acceptance #2).
## Le SERVEUR construit la liste des ennemis vivants depuis sa propre vue,
## filtre avec TargetSelect (logique pure testée), puis pousse les positions
## UNIQUEMENT aux coéquipiers (AbilityController.cast_reveal, RPC ciblées).
## `reveal_all` (ultime "Vision totale") ignore le point d'impact et révèle
## tous les ennemis de la carte.
extends Ability

@export var throw_range: float = 20.0
@export var reveal_radius: float = 10.0
@export var reveal_all: bool = false
@export var duration: float = 3.0

func _init() -> void:
	slot = "E"
	display_name = "Œil"
	description = "Marqueur qui révèle les ennemis à travers les murs dans un rayon, visible seulement par son équipe (3 s)."
	cooldown = 24.0
	charges = 1

func activate_server(player: PlayerController, aim_dir: Vector3) -> void:
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null or not ctrl.has_method("cast_reveal"):
		return
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
		candidates.append({"pos": other.global_position, "team": int(other.get("team"))})
	var enemies := TargetSelect.enemies_of(candidates, my_team)

	var revealed: Array
	if reveal_all:
		revealed = enemies
	else:
		var origin: Vector3 = player.head.global_position
		var space := player.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(origin, origin + aim_dir * throw_range)
		q.exclude = [player.get_rid()]
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		var cast_pos: Vector3 = hit.position if not hit.is_empty() else origin + aim_dir * throw_range
		revealed = TargetSelect.within_radius(cast_pos, enemies, reveal_radius)

	if revealed.is_empty():
		return
	var marks: Array = []
	for r in revealed:
		marks.append(r.pos)
	ctrl.cast_reveal(players_root, my_team, marks, duration)
