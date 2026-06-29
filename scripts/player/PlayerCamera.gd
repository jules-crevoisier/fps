## PlayerCamera.gd
## Effets de caméra réactifs au mouvement : FOV dynamique (sprint/slide),
## inclinaison (tilt) en strafe, et head-bob au sol. Branche-toi sur le
## PlayerController parent. À mettre sur le Camera3D.
extends Camera3D

@export var player_path: NodePath
var player: PlayerController
var config: MovementConfig

var _bob_time: float = 0.0
var _base_local_pos: Vector3

# Roulade (effet "machine à laver")
var _roll_t: float = -1.0
var _roll_dur: float = 0.65
var _roll_turns: float = 1.0
var _dizzy_t: float = 0.0

## Lance l'animation de roulade : la caméra fait `turns` tour(s) complet(s)
## en `dur` secondes. Appelé par l'état Roll.
func play_roll(dur: float, turns: float = 1.0) -> void:
	_roll_dur = max(dur, 0.05)
	_roll_turns = turns
	_roll_t = 0.0

func _ready() -> void:
	if not player_path.is_empty():
		player = get_node(player_path) as PlayerController
	else:
		player = get_parent().get_parent() as PlayerController
	if player:
		config = player.config
		fov = config.base_fov
	_base_local_pos = position

func _process(delta: float) -> void:
	if player == null or not player.is_multiplayer_authority():
		return
	_update_fov(delta)
	# Pendant la roulade, le spin pilote la rotation X (on saute tilt + bob).
	if _roll_t >= 0.0:
		_update_roll(delta)
		return
	# Pendant le stun : caméra qui tangue (tête qui tourne).
	if player.state_machine.current_name == "Stun":
		_dizzy_t += delta
		rotation.z = deg_to_rad(5.0) * sin(_dizzy_t * 7.0)
		return
	_update_tilt(delta)
	_update_bob(delta)

func _update_roll(delta: float) -> void:
	_roll_t += delta
	var p := clampf(_roll_t / _roll_dur, 0.0, 1.0)
	var eased := p * p * (3.0 - 2.0 * p)  # smoothstep : accélère puis ralentit
	# Galipette AVANT : rotation autour de l'axe X (tangage), dans le plan vertical.
	rotation.x = -TAU * _roll_turns * eased
	if p >= 1.0:
		_roll_t = -1.0
		rotation.x = 0.0

func _update_fov(delta: float) -> void:
	var target := config.base_fov
	var sm := player.state_machine.current_name
	if sm == "Sprint":
		target += config.sprint_fov_add
	elif sm == "Slide":
		target += config.slide_fov_add
	# Léger bonus de FOV proportionnel à la survitesse.
	var over := player.horizontal_speed() - config.sprint_speed
	if over > 0.0:
		target += clamp(over * 0.6, 0.0, config.speed_fov_add)
	fov = lerp(fov, target, config.fov_lerp_speed * delta)

func _update_tilt(delta: float) -> void:
	# Roule la caméra dans le sens du strafe (renforcé pendant le slide).
	var tilt := config.strafe_tilt
	if player.state_machine.current_name == "Slide":
		tilt += config.slide_tilt
	var target_roll := -player.input_vector.x * deg_to_rad(tilt)
	rotation.z = lerp(rotation.z, target_roll, config.tilt_lerp_speed * delta)

func _update_bob(delta: float) -> void:
	var grounded := player.is_on_floor()
	var speed := player.horizontal_speed()
	if grounded and speed > 0.5 and player.state_machine.current_name != "Slide":
		_bob_time += delta * config.bob_frequency * clamp(speed / config.sprint_speed, 0.4, 1.4)
		var offset_y := sin(_bob_time) * config.bob_amplitude
		var offset_x := cos(_bob_time * 0.5) * config.bob_amplitude * 0.6
		position = _base_local_pos + Vector3(offset_x, offset_y, 0.0)
	else:
		_bob_time = 0.0
		position = position.lerp(_base_local_pos, 10.0 * delta)
