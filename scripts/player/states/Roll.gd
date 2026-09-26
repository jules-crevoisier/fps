## Roll — roulade à l'atterrissage d'une plongée. Déclenche le spin caméra
## (effet "machine à laver") et décélère. Phase de récupération : pas d'action
## pendant la durée de la roulade, puis on se relève.
extends PlayerState

var _timer: float = 0.0

func enter(_from: String, msg: Dictionary = {}) -> void:
	player.set_crouching(true)
	_timer = 0.0
	# Spin de caméra dans le sens du dash (culbute avant/arrière, tonneau gauche/droite).
	var dir: Vector2 = msg.get("dir", Vector2(0.0, 1.0))
	if player.camera and player.camera.has_method("play_roll"):
		player.camera.play_roll(config.roll_duration, config.roll_spins, dir)

func physics_update(delta: float) -> void:
	_timer += delta
	player.apply_gravity(delta)
	# On garde l'élan du dash (friction faible) et on se dirige avec ZQSD ; si on roule
	# presque à l'arrêt, on remet de la vitesse de marche pour repartir sans temps mort.
	player.apply_friction(config.roll_friction, delta)
	player.redirect_velocity(player.wish_dir, config.roll_steer_rate, delta)
	if player.horizontal_speed() < config.walk_speed:
		player.ground_move(config.walk_speed, config.ground_accel, 0.0, delta)
	# Saut pendant la roulade : on enchaîne directement.
	if player.jump_buffered() and player.can_jump():
		player.set_crouching(false)
		player.do_jump()
		transition_to("Air")
		return

	# Fin de la roulade => on se relève.
	if _timer >= config.roll_duration:
		_stand()

func _stand() -> void:
	# Plafond bas au-dessus de la tête => rester accroupi (BUG-08) plutôt que
	# de se relever dans le décor ; Crouch relèvera dès que ce sera dégagé.
	if player.is_blocked_above():
		transition_to("Crouch")
		return
	player.set_crouching(false)
	if player.input_vector == Vector2.ZERO:
		transition_to("Idle")
	elif player.input.walk_held and player.horizontal_speed() <= config.walk_speed * 1.1:
		transition_to("Walk")
	else:
		# Sortie de dash encore rapide : on repart en course (l'élan n'est pas cassé).
		transition_to("Sprint")
