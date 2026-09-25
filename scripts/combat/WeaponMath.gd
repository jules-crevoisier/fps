## WeaponMath.gd
## Fonctions de dégâts pures (falloff, headshot, TTK). Aucune dépendance à
## l'arbre de scène : utilisées par Weapon.gd (résolution serveur) et par les
## tests (tests/combat/test_weapon_math.gd).
class_name WeaponMath
extends RefCounted

## Hauteur RÉELLE (mètres) de la zone de tête, mesurée depuis le SOMMET de la
## capsule COURANTE (PlayerController.current_height, répliquée serveur :
## GF-04) — jamais une proportion de `body_height`. Décision du lead (conflit
## §14 de docs/STYLE_BIBLE.md, GF-04B) : la tête garde sa taille réelle
## accroupie, plutôt que de rétrécir avec la capsule (l'approche
## proportionnelle de GF-04 réduisait la bande headshot accroupie à 0,20 m,
## plus petite qu'une tête). Debout (stand_height = 1.8 m), le seuil est
## 1.8 - 0.4 = 1.4 m, identique à l'ancien seuil fixe. Accroupi (crouch_height
## = 0.9 m), le seuil descend à 0.9 - 0.4 = 0.5 m : la bande headshot reste
## haute de 0.4 m dans les deux postures.
const HEAD_SIZE := 0.40

## Dégâts à `dist` mètres : plein dégât jusqu'à falloff_start, damage_min à
## partir de falloff_end, interpolation linéaire entre les deux.
static func damage_at(dist: float, c: WeaponConfig) -> float:
	if dist <= c.falloff_start:
		return c.damage
	if dist >= c.falloff_end:
		return c.damage_min
	var t := (dist - c.falloff_start) / (c.falloff_end - c.falloff_start)
	return lerpf(c.damage, c.damage_min, t)

## Un impact est-il un tir à la tête ? Strictement au-dessus du sommet de la
## capsule courante moins `HEAD_SIZE` : `body_origin_y + body_height -
## HEAD_SIZE` — `body_height` est la hauteur COURANTE de la cible (debout OU
## accroupie), jamais 1.4 m fixe.
static func is_headshot(hit_y: float, body_origin_y: float, body_height: float) -> bool:
	return hit_y > body_origin_y + body_height - HEAD_SIZE

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
