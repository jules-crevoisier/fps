## GameWorld.gd
## Gère le cycle de vie des joueurs : spawn, équipes, mort et respawn.
## À placer sur la racine du niveau. S'appuie sur un MultiplayerSpawner
## (enfant "PlayerSpawner") qui réplique player.tscn sur tous les pairs.
##
## Le SERVEUR fait autorité : spawn, assignation d'équipe, et respawn après mort
## (déclenché par le signal Health.died, lui aussi côté serveur).
extends Node3D

@export var player_scene: PackedScene
@export var players_root: NodePath = "Players"
@export var spawn_points_root: NodePath = "SpawnPoints"
@export var respawn_delay: float = 3.0
@export var team_count: int = 2
## Afficher l'écran de sélection d'agent avant de spawn (false = spawn direct, ex. training).
@export var agent_select: bool = true

const AGENT_SELECT := preload("res://scripts/ui/AgentSelectScreen.gd")

signal stats_changed
signal kill_logged(killer: String, victim: String, killer_team: int)

## id du peer -> { name, team, kills, deaths }
var player_info: Dictionary = {}

var _spawn_index: int = 0
var _team_counter: int = 0

func _ready() -> void:
	set_multiplayer_authority(1)  # serveur autoritaire sur les stats/killfeed
	add_to_group("match")
	Settings.load_all()  # applique les touches/sensi/FOV sauvegardés
	var net := NetworkManager.get_net(get_tree())
	net.player_disconnected.connect(_on_player_disconnected)

	if multiplayer.multiplayer_peer == null:
		# Lancé sans réseau (test solo dans l'éditeur) : on héberge localement.
		net.host()

	if agent_select:
		_open_agent_select()
	else:
		_spawn_local()

func _open_agent_select() -> void:
	var screen := AGENT_SELECT.new()
	add_child(screen)
	screen.locked.connect(func():
		if is_instance_valid(screen):
			screen.queue_free()
		_spawn_local())

func _spawn_local() -> void:
	if multiplayer.is_server():
		_spawn_player(multiplayer.get_unique_id())
	else:
		# Client : demande son spawn une fois SA map chargée (évite la course où
		# le serveur ferait spawn avant que le spawner du client existe).
		_request_spawn.rpc_id(1)

## Le client (sa scène prête) demande au serveur de le faire spawn.
@rpc("any_peer", "reliable")
func _request_spawn() -> void:
	if multiplayer.is_server():
		_spawn_player(multiplayer.get_remote_sender_id())

func _on_player_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var node := get_node(players_root).get_node_or_null(str(id))
	if node:
		node.queue_free()

func _spawn_player(id: int) -> void:
	if player_scene == null:
		push_error("player_scene non assignée sur GameWorld.")
		return
	# Anti double-spawn (si une demande arrive deux fois).
	if get_node(players_root).has_node(str(id)):
		return
	var player := player_scene.instantiate()
	player.name = str(id)  # nom = id => réplication propre par le spawner.
	# Équipe alternée.
	var team := _team_counter % team_count
	_team_counter += 1
	player.set("team", team)

	# Position de départ AVANT l'ajout à l'arbre : elle est répliquée par le
	# spawner (propriété "spawn") et lue par PlayerController._ready pour fixer
	# le point de respawn.
	var spawn := _get_spawn_position(team)
	player.position = spawn
	player.set("spawn_point", spawn)

	# L'autorité est réglée par PlayerController._ready (basée sur le nom = id),
	# de façon identique sur tous les pairs. On ne la force pas ici pour ne pas
	# créer d'incohérence serveur/clients.
	get_node(players_root).add_child(player, true)

	# Stats du joueur (serveur).
	player_info[id] = {"name": "Joueur %d" % id, "team": team, "kills": 0, "deaths": 0}
	_sync_stats.rpc(player_info)

	# Le serveur écoute la mort de ce joueur pour gérer le respawn.
	var hp := player.get_node_or_null("Health") as Health
	if hp:
		hp.died.connect(_on_player_died.bind(player))

func _on_player_died(killer_id: int, player: Node) -> void:
	if not multiplayer.is_server():
		return
	_record_kill(killer_id, str(player.name).to_int())
	# Respawn après délai.
	await get_tree().create_timer(respawn_delay).timeout
	if not is_instance_valid(player):
		return
	var team: int = player.get("team")
	var spawn := _get_spawn_position(team)
	# Téléportation envoyée au propriétaire (mouvement client-autoritaire).
	var owner_id := str(player.name).to_int()
	player.net_respawn.rpc_id(owner_id, spawn)
	var hp := player.get_node_or_null("Health") as Health
	if hp:
		hp.reset()

# ---- Kills / stats / killfeed (serveur) ----
func _record_kill(killer_id: int, victim_id: int) -> void:
	var vteam: int = int(player_info[victim_id].team) if player_info.has(victim_id) else -1
	if player_info.has(victim_id):
		player_info[victim_id].deaths += 1
	var kteam: int = -1
	if killer_id > 0 and killer_id != victim_id and player_info.has(killer_id):
		player_info[killer_id].kills += 1
		kteam = int(player_info[killer_id].team)
		_charge_ult(killer_id)
	# Le mode peut réagir (TDM : kill = point d'équipe).
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode and mode.has_method("on_kill"):
		mode.on_kill(killer_id, victim_id, kteam, vteam)
	# Killfeed.
	var kname: String = player_info[killer_id].name if (killer_id > 0 and player_info.has(killer_id)) else "Environnement"
	var vname: String = player_info[victim_id].name if player_info.has(victim_id) else "?"
	_killfeed.rpc(kname, vname, kteam)
	_sync_stats.rpc(player_info)

func _charge_ult(killer_id: int) -> void:
	var pnode := get_node(players_root).get_node_or_null(str(killer_id))
	if pnode:
		var ab := pnode.get_node_or_null("Abilities")
		if ab and ab.has_method("add_ult"):
			ab.add_ult.rpc_id(killer_id, 2.0)

@rpc("authority", "call_local", "reliable")
func _sync_stats(data: Dictionary) -> void:
	player_info = data
	stats_changed.emit()

@rpc("authority", "call_local", "reliable")
func _killfeed(killer: String, victim: String, killer_team: int) -> void:
	kill_logged.emit(killer, victim, killer_team)

## Rejouer (demandé par un client, exécuté par le serveur).
@rpc("any_peer", "reliable")
func request_reset() -> void:
	if multiplayer.is_server():
		reset_match()

func reset_match() -> void:
	if not multiplayer.is_server():
		return
	for id in player_info:
		player_info[id].kills = 0
		player_info[id].deaths = 0
	_sync_stats.rpc(player_info)
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode and mode.has_method("reset_match"):
		mode.reset_match()
	for child in get_node(players_root).get_children():
		var oid := str(child.name).to_int()
		var team := int(child.get("team"))
		var spawn := _get_spawn_position(team)
		child.net_respawn.rpc_id(oid, spawn)
		var hp := child.get_node_or_null("Health") as Health
		if hp:
			hp.reset()

func _get_spawn_position(team: int) -> Vector3:
	var root := get_node_or_null(spawn_points_root)
	if root == null or root.get_child_count() == 0:
		return Vector3(0, 1.5, 0)
	var points := root.get_children()
	# On répartit par équipe : on prend un point dont l'index correspond à l'équipe
	# si possible, sinon on cycle.
	var team_points: Array = []
	for p in points:
		if p.has_meta("team") and int(p.get_meta("team")) == team:
			team_points.append(p)
	if team_points.is_empty():
		team_points = points
	var chosen: Node3D = team_points[_spawn_index % team_points.size()]
	_spawn_index += 1
	return chosen.global_position
