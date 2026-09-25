## Dive — plongée "dolphin dive" façon vieux CoD : on se propulse vers l'avant
## (direction de la caméra) avec un arc. À l'atterrissage => Roll (roulade).
## Pendant la plongée le perso est engagé : pas de contrôle, juste l'inertie.
##
## Délai de sécurité (BUG-08) : sous un obstacle assez bas, l'élan vertical du
## plongeon est annulé dès la première frame et `is_on_floor()` reste vrai en
## continu — `_airborne` ne passe donc jamais à vrai et l'atterrissage naturel
## (`elif _airborne`) ne se déclenche jamais, laissant le joueur bloqué à vie
## dans cet état. `_MAX_DURATION` force la sortie quoi qu'il arrive.
extends PlayerState

const _MAX_DURATION := 1.0

var _airborne: bool = false
var _timer: float = 0.0

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(true)
	_airborne = false
	_timer = 0.0
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
	_timer += delta
	player.apply_gravity(delta)
	player.apply_friction(config.dive_air_drag, delta)

	if not player.is_on_floor():
		_airborne = true
	elif _airborne:
		# Atterrissage => roulade.
		transition_to("Roll")
		return

	# Minuterie de sécurité : jamais plus de _MAX_DURATION dans cet état, même
	# si un obstacle a empêché tout décollage réel (voir docstring plus haut).
	if _timer >= _MAX_DURATION:
		transition_to("Roll")
