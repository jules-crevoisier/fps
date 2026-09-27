## FlashMath.gd
## Durée d'éblouissement PURE de la flashbang selon l'orientation de la
## victime au moment de l'éclat (contrat lead : face/profil/dos) + règle
## d'équipe (affecte les ennemis ET le lanceur, jamais les coéquipiers).
class_name FlashMath
extends RefCounted

## Produit scalaire entre le regard de la victime et la direction VERS
## l'éclat — > 0.5 : la victime fait face au flash (regarde vers lui) ;
## < -0.5 : elle lui tourne le dos ; entre les deux : de profil. Fonction PURE
## isolée pour rester testable sans Node3D (l'appelant passe des vecteurs déjà
## normalisés — voir ThrownUtility._detonate_flash, seul appelant en jeu).
static func facing_dot(victim_forward: Vector3, victim_to_burst_dir: Vector3) -> float:
	if victim_forward.length_squared() < 0.0001 or victim_to_burst_dir.length_squared() < 0.0001:
		return 0.0
	return victim_forward.normalized().dot(victim_to_burst_dir.normalized())

## Durée (s) d'éblouissement selon `dot` (voir `facing_dot`) — seuils du
## contrat lead : dot > 0.5 (face) -> flash_facing_seconds ; dot < -0.5 (dos)
## -> flash_behind_seconds ; sinon (profil) -> flash_side_seconds.
## Fin d'éblouissement progressive : l'écran blanc du joueur visé met RECOVERY_S à
## s'effacer (GameHUD) et il ne voit toujours pas bien pendant ce temps ; les bots et
## l'indicateur visuel au-dessus de la tête (BlindIndicator) suivent la même durée
## totale (retour utilisateur 2026-09-27 : l'indicateur doit durer tout le temps où
## le personnage est flashé).
const RECOVERY_S := 0.6

## Temps total pendant lequel la victime est gênée : éblouissement plein + fondu.
static func impaired_seconds(blind_s: float) -> float:
	return blind_s + RECOVERY_S if blind_s > 0.0 else 0.0

static func blind_duration(dot: float, cfg: UtilityConfig) -> float:
	if dot > 0.5:
		return cfg.flash_facing_seconds
	if dot < -0.5:
		return cfg.flash_behind_seconds
	return cfg.flash_side_seconds

## Règle d'équipe (contrat lead : "affects enemies and the thrower, not
## teammates") — même forme que FragMath.should_damage, nommée séparément
## pour rester lisible au site d'appel (ce n'est pas des "dégâts").
static func should_affect(is_self: bool, same_team: bool) -> bool:
	return is_self or not same_team

## Durée finale appliquée à une cible : 0 si hors de portée, sans ligne de vue
## vers la tête, ou coéquipier (jamais soi-même/un ennemi).
static func blind_duration_for_target(dist: float, dot: float, cfg: UtilityConfig,
		is_self: bool, same_team: bool, has_los: bool) -> float:
	if dist > cfg.flash_radius:
		return 0.0
	if not has_los:
		return 0.0
	if not should_affect(is_self, same_team):
		return 0.0
	return blind_duration(dot, cfg)
