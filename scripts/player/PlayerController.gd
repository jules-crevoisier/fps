## PlayerController.gd
## Contrôleur joueur FPS — CharacterBody3D.
## Contient l'état physique partagé + les helpers de mouvement (accel/friction
## façon Source, gravité, saut bufferisé/coyote, gestion crouch). La LOGIQUE
## de chaque mode de déplacement vit dans les états (scripts/player/states).
## Compatible multijoueur : seul le pair propriétaire simule les entrées.
class_name PlayerController
extends CharacterBody3D

@export var config: MovementConfig

# --- Références de scène ---
@onready var head: Node3D = %Head
@onready var camera: Camera3D = %Camera3D
@onready var collision: CollisionShape3D = %Collision
@onready var ceiling_check: RayCast3D = %CeilingCheck
@onready var state_machine: PlayerStateMachine = %StateMachine
@onready var stun_stars: Node3D = get_node_or_null("%StunStars")

# --- État partagé entre les states ---
var wish_dir: Vector3 = Vector3.ZERO      ## Direction voulue (monde), normalisée.
var input_vector: Vector2 = Vector2.ZERO  ## Entrée brute (x = strafe, y = avant/arrière).
var is_crouching: bool = false
var current_height: float = 0.0
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false
var slide_jumped: bool = false  ## Vrai juste après un slide-jump (pour le slide-hop).
var _air_peak_y: float = 0.0    ## Altitude max atteinte en l'air (pour la hauteur de chute).
var _roll_buffer_timer: float = 0.0  ## Roulade d'atterrissage mémorisée (anti-stun).

## Une roulade d'atterrissage a-t-elle été déclenchée au bon timing ?
func land_roll_buffered() -> bool:
	return _roll_buffer_timer > 0.0

func consume_roll_buffer() -> void:
	_roll_buffer_timer = 0.0

@export var fall_limit: float = -40.0   ## Sous cette altitude => respawn.
var spawn_point: Vector3 = Vector3(0, 2, 0)
var team: int = 0                        ## Équipe assignée par le serveur.

# Recul (vrai recoil : déplace la visée, puis récupère).
var _recoil_target: Vector2 = Vector2.ZERO   # x = pitch (haut), y = yaw
var _recoil_applied: Vector2 = Vector2.ZERO
var _recoil_recovery: float = 7.0

## Ajoute un kick de recul (radians). Appelé par l'arme à chaque tir.
func add_recoil(pitch: float, yaw: float, recovery: float) -> void:
	_recoil_target += Vector2(pitch, yaw)
	_recoil_recovery = recovery

func _update_recoil(delta: float) -> void:
	# Récupération : la cible revient vers 0, ce qui ramène la visée.
	_recoil_target = _recoil_target.lerp(Vector2.ZERO, clampf(_recoil_recovery * delta, 0.0, 1.0))
	var new_applied := _recoil_applied.lerp(_recoil_target, clampf(22.0 * delta, 0.0, 1.0))
	var d := new_applied - _recoil_applied
	head.rotation.x = clamp(head.rotation.x + d.x, deg_to_rad(-89), deg_to_rad(89))
	rotate_y(d.y)
	_recoil_applied = new_applied

## L'autorité multijoueur DOIT être réglée dans _enter_tree (pas _ready), sinon le
## MultiplayerSynchronizer ne peut pas traiter le spawn (erreur "no network ID").
## Nom du nœud = id du peer propriétaire (identique sur tous les pairs). Le
## mouvement/caméra appartient à ce peer ; la vie (Health) est forcée sur le
## SERVEUR (peer 1) pour rester autoritaire.
func _enter_tree() -> void:
	var owner_id := str(name).to_int()
	if owner_id > 0:
		set_multiplayer_authority(owner_id)  # récursif (corps, synchronizer, arme)
	var hp := get_node_or_null("Health")
	if hp:
		hp.set_multiplayer_authority(1)

func _ready() -> void:
	if config == null:
		config = MovementConfig.new()
		push_warning("Aucun MovementConfig assigné — valeurs par défaut utilisées.")
	current_height = config.stand_height
	_air_peak_y = global_position.y
	spawn_point = global_position  # point de respawn par défaut = position de départ

	# Réglages sol pour un mouvement fluide sur les pentes (slide qui glisse,
	# pas de blocage en haut de pente, vitesse conservée aux ruptures de pente).
	floor_stop_on_slope = false
	floor_constant_speed = true
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(52)

	state_machine.setup(self)

	# En multijoueur, seul le propriétaire pilote sa caméra + input.
	var mine := is_multiplayer_authority()
	camera.current = mine
	if mine:
		add_to_group("local_player")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative)
	state_machine.handle_input(event)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if global_position.y < fall_limit:
		respawn()
		return
	# Mort : on fige le joueur (pas d'input/action) jusqu'au respawn serveur.
	var hp := get_node_or_null("Health") as Health
	if hp and hp.is_dead:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= config.gravity * delta
		move_and_slide()
		return
	_read_input()
	_gamepad_look(delta)
	_update_recoil(delta)
	_update_timers(delta)
	state_machine.physics_update(delta)
	_update_crouch_height(delta)
	move_and_slide()
	_check_fall_stun()
	_was_on_floor = is_on_floor()

## Visée à la manette (stick droit). Gelée si un menu est ouvert.
func _gamepad_look(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	var dz := 0.15
	if absf(rx) < dz: rx = 0.0
	if absf(ry) < dz: ry = 0.0
	if rx == 0.0 and ry == 0.0:
		return
	if Settings.invert_y:
		ry = -ry
	rotate_y(-rx * Settings.gamepad_sensitivity * delta)
	head.rotate_x(-ry * Settings.gamepad_sensitivity * delta)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

## Suit la hauteur de chute et déclenche un stun à l'atterrissage si trop haut.
## Rouler (Dive/Roll) absorbe la chute : pas de stun.
func _check_fall_stun() -> void:
	if is_on_floor():
		if not _was_on_floor:
			# Atterrissage. La roulade (buffer "dive" au bon timing) est PRIORITAIRE
			# sur le stun : on doit la tester ici car la détection du sol par
			# move_and_slide arrive avant que l'état Air n'ait sa frame.
			if land_roll_buffered():
				consume_roll_buffer()
				if state_machine.current_name != "Roll":
					state_machine.transition_to("Roll")
			else:
				_maybe_stun(_air_peak_y - global_position.y)
		_air_peak_y = global_position.y
	else:
		_air_peak_y = max(_air_peak_y, global_position.y)

func _maybe_stun(fall_height: float) -> void:
	if not config.stun_enabled or fall_height < config.fall_min_height:
		return
	var s := state_machine.current_name
	if s == "Roll" or s == "Dive" or s == "Stun":
		return  # la roulade absorbe l'impact
	var t: float = remap(fall_height, config.fall_min_height, config.fall_max_height, config.stun_min_time, config.stun_max_time)
	t = clampf(t, config.stun_min_time, config.stun_max_time)
	state_machine.transition_to("Stun", {"duration": t})

# ------------------------------------------------------------------
#  ENTRÉES
# ------------------------------------------------------------------
func _read_input() -> void:
	# Si la souris est libérée (menu pause/options ouvert), on ignore les entrées.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		input_vector = Vector2.ZERO
		wish_dir = Vector3.ZERO
		return
	input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Direction voulue relative à l'orientation du joueur (yaw sur le body).
	var basis_dir := (global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y))
	wish_dir = Vector3(basis_dir.x, 0.0, basis_dir.z).normalized()
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = config.jump_buffer_time
	# Appuyer sur "dive" EN L'AIR mémorise une roulade d'atterrissage (anti-stun).
	# Plus on tombe vite (chute haute), plus la fenêtre est large => plus facile.
	if Input.is_action_just_pressed("dive") and not is_on_floor():
		var fall_speed: float = max(-velocity.y, 0.0)
		var f: float = clampf(fall_speed / config.land_roll_fast_speed, 0.0, 1.0)
		_roll_buffer_timer = lerpf(config.land_roll_window, config.land_roll_window_max, f)

func _look(relative: Vector2) -> void:
	rotate_y(-relative.x * Settings.mouse_sensitivity)
	head.rotate_x(-relative.y * Settings.mouse_sensitivity)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

## Replace le joueur au point de spawn (chute hors map, etc.).
func respawn() -> void:
	velocity = Vector3.ZERO
	global_position = spawn_point
	if state_machine:
		state_machine.transition_to("Idle")

## Respawn réseau : le SERVEUR appelle ceci sur le PROPRIÉTAIRE (rpc_id) pour le
## téléporter — nécessaire car le mouvement est client-autoritaire (le serveur ne
## peut pas changer directement la position d'un autre pair).
@rpc("any_peer", "call_local", "reliable")
func net_respawn(pos: Vector3) -> void:
	spawn_point = pos
	velocity = Vector3.ZERO
	global_position = pos
	if state_machine:
		state_machine.transition_to("Idle")

# ------------------------------------------------------------------
#  HELPERS DE MOUVEMENT (utilisés par les states)
# ------------------------------------------------------------------
## Accélération style Source : ne pousse que la composante manquante vers wish_speed.
## Donne l'air-strafe fluide quand accel/friction sont bas en l'air.
func accelerate(dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	var current_speed := velocity.dot(dir)
	var add_speed := wish_speed - current_speed
	if add_speed <= 0.0:
		return
	var accel_speed: float = min(accel * wish_speed * delta, add_speed)
	velocity.x += accel_speed * dir.x
	velocity.z += accel_speed * dir.z

## Mouvement SOL façon CoD : réponse sèche et instantanée (move_toward linéaire).
## `target_speed` = vitesse visée ; `accel`/`friction` en m/s^2.
func ground_move(target_speed: float, accel: float, friction: float, delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir != Vector3.ZERO:
		hv = hv.move_toward(wish_dir * target_speed, accel * delta)
	else:
		hv = hv.move_toward(Vector3.ZERO, friction * delta)
	velocity.x = hv.x
	velocity.z = hv.z

## Contrôle directionnel DIRECT en l'air : freine / réoriente vers wish_dir.
## Toute AUGMENTATION de vitesse est ramenée à la vitesse d'entrée → ce contrôle
## ne crée pas de vitesse (il freine et fait tourner la trajectoire), le gain
## restant réservé à l'air-strafe (accelerate).
func air_control_move(strength: float, delta: float) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var before := hv.length()
	hv += wish_dir * strength * delta
	if hv.length() > before:
		hv = hv.normalized() * before
	velocity.x = hv.x
	velocity.z = hv.z

## Redirige le vecteur vitesse horizontal vers `dir` SANS changer sa norme.
## C'est ce qui donne le côté fluide / tap-strafe : on tourne sa course en
## conservant toute la vitesse. `rate` = vitesse de rotation (rad/s approx).
func redirect_velocity(dir: Vector3, rate: float, delta: float) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horiz.length()
	if speed < 0.5 or dir == Vector3.ZERO:
		return
	var cur_dir := horiz / speed
	var new_dir := cur_dir.slerp(dir.normalized(), clamp(rate * delta, 0.0, 1.0)).normalized()
	velocity.x = new_dir.x * speed
	velocity.z = new_dir.z * speed

## Friction horizontale (décélération exponentielle stable).
func apply_friction(friction: float, delta: float) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horiz.length()
	if speed < 0.01:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var drop := speed * friction * delta
	var new_speed: float = max(speed - drop, 0.0)
	var factor := new_speed / speed
	velocity.x *= factor
	velocity.z *= factor

func apply_gravity(delta: float) -> void:
	var g := config.gravity
	if velocity.y < 0.0:
		g *= config.fall_gravity_mult
	velocity.y -= g * delta

func horizontal_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)

func horizontal_speed() -> float:
	return horizontal_velocity().length()

## Le joueur peut-il sauter ? (au sol OU dans la fenêtre coyote)
func can_jump() -> bool:
	return is_on_floor() or _coyote_timer > 0.0

## Y a-t-il un saut bufferisé en attente ?
func jump_buffered() -> bool:
	return _jump_buffer_timer > 0.0

## Exécute le saut. Le momentum horizontal est TOUJOURS conservé (style Apex).
func do_jump() -> void:
	velocity.y = config.jump_velocity
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0

## Y a-t-il un obstacle au-dessus empêchant de se relever ?
func is_blocked_above() -> bool:
	return ceiling_check.is_colliding()

func set_crouching(value: bool) -> void:
	is_crouching = value

func _update_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = config.coyote_time
	else:
		_coyote_timer = max(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = max(_jump_buffer_timer - delta, 0.0)
	_roll_buffer_timer = max(_roll_buffer_timer - delta, 0.0)

func _update_crouch_height(delta: float) -> void:
	var target := config.crouch_height if is_crouching else config.stand_height
	current_height = lerp(current_height, target, config.crouch_lerp_speed * delta)
	var shape := collision.shape
	if shape is CapsuleShape3D:
		shape.height = current_height
		collision.position.y = current_height * 0.5
	# La tête suit la hauteur (légèrement sous le sommet).
	head.position.y = current_height - 0.2
