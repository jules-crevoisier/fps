## HealthServer.gd
## Petit serveur HTTP non bloquant (TCPServer) pour la sonde de santé Docker/
## Dokploy : `GET /health` répond 200 avec un JSON {status, players, mode,
## map, uptime_s} ; toute autre requête répond 404. Ajouté comme enfant de
## ServerBoot (pas un autoload) : `status_provider` (Callable -> Dictionary)
## est injectée par ServerBoot, qui connaît le monde de jeu — voir
## docs/SERVER.md. Ne plante jamais sur une entrée invalide : toute requête
## mal formée ou trop longue est simplement fermée (400/close), jamais une
## erreur GDScript.
class_name HealthServer
extends Node

## Taille max d'une requête avant qu'on la considère abusive et qu'on ferme
## la connexion (une requête `GET /health HTTP/1.1\r\n\r\n` tient en <40 o).
const MAX_REQUEST_BYTES := 8192
## Une connexion qui n'envoie rien au-delà de ce délai est fermée (évite une
## fuite de connexions TCP ouvertes par un client muet/scanner de port).
const CLIENT_TIMEOUT_SEC := 5.0

@export var port: int = 8080

## Callable() -> Dictionary {status, players, mode, map, uptime_s} — fournie
## par ServerBoot. Si absente/invalide, on répond un statut minimal.
var status_provider: Callable = Callable()

var _server := TCPServer.new()
## Chaque entrée : {"peer": StreamPeerTCP, "buffer": String, "age": float}
var _clients: Array = []

func _ready() -> void:
	var err := _server.listen(port)
	if err != OK:
		push_error("HealthServer : échec d'écoute sur le port %d (%s)" % [port, error_string(err)])

func _exit_tree() -> void:
	for c in _clients:
		(c["peer"] as StreamPeerTCP).disconnect_from_host()
	_clients.clear()
	_server.stop()

func _process(delta: float) -> void:
	while _server.is_connection_available():
		var tcp := _server.take_connection()
		if tcp:
			_clients.append({"peer": tcp, "buffer": "", "age": 0.0})

	# Parcours en arrière pour pouvoir retirer des entrées pendant l'itération.
	var i := _clients.size() - 1
	while i >= 0:
		if _pump_client(_clients[i], delta):
			_clients.remove_at(i)
		i -= 1

## Fait avancer une connexion d'un pas ; renvoie true si elle doit être retirée.
func _pump_client(c: Dictionary, delta: float) -> bool:
	var peer: StreamPeerTCP = c["peer"]
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return true

	var avail := peer.get_available_bytes()
	if avail <= 0:
		c["age"] += delta
		return c["age"] > CLIENT_TIMEOUT_SEC

	var res: Array = peer.get_data(avail)
	if res[0] == OK:
		var chunk: PackedByteArray = res[1]
		c["buffer"] += chunk.get_string_from_utf8()

	var buffer: String = c["buffer"]
	if buffer.length() > MAX_REQUEST_BYTES:
		_respond(peer, 400, "Bad Request", "")
		return true
	if buffer.contains("\r\n\r\n") or buffer.contains("\n\n"):
		_handle_request(peer, buffer)
		return true
	return false

## Ne lit QUE la ligne de requête ("GET /health HTTP/1.1") — les en-têtes ne
## nous intéressent pas. Toute forme inattendue (ligne vide, un seul mot,
## verbe/chemin absents) répond 400 plutôt que de planter.
func _handle_request(peer: StreamPeerTCP, raw: String) -> void:
	var lines := raw.split("\n")
	if lines.is_empty():
		_respond(peer, 400, "Bad Request", "")
		return
	var parts := lines[0].strip_edges().split(" ")
	if parts.size() < 2:
		_respond(peer, 400, "Bad Request", "")
		return
	var method := parts[0]
	var path := parts[1]
	if method == "GET" and (path == "/health" or path == "/health/"):
		_respond(peer, 200, "OK", JSON.stringify(_status_dict()), "application/json")
	else:
		_respond(peer, 404, "Not Found", "")

func _status_dict() -> Dictionary:
	if status_provider.is_valid():
		var d = status_provider.call()
		if d is Dictionary:
			return d
	return {"status": "starting", "players": 0, "mode": "", "map": "", "uptime_s": 0}

func _respond(peer: StreamPeerTCP, code: int, reason: String, body: String, content_type: String = "text/plain; charset=utf-8") -> void:
	var body_bytes := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
		code, reason, content_type, body_bytes.size()]
	peer.put_data(head.to_utf8_buffer())
	if body_bytes.size() > 0:
		peer.put_data(body_bytes)
	peer.disconnect_from_host()
