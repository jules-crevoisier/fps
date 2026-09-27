## BulletWhizz.gd
## Géométrie PURE du sifflement de balle (tâche "son", 2026-09-27, point 6) :
## plus courte distance entre la tête du joueur LOCAL et le segment d'un tir
## DISTANT (origine -> point d'impact ou portée max, voir Weapon._fire_visuals)
## — un tir qui passe assez près sans toucher personne siffle, joué au point
## de moindre approche (voir l'appelant, Weapon.gd, seul à connaître la scène).
class_name BulletWhizz
extends RefCounted

## Rayon (m) de moindre approche en-deçà duquel un tir distant siffle —
## contrat lead : "~2.5 m".
const WHIZZ_RADIUS_M := 2.5

## Point du segment [a, b] le plus proche de `p` — projection scalaire
## bornée à [0, 1] (jamais hors segment, contrairement à une droite infinie).
## Segment dégénéré (a == b) : le point unique lui-même.
static func closest_point_on_segment(a: Vector3, b: Vector3, p: Vector3) -> Vector3:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0000001:
		return a
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return a + ab * t

## Distance (m) de `p` au segment [a, b] (plus courte approche).
static func closest_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	return closest_point_on_segment(a, b, p).distance_to(p)

## Cette distance de moindre approche déclenche-t-elle le sifflement ?
static func should_whizz(dist: float, radius: float = WHIZZ_RADIUS_M) -> bool:
	return dist < radius
