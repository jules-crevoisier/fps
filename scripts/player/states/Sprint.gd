## Sprint — locomotion par DÉFAUT (sprint automatique). Shift => marche.
## Un tap de crouch en sprint => slide. Viser (ADS) SUSPEND le sprint auto
## (MV-02, façon Valorant : on ne sprinte pas en visant) : la vitesse cible
## retombe alors à l'allure de marche ralentie par `ads_move_mult`.
## Glu de Verrou (AGT-08, 2e passage -- vague 28 refusée) : Dive ET Slide
## gardés derrière `player.is_jump_locked()`, même raison que Walk.gd -- voir
## tests/agents/test_verrou_kit.gd.
extends PlayerState

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(false)

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	var target_speed := config.sprint_speed
	if player.input.aim_held:
		target_speed = WeaponFeel.ads_move_speed(config.walk_speed, true, config.ads_move_mult)
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
	if player.input.walk_held:
		transition_to("Walk")
