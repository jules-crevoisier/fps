## Crouch — accroupi (TOGGLE) : un tap de crouch pour s'accroupir, un autre pour
## se relever. On ne se relève que si le plafond est dégagé.
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
	# Re-tap de crouch => se relever (si rien au-dessus).
	if Input.is_action_just_pressed("crouch") and not player.is_blocked_above():
		player.set_crouching(false)
		_stand()

func _stand() -> void:
	if player.input_vector == Vector2.ZERO:
		transition_to("Idle")
	elif Input.is_action_pressed("walk"):
		transition_to("Walk")
	else:
		transition_to("Sprint")
