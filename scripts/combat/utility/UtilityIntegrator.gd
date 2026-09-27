## UtilityIntegrator.gd
## Intégrateur PUR et DÉTERMINISTE du vol d'un objet lancé (frag/flash/smoke) :
## un pas de gravité, un rebond avec restitution/frottement contre la géométrie
## du monde, un seuil d'arrêt. Même code exécuté par CHAQUE pair à un pas de
## temps FIXE (contrat lead : "every peer simulates the SAME deterministic
## path locally for visuals, fixed timestep, same raycast rules") — voir
## ThrownUtility.gd, seul appelant en jeu. Le raycast est passé en paramètre
## (PhysicsDirectSpaceState3D déjà résolu par l'appelant), même convention que
## BotPerception.has_los_to_any_point : cette classe reste testable sans
## dépendre elle-même de l'arbre de scène.
class_name UtilityIntegrator
extends RefCounted

## Gravité (m/s²) — constante PROPRE à l'intégrateur (indépendante de
## ProjectSettings physics/3d/default_gravity, comme WeaponMath ne dépend
## d'aucun réglage moteur) : un pas déterministe ne doit jamais varier si un
## réglage projet change par ailleurs.
const GRAVITY := 9.8

## Masque de raycast du rebond : le monde SEUL (jamais les joueurs, jamais la
## fumée — PhysicsLayers.VISION — qui ne bloque que la VUE, jamais un objet
## physique qui vole à travers).
const BOUNCE_MASK := PhysicsLayers.WORLD

## Marge (m) hors de la surface touchée à laquelle repositionner l'objet après
## un rebond — évite qu'un rebond répété au même endroit ne s'enfonce
## progressivement dans la géométrie par erreur d'arrondi.
const SURFACE_EPSILON := 0.02

## Un pas de vol SANS collision (chute libre) — fonction PURE minimale, isolée
## pour rester testable indépendamment du rebond (voir test "flight").
static func integrate_free(pos: Vector3, vel: Vector3, delta: float) -> Dictionary:
	var new_vel := vel + Vector3(0.0, -GRAVITY, 0.0) * delta
	var new_pos := pos + new_vel * delta
	return {"position": new_pos, "velocity": new_vel}

## Un pas complet (gravité + rebond contre le monde si le segment parcouru
## touche quelque chose) — `space` nul revient au vol libre pur (tests de
## trajectoire sans scène physique). `exclude` : RID à ignorer (le lanceur
## lui-même, éventuellement d'autres projectiles).
## Renvoie {"position", "velocity", "at_rest", "bounced"}.
static func step(pos: Vector3, vel: Vector3, delta: float, cfg: UtilityConfig,
		space: PhysicsDirectSpaceState3D = null, exclude: Array = []) -> Dictionary:
	var free := integrate_free(pos, vel, delta)
	var new_pos: Vector3 = free["position"]
	var new_vel: Vector3 = free["velocity"]

	if space == null:
		return {"position": new_pos, "velocity": new_vel, "at_rest": false, "bounced": false}

	var q := PhysicsRayQueryParameters3D.create(pos, new_pos, BOUNCE_MASK)
	q.exclude = exclude
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {"position": new_pos, "velocity": new_vel, "at_rest": false, "bounced": false}

	var normal: Vector3 = hit.normal
	var bounced_vel := reflect_with_restitution_and_friction(new_vel, normal, cfg.restitution, cfg.friction)
	var settled := bounced_vel.length() < cfg.rest_speed
	return {
		"position": hit.position + normal * (SURFACE_EPSILON + cfg.collision_radius),
		"velocity": Vector3.ZERO if settled else bounced_vel,
		"at_rest": settled,
		"bounced": true,
	}

## Vitesse après rebond sur une surface de normale `normal` : la composante
## NORMALE s'inverse et perd `1 - restitution` de son énergie, la composante
## TANGENTIELLE perd `friction` (jamais l'inverse — un rebond très élastique
## mais glissant, ou très mou mais qui roule librement, sont deux réglages
## distincts du contrat lead : restitution ~0.35, frottement séparé). Fonction
## PURE, testée directement (tests/combat/utility/test_utility_integrator.gd).
static func reflect_with_restitution_and_friction(vel: Vector3, normal: Vector3, restitution: float, friction: float) -> Vector3:
	var n := normal.normalized()
	var normal_speed := vel.dot(n)
	var normal_component := n * normal_speed
	var tangent_component := vel - normal_component
	# `normal_speed` est négatif quand la vitesse rentre DANS la surface (cas
	# normal d'un impact) : on ne renverse/atténue que dans ce cas — un appel
	# avec une vitesse déjà sortante (ne devrait pas arriver en jeu) traverse
	# sans changement plutôt que d'accélérer l'objet.
	var new_normal_component := normal_component
	if normal_speed < 0.0:
		new_normal_component = -normal_component * restitution
	var new_tangent_component := tangent_component * (1.0 - friction)
	return new_normal_component + new_tangent_component

## Simule le chemin complet depuis `pos`/`vel` jusqu'à l'arrêt (`at_rest`) ou
## `max_time` secondes — utilisé aussi bien pour l'aperçu de trajectoire (HUD,
## UtilityThrower.gd) que pour les tests d'intégration bout-en-bout ("bounce",
## "rest"). Renvoie la liste des positions visitées (première = `pos` de
## départ) — jamais vide.
static func simulate_path(pos: Vector3, vel: Vector3, cfg: UtilityConfig,
		space: PhysicsDirectSpaceState3D, exclude: Array = [],
		max_time: float = 4.0, dt: float = 1.0 / 60.0) -> Array:
	var points: Array = [pos]
	var cur_pos := pos
	var cur_vel := vel
	var t := 0.0
	while t < max_time:
		var res := step(cur_pos, cur_vel, dt, cfg, space, exclude)
		cur_pos = res["position"]
		cur_vel = res["velocity"]
		points.append(cur_pos)
		t += dt
		if res["at_rest"]:
			break
	return points
