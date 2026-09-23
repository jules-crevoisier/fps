## RenewalAbility — ULTIME de Baume ("Sursaut") : soin complet instantané
## (SANS la condition hors-combat du soin de base) + révèle les ennemis
## proches d'elle pour son équipe. Combine deux primitives serveur (soin,
## reveal) dans une seule capacité — comme SurgeAbility combine soin et bond.
extends Ability

@export var reveal_radius: float = 12.0
@export var reveal_duration: float = 3.0

func _init() -> void:
	slot = "X"
	display_name = "Sursaut"
	description = "Soin complet instantané (sans condition) et révèle les ennemis proches pour son équipe."
	is_ultimate = true
	ult_cost = 7

func activate_server(player: PlayerController, _aim_dir: Vector3) -> void:
	var hp := player.get_node_or_null("Health") as Health
	if hp and not hp.is_dead:
		hp.heal(hp.max_health)

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
	var revealed := TargetSelect.within_radius(player.global_position, TargetSelect.enemies_of(candidates, my_team), reveal_radius)
	if revealed.is_empty():
		return
	var marks: Array = []
	for r in revealed:
		marks.append(r.pos)
	ctrl.cast_reveal(players_root, my_team, marks, reveal_duration)
