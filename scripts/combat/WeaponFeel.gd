## WeaponFeel.gd
## Calculs PURS de la "sensation d'arme" (contract-r3.md, R3-IN#4) : motif de
## recul fixe puis pseudo-aléatoire, dispersion additionnelle en mouvement/en
## l'air, délai avant de pouvoir tirer après un sprint/slide/dive, et
## progression de la transition de visée (ADS). Aucun accès à l'arbre de
## scène — consommé par Weapon.gd (prédiction PROPRIÉTAIRE ; le serveur ne
## revalide pas la dispersion/le recul, seulement l'origine/la direction du
## tir via ShotValidator, donc prédiction et serveur restent cohérents par
## construction). Testé isolément dans tests/combat/test_weapon_feel.gd.
class_name WeaponFeel
extends RefCounted

## Décalage de recul pour le `shot_index`-ième tir (0-based) DEPUIS le début
## du spray courant : x = déviation horizontale (yaw, deg), y = montée
## verticale (pitch, deg). Sous `pattern_shots`, suit `recoil_pattern`
## (motif FIXE, façon Valorant) ; au-delà, retombe sur le recul
## pseudo-aléatoire (recoil_horizontal aléatoire, recoil_vertical constant —
## comportement pré-existant). `rng` optionnel pour rendre le tirage
## déterministe en test ; par défaut le RNG global (randf_range).
static func recoil_for_shot(c: WeaponConfig, shot_index: int, rng: RandomNumberGenerator = null) -> Vector2:
	if shot_index >= 0 and shot_index < c.pattern_shots and shot_index < c.recoil_pattern.size():
		var p: Vector2 = c.recoil_pattern[shot_index]
		return Vector2(p.x, p.y)
	var rh := c.recoil_horizontal
	var yaw := rng.randf_range(-rh, rh) if rng else randf_range(-rh, rh)
	return Vector2(yaw, c.recoil_vertical)

## Dispersion totale (deg) = dispersion de base (hanche ou visée, choisie par
## l'appelant) + pénalité de mouvement + pénalité aérienne.
static func total_spread_deg(base_deg: float, c: WeaponConfig, moving: bool, airborne: bool) -> float:
	var s := base_deg
	if moving:
		s += c.move_spread_add
	if airborne:
		s += c.air_spread_add
	return s

## Délai (s) restant avant de pouvoir tirer, selon le temps écoulé (s) depuis
## la fin d'un sprint/slide/dive (INF si l'action n'a jamais eu lieu — pas de
## pénalité). Le délai le plus contraignant des trois domine
## (sprint_to_fire/slide_to_fire/dive_to_fire) ; jamais négatif.
static func fire_delay_left(c: WeaponConfig, since_sprint: float, since_slide: float, since_dive: float) -> float:
	var left := 0.0
	left = maxf(left, c.sprint_to_fire - since_sprint)
	left = maxf(left, c.slide_to_fire - since_slide)
	left = maxf(left, c.dive_to_fire - since_dive)
	return left

## Progression ADS (0 = hanche, 1 = visée pleine), avancée sur `ads_time` s
## (au lieu d'une vitesse fixe) — voir ViewModel.AnimState.ads_blend.
static func ads_progress(current: float, aiming: bool, delta: float, ads_time: float) -> float:
	var t := maxf(ads_time, 0.001)
	return move_toward(current, 1.0 if aiming else 0.0, delta / t)
