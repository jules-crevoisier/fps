## BastionAbility — ULTIME de Verrou ("Bastion") : pose un mur ET une plaque
## de Glu au même endroit, verrouillant un couloir entier (rebranché sur la
## Glu — docs/research/10_ammo_kits_input.md §3.3 : "X Bastion : mur et Glu au
## lieu du piège étourdissant... existe, à rebrancher sur la Glu"). Le mur
## réutilise la primitive serveur existante d'AbilityController (cast_barrier,
## hors périmètre de ce contrat) ; la Glu réutilise GlueAbility.spawn_zone
## (zone persistante, plusieurs victimes — voir sa docstring), depuis la vue
## serveur du joueur.
extends Ability

const GlueAbilityScript := preload("res://scripts/agents/abilities/GlueAbility.gd")

@export var size: Vector3 = Vector3(5.0, 2.8, 0.45)
@export var distance: float = 3.0
@export var height_offset: float = 1.4
@export var wall_duration: float = 12.0
@export var wall_color: Color = Color(0.55, 0.3, 0.75)
@export var glue_duration: float = 16.0
@export var glue_radius: float = 2.5
@export var slow_mult: float = 0.5
@export var linger: float = 1.5
@export var glue_color: Color = Color(0.25, 0.55, 0.85)

func _init() -> void:
	slot = "X"
	display_name = "Bastion"
	description = "Pose un mur ET une plaque de Glu au même endroit : verrouille un couloir entier."
	is_ultimate = true
	ult_cost = 8

func activate_server(player: PlayerController, _aim_dir: Vector3) -> void:
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl and ctrl.has_method("cast_barrier"):
		var wall_pos := player.global_position + fwd * distance + Vector3(0, height_offset, 0)
		ctrl.cast_barrier(wall_pos, fwd, size, wall_duration, wall_color)
	var scene := player.get_tree().current_scene
	if scene:
		var glue_pos := player.global_position + fwd * (distance + 1.2)
		glue_pos.y = player.global_position.y
		GlueAbilityScript.spawn_zone(scene, glue_pos, int(player.get("team")), glue_radius, glue_duration,
			slow_mult, linger, glue_color)
