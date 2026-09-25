## BotLook.gd
## Regard humain HORS COMBAT (BOT-25, docs/research/08_bots_humanlike.md §3.1,
## règles L1-L6) — absorbe BOTFIX-01 (« but atteint » : le bot balaie les
## angles connus au lieu de rester statue). Remplace entièrement
## `BotBrain._face_direction`/`_idle_pitch_correction` (BOT-21) : la visée EN
## combat reste `BotAim`/`BotBrain._aim_towards`, inchangée.
##
## PUR comme `BotAim`/`BotStuck`/`BotMapKnowledge` : aucun accès à l'arbre de
## scène, aucun nom de carte — une instance PAR bot, nourrie à chaque tick
## HORS COMBAT par `BotBrain.gd` via `tick()`, qui reçoit tout son contexte en
## paramètre (position, orientation courante, direction de déplacement, points
## de chemin à venir, mémoires ennemi/ouïe, connaissance de carte `BotMapKnowledge`
## optionnelle, RNG). Testée isolément dans tests/ai/test_bot_look.gd.
##
## Priorité de sélection de cible (L1), réévaluée CHAQUE tick (jamais figée
## entre deux tirages de minuterie, contrairement au reste de la sélection) —
## ce sont des signaux de SÉCURITÉ, pas de simples « points d'intérêt » :
##   1. dernière position ennemie connue, si fraîche (< ENEMY_MEMORY_S) ;
##   2. dernier bruit entendu, si frais ;
##   3. coin du chemin qui tourne de plus de CORNER_TURN_DEG à moins de
##      CORNER_RANGE_M (L2 : « pré-visée des coins », toujours à jour, jamais
##      soumis à la minuterie ci-dessous — un virage aveugle n'attend pas 2 s).
## Si aucun des trois ne s'applique, la cible « de roulement » change toutes
## les U(1;2) s (U(5;10) s en tenue d'angle, `ctx.holding_angle`), par ordre :
##   4. angle de carte (K) à moins de 25 m dans ±60° du cap de déplacement ;
##   5. point du chemin 4 m devant (repli, toujours disponible).
## Un balayage des angles K visibles (L5, remplace BOTFIX-01) prend
## temporairement la place de 4/5 dès que la navigation atteint son but
## (`ctx.goal_reached`, front montant détecté en interne).
##
## L1's ordre documenté place l'angle K (4) AVANT le coin (3.7 §3.1) pour le
## choix de ROULEMENT ; le coin est ici élevé au rang des signaux DE SÉCURITÉ
## (comme la mémoire ennemie/l'ouïe) car L2 le décrit comme un déclenchement
## immédiat (« 0.3 à 0.6 s avant d'y arriver ») qui ne peut pas attendre le
## prochain tirage de minuterie — un choix de conception documenté ici, pas un
## écart caché.
class_name BotLook
extends RefCounted

# ======================================================================
#  L1 — minuterie de choix de cible + mémoires de sécurité.
# ======================================================================

const RETARGET_MIN_S := 1.0        ## Nouvelle cible de roulement toutes les U(1;2) s hors tenue d'angle.
const RETARGET_MAX_S := 2.0
const HOLD_ANGLE_MIN_S := 5.0       ## U(5;10) s en tenue d'angle (perchoir/surveillance, `ctx.holding_angle`).
const HOLD_ANGLE_MAX_S := 10.0
const ENEMY_MEMORY_S := 6.0         ## Mémoire de la dernière position ennemie VUE par CE bot (priorité #1).
const ANGLE_RANGE_M := 25.0         ## Portée d'un angle K candidat (priorité #4/roulement, et balayage L5).
const ANGLE_HALF_FOV_DEG := 60.0    ## Demi-cône autour du cap de déplacement pour un angle K de roulement.
const SWEEP_HALF_DEG := 15.0        ## Amplitude du balayage lent en tenue d'angle (± deg autour du cap choisi).
const HOLD_SWEEP_FREQ := TAU / 6.0  ## ~1 aller-retour toutes les 6 s pendant la tenue d'angle.

# ======================================================================
#  L2 — pré-visée des coins (signal de sécurité, voir en-tête).
# ======================================================================

const CORNER_TURN_DEG := 30.0
const CORNER_RANGE_M := 4.0
const CORNER_LOOK_AHEAD_M := 3.0    ## Distance, après le coin, du point regardé (« côté opposé du coin »).

# ======================================================================
#  L3 — tangage (hauteur du point regardé, bande plate par défaut).
# ======================================================================

const LOOK_HEIGHT_M := 1.5          ## Hauteur (m) ajoutée aux points au sol (coin, point de chemin) — « vise à 1.5 m ».
const FLAT_PITCH_LIMIT_DEG := 5.0   ## Sur sol plat (repli « point du chemin », rien de particulier à regarder), tangage borné à ± cette valeur.

# ======================================================================
#  L4 — dynamique du regard : ressort quasi critique, PLAFONNÉ en vitesse et
#  en accélération (contrairement à BotAim.spring_step, qui n'est calibré que
#  pour un dépassement cible sans plafond dur — ici le plafond doit être
#  ABSOLU, quelle que soit l'amplitude du saut de cible).
# ======================================================================

const SPRING_ZETA := 0.9            ## Dans [0.85, 1.0] (quasi critique, quasiment aucun dépassement).
const SPRING_PEAK_SPEED_DEG := 300.0 ## Pic de vitesse VISÉ (deg/s) sur un flick de référence de 90° (BotAim.FLICK_REFERENCE_DEG) avant plafonnement — sous MAX_SPEED_DEG avec marge, le plafond ci-dessous restant la garantie dure pour les sauts plus grands.
const MAX_SPEED_DEG := 360.0        ## Vitesse angulaire MAX absolue hors combat (L4).
const MAX_ACCEL_DEG := 3000.0       ## Accélération angulaire MAX absolue (L4). 45° en 60 ms impliquerait 750°/s de plus en 60ms ; à vitesse plafonnée 360°/s, un saut de 45° en 60ms est de toute façon impossible (360×0.06=21.6° < 45°) : la garantie L4 « jamais 45° en moins de 60ms » découle directement de MAX_SPEED_DEG, voir tests.

# ======================================================================
#  L6 — écart regard / déplacement.
# ======================================================================

const WALK_GAZE_GAP_DEG := 70.0

# --- État d'instance (une par bot) --------------------------------------
var _target_kind: String = ""
var _target_pos: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _retarget_left_s: float = 0.0
var _was_urgent: bool = false
var _hold_sweep_elapsed_s: float = 0.0
var _sweep_queue: Array = []
var _sweep_index: int = 0
var _prev_goal_reached: bool = false
var _yaw_speed_deg: float = 0.0
var _pitch_speed_deg: float = 0.0


# ======================================================================
#  Point d'entrée — un tick HORS COMBAT.
# ======================================================================

## `ctx` attend :
##  - "bot_pos": Vector3, "eye_pos": Vector3 (tête, pour la géométrie de visée)
##  - "cur_yaw_deg": float, "cur_pitch_deg": float (orientation ACTUELLE)
##  - "move_dir": Vector3 (direction de déplacement MONDE, Vector3.ZERO à l'arrêt)
##  - "path_points": Array[Vector3] (points de chemin à venir, dans l'ordre,
##    SANS la position actuelle du bot)
##  - "has_enemy_memory": bool, "enemy_pos": Vector3
##  - "has_heard": bool, "heard_pos": Vector3
##  - "map_knowledge": BotMapKnowledge ou null
##  - "holding_angle": bool (L1 : tenue d'angle, perchoir/surveillance)
##  - "goal_reached": bool (état COURANT de "navigation terminée" — le FRONT
##    montant est détecté ici, l'appelant n'a rien à dériver)
##  - "rng": RandomNumberGenerator
## Renvoie {"look_delta": Vector2 (même convention que PlayerController._look,
## à appliquer TEL QUEL sur `player.input.look_delta`), "force_walk": bool
## (L6), "target_kind": String, "target_pos": Vector3, "gaze_point": Vector3}
## — les 3 derniers champs sont exposés pour les tests, pas pour BotBrain.
func tick(delta: float, ctx: Dictionary) -> Dictionary:
	var goal_reached := bool(ctx.get("goal_reached", false))
	if goal_reached and not _prev_goal_reached:
		_refill_sweep_queue(ctx)
		_retarget_left_s = 0.0
	_prev_goal_reached = goal_reached

	_select_target(delta, ctx)

	var cur_yaw_deg: float = float(ctx.get("cur_yaw_deg", 0.0))
	var cur_pitch_deg: float = float(ctx.get("cur_pitch_deg", 0.0))
	var eye_pos: Vector3 = ctx.get("eye_pos", ctx.get("bot_pos", Vector3.ZERO))
	var gaze_point := _gaze_point_for(_target_kind, _target_pos)

	var target_yaw_deg := cur_yaw_deg
	var target_pitch_deg := cur_pitch_deg
	if eye_pos.distance_to(gaze_point) >= 0.01:
		var yp := desired_yaw_pitch_deg(eye_pos, gaze_point)
		target_yaw_deg = float(yp.yaw)
		target_pitch_deg = float(yp.pitch)

	# L1 : léger balayage ±SWEEP_HALF_DEG superposé au cap choisi tant que le
	# bot TIENT la même cible en tenue d'angle (perchoir/surveillance) — sinon
	# le regard resterait parfaitement statique pendant 5 à 10 s.
	if bool(ctx.get("holding_angle", false)) and _target_kind in ["angle", "sweep", "enemy", "heard"]:
		_hold_sweep_elapsed_s += delta
		target_yaw_deg += sin(_hold_sweep_elapsed_s * HOLD_SWEEP_FREQ) * SWEEP_HALF_DEG
	else:
		_hold_sweep_elapsed_s = 0.0

	# L3, bulle 2 : « sur sol plat, il reste à ±5° de l'horizon » — seul le
	# repli SANS point d'intérêt particulier (point du chemin 4 m devant) est
	# concerné ; un angle K/perchoir/coin/ennemi peut légitimement faire lever
	# les yeux (toits, derrick, grue), voir bulle 1.
	if _target_kind == "path_point":
		target_pitch_deg = clampf(target_pitch_deg, -FLAT_PITCH_LIMIT_DEG, FLAT_PITCH_LIMIT_DEG)

	var params := spring_params()
	var wrapped_target_yaw_deg := cur_yaw_deg + wrapf(target_yaw_deg - cur_yaw_deg, -180.0, 180.0)
	var yaw_step := spring_step_capped(cur_yaw_deg, _yaw_speed_deg, wrapped_target_yaw_deg, params.k, params.d, delta)
	var pitch_step := spring_step_capped(cur_pitch_deg, _pitch_speed_deg, target_pitch_deg, params.k, params.d, delta)
	_yaw_speed_deg = float(yaw_step.speed)
	_pitch_speed_deg = float(pitch_step.speed)

	var new_yaw_deg: float = yaw_step.angle
	var new_pitch_deg: float = pitch_step.angle
	var dy := deg_to_rad(new_yaw_deg - cur_yaw_deg)
	var dp := deg_to_rad(new_pitch_deg - cur_pitch_deg)

	return {
		"look_delta": Vector2(-dy, -dp),
		"force_walk": should_walk(new_yaw_deg, ctx.get("move_dir", Vector3.ZERO)),
		"target_kind": _target_kind,
		"target_pos": _target_pos,
		"gaze_point": gaze_point,
		# Champs de DEBUG (tests uniquement, BotBrain n'en a pas besoin) :
		# valeurs intermédiaires du calcul ci-dessus, pour vérifier le
		# balayage/l'écrêtage de tangage et la convergence du ressort sans
		# devoir ré-intégrer `look_delta` (radians, delta d'UN seul tick).
		"look_target_yaw_deg": target_yaw_deg,
		"look_target_pitch_deg": target_pitch_deg,
		"new_yaw_deg": new_yaw_deg,
		"new_pitch_deg": new_pitch_deg,
	}


## Temps (s) restant avant le prochain choix de cible de ROULEMENT (L1) —
## exposé pour les tests, comme `BotStuck.current_average_speed()`.
func dwell_left_s() -> float:
	return _retarget_left_s


# ======================================================================
#  Sélection de cible.
# ======================================================================

func _select_target(delta: float, ctx: Dictionary) -> void:
	var urgent := _urgent_override(ctx)
	if not urgent.is_empty():
		if _target_kind != String(urgent.kind):
			_commit_target(String(urgent.kind), urgent.pos, ctx)
		else:
			_target_pos = urgent.pos  # suit une cible urgente qui bouge (ennemi) sans relancer la minuterie.
		_was_urgent = true
		return
	if _was_urgent:
		_retarget_left_s = 0.0  # la cible urgente vient de s'éteindre : redécide sans attendre le reste de son délai.
		_was_urgent = false

	_retarget_left_s -= delta
	if not _has_target or _retarget_left_s <= 0.0:
		var picked := _pick_roam_target(ctx)
		_commit_target(String(picked.kind), picked.pos, ctx)


## Signaux DE SÉCURITÉ (L1 #1-2, L2) — réévalués CHAQUE tick, jamais soumis à
## la minuterie de roulement. `{}` si aucun ne s'applique.
func _urgent_override(ctx: Dictionary) -> Dictionary:
	if bool(ctx.get("has_enemy_memory", false)):
		return {"kind": "enemy", "pos": ctx.get("enemy_pos", Vector3.ZERO)}
	if bool(ctx.get("has_heard", false)):
		return {"kind": "heard", "pos": ctx.get("heard_pos", Vector3.ZERO)}
	var path_points: Array = ctx.get("path_points", [])
	var corner := find_sharp_corner(path_points, ctx.get("bot_pos", Vector3.ZERO))
	if bool(corner.get("found", false)):
		return {"kind": "corner", "pos": corner.pos}
	return {}


## Cible de ROULEMENT (L1 #4-5, L5) — balayage K en cours en priorité, sinon
## angle K dans le cap, sinon point du chemin 4 m devant (toujours disponible).
func _pick_roam_target(ctx: Dictionary) -> Dictionary:
	if not _sweep_queue.is_empty():
		var idx: int = _sweep_index % _sweep_queue.size()
		var entry: Dictionary = _sweep_queue[idx]
		_sweep_index += 1
		if _sweep_index >= _sweep_queue.size():
			_sweep_queue = []  # une passe complète : retour au choix normal, jamais un balayage sans fin.
		return {"kind": "sweep", "pos": entry.get("pos", ctx.get("bot_pos", Vector3.ZERO))}

	var mk = ctx.get("map_knowledge")
	if mk != null:
		var fwd := _facing_dir(ctx)
		var candidates: Array = mk.angles_near(ctx.get("bot_pos", Vector3.ZERO), fwd, ANGLE_RANGE_M, ANGLE_HALF_FOV_DEG)
		if not candidates.is_empty():
			var nearest := _nearest_by_pos(candidates, ctx.get("bot_pos", Vector3.ZERO))
			return {"kind": "angle", "pos": nearest.get("pos", Vector3.ZERO)}

	var path_points: Array = ctx.get("path_points", [])
	var bot_pos: Vector3 = ctx.get("bot_pos", Vector3.ZERO)
	var ahead := point_ahead_on_path(path_points, bot_pos, 4.0)
	return {"kind": "path_point", "pos": ahead}


func _commit_target(kind: String, pos: Vector3, ctx: Dictionary) -> void:
	_target_kind = kind
	_target_pos = pos
	_has_target = true
	var holding := bool(ctx.get("holding_angle", false))
	var rng: RandomNumberGenerator = ctx.get("rng")
	if rng != null:
		_retarget_left_s = rng.randf_range(HOLD_ANGLE_MIN_S, HOLD_ANGLE_MAX_S) if holding else rng.randf_range(RETARGET_MIN_S, RETARGET_MAX_S)
	else:
		_retarget_left_s = HOLD_ANGLE_MIN_S if holding else RETARGET_MIN_S


## Rafraîchit la file de balayage (L5, remplace BOTFIX-01) au FRONT montant de
## `goal_reached` : tous les angles K visibles depuis la position courante
## (cône complet, 180°, un but atteint se balaie dans toutes les directions,
## pas seulement dans le cap de déplacement — souvent nul à l'arrêt).
func _refill_sweep_queue(ctx: Dictionary) -> void:
	var mk = ctx.get("map_knowledge")
	if mk == null:
		_sweep_queue = []
		return
	var fwd := _facing_dir(ctx)
	_sweep_queue = mk.angles_near(ctx.get("bot_pos", Vector3.ZERO), fwd, ANGLE_RANGE_M, 180.0)
	_sweep_index = 0


func _facing_dir(ctx: Dictionary) -> Vector3:
	var move_dir: Vector3 = ctx.get("move_dir", Vector3.ZERO)
	if move_dir.length() >= 0.05:
		return move_dir
	return yaw_forward_dir(float(ctx.get("cur_yaw_deg", 0.0)))


static func _nearest_by_pos(candidates: Array, bot_pos: Vector3) -> Dictionary:
	var best: Dictionary = candidates[0]
	var best_d := bot_pos.distance_to(best.get("pos", bot_pos))
	for c in candidates:
		var entry: Dictionary = c
		var d := bot_pos.distance_to(entry.get("pos", bot_pos))
		if d < best_d:
			best_d = d
			best = entry
	return best


## Point regardé (L3) : les points au sol (coin, point de chemin) gagnent
## +LOOK_HEIGHT_M — un angle K/perchoir/l'ennemi lui-même sont déjà de vraies
## positions 3D (tête, perchoir en hauteur...), utilisés tels quels.
func _gaze_point_for(kind: String, raw_pos: Vector3) -> Vector3:
	if kind == "corner" or kind == "path_point":
		return raw_pos + Vector3(0.0, LOOK_HEIGHT_M, 0.0)
	return raw_pos


# ======================================================================
#  L2 — détection d'un coin serré sur le chemin.
# ======================================================================

## `path_points` : points de chemin à venir dans l'ordre (SANS `bot_pos`,
## voir `tick()`). Renvoie `{"found": bool, "pos": Vector3, "turn_deg": float}`
## — `pos` est le point regardé (« côté opposé du coin », au sol, +1.5 m
## ajouté par `_gaze_point_for`), PAS le sommet du coin lui-même : un point
## CORNER_LOOK_AHEAD_M après le virage, dans la direction de sortie — ce qui
## est réellement caché tant qu'on n'a pas tourné.
static func find_sharp_corner(path_points: Array, bot_pos: Vector3) -> Dictionary:
	if path_points.size() < 2:
		return {"found": false}
	var p0: Vector3 = path_points[0]
	var p1: Vector3 = path_points[1]
	if bot_pos.distance_to(p0) > CORNER_RANGE_M:
		return {"found": false}
	var in_dir := Vector3(p0.x - bot_pos.x, 0.0, p0.z - bot_pos.z)
	var out_dir := Vector3(p1.x - p0.x, 0.0, p1.z - p0.z)
	if in_dir.length() < 0.05 or out_dir.length() < 0.05:
		return {"found": false}
	var turn_deg := rad_to_deg(in_dir.normalized().angle_to(out_dir.normalized()))
	if turn_deg <= CORNER_TURN_DEG:
		return {"found": false}
	var look_pos := p0 + out_dir.normalized() * CORNER_LOOK_AHEAD_M
	return {"found": true, "pos": look_pos, "turn_deg": turn_deg}


## Point du chemin `ahead_m` mètres devant `bot_pos`, en suivant la polyligne
## `path_points` (repli L1 #5, « point du chemin 4 m devant » — toujours
## disponible, contrairement aux angles K). `bot_pos` lui-même si le chemin
## est vide ; le DERNIER point si `ahead_m` dépasse la longueur restante.
static func point_ahead_on_path(path_points: Array, bot_pos: Vector3, ahead_m: float) -> Vector3:
	if path_points.is_empty():
		return bot_pos
	var remaining := ahead_m
	var prev := bot_pos
	for p in path_points:
		var point: Vector3 = p
		var seg := prev.distance_to(point)
		if seg >= remaining:
			var t := remaining / seg if seg > 0.001 else 0.0
			return prev.lerp(point, t)
		remaining -= seg
		prev = point
	return path_points[path_points.size() - 1]


# ======================================================================
#  Géométrie de visée — mêmes formules que BotBrain._aim_towards (BOT-02),
#  reprises ici pour rester PUR (aucun accès à `player`/`Node3D`).
# ======================================================================

## `{"yaw": float, "pitch": float}` (deg) pour regarder `target_pos` depuis
## `from_pos` — pitch borné à ±89° (jamais tout droit vers le zénith/nadir,
## la caméra perdrait tout repère de lacet).
static func desired_yaw_pitch_deg(from_pos: Vector3, target_pos: Vector3) -> Dictionary:
	var to_target := target_pos - from_pos
	var yaw_deg := rad_to_deg(atan2(-to_target.x, -to_target.z))
	var flat := Vector2(to_target.x, to_target.z).length()
	var pitch_deg := rad_to_deg(clampf(atan2(to_target.y, maxf(flat, 0.001)), deg_to_rad(-89.0), deg_to_rad(89.0)))
	return {"yaw": yaw_deg, "pitch": pitch_deg}


## Direction MONDE (plane, y=0) vers laquelle `yaw_deg` fait face — inverse de
## `desired_yaw_pitch_deg` (même convention que PlayerController.rotation.y).
static func yaw_forward_dir(yaw_deg: float) -> Vector3:
	var yaw := deg_to_rad(yaw_deg)
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


# ======================================================================
#  L4 — ressort quasi critique, plafonné en vitesse ET en accélération.
# ======================================================================

## Raideur/amortissement `{"k": float, "d": float}` pour SPRING_ZETA (quasi
## critique) — réutilise `BotAim.spring_natural_freq` (BOT-02, même formule
## qu'un ressort-amortisseur du 2e ordre) plutôt que d'en réécrire une copie.
static func spring_params() -> Dictionary:
	var wn := BotAim.spring_natural_freq(SPRING_PEAK_SPEED_DEG, SPRING_ZETA)
	return {"k": wn * wn, "d": 2.0 * SPRING_ZETA * wn}


## Un pas du ressort-amortisseur, PLAFONNÉ en accélération (±MAX_ACCEL_DEG)
## PUIS en vitesse (±MAX_SPEED_DEG) — contrairement à `BotAim.spring_step`
## (calibré pour un dépassement cible SANS garantie dure), ces deux plafonds
## sont des bornes ABSOLUES quelle que soit l'amplitude du saut de cible (L4).
static func spring_step_capped(current_angle: float, current_speed: float, target_angle: float, k: float, d: float, delta: float) -> Dictionary:
	var alpha := target_angle - current_angle
	var accel := clampf(k * alpha - d * current_speed, -MAX_ACCEL_DEG, MAX_ACCEL_DEG)
	var new_speed := clampf(current_speed + accel * delta, -MAX_SPEED_DEG, MAX_SPEED_DEG)
	var new_angle := current_angle + new_speed * delta
	return {"angle": new_angle, "speed": new_speed}


# ======================================================================
#  L6 — écart regard / déplacement : marche au-delà de 70°.
# ======================================================================

## Écart (0-180°) entre le lacet du regard et le cap de déplacement — `0.0`
## à l'arrêt (`move_dir` quasi nul, aucun cap défini, jamais de marche forcée
## juste parce que le bot est immobile).
static func gaze_move_gap_deg(gaze_yaw_deg: float, move_dir: Vector3) -> float:
	if move_dir.length() < 0.05:
		return 0.0
	var heading_deg := rad_to_deg(atan2(-move_dir.x, -move_dir.z))
	return absf(wrapf(gaze_yaw_deg - heading_deg, -180.0, 180.0))


static func should_walk(gaze_yaw_deg: float, move_dir: Vector3) -> bool:
	return gaze_move_gap_deg(gaze_yaw_deg, move_dir) > WALK_GAZE_GAP_DEG
