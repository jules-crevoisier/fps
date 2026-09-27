## SmokeMath.gd
## Minuterie PURE du fumigène : détonation anticipée au sol, puis
## croissance/tenue/dissipation du nuage — contrat lead : "detonates 1.4s
## after release, or on first ground contact after 0.8s, whichever comes
## first" et "builds a cloud of radius 4.5m over 1s, holds for 12s, then
## fades over 1.5s".
class_name SmokeMath
extends RefCounted

## Vrai si le fumigène doit détoner MAINTENANT : amorce (`cfg.fuse_time`)
## écoulée depuis le relâchement, OU au sol depuis au moins
## `cfg.smoke_ground_arm_seconds` — le premier des deux qui survient (contrat
## lead, "whichever comes first"). `time_since_release` : secondes écoulées
## depuis le relâchement de la touche (fuse démarrée à la volée, PAS au
## premier appui — voir UtilityConfig.fuse_starts_on_press = false pour ce type).
static func should_detonate(time_since_release: float, is_grounded: bool, cfg: UtilityConfig) -> bool:
	if time_since_release >= cfg.fuse_time:
		return true
	return is_grounded and time_since_release >= cfg.smoke_ground_arm_seconds

## Rayon (m) du nuage à `t` secondes après la détonation : croissance linéaire
## 0 -> `smoke_radius` sur `smoke_grow_seconds`, plein rayon pendant
## `smoke_hold_seconds`, puis décroissance linéaire vers 0 sur
## `smoke_fade_seconds`. 0 avant/après la fenêtre de vie totale.
static func cloud_radius(t: float, cfg: UtilityConfig) -> float:
	if t < 0.0:
		return 0.0
	var grow_end := cfg.smoke_grow_seconds
	var hold_end := grow_end + cfg.smoke_hold_seconds
	var fade_end := hold_end + cfg.smoke_fade_seconds
	if t < grow_end:
		if grow_end <= 0.0:
			return cfg.smoke_radius
		return lerpf(0.0, cfg.smoke_radius, t / grow_end)
	if t < hold_end:
		return cfg.smoke_radius
	if t < fade_end:
		if cfg.smoke_fade_seconds <= 0.0:
			return 0.0
		var ft := (t - hold_end) / cfg.smoke_fade_seconds
		return lerpf(cfg.smoke_radius, 0.0, ft)
	return 0.0

## Opacité visuelle (0-1) suivant la même enveloppe que `cloud_radius` — le
## nuage apparaît/disparaît en fondu plutôt qu'en changeant seulement de
## taille (des sphères minuscules à pleine opacité auraient l'air de
## ponctuer, pas de se dissiper).
static func cloud_alpha(t: float, cfg: UtilityConfig) -> float:
	var r := cloud_radius(t, cfg)
	if cfg.smoke_radius <= 0.0:
		return 0.0
	return clampf(r / cfg.smoke_radius, 0.0, 1.0)

## Durée de vie totale (s) du nuage depuis la détonation (croissance + tenue +
## fondu) — utile à l'appelant pour savoir quand libérer le nœud du nuage.
static func total_lifetime(cfg: UtilityConfig) -> float:
	return cfg.smoke_grow_seconds + cfg.smoke_hold_seconds + cfg.smoke_fade_seconds
