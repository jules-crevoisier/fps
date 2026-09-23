## RoundState.gd
## Machine à états PURE (aucun accès à l'arbre de scène) pour un match "à
## manches" (SnD, Duel/Duo) : BUY/PREROUND -> LIVE -> POST -> manche suivante.
## Ne connaît RIEN des règles de jeu (bombe, capture...) : `tick()` se contente
## de faire avancer l'horloge et de signaler un timeout de manche LIVE ; c'est
## au mode concret (SnDMode, DuelMode) de décider qui gagne dans ce cas et
## d'appeler `end_round(team)`. Utilisée deux fois comme les autres classes
## pures du jeu : copie AUTORITAIRE côté serveur (RoundMode), lue en lecture
## seule côté clients via la réplication (`RoundMode._sync_round`).
class_name RoundState
extends RefCounted

enum Phase { BUY, LIVE, POST }

var rounds_to_win: int
var swap_after: int       ## Nombre de manches jouées avant l'échange de camp (0 = désactivé).
var buy_duration: float   ## Durée de la phase BUY/PREROUND (s).
var round_duration: float ## Durée de la phase LIVE (s).
var post_duration: float  ## Durée de la phase POST (affichage du résultat) (s).

var phase: int = Phase.BUY
var time_left: float = 0.0
var wins: Array = [0, 0]
var winner: int = -1
var rounds_played: int = 0
var sides_swapped: bool = false

func _init(rounds_to_win_: int = 6, swap_after_: int = 5, buy_duration_: float = 15.0,
		round_duration_: float = 90.0, post_duration_: float = 4.0) -> void:
	rounds_to_win = rounds_to_win_
	swap_after = swap_after_
	buy_duration = buy_duration_
	round_duration = round_duration_
	post_duration = post_duration_
	reset()

## Avance l'horloge de `delta` secondes. Renvoie VRAI uniquement sur le tick où
## le temps de la phase LIVE s'épuise sans qu'un vainqueur de manche n'ait
## déjà été déclaré (au mode de décider la suite : ex. défenseurs gagnent au
## chrono en SnD, capture forcée en Duel). N'avance plus une fois le match
## terminé (`winner != -1`) ni une fois le temps à zéro (attend un appel
## explicite de `start_live()` / `end_round()`).
func tick(delta: float) -> bool:
	if winner != -1 or time_left <= 0.0:
		return false
	time_left -= delta
	if time_left > 0.0:
		return false
	time_left = 0.0
	return phase == Phase.LIVE

## Passe en phase BUY/PREROUND (achats / préparation avant la manche).
func start_buy() -> void:
	phase = Phase.BUY
	time_left = buy_duration

## Passe en phase LIVE (la manche est jouable).
func start_live() -> void:
	phase = Phase.LIVE
	time_left = round_duration

## Termine la manche courante au profit de `team` (0 ou 1) : incrémente le
## score, passe en POST, déclare un vainqueur si le seuil est atteint et
## déclenche l'échange de camp une fois. Sans effet si le match est déjà
## terminé ou si `team` est invalide (aucun score n'est compté).
func end_round(team: int) -> void:
	if winner != -1 or team < 0 or team > 1:
		return
	wins[team] += 1
	rounds_played += 1
	phase = Phase.POST
	time_left = post_duration
	if wins[team] >= rounds_to_win:
		winner = team
	elif swap_after > 0 and rounds_played == swap_after and not sides_swapped:
		sides_swapped = true

## VRAI si `team` gagne la manche suivante et remporte le match (point de
## manche), tant qu'aucun vainqueur n'est encore déclaré.
func is_match_point(team: int) -> bool:
	if winner != -1 or team < 0 or team > 1:
		return false
	return wins[team] == rounds_to_win - 1

## VRAI quand les deux équipes sont À ÉGALITÉ au point de manche (manche
## décisive, façon "sudden death") — le match n'a alors plus qu'une manche
## d'écart possible.
func is_overtime() -> bool:
	return winner == -1 and wins[0] == rounds_to_win - 1 and wins[1] == rounds_to_win - 1

## Réinitialise entièrement l'état (rejouer un match).
func reset() -> void:
	phase = Phase.BUY
	time_left = buy_duration
	wins = [0, 0]
	winner = -1
	rounds_played = 0
	sides_swapped = false
