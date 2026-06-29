## AbilityController.gd
## Gère les capacités de l'agent du joueur : entrées (C/Q/E/X), cooldowns,
## charges et points d'ultime. À mettre en enfant du joueur (nom "Abilities").
## Les capacités s'exécutent côté propriétaire (mouvement local) ; les effets de
## vie passent par un RPC serveur (voir HealAbility).
class_name AbilityController
extends Node

var player: PlayerController
var agent: AgentConfig

var _charges: Array = []   # charges restantes par capacité
var _cd: Array = []        # timer de cooldown par capacité
var _ult_points: float = 0.0
var _ult_charge_rate: float = 0.45  # points/s (placeholder ; + sur les kills plus tard)

func _ready() -> void:
	player = get_parent() as PlayerController
	agent = AgentDatabase.selected()
	_setup()

func _setup() -> void:
	_charges.clear()
	_cd.clear()
	for ab in agent.abilities:
		_charges.append(ab.charges)
		_cd.append(0.0)
	_ult_points = 0.0

func _process(delta: float) -> void:
	if player == null or not player.is_multiplayer_authority() or agent == null:
		return

	for i in agent.abilities.size():
		var ab: Ability = agent.abilities[i]
		if ab.is_ultimate:
			if _ult_points < ab.ult_cost:
				_ult_points = minf(_ult_points + delta * _ult_charge_rate, float(ab.ult_cost))
		elif _charges[i] < ab.charges and _cd[i] > 0.0:
			_cd[i] -= delta
			if _cd[i] <= 0.0:
				_charges[i] += 1
				if _charges[i] < ab.charges:
					_cd[i] = ab.cooldown

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	for i in agent.abilities.size():
		var action := _action_for(agent.abilities[i].slot)
		if action != "" and Input.is_action_just_pressed(action):
			_try_activate(i)

func _action_for(slot: String) -> String:
	match slot:
		"C": return "ability_c"
		"Q": return "ability_q"
		"E": return "ability_e"
		"X": return "ultimate"
	return ""

func _try_activate(i: int) -> void:
	var ab: Ability = agent.abilities[i]
	if ab.is_ultimate:
		if _ult_points >= ab.ult_cost:
			ab.activate(player)
			_ult_points = 0.0
	elif _charges[i] > 0:
		var was_full: bool = _charges[i] >= ab.charges
		_charges[i] -= 1
		if was_full:
			_cd[i] = ab.cooldown
		ab.activate(player)

## Charge l'ultime (appelé par le serveur sur le tueur, ex. sur un kill).
@rpc("any_peer", "call_local", "reliable")
func add_ult(amount: float) -> void:
	if agent == null:
		return
	for ab in agent.abilities:
		if ab.is_ultimate:
			_ult_points = minf(_ult_points + amount, float(ab.ult_cost))
			return

## Spawn d'une barrière (mur) RÉPLIQUÉE : appelé par une capacité côté propriétaire,
## construit le mur sur TOUS les pairs (visible + bloquant partout, serveur inclus).
func cast_barrier(pos: Vector3, fwd: Vector3, size: Vector3, duration: float, color: Color) -> void:
	_spawn_barrier.rpc(pos, fwd, size, duration, color)

@rpc("any_peer", "call_local", "reliable")
func _spawn_barrier(pos: Vector3, fwd: Vector3, size: Vector3, duration: float, color: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var wall := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	wall.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.6
	mat.emission_energy_multiplier = 1.5
	mesh.material_override = mat
	wall.add_child(mesh)
	scene.add_child(wall)
	wall.global_position = pos
	wall.look_at(pos + fwd, Vector3.UP)
	var t := scene.get_tree().create_timer(duration)
	t.timeout.connect(func(): if is_instance_valid(wall): wall.queue_free())

## Pour le HUD : état de chaque capacité.
func slot_info() -> Array:
	var out: Array = []
	for i in agent.abilities.size():
		var ab: Ability = agent.abilities[i]
		if ab.is_ultimate:
			out.append({
				"slot": ab.slot, "name": ab.display_name, "ult": true,
				"ready": _ult_points >= ab.ult_cost,
				"ratio": _ult_points / float(ab.ult_cost), "charges": 0,
			})
		else:
			var ratio := 1.0
			if ab.cooldown > 0.0 and _charges[i] < ab.charges:
				ratio = 1.0 - clampf(_cd[i] / ab.cooldown, 0.0, 1.0)
			out.append({
				"slot": ab.slot, "name": ab.display_name, "ult": false,
				"ready": _charges[i] > 0, "ratio": ratio, "charges": _charges[i],
			})
	return out
