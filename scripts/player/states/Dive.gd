## Dive — plongée "dolphin dive" façon vieux CoD : on se propulse vers l'avant
## (direction de la caméra) avec un arc. À l'atterrissage => Roll (roulade).
## Pendant la plongée le perso est engagé : pas de contrôle, juste l'inertie.
extends PlayerState

var _airborne: bool = false

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(true)
	_airborne = false
	# Direction horizontale de la caméra (= yaw du corps).
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if fwd == Vector3.ZERO:
		fwd = -player.global_transform.basis.z
	player.velocity.x = fwd.x * config.dive_speed
	player.velocity.z = fwd.z * config.dive_speed
	player.velocity.y = config.dive_jump

func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.apply_friction(config.dive_air_drag, delta)

	if not player.is_on_floor():
		_airborne = true
	elif _airborne:
		# Atterrissage => roulade.
		transition_to("Roll")
