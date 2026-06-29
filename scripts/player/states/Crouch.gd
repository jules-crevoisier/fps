## Crouch — accroupi, lent. Ne peut se relever que si le plafond est dégagé.
extends PlayerState

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(true)

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	if player.wish_dir != Vector3.ZERO:
		player.accelerate(player.wish_dir, config.crouch_speed, config.ground_accel, delta)
	else:
		player.apply_friction(config.ground_friction, delta)

	if not player.is_on_floor():
		transition_to("Air")
		return
	if player.jump_buffered() and player.can_jump() and not player.is_blocked_above():
		player.set_crouching(false)
		player.do_jump()
		transition_to("Air")
		return
	# On ne se relève que si rien au-dessus.
	if not Input.is_action_pressed("crouch") and not player.is_blocked_above():
		if player.input_vector == Vector2.ZERO:
			transition_to("Idle")
		elif Input.is_action_pressed("sprint"):
			transition_to("Sprint")
		else:
			transition_to("Walk")
