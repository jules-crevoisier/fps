## Air — en l'air. Cœur de la fluidité façon Apex :
##  - AIR STRAFE (gain de vitesse style Source via accelerate),
##  - AIR CONTROL : on redirige le vecteur vitesse vers la direction visée sans
##    perdre de vitesse (redirect_velocity) -> trajectoires courbes fluides,
##  - TAP-STRAFE : une nouvelle pression directionnelle renforce la redirection,
##  - SLIDE-HOP : atterrir crouch maintenu relance un slide en gardant la vitesse.
extends PlayerState

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(false)

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)

	if player.wish_dir != Vector3.ZERO:
		# Léger gain de vitesse (strafe), puis redirection fluide vers la visée.
		player.accelerate(player.wish_dir, config.air_speed, config.air_accel, delta)
		var rate := config.air_control
		if config.tap_strafe_enabled and _just_tapped():
			rate *= config.tap_strafe_boost
		player.redirect_velocity(player.wish_dir, rate, delta)
	elif config.air_friction > 0.0:
		player.apply_friction(config.air_friction, delta)

	# Saut bufferisé encore valable via coyote time.
	if player.jump_buffered() and player.can_jump():
		player.do_jump()
		return

	if player.is_on_floor():
		_land()

## Détecte une nouvelle pression directionnelle (pour le tap-strafe).
func _just