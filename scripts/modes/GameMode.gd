## GameMode.gd
## Base d'un mode de jeu, SERVEUR-AUTORITAIRE : scores par équipe, condition de
## victoire, et synchro vers les clients. Les modes concrets (Hardpoint, SnD…)
## héritent et remplissent la logique. Le HUD lit l'état via le groupe "game_mode".
class_name GameMode
extends Node

signal updated

@export var mode_name: String = "Mode"
@export var score_to_win: int = 250
## Limite de temps du MATCH (s) — au-delà, la victoire se décide au score dès
## qu'un écart existe (voir `_try_decide_by_score`). TDM/Hardpoint : 10 min.
@export var match_time_limit: float = 600.0

## Capacités d'agent actives dans ce mode (Duel/Duo : false, pas de capacités).
var abilities_enabled: bool = true
## Phase d'achat en cours (lu par BuyMenu/Weapon._server_buy). Les modes à
## manches (SnD) le pilotent depuis RoundMode ; les modes d'arène (TDM/HP)
## achètent librement pendant toute la partie.
var buy_phase: bool = true

## Règle de munitions du mode (lue par Weapon.gd, docs/research/
## 10_ammo_kits_input.md §2.2) : "round" (`Inventory.RULE_ROUND`, réserve des
## .tres) pour un mode à MANCHES — RoundMode (SnD/Duel/Duo) surcharge déjà
## `respawns_immediately()` à faux pour attendre la manche suivante plutôt que
## de respawn tout de suite ; "arena" (`Inventory.RULE_ARENA`, réserve élargie
## §2.3) sinon, le cas de TDM/Hardpoint qui héritent tels quels de GameMode.
## Champ CALCULÉ (comme `weapons`/`mag`/`current` de Weapon.gd) plutôt que
## stocké : il se déduit de `respawns_immediately()`, DÉJÀ correct pour toute
## sous-classe existante (RoundMode et ses propres sous-classes SnDMode/
## DuelMode, hors de ma liste de fichiers) sans qu'aucune d'elles n'ait besoin
## d'être touchée pour en hériter. L'entraînement (aucune scène de mode, donc
## aucun nœud du groupe "game_mode" du tout) n'est PAS couvert ici : c'est
## Weapon._ammo_rule() qui retombe alors sur `Inventory.RULE_INFINITE`.
var ammo_rule: String:
	get: return "round" if not respawns_immediately() else "arena"

## Le stun de chute (MV-03, MovementConfig.stun_enabled/fall_min_height/
## stun_max_time) est-il actif dans CE mode ? Champ CALCULÉ, même patron que
## `ammo_rule` ci-dessus : à partir de `respawns_immediately()`, DÉJÀ correct
## pour toute sous-classe existante sans qu'aucune d'elles n'ait besoin d'être
## touchée. TDM/Hardpoint (arène, respawn immédiat, héritent tels quels de
## GameMode) le gardent activé ; RoundMode et ses sous-classes SnDMode/
## DuelMode (manches — Duel 1v1 ET Duo 2v2, hors de ma liste de fichiers)
## le désactivent déjà en écrasant `respawns_immediately()` à faux — une
## perte de contrôle après une chute est jugée trop punitive en compétitif à
## manches (docs/research/01_game_feel.md #16 : "perte de contrôle totale en
## plein combat, frustrante en compétitif"). À lire par PlayerController
## (hors de mon périmètre) via le mode du groupe "game_mode" courant avant de
## déclencher l'état `Stun`.
var fall_stun_enabled: bool:
	get: return respawns_immediately()

var team_scores: Array = [0.0, 0.0]
var winner: int = -1
var hud_state: String = ""

var match_elapsed: float = 0.0
var _time_expired: bool = false

## Bandeau exposé par le mode une fois le temps écoulé alors que les scores
## sont à égalité ("MORT SUBITE" — le prochain point marqué décide) ; vide en
## dehors de cette phase. Champ séparé de `hud_state` (texte d'objectif),
## même convention que `side_swap_notice` (TDM/Hardpoint), pour ne rien lui
## faire perdre.
const SUDDEN_DEATH_NOTICE := "MORT SUBITE"
var sudden_death_notice: String = ""

# ======================================================================
#  Objectifs de bot STABLES (BOT-01, docs/research/02_bots_ai.md §2.2/§4.1) :
#  un but ne change que sur ÉVÈNEMENT (kill, bombe posée, zone qui tourne, but
#  atteint) ou, à défaut, au plus toutes les GOAL_REFRESH_INTERVAL secondes —
#  jamais un recalcul à chaque appel (l'ancien "ennemi au hasard toutes les
#  0.5 s" cassait l'illusion ET révélait une position ennemie hors
#  perception). Commun aux 4 modes concrets : cette base tient le cache et la
#  mémoire d'équipe, chaque mode ne fournit que `_compute_bot_goal`.
# ======================================================================
const GOAL_REFRESH_INTERVAL := 6.0        ## Cadence mini de recalcul (s).
const GOAL_REACHED_DISTANCE := 2.5        ## "But atteint" -> recalcul immédiat (m).
const ENEMY_MEMORY_TTL := 6.0             ## Fraîcheur d'un ennemi signalé par l'équipe (s).

## bot_id -> {"pos": Vector3, "time": float} — dernier but RENVOYÉ à ce bot
## (la position peut rester identique d'un recalcul au suivant : seul un
## changement de VALEUR compte comme "changement de but").
var _bot_goal_cache: Dictionary = {}

## team -> {"pos": Vector3, "time": float} — dernière position ennemie
## SIGNALÉE par un bot de cette équipe (jamais lue directement depuis l'état
## serveur : uniquement ce qu'un bot a lui-même PERÇU, voir BotBrain.
## _report_sightings -> `report_enemy_sighting`). C'est la "dernière position
## connue partagée par l'équipe" du contrat BOT-01, pas un wall-hack.
var _last_seen_enemy: Dictionary = {}

## RNG du tirage de point de patrouille (`_pick_patrol_point`) — PAS pour un
## comportement critique/testé (aucun test ne fixe sa graine), seulement pour
## répartir les bots sur toute la carte plutôt que toujours le point le plus
## proche (BUG-REGR-01, voir sa docstring).
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	set_multiplayer_authority(1)  # le serveur fait autorité sur le mode
	add_to_group("game_mode")
	_rng.randomize()

## Garde COMMUNE (BUG-27) à la place de `multiplayer.is_server()` nu, utilisée
## par toute la logique autoritaire de GameMode ET des modes qui en héritent
## (TDMMode...). Godot ne rend `is_server()` fiable que si un pair est assigné
## : par défaut `Node.multiplayer.multiplayer_peer` vaut un `OfflineMultiplayerPeer`
## (is_server() == true, doc officielle "high_level_multiplayer"/
## OfflineMultiplayerPeer), MAIS `NetworkManager.disconnect_from_game()` le
## remet à `null` (au lieu d'un nouvel `OfflineMultiplayerPeer`) plutôt que de
## le recréer — et un mode instancié seul (entraînement hors ligne, écran de
## sélection, ui_shots, ce test) n'a jamais eu de pair du tout. Dans les DEUX
## cas, `multiplayer.is_server()` consulte alors `get_unique_id()` sur un pair
## nul : Godot journalise "No multiplayer peer is assigned. Unable to get
## unique ID." (scene_multiplayer.cpp) ET renvoie FAUX — donc, sans cette
## garde, tout ce bloc autoritaire (scores, minuteries, IA, reset) restait
## silencieusement gelé au lieu de tourner. Le contrat réseau autoritaire
## serveur (voir NetworkManager.is_host()) dit "pair assigné + is_server()" ;
## ICI c'est l'inverse qu'il faut : l'ABSENCE de pair signifie une simulation
## LOCALE autoritaire (pas un client qui attendrait un serveur distant), donc
## `true` aussi dans ce cas.
func _is_authoritative() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()

## Réplique `sync_state` (scores/vainqueur/objectif) aux pairs — SUITE de
## BUG-27 : une fois `_is_authoritative()` corrigée, un pair absent atteint
## quand même `.rpc()`, que Godot refuse ENCORE, même en "call_local" pur
## ("Trying to call an RPC while no multiplayer peer is active.",
## scene_rpc_interface.cpp) — une garde `is_server()` ne protège QUE l'appel
## `is_server()` lui-même, pas la réplication qui suit. Sans pair, il n'y a
## personne à qui répliquer : l'appel DIRECT de `sync_state` fait exactement
## ce que `call_local` aurait fait en plus de l'envoi réseau (voir sa
## docstring), donc le résultat local est identique.
func _sync_state(scores: Array, win: int, state: String) -> void:
	if multiplayer.multiplayer_peer == null:
		sync_state(scores, win, state)
	else:
		sync_state.rpc(scores, win, state)

## Même garde que `_sync_state` ci-dessus, pour le bandeau de mort subite.
func _sync_sudden_death(notice: String) -> void:
	if multiplayer.multiplayer_peer == null:
		sync_sudden_death(notice)
	else:
		sync_sudden_death.rpc(notice)

## Minuteur de MATCH commun (TDM/Hardpoint). Les modes à manches (RoundMode)
## gèrent leur propre horloge (RoundState) et n'appellent pas ceci. Une fois
## le temps écoulé, `_try_decide_by_score()` est retenté à CHAQUE tick (pas
## seulement au tick d'expiration) : si les scores étaient à égalité à ce
## moment (mort subite), le prochain point marqué — par n'importe quel appel
## de `check_win()` chez le mode concret, voire un score changé sans passer
## par lui — est détecté et tranche dès le tick suivant (BUG-01).
func _physics_process(delta: float) -> void:
	if not _is_authoritative() or winner != -1:
		return
	match_elapsed += delta
	if match_elapsed >= match_time_limit and not _time_expired:
		_time_expired = true
		if team_scores[0] == team_scores[1]:
			_set_sudden_death(SUDDEN_DEATH_NOTICE)
	if _time_expired:
		_try_decide_by_score()

## À appeler côté serveur après modification des scores. Décide aussi la
## victoire au score si le temps du match est déjà écoulé (manche décisive).
func check_win() -> void:
	for t in team_scores.size():
		if team_scores[t] >= score_to_win:
			winner = t
			return
	_try_decide_by_score()

## Une fois le temps écoulé, le premier écart de score décide du match.
func _try_decide_by_score() -> void:
	if not _time_expired or winner != -1:
		return
	if team_scores[0] != team_scores[1]:
		winner = 0 if team_scores[0] > team_scores[1] else 1
		if sudden_death_notice != "":
			_set_sudden_death("")
		_sync_state(team_scores, winner, hud_state)

## Assigne localement puis réplique le bandeau de mort subite (même patron
## que `winner`/`hud_state` avant `_sync_state` : la valeur locale est déjà
## correcte même si aucun pair distant n'est connecté).
func _set_sudden_death(notice: String) -> void:
	sudden_death_notice = notice
	_sync_sudden_death(notice)

@rpc("authority", "call_local", "reliable")
func sync_sudden_death(notice: String) -> void:
	sudden_death_notice = notice
	updated.emit()

## Le joueur qui vient de mourir doit-il repartir immédiatement (TDM/HP) ou
## attendre la prochaine manche (SnD/Duel, voir RoundMode) ?
func respawns_immediately() -> bool:
	return true

## Achat en boutique demandé par `peer_id` pour `weapon_id` : autorisé par
## défaut (TDM/HP). Les modes à manches (SnD) surchargent pour valider la
## phase d'achat et débiter l'économie (voir Weapon._server_buy, R-A2).
func server_try_purchase(_peer_id: int, _weapon_id: int) -> bool:
	return true

## Réplique l'état (scores, vainqueur, texte d'objectif) à tous les pairs.
@rpc("authority", "call_local", "reliable")
func sync_state(scores: Array, win: int, state: String) -> void:
	team_scores = scores
	winner = win
	hud_state = state
	updated.emit()

func team_score(t: int) -> int:
	return int(team_scores[t]) if t < team_scores.size() else 0

# ======================================================================
#  Audio (R-E, autoload "Sfx" : scripts/core/Audio.gd) — appelé côté CLIENT
#  depuis les RPC d'autorité (call_local, donc aussi sur l'hôte), jamais
#  uniquement côté serveur. Gardé par has_node/has_method : ne casse rien si
#  l'autoload n'est pas encore chargé (tests headless sans scène, Sfx pas
#  encore construit en parallèle).
# ======================================================================
func _sfx() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("Sfx")

func _play_sfx_ui(name: String) -> void:
	var sfx := _sfx()
	if sfx and sfx.has_method("play_ui"):
		sfx.play_ui(name)

func _play_sfx_at(name: String, pos: Vector3) -> void:
	var sfx := _sfx()
	if sfx and sfx.has_method("play_at"):
		sfx.play_at(name, pos)

## Équipe du joueur LOCAL (-1 s'il n'existe pas encore, ex. écran de sélection).
func _local_player_team() -> int:
	var arr := get_tree().get_nodes_in_group("local_player")
	if arr.is_empty():
		return -1
	return int(arr[0].get("team"))

## Réagit à un kill (surchargé par les modes, ex. TDM). Serveur.
func on_kill(_killer_id: int, _victim_id: int, _killer_team: int, _victim_team: int) -> void:
	pass

## Horloge du cache de but de bot — `Time.get_ticks_msec` par défaut ;
## SURCHARGEABLE (tests) pour simuler l'écoulement du temps sans attendre en
## temps réel, voir tests/ai/test_bot_goals.gd (`_ClockedTDMMode` et consorts).
func _goal_clock_now() -> float:
	return Time.get_ticks_msec() / 1000.0

## Force un recalcul au PROCHAIN appel de `bot_goal_for`, pour TOUS les bots —
## à appeler depuis les hooks d'évènement des modes concrets (kill, bombe
## posée, zone qui tourne...). Un recalcul ne produit pas forcément une valeur
## DIFFÉRENTE (ex. aucun ennemi signalé entre-temps) : "changement de but" ne
## compte que si la valeur renvoyée change réellement, voir `bot_goal_for`.
func _invalidate_bot_goals() -> void:
	_bot_goal_cache.clear()

## Cible d'objectif STABLE (contrat BOT-01) pour le bot `bot_id` de `team`,
## actuellement en `bot_pos`. Ne recalcule (`_compute_bot_goal`, à surcharger
## par le mode concret — TDM/Hardpoint/SnD/Duel) que si : aucun but encore
## connu pour ce bot, le cache vient d'être invalidé par un évènement
## (`_invalidate_bot_goals`), le but précédent est ATTEINT (distance <=
## GOAL_REACHED_DISTANCE), ou GOAL_REFRESH_INTERVAL secondes se sont écoulées
## depuis le dernier calcul — sinon renvoie EXACTEMENT le même Vector3 qu'au
## dernier appel (plus d'aller-retour permanent, voir docs/research/
## 02_bots_ai.md §2.2/§4.1). `_compute_bot_goal` ne doit lire QUE des données
## publiques du mode/de la carte ou la mémoire d'équipe (`_shared_last_seen_
## enemy`), jamais l'état serveur brut d'un ennemi (pas de wall-hack).
func bot_goal_for(team: int, bot_id: int, bot_pos: Vector3) -> Vector3:
	var now := _goal_clock_now()
	var cached: Dictionary = _bot_goal_cache.get(bot_id, {})
	var stale := cached.is_empty() or (now - float(cached.get("time", 0.0))) >= GOAL_REFRESH_INTERVAL
	var reached := not cached.is_empty() \
			and bot_pos.distance_to(cached.get("pos", Vector3.ZERO)) <= GOAL_REACHED_DISTANCE
	if stale or reached:
		# `reached` (et lui SEUL, pas la simple péremption des 6 s pendant que
		# le bot est encore en chemin) est transmis au calcul : un point de
		# patrouille ATTEINT doit être exclu du prochain choix (sinon le bot
		# se le reverrait aussitôt réassigné), mais un simple recalcul de
		# routine ne doit PAS faire tourner le but si le bot n'y est pas
		# encore (voir GameMode._pick_patrol_point).
		var goal: Vector3 = _compute_bot_goal(team, bot_id, bot_pos, reached)
		_bot_goal_cache[bot_id] = {"pos": goal, "time": now}
		return goal
	return cached.get("pos", Vector3.ZERO)

## Calcul RÉEL du but — à surcharger (TDM/Hardpoint/SnD/Duel possédés par
## R3-IN). `reached` : vrai seulement si CE recalcul est déclenché parce que
## le bot vient d'atteindre son but précédent (pas une simple péremption des
## 6 s) — voir `_pick_patrol_point`. Vector3.ZERO par défaut = "aucune
## préférence" (BotBrain reste sur place).
func _compute_bot_goal(_team: int, _bot_id: int, _bot_pos: Vector3, _reached: bool = false) -> Vector3:
	return Vector3.ZERO

## Le but de mode de `bot_id` est-il une POSITION À TENIR (zone Hardpoint,
## point de surveillance) plutôt qu'un point de passage ? Si oui, BotBrain ne
## l'abandonne jamais pour aller voir un tir entendu : l'ouïe ne fait plus
## que diriger son REGARD (BotLook, L1 « puis son entendu »). Faux par défaut
## : TDM/SnD/Duel gardent l'enquête au bruit (chasse), inchangée.
func bot_holds_position(_team: int, _bot_id: int) -> bool:
	return false

## Un bot (ou, plus tard, un joueur humain) qui VOIT ACTUELLEMENT un ennemi le
## signale ici — mémoire PARTAGÉE de son équipe (`team`), alimentée
## UNIQUEMENT par la perception réelle d'un bot (BotBrain._visible_enemies,
## raycast + cône de vue), jamais par une lecture directe de l'état serveur :
## c'est la "dernière position connue partagée par l'équipe" du contrat
## BOT-01, pas un wall-hack. Appelé à chaque tick où au moins un ennemi est
## visible (voir BotBrain._report_sightings).
func report_enemy_sighting(team: int, pos: Vector3) -> void:
	_last_seen_enemy[team] = {"pos": pos, "time": _goal_clock_now()}

## Dernière position ennemie signalée par un bot de `team`, si elle n'a pas
## expiré (ENEMY_MEMORY_TTL) — Vector3.INF sinon ("aucune mémoire fraîche",
## distinct de Vector3.ZERO qui est une position monde valide).
func _shared_last_seen_enemy(team: int) -> Vector3:
	var mem: Dictionary = _last_seen_enemy.get(team, {})
	if mem.is_empty() or _goal_clock_now() - float(mem.get("time", 0.0)) > ENEMY_MEMORY_TTL:
		return Vector3.INF
	return mem.get("pos", Vector3.INF)

## Identifiant de la carte courante — lu depuis `get_parent().map_id`. Le
## nœud `GameMode` est TOUJOURS construit comme enfant direct du `MapSetup`
## qui l'instancie (`MapSetup._build_game_mode`, hors de mon périmètre :
## "add_child(mode)" y est appelé sur `self` = MapSetup, jamais sur
## GameWorld — voir sa docstring "ENFANTS DE MapSetup LUI-MÊME"), et
## `MapSetup.map_id` est un export PUBLIC, déjà lu de la même façon par
## `GameHUD._acquire_map_setup` (autre tâche : dupliquer la lecture d'un
## champ public plutôt que d'appeler une méthode `_`-préfixée d'un fichier
## hors périmètre). `""` pour un mode sans parent "MapSetup-like" (tout test
## qui ajoute le mode comme enfant du SUITE de test lui-même, ex. la plupart
## de tests/ai/test_bot_goals.gd) — repli propre, contrat LD-25.
func _current_map_id() -> String:
	var parent := get_parent()
	if parent != null and "map_id" in parent:
		return String(parent.get("map_id"))
	return ""

## Connaissance de carte pour bots (LD-24, docs/research/
## 09_wasteland_vertical_slice.md §e : `lanes`/`hotspots`/`hp_hold_points`/
## `nav_links`/`danger_spans`) — lue directement depuis la source PURE et
## PUBLIQUE de la carte courante (`WastelandBots.data()`, jamais une méthode
## `_`-préfixée de `MapSetup`, même discipline que `_current_map_id`
## ci-dessus), utilisée par TDM (patrouille par hotspots/lanes) et Hardpoint
## (points de tenue distincts) — voir leurs `_compute_bot_goal` respectifs.
## Dictionary VIDE pour toute carte qui n'expose pas encore ces données
## ("repli propre sur une carte sans données", LD-25) : TDM/Hardpoint
## retombent alors sur leur comportement HISTORIQUE (marqueurs de spawn /
## centre de zone commun), inchangé — les autres cartes ne régressent pas.
func _bot_knowledge() -> Dictionary:
	match _current_map_id():
		"wasteland":
			return WastelandBots.data()
	return {}

## Points de patrouille STATIQUES de la carte (marqueurs de spawn — connus
## d'avance, jamais l'état des joueurs) — repli de `_compute_bot_goal` (TDM/
## Duel) quand aucune mémoire d'ennemi n'est fraîche (contrat BOT-01 :
## "points de patrouille/zones chaudes de la carte"). `GameWorld.
## spawn_points_root` est un export PUBLIC (pas besoin de le modifier ici).
func _map_patrol_points() -> Array:
	var world := get_tree().get_first_node_in_group("match")
	if world == null:
		return []
	var root := world.get_node_or_null(world.spawn_points_root)
	if root == null:
		return []
	var out: Array = []
	for p in root.get_children():
		out.append((p as Node3D).global_position)
	return out

## Point de patrouille TIRÉ AU HASARD parmi `_map_patrol_points` (TOUS les
## marqueurs de spawn de la carte, des DEUX équipes — `_map_patrol_points` ne
## filtre pas par équipe) — à L'EXCEPTION du but actuellement en cache pour
## `bot_id` SEULEMENT si `exclude_current` (vrai quand ce recalcul vient de
## "but atteint" — voir `bot_goal_for`) : sans cette exclusion CONDITIONNELLE,
## un bot qui vient d'ATTEINDRE son point de patrouille pourrait se le revoir
## aussitôt réassigné. L'appliquer aussi à un simple recalcul de routine
## (péremption des 6 s, pendant que le bot est encore en chemin) ferait
## tourner le but à chaque cycle même sans raison — ce que le contrat BOT-01
## interdit.
##
## BUG-REGR-01 (régression bot_smoke : 0 kill/0 tir en 4v4, sur cargo_ship
## COMME sur wasteland) : le tirage était à l'origine "le point le plus
## proche de `bot_pos`" plutôt qu'au hasard. Les marqueurs de spawn de CHAQUE
## équipe sont regroupés à proximité les uns des autres (quelques mètres,
## près de LEUR base) mais loin de ceux de l'équipe adverse (~45 m sur
## cargo_ship, à peine sous SIGHT_RANGE) : "le plus proche" retombait donc
## TOUJOURS sur un point de la MÊME grappe que la position actuelle du bot,
## qui ne le fait jamais sortir du voisinage de son propre spawn. Résultat :
## aucun bot n'approchait jamais assez de l'équipe adverse pour la
## PERCEVOIR (`BotBrain._visible_enemies`, LOS/FOV/distance) — sans
## perception, `_shared_last_seen_enemy` (mémoire d'équipe) ne se peuple
## jamais non plus, et TDM/Duel retombaient donc en permanence sur ce même
## point de patrouille local : les deux équipes patrouillaient chacune sur
## place, jamais de contact, jamais un seul tir. Un tirage AU HASARD parmi
## TOUS les points (donc, une fois sur deux environ, un point du CÔTÉ
## adverse) fait traverser la carte aux bots assez souvent pour rétablir
## l'engagement, sans jamais leur donner la position d'un ennemi VIVANT (le
## point tiré est un marqueur de spawn STATIQUE, connu d'avance — toujours
## conforme au contrat BOT-01 "jamais un wall-hack").
##
## Vector3.ZERO si la carte n'expose aucun point (comportement historique :
## "aucune préférence").
func _pick_patrol_point(bot_id: int, _bot_pos: Vector3, exclude_current: bool = false) -> Vector3:
	var points := _map_patrol_points()
	if points.is_empty():
		return Vector3.ZERO
	var exclude: Vector3 = Vector3.INF
	if exclude_current:
		var cached: Dictionary = _bot_goal_cache.get(bot_id, {})
		if not cached.is_empty():
			exclude = cached.get("pos", Vector3.INF)
	var candidates: Array = []
	for p in points:
		if points.size() > 1 and exclude != Vector3.INF and (p as Vector3).distance_to(exclude) <= 0.01:
			continue
		candidates.append(p)
	if candidates.is_empty():
		return points[0]
	return candidates[_rng.randi() % candidates.size()]

## Réinitialise le mode (rejouer). Serveur.
func reset_match() -> void:
	if not _is_authoritative():
		return
	for i in team_scores.size():
		team_scores[i] = 0.0
	winner = -1
	match_elapsed = 0.0
	_time_expired = false
	if sudden_death_notice != "":
		_set_sudden_death("")
	_sync_state(team_scores, winner, hud_state)
