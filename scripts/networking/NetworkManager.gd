## NetworkManager.gd  (Autoload : "Net")
## Couche réseau minimale basée sur ENet + l'API multijoueur haut-niveau de Godot.
## - host() : démarre un serveur (qui est aussi joueur).
## - join() : se connecte à un serveur.
## Le spawn effectif des joueurs est géré par le MultiplayerSpawner de la scène
## de niveau (voir GameWorld.gd).
extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_started
signal connection_failed
signal connection_succeeded

const DEFAULT_PORT: int = 7777
const DEFAULT_IP: String = "127.0.0.1"
const MAX_PLAYERS: int = 16

var peer: ENetMultiplayerPeer

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): connection_succeeded.emit())
	multiplayer.connection_failed.connect(func(): connection_failed.emit())

func host(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Échec création serveur: %s" % err)
		return err
	multiplayer.multiplayer_peer = peer
	server_started.emit()
	return OK

func join(ip: String = DEFAULT_IP, port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("Échec connexion: %s" % err)
		return err
	multiplayer.multiplayer_peer = peer
	return OK

func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	player_disconnected.emit(id)
