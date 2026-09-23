## PlayerController.gd
## Contrôleur joueur FPS — CharacterBody3D.
## Contient l'état physique partagé + les helpers de mouvement (accel/friction
## façon Source, gravité, saut bufferisé/coyote, gestion crouch). La LOGIQUE
## de chaque mode de déplacement vit dans les états (scripts/player/states).
## Compatible multijoueur : seul le pair propriétaire simule les entrées.
class_name PlayerController
extends CharacterBody3D

## Ids >= ce seuil désignent un BOT (joueur simulé par le SERVEUR, jamais un
## pair réel) — contract-r3.md, "Cross-slice interfaces" : "ids >= 9001,
## authority 1". Utilisé par GameWorld (attribution des ids de bot) et
## `_enter_tree` (résolution de l'autorité réseau, voir plus bas).
const BOT_ID_START := 9001

@export var config: MovementConfig

# --- Références de scène ---
@onready var head: Node3D = %Head
@onready var camera: Camera3D = %Camera3D
@onready var collision: CollisionShape3D = %Collision
@onready var ceiling_check: RayCast3D = %CeilingCheck
@onready var state_machine: PlayerStateMachine = %StateMachine
@onready var stun_stars: Node3D = get_node_or_null("%StunStars")
## Point d'entrée UNIQUE des entrées de gameplay (humain local OU bot — voir
## scripts/player/PlayerInput.gd). Tout le code de gameplay lit `player.input`,
## jamais le singleton Input directement (exception : le regard humain brut,
## qui reste dans `_unhandled_input`/`_gamepad_look`, cf. contract-r3.md).
@onready var input: PlayerInput = %Input

# --- État partagé entre les states ---
var wish_dir: Vector3 = Vector3.ZERO      ## Direction voulue (monde), normalisée.
var input_vector: Vector2 = Vector2.ZERO  ## Entrée brute (x = strafe, y = avant/arrière).
var is_crouching: bool = false
var current_height: float = 0.0
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false
var slide_jumped: bool = false  ## Vrai juste après un slide-jump (pour le slide-hop).
var _air_peak_y: float = 0.0    ## Altitude max atteinte en l'air (pour la hauteur de chute).
var _roll_buffer_timer: float = 0.0  ## Roulade d'atterrissage mémorisée (anti-stun).

## Une roulade d'atterrissage a-t-elle été déclenchée au bon timing ?
func land_roll_buffered() -> bool:
	return _roll_buffer_timer > 0.0

func consume_roll_buffer() -> void:
	_roll_buffer_timer = 0.0

@export var fall_limit: float = -40.0   ## Sous cette altitude => respawn.
var spawn_point: Vector3 = Vector3(0, 2, 0)
var team: int = 0                        ## Équipe assignée par le serveur.
## Joueur simulé par le SERVEUR (bot), jamais par un pair réel — répliqué au
## spawn (spawn only, comme agent_index/team) par GameWorld._spawn_player.
## Voir `is_local_human()` : un bot a l'autorité réseau du SERVEUR (peer 1,
## comme l'hôte lui-même quand il joue) mais n'est jamais "l'humain à ce
## clavier" — c'est cette distinction qui compte pour la caméra/la capture
## souris/le groupe local_player/le HUD, PAS l'autorité réseau seule.
var is_bot: bool = false
## Agent (classe) choisi, assigné par le serveur au spawn (GameWorld._spawn_player)
## et répliqué une seule fois (SceneReplicationConfig, spawn only). -1 = non
## assigné (ex. entraînement hors-ligne sans passer par GameWorld) : dans ce
## cas AbilityController se replie sur AgentDatabase.selected().
var agent_index: int = -1

## Mouvement figé par le SERVEUR (phase BUY/PREROUND d'un mode à manches —
## voir RoundMode/GameWorld.set_all_locked). Honoré par _physics_process
## (même traitement que la mort : gravité seule, pas de state machine).
var movement_locked: bool = false

## -- Animation (CharacterAnimator, scenes/player/player.tscn) --------------
## Les pairs DISTANTS ne font PAS tourner la state machine (scripts/player/
## states/*) : on réplique donc l'ÉTAT D'ANIMATION lui-même, posé par
## l'AUTORITÉ (propriétaire humain, ou SERVEUR pour un bot) CHAQUE tick
## physique, plutôt que le nom de state brut — `CharacterAnimator.
## locomotion_for()` (logique pure) fait le même calcul ici et dans les tests
## (tests/player/test_character_animator.gd). `anim_state` empaquette la
## locomotion (bas du corps) + un bit "en rechargement" (haut du corps, voir
## `_on_weapon_reload_started` : `Weapon.reload_started` n'est émis QUE là où
## la prédiction tourne, càd exactement le pair où `is_multiplayer_authority()`
## est vrai — même pair que celui qui calcule `anim_state` ici, contrairement
## à un simple corps distant qui ne verrait jamais ce signal).
## Répliqué TOUJOURS (SceneReplicationConfig, player.tscn) — pas "spawn only" :
## contrairement à agent_index/team, ça change en permanence.
var anim_state: int = 0
## Pitch de la tête (radians, copie de `head.rotation.x`) — utilisé par
## CharacterAnimator pour mélanger Pistol_Aim_Down/Neutral/Up (voir
## `CharacterAnimator.aim_blend_t`). Répliqué TOUJOURS, comme `anim_state`.
var aim_pitch: float = 0.0
var _jump_start_t: float = 0.0
var _jump_land_t: float = 0.0
var _reload_t: float = 0.0
var _prev_state_name: String = ""

# Recul (vrai recoil : déplace la visée, puis récupère).
var _recoil_target: Vector2 = Vector2.ZERO   # x = pitch (haut), y = yaw
var _recoil_applied: Vector2 = Vector2.ZERO
var _recoil_recovery: float = 7.0

## Ajoute un kick de recul (radians). Appelé par l'arme à chaque tir.
func add_recoil(pitch: float, yaw: float, recovery: float) -> void:
	_recoil_target += Vector2(pitch, yaw)
	_recoil_recovery = recovery

func _update_recoil(delta: float) -> void:
	# Récupération : la cible revient vers 0, ce qui ramène la visée.
	_recoil_target = _recoil_target.lerp(Vector2.ZERO, clampf(_recoil_recovery * delta, 0.0, 1.0))
	var new_applied := _recoil_applied.lerp(_recoil_target, clampf(22.0 * delta, 0.0, 1.0))
	var d := new_applied - _recoil_applied
	head.rotation.x = clamp(head.rotation.x + d.x, deg_to_rad(-89), deg_to_rad(89))
	rotate_y(d.y)
	_recoil_applied = new_applied

## L'autorité multijoueur DOIT être réglée dans _enter_tree (pas _ready), sinon le
## MultiplayerSynchronizer ne peut pas traiter le spawn (erreur "no network ID").
## Nom du nœud = id du "propriétaire" (identique sur tous les pairs) : pour un
## HUMAIN, c'est son vrai id de pair réseau. Pour un BOT (id >= BOT_ID_START),
## il n'existe AUCUN pair réel portant cet id — le bot est simulé par le
## SERVEUR, dont l'autorité (peer 1) est donc utilisée à la place (contract-r3.md :
## "Bots are server-owned players... authority 1"). Le mouvement/caméra
## appartient à cette autorité ; les composants de gameplay (Health, Weapon,
## Abilities) sont TOUJOURS forcés sur le SERVEUR (peer 1), bot ou humain —
## voir "Global rules" du contrat Phase 0.
func _enter_tree() -> void:
	var owner_id := str(name).to_int()
	var authority_id := 1 if owner_id >= BOT_ID_START else owner_id
	if authority_id > 0:
		set_multiplayer_authority(authority_id)  # récursif (corps, synchronizer...)
	for gameplay_node in ["Health", "Weapon", "Abilities"]:
		var n := get_node_or_null(gameplay_node)
		if n:
			n.set_multiplayer_authority(1)

## "L'humain à CE clavier" — distinct de `is_multiplayer_authority()`, qui
## est vraie aussi bien pour l'hôte-joueur QUE pour chaque bot sur le
## SERVEUR (les deux partagent l'autorité peer 1, voir `_enter_tree`).
## Caméra active, capture souris, groupe "local_player", ViewModel,
## PlayerCamera (effets), HUD : tout ce qui n'a de sens que pour l'humain
## devant l'écran doit utiliser CETTE fonction, jamais `is_multiplayer_authority()`
## seule (contract-r3.md, "Cross-slice interfaces").
func is_local_human() -> bool:
	return is_multiplayer_authority() and not is_bot

func _ready() -> void:
	if config == null:
		config = MovementConfig.new()
		push_warning("Aucun MovementConfig assigné — valeurs par défaut utilisées.")
	current_height = config.stand_height
	_air_peak_y = global_position.y
	spawn_point = global_position  # point de respawn par défaut = position de départ

	# Réglages sol pour un mouvement fluide sur les pentes (slide qui glisse,
	# pas de blocage en haut de pente, vitesse conservée aux ruptures de pente).
	floor_stop_on_slope = false
	floor_constant_speed = true
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(52)

	state_machine.setup(self)

	# Look cartoon (matériau encre + masquage du corps local) : géré par
	# PlayerLook.gd (R-A), enfant "Look" de cette scène — plus ici.

	# En multijoueur, seul l'HUMAIN LOCAL pilote sa caméra + capture la souris
	# (un bot partage l'autorité serveur mais n'est "personne devant l'écran").
	var mine := is_local_human()
	camera.current = mine
	if mine:
		add_to_group("local_player")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Rechargement -> bit RELOADING_FLAG de `anim_state` (voir docstring
	# `anim_state` : `reload_started` n'est émis QUE là où la prédiction
	# tourne, càd exactement ce pair quand `is_multiplayer_authority()` est
	# vrai — jamais sur un corps distant, d'où la nécessité de répliquer le
	# résultat plutôt que le signal lui-même).
	var w := get_node_or_null("Weapon") as Weapon
	if w:
		w.reload_started.connect(_on_weapon_reload_started)

func _on_weapon_reload_started(cfg: WeaponConfig) -> void:
	_reload_t = cfg.reload_time if cfg else 1.8

func _unhandled_input(event: InputEvent) -> void:
	if not is_local_human():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative)
	state_machine.handle_input(event)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if global_position.y < fall_limit:
		respawn()
		return
	# Mort OU mouvement verrouillé par le serveur (phase BUY/PREROUND d'un mode
	# à manches) : on fige le joueur (pas d'input/action) mais la gravité
	# continue de s'appliquer (pas de flottement en l'air).
	var hp := get_node_or_null("Health") as Health
	if (hp and hp.is_dead) or movement_locked:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= config.gravity * delta
		move_and_slide()
		_update_anim_state(delta, hp)
		return
	if is_bot:
		_apply_bot_look()  # AVANT _read_input : wish_dir utilise l'orientation à jour.
	else:
		_gamepad_look(delta)
	_read_input()
	_update_recoil(delta)
	_update_timers(delta)
	state_machine.physics_update(delta)
	_update_crouch_height(delta)
	move_and_slide()
	_check_fall_stun()
	_was_on_floor = is_on_floor()
	_update_anim_state(delta, hp)

## Calcule `anim_state`/`aim_pitch` (répliqués — voir leur docstring) à partir
## de l'état de la state machine LOCALE. Appelé sur les DEUX branches de
## _physics_process (mort/verrouillé inclus, pour que `anim_state` reflète
## bien DEAD même figé) — jamais côté pair distant (tout `_physics_process`
## est déjà gardé par `is_multiplayer_authority()`).
func _update_anim_state(delta: float, hp: Health) -> void:
	var sname := state_machine.current_name if state_machine else ""
	if sname == "Air" and _prev_state_name != "Air" and velocity.y > 0.5:
		_jump_start_t = CharacterAnimator.JUMP_START_DUR
	if _prev_state_name == "Air" and sname != "Air" and sname != "Roll":
		_jump_land_t = CharacterAnimator.JUMP_LAND_DUR
	_jump_start_t = maxf(_jump_start_t - delta, 0.0)
	_jump_land_t = maxf(_jump_land_t - delta, 0.0)
	_reload_t = maxf(_reload_t - delta, 0.0)

	var dead := hp != null and hp.is_dead
	var interacting := input != null and input.pickup_held and not dead
	var loco := CharacterAnimator.locomotion_for(sname, horizontal_speed(), interacting, dead,
		_jump_start_t, _jump_land_t)
	anim_state = CharacterAnimator.pack_anim_state(loco, _reload_t > 0.0)
	aim_pitch = head.rotation.x
	_prev_state_name = sname

## Applique le regard d'un BOT (BotBrain écrit `input.look_delta`, en radians,
## AVANT ce tick — voir process_physics_priority sur PlayerInput/BotBrain).
## Même formule que `_look()` (mouse look humain), sans multiplicateur de
## sensibilité : BotBrain fournit déjà un delta en radians borné par tick.
func _apply_bot_look() -> void:
	var d: Vector2 = input.look_delta
	if d == Vector2.ZERO:
		return
	rotate_y(-d.x)
	head.rotate_x(-d.y)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

## Visée à la manette (stick droit). Gelée si un menu est ouvert. HUMAIN
## LOCAL uniquement (jamais un bot : lit le périphérique réel de CETTE machine).
func _gamepad_look(delta: float) -> void:
	if not is_local_human():
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	var dz := 0.15
	if absf(rx) < dz: rx = 0.0
	if absf(ry) < dz: ry = 0.0
	if rx == 0.0 and ry == 0.0:
		return
	if Settings.invert_y:
		ry = -ry
	rotate_y(-rx * Settings.gamepad_sensitivity * delta)
	head.rotate_x(-ry * Settings.gamepad_sensitivity * delta)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

## Suit la hauteur de chute et déclenche un stun à l'atterrissage si trop haut.
## Rouler (Dive/Roll) absorbe la chute : pas de stun.
func _check_fall_stun() -> void:
	if is_on_floor():
		if not _was_on_floor:
			# Atterrissage. La roulade (buffer "dive" au bon timing) est PRIORITAIRE
			# sur le stun : on doit la tester ici car la détection du sol par
			# move_and_slide arrive avant que l'état Air n'ait sa frame.
			if land_roll_buffered():
				consume_roll_buffer()
				if state_machine.current_name != "Roll":
					state_machine.transition_to("Roll")
			else:
				_maybe_stun(_air_peak_y - global_position.y)
		_air_peak_y = global_position.y
	else:
		_air_peak_y = max(_air_peak_y, global_position.y)

func _maybe_stun(fall_height: float) -> void:
	if not config.stun_enabled or fall_height < config.fall_min_height:
		return
	var s := state_machine.current_name
	if s == "Roll" or s == "Dive" or s == "Stun":
		return  # la roulade absorbe l'impact
	var t: float = remap(fall_height, config.fall_min_height, config.fall_max_height, config.stun_min_time, config.stun_max_time)
	t = clampf(t, config.stun_min_time, config.stun_max_time)
	state_machine.transition_to("Stun", {"duration": t})

# ------------------------------------------------------------------
#  ENTRÉES
# ------------------------------------------------------------------
func _read_input() -> void:
	# `input` (PlayerInput) porte déjà le gating "souris relâchée => tout à
	# zéro" pour un humain (voir PlayerInput.gather_from_devices) ; un bot n'a
	# pas ce concept, ses champs viennent de BotBrain.
	input_vector = input.move
	# Direction voulue relative à l'orientation du joueur (yaw sur le body).
	var basis_dir := (global_transform.basis * Vector3(input_vector.x, 0.0, input_vector.y))
	wish_dir = Vector3(basis_dir.x, 0.0, basis_dir.z).normalized()
	if input.jump_pressed:
		_jump_buffer_timer = config.jump_buffer_time
	# Appuyer sur "dive" EN L'AIR mémorise une roulade d'atterrissage (anti-stun).
	# Plus on tombe vite (chute haute), plus la fenêtre est large => plus facile.
	if input.dive_pressed and not is_on_floor():
		var fall_speed: float = max(-velocity.y, 0.0)
		var f: float = clampf(fall_speed / config.land_roll_fast_speed, 0.0, 1.0)
		_roll_buffer_timer = lerpf(config.land_roll_window, config.land_roll_window_max, f)

func _look(relative: Vector2) -> void:
	rotate_y(-relative.x * Settings.mouse_sensitivity)
	head.rotate_x(-relative.y * Settings.mouse_sensitivity)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

## Replace le joueur au point de spawn (chute hors map, etc.).
func respawn() -> void:
	velocity = Vector3.ZERO
	global_position = spawn_point
	if state_machine:
		state_machine.transition_to("Idle")

## Téléportation effective (respawn) — factorisée pour être appelée SOIT par
## `net_respawn` (RPC, joueur distant), SOIT directement par `server_respawn`
## (joueur simulé ICI : hôte ou bot — voir plus bas). Ne valide RIEN elle-même :
## les deux appelants ont déjà établi la confiance (RPC vérifiée / appel serveur direct).
func _do_respawn(pos: Vector3) -> void:
	spawn_point = pos
	velocity = Vector3.ZERO
	global_position = pos
	if state_machine:
		state_machine.transition_to("Idle")

## Respawn réseau : le SERVEUR appelle ceci sur le PROPRIÉTAIRE DISTANT
## (rpc_id) pour le téléporter — nécessaire car le mouvement est
## client-autoritaire (le serveur ne peut pas changer directement la position
## d'un autre pair). Le nœud racine a l'autorité du PROPRIÉTAIRE (pas du
## serveur) : "any_peer" est donc nécessaire pour que le serveur puisse
## émettre cet appel, mais on doit alors vérifier nous-même l'expéditeur
## (sinon un client pourrait se téléporter lui-même).
## RÉSERVÉ aux propriétaires DISTANTS (id de pair réel) : un BOT n'en a
## aucun — `rpc_id(bot_id, ...)` ne délivrerait à personne — voir
## `server_respawn`, que GameWorld appelle à la place pour l'hôte et les bots
## (contract-r3.md : "Server-side request wrappers must use the player's
## owner id when the server simulates that player itself... never blindly
## multiplayer.get_unique_id()" — même motif, dans l'autre sens : ici c'est
## un PUSH serveur, pas une requête, mais la même distinction bot/pair réel s'applique).
@rpc("any_peer", "call_local", "reliable")
func net_respawn(pos: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_do_respawn(pos)

## Respawn d'un joueur simulé ICI (hôte-joueur ou BOT, qui partagent
## l'autorité serveur — voir `is_local_human`) : appel DIRECT, sans RPC (pas
## de pair réel à qui l'envoyer pour un bot). Appelé par GameWorld.
func server_respawn(pos: Vector3) -> void:
	if not multiplayer.is_server() or not is_multiplayer_authority():
		return
	_do_respawn(pos)

## Effectif — factorisé, voir `_do_respawn` / `server_respawn`.
func _do_set_locked(locked: bool) -> void:
	movement_locked = locked

## Verrouille/déverrouille le mouvement (RoundMode : phase BUY/PREROUND d'un
## mode à manches, via GameWorld.set_all_locked). Même motif que `net_respawn` :
## RÉSERVÉ aux propriétaires DISTANTS ; voir `server_set_locked` pour l'hôte/les bots.
@rpc("any_peer", "call_local", "reliable")
func net_set_locked(locked: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_do_set_locked(locked)

## Verrouillage d'un joueur simulé ICI (hôte-joueur ou bot) : appel DIRECT.
func server_set_locked(locked: bool) -> void:
	if not multiplayer.is_server() or not is_multiplayer_authority():
		return
	_do_set_locked(locked)

# ------------------------------------------------------------------
#  HELPERS DE MOUVEMENT (utilisés par les states)
# ------------------------------------------------------------------
## Accélération style Source : ne pousse que la composante manquante vers wish_speed.
## Donne l'air-strafe fluide quand accel/friction sont bas en l'air.
func accelerate(dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	var current_speed := velocity.dot(dir)
	var add_speed := wish_speed - current_speed
	if add_speed <= 0.0:
		return
	var accel_speed: float = min(accel * wish_speed * delta, add_speed)
	velocity.x += accel_speed * dir.x
	velocity.z += accel_speed * dir.z

## Mouvement SOL façon CoD : réponse sèche et instantanée (move_toward linéaire).
## `target_speed` = vitesse visée ; `accel`/`friction` en m/s^2.
func ground_move(target_speed: float, accel: float, friction: float, delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir != Vector3.ZERO:
		hv = hv.move_toward(wish_dir * target_speed, accel * delta)
	else:
		hv = hv.move_toward(Vector3.ZERO, friction * delta)
	velocity.x = hv.x
	velocity.z = hv.z

## Contrôle directionnel DIRECT en l'air : freine / réoriente vers wish_dir.
## Toute AUGMENTATION de vitesse est ramenée à la vitesse d'entrée → ce contrôle
## ne crée pas de vitesse (il freine et fait tourner la trajectoire), le gain
## restant réservé à l'air-strafe (accelerate).
func air_control_move(strength: float, delta: float) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var before := hv.length()
	hv += wish_dir * strength * delta
	if hv.length() > before:
		hv = hv.normalized() * before
	velocity.x = hv.x
	velocity.z = hv.z

## Redirige le vecteur vitesse horizontal vers `dir` SANS changer sa norme.
## C'est ce qui donne le côté fluide / tap-strafe : on tourne sa course en
## conservant toute la vitesse. `rate` = vitesse de rotation (rad/s approx).
func redirect_velocity(dir: Vector3, rate: float, delta: float) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horiz.length()
	if speed < 0.5 or dir == Vector3.ZERO:
		return
	var cur_dir := horiz / speed
	var new_dir := cur_dir.slerp(dir.normalized(), clamp(rate * delta, 0.0, 1.0)).normalized()
	velocity.x = new_dir.x * speed
	velocity.z = new_dir.z * speed

## Friction horizontale (décélération exponentielle stable).
func apply_friction(friction: float, delta: float) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horiz.length()
	if speed < 0.01:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var drop := speed * friction * delta
	var new_speed: float = max(speed - drop, 0.0)
	var factor := new_speed / speed
	velocity.x *= factor
	velocity.z *= factor

func apply_gravity(delta: float) -> void:
	var g := config.gravity
	if velocity.y < 0.0:
		g *= config.fall_gravity_mult
	velocity.y -= g * delta

func horizontal_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)

func horizontal_speed() -> float:
	return horizontal_velocity().length()

## Le joueur peut-il sauter ? (au sol OU dans la fenêtre coyote)
func can_jump() -> bool:
	return is_on_floor() or _coyote_timer > 0.0

## Y a-t-il un saut bufferisé en attente ?
func jump_buffered() -> bool:
	return _jump_buffer_timer > 0.0

## Exécute le saut. Le momentum horizontal est TOUJOURS conservé (style Apex).
func do_jump() -> void:
	velocity.y = config.jump_velocity
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0

## Y a-t-il un obstacle au-dessus empêchant de se relever ?
func is_blocked_above() -> bool:
	return ceiling_check.is_colliding()

func set_crouching(value: bool) -> void:
	is_crouching = value

func _update_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = config.coyote_time
	else:
		_coyote_timer = max(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = max(_jump_buffer_timer - delta, 0.0)
	_roll_buffer_timer = max(_roll_buffer_timer - delta, 0.0)

func _update_crouch_height(delta: float) -> void:
	var target := config.crouch_height if is_crouching else config.stand_height
	current_height = lerp(current_height, target, config.crouch_lerp_speed * delta)
	var shape := collision.shape
	if shape is CapsuleShape3D:
		shape.height = current_height
		collision.position.y = current_height * 0.5
	# La tête suit la hauteur (légèrement sous le sommet).
	head.position.y = current_height - 0.2
