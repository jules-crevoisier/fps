## OutOfCombatTracker.gd
## Suivi PUR (pas d'accès scène) du "hors-combat" d'un joueur : utilisé par
## HealAbility pour le soin de base, qui n'agit que si aucun dégât n'a été pris
## depuis `window` secondes (contract-r2.md, R-B3 acceptance #2). L'horodatage
## est injecté par l'appelant (AbilityController, via Time.get_ticks_msec) —
## garde le calcul testable sans horloge réelle.
class_name OutOfCombatTracker
extends RefCounted

var _last_damage_at: float = -INF

## Appelé côté serveur quand le joueur encaisse des dégâts (Health.damaged).
func mark_damaged(now: float) -> void:
	_last_damage_at = now

## true si au moins `window` secondes se sont écoulées depuis le dernier dégât
## (ou si le joueur n'a jamais été touché).
func is_out_of_combat(now: float, window: float = 3.0) -> bool:
	return now - _last_damage_at >= window
