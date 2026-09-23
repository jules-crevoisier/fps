## net_smoke.gd
## Test réseau à DEUX processus (hôte + client) sur le terrain d'entraînement,
## en headless. Vérifie de bout en bout que les tirs légitimes passent et que
## les tirs tricheurs sont refusés par le serveur.
##   Hôte   : godot --headless --path . -s res://tools/net_smoke.gd -- --role=host
##   Client : godot --headless --path . -s res://tools/net_smoke.gd -- --role=client
## L'hôte affiche une ligne `NET_SMOKE_RESULT ...` puis quitte avec le code 0
## (succès) ou 1 (échec). Le client affiche ce qu'il a envoyé.
extends SceneTree

const LEVEL := "res://scenes/levels/test_arena.tscn"
const HOST_TIMEOUT := 16.0
const CLIENT_TIMEOUT := 22.0  # le client reste connecté jusqu'au verdict de l'hôte
const VALID_SHOTS := 3
const BURST_SHOTS := 10

var _role: String = ""
var _t: float = 0.0
var _step: int = 0
var _step_t: float = 0.0
var _host_min_health: float = INF
var _expected_damage: float = 0.0

var _started: bool = false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			_role = a.get_slice("=", 1)

## Démarre le réseau à la première frame : pendant `_initialize` la racine
## n'est pas encore dans l'arbre, donc `multiplayer` n'existe pas encore.
func _start() -> void:
	_started = true
	var net := NetworkManager.get_net(self)
	if _role == "host":
		net.host()
		change_scene_to_file(LEVEL)
	elif _role == "client":
		net.connection_succeeded.connect(func() -> void: change_scene_to_file(LEVEL))
		net.join("127.0.0.1")
	else:
		push_error("net_smoke : --role=host|client requis")
		quit(2)

func _process(delta: float) -> bool:
	if not _started:
		_start()
		return false
	_t += delta
	if _role == "host":
		return _host_tick()
	return _client_tick(delta)

func _players() -> Node:
	return current_scene.get_node_or_null("Players") if current_scene else null

# ---------------------------------------------------------------- HÔTE
func _host_tick() -> bool:
	var players := _players()
	if players:
		var me := players.get_node_or_null("1")
		if me:
			var hp := me.get_node("Health") as Health
			_host_min_health = minf(_host_min_health, hp.current_health)
	if _t < HOST_TIMEOUT:
		return false
	var client: Node = null
	if players:
		for p in players.get_children():
			if p.name != "1":
				client = p
	if client == null:
		print("NET_SMOKE_RESULT ok=false reason=no_client")
		quit(1)
		return true
	var w := client.get_node("Weapon") as Weapon
	var host_hp := (players.get_node("1").get_node("Health") as Health)
	var damage_taken := host_hp.max_health - _host_min_health
	var agent_ok: bool = int(client.get("agent_index")) >= 0
	# 3 tirs valides + 2 en rafale acceptés (burst) ; le reste doit être refusé.
	var ok := damage_taken > 0.0 and w.rejected_shots >= 2 + (BURST_SHOTS - 2) and agent_ok
	print("NET_SMOKE_RESULT ok=%s damage_taken=%.1f rejected_shots=%d agent_index=%d" % [
		ok, damage_taken, w.rejected_shots, int(client.get("agent_index"))])
	quit(0 if ok else 1)
	return true

# ---------------------------------------------------------------- CLIENT
func _client_tick(delta: float) -> bool:
	if _t > CLIENT_TIMEOUT:
		quit(0)
		return true
	var peer := get_multiplayer().multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	var players := _players()
	if players == null:
		return false
	var me := players.get_node_or_null(str(get_multiplayer().get_unique_id())) as PlayerController
	var host := players.get_node_or_null("1") as PlayerController
	if me == null or host == null:
		return false
	var w := me.get_node("Weapon") as Weapon
	_step_t += delta
	match _step:
		0:
			# Se place à 4 m de l'hôte (mouvement client-autoritaire, répliqué).
			if _step_t > 1.0:
				me.global_position = host.global_position + Vector3(0, 0, 4)
				me.velocity = Vector3.ZERO
				_next()
		1:
			if _step_t > 0.8:
				_next()
		2, 3, 4:
			# Tirs légitimes, espacés au-delà de la cadence.
			if _step_t > 0.35:
				_fire(w, me, host, w._inv.current_id(), Vector3.ZERO)
				_next()
		5:
			# Triche A : arme non possédée (sniper).
			_fire(w, me, host, WeaponDatabase.PATHS.size() - 1, Vector3.ZERO)
			_next()
		6:
			# Triche B : origine à 50 m au-dessus de la tête.
			if _step_t > 0.4:
				_fire(w, me, host, w._inv.current_id(), Vector3(0, 50, 0))
				_next()
		7:
			# Triche C : rafale au-delà de la cadence (même frame).
			if _step_t > 0.4:
				for i in BURST_SHOTS:
					_fire(w, me, host, w._inv.current_id(), Vector3.ZERO)
				_next()
		8:
			# Triche D : usurpation — tirer « au nom » de l'hôte via SON nœud Weapon.
			if _step_t > 0.4:
				var origin := host.global_position + Vector3(0, 1.6, 0)
				var hw := host.get_node("Weapon") as Weapon
				hw.request_fire.rpc_id(1, origin, [Vector3.FORWARD], WeaponDatabase.default_loadout_ids()[0])
				print("NET_SMOKE_CLIENT sent all steps, expected_valid_damage=%.1f" % _expected_damage)
				_next()
	return false

func _next() -> void:
	_step += 1
	_step_t = 0.0

func _fire(w: Weapon, me: PlayerController, host: PlayerController, weapon_id: int, origin_offset: Vector3) -> void:
	var origin := me.camera.global_position + origin_offset
	var target := host.global_position + Vector3(0, 1.0, 0)
	var dir := (target - me.camera.global_position).normalized()
	w._inv.consume_round()
	w._do_request_fire(origin, [dir], weapon_id)
	var c := WeaponDatabase.get_by_id(weapon_id)
	if c and origin_offset == Vector3.ZERO and _step <= 4:
		_expected_damage += WeaponMath.damage_at(origin.distance_to(target), c)
