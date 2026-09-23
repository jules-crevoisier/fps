## ShotValidator.gd
## Validation pure d'une requête de tir côté serveur : l'origine doit être
## finie et proche de la tête du joueur (couvre le lag de réplication en
## attendant la compensation de lag, P1.3), et chaque direction doit être un
## Vector3 fini normalisé, en nombre égal au nombre de plombs attendu.
class_name ShotValidator
extends RefCounted

## Tolérance (m) entre la position tête connue du serveur et l'origine envoyée.
const ORIGIN_TOLERANCE := 3.0

static func is_valid(origin: Vector3, head_pos: Vector3, dirs: Array, expected_pellets: int) -> bool:
	if not _finite_vec3(origin):
		return false
	if origin.distance_to(head_pos) > ORIGIN_TOLERANCE:
		return false
	var expected: int = maxi(1, expected_pellets)
	if dirs.size() != expected:
		return false
	for d in dirs:
		if not (d is Vector3):
			return false
		if not _finite_vec3(d):
			return false
		var len: float = d.length()
		if len < 0.99 or len > 1.01:
			return false
	return true

static func _finite_vec3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
