## NetworkManager.gd  (Autoload : "Net")
## Couche réseau minimale basée sur ENet + l'API multijoueur haut-niveau de Godot.
## - host() : démarre un serveur (qui est aussi joueur, sauf en serveur dédié
##   — voir ServerBoot.gd/GameWorld.gd).
## - join() : se connecte à un serveur.
## Le spawn effectif des joueurs est géré par le MultiplayerSpawner de la scène
## de niveau (voir GameWorld.gd).
##
## Normalement enregistré en autoload ("Net"). Pour être ROBUSTE même si
## l'autoload n'est pas pris en compte, on y accède via NetworkManager.get_net()
## (qui le retrouve à /root/Net, ou le crée au besoin).
##
## Handshake d'authentification (SceneMultiplayer.auth_callback — doc Godot
## 4.7 "High-level multiplayer") : à CHAQUE connexion (hébergement normal ET
## serveur dédié), le client envoie sa version de protocole (+ un jeton
## optionnel) ; le serveur valide avant de compléter la poignée de main, donc
## un pair refusé n'apparaît JAMAIS dans `peer_connected` / le spawner de
## scène. `match_token_secret` vide (par défaut) = aucun jeton exigé, pour ne
## jamais casser le LAN/host play (ServerBoot le renseigne pour un serveur
## dédié avec MATCH_TOKEN_SECRET défini).
class_name NetworkManager
extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_started
signal connection_failed
signal connection_succeeded
signal server_lost

const DEFAULT_PORT: int = 7777
const DEFAULT_IP: String = "127.0.0.1"
const MAX_PLAYERS: int = 16
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
## Motif de refus par défaut quand le serveur n'a pas pu (dé)coder de raison
## explicite (ne devrait arriver que sur un paquet corrompu/tronqué).
const DEFAULT_REJECT_REASON := "Connexion refusée par le serveur."

var peer: ENetMultiplayerPeer
## Motif du dernier retour forcé au menu (lu puis effacé par le menu principal).
var last_disconnect_reason: String = ""

## Renseignés par ServerBoot pour un serveur dédié (sinon vides = pas de
## jeton exigé). Voir JoinToken.gd.
var match_id: String = ""
var match_token_secret: String = ""

## Renseignés par join() avant la connexion, envoyés au serveur lors du
## handshake d'authentification (voir _on_peer_authenticating).
var _pending_player_id: String = ""
var _pending_token: String = ""

## Accès robuste au gestionnaire réseau, indépendant de l'autoload.
## Le retrouve à /root/Net (autoload) ou le crée s'il n'existe pas.
static func get_net(tree: SceneTree) -> NetworkManager:
	var root := tree.root
	var n := root.get_node_or_null("Net")
	if n == null:
		n = NetworkManager.new()
		n.name = "Net"
		root.add_child(n)
	return n

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): connection_succeeded.emit())
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_authenticating.connect(_on_peer_authenticating)
	multiplayer.peer_authentication_failed.connect(_on_peer_authentication_failed)
	multiplayer.auth_callback = _on_auth_data

func host(port: int = DEFAULT_PORT, max_players: int = MAX_PLAYERS) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		push_error("Échec création serveur: %s" % err)
		return err
	multiplayer.multiplayer_peer = peer
	server_started.emit()
	return OK

## `player_id`/`token` : identité + jeton HMAC délivrés hors-bande par un
## service de matchmaking (voir JoinToken.gd) — optionnels, seulement exigés
## si le serveur a un `match_token_secret` (serveur dédié avec
## MATCH_TOKEN_SECRET défini). Vides = LAN/host play normal, inchangé.
func join(ip: String = DEFAULT_IP, port: int = DEFAULT_PORT, player_id: String = "", token: String = "") -> Error:
	_pending_player_id = player_id
	_pending_token = token
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

## Le serveur a disparu (hôte parti, coupure) : on ferme proprement la session
## et on revient au menu, qui affiche le motif. Sans ça le client reste figé
## dans une partie morte.
func _on_server_disconnected() -> void:
	last_disconnect_reason = "Connexion au serveur perdue."
	disconnect_from_game()
	server_lost.emit()
	get_tree().change_scene_to_file(MAIN_MENU)

# ======================================================================
#  Handshake d'authentification (SceneMultiplayer.auth_callback)
#  - Client : `peer_authenticating(1)` -> envoie {version, player_id, token} ;
#    attend la réponse du serveur ({ok:true} -> complete_auth, {ok:false,
#    reason} -> mémorise la raison, laisse le serveur couper la connexion).
#  - Serveur : reçoit {version, player_id, token} d'un pair CONNECTANT (pas
#    encore dans player_info/le spawner) ; valide, répond {ok:true} +
#    complete_auth, ou {ok:false, reason} + disconnect_peer.
#  Un pair refusé n'émet donc JAMAIS peer_connected (voir doc Godot
#  "High-level multiplayer") : il n'entre jamais dans la partie.
# ======================================================================

## Le pair local doit s'authentifier auprès de `id` — uniquement pertinent
## côté CLIENT (id == 1, le serveur) ; le serveur n'a rien à envoyer avant
## d'avoir reçu les identifiants du client (voir _on_auth_data).
func _on_peer_authenticating(id: int) -> void:
	if multiplayer.is_server():
		return
	var payload := {
		"version": ProtocolVersion.CURRENT,
		"player_id": _pending_player_id,
		"token": _pending_token,
	}
	multiplayer.send_auth(id, JSON.stringify(payload).to_utf8_buffer())

## Données d'authentification reçues de `peer_id` (voir SceneMultiplayer.send_auth).
func _on_auth_data(peer_id: int, payload: PackedByteArray) -> void:
	if multiplayer.is_server():
		_server_validate_and_reply(peer_id, payload)
	else:
		_client_apply_server_decision(payload)

## Côté SERVEUR : `peer_id` est un pair encore en cours de connexion (pas un
## joueur du match). Ne JAMAIS faire confiance à `payload` (JSON externe,
## potentiellement forgé) : tout défaut de forme est traité comme un refus,
## jamais une erreur GDScript.
func _server_validate_and_reply(peer_id: int, payload: PackedByteArray) -> void:
	var reason := _server_validation_reason(payload)
	if reason == "":
		multiplayer.send_auth(peer_id, JSON.stringify({"ok": true}).to_utf8_buffer())
		multiplayer.complete_auth(peer_id)
	else:
		multiplayer.send_auth(peer_id, JSON.stringify({"ok": false, "reason": reason}).to_utf8_buffer())
		_disconnect_rejected_peer(peer_id)

## Un `disconnect_peer` immédiat peut devancer, sur certains transports, le
## paquet `send_auth` du motif de refus juste au-dessus (observé en
## pratique : le client ne recevait alors que le motif générique de secours,
## jamais le motif précis) — on laisse une courte fenêtre pour qu'il soit
## remis avant de couper.
func _disconnect_rejected_peer(peer_id: int) -> void:
	var timer := get_tree().create_timer(0.3)
	timer.timeout.connect(func() -> void:
		if multiplayer.multiplayer_peer != null:
			multiplayer.disconnect_peer(peer_id))

## "" = accepté, sinon motif (français, affichable tel quel côté client).
func _server_validation_reason(payload: PackedByteArray) -> String:
	var data: Variant = JSON.parse_string(payload.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return DEFAULT_REJECT_REASON
	var version := str((data as Dictionary).get("version", ""))
	if not ProtocolVersion.is_compatible(version):
		return "Version du jeu incompatible (client %s, serveur %s)." % [version, ProtocolVersion.CURRENT]
	if match_token_secret != "":
		var player_id := str((data as Dictionary).get("player_id", ""))
		var token := str((data as Dictionary).get("token", ""))
		if not JoinToken.verify(match_token_secret, match_id, player_id, token):
			return "Jeton de connexion invalide ou manquant."
	return ""

## Côté CLIENT : réponse du serveur (voir _server_validate_and_reply). Sur
## refus, on mémorise juste le motif — c'est le serveur qui coupe la
## connexion (déclenche `peer_authentication_failed`, voir
## _on_peer_authentication_failed).
func _client_apply_server_decision(payload: PackedByteArray) -> void:
	var data: Variant = JSON.parse_string(payload.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d := data as Dictionary
	if bool(d.get("ok", false)):
		multiplayer.complete_auth(1)
	else:
		last_disconnect_reason = str(d.get("reason", DEFAULT_REJECT_REASON))

## L'authentification échoue avant `peer_connected` (version/jeton refusés,
## ou coupure pendant le handshake). Ce signal arrive AUSSI côté serveur pour
## chaque pair qu'il refuse : `is_host()` s'assure de ne jamais renvoyer le
## serveur lui-même au menu à cause du refus d'un tiers.
func _on_peer_authentication_failed(_id: int) -> void:
	if is_host():
		return
	if last_disconnect_reason == "":
		last_disconnect_reason = DEFAULT_REJECT_REASON
	disconnect_from_game()
	connection_failed.emit()
	get_tree().change_scene_to_file(MAIN_MENU)
