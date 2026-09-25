## Idle — au sol, immobile. Sprint automatique dès qu'on bouge (Shift = marche).
## Glu de Verrou (AGT-08, 2e passage -- vague 28 refusée) : `player.
## is_jump_locked()` bloque déjà le saut via `can_jump()` (PlayerController.gd,
## hors périmètre de ce contrat), mais RIEN ne bloquait jusqu'ici l'entrée en
## Dive -- un joueur englué pouvait plonger normalement. Gardée ici derrière
## le même verrou (voir tests/agents/test_verrou_kit.gd, section intégration
## des states).
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
	if config.dive_enabled and player.input.dive_pressed and not player.is_jump_locked():
		transition_to("Dive")
		return
	if player.input.crouch_held:
		transition_to("Crouch")
		return
	if player.input_vector != Vector2.ZERO:
		transition_to("Walk" if player.input.walk_held else "Sprint")
