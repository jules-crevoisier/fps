## BastionAbility — ULTIME de Verrou ("Bastion") : pose un mur ET un piège
## étourdissant au même endroit, verrouillant un couloir entier. Combine deux
## primitives serveur (mur, piège) réutilisant directement AbilityController
## (cast_barrier / cast_stun_trap), depuis la vue serveur du joueur.
extends Ability

@export var size: Vector3 = Vector3(5.0, 2.8, 0.45)
@export var distance: float = 3.0
@export var height_offset: float = 1.4
@export var wall_duration: float = 12.0
@export var color: Color = Color(0.55, 0.3, 0.75)
@export var trap_duration: float = 16.0
@export var stun_duration: float = 2.2

func _init() -> void:
	slot = "X"
	display_name = "Bastion"
	description = "Pose un mur ET un piège étourdissant au même endroit : verrouille un couloir entier."
	is_ultimate = true
	ult_cost = 8

func activate_server(player: PlayerController, _aim_dir: Vector3) -> void:
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null:
		return
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if ctrl.has_method("cast_barrier"):
		var wall_pos := player.global_position + fwd * distance + Vector3(0, height_offset, 0)
		ctrl.cast_barrier(wall_pos, fwd, size, wall_duration, color)
	if ctrl.has_method("cast_stun_trap"):
		var trap_pos := player.global_position + fwd * (distance + 1.2)
		ctrl.cast_stun_trap(trap_pos, int(player.get("team")), trap_duration, stun_duration)
