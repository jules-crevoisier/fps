## BotStuck.gd
## Anti-blocage PUR (BOT-09, docs/research/02_bots_ai.md §2.1/§4#13 : « surveiller
## la vitesse moyenne sur une courte fenêtre. Si bloqué : wiggle aléatoire, puis
## saut aléatoire », et l'écart constaté chez nous, `avoidance_enabled = false`,
## « pas de surveillance de la vitesse moyenne »). Une instance PAR bot, nourrie
## à chaque tick physique par `BotBrain.gd` via `update()` — AUCUN accès à
## l'arbre de scène (seuls `NavigationServer3D.map_get_closest_point`, une
## fonction de serveur global, pas un nœud, et les Vector3/RID reçus en
## paramètres) : testée isolément dans tests/ai/test_bot_stuck.gd.
##
## Séquence si la vitesse moyenne glissante sur SPEED_WINDOW (1 s) tombe sous
## STUCK_SPEED_THRESHOLD alors qu'un chemin de navigation est ACTIF :
##   1. WIGGLE  — oscillation latérale (strafe alterné) pendant WIGGLE_DURATION.
##   2. JUMP    — une impulsion de saut (un seul tick, comme `Input.is_action_
##      just_pressed`, voir scripts/player/PlayerInput.gd:109).
##   3. request_repath — un seul tick plus tard, signale à l'appelant de
##      re-router vers un point INTERMÉDIAIRE ALTERNATIF (`alternate_repath_point`,
##      jamais la position courante ni l'objectif direct : un point décalé
##      PERPENDICULAIREMENT à la direction de blocage, côté alterné à chaque
##      déclenchement, puis PROJETÉ sur la navmesh).
## Une fois la séquence lancée, elle va jusqu'au bout (pas d'annulation en cours
## de route sur un sursaut de vitesse isolé — la fenêtre d'1 s qui a déclenché
## le blocage reflète déjà un problème réel, pas un bruit d'une frame) ; un
## COOLDOWN suit la demande de repath pour laisser au nouveau chemin le temps de
## faire effet avant de rejuger "bloqué" sur les mêmes échantillons pré-fuite.
class_name BotStuck
extends RefCounted

# ======================================================================
#  Détection — fenêtre de vitesse moyenne glissante.
# ======================================================================

const SPEED_WINDOW := 1.0            ## Fenêtre (s) sur laquelle la vitesse moyenne est mesurée.
const STUCK_SPEED_THRESHOLD := 0.5   ## m/s — sous ce seuil, chemin actif, le bot est jugé bloqué.

# ======================================================================
#  Séquence de déblocage — wiggle -> saut -> demande de repath -> cooldown.
# ======================================================================

const WIGGLE_DURATION := 0.3         ## s — durée de l'oscillation latérale.
const WIGGLE_HZ := 5.0               ## Hz — fréquence de l'oscillation gauche/droite (1.5 cycle sur 0.3 s : les deux sens sont bien parcourus).
const COOLDOWN_DURATION := 1.5       ## s — après la demande de repath, avant de pouvoir se rejuger "bloqué" (laisse le nouveau chemin faire effet).

## Décalage LATÉRAL (m, perpendiculaire à la direction de blocage) du point
## intermédiaire alternatif, avant projection sur la navmesh — alterne de côté
## à chaque déclenchement (si le premier essai échoue encore, le suivant tente
## l'autre côté plutôt que de re-proposer le même point).
const ALT_POINT_OFFSET := 2.0
## Durée (s) pendant laquelle l'appelant doit laisser `nav_agent.target_position`
## pointer vers le point alternatif avant de le laisser reprendre l'objectif
## normal (sinon le repath périodique de BotBrain, toutes les 0.5 s, écrase le
## point alternatif avant même que le bot ait pu s'en approcher).
const ALT_TARGET_HOLD_SECONDS := 1.0

enum Phase { IDLE, WIGGLE, JUMP, REQUEST_REPATH, COOLDOWN }

var _phase: int = Phase.IDLE
var _phase_timer: float = 0.0
var _alt_side: int = 1

var _has_last_pos: bool = false
var _last_pos: Vector3 = Vector3.ZERO
var _window_samples: Array = []   ## file de {"dt": float, "dist": float}, la plus ancienne en tête.
var _window_time: float = 0.0
var _window_dist: float = 0.0


# ======================================================================
#  Fenêtre de vitesse moyenne — alimentée à CHAQUE tick, quel que soit l'état.
# ======================================================================

func _update_speed_window(delta: float, position: Vector3) -> void:
	if delta <= 0.0:
		return
	var dist := 0.0
	if _has_last_pos:
		dist = _last_pos.distance_to(position)
	else:
		_has_last_pos = true
	_last_pos = position
	_window_samples.append({"dt": delta, "dist": dist})
	_window_time += delta
	_window_dist += dist
	# Ne retire le plus ancien échantillon QUE si la fenêtre reste au moins
	# aussi grande que SPEED_WINDOW sans lui (regarder AVANT de dépiler) —
	# dépiler dès que `_window_time` DÉPASSE SPEED_WINDOW (comme un simple
	# `while _window_time > SPEED_WINDOW`) la ramène systématiquement tout
	# juste SOUS le seuil : avec un bruit flottant accumulé sur des centaines
	# d'additions de 1/60, `_window_time` ne redépasserait alors plus JAMAIS
	# SPEED_WINDOW de façon fiable, et `update()` ne détecterait donc jamais
	# "fenêtre pleine" (le bug observé : plus aucun déclenchement après 1.5 s).
	while _window_samples.size() > 1 and (_window_time - float(_window_samples[0]["dt"])) >= SPEED_WINDOW:
		var oldest: Dictionary = _window_samples.pop_front()
		_window_time -= float(oldest["dt"])
		_window_dist -= float(oldest["dist"])


## Oublie l'historique de position — utilisé après une demande de repath : le
## bot va se déplacer vers un nouveau point, l'ancienne fenêtre (quasi
## immobile, c'est justement ce qui a déclenché la séquence) ne doit pas
## re-déclencher instantanément un second blocage sur les mêmes échantillons.
func _reset_speed_window() -> void:
	_window_samples.clear()
	_window_time = 0.0
	_window_dist = 0.0
	_has_last_pos = false


## Vitesse moyenne (m/s) sur la fenêtre glissante courante (0 tant qu'aucun
## échantillon n'a été intégré).
func current_average_speed() -> float:
	if _window_time <= 0.0:
		return 0.0
	return _window_dist / _window_time


# ======================================================================
#  Machine à états — un tick.
# ======================================================================

## Un tick de la machine de déblocage. `delta` (s), `position` (position monde
## COURANTE du bot), `has_active_path` (vrai si le NavigationAgent3D a un
## chemin en cours, ni terminé ni invalide — voir BotBrain._tick_movement).
## Renvoie :
##   "phase"           : la Phase dont le COMPORTEMENT produit CE tick (jamais
##                       la phase interne "après transition" — une phase d'un
##                       seul tick comme JUMP transite ET agit dans le MÊME
##                       appel : `jump_pressed=true` est donc bien rapporté
##                       avec "phase" == Phase.JUMP, pas déjà REQUEST_REPATH).
##   "blocked"          : vrai pendant toute la séquence de déblocage (WIGGLE,
##                       JUMP, REQUEST_REPATH) — utilisé pour la métrique
##                       "temps cumulé bloqué" (BOT-13, hors périmètre ici).
##   "move_override"   : Vector2 (déplacement local à appliquer À LA PLACE du
##                       déplacement normal) pendant WIGGLE/JUMP/REQUEST_REPATH,
##                       sinon `null`.
##   "jump_pressed"    : vrai un seul tick (édge, comme Input.is_action_just_
##                       pressed) au moment du saut.
##   "request_repath"  : vrai un seul tick, un tick après le saut : demande à
##                       l'appelant un repath vers `alternate_repath_point`.
func update(delta: float, position: Vector3, has_active_path: bool) -> Dictionary:
	_update_speed_window(delta, position)
	var out := {
		"phase": Phase.IDLE,
		"blocked": false,
		"move_override": null,
		"jump_pressed": false,
		"request_repath": false,
	}

	match _phase:
		Phase.IDLE:
			out.phase = Phase.IDLE
			if has_active_path and _window_time >= SPEED_WINDOW and current_average_speed() < STUCK_SPEED_THRESHOLD:
				_phase = Phase.WIGGLE
				_phase_timer = WIGGLE_DURATION
				out.phase = Phase.WIGGLE
				out.blocked = true
				out.move_override = _wiggle_move(0.0)

		Phase.WIGGLE:
			out.phase = Phase.WIGGLE
			out.blocked = true
			var elapsed := WIGGLE_DURATION - _phase_timer
			out.move_override = _wiggle_move(elapsed)
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				_phase = Phase.JUMP

		Phase.JUMP:
			out.phase = Phase.JUMP
			out.blocked = true
			out.move_override = Vector2.ZERO
			out.jump_pressed = true
			_phase = Phase.REQUEST_REPATH

		Phase.REQUEST_REPATH:
			out.phase = Phase.REQUEST_REPATH
			out.blocked = true
			out.move_override = Vector2.ZERO
			out.request_repath = true
			_phase = Phase.COOLDOWN
			_phase_timer = COOLDOWN_DURATION
			_reset_speed_window()

		Phase.COOLDOWN:
			out.phase = Phase.COOLDOWN
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				_phase = Phase.IDLE

	return out


## Déplacement local (`move.x` seulement) de l'oscillation latérale au temps
## `elapsed` (s, depuis le début de la phase WIGGLE) : `sign(sin(...))`, jamais
## un `lerp` continu — un vrai "wiggle" doit changer de sens franchement, pas
## glisser d'un côté à l'autre.
func _wiggle_move(elapsed: float) -> Vector2:
	var x := signf(sin(elapsed * WIGGLE_HZ * TAU))
	return Vector2(x, 0.0)


# ======================================================================
#  Point intermédiaire alternatif — perpendiculaire à la direction de
#  blocage, côté alterné, PROJETÉ sur la navmesh.
# ======================================================================

## Point vers lequel router après une séquence de déblocage : décalé de
## ALT_POINT_OFFSET m PERPENDICULAIREMENT à `blocked_dir` (la direction
## horizontale vers laquelle le bot tentait d'avancer quand il s'est bloqué),
## côté alterné à chaque appel, puis projeté sur la navmesh (`nav_map`) via
## `project_strafe_to_navmesh` — jamais un point flottant hors surface
## navigable qui ferait échouer le repath.
func alternate_repath_point(current_pos: Vector3, blocked_dir: Vector3, nav_map: RID) -> Vector3:
	var side := _alt_side
	_alt_side = -_alt_side

	var horizontal := Vector3(blocked_dir.x, 0.0, blocked_dir.z)
	if horizontal.length() < 0.01:
		horizontal = Vector3.FORWARD
	horizontal = horizontal.normalized()
	var perpendicular := Vector3(-horizontal.z, 0.0, horizontal.x) * float(side)

	var candidate := current_pos + perpendicular * ALT_POINT_OFFSET
	return project_strafe_to_navmesh(candidate, nav_map)


## Projette `desired_pos` (position monde visée par un déplacement, ex. le
## strafe de combat ou le point alternatif ci-dessus) sur la navmesh via
## `NavigationServer3D.map_get_closest_point` — jamais appliqué "en aveugle" :
## un point hors surface navigable (bord de toit, vide) revient tronqué vers
## la navmesh la plus proche (BOT-09, écart #13 : `avoidance_enabled = false`,
## strafe qui « pousse hors du chemin »). `nav_map` invalide (pas encore
## synchronisée) : renvoie `desired_pos` inchangé plutôt que planter.
static func project_strafe_to_navmesh(desired_pos: Vector3, nav_map: RID) -> Vector3:
	if not nav_map.is_valid():
		return desired_pos
	return NavigationServer3D.map_get_closest_point(nav_map, desired_pos)
