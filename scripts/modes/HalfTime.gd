## HalfTime.gd
## Échange de côté PUR pour les modes d'arène sur map asymétrique
## (.orchestrator/maps-spec-v2.md §7.5/§5.6.2) : "the mode sets sides_swapped
## once, at 50% of the time limit or when the leader reaches half the score
## limit, whichever comes first". `TDMMode`/`HardpointMode` appellent ceci
## une fois par tick tant que `sides_swapped` est encore faux ; dès que ça
## renvoie vrai, ils passent `sides_swapped` à vrai (une seule fois, jamais
## re-basculé).
class_name HalfTime
extends RefCounted

static func should_swap(elapsed_s: float, limit_s: float, score_a: int, score_b: int, score_limit: int) -> bool:
	if limit_s > 0.0 and elapsed_s >= limit_s * 0.5:
		return true
	if score_limit > 0 and (score_a >= score_limit * 0.5 or score_b >= score_limit * 0.5):
		return true
	return false
