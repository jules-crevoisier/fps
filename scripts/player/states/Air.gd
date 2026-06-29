## Air — en l'air. Air-strafe fluide : accel/friction faibles = on garde l'inertie
## et on peut redirriger sa course en combinant souris + strafe (façon Source).
extends PlayerState

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(false)

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)

	if config.air_friction > 0.0 and player.wish_dir == Vector3.ZERO:
		player.apply_friction(config.air_friction, delta)
	if player.wish_dir != Vector3.ZERO:
		# wish_speed faible : on ajoute juste de quoi tourner sans capper la vitesse.
		player.accelerate(player.wish_dir, config.air_speed, config.air_accel, delta)

	# Saut bufferisé encore valable via coyote time.
	if player.jump_buffered() and player.can_jump():
		player.do_jump()
		return

	if player.is_on_floor():
		_land()

func _land() -> void:
	# Atterrir en maintenant crouch + assez de vitesse => slide direct (clé du fluide).
	if Input.is_action_pressed("crouch") and player.can_slide() and player.horizontal_speed() >= config.slide_min_speed:
		transition_to("Slide")
		return
	if Input.is_action_pressed("crouch"):
		transition_to("Crouch")
		return
	if player.input_vector == Vector2.ZERO:
		transition_to("Idle")
	elif Input.is_action_pressed("sprint"):
		transition_to("Sprint")
	else:
		transition_to("Walk")
