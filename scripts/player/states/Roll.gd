## Roll — roulade à l'atterrissage d'une plongée. Déclenche le spin caméra
## (effet "machine à laver") et décélère. Phase de récupération : pas d'action
## pendant la durée de la roulade, puis on se relève.
extends PlayerState

var _timer: float = 0.0

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(true)
	_timer = 0.0
	# Lance l'animation de roulade sur la caméra (spin complet).
	if player.camera and player.camera.has_method("play_roll"):
		player.camera.play_roll(config.roll_duration, config.roll_spins)

func physics_update(delta: float) -> void:
	_timer += delta
	player.apply_gravity(delta)
	player.apply_friction(config.roll_friction, delta)

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
	elif player.input.walk_held:
		transition_to("Walk")
	else:
		transition_to("Sprint")
