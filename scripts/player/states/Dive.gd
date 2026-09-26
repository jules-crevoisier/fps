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
var _local_dir := Vector2(0.0, 1.0)  ## sens du dash (x = droite, y = avant), pour la roulade
var _timer: float = 0.0

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(true)
	_airborne = false
	_timer = 0.0
	# Dash dans la direction des touches (ZQSD, relative au regard) ; sans touche, droit devant.
	var dir := dash_direction(player.wish_dir, -player.global_transform.basis.z)
	player.velocity.x = dir.x * config.dive_speed
	player.velocity.z = dir.z * config.dive_speed
	_local_dir = local_dash_dir(player.input_vector)
	player.velocity.y = config.dive_jump

func physics_update(delta: float) -> void:
	_timer += delta
	player.apply_gravity(delta)
	player.apply_friction(config.dive_air_drag, delta)

	if not player.is_on_floor():
		_airborne = true
	elif _airborne:
		# Atterrissage => roulade.
		transition_to("Roll", {"dir": _local_dir})
		return

	# Minuterie de sécurité : jamais plus de _MAX_DURATION dans cet état, même
	# si un obstacle a empêché tout décollage réel (voir docstring plus haut).
	if _timer >= _MAX_DURATION:
		transition_to("Roll", {"dir": _local_dir})


## Direction horizontale du dash : celle des touches si on en appuie, sinon le regard.
static func dash_direction(wish_dir: Vector3, look_fwd: Vector3) -> Vector3:
	var d := Vector3(wish_dir.x, 0.0, wish_dir.z)
	if d.length_squared() < 0.01:
		d = Vector3(look_fwd.x, 0.0, look_fwd.z)
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD

## Sens local du dash pour l'animation de roulade : x = droite, y = avant.
static func local_dash_dir(input_vector: Vector2) -> Vector2:
	var v := Vector2(input_vector.x, -input_vector.y)
	return v.normalized() if v.length_squared() > 0.01 else Vector2(0.0, 1.0)
