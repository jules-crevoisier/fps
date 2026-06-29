## Air — en l'air, modèle CS / Valorant (air-strafe style Source) : on n'ajoute de
## la vitesse que jusqu'à une petite "vitesse souhaitée" dans la direction visée ;
## en tournant la souris tout en strafant, on redresse et on gagne de la vitesse.
## Le momentum est conservé (pas de friction aérienne).
extends PlayerState

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(false)

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	if player.wish_dir != Vector3.ZERO:
		# 1) air-strafe Source : gagne de la vitesse en tournant la souris + strafe.
		player.accelerate(player.wish_dir, config.air_wishspeed, config.air_accel, delta)
		# 2) contrôle direct : freine / réoriente dans toutes les directions.
		player.air_control_move(config.air_control, delta)

	# Saut bufferisé encore valable via coyote time.
	if player.jump_buffered() and player.can_jump():
		player.do_jump()
		return

	if player.is_on_floor():
		_land()

func _land() -> void:
	player.slide_jumped = false
	# Landing roll au bon timing (dive pressé juste avant l'atterrissage) => roulade
	# qui annule le stun de chute.
	if player.land_roll_buffered():
		player.consume_roll_buffer()
		transition_to("Roll")
		return
	# Atterrir crouch maintenu + assez vite => slide-hop.
	if config.slide_hop_enabled and Input.is_action_pressed("crouch") \
			and player.horizontal_speed() >= config.slide_min_speed:
		transition_to("Slide")
		return
	if player.input_vector == Vector2.ZERO:
		transition_to("Idle")
	elif Input.is_action_pressed("walk"):
		transition_to("Walk")
	else:
		transition_to("Sprint")
