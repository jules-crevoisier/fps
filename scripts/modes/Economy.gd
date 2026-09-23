## Economy.gd
## Machine PURE (aucun accès à l'arbre de scène) pour l'économie façon Valorant
## du mode Recherche & Destruction : crédits par joueur (peer id -> int),
## récompenses de kill/pose, fin de manche (victoire/défaite avec palier de
## série de défaites), plafond, et validation d'achat. Copie AUTORITAIRE
## détenue par SnDMode (serveur) ; les clients ne voient que leur propre solde,
## poussé par RPC (voir RoundMode/SnDMode).
class_name Economy
extends RefCounted

const START := 800
const WIN_REWARD := 3000
const LOSS_REWARDS := [1900, 2400, 2900]  ## Palier selon la série de défaites (1re, 2e, 3e et +).
const KILL_REWARD := 200
const PLANT_REWARD := 300
const CAP := 9000

var credits: Dictionary = {}       ## peer_id -> int
var _loss_streak: Dictionary = {}  ## peer_id -> int (défaites consécutives)

## (Ré)initialise un joueur au solde de départ (rejoint la partie / nouveau match).
func reset_player(id: int) -> void:
	credits[id] = START
	_loss_streak[id] = 0

## Crédite `amount` (peut être négatif), plafonné à [0, CAP].
func add(id: int, amount: int) -> void:
	credits[id] = clampi(get_credits(id) + amount, 0, CAP)

func get_credits(id: int) -> int:
	return credits.get(id, 0)

func can_afford(id: int, cost: int) -> bool:
	return get_credits(id) >= cost

## Débite `cost` si possible (achat). Renvoie faux (et ne débite rien) si le
## solde est insuffisant — c'est cette valeur que le mode utilise pour
## refuser un achat côté serveur.
func spend(id: int, cost: int) -> bool:
	if not can_afford(id, cost):
		return false
	credits[id] = get_credits(id) - cost
	return true

func award_kill(id: int) -> void:
	add(id, KILL_REWARD)

func award_plant(id: int) -> void:
	add(id, PLANT_REWARD)

## Fin de manche : chaque gagnant touche le montant fixe de victoire (et voit
## sa série de défaites remise à zéro) ; chaque perdant touche le palier
## correspondant à sa série de défaites CONSÉCUTIVES (1900/2400/2900, plafonné
## au dernier palier), qui s'incrémente ensuite.
func round_ended(winners: Array, losers: Array) -> void:
	for id in winners:
		add(id, WIN_REWARD)
		_loss_streak[id] = 0
	for id in losers:
		var streak: int = _loss_streak.get(id, 0)
		add(id, LOSS_REWARDS[mini(streak, LOSS_REWARDS.size() - 1)])
		_loss_streak[id] = streak + 1
