## SpawnPick.gd
## Sélection de spawn PURE (.orchestrator/maps-spec-v2.md §7.6) : parmi
## `points`, choisit celui qui maximise la distance au `enemies` (joueurs
## ennemis VIVANTS) le plus proche — "every respawn picks the point furthest
## from the nearest living enemy" (§5.6, la parade Wasteland au spawn-kill,
## appliquée à `GameWorld._get_spawn_position` pour TOUTES les maps : ça
## n'aggrave jamais une map symétrique, et ça corrige un vrai problème sur
## les asymétriques). Sans ennemi vivant (début de partie, aucun adversaire
## encore spawné), ou `points` vide, retombe sur `cursor` (l'ancien tourniquet
## round-robin) pour ne rien changer au comportement existant.
class_name SpawnPick
extends RefCounted

static func safest(points: Array, enemies: Array, cursor: int) -> int:
	if points.is_empty():
		return 0
	var cursor_idx := cursor % points.size()
	if enemies.is_empty():
		return cursor_idx
	var dists: Array = []
	var best_dist := -1.0
	for i in points.size():
		var p: Vector3 = points[i]
		var nearest := INF
		for e in enemies:
			var d: float = p.distance_to(e as Vector3)
			if d < nearest:
				nearest = d
		dists.append(nearest)
		if nearest > best_dist:
			best_dist = nearest
	# Égalité (à 1 cm près) : le tourniquet départage, comme un round-robin
	# stable plutôt qu'un choix arbitraire entre points à distance égale.
	if absf(dists[cursor_idx] - best_dist) < 0.01:
		return cursor_idx
	for i in points.size():
		if absf(dists[i] - best_dist) < 0.01:
			return i
	return cursor_idx
