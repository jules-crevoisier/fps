## GameWorld.gd
## Gère le cycle de vie des joueurs : spawn, équipes, mort et respawn.
## À placer sur la racine du niveau. S'appuie sur un MultiplayerSpawner
## (enfant "PlayerSpawner") qui réplique player.tscn sur tous les pairs.
##
## Le SERVEUR fait autorité : spawn, assignation d'équipe, et respawn après mort
## (déclenché par le signal Health.died, lui aussi côté serveur).
class_name GameWorld
extends Node3D

@export var player_scene: PackedScene
@export var players_root: NodePath = "Players"
@export var spawn_points_root: NodePath = "SpawnPoints"
@export var respawn_delay: float = 3.0
@export var team_count: int = 2
## Afficher l'écran de sélection d'agent avant de spawn (false = spawn direct, ex. training).
@export var agent_select: bool = true
## Achats autorisés (lu par BuyMenu via le groupe "match" ; par défaut permis
## si le nœud "match" est absent).
@export var buy_enabled: bool = true
## Active le remplissage des équipes par des bots depuis MatchConfig
## (bots_enabled/team_size — contract-r3.md, R3-IN#2). FAUX par défaut :
## un opt-in scène par scène, pour ne JAMAIS changer le comportement d'une
## scène existante qui n'a pas encore été mise à jour (notamment
## scenes/levels/test_arena.tscn, utilisée telle quelle par tools/net_smoke.gd,
## qui suppose exactement 2 joueurs — hôte + client — et casserait si des
## bots apparaissaient). Les nouvelles cartes de match (R3-MAPS/R3-UI) et
## tools/bot_smoke.gd (mien) l'activent explicitement.
@export var allow_bot_fill: bool = false

const AGENT_SELECT := preload("res://scripts/ui/AgentSelectScreen.gd")
const BOT_NAV := preload("res://scripts/ai/BotNavMesh.gd")

## Courts prénoms français pour les bots ("BOT <nom>" — contract-r3.md).
const BOT_NAMES := [
	"Alizé", "Brume", "Céleste", "Diane", "Étoile", "Faucon", "Gitane", "Hiver",
	"Iris", "Jonas", "Korrigan", "Lucie", "Mistral", "Néon", "Orage", "Perle",
	"Quartz", "Renard", "Sable", "Tonnerre",
]

signal stats_changed
signal kill_logged(killer: String, victim: String, killer_team: int)

## id du peer -> { name, team, kills, deaths, is_bot }
var player_info: Dictionary = {}

## Mouvement actuellement verrouillé (phase BUY/PREROUND d'un mode à manches,
## voir RoundMode.set_all_locked) : appliqué aussi aux joueurs qui spawnent
## APRÈS le verrouillage (rejoint en cours de phase d'achat).
var round_locked: bool = false

var _spawn_index: int = 0
var _team_counter: int = 0
var _next_bot_id: int = PlayerController.BOT_ID_START

func _ready() -> void:
	set_multiplayer_authority(1)  # serveur autoritaire sur les stats/killfeed
	add_to_group("match")
	Settings.load_all()  # applique les touches/sensi/FOV sauvegardés
	var net := NetworkManager.get_net(get_tree())
	net.player_disconnected.connect(_on_player_disconnected)

	if multiplayer.multiplayer_peer == null:
		# Lancé sans réseau (test solo dans l'éditeur) : on héberge localement.
		net.host()

	# Serveur dédié (scripts/networking/ServerBoot.gd) : le process serveur
	# n'est JAMAIS un joueur (pas de spawn local ni d'écran de sélection
	# d'agent — headless, aucune caméra/HUD), et les équipes se remplissent
	# de bots même si CETTE scène n'a pas activé `allow_bot_fill` (voir
	# docs/SERVER.md).
	if ServerBoot.active:
		allow_bot_fill = true

	# Navmesh des bots : baked AVANT le premier spawn (contract-r3.md,
	# "Cross-slice interfaces" — les cartes R3-MAPS en fournissent déjà une
	# dans le groupe "nav_region", sinon on la construit à la volée depuis
	# les colliders statiques de la scène, voir BotNavMesh.ensure_baked).
	if multiplayer.is_server() and allow_bot_fill and MatchConfig.bots_enabled:
		BOT_NAV.ensure_baked(self)

	if ServerBoot.active:
		call_deferred("_fill_bots_if_needed")
		return

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
		# L'hôte utilise directement sa propre sélection (pas de RPC à soi-même).
		_spawn_player(multiplayer.get_unique_id(), AgentDatabase.selected_index)
	else:
		# Client : demande son spawn une fois SA map chargée (évite la course où
		# le serveur ferait spawn avant que le spawner du client existe), avec
		# l'agent choisi à l'écran de sélection.
		_request_spawn.rpc_id(1, AgentDatabase.selected_index)

## Le client (sa scène prête) demande au serveur de le faire spawn avec
## l'agent qu'il a choisi. `agent_index` n'est jamais fait confiance tel
## quel : borné à 0 s'il est hors de la plage des agents connus.
@rpc("any_peer", "reliable")
func _request_spawn(agent_index: int) -> void:
	if multiplayer.is_server():
		_spawn_player(multiplayer.get_remote_sender_id(), agent_index)

func _on_player_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var node := get_node(players_root).get_node_or_null(str(id))
	if node:
		node.queue_free()
	if player_info.has(id):
		player_info.erase(id)
		_sync_stats.rpc(player_info)
	# Un humain part : un bot peut prendre sa place (contract-r3.md :
	# "bots leave when humans join" — et symétriquement en reprennent la
	# place quand ils partent).
	call_deferred("_fill_bots_if_needed")

## `is_bot`/`forced_team`/`display_name` : réservés à `_spawn_bot` (un humain
## garde l'appel à 2 arguments existant, équipe alternée automatique).
func _spawn_player(id: int, agent_index: int, is_bot: bool = false, forced_team: int = -1, display_name: String = "") -> void:
	if player_scene == null:
		push_error("player_scene non assignée sur GameWorld.")
		return
	# Anti double-spawn (si une demande arrive deux fois).
	if get_node(players_root).has_node(str(id)):
		return
	var player := player_scene.instantiate()
	player.name = str(id)  # nom = id => réplication propre par le spawner.
	# Équipe : imposée pour un bot (remplissage ciblé), sinon alternée.
	var team: int
	if forced_team >= 0:
		team = forced_team
	else:
		team = _team_counter % team_count
		_team_counter += 1

	# Agent choisi (borné à 0 si l'index reçu du client est invalide).
	var agent_count := AgentDatabase.all().size()
	var valid_agent_index := agent_index
	if valid_agent_index < 0 or valid_agent_index >= agent_count:
		valid_agent_index = 0

	# Identité (agent + équipe + is_bot) réglée AVANT l'ajout à l'arbre : c'est
	# à ce moment que le spawner capture les propriétés répliquées "spawn only"
	# (agent_index, team, is_bot — voir SceneReplicationConfig de player.tscn).
	player.set("agent_index", valid_agent_index)
	player.set("team", team)
	player.set("is_bot", is_bot)

	# Position de départ AVANT l'ajout à l'arbre : elle est répliquée par le
	# spawner (propriété "spawn") et lue par PlayerController._ready pour fixer
	# le point de respawn.
	var spawn := _get_spawn_position(team)
	player.position = spawn
	player.set("spawn_point", spawn)

	# L'autorité est réglée par PlayerController._enter_tree (basée sur le nom
	# = id, ou le serveur pour un bot), de façon identique sur tous les pairs.
	# On ne la force pas ici pour ne pas créer d'incohérence serveur/clients.
	get_node(players_root).add_child(player, true)

	# Stats du joueur (serveur).
	var pname := display_name if is_bot else "Joueur %d" % id
	player_info[id] = {"name": pname, "team": team, "kills": 0, "deaths": 0, "is_bot": is_bot}
	_sync_stats.rpc(player_info)

	# Le serveur écoute la mort/les dégâts de ce joueur (respawn, charge d'ultime).
	var hp := player.get_node_or_null("Health") as Health
	if hp:
		hp.died.connect(_on_player_died.bind(player))
		hp.damaged.connect(_on_player_damaged)

	# Applique le verrouillage de mouvement en cours (rejoint pendant une
	# phase BUY/PREROUND d'un mode à manches).
	if round_locked:
		_lock_player(player, true)

	# Un humain vient de spawn : (re)synchronise le remplissage par des bots
	# (nouvelle équipe à compléter, ou une place à libérer). PAS pour un bot
	# lui-même (idempotence : évite un aller-retour inutile par bot spawné).
	if not is_bot:
		call_deferred("_fill_bots_if_needed")

func _on_player_died(killer_id: int, player: Node) -> void:
	if not multiplayer.is_server():
		return
	_record_kill(killer_id, str(player.name).to_int())
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode != null and mode.has_method("respawns_immediately") and not mode.respawns_immediately():
		return  # mode à manches (SnD/Duel) : pas de respawn avant la prochaine manche
	# Respawn après délai (arène : TDM/Hardpoint/entraînement).
	await get_tree().create_timer(respawn_delay).timeout
	if not is_instance_valid(player):
		return
	var team: int = player.get("team")
	var spawn := _get_spawn_position(team)
	_teleport_player(player, spawn)
	var hp := player.get_node_or_null("Health") as Health
	if hp:
		hp.reset()
		hp.spawn_protection(1.0)

## Charge l'ultime de l'ATTAQUANT à chaque dégât infligé (0.05 pt / dégât,
## voir contract-r2.md), en plus du bonus fixe sur kill (_record_kill).
func _on_player_damaged(amount: float, attacker_id: int) -> void:
	if not multiplayer.is_server() or attacker_id <= 0:
		return
	_charge_ult(attacker_id, amount * 0.05)

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

func _charge_ult(killer_id: int, points: float = 2.0) -> void:
	var pnode := get_node(players_root).get_node_or_null(str(killer_id))
	if pnode:
		var ab := pnode.get_node_or_null("Abilities")
		# Appel DIRECT (pas de RPC) : on est déjà côté serveur, et
		# AbilityController.server_add_ult pousse lui-même la correction au
		# propriétaire une fois l'état autoritaire mis à jour.
		if ab and ab.has_method("server_add_ult"):
			ab.server_add_ult(points)

@rpc("authority", "call_local", "reliable")
func _sync_stats(data: Dictionary) -> void:
	player_info = data
	stats_changed.emit()

@rpc("authority", "call_local", "reliable")
func _killfeed(killer: String, victim: String, killer_team: int) -> void:
	kill_logged.emit(killer, victim, killer_team)

## Rejouer (demandé par un client, exécuté par le serveur). Autorisé
## uniquement pour un expéditeur connu (présent dans player_info — anti-spam
## d'un pair non joueur) et seulement s'il n'y a pas de mode de jeu (ex.
## training) ou si le mode a déjà un vainqueur (fin de partie) : on ne
## réinitialise jamais un match en cours.
@rpc("any_peer", "reliable")
func request_reset() -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if not player_info.has(sender_id):
		return
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode != null and int(mode.winner) == -1:
		return
	reset_match()

func reset_match() -> void:
	if not multiplayer.is_server():
		return
	for id in player_info:
		player_info[id].kills = 0
		player_info[id].deaths = 0
	_sync_stats.rpc(player_info)
	var mode := get_tree().get_first_node_in_group("game_mode")
	# Les modes à manches (RoundMode) pilotent LEUR propre respawn/verrouillage
	# depuis reset_match() (BUY/PREROUND de la manche 1) : on ne double pas
	# l'appel ici pour ne pas les respawn deux fois d'affilée. Les modes
	# d'arène (TDM/Hardpoint, ou aucun mode) respawnent directement ici.
	if mode != null and mode.has_method("reset_match"):
		mode.reset_match()
	if mode == null or mode.respawns_immediately():
		set_all_locked(false)
		respawn_all_for_round()

## Respawn TOUS les joueurs actuels (vivants ou morts) au début d'une nouvelle
## manche (SnD/Duel, appelé par RoundMode._enter_buy_phase) : pleine vie,
## position d'équipe et courte protection de spawn. Ne touche PAS l'inventaire
## d'armes (RoundMode gère survivants/loadout imposé après cet appel).
func respawn_all_for_round() -> void:
	if not multiplayer.is_server():
		return
	for child in get_node(players_root).get_children():
		var team := int(child.get("team"))
		var spawn := _get_spawn_position(team)
		_teleport_player(child, spawn)
		var hp := child.get_node_or_null("Health") as Health
		if hp:
			hp.reset()
			hp.spawn_protection(1.0)

## Verrouille/déverrouille le mouvement de TOUS les joueurs actuels (RoundMode :
## phase BUY/PREROUND d'un mode à manches). Mémorisé (`round_locked`) pour être
## réappliqué aux joueurs qui spawnent après coup (voir `_spawn_player`).
func set_all_locked(locked: bool) -> void:
	if not multiplayer.is_server():
		return
	round_locked = locked
	for child in get_node(players_root).get_children():
		_lock_player(child, locked)

## Téléporte (respawn) un joueur simulé ICI (hôte/bot, appel serveur direct
## via `server_respawn`) ou distant (RPC ciblée `net_respawn`) — un bot
## (id >= PlayerController.BOT_ID_START) n'a aucun pair réel à qui envoyer
## une RPC (contract-r3.md, "Cross-slice interfaces").
func _teleport_player(player: Node, pos: Vector3) -> void:
	if player.has_method("server_respawn") and player.is_multiplayer_authority():
		player.server_respawn(pos)
	elif player.has_method("net_respawn"):
		player.net_respawn.rpc_id(str(player.name).to_int(), pos)

## Même distinction que `_teleport_player`, pour le verrouillage de mouvement.
func _lock_player(player: Node, locked: bool) -> void:
	if player.has_method("server_set_locked") and player.is_multiplayer_authority():
		player.server_set_locked(locked)
	elif player.has_method("net_set_locked"):
		player.net_set_locked.rpc_id(str(player.name).to_int(), locked)

# ======================================================================
#  BOTS — remplissage/remplacement par équipe depuis MatchConfig
#  (contract-r3.md, R3-IN#2). Actif seulement si `allow_bot_fill` (voir sa
#  doc) ET `MatchConfig.bots_enabled`. Un bot a un id >= PlayerController.BOT_ID_START
#  (jamais un id de pair réel), l'autorité SERVEUR (peer 1, voir
#  PlayerController._enter_tree) et un nom "BOT <prénom français>".
# ======================================================================
func _fill_bots_if_needed() -> void:
	if not multiplayer.is_server() or not allow_bot_fill or not MatchConfig.bots_enabled:
		return
	for team in team_count:
		_sync_team_bots(team)

func _sync_team_bots(team: int) -> void:
	var target := maxi(MatchConfig.team_size, 0)
	var humans := 0
	var bots: Array = []
	for id in player_info.keys():
		if int(player_info[id].team) != team:
			continue
		if bool(player_info[id].get("is_bot", false)):
			bots.append(id)
		else:
			humans += 1
	var wanted_bots := maxi(target - humans, 0)
	# Un humain a rejoint cette équipe déjà complète : on retire un bot pour
	# lui faire de la place.
	while bots.size() > wanted_bots:
		_remove_bot(bots.pop_back())
	# Équipe incomplète : on complète avec des bots.
	while bots.size() < wanted_bots:
		bots.append(_spawn_bot(team))

func _spawn_bot(team: int) -> int:
	var id := _next_bot_id
	_next_bot_id += 1
	var agent_count := AgentDatabase.all().size()
	var agent_index := randi() % maxi(agent_count, 1)
	_spawn_player(id, agent_index, true, team, _pick_bot_name())
	return id

func _remove_bot(id: int) -> void:
	var node := get_node(players_root).get_node_or_null(str(id))
	if node:
		node.queue_free()
	if player_info.has(id):
		player_info.erase(id)
	_sync_stats.rpc(player_info)

## Premier prénom français encore inutilisé par un bot vivant ; repli
## numéroté si la liste est épuisée (parties à très nombreux bots).
func _pick_bot_name() -> String:
	var used := {}
	for id in player_info.keys():
		if bool(player_info[id].get("is_bot", false)):
			used[String(player_info[id].name)] = true
	for n in BOT_NAMES:
		var full := "BOT %s" % n
		if not used.has(full):
			return full
	return "BOT %d" % _next_bot_id

## Marqueur de spawn (méta "team" sur les nœuds sous `spawn_points_root`) à
## utiliser pour un joueur de `team`, compte tenu de l'échange de côté d'un
## mode à manches (.orchestrator/maps-spec.md §4.6 : "spawn_team = team if
## not sides_swapped else 1 - team"). Les marqueurs sont tagués par CÔTÉ
## géométrique fixe (0 = attaque, 1 = défense en SnD — voir MapSetup), pas
## par équipe : après l'échange de côté (SnD, manche 6+), le NUMÉRO d'équipe
## du joueur ne change pas mais son RÔLE si, donc le côté où il doit spawn
## doit suivre le rôle, pas le numéro brut (sinon les attaquants spawnent
## sur les sites de bombe — bug remonté par le level design). Pur — testable
## sans scène, voir tests/networking/test_spawn_role.gd.
static func spawn_side_for(team: int, sides_swapped: bool) -> int:
	return (1 - team) if sides_swapped else team

## Échange de côté du mode COURANT (RoundMode.sides_swapped — SnD/Duel ;
## absent des modes d'arène TDM/Hardpoint, qui ignorent alors ce mécanisme).
func _sides_swapped() -> bool:
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode == null:
		return false
	var v = mode.get("sides_swapped")
	return false if v == null else bool(v)

## Positions des ennemis VIVANTS (équipe != `team`) — maps-spec-v2.md §7.6 /
## §5.6.2 "every respawn picks the point furthest from the nearest living
## enemy" (parade au spawn-kill, en particulier sur une map asymétrique juste
## après l'échange de côté, mais appliquée à TOUTES les maps : ça n'aggrave
## jamais une map symétrique). Aucun ennemi encore vivant (tout début de
## partie) => tableau vide, `SpawnPick.safest` retombe alors sur l'ancien
## tourniquet round-robin, comportement 100% inchangé dans ce cas.
func _living_enemy_positions(team: int) -> Array:
	var out: Array = []
	var pr := get_node_or_null(players_root)
	if pr == null:
		return out
	for child in pr.get_children():
		if int(child.get("team")) == team:
			continue
		var hp := child.get_node_or_null("Health") as Health
		if hp and hp.is_dead:
			continue
		out.append((child as Node3D).global_position)
	return out

func _get_spawn_position(team: int) -> Vector3:
	var root := get_node_or_null(spawn_points_root)
	if root == null or root.get_child_count() == 0:
		return Vector3(0, 1.5, 0)
	var points := root.get_children()
	var side := spawn_side_for(team, _sides_swapped())
	# On répartit par côté : on prend un point dont la méta "team" correspond
	# au côté courant du joueur si possible, sinon on cycle.
	var team_points: Array = []
	for p in points:
		if p.has_meta("team") and int(p.get_meta("team")) == side:
			team_points.append(p)
	if team_points.is_empty():
		team_points = points
	var positions: Array = []
	for p in team_points:
		positions.append((p as Node3D).global_position)
	var idx := SpawnPick.safest(positions, _living_enemy_positions(team), _spawn_index)
	_spawn_index += 1
	return positions[idx]
