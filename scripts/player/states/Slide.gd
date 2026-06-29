## Slide — glissade rapide avec momentum, accélération en descente, et SLIDE CANCEL.
##
## Slide cancel : re-tapper "crouch" (ou sauter) pendant le slide l'annule en
## conservant le momentum, sans cooldown par défaut -> on peut enchaîner
## slide → cancel → slide pour entretenir une vitesse élevée (façon Apex/CoD).
extends PlayerState

var _timer: float = 0.0
var _slide_dir: Vector3 = Vector3.ZERO

func enter(_from: String, _msg: Dictionary = {}) -> void:
	player.set_crouching(true)
	_timer = 0.0
	# Direction figée au début du slide (on garde le cap, steer limité ensuite).
	_slide_dir = player.horizontal_velocity().normalized()
	if _slide_dir == Vector3.ZERO:
		_slide_dir = -player.global_transform.basis.z

	# Boost initial, plafonné.
	var speed: float = player.horizontal_speed() + config.slide_boost
	speed = min(speed, config.slide_max_speed)
	player.velocity.x = _slide_dir.x * speed
	player.velocity.z = _slide_dir.z * speed

func physics_update(delta: float) -> void:
	_timer += delta
	player.apply_gravity(delta)

	# Quitter le sol => on passe en l'air en gardant toute la vitesse.
	if not player.is_on_floor():
		transition_to("Air")
		return

	# Accélération en descente (le slide prend de la vitesse dans les pentes).
	var floor_normal := player.get_floor_normal()
	var slope := Vector3(floor_normal.x, 0.0, floor_normal.z)
	if slope.length() > 0.01:
		var downhill := slope.normalized()
		# Si on glisse vers le bas de la pente, on accélère.
		if _slide_dir.dot(downhill) > 0.0:
			player.velocity.x += downhill.x * config.slide_slope_accel * delta
			player.velocity.z += downhill.z * config.slide_slope_accel * delta

	# Steer limité : on peut infléchir légèrement la trajectoire.
	if player.wish_dir != Vector3.ZERO and config.slide_steer > 0.0:
		var spd := player.horizontal_speed()
		var new_dir := player.horizontal_velocity().normalized().lerp(player.wish_dir, config.slide_steer * delta * 10.0).normalized()
		player.velocity.x = new_dir.x * spd
		player.velocity.z = new_dir.z * spd
		_slide_dir = new_dir

	# Friction du slide.
	player.apply_friction(config.slide_friction, delta)

	# Plafonner à la vitesse max de slide.
	var cur := player.horizontal_speed()
	if cur > config.slide_max_speed:
		var n := player.horizontal_velocity().normalized()
		player.velocity.x = n.x * config.slide_max_speed
		player.velocity.z = n.z * config.slide_max_speed

	# --- Saut depuis le slide : annule en gardant le momentum, part en l'air ---
	if player.jump_buffered() and player.can_jump():
		_end_slide(true)
		player.do_jump()
		transition_to("Air")
		return

	# --- SLIDE CANCEL : re-tap de crouch pendant le slide ---
	if config.slide_cancel_enabled and Input.is_action_just_pressed("crouch"):
		_end_slide(true)
		_exit_to_ground()
		return

	# Fin naturelle : durée dépassée, trop lent, ou crouch relâché.
	var too_slow := player.horizontal_speed() < config.slide_min_speed * 0.6
	if _timer >= config.slide_max_time or too_slow or not Input.is_action_pressed("crouch"):
		var clean_release := not Input.is_action_pressed("crouch")
		_end_slide(clean_release)
		if Input.is_action_pressed("crouch"):
			transition_to("Crouch")
		else:
			_exit_to_ground()

## Termine le slide. `keep_momentum` true conserve la vitesse (cancel propre).
func _end_slide(keep_momentum: bool) -> void:
	player.set_crouching(false)
	player.slide_cooldown_timer = config.slide_cooldown
	if keep_momentum:
		# Cancel dans la fenêtre = momentum total ; au-delà = fraction configurée.
		var keep := config.slide_cancel_keep if _timer <= config.slide_cancel_window else 0.9
		player.velocity.x *= keep
		player.velocity.z *= keep

func _exit_to_ground() -> void:
	if player.input_vector == Vector2.ZERO:
		transition_to("Idle")
	elif Input.is_action_pressed("sprint"):
		transition_to("Sprint")
	else:
		transition_to("Walk")
