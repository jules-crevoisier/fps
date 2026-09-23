## TDMMode.gd
## Team Deathmatch : chaque élimination d'un ennemi rapporte 1 point à l'équipe.
## Première équipe à `score_to_win` éliminations gagne. Scoring serveur-autoritaire.
class_name TDMMode
extends GameMode

## 50 éliminations par défaut (contrat R2 : "50 kills ou 10 min") — GDScript
## interdit de redéclarer un @export hérité (GameMode.score_to_win = 250,
## pensé pour Hardpoint) : on change juste la valeur par défaut ici, avant
## qu'une éventuelle valeur de scène ne l'écrase.
func _init() -> void:
	score_to_win = 50

func _ready() -> void:
	super._ready()
	mode_name = "Team Deathmatch"
	hud_state = "Premier à %d éliminations" % score_to_win

## Échange de côté (maps-spec-v2.md §5.6.2/§7.5, maps ASYMÉTRIQUES seulement,
## ex. wasteland) : MapSetup positionne `asymmetric_map` (data "asymmetric")
## juste après avoir instancié ce mode — `false` par défaut => comportement
## 100% inchangé sur toute map symétrique. Décidé UNE SEULE FOIS par
## `HalfTime.should_swap` (50% du temps limite OU meneur à moitié du score
## limite), puis répliqué comme les autres RPC d'état (`sync_state`). Les
## joueurs vivants restent où ils sont — seul le PROCHAIN respawn utilise le
## nouveau côté (`GameWorld._get_spawn_position` lit `sides_swapped`).
## `side_swap_notice` : cartouche HUD ("CHANGEMENT DE CÔTÉ") — champ séparé de
## `hud_state` (texte d'objectif) pour ne rien lui faire perdre.
@export var asymmetric_map: bool = false
var sides_swapped: bool = false
var side_swap_notice: String = ""

@rpc("authority", "call_local", "reliable")
func sync_sides_swapped(swapped: bool, notice: String) -> void:
	sides_swapped = swapped
	side_swap_notice = notice
	updated.emit()

## Minuteur de MATCH (10 min par défaut, voir GameMode.match_time_limit) :
## décide la victoire au score une fois le temps écoulé (GameMode._physics_process).
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if multiplayer.is_server() and winner == -1 and asymmetric_map and not sides_swapped:
		if HalfTime.should_swap(match_elapsed, match_time_limit, team_scores[0], team_scores[1], score_to_win):
			sync_sides_swapped.rpc(true, "CHANGEMENT DE CÔTÉ")

func on_kill(_killer_id: int, _victim_id: int, killer_team: int, victim_team: int) -> void:
	if not multiplayer.is_server() or winner != -1:
		return
	if killer_team >= 0 and killer_team != victim_team:
		team_scores[killer_team] += 1
		check_win()
	sync_state.rpc(team_scores, winner, hud_state)

## TDM : "va combattre" — un ennemi vivant au hasard (approximation faute de
## connaître la position du bot appelant, voir GameMode.bot_goal_for).
func bot_goal_for(team: int) -> Vector3:
	var enemies := _team_player_positions(1 - team)
	if enemies.is_empty():
		return Vector3.ZERO
	return enemies[randi() % enemies.size()]
