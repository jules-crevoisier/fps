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
## `weapon_or_ability`/`headshot` : résolus CÔTÉ SERVEUR pour TOUT kill, bot
## contre bot compris (relance QA UX-01 — voir `_record_kill` : l'ancien
## signal ne portait ni l'un ni l'autre, et GameHUD ne pouvait deviner que sa
## PROPRE arme via Weapon.hit_confirmed, jamais celle d'un kill entre bots).
signal kill_logged(killer: String, victim: String, killer_team: int, weapon_or_ability: String, headshot: bool)
## Ping relayé à CE pair (UX-10, voir section « SYSTÈME DE PING » plus bas) --
## émis par `_deliver_ping_local`, appelé directement pour l'hôte/soi-même et
## par la RPC `_relay_ping` pour tout autre client. Câblage HUD (connexion à
## `PingMarkers.receive`) hors périmètre de cette tâche (GameHUD.gd/
## player.tscn n'y figurent pas, voir tasks/backlog.yaml UX-10).
signal ping_received(sender_id: int, sender_name: String, kind: String, pos: Vector3, zone_name: String)

## id du peer -> { name, team, kills, deaths, is_bot }
var player_info: Dictionary = {}

## Instrument PARTAGÉ (une entrée par victime) qui suit les dégâts encaissés
## pour déterminer les ASSISTANCES à la mort (AGT-01/AGT-02, voir la doc de
## AssistTracker.gd) : alimenté à CHAQUE dégât serveur par `_on_player_damaged`
## (`record_damage`), consommé à chaque mort par `_record_kill`
## (`assists_for_kill`).
var _assists := AssistTracker.new()

## Mouvement actuellement verrouillé (phase BUY/PREROUND d'un mode à manches,
## voir RoundMode.set_all_locked) : appliqué aussi aux joueurs qui spawnent
## APRÈS le verrouillage (rejoint en cours de phase d'achat).
var round_locked: bool = false

## Données tactiques pré-calculées de la carte en cours (BOT-05/BOT-05B),
## chargées côté serveur AVANT le premier spawn de bot — voir `_ready`.
## `null` si `resources/bot_spots/<map_id>.tres` n'a pas encore été bakée
## (`tools/bake_bot_spots.gd`) : aucune régression, le position-picking des
## bots (BOT-06, hors périmètre ici) n'a alors simplement pas ces données.
var bot_spots: BotSpots = null

var _spawn_index: int = 0
var _team_counter: int = 0
var _next_bot_id: int = PlayerController.BOT_ID_START

## ---- Sélection d'agent d'équipe (UX-11, docs/research/04_ui_ux.md §2.4) ----
## Référence à L'ÉCRAN DE SÉLECTION LOCAL (ce pair), tant qu'il est ouvert —
## sert à relayer les mises à jour reçues du serveur (`on_picks_updated`/
## `on_pick_rejected`) sans dépendre d'un nom de nœud. `null` en dehors de la
## phase de sélection (écran verrouillé/jamais ouvert, ex. serveur dédié).
var _agent_select_screen: Node = null
## id de pair -> équipe assignée dès L'OUVERTURE de l'écran de sélection (voir
## `assign_agent_select_team`) — réutilisée telle quelle par `_spawn_player`
## (aucun second tirage au sort à part), jusqu'à ce que `leave_agent_select`
## l'efface au moment du spawn réel de ce joueur.
var _agent_select_team: Dictionary = {}
## id de pair -> {"agent_index": int, "locked": bool, "name": String} :
## dernier choix connu de chaque joueur HUMAIN en cours de sélection (jamais
## les bots, qui ne passent pas par cet écran — voir `_spawn_bot`).
var _agent_picks: Dictionary = {}

## Historique des morts récentes PAR ÉQUIPE ({"pos": Vector3, "t": float}
## horodatage Unix) — alimente la pénalité "un allié est mort ici il y a
## moins de 5 s" de `SpawnPick.score` (LD-02, docs/research/03_level_design.md
## §2.4). Purgé opportunément (`_record_recent_death`) au-delà de
## `_RECENT_DEATH_HISTORY_S`, une fenêtre large par rapport aux 5 s que
## `SpawnPick.score` retient réellement — juste de quoi borner la mémoire.
var _recent_deaths_by_team: Dictionary = {}
const _RECENT_DEATH_HISTORY_S := 10.0
## Hauteur d'œil utilisée pour le rayon de ligne de vue de spawn (docs/
## research/03_level_design.md §3.1 : œil debout à 1,6 m), des deux côtés du
## rayon (ennemi -> point candidat, ou zone Hardpoint -> point candidat,
## même fonction — voir `_spawn_enemy_has_los`).
const _SPAWN_EYE_HEIGHT := 1.6

## Sentinelle "aucune position imposée" pour `_spawn_player(spawn_override:)`
## (LD-23) : une composante infinie ne peut jamais être une vraie position de
## spawn, et `==` sur deux `Vector3(INF, INF, INF)` est fiable (contrairement
## à NAN, INF se compare correctement par égalité en GDScript/IEEE 754).
const _NO_SPAWN_OVERRIDE := Vector3(INF, INF, INF)

## Plancher anti-empilement (LD-23, R17) — même valeur que le défaut de
## `SpawnPick.pick_spawn_set`, mais nommée ici pour être réutilisée par le
## pré-filtre "marqueur déjà occupé" de `_get_team_spawn_positions` (voir sa
## doc : sans lui, un marqueur déjà pris par un coéquipier vivant HORS du lot
## pourrait être choisi À NOUVEAU pour un membre du lot, le plancher de
## `pick_spawn_set` ne s'appliquant jamais à un point choisi AVANT son appel).
const _SPAWN_MIN_SEPARATION := 3.0

# ---- Télémétrie (FUN-05, docs/research/05_fun_retention.md §5) ----------
## Identifiant du match COURANT, connu de TOUS les pairs (diffusé par
## `_broadcast_match_id` — voir `_start_new_match`) : un pair non-serveur en a
## besoin pour rattacher ses propres événements locaux (agent choisi,
## capacité utilisée...) au bon match, même s'il n'écrit jamais les
## événements de jeu eux-mêmes (Telemetry.GAME_EVENTS, réservés au serveur).
var _match_id: String = ""
var _match_start_t: float = 0.0
var _round_index: int = 0
## Dernier instant de spawn (Time.get_unix_time_from_system) par id de
## joueur — sert au champ `time_since_spawn` d'un `kill` (indicateur "morts
## < 3 s après un spawn", docs/research/05_fun_retention.md §3.3).
var _spawn_time: Dictionary = {}
## Dernier tir confirmé (headshot ou non) par id de TIREUR, et dernière
## capacité activée par id de JOUEUR — alimentés par `_on_own_hit_confirmed`/
## `_on_own_ability_used` (écoute des signaux PUBLICS Weapon.hit_confirmed /
## AbilityController.ability_used sur l'entité qu'un pair simule lui-même :
## voir `_on_player_node_spawned`) ou reportés au serveur par
## `_report_headshot`/`_report_ability_used` quand ce pair n'est pas le
## serveur. Fenêtre de fraîcheur courte : un headshot/une capacité trop
## ancien(ne) au moment du kill n'est plus attribué(e) (évite d'attribuer à
## tort un vieux tir/une vieille capacité à un kill sans rapport).
var _last_headshot: Dictionary = {}
var _last_ability: Dictionary = {}
const _HEADSHOT_FRESHNESS_S := 2.0
const _ABILITY_FRESHNESS_S := 5.0
## id d'expéditeur -> Array[float] (horodatages Unix de ses derniers pings
## ENVOYÉS, encore dans la fenêtre glissante -- UX-10, « au plus 3 pings par
## 5 s et par joueur »). Voir section « SYSTÈME DE PING » plus bas.
var _ping_history: Dictionary = {}
## Accumulateur de temps de frame LOCAL à ce pair (voir `_process`), résumé
## en un événement `match_perf` par `_emit_match_perf` (fin de match/rejouer).
var _frame_stats := FrameStats.new()

func _ready() -> void:
	set_multiplayer_authority(1)  # serveur autoritaire sur les stats/killfeed
	add_to_group("match")
	# Télémétrie (FUN-05) : un journal JSONL local PAR PROCESS (menu + tous
	# les matchs joués pendant cette session) — appel idempotent : un second
	# chargement de niveau dans le même process ne réouvre rien.
	Telemetry.start_session()
	Settings.load_all()  # applique les touches/sensi/FOV sauvegardés
	var net := NetworkManager.get_net(get_tree())
	net.player_disconnected.connect(_on_player_disconnected)
	# Écoute la réplication des joueurs (voir doc d'en-tête) pour brancher la
	# télémétrie de tir/capacité SUR L'ENTITÉ QUE CE PAIR SIMULE LUI-MÊME
	# (voir `_on_player_node_spawned`) : sans dépendre de `_spawn_player`, qui
	# ne s'exécute jamais côté client.
	var spawner := get_node_or_null("PlayerSpawner") as MultiplayerSpawner
	if spawner:
		spawner.spawned.connect(_on_player_node_spawned)

	var peer := multiplayer.multiplayer_peer
	if peer == null:
		# Lancé sans réseau (test solo dans l'éditeur) : on héberge localement.
		net.host()
	elif not (peer is OfflineMultiplayerPeer) \
			and peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		# Tentative de connexion restée en cours (ex. « Rejoindre » raté puis
		# terrain d'entraînement) : on l'abandonne, sinon on se croirait client
		# d'un serveur absent et la demande de spawn partirait dans le vide.
		# On héberge ensuite localement, comme la branche sans réseau.
		net.disconnect_from_game()
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
	# Données tactiques (BOT-05B) : chargées dans la foulée, AVANT le premier
	# bot, depuis la ressource bakée par tools/bake_bot_spots.gd pour la carte
	# en cours (MatchConfig.map_id) — `null` silencieux si elle n'existe pas
	# encore (voir doc de `bot_spots` ci-dessus).
	if multiplayer.is_server() and allow_bot_fill and MatchConfig.bots_enabled:
		BOT_NAV.ensure_baked(self)
		bot_spots = BotSpots.load_for_map(MatchConfig.map_id)

	# Télémétrie : un `match_start` (serveur dédié ou hôte) AVANT le premier
	# spawn, pour que `spawn`/`kill` suivants portent déjà le bon `match_id`.
	if multiplayer.is_server():
		_start_new_match()

	if ServerBoot.active:
		call_deferred("_fill_bots_if_needed")
		return

	if agent_select:
		_open_agent_select()
	else:
		_spawn_local()

func _open_agent_select() -> void:
	var screen := AGENT_SELECT.new()
	_agent_select_screen = screen
	add_child(screen)
	# UX-11 : chaque changement de survol non verrouillé est diffusé à
	# l'équipe (≤ 200 ms, RPC fiable directe — même mécanisme que
	# `_sync_stats`/`_killfeed` déjà utilisés côté serveur->clients ici).
	screen.agent_picked.connect(_on_local_agent_picked)
	screen.locked.connect(func():
		# Annonce le verrouillage AVANT `_spawn_local()` : les deux RPC
		# (verrouillage puis demande de spawn) partent sur le même canal
		# fiable, donc dans cet ordre côté serveur (voir `resolve_final_agent_index`,
		# qui a besoin du verrouillage déjà appliqué au moment du spawn).
		_on_local_agent_locked()
		if is_instance_valid(screen):
			screen.queue_free()
		_agent_select_screen = null
		# UX-11 : "à l'ouverture, le dernier agent joué est survolé" — le choix
		# VERROUILLÉ par ce joueur (jamais un survol non confirmé) devient sa
		# présélection persistante pour la prochaine ouverture de cet écran.
		AgentDatabase.record_played(AgentDatabase.selected_index)
		# Action LOCALE au pair (pas un état de match autoritaire) : écrite
		# directement, sans passer par le serveur (Telemetry.GAME_EVENTS ne
		# la liste pas — voir sa doc d'en-tête).
		Telemetry.record(Telemetry.EVENT_AGENT_SELECTED, {
			"player_id": multiplayer.get_unique_id(),
			"agent_id": AgentDatabase.selected().agent_name,
		}, _match_id, false)
		_spawn_local())
	var id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		# L'hôte est simulé côté serveur (architecture) : appel direct au lieu
		# d'un RPC à soi-même pour rejoindre la sélection d'équipe.
		var team := assign_agent_select_team(id)
		record_agent_pick(id, AgentDatabase.selected_index, false)
		_broadcast_agent_picks(team)
	else:
		_server_join_agent_select.rpc_id(1, AgentDatabase.selected_index)

func _spawn_local() -> void:
	if multiplayer.is_server():
		# L'hôte utilise directement sa propre sélection (pas de RPC à soi-même).
		var id := multiplayer.get_unique_id()
		_spawn_player(id, resolve_final_agent_index(id, AgentDatabase.selected_index))
		_leave_agent_select_after_spawn(id)
	else:
		# Client : demande son spawn une fois SA map chargée (évite la course où
		# le serveur ferait spawn avant que le spawner du client existe), avec
		# l'agent choisi à l'écran de sélection.
		_request_spawn.rpc_id(1, AgentDatabase.selected_index)

## Le client (sa scène prête) demande au serveur de le faire spawn avec
## l'agent qu'il a choisi. `agent_index` n'est jamais fait confiance tel
## quel : résolu par `resolve_final_agent_index` (verrouillage validé pendant
## la sélection d'équipe si présent, sinon bornage classique — voir sa doc).
@rpc("any_peer", "reliable")
func _request_spawn(agent_index: int) -> void:
	if multiplayer.is_server():
		var sender_id := multiplayer.get_remote_sender_id()
		_spawn_player(sender_id, resolve_final_agent_index(sender_id, agent_index))
		_leave_agent_select_after_spawn(sender_id)

func _on_player_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var node := get_node(players_root).get_node_or_null(str(id))
	if node:
		node.queue_free()
	if player_info.has(id):
		Telemetry.record(Telemetry.EVENT_ABANDON, {
			"player_id": id, "team": int(player_info[id].team),
		}, _match_id, true)
		player_info.erase(id)
		_sync_stats.rpc(player_info)
	# Un joueur peut se déconnecter EN COURS de sélection d'agent, avant tout
	# spawn (UX-11) : on libère sa place/son éventuel agent verrouillé pour le
	# reste de son équipe encore en train de choisir.
	var agent_select_team := int(_agent_select_team.get(id, -1))
	leave_agent_select(id)
	if agent_select_team >= 0:
		_broadcast_agent_picks(agent_select_team)
	# Un humain part : un bot peut prendre sa place (contract-r3.md :
	# "bots leave when humans join" — et symétriquement en reprennent la
	# place quand ils partent).
	call_deferred("_fill_bots_if_needed")

# ======================================================================
#  SÉLECTION D'AGENT D'ÉQUIPE (UX-11, docs/research/04_ui_ux.md §2.4) —
#  répartition d'équipe précoce (dès l'ouverture de l'écran, pas au spawn) +
#  synchronisation des choix/verrouillages entre COÉQUIPIERS SEULS (jamais
#  l'équipe adverse). Les fonctions ci-dessous sont volontairement PURES vis-
#  à-vis du réseau (aucun appel à `multiplayer`) pour rester testables sans
#  scène ni pair réseau réel (voir tests/networking/test_match_config_sync.gd
#  pour le même principe) ; seules les méthodes RPC en bas de section touchent
#  `multiplayer`, en pur relais vers elles.
# ======================================================================

## Assigne (ou retrouve, appel idempotent) l'équipe de `id` pour la phase de
## sélection — alternée comme l'ancien tirage au sort de `_spawn_player`,
## réutilisée telle quelle au spawn réel (voir son bloc `elif
## _agent_select_team.has(id)` ci-dessous).
func assign_agent_select_team(id: int) -> int:
	if not _agent_select_team.has(id):
		_agent_select_team[id] = _team_counter % team_count
		_team_counter += 1
	return _agent_select_team[id]

## Enregistre le choix COURANT de `id` (survol : `locked` faux : toujours
## accepté ; verrouillage : `locked` vrai) — renvoie faux et n'écrit RIEN si
## `id` n'a pas encore rejoint la sélection (`assign_agent_select_team` jamais
## appelé) ou si `agent_index` est déjà VERROUILLÉ par un coéquipier (UX-11 :
## "deux coéquipiers ne peuvent pas verrouiller le même agent").
## `agent_index` n'est jamais fait confiance tel quel : borné à la plage des
## agents connus, comme `_request_spawn` historiquement.
func record_agent_pick(id: int, agent_index: int, locked: bool) -> bool:
	if not _agent_select_team.has(id):
		return false
	var team: int = _agent_select_team[id]
	var valid_index := clampi(agent_index, 0, AgentDatabase.all().size() - 1)
	if locked and is_agent_locked_by_teammate(_locked_teammate_indices(team, id), valid_index):
		return false
	_agent_picks[id] = {"agent_index": valid_index, "locked": locked, "name": _agent_pick_name(id)}
	return true

## Vrai si `agent_index` figure parmi `locked_indices` — fonction PURE (UX-11 :
## "deux coéquipiers ne peuvent pas verrouiller le même agent"), isolée pour
## rester testable directement, comme `spawn_side_for` ci-dessous.
static func is_agent_locked_by_teammate(locked_indices: Array, agent_index: int) -> bool:
	return locked_indices.has(agent_index)

## Index d'agents déjà VERROUILLÉS par les membres de `team` autres que
## `excluding_id` — jamais les bots (absents de `_agent_picks`, voir sa doc).
func _locked_teammate_indices(team: int, excluding_id: int) -> Array:
	var out: Array = []
	for pid in _agent_picks:
		if pid == excluding_id:
			continue
		if int(_agent_select_team.get(pid, -1)) != team:
			continue
		var p: Dictionary = _agent_picks[pid]
		if bool(p.get("locked", false)):
			out.append(int(p.get("agent_index", -1)))
	return out

## État courant (choix/verrouillage) de TOUS les membres HUMAINS de `team` en
## cours de sélection — jamais l'équipe adverse (UX-11 : "les choix des
## coéquipiers"). Copie défensive : l'appelant (diffusion RPC) ne doit jamais
## pouvoir modifier l'état serveur en modifiant le dictionnaire renvoyé.
func agent_picks_roster(team: int) -> Dictionary:
	var out := {}
	for pid in _agent_select_team:
		if int(_agent_select_team[pid]) == team and _agent_picks.has(pid):
			out[pid] = (_agent_picks[pid] as Dictionary).duplicate()
	return out

## Referme la participation de `id` à la sélection d'agent (retire ses
## entrées de `_agent_select_team`/`_agent_picks`) — appelé au moment de son
## spawn RÉEL (`_leave_agent_select_after_spawn`) ou de sa déconnexion, jamais
## avant : tant qu'il n'a pas explicitement quitté, son verrouillage continue
## de bloquer ses coéquipiers (c'est tout le sens de la contrainte UX-11).
func leave_agent_select(id: int) -> void:
	_agent_picks.erase(id)
	_agent_select_team.erase(id)

## Agent FINAL à utiliser pour le spawn de `id` : celui qu'il a réellement
## verrouillé pendant la sélection s'il y en a un (jamais un doublon d'un
## coéquipier, la validation a déjà eu lieu dans `record_agent_pick`), sinon
## `requested_index` borné classiquement — mais alors, si ce dernier se
## trouve malgré tout être verrouillé par un coéquipier (course : le
## verrouillage a été REJETÉ juste avant ce spawn, voir `_apply_remote_agent_pick`),
## on retombe sur le premier agent encore libre plutôt que dupliquer un agent
## déjà pris, même dans ce cas extrême. Appelée AVANT `leave_agent_select`
## (voir `_leave_agent_select_after_spawn`, appelée juste après le spawn par
## `_spawn_local`/`_request_spawn`) : lit encore l'état de sélection de `id`.
func resolve_final_agent_index(id: int, requested_index: int) -> int:
	var agent_count := AgentDatabase.all().size()
	var valid_index := clampi(requested_index, 0, agent_count - 1)
	if _agent_picks.has(id) and bool(_agent_picks[id].locked):
		return clampi(int(_agent_picks[id].agent_index), 0, agent_count - 1)
	var team := int(_agent_select_team.get(id, -1))
	if team < 0 or not is_agent_locked_by_teammate(_locked_teammate_indices(team, id), valid_index):
		return valid_index
	for i in agent_count:
		if not is_agent_locked_by_teammate(_locked_teammate_indices(team, id), i):
			return i
	return valid_index  # cas extrême (plus un seul agent libre) : jamais bloquer le spawn.

## Referme la participation de `id` à la sélection d'agent JUSTE APRÈS son
## spawn réel (voir `resolve_final_agent_index`, qui doit encore lire son état
## AVANT cet appel) et informe le reste de son équipe que sa place/son agent
## se libèrent.
func _leave_agent_select_after_spawn(id: int) -> void:
	var team := int(_agent_select_team.get(id, -1))
	leave_agent_select(id)
	if team >= 0:
		_broadcast_agent_picks(team)

func _agent_select_display_name(id: int) -> String:
	return "Joueur %d" % id

## Nom d'affichage courant de `id` dans `_agent_picks` (retombe sur le nom par
## défaut s'il n'a pas encore d'entrée).
func _agent_pick_name(id: int) -> String:
	return String(_agent_picks[id].name) if _agent_picks.has(id) else _agent_select_display_name(id)

## Diffuse l'état COURANT de `team` à tous ses membres HUMAINS connus — appel
## DIRECT pour l'hôte (peer 1, architecture "hôte simulé côté serveur" : pas
## de RPC à soi-même), RPC ciblée pour les autres. Jamais l'équipe adverse.
func _broadcast_agent_picks(team: int) -> void:
	var roster := agent_picks_roster(team)
	for pid in _agent_select_team.keys():
		if int(_agent_select_team[pid]) != team:
			continue
		if pid == 1:
			if is_instance_valid(_agent_select_screen):
				_agent_select_screen.on_picks_updated(team, roster)
		else:
			_sync_agent_picks.rpc_id(pid, team, roster)

@rpc("authority", "reliable")
func _sync_agent_picks(team: int, roster: Dictionary) -> void:
	if is_instance_valid(_agent_select_screen):
		_agent_select_screen.on_picks_updated(team, roster)

func _notify_pick_rejected(id: int, agent_index: int) -> void:
	if id == 1:
		if is_instance_valid(_agent_select_screen):
			_agent_select_screen.on_pick_rejected(agent_index)
	else:
		_agent_pick_rejected.rpc_id(id, agent_index)

@rpc("authority", "reliable")
func _agent_pick_rejected(agent_index: int) -> void:
	if is_instance_valid(_agent_select_screen):
		_agent_select_screen.on_pick_rejected(agent_index)

## Point d'entrée commun (hôte en appel direct, client via RPC ci-dessous) à
## chaque changement de survol/verrouillage LOCAL à ce pair.
func _apply_remote_agent_pick(id: int, agent_index: int, locked: bool) -> void:
	var team := int(_agent_select_team.get(id, -1))
	if team < 0:
		return  # sélection jamais rejointe (RPC hors séquence) : ignoré.
	if record_agent_pick(id, agent_index, locked):
		_broadcast_agent_picks(team)
	elif locked:
		_notify_pick_rejected(id, clampi(agent_index, 0, AgentDatabase.all().size() - 1))

func _on_local_agent_picked(index: int) -> void:
	if multiplayer.is_server():
		_apply_remote_agent_pick(multiplayer.get_unique_id(), index, false)
	else:
		_server_agent_pick.rpc_id(1, index, false)

func _on_local_agent_locked() -> void:
	if multiplayer.is_server():
		_apply_remote_agent_pick(multiplayer.get_unique_id(), AgentDatabase.selected_index, true)
	else:
		_server_agent_pick.rpc_id(1, AgentDatabase.selected_index, true)

## Le client annonce qu'il rejoint la sélection d'agent, avec sa présélection
## COURANTE (dernier agent joué, voir AgentSelectScreen._ready) : le serveur
## lui assigne une équipe et diffuse l'état à ses coéquipiers.
@rpc("any_peer", "reliable")
func _server_join_agent_select(agent_index: int) -> void:
	if multiplayer.is_server():
		var sender_id := multiplayer.get_remote_sender_id()
		var team := assign_agent_select_team(sender_id)
		record_agent_pick(sender_id, agent_index, false)
		_broadcast_agent_picks(team)

## Le client annonce un changement de survol (`locked` faux) ou un
## verrouillage (`locked` vrai) — un verrouillage refusé (agent déjà pris par
## un coéquipier) est signalé au SEUL expéditeur via `_notify_pick_rejected`,
## jamais utilisé pour un spawn réel (voir `resolve_final_agent_index`).
@rpc("any_peer", "reliable")
func _server_agent_pick(agent_index: int, locked: bool) -> void:
	if multiplayer.is_server():
		_apply_remote_agent_pick(multiplayer.get_remote_sender_id(), agent_index, locked)

## `is_bot`/`forced_team`/`display_name` : réservés à `_spawn_bot` (un humain
## garde l'appel à 2 arguments existant, équipe alternée automatique).
## `spawn_override` (LD-23) : position DÉJÀ choisie par un lot
## `_get_team_spawn_positions` (anti-empilement ≥ 3 m entre plusieurs bots
## ajoutés à la même équipe à la même seconde, voir `_sync_team_bots`) —
## `_NO_SPAWN_OVERRIDE` (défaut) laisse ce spawn choisir SA PROPRE position
## via `_get_spawn_position` comme avant cette tâche (humain, bot isolé).
func _spawn_player(id: int, agent_index: int, is_bot: bool = false, forced_team: int = -1, display_name: String = "", spawn_override: Vector3 = _NO_SPAWN_OVERRIDE) -> void:
	if player_scene == null:
		push_error("player_scene non assignée sur GameWorld.")
		return
	# Anti double-spawn (si une demande arrive deux fois).
	if get_node(players_root).has_node(str(id)):
		return
	var player := player_scene.instantiate()
	player.name = str(id)  # nom = id => réplication propre par le spawner.
	# Équipe : imposée pour un bot (remplissage ciblé) ; sinon celle déjà
	# assignée dès l'ouverture de l'écran de sélection d'agent si ce joueur y
	# est passé (UX-11 : `assign_agent_select_team`, appelé par
	# `_open_agent_select`/`_server_join_agent_select` bien avant ce spawn ;
	# `_leave_agent_select_after_spawn`, appelé par `_spawn_local`/
	# `_request_spawn` juste APRÈS `_spawn_player`, l'efface ensuite) ; sinon
	# alternée comme avant cette tâche (ex. training, agent_select=false).
	var team: int
	if forced_team >= 0:
		team = forced_team
	elif _agent_select_team.has(id):
		team = _agent_select_team[id]
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
	# le point de respawn. `spawn_override` : voir sa doc ci-dessus (LD-23).
	var spawn := spawn_override if spawn_override != _NO_SPAWN_OVERRIDE else _get_spawn_position(team)
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
	_mark_spawned(id)
	Telemetry.record(Telemetry.EVENT_SPAWN, {
		"player_id": id, "team": team, "pos": _vec_to_array(spawn), "is_bot": is_bot,
	}, _match_id, true)

	# Le serveur écoute la mort/les dégâts de ce joueur (respawn, charge d'ultime,
	# AssistTracker -- `_on_player_damaged` a besoin de savoir QUI a été touché,
	# `Health.damaged` ne porte que l'attaquant, d'où le `.bind(id)`, même
	# patron que `_on_player_died.bind(player)` juste au-dessus).
	var hp := player.get_node_or_null("Health") as Health
	if hp:
		hp.died.connect(_on_player_died.bind(player))
		hp.damaged.connect(_on_player_damaged.bind(id))

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
	_record_recent_death(player)
	# GF-22 (docs/research/10_ammo_kits_input.md §2.4, « Cartouchière ») :
	# capture la position DE LA MORT avant toute téléportation de respawn plus
	# bas (`_teleport_player` déplace ce même nœud `player`) — même prudence que
	# `_record_recent_death` juste au-dessus, qui lit `global_position` pour la
	# même raison.
	var death_pos: Vector3 = (player as Node3D).global_position
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode != null and mode.has_method("respawns_immediately") and not mode.respawns_immediately():
		return  # mode à manches (SnD/Duel) : pas de respawn avant la prochaine manche, PAS de cartouchière (§2.2 : absente en Litige/Duel)
	# GF-22 §2.4 : la cartouchière apparaît IMMÉDIATEMENT à la mort (« reste 20 s »
	# depuis cet instant), pas après `respawn_delay` — indépendante du respawn du
	# joueur ci-dessous. Seuls les modes d'arène (TDM/Hardpoint) et l'absence de
	# mode (entraînement) atteignent cette ligne, comme `server_refill_ammo` plus
	# bas (même retour anticipé ci-dessus).
	_server_spawn_ammo_pack(death_pos + Vector3(0, 0.3, 0))
	# Respawn après délai (arène : TDM/Hardpoint/entraînement).
	await get_tree().create_timer(respawn_delay).timeout
	if not is_instance_valid(player):
		return
	var team: int = player.get("team")
	var spawn := _get_spawn_position(team)
	_teleport_player(player, spawn)
	_mark_spawned(str(player.name).to_int())
	var hp := player.get_node_or_null("Health") as Health
	if hp:
		hp.reset()
		hp.spawn_protection(1.0)
	# GF-20 (docs/research/10_ammo_kits_input.md §2.1) : Weapon.server_refill_ammo()
	# existait déjà mais n'avait AUCUN appelant — après 2-3 vies le loadout
	# restait à sec pour le reste du match (Mêlée/Borne/entraînement, les seuls
	# modes qui atteignent cette ligne : SnD/Duel sont déjà repartis plus haut,
	# ils rechargent au round via leur propre `_after_round_respawn`). Appel
	# DIRECT (même patron que `ab.server_refill()` dans `respawn_all_for_round`
	# ci-dessous) : on est déjà côté serveur, et `server_refill_ammo()` pousse
	# lui-même la correction au propriétaire une fois l'inventaire autoritaire
	# rempli — ses propres garde-fous couvrent hôte/bot simulés ICI (appel
	# direct, `_apply_sync`) comme le client distant répliqué (RPC vers son id).
	var weapon := player.get_node_or_null("Weapon")
	if weapon and weapon.has_method("server_refill_ammo"):
		weapon.server_refill_ammo()

## Économie d'ultime (§3.4, docs/research/10_ammo_kits_input.md, AGT-02) --
## l'ancienne économie (0,05 pt/dégât + 2 pts/kill, soit ~7 pts pour un kill à
## 100 dégâts) rechargeait l'ultime en un seul kill, pour un coût de 7 à 9.
## Ramenée à 0,01 pt/dégât + 1 pt/kill : un kill à 100 dégâts vaut 2 pts, un
## ultime à coût 8 se charge en ≈ 3 à 4 kills (voir les tests dédiés de
## test_ability_state.gd, qui référencent ces constantes).
const ULT_DAMAGE_RATE := 0.01
const ULT_KILL_POINTS := 1.0
## Litige (SnD)/Duel-Duo (mode à manches) : le gain continu
## (`AbilityState.ult_charge_rate`) est nul (coupé par
## `AbilityController._sync_ult_charge_rate`) et remplacé par ce bonus fixe à
## la pose ou au désamorçage (§3.4). Appelé par `SnDMode._do_plant`/`_do_defuse`
## (scripts/modes/SnDMode.gd) via `charge_ult_for_objective` ci-dessous.
const ULT_OBJECTIVE_POINTS := 1.0

## Charge l'ultime de l'ATTAQUANT à chaque dégât infligé (ULT_DAMAGE_RATE pt
## / dégât), en plus du bonus fixe sur kill (_record_kill). Alimente aussi
## l'AssistTracker PARTAGÉ à CHAQUE dégât serveur, quel que soit l'attaquant
## (dégât d'environnement/de soi-même compris -- `record_damage` les ignore
## lui-même, voir sa doc) : une mort ferme cette fenêtre plus bas
## (`_record_kill`).
func _on_player_damaged(amount: float, attacker_id: int, victim_id: int) -> void:
	if not multiplayer.is_server():
		return
	_assists.record_damage(victim_id, attacker_id, amount, Time.get_unix_time_from_system())
	if attacker_id <= 0:
		return
	_charge_ult(attacker_id, amount * ULT_DAMAGE_RATE)

# ---- Kills / stats / killfeed (serveur) ----
func _record_kill(killer_id: int, victim_id: int) -> void:
	var vteam: int = int(player_info[victim_id].team) if player_info.has(victim_id) else -1
	if player_info.has(victim_id):
		player_info[victim_id].deaths += 1
	var kteam: int = -1
	if killer_id > 0 and killer_id != victim_id and player_info.has(killer_id):
		player_info[killer_id].kills += 1
		kteam = int(player_info[killer_id].team)
		_charge_ult(killer_id, ULT_KILL_POINTS)
		# Passif du TUEUR (AGT-01 socle commun, §3.5 -- ex. Mèche courte de
		# Vif) : câblage laissé prêt par AGT-01, appelé ici.
		_notify_on_kill(killer_id, victim_id)
	# AssistTracker : ferme la fenêtre d'assistance de la victime dans TOUS
	# les cas (mort environnementale/de soi-même comprise -- voir la doc de
	# `assists_for_kill`), puis notifie le passif de chaque assistant retenu
	# (>= 40 dégâts cumulés dans les 5 s précédentes, tueur exclu).
	for assister_id in _assists.assists_for_kill(victim_id, killer_id, Time.get_unix_time_from_system()):
		_notify_on_assist(assister_id, victim_id)
	# Le mode peut réagir (TDM : kill = point d'équipe).
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode and mode.has_method("on_kill"):
		mode.on_kill(killer_id, victim_id, kteam, vteam)
	# Killfeed — arme/capacité ET headshot pour TOUT kill (relance QA UX-01,
	# bot contre bot compris) : mêmes résolveurs que `_log_kill_event`
	# ci-dessous (télémétrie), jamais une seconde logique qui pourrait diverger.
	var kname: String = player_info[killer_id].name if (killer_id > 0 and player_info.has(killer_id)) else "Environnement"
	var vname: String = player_info[victim_id].name if player_info.has(victim_id) else "?"
	var active_ability := _fresh_active_ability(killer_id)
	var weapon_or_ability := active_ability if active_ability != "" else _kill_weapon_name(killer_id)
	_killfeed.rpc(kname, vname, kteam, weapon_or_ability, _fresh_headshot(killer_id))
	_sync_stats.rpc(player_info)
	_log_kill_event(killer_id, victim_id, kteam, vteam)

## Nœud AbilityController ("Abilities") de `player_id`, ou `null` si le
## joueur est absent/déconnecté -- chemin partagé par `_charge_ult` et les
## hooks passif ci-dessous.
func _abilities_of(player_id: int) -> Node:
	var pnode := get_node(players_root).get_node_or_null(str(player_id))
	return pnode.get_node_or_null("Abilities") if pnode else null

func _charge_ult(player_id: int, points: float = ULT_KILL_POINTS) -> void:
	var ab := _abilities_of(player_id)
	# Appel DIRECT (pas de RPC) : on est déjà côté serveur, et
	# AbilityController.server_add_ult pousse lui-même la correction au
	# propriétaire une fois l'état autoritaire mis à jour.
	if ab and ab.has_method("server_add_ult"):
		ab.server_add_ult(points)

## Point d'entrée POSE/DÉSAMORÇAGE (Litige/SnD, §3.4) : +1 pt d'ultime pour
## `player_id`. Voir la doc de ULT_OBJECTIVE_POINTS ci-dessus. Appelé par
## `SnDMode._do_plant`/`_do_defuse` via son propre relais `_charge_ult_for_objective`
## (groupe "match", `has_method` -- SnDMode.gd n'a jamais de dépendance dure
## sur ce script).
func charge_ult_for_objective(player_id: int) -> void:
	_charge_ult(player_id, ULT_OBJECTIVE_POINTS)

## Notifie le passif du TUEUR (AbilityController.server_on_kill, AGT-01, §3.5)
## -- ex. Mèche courte de Vif (+1 charge de Ruée). Sans effet si l'agent n'a
## pas de passif ou si `killer_id` est introuvable (server_on_kill se garde
## lui-même côté serveur).
func _notify_on_kill(killer_id: int, victim_id: int) -> void:
	var ab := _abilities_of(killer_id)
	if ab and ab.has_method("server_on_kill"):
		ab.server_on_kill(victim_id)

## Idem pour chaque ASSISTANCE (AbilityController.server_on_assist, AGT-01).
func _notify_on_assist(assister_id: int, victim_id: int) -> void:
	var ab := _abilities_of(assister_id)
	if ab and ab.has_method("server_on_assist"):
		ab.server_on_assist(victim_id)

@rpc("authority", "call_local", "reliable")
func _sync_stats(data: Dictionary) -> void:
	player_info = data
	stats_changed.emit()

@rpc("authority", "call_local", "reliable")
func _killfeed(killer: String, victim: String, killer_team: int, weapon_or_ability: String, headshot: bool) -> void:
	kill_logged.emit(killer, victim, killer_team, weapon_or_ability, headshot)

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
	# FUN-01 : périme toute coroutine de compte à rebours automatique en vol
	# (voir `_run_rematch_countdown`) — qu'elle vienne de CE `reset_match` (la
	# revanche automatique elle-même appelle cette fonction en tout dernier)
	# ou d'un « Rejouer » manuel déclenché PENDANT le compte à rebours : dans
	# les deux cas, un seul reset doit avoir lieu, jamais un second 10 s plus
	# tard.
	_rematch_token += 1
	# Télémétrie : une revanche (FUN-01) est un nouveau match pour les stats
	# (remises à zéro juste après) — `match_end` de l'ancien puis `match_start`
	# du nouveau, avec un `match_id` frais diffusé à tous les pairs.
	_start_new_match()
	# BUG-03 : un mur/fumée/tremplin/piège/marqueur posé pendant le match
	# précédent ne doit pas survivre à la revanche (les modes à manches le
	# vident déjà à chaque nouvelle manche via _enter_buy_phase -> voir
	# RoundMode._clear_round_props -- mais un reset direct, ex. mode d'arène
	# TDM/Hardpoint sans phase d'achat, doit lui aussi passer par ici).
	clear_round_props()
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

# ======================================================================
#  ENCHAÎNEMENT DE SESSION (FUN-01, docs/research/05_fun_retention.md §2.1,
#  "Session (10–30 min) : un match, un écran de fin ... puis on rejoue") --
#  compte à rebours SERVEUR de `rematch_countdown_s` (10 s par défaut, exporté
#  pour un raccourci en test comme `respawn_delay` ci-dessus) déclenché dès que
#  le mode bascule en fin de partie (`mode.winner >= 0`, détecté par
#  `_watch_for_match_end`, appelée depuis `_process` -- édition sur le FRONT
#  montant seulement, `_rematch_watch_active` évite de relancer un second
#  compte à rebours tant que le premier n'est pas retombé).
#  Au bout du délai, si la MAJORITÉ des humains connus À LA FIN DU MATCH
#  (`player_info`, jamais un simple pair encore ouvert : couvre un humain qui
#  quitte PENDANT le compte à rebours, voir `_on_player_disconnected` qui
#  l'efface de `player_info`) est encore présente, les équipes sont
#  rééquilibrées (`_rebalance_teams_for_rematch`, humains ET bots confondus)
#  puis `reset_match()` relance MÊME mode/MÊME carte (aucun changement de
#  scène : on ne fait que remettre l'état à zéro, stats comprises). Sinon, la
#  revanche automatique est simplement abandonnée -- l'écran de fin reste
#  affiché, « Rejouer » manuel (`request_reset`) reste possible.
#  `rematch_countdown` (secondes RESTANTES, -1 = annulée) est diffusé à tous
#  les pairs via `_broadcast_rematch_countdown` : EndPanel.gd s'y abonne
#  directement (hors GameHUD.gd, non possédé ici) pour afficher le compte à
#  rebours sans dépendre d'un appel par-frame externe.
# ======================================================================

@export var rematch_countdown_s: float = 10.0

## Secondes restantes (diffusion `_broadcast_rematch_countdown`), -1 = compte
## à rebours annulé (majorité des humains partie) -- EndPanel.gd s'y abonne.
signal rematch_countdown(seconds_left: int)

var _rematch_watch_active: bool = false
## Incrémenté à CHAQUE `reset_match()` (manuel ou automatique) -- une
## coroutine de compte à rebours qui se réveille après un token périmé
## s'arrête sans relancer une seconde revanche (voir `_run_rematch_countdown`).
var _rematch_token: int = 0

## Détecte le FRONT MONTANT "le mode vient de désigner un vainqueur" --
## appelée à chaque frame SERVEUR depuis `_process`. Duck-typing (`mode.get`)
## comme `_sides_swapped()`/`_emit_match_end()` : `mode` reste un `Node` nu,
## GameMode.gd est hors de ma liste de fichiers.
func _watch_for_match_end() -> void:
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode == null:
		return
	var winner_v = mode.get("winner")
	var over: bool = winner_v != null and int(winner_v) >= 0
	if over and not _rematch_watch_active:
		_rematch_watch_active = true
		_run_rematch_countdown()
	elif not over:
		_rematch_watch_active = false

## Identifiants HUMAINS (jamais un bot) actuellement connus de `player_info`.
func _human_ids_present() -> Array:
	var out: Array = []
	for id in player_info.keys():
		if not bool(player_info[id].get("is_bot", false)):
			out.append(id)
	return out

## Vrai si au moins la MOITIÉ de `before` (humains présents à la fin du match)
## sont encore des humains connus MAINTENANT (`player_info`) -- un humain qui
## est parti entre-temps (déconnecté, voir `_on_player_disconnected`) ne
## compte plus. `before` vide (aucun humain au moment de la fin -- ex. training
## bots seuls) : jamais de revanche automatique, rien à relancer pour personne.
func _majority_of_humans_still_present(before: Array) -> bool:
	if before.is_empty():
		return false
	var still := 0
	for id in before:
		if player_info.has(id) and not bool(player_info[id].get("is_bot", false)):
			still += 1
	return still * 2 >= before.size()

## Compte à rebours serveur (voir doc de section ci-dessus). `await` DIRECT
## dans cette fonction (jamais une lambda qui capturerait `self` dans
## `get_tree().create_timer()` -- règle de tête de fichier du projet, même
## patron que `_on_player_died`) : `is_instance_valid(self)` après CHAQUE
## `await` protège contre ce nœud libéré entre-temps (scène quittée -- ex.
## l'hôte revient au menu pendant le compte à rebours), et la comparaison de
## `token` protège contre un « Rejouer » manuel survenu entre-temps (déjà géré
## par un `reset_match()` propre à lui, voir sa doc).
func _run_rematch_countdown() -> void:
	var token := _rematch_token
	var humans_at_end := _human_ids_present()
	# `ticks` : un tic par seconde ENTIÈRE à la durée par défaut (10 -> 10 tics
	# d'1,0 s pile, l'affichage "compte à rebours de 10 s" du contrat) ; une
	# `rematch_countdown_s` raccourcie en test (voir doc de l'export ci-dessus,
	# même convention que `respawn_delay`) réduit `tick_duration` en proportion
	# au lieu de forcer chaque tic à durer 1 s réelle quel que soit le réglage.
	var ticks := maxi(int(ceil(rematch_countdown_s)), 1)
	var tick_duration := rematch_countdown_s / float(ticks)
	var seconds_left := ticks
	_broadcast_rematch_countdown.rpc(seconds_left)
	while seconds_left > 0:
		await get_tree().create_timer(tick_duration).timeout
		if not is_instance_valid(self) or token != _rematch_token:
			return
		seconds_left -= 1
		_broadcast_rematch_countdown.rpc(seconds_left)
	if not is_instance_valid(self) or token != _rematch_token:
		return
	if _majority_of_humans_still_present(humans_at_end):
		_rebalance_teams_for_rematch()
		_fill_bots_if_needed()
		reset_match()
		# PAS de `_rematch_watch_active = false` ici : `reset_match()` fait
		# retomber `mode.winner` à -1 (mode.reset_match(), voir tests/modes/
		# test_rematch_reset.gd) dès le PROCHAIN `_process` -- c'est la branche
		# `elif not over` de `_watch_for_match_end` qui le remet à jour, prête
		# pour la PROCHAINE fin de match.
	else:
		# Revanche automatique ABANDONNÉE (majorité partie) : `mode.winner`
		# reste TEL QUEL (>= 0, aucun reset) -- si on remettait
		# `_rematch_watch_active` à faux ici, `_watch_for_match_end` verrait
		# `over` encore vrai au PROCHAIN `_process` et relancerait aussitôt un
		# second compte à rebours (avec un nouveau `humans_at_end`, capturé
		# APRÈS le départ de la majorité -- pouvant à tort se solder par une
		# revanche quand même). Un seul essai par fin de match : reste armé
		# jusqu'à ce qu'un « Rejouer » manuel ou une nouvelle fin de match
		# (`mode.winner` retombé à -1 puis remonté) réarme proprement le
		# guetteur.
		_broadcast_rematch_countdown.rpc(-1)

@rpc("authority", "call_local", "reliable")
func _broadcast_rematch_countdown(seconds_left: int) -> void:
	rematch_countdown.emit(seconds_left)

## Répartit à parts égales (têtes, humains ET bots confondus) les joueurs
## ACTUELS entre les `team_count` équipes -- appelé juste avant `reset_match()`
## par la revanche AUTOMATIQUE seulement (FUN-01 : « équipes rééquilibrées »).
## Un « Rejouer » manuel (`request_reset`/`reset_match` seuls) garde les
## équipes telles quelles, comportement inchangé. Ordre déterministe (id
## croissant, humains < PlayerController.BOT_ID_START < bots) : stable et
## testable, jamais un tirage au sort.
func _rebalance_teams_for_rematch() -> void:
	var ids: Array = player_info.keys()
	ids.sort()
	var pr := get_node_or_null(players_root)
	for i in ids.size():
		var id = ids[i]
		var team := i % team_count
		player_info[id].team = team
		var node := pr.get_node_or_null(str(id)) if pr else null
		if node:
			node.set("team", team)
	_team_counter = ids.size()

## Respawn TOUS les joueurs actuels (vivants ou morts) au début d'une nouvelle
## manche (SnD/Duel, appelé par RoundMode._enter_buy_phase) : pleine vie,
## position d'équipe et courte protection de spawn. Ne touche PAS l'inventaire
## d'armes (RoundMode gère survivants/loadout imposé après cet appel).
func respawn_all_for_round() -> void:
	if not multiplayer.is_server():
		return
	_round_index += 1
	Telemetry.record(Telemetry.EVENT_ROUND_START, {"round_index": _round_index}, _match_id, true)
	# LD-23 : TOUS les joueurs actuels respawnent ici à la même seconde
	# (nouvelle manche RoundMode via `RoundMode._respawn_all_for_round`, ou
	# reset de match) — un lot `pick_spawn_set` PAR ÉQUIPE (anti-empilement
	# ≥ 3 m), même raisonnement que `_sync_team_bots` ci-dessus, plutôt qu'un
	# `_get_spawn_position` isolé par joueur.
	var by_team: Dictionary = {}
	for child in get_node(players_root).get_children():
		var team := int(child.get("team"))
		if not by_team.has(team):
			by_team[team] = []
		by_team[team].append(child)
	for team in by_team.keys():
		var squad: Array = by_team[team]
		var spawn_batch := _get_team_spawn_positions(team, squad.size())
		for i in squad.size():
			var child: Node = squad[i]
			# Repli sur un pick isolé si le lot est plus court que l'équipe
			# (seulement possible avec `spawn_points_root` vide/dégénéré, voir
			# `_team_spawn_marker_positions`) : jamais d'index hors bornes.
			var spawn: Vector3 = spawn_batch[i] if i < spawn_batch.size() else _get_spawn_position(team)
			_teleport_player(child, spawn)
			_mark_spawned(int(child.name))
			var hp := child.get_node_or_null("Health") as Health
			if hp:
				hp.reset()
				hp.spawn_protection(1.0)
			# BUG-03/BUG-04 : recharge les capacités de base (pas l'ultime) au
			# début de chaque manche (AbilityState.refill()). Appel DIRECT,
			# comme _charge_ult : on est déjà côté serveur, et
			# server_refill() pousse lui-même la correction au propriétaire
			# une fois l'état autoritaire mis à jour.
			var ab := child.get_node_or_null("Abilities")
			if ab and ab.has_method("server_refill"):
				ab.server_refill()

## Vide le groupe "round_props" (murs/fumées/tremplins/pièges/marqueurs posés
## par AbilityController, voir sa doc d'en-tête) sur TOUS les pairs — ces
## objets sont répliqués (RPC "authority"/"call_local" à la pose), donc leur
## suppression doit l'être aussi, sinon ils restent visibles/bloquants chez
## les clients alors qu'ils ont disparu chez le serveur (BUG-03). Appelé par
## RoundMode._clear_round_props (passage en phase d'achat) et par
## `reset_match()` ci-dessus (couvre aussi les modes d'arène, sans phase
## d'achat).
func clear_round_props() -> void:
	if multiplayer.is_server():
		_clear_round_props.rpc()

@rpc("authority", "call_local", "reliable")
func _clear_round_props() -> void:
	for prop in get_tree().get_nodes_in_group("round_props"):
		if is_instance_valid(prop):
			prop.queue_free()

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
#  CARTOUCHIÈRE (GF-22, docs/research/10_ammo_kits_input.md §2.4) — apparition
#  répliquée (même patron que `_broadcast_world_spawn`/`_broadcast_world_despawn`
#  de Weapon.gd pour les armes au sol, hébergé ICI plutôt que sur Weapon.gd
#  car une cartouchière n'appartient à AUCUNE arme/joueur en particulier ;
#  GameWorld, racine du niveau, existe identiquement sur tous les pairs et
#  porte déjà l'autorité serveur — `set_multiplayer_authority(1)` dans
#  `_ready()`). AmmoPack.gd tient son propre registre STATIQUE uid -> instance
#  (comme WorldWeapon._registry) : `active_count()`/`oldest_uid()` reflètent
#  donc exactement ce qui est RÉELLEMENT rendu sur CE pair (y compris après
#  une expiration naturelle par la minuterie locale d'AmmoPack, §2.4 « reste
#  20 s » — voir sa doc), sans double comptage à tenir ici.
# ======================================================================
const AMMO_PACK_MAX := 16  # §2.4 : "16 au plus. La plus ancienne disparaît."

var _next_ammo_pack_uid: int = 1  # compteur d'uid, comme Weapon._next_world_uid

## Fait apparaître une cartouchière à `pos` pour tous les pairs — appelé
## UNIQUEMENT par `_on_player_died` ci-dessus (arène/entraînement, jamais
## Litige/Duel, voir son retour anticipé). Plafond de 16 : la plus ancienne
## ENCORE VIVANTE (`AmmoPack.oldest_uid()`, ordre d'insertion du registre
## statique) est retirée avant d'ajouter la nouvelle.
func _server_spawn_ammo_pack(pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if AmmoPack.active_count() >= AMMO_PACK_MAX:
		var oldest := AmmoPack.oldest_uid()
		if oldest != -1:
			_broadcast_ammo_pack_despawn.rpc(oldest)
	var uid := _next_ammo_pack_uid
	_next_ammo_pack_uid += 1
	_broadcast_ammo_pack_spawn.rpc(uid, pos)

## Appelé par une AmmoPack elle-même (SERVEUR uniquement, voir
## AmmoPack._grant_pickup) une fois un ramassage EFFECTIF (au moins une
## réserve augmentée, `Weapon.server_add_reserve_mags` — §2.4 : « si l'une de
## ses réserves n'est pas pleine ») : diffuse sa disparition à tous les pairs.
## Nom PUBLIC (sans underscore, contrairement aux RPC ci-dessous) : point
## d'entrée d'un autre script, comme `Weapon.server_refill_ammo`.
func server_despawn_ammo_pack(uid: int) -> void:
	if not multiplayer.is_server():
		return
	_broadcast_ammo_pack_despawn.rpc(uid)

@rpc("authority", "call_local", "reliable")
func _broadcast_ammo_pack_spawn(uid: int, pos: Vector3) -> void:
	AmmoPack.spawn_local(uid, pos, get_tree().current_scene)

@rpc("authority", "call_local", "reliable")
func _broadcast_ammo_pack_despawn(uid: int) -> void:
	AmmoPack.despawn_local(uid)

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
	# Équipe incomplète : on complète avec des bots. LD-23 : tous les bots
	# manquants de CETTE équipe partagent UN SEUL lot `pick_spawn_set` (via
	# `_get_team_spawn_positions`) au lieu d'un `_get_spawn_position` par bot
	# — un `pick_best` isolé par bot est la cause structurelle de
	# l'empilement observé en télémétrie (le bonus "allié proche" de
	# `SpawnPick.score` récompense un point collé au bot déjà spawné juste
	# avant, voir la doc de classe de `SpawnPick.pick_spawn_set`).
	var to_add := wanted_bots - bots.size()
	if to_add > 0:
		# `_living_ally_positions(team)` ICI = les coéquipiers déjà spawnés
		# AVANT ce lot (ex. l'hôte humain) — voir la doc de `exclude_positions`
		# sur `_get_team_spawn_positions` : aucun des `to_add` bots ajoutés
		# ci-dessous n'existe encore, donc rien à en exclure par erreur.
		var spawn_batch := _get_team_spawn_positions(team, to_add, _living_ally_positions(team))
		for spawn_pos in spawn_batch:
			bots.append(_spawn_bot(team, spawn_pos))

func _spawn_bot(team: int, spawn_pos: Vector3) -> int:
	var id := _next_bot_id
	_next_bot_id += 1
	var agent_count := AgentDatabase.all().size()
	var agent_index := randi() % maxi(agent_count, 1)
	_spawn_player(id, agent_index, true, team, _pick_bot_name(), spawn_pos)
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
## partie) => tableau vide : `SpawnPick.score`/`pick_best` retombent alors
## sur les seuls signaux restants (alliés/morts récentes), ou le tourniquet
## round-robin si eux aussi sont vides — comportement inchangé dans ce cas.
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

## Positions des ALLIÉS vivants (même équipe) — LD-02, bonus de regroupement
## de `SpawnPick.score`. Le joueur qui va spawn n'est pas encore dans
## `players_root` à cet instant (voir `_spawn_player`/`_on_player_died`), donc
## rien à exclure explicitement.
func _living_ally_positions(team: int) -> Array:
	var out: Array = []
	var pr := get_node_or_null(players_root)
	if pr == null:
		return out
	for child in pr.get_children():
		if int(child.get("team")) != team:
			continue
		var hp := child.get_node_or_null("Health") as Health
		if hp and hp.is_dead:
			continue
		out.append((child as Node3D).global_position)
	return out

## Enregistre la mort d'un joueur (position + horodatage) dans l'historique
## de SON équipe — LD-02 : `SpawnPick.score` pénalise un point où un allié
## est mort il y a moins de 5 s. Appelé depuis `_on_player_died`, AVANT toute
## téléportation du cadavre : `player.global_position` est encore le lieu de
## la mort.
func _record_recent_death(player: Node) -> void:
	var team := int(player.get("team"))
	var pos: Vector3 = (player as Node3D).global_position
	var now := Time.get_unix_time_from_system()
	var list: Array = _recent_deaths_by_team.get(team, [])
	list.append({"pos": pos, "t": now})
	var kept: Array = []
	for d in list:
		if now - float(d.t) <= _RECENT_DEATH_HISTORY_S:
			kept.append(d)
	_recent_deaths_by_team[team] = kept

## Morts récentes de l'équipe `team`, au format attendu par `SpawnPick.score`
## ({"pos": Vector3, "age": float} — secondes écoulées depuis la mort,
## calculées MAINTENANT, pas au moment de l'enregistrement).
func _recent_ally_deaths(team: int) -> Array:
	var out: Array = []
	if not _recent_deaths_by_team.has(team):
		return out
	var now := Time.get_unix_time_from_system()
	for d in _recent_deaths_by_team[team]:
		out.append({"pos": d.pos, "age": now - float(d.t)})
	return out

## Ligne de vue réelle (raycast, même convention que BotBrain._has_los) entre
## une CIBLE (ennemi vivant, ou centre de la zone active Hardpoint — même
## signature `Callable(point, target) -> bool`) et un point de spawn
## candidat, aux hauteurs d'œil (docs/research/03_level_design.md §3.1) :
## sert de `los_fn` à `SpawnPick.score` ET de `hp_los_fn` à
## `SpawnPick.is_hardpoint_hazard`/`pick_best_hardpoint` (LD-23) — un raycast
## point-à-point n'a pas besoin de savoir CE QUI se trouve à l'autre bout.
## Rien à exclure du rayon (aucun corps de joueur n'existe encore au point
## candidat).
func _spawn_enemy_has_los(point: Vector3, target_pos: Vector3) -> bool:
	var world := get_world_3d()
	if world == null:
		return true  # hors de l'arbre (ne devrait pas arriver en jeu réel) : suppose visible par prudence.
	var eye := Vector3.UP * _SPAWN_EYE_HEIGHT
	var space := world.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(target_pos + eye, point + eye)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	return hit.is_empty()

## Positions candidates (Vector3) pour un spawn de `team`, compte tenu de
## l'échange de côté (voir `spawn_side_for`) — factorisé hors de
## `_get_spawn_position`/`_get_team_spawn_positions` (LD-23), pour ne
## résoudre les marqueurs de la scène qu'une fois par appel au lieu d'une
## fois par joueur d'un même lot.
func _team_spawn_marker_positions(team: int) -> Array:
	var root := get_node_or_null(spawn_points_root)
	if root == null or root.get_child_count() == 0:
		return [Vector3(0, 1.5, 0)]
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
	return positions

## État de la zone active Hardpoint (LD-23, docs/research/09_wasteland_
## vertical_slice.md §c.4), lu par duck-typing sur le mode courant — même
## patron que `_sides_swapped()` ci-dessus (`Object.get()` renvoie `null` si
## la propriété n'existe pas sur ce mode, sans erreur : voir la doc Godot de
## `Object.get`). `HardpointMode.gd` est hors du périmètre de cette tâche,
## d'où la lecture indirecte de sa variable `_zone` (un `Area3D`, préfixe `_`
## = convention de nommage, pas une restriction du langage) plutôt qu'un
## appel de méthode publique dédiée. `active` faux pour tout mode SANS zone
## (TDM, modes à manches) ou avant que `HardpointMode._ready()` n'ait posé sa
## première zone : dans les deux cas, aucune pénalité Hardpoint ne doit
## s'appliquer, exactement comme `zone_active = false` dans
## `SpawnPick.pick_best_hardpoint` (voir sa doc de classe).
## `radius` : rayon du cercle circonscrit à l'emprise horizontale (X/Z) de la
## zone (`MapSetup._make_zone`, `BoxShape3D.size`) — ex. 10×4×10 m => ≈7,1 m,
## voir la doc de classe de `SpawnPick.is_hardpoint_hazard`. Calculé à
## l'exécution (jamais une constante par map) : la taille/l'emprise d'une
## zone Hardpoint est une donnée de carte, pas de code.
func _hardpoint_zone_state() -> Dictionary:
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode == null:
		return {"active": false, "center": Vector3.ZERO, "radius": 0.0}
	var zone_variant: Variant = mode.get("_zone")
	if not (zone_variant is Node3D):
		return {"active": false, "center": Vector3.ZERO, "radius": 0.0}
	var zone: Node3D = zone_variant
	var radius := 0.0
	for child in zone.get_children():
		if child is CollisionShape3D:
			var shape := (child as CollisionShape3D).shape
			if shape is BoxShape3D:
				var size: Vector3 = (shape as BoxShape3D).size
				radius = Vector2(size.x, size.z).length() * 0.5
				break
	return {"active": true, "center": zone.global_position, "radius": radius}

## Spawn d'UN joueur (respawn après mort, ou rejoint en cours de match — pas
## un lot, voir `_get_team_spawn_positions` pour ça). LD-02 : spawn dynamique
## noté (distance/ligne de vue ennemie, alliés proches, mort récente d'un
## allié) — remplace l'ancien `SpawnPick.safest` (laissé intact pour
## tests/modes/test_halftime.gd, qui le teste directement). LD-23 :
## `pick_best_hardpoint` au lieu de `pick_best` — ajoute la pénalité de zone
## Hardpoint active SANS rien changer hors Hardpoint (`zone_active = false`
## se comporte exactement comme `pick_best`, voir `_hardpoint_zone_state`).
func _get_spawn_position(team: int) -> Vector3:
	var positions := _team_spawn_marker_positions(team)
	var hp := _hardpoint_zone_state()
	var idx := SpawnPick.pick_best_hardpoint(
		positions,
		_living_enemy_positions(team),
		_living_ally_positions(team),
		_recent_ally_deaths(team),
		Callable(self, "_spawn_enemy_has_los"),
		hp.active, hp.center, hp.radius,
		Callable(self, "_spawn_enemy_has_los"),
		_spawn_index,
	)
	_spawn_index += 1
	return positions[idx]

## Spawn EN LOT de `count` joueurs de `team` qui apparaissent à LA MÊME
## seconde (remplissage initial des bots — `_sync_team_bots` — et respawn de
## manche — `respawn_all_for_round`) : LD-23, `SpawnPick.pick_spawn_set`
## impose un plancher DUR de 3 m entre les points choisis dans ce même lot,
## ce qu'un `_get_spawn_position` par joueur ne peut pas garantir (le bonus
## "allié proche" de `score()` récompense au contraire l'empilement — voir
## la doc de classe de `pick_spawn_set`).
## `exclude_positions` : marqueurs occupés par un coéquipier VIVANT qui ne
## fait PAS partie de ce lot (ex. l'hôte humain, déjà spawné avant le
## remplissage de ses bots par `_sync_team_bots` — voir sa doc). Nécessaire
## car `pick_spawn_set` ne connaît que les points choisis DANS SON PROPRE
## appel, jamais un point choisi par un appel PRÉCÉDENT : sans cette
## exclusion, un membre du lot pourrait atterrir EXACTEMENT sur le marqueur
## déjà occupé par ce coéquipier. Deux paliers, du plus au moins strict :
##   1. Exclusion STRICTE (≥ `_SPAWN_MIN_SEPARATION`, le "bon" cas) —
##      appliquée seulement si elle laisse au moins `count` marqueurs.
##   2. Exclusion DURE mais MINIMALE (le marqueur occupé LUI-MÊME
##      seulement, distance ~0) — TOUJOURS appliquée, même si elle ne
##      laisse pas `count` marqueurs : réutiliser À NOUVEAU le marqueur
##      EXACT d'un coéquipier est le seul cas strictement PIRE que
##      n'importe quelle autre alternative (garanti 0 m de séparation),
##      donc jamais préférable au repli "moins empilé" que `pick_spawn_set`
##      choisirait sinon lui-même parmi le reste. Constaté en pratique sur
##      Cargo Ship : 4 marqueurs par côté, mais seulement espacés de 2 m
##      entre voisins (< le plancher de 3 m) — la carte elle-même ne permet
##      PAS 4 spawns tous à ≥ 3 m les uns des autres (hors périmètre de
##      cette tâche, qui ne touche aucune scène de carte) ; le palier 1 (3 m)
##      élimine alors TOUS les marqueurs restants (y compris ceux à 2 m,
##      pourtant libres) et retombe sur le palier 2, qui garantit au moins
##      des positions DISTINCTES entre coéquipiers, même si certaines paires
##      restent sous 3 m faute d'assez de marqueurs bien espacés.
## Vide par défaut : `respawn_all_for_round` respawne le lot ENTIER d'une
## équipe (aucun coéquipier "hors du lot" à exclure — les positions
## ACTUELLES de ce même lot, avant téléportation, n'ont aucun sens comme
## exclusion, voir son appel).
## Zone Hardpoint active : `pick_spawn_set` (fonction pure LD-02, non
## modifiée par cette tâche) ignore aussi la notion de zone — même principe,
## on PRÉ-FILTRE les points dangereux (`SpawnPick.is_hardpoint_hazard`)
## ENSUITE. Chaque pré-filtre retombe sur la liste qui l'a précédé si
## l'exclusion ne laisse pas assez de points pour tout le lot (jamais un lot
## plus court que `count` par excès de prudence — même principe de repli que
## les fonctions pures elles-mêmes).
func _get_team_spawn_positions(team: int, count: int, exclude_positions: Array = []) -> Array:
	if count <= 0:
		return []
	var positions := _team_spawn_marker_positions(team)
	if not exclude_positions.is_empty():
		# Palier 2 (dur, minimal) : jamais le marqueur EXACT déjà occupé —
		# toujours retiré, quitte à repasser sous `count` marqueurs (repli
		# assumé, voir la doc ci-dessus).
		var not_exact_duplicate: Array = []
		for p in positions:
			var is_exact_duplicate := false
			for o in exclude_positions:
				if (p as Vector3).distance_to(o) < 0.05:
					is_exact_duplicate = true
					break
			if not is_exact_duplicate:
				not_exact_duplicate.append(p)
		positions = not_exact_duplicate
		# Palier 1 (souple, préféré) : le plancher `_SPAWN_MIN_SEPARATION`
		# complet, seulement s'il laisse encore assez de marqueurs pour tout
		# le lot.
		var free: Array = []
		for p in positions:
			var too_close := false
			for o in exclude_positions:
				if (p as Vector3).distance_to(o) < _SPAWN_MIN_SEPARATION:
					too_close = true
					break
			if not too_close:
				free.append(p)
		if free.size() >= count:
			positions = free
	var hp := _hardpoint_zone_state()
	if hp.active:
		var safe: Array = []
		for p in positions:
			if not SpawnPick.is_hardpoint_hazard(p, hp.center, hp.radius, Callable(self, "_spawn_enemy_has_los")):
				safe.append(p)
		if safe.size() >= count:
			positions = safe
	var chosen := SpawnPick.pick_spawn_set(
		positions, count,
		_living_enemy_positions(team), _living_ally_positions(team), _recent_ally_deaths(team),
		Callable(self, "_spawn_enemy_has_los"),
		_spawn_index, _SPAWN_MIN_SEPARATION,
	)
	_spawn_index += chosen.size()
	var out: Array = []
	for i in chosen:
		out.append(positions[i])
	return out

# ======================================================================
#  TÉLÉMÉTRIE (FUN-05, docs/research/05_fun_retention.md §5) — construit et
#  écrit les événements Telemetry.* : cycle de vie du match (match_start/
#  match_end/round_start), spawn, kill (corrélation tir/capacité — voir
#  `_on_player_node_spawned` ci-dessous), abandon (`_on_player_disconnected`
#  plus haut), performance (`match_perf`), capacité utilisée, agent choisi
#  (`_open_agent_select` plus haut). "purchase"/"round_end" restent hors
#  périmètre de cette tâche : le premier dépend de Weapon.gd/BuyMenu.gd (achat
#  d'arme), le second du gagnant de MANCHE décidé par RoundMode.gd — ni l'un
#  ni l'autre ne sont dans les fichiers possédés par FUN-05. Le schéma
#  (Telemetry._REQUIRED_FIELDS) les accepte déjà : câblage laissé à la tâche
#  qui possède ces fichiers.
# ======================================================================

func _generate_match_id() -> String:
	return "m_%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 100000]

## Termine le match courant s'il y en a un (`match_end` + `match_perf`), puis
## en démarre un nouveau : `match_id` frais diffusé à TOUS les pairs (voir
## `_broadcast_match_id`, dont un pair non-serveur a besoin pour rattacher
## ses propres événements locaux au bon match) et `match_start`. Serveur
## uniquement — appelé depuis `_ready` et `reset_match`, déjà gatés.
func _start_new_match() -> void:
	if _match_id != "":
		_emit_match_end()
	_match_id = _generate_match_id()
	_match_start_t = Time.get_unix_time_from_system()
	_round_index = 0
	_broadcast_match_id.rpc(_match_id)
	Telemetry.record(Telemetry.EVENT_MATCH_START, {
		"mode_id": MatchConfig.mode_id, "map_id": MatchConfig.map_id, "team_size": MatchConfig.team_size,
	}, _match_id, true)

func _emit_match_end() -> void:
	var mode := get_tree().get_first_node_in_group("game_mode")
	var winner_v = mode.get("winner") if mode else null
	var winner: int = int(winner_v) if winner_v != null else -1
	Telemetry.record(Telemetry.EVENT_MATCH_END, {
		"winner_team": winner, "duration_s": Time.get_unix_time_from_system() - _match_start_t,
	}, _match_id, true)
	# `call_local` : CHAQUE pair (dont ce serveur) émet et remet à zéro SA
	# PROPRE mesure de performance pour le match qui se termine (voir
	# `_flush_match_perf` : hors `Telemetry.GAME_EVENTS`, performance propre à
	# ce pair, pas un état de match autoritaire).
	_flush_match_perf.rpc(_match_id)

@rpc("authority", "call_local", "reliable")
func _broadcast_match_id(id: String) -> void:
	_match_id = id
	Telemetry.current_match_id = id

## `avg_fps`/`p99_ms` : mesurés LOCALEMENT par ce pair (`_frame_stats`,
## alimenté par `_process`). `avg_ping_ms` : voir `_average_ping_ms` (même API
## que PerfOverlay._ping_suffix, 0.0 si transport non-ENet ou aucun pair
## distant). `ended_match_id` : le match qui vient de finir (déjà remplacé
## dans `_match_id` par `_broadcast_match_id` au moment où ceci s'exécute
## ailleurs que sur l'appelant — d'où le paramètre explicite plutôt que lire
## `_match_id`).
@rpc("authority", "call_local", "reliable")
func _flush_match_perf(ended_match_id: String) -> void:
	Telemetry.record(Telemetry.EVENT_MATCH_PERF, {
		"avg_fps": _frame_stats.avg_fps(), "p99_ms": _frame_stats.p99_ms(),
		"avg_ping_ms": _average_ping_ms(),
	}, ended_match_id, false)
	_frame_stats.clear()

func _mark_spawned(id: int) -> void:
	_spawn_time[id] = Time.get_unix_time_from_system()

func _vec_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

## Nom de l'arme en main du TIREUR au moment du kill (Weapon.cfg(), lu depuis
## l'API PUBLIQUE du nœud) — "" si `killer_id` invalide/introuvable, jamais un
## nom inventé. Partagé par le killfeed (`_record_kill`) ET la télémétrie
## (`_log_kill_event`), UNE SEULE résolution plutôt que deux qui pourraient
## diverger (relance QA UX-01).
func _kill_weapon_name(killer_id: int) -> String:
	if killer_id <= 0:
		return ""
	var killer_node := get_node(players_root).get_node_or_null(str(killer_id))
	if killer_node == null:
		return ""
	var w := killer_node.get_node_or_null("Weapon")
	if w and w.has_method("cfg"):
		var c = w.cfg()
		if c:
			return c.weapon_name
	return ""

## Dernier tir confirmé du TIREUR encore FRAIS (voir `_last_headshot`/
## `_HEADSHOT_FRESHNESS_S`) — `false` au-delà de la fenêtre ou si inconnu,
## jamais une donnée inventée. Partagé par le killfeed ET la télémétrie.
func _fresh_headshot(killer_id: int) -> bool:
	var now := Time.get_unix_time_from_system()
	if _last_headshot.has(killer_id) and now - float(_last_headshot[killer_id].t) <= _HEADSHOT_FRESHNESS_S:
		return bool(_last_headshot[killer_id].headshot)
	return false

## Dernière capacité ACTIVÉE par le TIREUR encore FRAÎCHE (voir `_last_ability`/
## `_ABILITY_FRESHNESS_S`) — "" au-delà de la fenêtre ou si inconnue, jamais
## une donnée inventée. Partagé par le killfeed ET la télémétrie.
func _fresh_active_ability(killer_id: int) -> String:
	var now := Time.get_unix_time_from_system()
	if _last_ability.has(killer_id) and now - float(_last_ability[killer_id].t) <= _ABILITY_FRESHNESS_S:
		return String(_last_ability[killer_id].name)
	return ""

## Construit et écrit l'événement `kill` — appelée uniquement depuis
## `_record_kill`, déjà exécutée seulement côté serveur. `weapon`/
## `movement_state` : lus depuis les nœuds/API PUBLICS du tueur au moment du
## kill (Weapon.cfg(), PlayerController.anim_state décodé par
## CharacterAnimator.unpack_locomotion), sans dépendre d'aucun fichier hors
## du périmètre de cette tâche. `headshot`/`active_ability` : voir
## `_fresh_headshot`/`_fresh_active_ability` ci-dessus (mêmes résolveurs que le
## killfeed) — au-delà de leur fenêtre de fraîcheur, valeur par défaut
## `false`/"" (un kill SANS tir/capacité récent connu, jamais une donnée
## inventée).
func _log_kill_event(killer_id: int, victim_id: int, kteam: int, vteam: int) -> void:
	var players := get_node(players_root)
	var victim_node := players.get_node_or_null(str(victim_id))
	var killer_node := players.get_node_or_null(str(killer_id)) if killer_id > 0 else null
	var victim_pos: Vector3 = (victim_node as Node3D).global_position if victim_node is Node3D else Vector3.ZERO
	var killer_pos: Vector3 = (killer_node as Node3D).global_position if killer_node is Node3D else victim_pos
	var weapon_name := _kill_weapon_name(killer_id)
	var movement_state := "unknown"
	if killer_node:
		var anim = killer_node.get("anim_state")
		if anim != null:
			var loco := CharacterAnimator.unpack_locomotion(int(anim))
			var names := CharacterAnimator.Locomotion.keys()
			if loco >= 0 and loco < names.size():
				movement_state = names[loco]
	var now := Time.get_unix_time_from_system()
	var headshot := _fresh_headshot(killer_id)
	var active_ability := _fresh_active_ability(killer_id)
	var spawned_at: float = _spawn_time.get(victim_id, now)
	Telemetry.record(Telemetry.EVENT_KILL, {
		"killer_id": killer_id, "victim_id": victim_id,
		"killer_team": kteam, "victim_team": vteam,
		"killer_pos": _vec_to_array(killer_pos), "victim_pos": _vec_to_array(victim_pos),
		"weapon": weapon_name, "distance": killer_pos.distance_to(victim_pos),
		"movement_state": movement_state, "active_ability": active_ability,
		"headshot": headshot, "time_since_spawn": now - spawned_at,
	}, _match_id, true)

## Moyenne des RTT ENet (ms) vers chaque pair distant connu du serveur — même
## API que PerfOverlay._ping_suffix (scripts/core/PerfOverlay.gd), lue ici
## côté SERVEUR (vers chaque client) plutôt que côté client (vers l'hôte).
## 0.0 si transport non-ENet ou aucun pair distant (solo/entraînement).
func _average_ping_ms() -> float:
	var enet_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet_peer == null:
		return 0.0
	var total := 0.0
	var count := 0
	for id in multiplayer.get_peers():
		var p := enet_peer.get_peer(id)
		if p:
			total += p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
			count += 1
	return (total / count) if count > 0 else 0.0

func _process(_delta: float) -> void:
	_frame_stats.add(_delta * 1000.0)
	# FUN-01 : détection de fin de match (compte à rebours de revanche
	# automatique) -- SERVEUR uniquement, voir `_watch_for_match_end`.
	if multiplayer.is_server():
		_watch_for_match_end()

## Une entité RÉPLIQUÉE (joueur humain OU bot) vient d'apparaître dans
## `players_root` SUR CE PAIR (voir le branchement sur `PlayerSpawner.spawned`
## dans `_ready`). `is_multiplayer_authority()` : vrai uniquement là où cette
## entité est réellement SIMULÉE (le propriétaire humain sur son propre
## client, ou le serveur pour l'hôte-joueur/un bot) — c'est le SEUL endroit
## où les signaux PUBLICS Weapon.hit_confirmed / AbilityController.ability_used
## de CETTE entité s'émettent réellement (voir docstring de `_last_headshot`) :
## brancher ailleurs ne capterait jamais rien.
func _on_player_node_spawned(node: Node) -> void:
	if not node.is_multiplayer_authority():
		return
	var id := str(node.name).to_int()
	var weapon := node.get_node_or_null("Weapon")
	if weapon and weapon.has_signal("hit_confirmed"):
		weapon.hit_confirmed.connect(_on_own_hit_confirmed.bind(id))
	var abilities := node.get_node_or_null("Abilities")
	if abilities and abilities.has_signal("ability_used"):
		abilities.ability_used.connect(_on_own_ability_used.bind(id))

func _on_own_hit_confirmed(_pos: Vector3, _dmg: float, headshot: bool, _is_kill: bool, shooter_id: int) -> void:
	_store_headshot(shooter_id, headshot)
	if not multiplayer.is_server():
		_report_headshot.rpc_id(1, headshot)

func _store_headshot(shooter_id: int, headshot: bool) -> void:
	_last_headshot[shooter_id] = {"headshot": headshot, "t": Time.get_unix_time_from_system()}

## Un pair non-serveur rapporte le résultat (headshot ou non) de SON PROPRE
## dernier tir confirmé — jamais fait confiance pour autre chose que ce
## champ : le kill lui-même reste entièrement résolu par Weapon.gd côté
## serveur (hors périmètre ici). Au pire, un client qui trafiquerait cette
## valeur fausserait sa PROPRE télémétrie, jamais l'état de jeu autoritaire.
@rpc("any_peer", "call_remote", "reliable")
func _report_headshot(headshot: bool) -> void:
	if multiplayer.is_server():
		_store_headshot(multiplayer.get_remote_sender_id(), headshot)

## Événement `ability_used` (capacité) — écrit LOCALEMENT par le pair qui
## simule l'entité (hors `Telemetry.GAME_EVENTS` : action propre à un joueur,
## pas un état de match autoritaire), et mis en cache pour la corrélation
## avec un `kill` à venir (`_last_ability`, voir `_log_kill_event`).
func _on_own_ability_used(_slot: String, ability_name: String, player_id: int) -> void:
	_store_ability(player_id, ability_name)
	Telemetry.record(Telemetry.EVENT_ABILITY_USED, {
		"player_id": player_id, "ability_id": ability_name,
	}, _match_id, false)
	if not multiplayer.is_server():
		_report_ability_used.rpc_id(1, ability_name)

func _store_ability(player_id: int, ability_name: String) -> void:
	_last_ability[player_id] = {"name": ability_name, "t": Time.get_unix_time_from_system()}

## Corrèle la capacité récente d'un pair non-serveur (déjà écrite dans SON
## PROPRE journal par `_on_own_ability_used`) — ne réémet PAS l'événement
## côté serveur, seulement le cache utilisé par `_log_kill_event`.
@rpc("any_peer", "call_remote", "reliable")
func _report_ability_used(ability_name: String) -> void:
	if multiplayer.is_server():
		_store_ability(multiplayer.get_remote_sender_id(), ability_name)

# ======================================================================
#  SYSTÈME DE PING (UX-10, docs/research/04_ui_ux.md §2.8/§4 tâche UX-10) --
#  `PingController` (client, hors réseau) calcule kind+position localement et
#  appelle `request_ping` (hôte : direct : ; client : RPC ci-dessous, MÊME
#  patron que `_request_spawn`/`_spawn_local`). Le SERVEUR ne fait JAMAIS
#  confiance au client au-delà de kind+pos : il résout LUI-MÊME le nom de
#  zone (`_zone_name_at`, LD-04) et applique la limite de fréquence
#  (`_ping_history`) — un client modifié ne peut ni mentir sur sa zone, ni
#  spammer au-delà de 3 pings / 5 s. Relais RÉSERVÉ À L'ÉQUIPE de
#  l'expéditeur (`teammates_for_ping`, jamais l'équipe adverse) — hôte en
#  appel direct, tout autre HUMAIN via `_relay_ping.rpc_id` (MÊME distinction
#  que `_broadcast_agent_picks`/`_sync_agent_picks` ci-dessus). Les BOTS
#  n'ont ni RPC ni HUD à recevoir (voir doc de `teammates_for_ping`) : leur
#  réaction passe par `report_enemy_sighting` (mémoire d'équipe de GameMode,
#  déjà lue par `BotBrain._current_goal`/`*Mode._compute_bot_goal` pour
#  orienter le déplacement des bots vers la dernière position ennemie
#  connue — voir GameMode.gd/TDMMode.gd, hors périmètre ici : ce fichier ne
#  fait qu'appeler leur API PUBLIQUE existante, comme `_charge_ult`/
#  `_notify_on_kill` le font déjà pour AbilityController) : « défendez »/
#  « j'y vais » (et une désignation d'ennemi, « ennemi »/« ennemi ici », qui
#  EST littéralement un signalement) y poussent la position pingée pour la
#  team de l'expéditeur, ce qui fait converger les bots alliés vers elle au
#  prochain recalcul de but (GOAL_REFRESH_INTERVAL, déjà borné côté
#  GameMode). « besoin d'aide »/« marque »/« objet » ne déclenchent
#  délibérément rien côté bot (hors du contrat de cette tâche, qui ne cite
#  que « défendez » et « j'y vais »).
# ======================================================================

const PING_WINDOW_S := 5.0
const PING_MAX_PER_WINDOW := 3

## Kinds qui, en plus du relais HUD, alimentent la mémoire de sighting
## partagée par l'équipe (voir doc de section ci-dessus).
const _BOT_RALLY_KINDS: Array[String] = [
	PingController.KIND_DEFEND, PingController.KIND_GOING,
	PingController.KIND_ENEMY, PingController.KIND_ENEMY_HERE,
]

## Point d'entrée PUBLIC appelé par `PingController` (hôte : appel direct ;
## client : RPC `_server_request_ping`, MÊME patron que `_spawn_local`/
## `_request_spawn`). `pos` : position MONDE déjà résolue côté client
## (raycast local) — voir `_server_ping` pour ce que le serveur vérifie
## lui-même.
func request_ping(kind: String, pos: Vector3) -> void:
	if multiplayer.is_server():
		_server_ping(kind, pos, multiplayer.get_unique_id())
	else:
		_server_request_ping.rpc_id(1, kind, pos)

@rpc("any_peer", "reliable")
func _server_request_ping(kind: String, pos: Vector3) -> void:
	if multiplayer.is_server():
		_server_ping(kind, pos, multiplayer.get_remote_sender_id())

## Logique serveur complète : validation, limite de fréquence, résolution de
## zone, relais équipe seule, réaction des bots — séparée de la RPC
## ci-dessus pour rester appelable directement (hôte). Touche `multiplayer`
## (RPC de relais) : non testée directement (patron déjà établi par
## `_broadcast_agent_picks`, voir sa doc plus haut) — ce que ce corps calcule
## l'est via les fonctions PURES ci-dessous (`prune_ping_timestamps`,
## `can_send_ping`, `teammates_for_ping`, `triggers_bot_rally`,
## tests/player/test_ping.gd), sauf la branche 100 % hôte (id 1, aucune RPC
## réelle), elle-même exercée par ce même fichier de test.
func _server_ping(kind: String, pos: Vector3, sender_id: int) -> void:
	if not player_info.has(sender_id):
		return  # pair non-joueur (déconnecté entre-temps) : jamais relayé.
	if not PingController.ALL_KINDS.has(kind):
		return  # client modifié/désynchronisé : kind inconnu, silencieux.
	var now := Time.get_unix_time_from_system()
	var history := prune_ping_timestamps(_ping_history.get(sender_id, []), now, PING_WINDOW_S)
	if not can_send_ping(history, PING_MAX_PER_WINDOW):
		_ping_history[sender_id] = history  # purge quand même : pas de fuite mémoire.
		return
	history.append(now)
	_ping_history[sender_id] = history

	var team: int = int(player_info[sender_id].team)
	var sender_name: String = String(player_info[sender_id].name)
	var zone_name := _zone_name_at(pos)
	for tid in teammates_for_ping(player_info, team):
		if tid == 1:
			_deliver_ping_local(sender_id, sender_name, kind, pos, zone_name)
		else:
			_relay_ping.rpc_id(tid, sender_id, sender_name, kind, pos, zone_name)

	if triggers_bot_rally(kind):
		var mode := get_tree().get_first_node_in_group("game_mode")
		if mode != null and mode.has_method("report_enemy_sighting"):
			mode.report_enemy_sighting(team, pos)

func _deliver_ping_local(sender_id: int, sender_name: String, kind: String, pos: Vector3, zone_name: String) -> void:
	ping_received.emit(sender_id, sender_name, kind, pos, zone_name)

@rpc("authority", "reliable")
func _relay_ping(sender_id: int, sender_name: String, kind: String, pos: Vector3, zone_name: String) -> void:
	_deliver_ping_local(sender_id, sender_name, kind, pos, zone_name)

## Nom de zone (LD-04, `MapSetup.callout_at`) à `pos` — repérage IDENTIQUE à
## `GameHUD._acquire_map_setup` (groupe "nav_region" -> son parent ;
## MapSetup.gd n'est pas dans la liste de fichiers de cette tâche, jamais un
## nouveau groupe). "" hors de toute zone déclarée ou sans MapSetup (stand
## de tir) — même état "vide" que LocationLabel.
func _zone_name_at(pos: Vector3) -> String:
	var nav := get_tree().get_first_node_in_group("nav_region")
	if nav == null:
		return ""
	var parent := nav.get_parent()
	if parent == null or not parent.has_method("callout_at"):
		return ""
	return String(parent.callout_at(pos))

# ---- Fonctions PURES (testées directement, tests/player/test_ping.gd) ----

## Ne garde que les horodatages encore dans la fenêtre glissante de
## `window_s` secondes avant `now`.
static func prune_ping_timestamps(timestamps: Array, now: float, window_s: float = PING_WINDOW_S) -> Array:
	var kept: Array = []
	for t in timestamps:
		if now - float(t) <= window_s:
			kept.append(t)
	return kept

## Vrai si `timestamps` (déjà purgés par `prune_ping_timestamps`) contient
## STRICTEMENT moins de `max_count` entrées — la limite ne bloque que l'envoi
## SUIVANT, jamais rétroactivement les précédents.
static func can_send_ping(timestamps: Array, max_count: int = PING_MAX_PER_WINDOW) -> bool:
	return timestamps.size() < max_count

## Ids de tous les membres HUMAINS de `team` connus de `player_info`
## (expéditeur compris — il voit son propre marqueur, comme dans Apex) —
## JAMAIS un membre de l'équipe adverse (contrat UX-10 : « relaie à l'équipe
## seule, jamais à l'adversaire »). Jamais un BOT non plus : un bot n'a ni
## pair réseau à qui envoyer `_relay_ping`, ni HUD pour l'afficher (sa
## réaction passe par `report_enemy_sighting`, appelé séparément dans
## `_server_ping` — voir doc de section). Pure — aucune dépendance à
## `multiplayer`, testée directement (même principe que
## `agent_picks_roster` plus haut).
static func teammates_for_ping(player_info: Dictionary, team: int) -> Array:
	var out: Array = []
	for id in player_info.keys():
		var entry: Dictionary = player_info[id]
		if int(entry.get("team", -1)) == team and not bool(entry.get("is_bot", false)):
			out.append(id)
	return out

## Vrai pour les kinds qui doivent aussi alimenter la mémoire de sighting
## partagée par l'équipe (voir doc de section ci-dessus) — SEULEMENT
## « défendez »/« j'y vais » (contrat UX-10) et une désignation d'ennemi
## (« ennemi »/« ennemi ici », un signalement au sens littéral de
## `report_enemy_sighting`) ; jamais « besoin d'aide »/« marque »/« objet ».
static func triggers_bot_rally(kind: String) -> bool:
	return _BOT_RALLY_KINDS.has(kind)
