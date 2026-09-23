## Crouch — accroupi en MAINTIEN : tant que Ctrl est tenu on reste accroupi ;
## relâcher Ctrl relève (si le plafond est dégagé). Jamais bloqué.
extends PlayerState

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(true)

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.ground_move(config.crouch_speed, config.ground_accel, config.ground_friction, delta)

	if not player.is_on_floor():
		transition_to("Air")
		return
	if player.jump_buffered() and player.can_jump() and not player.is_blocked_above():
		player.set_crouching(false)
		player.do_jump()
		transition_to("Air")
		return
	# Relâcher Ctrl => se relever (si rien au-dessus).
	if not player.input.crouch_held and not player.is_blocked_above():
		player.set_crouching(false)
		_stand()

func _stand() -> void:
	if player.input_vector == Vector2.ZERO:
		transition_to("Idle")
	elif player.input.walk_held:
		transition_to("Walk")
	else:
		transition_to("Sprint")
