## BotBrain.gd
## Cerveau d'un bot : perception (ligne de vue + audition des tirs récents),
## décision (combattre ou tenir l'objectif du mode) et pilotage — via
## `player.input` (scripts/player/PlayerInput.gd), EXACTEMENT les mêmes
## champs qu'un humain, plus `look_delta` (regard, réservé aux bots) — et un
## NavigationAgent3D pour le déplacement (contract-r3.md, R3-IN#2).
##
## Enfant "BotBrain" du joueur (scenes/player/player.tscn) : NO-OP pour un
## joueur humain (`player.is_bot == false`, fixé par le serveur AVANT le spawn
## — voir GameWorld._spawn_bot). Ne tourne QUE côté serveur (le seul pair qui
## simule réellement un bot). `process_physics_priority = -150`, plus bas que
## PlayerInput (-100) : les champs de `player.input` sont posés AVANT que
## PlayerInput (no-op pour un bot) et PlayerController ne s'exécutent.
##
## Va au combat via le MÊME pipeline de validation serveur qu'un humain
## (Weapon._owner_tick tourne pour ce joueur car son autorité EST le serveur,
## voir PlayerController._enter_tree) : aucun raccourci, aucune triche —
## seulement ce que le bot peut VOIR ou ENTENDRE (pas de wall-hack).
class_name BotBrain
extends Node

const REACTION := preload("res://scripts/ai/BotReaction.gd")
const TARGET_SELECT := preload("res://scripts/ai/BotTargetSelect.gd")

const SIGHT_RANGE := 45.0                  ## Portée de vue max (m).
const SIGHT_FOV := 100.0                   ## Cône de vue total (deg).
const HEAR_RADIUS := 22.0                  ## Portée d'audition d'un tir (m).
const HEAR_MEMORY := 4.0                   ## Le bot se souvient d'un bruit ce temps (s).
const AIM_TURN_RATE := 220.0               ## Vitesse de rotation max en combat (deg/s).
const REPATH_INTERVAL := 0.5               ## Recalcule le chemin toutes les 0.5 s.

var player: PlayerController
var nav_agent: NavigationAgent3D

var _difficulty: int = MatchConfig.Difficulty.VETERAN
var _target_id: int = -1
var _target_pos: Vector3 = Vector3.INF
var _tracking_time: float = 0.0
var _reaction_left: float = 0.0
var _heard_pos: Vector3 = Vector3.ZERO
var _heard_until: float = 0.0
var _strafe_dir: int = 1
var _strafe_timer: float = 2.0
var _special_move_timer: float = 3.0
var _repath_timer: float = 0.0
var _bought_this_phase: bool = false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_physics_priority = -150
	player = get_parent() as PlayerController
	if player == null or not player.is_bot:
		set_physics_process(false)
		return
	_rng.randomize()
	_difficulty = MatchConfig.bot_difficulty
	_strafe_dir = 1 if _rng.randf() < 0.5 else -1
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "BotNavAgent"
	nav_agent.path_desired_distance = 0.8
	nav_agent.target_desired_distance = 0.8
	nav_agent.avoidance_enabled = false
	# ENFANT DIRECT du joueur (Node3D), PAS de BotBrain (un simple Node) :
	# NavigationAgent3D résout la position/carte de navigation depuis son
	# parent Node3D — parenté à un Node non-3D, il ne se lie à AUCUNE
	# NavigationMap (get_navigation_map() reste invalide indéfiniment).
	# `call_deferred` : ce _ready() s'exécute PENDANT que GameWorld ajoute le
	# joueur à l'arbre (add_child(player, true) traite ses enfants, dont
	# celui-ci) — un add_child SYNCHRONE sur `player` ici échoue ("Parent node
	# is busy setting up children").
	player.add_child.call_deferred(nav_agent)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or player == null:
		return
	var hp := player.get_node_or_null("Health") as Health
	if hp and hp.is_dead:
		player.input.clear()
		_target_id = -1
		return

	var candidates := _visible_enemies()
	if candidates.is_empty():
		var heard: Variant = _hear_gunfire()
		if heard != null:
			_heard_pos = heard
			_heard_until = _now() + HEAR_MEMORY

	_tick_combat(delta, candidates)
	_tick_movement(delta)
	_tick_objective()
	_tick_ability()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# ======================================================================
#  PERCEPTION — uniquement ce que le bot peut VOIR (raycast) ou ENTENDRE
#  (tirs récents) : aucun accès direct à la position/l'état d'un ennemi hors
#  de ces deux canaux (pas de wall-hack).
# ======================================================================
func _visible_enemies() -> Array:
	var world := get_tree().get_first_node_in_group("match")
	if world == null or player.head == null:
		return []
	if float(player.get_meta("blinded_until", 0.0)) > _now():
		return []  # ébloui : ne voit rien
	var out: Array = []
	var my_team := int(player.team)
	var head_pos: Vector3 = player.head.global_position
	var fwd: Vector3 = -player.global_transform.basis.z
	for child in world.get_node(world.players_root).get_children():
		if child == player or int(child.get("team")) == my_team:
			continue
		var hp := child.get_node_or_null("Health") as Health
		if hp == null or hp.is_dead:
			continue
		var enemy_head: Node3D = child.get_node_or_null("Head")
		var target_pos: Vector3 = enemy_head.global_position if enemy_head else child.global_position
		var dist := head_pos.distance_to(target_pos)
		if dist > SIGHT_RANGE:
			continue
		var to_target := target_pos - head_pos
		if fwd.length() > 0.001 and to_target.length() > 0.001:
			if rad_to_deg(fwd.angle_to(to_target)) > SIGHT_FOV * 0.5:
				continue
		if not _has_los(head_pos, target_pos, child):
			continue
		out.append({"id": str(child.name).to_int(), "distance": dist, "pos": target_pos})
	return out

func _has_los(from: Vector3, to: Vector3, target: Node) -> bool:
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	return hit.collider == target

## Position d'un tir ENNEMI récent et proche, ou null si rien entendu (le
## bus statique Weapon.recent_gunfire n'est alimenté que côté serveur — voir
## Weapon._server_fire).
func _hear_gunfire() -> Variant:
	var now := _now()
	var my_team := int(player.team)
	var best: Variant = null
	var best_d := HEAR_RADIUS
	for shot in Weapon.recent_gunfire:
		if now - float(shot.time) > 1.0 or int(shot.team) == my_team:
			continue
		var d: float = player.global_position.distance_to(shot.pos)
		if d < best_d:
			best_d = d
			best = shot.pos
	return best

# ======================================================================
#  COMBAT — acquisition + réaction + visée (erreur qui rétrécit en suivi).
# ======================================================================
func _tick_combat(delta: float, candidates: Array) -> void:
	# Cible "collante" : tant que la cible courante reste visible, on la
	# garde (sinon le choix "plus proche" oscille entre plusieurs ennemis à
	# distance similaire, remettant sans cesse à zéro le suivi/l'erreur de
	# visée — aucun tir n'a jamais le temps de faire baisser assez de vie
	# avant que la régénération ne compense). On ne réévalue que si la cible
	# courante n'est plus dans les candidats visibles.
	var current_still_visible := false
	for c in candidates:
		if int(c.id) == _target_id:
			current_still_visible = true
			break
	var chosen_id: int = _target_id if current_still_visible else TARGET_SELECT.choose(candidates)
	if chosen_id != _target_id:
		_target_id = chosen_id
		_tracking_time = 0.0
		_reaction_left = REACTION.reaction_time(_difficulty) if chosen_id != -1 else 0.0

	if _target_id == -1:
		player.input.fire_held = false
		player.input.fire_pressed = false
		player.input.aim_held = false
		_target_pos = Vector3.INF
		return

	_tracking_time += delta
	_reaction_left = maxf(_reaction_left - delta, 0.0)

	var target_pos: Vector3 = player.global_position
	for c in candidates:
		if int(c.id) == _target_id:
			target_pos = c.pos
			break
	_target_pos = target_pos

	_aim_towards(target_pos, delta)

	var can_shoot := _reaction_left <= 0.0
	player.input.aim_held = can_shoot and _difficulty != MatchConfig.Difficulty.RECRUE
	player.input.fire_held = can_shoot
	player.input.fire_pressed = can_shoot

func _aim_towards(target_pos: Vector3, delta: float) -> void:
	var head_pos: Vector3 = player.head.global_position
	var err := REACTION.aim_error_for(_difficulty, _tracking_time)
	var aim_point := target_pos
	if err > 0.0:
		# Erreur (radians) convertie en un rayon de décalage (m) à une
		# distance de référence de 10 m — reste lisible sans dépendre de la
		# distance réelle à la cible (RAND range léger, décorrélé par axe).
		var radius := err * 10.0
		aim_point += Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * radius

	var to_target := aim_point - head_pos
	if to_target.length() < 0.01:
		return

	var desired_yaw := atan2(-to_target.x, -to_target.z)
	var flat := Vector2(to_target.x, to_target.z).length()
	var desired_pitch := clampf(atan2(to_target.y, maxf(flat, 0.001)), deg_to_rad(-89), deg_to_rad(89))
	var pitch_diff: float = desired_pitch - player.head.rotation.x

	var max_step := deg_to_rad(AIM_TURN_RATE) * delta
	var dy := clampf(wrapf(desired_yaw - player.rotation.y, -PI, PI), -max_step, max_step)
	var dp := clampf(pitch_diff, -max_step, max_step)
	# `_apply_bot_look` applique `rotate_y(-look_delta.x)` / `head.rotate_x(-look_delta.y)`
	# (même convention que la souris humaine, voir PlayerController._look) :
	# les DEUX composantes doivent donc être négées ici pour que rotation.y et
	# head.rotation.x avancent bien de +dy / +dp vers la cible.
	player.input.look_delta = Vector2(-dy, -dp)

## Tourne le CORPS (yaw seulement, pas de pitch) vers `world_dir` — utilisé
## hors combat pour que le bot regarde où il marche (sinon son cône de vue
## reste figé à l'orientation du spawn et ne détecte jamais personne, voir
## `_tick_movement`). Même limite de vitesse que la visée en combat.
func _face_direction(world_dir: Vector3, delta: float) -> void:
	if world_dir.length() < 0.05:
		return
	var desired_yaw := atan2(-world_dir.x, -world_dir.z)
	var max_step := deg_to_rad(AIM_TURN_RATE) * delta
	var dy := clampf(wrapf(desired_yaw - player.rotation.y, -PI, PI), -max_step, max_step)
	player.input.look_delta = Vector2(-dy, 0.0)

# ======================================================================
#  MOUVEMENT — navmesh vers l'objectif du mode (ou le dernier bruit entendu),
#  strafe en combat, saut/accroupi/plongeon occasionnels.
# ======================================================================
func _tick_movement(delta: float) -> void:
	# En combat, l'objectif de déplacement devient la cible engagée elle-même
	# (se rapprocher/contourner) — sinon le bot continue de naviguer vers
	# l'objectif du MODE (souvent un ennemi DIFFÉRENT côté TDM), et peut
	# s'éloigner de la cible qu'il est justement en train de canarder.
	var goal := _target_pos if (_target_id != -1 and _target_pos != Vector3.INF) else _current_goal()
	_repath_timer -= delta
	if _repath_timer <= 0.0 and nav_agent:
		_repath_timer = REPATH_INTERVAL
		nav_agent.target_position = goal

	var move := Vector2.ZERO
	var move_world_dir := Vector3.ZERO
	var nav_map: RID = nav_agent.get_navigation_map() if nav_agent else RID()
	if nav_agent and nav_map.is_valid() and NavigationServer3D.map_get_iteration_id(nav_map) != 0 \
			and not nav_agent.is_navigation_finished():
		var next_pos := nav_agent.get_next_path_position()
		var dir := next_pos - player.global_position
		dir.y = 0.0
		move_world_dir = dir
		move = _world_dir_to_local_move(dir)

	var in_combat := _target_id != -1
	if not in_combat:
		# Regarde où il marche : sans ça le cône de vue reste figé à
		# l'orientation du spawn et le bot ne détecte jamais personne.
		_face_direction(move_world_dir, delta)
	if in_combat:
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = _rng.randf_range(0.8, 1.8)
			_strafe_dir = -_strafe_dir
		move.x = clampf(move.x + float(_strafe_dir) * 0.8, -1.0, 1.0)
		# Recule un peu si la cible est très proche (évite le corps-à-corps bête).
		if _target_pos != Vector3.INF and player.global_position.distance_to(_target_pos) < 4.0:
			move.y = clampf(move.y + 0.6, -1.0, 1.0)

	player.input.move = move
	player.input.walk_held = false

	_special_move_timer -= delta
	if _special_move_timer <= 0.0:
		_special_move_timer = _rng.randf_range(3.0, 7.0)
		var roll := _rng.randf()
		player.input.jump_pressed = roll < 0.4
		player.input.jump_held = player.input.jump_pressed
		player.input.crouch_pressed = roll >= 0.4 and roll < 0.7
		player.input.dive_pressed = in_combat and roll >= 0.7
	else:
		player.input.jump_pressed = false
		player.input.jump_held = false
		player.input.crouch_pressed = false
		player.input.dive_pressed = false
	player.input.crouch_held = false

func _world_dir_to_local_move(world_dir: Vector3) -> Vector2:
	if world_dir.length() < 0.05:
		return Vector2.ZERO
	var local := player.global_transform.basis.inverse() * world_dir.normalized()
	return Vector2(local.x, local.z).normalized()

## Objectif courant : un bruit récent prime (aller voir), sinon l'objectif du
## mode de jeu (`bot_goal_for`, ajouté à chaque mode possédé par R3-IN),
## sinon on reste sur place.
func _current_goal() -> Vector3:
	if _now() < _heard_until:
		return _heard_pos
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode and mode.has_method("bot_goal_for"):
		var g: Vector3 = mode.bot_goal_for(int(player.team))
		if g != Vector3.ZERO:
			return g
	return player.global_position

# ======================================================================
#  OBJECTIF DE MODE (SnD : tenir pickup pour poser/désamorcer ; achat) et
#  capacité rare — via les MÊMES points d'entrée qu'un humain.
# ======================================================================
func _tick_objective() -> void:
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode == null:
		return
	if mode.has_method("bot_set_holding"):
		mode.bot_set_holding(str(player.name).to_int(), _target_id == -1)
	var buy_phase: bool = bool(mode.get("buy_phase")) if mode.get("buy_phase") != null else false
	if buy_phase and mode.has_method("server_try_purchase"):
		_maybe_buy()
	else:
		_bought_this_phase = false

func _maybe_buy() -> void:
	if _bought_this_phase:
		return
	_bought_this_phase = true
	var w := player.get_node_or_null("Weapon")
	if w == null:
		return
	var ids := WeaponDatabase.default_loadout_ids()
	if not ids.is_empty():
		w.buy(ids[0])

## Utilisation RARE d'une capacité (contract-r3.md : "rare ability use") — un
## simple tirage à chaque tick ; AbilityController ignore la requête si le
## mode les désactive (Duel/Duo) ou si aucune charge n'est disponible.
func _tick_ability() -> void:
	player.input.ability_pressed = ""
	if _rng.randf() >= 0.002:
		return
	var ab := player.get_node_or_null("Abilities")
	if ab == null or ab.agent == null or ab.agent.abilities.is_empty():
		return
	var pick: Ability = ab.agent.abilities[_rng.randi() % ab.agent.abilities.size()]
	player.input.ability_pressed = pick.slot
