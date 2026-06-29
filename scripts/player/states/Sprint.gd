## Sprint — course rapide. Point d'entrée du slide (crouch en pleine course).
extends PlayerState

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(false)

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	if player.wish_dir != Vector3.ZERO:
		player.accelerate(player.wish_dir, config.sprint_speed, config.ground_accel, delta)
	else:
		player.apply_friction(config.ground_friction, delta)

	if not player.is_on_floor():
		transition_to("Air")
		return
	if player.jump_buffered() and player.can_jump():
		player.do_jump()
		transition_to("Air")
		return
	# Déclenchement du slide : crouch pressé en course assez rapide.
	if Input.is_action_just_pressed("crouch") and player.can_slide() and player.horizontal_speed() >= config.slide_min_speed:
		transition_to("Slide")
		return
	if Input.is_action_pressed("crouch"):
		transition_to("Crouch")
		return
	if player.input_vector == Vector2.ZERO:
		transition_to("Idle")
		return
	if not Input.is_action_pressed("sprint"):
		transition_to("Walk")
