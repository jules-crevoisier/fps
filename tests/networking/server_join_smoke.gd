## server_join_smoke.gd
## Vérification manuelle en DEUX process (comme tools/net_smoke.gd — pas un
## test gdUnit4) du chemin COMPLET d'un serveur dédié réel : un client normal
## rejoint et spawn comme joueur, un client à la mauvaise version de
## protocole est refusé avec un motif (NetworkManager.last_disconnect_reason).
## À lancer contre un serveur dédié déjà démarré (voir docs/SERVER.md) :
##   $GODOT_BIN --headless --path . -- --server   (avec MODE=tdm MAP=port_ferraille)
## Puis, dans un second process :
##   Rejoindre normalement :
##     godot --headless --path . -s res://tests/networking/server_join_smoke.gd -- --role=join
##   Simuler un client à jour obsolète (version de protocole différente) :
##     godot --headless --path . -s res://tests/networking/server_join_smoke.gd -- --role=bad_version
## Affiche `SERVER_JOIN_SMOKE_RESULT ok=<bool> reason="..."` puis quitte
## (0 = résultat conforme à ce que le rôle attend, 1 = échec/timeout).
extends SceneTree

const PORT := 7777
const TIMEOUT_SEC := 10.0
## Carte de vérification fixe (assortie à l'appel serveur de la procédure de
## vérification, voir docs/SERVER.md) — même principe que le
## `LEVEL` codé en dur de tools/net_smoke.gd.
const VERIFY_MAP_ID := "port_ferraille"

var _role: String = "join"
var _t: float = 0.0
var _started: bool = false
var _spawn_requested: bool = false
var _level_scene: String = ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			_role = a.get_slice("=", 1)
	_level_scene = str(MapCatalog.get_by_id(VERIFY_MAP_ID).get("scene", ""))

func _start() -> void:
	_started = true
	var net := NetworkManager.get_net(self)
	if _role == "bad_version":
		_simulate_stale_client(net)
	net.connection_failed.connect(func() -> void:
		_finish(_role == "bad_version", net.last_disconnect_reason))
	net.connection_succeeded.connect(func() -> void:
		if _role == "bad_version":
			_finish(false, "connecté alors qu'un refus était attendu")
		else:
			change_scene_to_file(_level_scene))
	net.join("127.0.0.1", PORT)

## Contourne NetworkManager._on_peer_authenticating (qui enverrait TOUJOURS la
## version courante) pour simuler un client compilé avec une version de
## protocole différente — exercice volontaire d'un chemin interne
## (méthode `_`) : c'est la seule façon d'obtenir, dans ce process, un
## handshake qui ment sur sa version sans modifier NetworkManager lui-même.
func _simulate_stale_client(net: NetworkManager) -> void:
	var mp := get_multiplayer()
	if mp.peer_authenticating.is_connected(net._on_peer_authenticating):
		mp.peer_authenticating.disconnect(net._on_peer_authenticating)
	mp.peer_authenticating.connect(func(id: int) -> void:
		var payload := {"version": "0.0.1-stale", "player_id": "", "token": ""}
		mp.send_auth(id, JSON.stringify(payload).to_utf8_buffer()))

func _process(delta: float) -> bool:
	if not _started:
		_start()
		return false
	_t += delta
	if _role == "join":
		_try_request_spawn()
		if _am_i_spawned():
			_finish(true, "spawned as player")
			return true
	if _t > TIMEOUT_SEC:
		_finish(false, "timeout (role=%s)" % _role)
		return true
	return false

func _try_request_spawn() -> void:
	if _spawn_requested or current_scene == null:
		return
	if not current_scene.has_method("_request_spawn"):
		return
	current_scene._request_spawn.rpc_id(1, 0)
	_spawn_requested = true

func _am_i_spawned() -> bool:
	if current_scene == null:
		return false
	var players := current_scene.get_node_or_null("Players")
	if players == null:
		return false
	return players.get_node_or_null(str(get_multiplayer().get_unique_id())) != null

func _finish(ok: bool, reason: String) -> void:
	print("SERVER_JOIN_SMOKE_RESULT ok=%s reason=\"%s\" role=%s" % [ok, reason, _role])
	quit(0 if ok else 1)
