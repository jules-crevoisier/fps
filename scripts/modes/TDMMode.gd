## TDMMode.gd
## Team Deathmatch : chaque élimination d'un ennemi rapporte 1 point à l'équipe.
## Première équipe à `score_to_win` éliminations gagne. Scoring serveur-autoritaire.
class_name TDMMode
extends GameMode

func _ready() -> void:
	super._ready()
	mode_name = "Team Deathmatch"
	hud_state = "Premier à %d éliminations" % score_to_win

func on_kill(_killer_id: int, _victim_id: int, killer_team: int, victim_team: int) -> void:
	if not multiplayer.is_server() or winner != -1:
		return
	if killer_team >= 0 and killer_team != victim_team:
		team_scores[killer_team] += 1
		check_win()
	sync_state.rpc(team_scores, winner, hud_state)
