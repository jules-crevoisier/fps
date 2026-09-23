## Walk — marche lente (Shift maintenu). Relâcher Shift => sprint automatique.
extends PlayerState

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(false)

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.ground_move(config.walk_speed, config.ground_accel, config.ground_friction, delta)

	if not player.is_on_floor():
		transition_to("Air")
		return
	if player.jump_buffered() and player.can_jump():
		player.do_jump()
		transition_to("Air")
		return
	if config.dive_enabled and player.input.dive_pressed:
		transition_to("Dive")
		return
	if player.input.crouch_pressed and player.horizontal_speed() >= config.slide_min_speed:
		transition_to("Slide")
		return
	if player.input.crouch_held:
		transition_to("Crouch")
		return
	if player.input_vector == Vector2.ZERO:
		transition_to("Idle")
		return
	if not player.input.walk_held:
		transition_to("Sprint")
