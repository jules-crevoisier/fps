## DashAbility — ruée rapide dans la direction de déplacement (ou du regard).
extends Ability

func _init() -> void:
	slot = "C"
	display_name = "Dash"
	cooldown = 6.0
	charges = 2

func activate(player: PlayerController) -> void:
	var dir := player.wish_dir
	if dir == Vector3.ZERO:
		dir = -player.global_transform.basis.z
		dir.y = 0.0
		dir = dir.normalized()
	var force := 17.0
	player.velocity.x = dir.x * force
	player.velocity.z = dir.z * force
	if player.velocity.y < 2.5:
		player.velocity.y = 2.5
