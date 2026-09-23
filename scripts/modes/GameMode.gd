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

var team_scores: Array = [0.0, 0.0]
var winner: int = -1
var hud_state: String = ""

var match_elapsed: float = 0.0
var _time_expired: bool = false

func _ready() -> void:
	set_multiplayer_authority(1)  # le serveur fait autorité sur le mode
	add_to_group("game_mode")

## Minuteur de MATCH commun (TDM/Hardpoint). Les modes à manches (RoundMode)
## gèrent leur propre horloge (RoundState) et n'appellent pas ceci.
func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or winner != -1:
		return
	match_elapsed += delta
	if match_elapsed >= match_time_limit and not _time_expired:
		_time_expired = true
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
		sync_state.rpc(team_scores, winner, hud_state)

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

## Cible d'objectif pour un bot de `team` (zone de capture, site à planter,
## bombe posée, ennemi le plus proche...) — chaque mode concret possédé par
## R3-IN (TDM/Hardpoint/SnD/Duel) surcharge (contract-r3.md, R3-IN#2 :
## "Objective play through bot_goal_for(team)"). Le SIGNAL ne prend que
## `team` (pas la position du bot appelant, un seul objectif "vaut" pour
## toute l'équipe) — scripts/ai/BotBrain.gd s'en sert comme cible de
## déplacement quand aucun ennemi n'est visible/entendu. Vector3.ZERO par
## défaut = "aucune préférence" (BotBrain reste sur place).
func bot_goal_for(_team: int) -> Vector3:
	return Vector3.ZERO

## Positions des joueurs VIVANTS de `team` (ou de tous, `alive_only=false`) —
## helper partagé par les surcharges de `bot_goal_for` (TDM/Duel : "ennemi le
## plus proche", approximé par un ennemi vivant au hasard faute de connaître
## la position du bot appelant depuis cette seule signature).
func _team_player_positions(team: int, alive_only: bool = true) -> Array:
	var world := get_tree().get_first_node_in_group("match")
	if world == null:
		return []
	var out: Array = []
	for child in world.get_node(world.players_root).get_children():
		if int(child.get("team")) != team:
			continue
		if alive_only:
			var hp := child.get_node_or_null("Health") as Health
			if hp and hp.is_dead:
				continue
		out.append(child.global_position)
	return out

## Réinitialise le mode (rejouer). Serveur.
func reset_match() -> void:
	if not multiplayer.is_server():
		return
	for i in team_scores.size():
		team_scores[i] = 0.0
	winner = -1
	match_elapsed = 0.0
	_time_expired = false
	sync_state.rpc(team_scores, winner, hud_state)
