## BotReaction.gd
## Modèle PUR de réaction humain-like d'un bot (contract-r3.md, R3-IN#2) :
## délai avant de pouvoir tirer sur une cible qui vient d'apparaître (Recrue
## ~450 ms, Vétéran ~300 ms, Élite ~200 ms), et erreur de visée qui rétrécit
## pendant le suivi CONTINU d'une même cible (plus on la voit longtemps, plus
## on vise juste). Aucun accès à l'arbre de scène — consommé par
## scripts/ai/BotBrain.gd, testé isolément dans tests/ai/test_bot_reaction.gd.
class_name BotReaction
extends RefCounted

## Constante de décroissance (s) de l'erreur de visée pendant le suivi.
const TRACKING_SHRINK_TAU := 0.8

## Délai de réaction (s) avant de pouvoir engager une cible nouvellement
## acquise, par difficulté (MatchConfig.Difficulty).
static func reaction_time(difficulty: int) -> float:
	match difficulty:
		MatchConfig.Difficulty.RECRUE:
			return 0.45
		MatchConfig.Difficulty.ELITE:
			return 0.2
		_:
			return 0.3  # VETERAN (et toute valeur inconnue : repli raisonnable)

## Erreur de visée MAX (radians) au premier contact avec une cible, par
## difficulté — décroît ensuite avec `aim_error_for`.
static func max_aim_error(difficulty: int) -> float:
	match difficulty:
		MatchConfig.Difficulty.RECRUE:
			return deg_to_rad(6.0)
		MatchConfig.Difficulty.ELITE:
			return deg_to_rad(1.5)
		_:
			return deg_to_rad(3.5)  # VETERAN

## Erreur de visée courante (radians), décroissance exponentielle vers 0
## pendant que la cible est suivie sans interruption depuis `tracking_time` s.
static func aim_error_for(difficulty: int, tracking_time: float) -> float:
	var max_err := max_aim_error(difficulty)
	var t := maxf(tracking_time, 0.0)
	return max_err * exp(-t / TRACKING_SHRINK_TAU)
