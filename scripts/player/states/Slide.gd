## Slide — glissade. Modèle de contrôle simple et sans conflit de touche :
##  - RELÂCHER Ctrl pendant le slide = cancel (on se relève en gardant l'élan) ;
##  - TENIR Ctrl jusqu'au bout = on finit accroupi (relâcher Ctrl relève ensuite) ;
##  - SAUTER = slide-jump (conserve le momentum + petit pop).
## Le slide accélère dans les pentes descendantes (cœur du mouvement).
extends PlayerState

var _timer: float = 0.0
var _dir: Vector3 = Vector3.ZERO

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(true)
	_timer = 0.0
	_dir = player.horizontal_velocity().normalized()
	if _dir == Vector3.ZERO:
		_dir = -player.global_transform.basis.z

	var speed := player.horizontal_speed()
	if not player.slide_jumped:
		speed += config.slide_boost
	speed = min(speed, config.chain_speed_cap)
	player.slide_jumped = false
	player.velocity.x = _dir.x * speed
	player.velocity.z = _dir.z * speed

func physics_update(delta: float) -> void:
	_timer += delta
	player.apply_gravity(delta)

	if not player.is_on_floor():
		transition_to("Air")
		return

	# Accélération en descente.
	var n := player.get_floor_normal()
	var slope := Vector3(n.x, 0.0, n.z)
	if slope.length() > 0.01:
		var downhill := slope.normalized()
		if _dir.dot(downhill) > 0.0:
			player.velocity.x += downhill.x * config.slide_slope_accel * delta
			player.velocity.z += downhill.z * config.slide_slope_accel * delta

	# Steer limité.
	if player.wish_dir != Vector3.ZERO and config.slide_steer > 0.0:
		player.redirect_velocity(player.wish_dir, config.slide_steer * 12.0, delta)
		_dir = player.horizontal_velocity().normalized()

	player.apply_friction(config.slide_friction, delta)

	# Plafond de vitesse.
	if player.horizontal_speed() > config.slide_max_speed:
		var c := player.horizontal_velocity().normalized()
		player.velocity.x = c.x * config.slide_max_speed
		player.velocity.z = c.z * config.slide_max_speed

	# SLIDE-JUMP : sauter garde le momentum + petit pop.
	if player.jump_buffered() and player.can_jump():
		_keep_momentum()
		player.set_crouching(false)
		player.do_jump()
		player.velocity.y += config.slide_jump_pop
		player.slide_jumped = true
		transition_to("Air")
		return

	# CANCEL : relâcher Ctrl pendant le slide => on se relève en gardant l'élan.
	if not Input.is_action_pressed("crouch"):
		_keep_momentum()
		_exit_to_ground()
		return

	# Fin naturelle : durée écoulée ou trop lent (Ctrl encore tenu => on reste
	# accroupi ; relâcher Ctrl relèvera ensuite).
	var too_slow := player.horizontal_speed() < config.slide_min_speed * 0.6
	if _timer >= config.slide_max_time or too_slow:
		_exit_to_ground()

func _keep_momentum() -> void:
	player.velocity.x *= config.slide_keep
	player.velocity.z *= config.slide_keep

func _exit_to_ground() -> void:
	player.set_crouching(false)
	# Ctrl encore tenu => on s'accroupit (crouch en maintien : relâcher relève).
	if Input.is_action_pressed("crouch"):
		transition_to("Crouch")
		return
	if player.input_vector == Vector2.ZERO:
		transition_to("Idle")
	elif Input.is_action_pressed("walk"):
		transition_to("Walk")
	else:
		transition_to("Sprint")
