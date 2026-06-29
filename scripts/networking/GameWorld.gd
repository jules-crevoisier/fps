## GameWorld.gd
## Gère le cycle de vie des joueurs dans un niveau. À placer sur la racine du
## niveau. S'appuie sur un MultiplayerSpawner (enfant "PlayerSpawner") qui
## réplique automatiquement les instances de player.tscn sur tous les pairs.
##
## Le serveur fait autorité sur le spawn ; il assigne l'autorité multijoueur de
## chaque joueur à son pair propriétaire pour que chacun pilote son perso.
extends Node3D

@export var player_scene: PackedScene
@export var players_root: NodePath = "Players"
@export var spawn_points_root: NodePath = "SpawnPoints"

var _next_spawn: int = 0

func _ready() -> void:
	# Le serveur écoute les connexions/déconnexions pour (dé)spawner.
	Net.player_connected.connect(_on_player_connected)
	Net.player_disconnected.connect(_on_player_disconnected)

	if multiplayer.multiplayer_peer == null:
		# Lancé sans réseau (test solo dans l'éditeur) : on héberge localement.
		Net.host()

	if multiplayer.is_server():
		# Spawn du joueur hôte (id 1).
		_spawn_player(multiplayer.get_unique_id())

func _on_player_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(id)

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
	var player := player_scene.instantiate()
	player.name = str(id)  # nom = id => le spawner le réplique proprement.
	get_node(players_root).add_child(player, true)
	# Autorité au pair propriétaire (il pilote ses entrées).
	player.set_multiplayer_authority(id)
	player.global_position = _get_spawn_position()

func _get_spawn_position() -> Vector3:
	var root := get_node_or_null(spawn_points_root)
	if root == null or root.get_child_count() == 0:
		return Vector3(0, 1.5, 0)
	var points := root.get_children()
	var p: Node3D = points[_next_spawn % points.size()]
	_next_spawn += 1
	return p.global_position
