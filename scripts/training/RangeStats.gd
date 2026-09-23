## RangeStats.gd
## Stats PURES du "Stand de tir" (.orchestrator/contract-r4a.md, R4-TRAIN #3 :
## "hit/headshot stats and DPS readout") : compte les touches confirmées
## (`Weapon.hit_confirmed`, écouté par `scripts/training/ShootingRange.gd`) et
## calcule un DPS glissant. Aucun nœud/scène — RefCounted, testable seul.
class_name RangeStats
extends RefCounted

var shots_hit: int = 0
var headshots: int = 0
var total_damage: float = 0.0
## Historique (horodatage, dégâts) pour le DPS glissant — purgé au fil de l'eau.
var _events: Array = []

func record_hit(dmg: float, headshot: bool, t: float) -> void:
	shots_hit += 1
	if headshot:
		headshots += 1
	total_damage += dmg
	_events.append({"t": t, "dmg": dmg})

## % de touches à la tête (0 si aucune touche encore).
func headshot_ratio() -> float:
	return ratio_of(headshots, shots_hit)

static func ratio_of(part: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return float(part) / float(total)

## Dégâts/seconde sur les `window` dernières secondes (glissant). Purge les
## évènements plus vieux que la fenêtre à chaque appel (pas de fuite mémoire
## sur une longue session d'entraînement).
func dps(now: float, window: float = 5.0) -> float:
	var cutoff := now - window
	var kept: Array = []
	var sum := 0.0
	for e in _events:
		if float(e["t"]) >= cutoff:
			kept.append(e)
			sum += float(e["dmg"])
	_events = kept
	if window <= 0.0:
		return 0.0
	return sum / window

func reset() -> void:
	shots_hit = 0
	headshots = 0
	total_damage = 0.0
	_events.clear()
