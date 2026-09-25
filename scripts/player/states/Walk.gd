## Walk — marche lente (Shift maintenu, ou visée ADS qui suspend le sprint
## auto). Relâcher Shift (hors visée) => sprint automatique. Viser (MV-02)
## ralentit encore la marche via `ads_move_mult`.
## Glu de Verrou (AGT-08, 2e passage -- vague 28 refusée) : Dive ET Slide
## gardés derrière `player.is_jump_locked()` -- un joueur englué ne pouvait
## jusqu'ici toujours plonger/glisser normalement malgré le verrou de saut
## déjà câblé (can_jump()). Voir tests/agents/test_verrou_kit.gd.
extends PlayerState

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(false)

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	var target_speed := WeaponFeel.ads_move_speed(config.walk_speed, player.input.aim_held, config.ads_move_mult)
	player.ground_move(target_speed, config.ground_accel, config.ground_friction, delta)

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
	if player.input.crouch_pressed and player.horizontal_speed() >= config.slide_min_speed \
			and not player.is_jump_locked():
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
