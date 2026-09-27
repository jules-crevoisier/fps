## FragMath.gd
## Dégâts PURS de la grenade à fragmentation (falloff linéaire) + règle
## d'équipe. Aucune dépendance à l'arbre de scène — la ligne de vue (raycast
## contre la géométrie du monde) et la résolution des cibles restent du
## ressort de ThrownUtility.gd/UtilityThrower.gd (serveur), qui appellent ces
## fonctions avec des booléens déjà résolus. Même séparation que
## WeaponMath.gd pour les balles.
class_name FragMath
extends RefCounted

## Dégâts à `dist` mètres du centre de l'explosion : plein dégât au centre,
## chute LINÉAIRE jusqu'à 0 à `cfg.frag_damage_radius` (contrat lead : "130 at
## the center, linear falloff to 0 at 6.5 m" — pas de palier plat comme
## WeaponMath.damage_at, une vraie rampe dès la distance 0).
static func damage_at(dist: float, cfg: UtilityConfig) -> float:
	if cfg.frag_damage_radius <= 0.0:
		return 0.0
	var t := clampf(dist / cfg.frag_damage_radius, 0.0, 1.0)
	return lerpf(cfg.frag_damage, 0.0, t)

## Règle d'équipe (contrat lead : "Self damage yes, teammates no") — NOTE :
## contrairement à ce que sous-entend le contrat ("follow the existing
## friendly-fire rule used for bullets"), les balles (Weapon._resolve_ray)
## n'ont AUCUNE règle d'équipe aujourd'hui (elles blessent tout le monde, y
## compris les coéquipiers — seul le score de kill distingue les équipes, voir
## TDMMode.on_kill) : il n'existe donc rien à "suivre". Cette fonction
## implémente la règle explicite demandée pour les grenades spécifiquement
## (voir le rendu de tâche, section "blocked_on", pour signaler l'écart au
## lead). `is_self` prime toujours sur `same_team` (l'auto-dégât fonctionne
## même si `same_team` vaut vrai par construction pour soi-même).
static func should_damage(is_self: bool, same_team: bool) -> bool:
	return is_self or not same_team

## Dégâts finaux appliqués à une cible : falloff × règle d'équipe/self × ligne
## de vue (`has_los`, calculée par l'appelant — raycast vers le TORSE de la
## cible, contrat lead) — 0 si l'une des conditions échoue.
static func damage_for_target(dist: float, cfg: UtilityConfig, is_self: bool, same_team: bool, has_los: bool) -> float:
	if not has_los:
		return 0.0
	if not should_damage(is_self, same_team):
		return 0.0
	return damage_at(dist, cfg)
