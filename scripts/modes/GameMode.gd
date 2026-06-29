## GameMode.gd
## Base d'un mode de jeu, SERVEUR-AUTORITAIRE : scores par équipe, condition de
## victoire, et synchro vers les clients. Les modes concrets (Hardpoint, SnD…)
## héritent et remplissent la logique. Le HUD lit l'état via le groupe "game_mode".
class_name GameMode
extends Node

signal updated

@export var mode_name: String = "Mode"
@export var score_to_win: int = 250

var team_scores: Array = [0.0, 0.0]
var winner: int = -1
var hud_state: String = ""

func _ready() -> void:
	set_multiplayer_authority(1)  # le serveur fait autorité sur le mode
	add_to_group("game_mode")

## À appeler côté serveur après modification des scores.
func check_win() -> void:
	for t in team_scores.size():
		if team_scores[t] >= score_to_win:
			winner = t
			return

## Réplique l'état (scores, vainqueur, texte d'objectif) à tous les pairs.
@rpc("authority", "call_local", "reliable")
func sync_state(scores: Array, win: int, state: String) -> void:
	team_scores = scores
	winner = win
	hud_state = state
	updated.emit()

func team_score(t: int) -> int:
	return int(team_scores[t]) if t < team_scores.size() else 0

## Réagit à un kill (surchargé par les modes, ex. TDM). Serveur.
func on_kill(_killer_id: int, _victim_id: int, _killer_team: int, _victim_team: int) -> void:
	pass

## Réinitialise le mode (rejouer). Serveur.
func reset_match() -> void:
	if not multiplayer.is_server():
		return
	for i in team_scores.size():
		team_scores[i] = 0.0
	winner = -1
	sync_state.rpc(team_scores, winner, hud_state)
