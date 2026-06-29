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

# --- État partagé entre les states ---
var wish_dir: Vector3 = Vector3.ZERO      ## Direction voulue (monde), normalisée.
var input_vector: Vector2 = Vector2.ZERO  ## Entrée brute (x = strafe, y = avant/arrière).
var is_crouching: bool = false
var current_height: float = 0.0
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false
var slide_cooldown_timer: float = 0.0  ## Empêche un nouveau slide tant que > 0.

## Un slide est-il autorisé maintenant ?
func can_slide() -> bool:
	return slide_cooldown_timer <= 0.0

func _ready() -> void:
	if config == null:
		config = MovementConfig.new()
		push_warning("Aucun MovementConfig assigné — valeurs par défaut utilisées.")
	current_height = config.stand_height
	state_machine.setup(self)

	# En multijoueur, seul le propriétaire pilote sa caméra + input.
	var mine := is_multiplayer_authority()
	camera.current = mine
	if mine:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	state_machine.handle_input(event)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_read_input()
	_update_timers(delta)
	state_machine.physics_update(delta)
	_update_crouch_height(delta)
	move_and_slide()
	_was_on_floor = is_on_floor()

# ------------------------------------------------------------------
#  ENTRÉES
# ------------------------------------------------------------------
func _read_input() -> void:
	input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Direction voulue relative à l'orientation du joueur (yaw sur le body).
	var basis_dir := (global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y))
	wish_dir = Vector3(basis_dir.x, 0.0, basis_dir.z).normalized()
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = config.jump_buffer_time

func _look(relative: Vector2) -> void:
	rotate_y(-relative.x * config.mouse_sensitivity)
	head.rotate_x(-relative.y * config.mouse_sensitivity)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

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
	var scale := new_speed / speed
	velocity.x *= scale
	velocity.z *= scale

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

## Exécute le saut en conservant (ou non) le momentum horizontal.
func do_jump() -> void:
	velocity.y = config.jump_velocity
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	if not config.preserve_momentum_on_jump:
		velocity.x = 0.0
		velocity.z = 0.0

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
	slide_cooldown_timer = max(slide_cooldown_timer - delta, 0.0)

func _update_crouch_height(delta: float) -> void:
	var target := config.crouch_height if is_crouching else config.stand_height
	current_height = lerp(current_height, target, config.crouch_lerp_speed * delta)
	var shape := collision.shape
	if shape is CapsuleShape3D:
		shape.height = current_height
		collision.position.y = current_height * 0.5
	# La tête suit la hauteur (légèrement sous le sommet).
	head.position.y = current_height - 0.2
