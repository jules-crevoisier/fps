## UtilityValidator.gd
## Validation PURE d'une requête de lancer côté serveur — même patron que
## ShotValidator.gd : l'origine doit être finie et proche de la tête du
## joueur (couvre le lag de réplication), la direction un Vector3 fini
## normalisé, et le temps de maintien annoncé par le client compatible avec
## l'amorce déclarée (jamais négatif, jamais plus long que l'amorce elle-même
## — un client qui annonce un maintien plus long aurait dû déclencher
## l'explosion en main AVANT d'envoyer la requête, voir
## UtilityThrowInput.should_explode_in_hand). Les vérifications qui dépendent
## d'un ÉTAT serveur (vivant, charge disponible, manche verrouillée, cadence)
## restent des booléens déjà résolus par l'appelant (UtilityThrower._server_throw),
## combinés ici par `can_throw` — même séparation que Weapon._server_fire,
## qui teste chaque condition séparément plutôt que de les cacher dans une
## fonction à trous.
class_name UtilityValidator
extends RefCounted

## Tolérance (m) entre la position tête connue du serveur et l'origine
## envoyée — identique à ShotValidator.ORIGIN_TOLERANCE (même géométrie,
## même marge de jigue réseau).
const ORIGIN_TOLERANCE := 3.0

## `short` (contrat lead 2026-09-27, "short throw on RIGHT click") : ACCEPTÉ
## tel quel, jamais validé ici — c'est un simple bool, toujours valide côté
## client ; c'est `UtilityThrower.throw_velocity(direction, cfg, short)` (appelé
## par l'appelant APRÈS cette validation, jamais ici) qui en dérive la vitesse
## réelle, jamais une valeur annoncée par le client. Présent dans la signature
## pour que le serveur ait la vue complète de la requête au point de
## validation, même si aucune règle géométrique ne dépend de lui aujourd'hui.
static func is_valid_request(origin: Vector3, head_pos: Vector3, direction: Vector3, held_duration_s: float, cfg: UtilityConfig, short: bool = false) -> bool:
	if not _finite_vec3(origin):
		return false
	if origin.distance_to(head_pos) > ORIGIN_TOLERANCE:
		return false
	if not _finite_vec3(direction):
		return false
	var len := direction.length()
	if len < 0.99 or len > 1.01:
		return false
	if not is_finite(held_duration_s) or held_duration_s < 0.0:
		return false
	# Une frag "cuite" jusqu'à l'amorce complète explose EN MAIN (voir
	# UtilityThrowInput.should_explode_in_hand) et ne passe jamais par cette
	# requête de lancer : un maintien annoncé >= fuse_time est donc toujours
	# suspect (client modifié, ou désynchronisation) pour les types dont
	# l'amorce démarre au premier appui.
	if cfg.fuse_starts_on_press and held_duration_s >= cfg.fuse_time:
		return false
	return true

## Combine les conditions d'ÉTAT (déjà résolues par l'appelant) qui autorisent
## un lancer, indépendamment de la géométrie de la requête (voir
## `is_valid_request` ci-dessus) : vivant, au moins une charge de ce type,
## manche non verrouillée (BUY/PREROUND, même règle que Weapon._round_locked).
static func can_throw(is_alive: bool, has_charge: bool, round_locked: bool) -> bool:
	return is_alive and has_charge and not round_locked

static func _finite_vec3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
