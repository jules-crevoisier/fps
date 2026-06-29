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
	_update_tilt(delta)
	_update_bob(delta)

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
		var offset_x := cos(_