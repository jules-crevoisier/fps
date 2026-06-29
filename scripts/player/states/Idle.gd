## Idle — au sol, immobile. Sprint automatique dès qu'on bouge (Shift = marche).
extends PlayerState

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(false)

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.ground_move(0.0, config.ground_accel, config.ground_friction, delta)

	if not player.is_on_floor():
		transition_to("Air")
		return
	if player.jump_buffered() and player.can_jump():
		player.do_jump()
		transition_to("Air")
		return
	if config.dive_enabled and Input.is_action_just_pressed("dive"):
		transition_to("Dive")
		return
	if Input.is_action_pressed("crouch"):
		transition_to("Crouch")
		return
	if player.input_vector != Vector2.ZERO:
		transition_to("Walk" if Input.is_action_pressed("walk") else "Sprint")
