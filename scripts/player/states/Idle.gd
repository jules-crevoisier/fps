## Idle — au sol, immobile.
extends PlayerState

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(false)

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.apply_friction(config.ground_friction, delta)

	if not player.is_on_floor():
		transition_to("Air")
		return
	if player.jump_buffered() and player.can_jump():
		player.do_jump()
		transition_to("Air")
		return
	if Input.is_action_pressed("crouch"):
		transition_to("Crouch")
		return
	if player.input_vector != Vector2.ZERO:
		if Input.is_action_pressed("sprint"):
			transition_to("Sprint")
		else:
			transition_to("Walk")
