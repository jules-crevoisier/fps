## RenewalAbility — ULTIME de Roseau ("Sursaut"), VERSION D'ÉQUIPE
## (docs/research/10_ammo_kits_input.md §3.3, fiche Roseau, X) : soin complet
## instantané (SANS la condition hors-combat du soin de base) pour elle-même
## ET pour ses ALLIÉS vivants à <= `ally_heal_radius`, + révèle les ennemis
## proches d'elle pour son équipe. Combine trois primitives serveur (soin
## soi-même, soin d'équipe, reveal) — comme SurgeAbility combine soin et bond.
extends Ability

## Rayon (m) dans lequel un ALLIÉ vivant reçoit lui aussi un soin complet.
@export var ally_heal_radius: float = 10.0
@export var reveal_radius: float = 12.0
@export var reveal_duration: float = 3.0

func _init() -> void:
	slot = "X"
	display_name = "Sursaut"
	description = "Soin complet instantané pour elle et ses alliés proches, et révèle les ennemis proches pour son équipe."
	is_ultimate = true
	ult_cost = 7

func activate_server(player: PlayerController, _aim_dir: Vector3) -> void:
	var hp := player.get_node_or_null("Health") as Health
	if hp and not hp.is_dead:
		hp.heal(hp.max_health)

	var players_root := player.get_parent()
	if players_root == null:
		return
	var my_team := int(player.get("team"))
	# Un seul passage sur les autres joueurs : soigne les alliés proches ET
	# construit la liste de candidats pour le reveal (ennemis vivants).
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
		var other_team := int(other.get("team"))
		if ohp and other_team == my_team:
			# Allié vivant à <= ally_heal_radius (docs/research/
			# 10_ammo_kits_input.md §3.3 : "soin complet ... pour elle et ses
			# alliés à <= 10 m") : soin complet, comme pour elle-même.
			if player.global_position.distance_to(other.global_position) <= ally_heal_radius:
				ohp.heal(ohp.max_health)
		candidates.append({"pos": other.global_position, "team": other_team})

	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null or not ctrl.has_method("cast_reveal"):
		return
	var revealed := TargetSelect.within_radius(player.global_position, TargetSelect.enemies_of(candidates, my_team), reveal_radius)
	if revealed.is_empty():
		return
	var marks: Array = []
	for r in revealed:
		marks.append(r.pos)
	ctrl.cast_reveal(players_root, my_team, marks, reveal_duration)
