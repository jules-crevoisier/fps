## BotTargetSelect.gd
## Choix de cible PUR parmi des candidats déjà filtrés par l'appelant
## (ligne de vue + portée + audition — scripts/ai/BotBrain.gd, qui fait les
## raycasts). Aucun accès à l'arbre de scène. Politique actuelle : la cible
## visible la plus proche gagne (comportement humain-like simple et lisible).
## Testé isolément dans tests/ai/test_bot_target_select.gd.
class_name BotTargetSelect
extends RefCounted

## `candidates` : Array de Dictionary {"id": int, "distance": float, ...}.
## Renvoie l'id du meilleur candidat, -1 si `candidates` est vide.
static func choose(candidates: Array) -> int:
	var best_id := -1
	var best_dist := INF
	for c in candidates:
		var d: float = c.get("distance", INF)
		if d < best_dist:
			best_dist = d
			best_id = int(c.get("id", -1))
	return best_id
