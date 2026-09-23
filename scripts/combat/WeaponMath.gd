## WeaponMath.gd
## Fonctions de dégâts pures (falloff, headshot, TTK). Aucune dépendance à
## l'arbre de scène : utilisées par Weapon.gd (résolution serveur) et par les
## tests (tests/combat/test_weapon_math.gd).
class_name WeaponMath
extends RefCounted

## Hauteur (m) au-dessus de l'origine du corps à partir de laquelle un impact
## est considéré comme un tir à la tête.
const HEAD_HEIGHT := 1.4

## Dégâts à `dist` mètres : plein dégât jusqu'à falloff_start, damage_min à
## partir de falloff_end, interpolation linéaire entre les deux.
static func damage_at(dist: float, c: WeaponConfig) -> float:
	if dist <= c.falloff_start:
		return c.damage
	if dist >= c.falloff_end:
		return c.damage_min
	var t := (dist - c.falloff_start) / (c.falloff_end - c.falloff_start)
	return lerpf(c.damage, c.damage_min, t)

## Un impact est-il un tir à la tête ? Strictement au-dessus de HEAD_HEIGHT.
static func is_headshot(hit_y: float, body_origin_y: float) -> bool:
	return hit_y > body_origin_y + HEAD_HEIGHT

## Dégâts d'un tir complet (tous les plombs touchent) : falloff × multiplicateur
## de tête (si headshot) × nombre de plombs.
static func shot_damage(c: WeaponConfig, dist: float, headshot: bool) -> float:
	var d := damage_at(dist, c)
	if headshot:
		d *= c.headshot_mult
	return d * float(maxi(1, c.pellets))

## Nombre de tirs nécessaires pour tuer une cible à `hp` PV (arrondi au supérieur).
static func shots_to_kill(c: WeaponConfig, dist: float, hp: float, headshot: bool) -> int:
	var dmg := shot_damage(c, dist, headshot)
	return int(ceil(hp / dmg))

## Temps pour tuer (ms) : (tirs - 1) / cadence — le dernier tir n'attend pas.
static func ttk_ms(c: WeaponConfig, dist: float, hp: float, headshot: bool) -> float:
	var shots := shots_to_kill(c, dist, hp, headshot)
	return float(shots - 1) / c.fire_rate * 1000.0
