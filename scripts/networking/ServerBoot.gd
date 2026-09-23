## ServerBoot.gd  (Autoload : "Boot" — nommé différemment du `class_name` pour
## éviter le conflit Godot "Class hides an autoload singleton" ; même
## convention que Net/NetworkManager.gd. Tout le code y accède par le
## `class_name` statique `ServerBoot`, jamais par le nom de nœud "Boot".)
## Démarre le jeu en SERVEUR DÉDIÉ headless quand le build porte le tag de
## fonctionnalité "dedicated_server" (export "Linux Server", voir
## export_presets.cfg) ou quand `--server` est passé en argument utilisateur
## (pratique pour tester avec le binaire desktop normal — voir docs/SERVER.md,
## `$GODOT_BIN --headless --path . -- --server`). Sinon ne fait RIEN : le menu
## principal (run/main_scene) démarre normalement, comportement inchangé.
##
## En serveur dédié : lit la config (ServerConfig, env vars/args), configure
## MatchConfig, héberge (NetworkManager), démarre la sonde de santé
## (HealthServer) puis charge la carte. Le process serveur N'EST JAMAIS un
## joueur (voir GameWorld._ready, qui vérifie `ServerBoot.active`) — pas de
## spawn local, pas d'écran de sélection d'agent, pas de caméra/HUD ; les
## bots continuent de remplir les équipes normalement (GameWorld.allow_bot_fill
## forcé à vrai). À la fin d'un match (GameMode.winner != -1, même condition
## que GameWorld.request_reset() utilise déjà), soit une nouvelle partie
## recommence sur la même carte/mode (RESTART_ON_END=true, défaut), soit le
## process quitte avec le code 0 pour laisser l'orchestrateur (Dokploy)
## recycler le conteneur (RESTART_ON_END=false).
##
## Journalisation : une ligne par évènement sur stdout, préfixée
## `SERVER_EVENT`, format `cle=valeur` (grep-able) — jamais de secret
## (MATCH_TOKEN_SECRET n'est JAMAIS journalisé, voir _log_event).
class_name ServerBoot
extends Node

## Vrai une fois le démarrage dédié engagé — lu par GameWorld (skip l'écran
## de sélection d'agent et le spawn local du serveur lui-même). Statique :
## accessible sans passer par l'arbre de scène (tests, autres autoloads).
static var active: bool = false

## Délai après la fin d'un match avant de relancer/quitter (laisse le temps
## aux clients d'afficher l'écran de fin de partie).
const POST_MATCH_DELAY_SEC := 5.0

var config: ServerConfig
var health_server: HealthServer

var _start_ticks_msec: int = 0
var _match_ended: bool = false
var _end_wait_t: float = 0.0

func _ready() -> void:
	if not ServerConfig.wants_dedicated(OS.has_feature("dedicated_server"), OS.get_cmdline_user_args()):
		return
	active = true
	_start_ticks_msec = Time.get_ticks_msec()
	config = ServerConfig.from_os()

	MatchConfig.set_mode(config.mode_id)
	MatchConfig.map_id = config.map_id
	MatchConfig.bots_enabled = config.bots_enabled
	MatchConfig.bot_difficulty = ServerConfig.difficulty_id(config.bot_difficulty)

	var net := NetworkManager.get_net(get_tree())
	net.match_id = config.match_id
	net.match_token_secret = config.match_token_secret
	net.player_connected.connect(_on_player_connected)
	net.player_disconnected.connect(_on_player_disconnected)

	var err := net.host(config.port, config.max_players)
	if err != OK:
		_log_event("start_failed", {"error": error_string(err)})
		get_tree().quit(1)
		return

	health_server = HealthServer.new()
	health_server.name = "HealthServer"
	health_server.port = config.health_port
	health_server.status_provider = Callable(self, "_health_status")
	add_child(health_server)

	_log_event("start", {
		"port": config.port,
		"health_port": config.health_port,
		"mode": MatchConfig.mode_id,
		"map": config.map_id if config.map_id != "" else "(défaut)",
		"max_players": config.max_players,
		"bots": config.bots_enabled,
		"bot_difficulty": config.bot_difficulty,
		"token_required": config.match_token_secret != "",
		"restart_on_end": config.restart_on_end,
	})

	# `_ready()` s'exécute pendant que l'arbre ajoute encore la scène
	# principale (main_menu.tscn, dont le _ready() propre — focus initial,
	# etc. — n'a pas encore tourné) : changer de scène ICI lève "Parent node
	# is busy adding/removing children", et le faire en un seul
	# `call_deferred` tombe encore dans le MÊME vidage de la file différée
	# que le _ready() du menu (course avec son focus initial différé). On
	# attend deux frames complètes pour être sûr que l'arbre est stable
	# avant de changer de scène.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(_resolve_map_scene())

func _process(delta: float) -> void:
	if not active:
		return
	_poll_match_end(delta)

# ---------------------------------------------------------------- Carte
func _resolve_map_scene() -> String:
	var entry: Dictionary = MapCatalog.get_by_id(config.map_id) if config.map_id != "" else {}
	if entry.is_empty():
		entry = MapCatalog.default_for(MatchConfig.mode_id)
	return str(entry.get("scene", "res://scenes/levels/tdm_map.tscn"))

# ---------------------------------------------------------------- Fin de match
func _poll_match_end(delta: float) -> void:
	var mode := get_tree().get_first_node_in_group("game_mode") as GameMode
	if mode == null or mode.winner == -1:
		_match_ended = false
		_end_wait_t = 0.0
		return
	if _match_ended:
		return
	_end_wait_t += delta
	if _end_wait_t < POST_MATCH_DELAY_SEC:
		return
	_match_ended = true
	_log_event("match_end", {"winner": mode.winner, "mode": MatchConfig.mode_id, "map": MatchConfig.map_id})
	if config.restart_on_end:
		var world := get_tree().get_first_node_in_group("match") as GameWorld
		if world:
			world.reset_match()
		_log_event("match_restart", {})
	else:
		_log_event("shutdown", {"code": 0})
		get_tree().quit(0)

# ---------------------------------------------------------------- Santé
## Injectée dans HealthServer.status_provider — voir HealthServer.gd.
func _health_status() -> Dictionary:
	var world := get_tree().get_first_node_in_group("match") as GameWorld
	var players := 0
	if world:
		for id in world.player_info.keys():
			if not bool(world.player_info[id].get("is_bot", false)):
				players += 1
	return {
		"status": "ok",
		"players": players,
		"mode": MatchConfig.mode_id,
		"map": MatchConfig.map_id,
		"uptime_s": int((Time.get_ticks_msec() - _start_ticks_msec) / 1000.0),
	}

# ---------------------------------------------------------------- Journal
func _on_player_connected(id: int) -> void:
	_log_event("player_join", {"peer_id": id})

func _on_player_disconnected(id: int) -> void:
	_log_event("player_leave", {"peer_id": id})

## Une ligne par évènement, format `cle=valeur` (grep-able) — JAMAIS
## `config.match_token_secret` ni aucune autre valeur sensible.
func _log_event(event: String, data: Dictionary = {}) -> void:
	var parts := ["SERVER_EVENT", "event=%s" % event]
	for key in data:
		parts.append("%s=%s" % [key, str(data[key])])
	print(" ".join(parts))
