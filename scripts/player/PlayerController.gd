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

## GF-02 : au-delà de cette distance ENTRE DEUX INSTANTANÉS REÇUS (m), un
## instantané réseau n'est plus un mouvement organique mais une téléportation
## (respawn) — voir `_apply_remote_interpolation`, qui vide alors le tampon
## plutôt que d'interpoler un glissement fantôme entre l'ancienne et la
## nouvelle position, comme `reset_physics_interpolation()` le fait déjà côté
## autorité (`respawn`/`_do_respawn`) pour la même raison. Seuil volontairement
## généreux : deux instantanés consécutifs REÇUS peuvent être plusieurs ticks
## physiques (60 Hz) apart si le réseau accuse un bref à-coup (le
## MultiplayerSynchronizer ne rattrape alors que la DERNIÈRE valeur, sans
## renvoyer les valeurs intermédiaires) — à la vitesse max du jeu (~12 m/s en
## slide), il faudrait plus de 500 ms d'à-coup pour dépasser ce seuil, très
## au-delà de la gigue réseau normale visée par ce ticket (20 % d'un tick).
const REMOTE_TELEPORT_DISTANCE := 6.0

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
## Répliqué TOUJOURS (SceneReplicationConfig, player.tscn — GF-04) : modifié
## SEULEMENT par le state_machine LOCAL (Crouch.gd), donc uniquement chez
## l'AUTORITÉ (propriétaire humain ou serveur pour un bot). Les autres pairs
## (dont le serveur pour un joueur humain distant) le reçoivent en lecture
## seule.
var is_crouching: bool = false
## Hauteur COURANTE (m) de la capsule/tête — lerp vers stand_height/
## crouch_height, voir `_update_crouch_height`. Répliqué TOUJOURS, comme
## `is_crouching` : c'est CETTE valeur, une fois appliquée à la capsule sur
## TOUT pair (`_apply_body_height`), que le serveur raycaste pour résoudre les
## tirs (Weapon._resolve_ray) — d'où le seuil de headshot RELATIF de
## WeaponMath.is_headshot (jamais 1.4 m fixe, cf. WeaponMath.HEAD_HEIGHT_RATIO).
var current_height: float = 0.0
## Décalage vertical LOCAL (m) appliqué à `head.position.y` en plus de
## `current_height` — lisse visuellement le saut de hauteur brut causé par un
## step-up/step-down (MV-01, voir StairStep + `_apply_step_smoothing`) sur
## ~`config.stair_step_smooth_time` secondes. JAMAIS répliqué (purement
## cosmétique, propre à l'instance qui simule réellement le pas — voir
## `_apply_step_smoothing`, appelée uniquement côté AUTORITÉ) : un pair distant
## qui ne fait qu'appliquer une hauteur reçue (`_apply_body_height` seule)
## garde ce champ à 0.0 en permanence, ce qui est correct (rien à lisser pour
## une position déjà interpolée par le réseau).
var _head_step_offset: float = 0.0
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

## -- Interpolation réseau des pairs distants (GF-02, RemoteInterpolator.gd) --
## `net_position`/`net_rotation_y`/`net_tick` remplacent l'ancienne réplication
## BRUTE de `.:position`/`.:rotation` (SceneReplicationConfig, player.tscn) :
## on réplique désormais un INSTANTANÉ horodaté par l'AUTORITÉ (posé chaque
## tick physique — voir `_publish_net_snapshot`), pour que chaque pair
## NON-AUTORITÉ le fasse passer par un tampon d'interpolation à délai fixe
## (RemoteInterpolator) plutôt que de recopier directement la dernière valeur
## reçue, source des saccades des pairs distants constatées (docs/research/
## 01_game_feel.md §2.1 point 2 / §4.2). `position`/`rotation` restent les
## propriétés RÉELLES du CharacterBody3D (lues par Weapon._resolve_ray côté
## serveur, la caméra, etc.) : côté AUTORITÉ elles viennent de la simulation
## (move_and_slide, comme avant) ; côté NON-AUTORITÉ elles sont désormais
## ÉCRITES par `_apply_remote_interpolation`, jamais posées directement par le
## MultiplayerSynchronizer.
var net_position: Vector3 = Vector3.ZERO
## Seul le LACET (yaw) du corps est répliqué : le corps ne tangue/ne roule
## jamais (voir `_look`/`_apply_bot_look`/`_update_recoil`, qui ne touchent
## que `head.rotation.x` et `rotate_y`) — inutile de répliquer une rotation
## 3D complète pour ne transmettre que des zéros sur deux axes.
var net_rotation_y: float = 0.0
## Tick physique de l'AUTORITÉ au moment de l'instantané ci-dessus
## (`Engine.get_physics_frames()`, propre à CHAQUE pair — seule la DIFFÉRENCE
## entre deux valeurs reçues du MÊME émetteur compte pour l'espacement des
## instantanés, jamais sa valeur absolue, qui n'a aucun sens comparée entre
## deux pairs différents). Convertie en horodatage `t` (secondes) pour
## `RemoteInterpolator.push_snapshot` — voir `_apply_remote_interpolation`.
var net_tick: int = 0
## Tampon d'interpolation — un par instance, jamais partagé (RefCounted, pas
## d'état global). Réellement CONSOMMÉ uniquement côté NON-AUTORITÉ (voir
## `_apply_remote_interpolation`) ; un bot/hôte (autorité) le construit sans
## jamais s'en servir (coût négligeable, un seul RefCounted).
var _remote_interp := RemoteInterpolator.new()
## Horloge locale de rendu (secondes, même base que les `t` bufferisés dans
## `_remote_interp`) — ancrée sur le PREMIER instantané reçu (spawn ou
## reconnexion) puis avancée de `delta` à chaque tick, plutôt que recalée sur
## l'instant d'arrivée réseau du dernier paquet : sinon le rendu avancerait
## par à-coups, calé sur la cadence d'arrivée plutôt que lissé entre deux
## instantanés (voir RemoteInterpolator.gd, section "Principe").
var _remote_clock: float = 0.0
var _remote_clock_started: bool = false
var _last_net_tick: int = -1

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
	# Chaque instance DOIT posséder sa PROPRE CapsuleShape3D (BUG-22,
	# docs/audit/bugs.md) : le CapsuleShape3D du .tscn est un sous-resource
	# PARTAGÉ par défaut entre toutes les instances de la scène. Or
	# `_apply_body_height` MUTE `shape.height` directement — sans duplication,
	# UN SEUL joueur accroupi rétrécissait donc la capsule de TOUS les autres
	# joueurs, côté serveur (bots/hôte, autorité) comme côté client (corps
	# distants répliqués, cf. la branche non-autorité de `_physics_process`
	# qui appelle aussi `_apply_body_height`). On duplique explicitement ici
	# plutôt que de compter sur `resource_local_to_scene` seul sur le
	# sous-resource : ce indicateur est fragile à un futur ré-enregistrement
	# de la scène depuis l'éditeur, alors que cette duplication est garantie
	# par le code, pour CHAQUE instance, quoi qu'il arrive au fichier .tscn.
	if collision.shape:
		collision.shape = collision.shape.duplicate()
	current_height = config.stand_height
	_air_peak_y = global_position.y
	spawn_point = global_position  # point de respawn par défaut = position de départ
	# Place initiale : sans ça, l'interpolation physique (GF-03,
	# project.godot > physics/common/physics_interpolation) lisserait un
	# "vol" fantôme depuis l'origine (0,0,0) — ou depuis la position du
	# tick précédent d'un nœud réutilisé (pool) — jusqu'ici, sur le premier
	# tick (docs Godot "Call reset_physics_interpolation() when teleporting").
	reset_physics_interpolation()

	if not is_multiplayer_authority():
		# Amorce le tampon d'interpolation (GF-02) avec l'instantané de spawn
		# (net_position/net_rotation_y/net_tick, répliqués "spawn" — voir
		# SceneReplicationConfig de player.tscn) : sans ça, ce pair distant
		# resterait à l'origine (valeurs par défaut de ces variables) jusqu'au
		# premier instantané "always" reçu APRÈS le spawn, au lieu d'apparaître
		# directement à sa vraie position.
		var spawn_t := float(net_tick) / _remote_interp.tick_rate
		_remote_interp.push_snapshot(spawn_t, net_position, Vector3(0.0, net_rotation_y, 0.0))
		_remote_clock = spawn_t
		_remote_clock_started = true
		_last_net_tick = net_tick
		position = net_position
		rotation.y = net_rotation_y

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
		# Trauma de dégât reçu (GF-29/GF-08, CameraShake.TRAUMA_DAMAGE_TAKEN =
		# 0.3) — SEUL l'humain local secoue sa propre caméra à ses propres
		# dégâts (même garde que ci-dessus). `Health.hit_reaction` (GF-10) est
		# le bon signal : émis PAR CE Health (un par joueur, jamais celui d'un
		# autre) à CHAQUE dégât confirmé, contrairement à `damaged` (serveur
		# uniquement) ou `health_changed` (se déclenche aussi sur la régen) —
		# même patron de câblage que PlayerLook.gd/CharacterAnimator.gd
		# (flash de hit / recul additif), qui y sont déjà connectés SANS ce
		# filtre (leur effet est visible par TOUS les pairs, pas seulement
		# l'écran local).
		var hp := get_node_or_null("Health") as Health
		if hp:
			hp.hit_reaction.connect(_on_local_hit_reaction)

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

## Trauma de dégât reçu (GF-29/GF-08) — câblé uniquement pour l'humain LOCAL
## (voir `_ready`, bloc `if mine:`) : ce Health n'émet `hit_reaction` QUE pour
## SES PROPRES dégâts (un Health par joueur), inutile de revérifier l'identité
## ici. `_headshot` ignoré : contrairement au flash de PlayerLook.gd, la
## trauma caméra GF-08 ne distingue pas le headshot (`add_damage_trauma` est
## un montant fixe, voir CameraShake.TRAUMA_DAMAGE_TAKEN). `camera` reste typé
## `Camera3D` (voir plus haut) : cast requis pour atteindre `PlayerCamera`.
func _on_local_hit_reaction(_headshot: bool) -> void:
	var cam := camera as PlayerCamera
	if cam:
		cam.add_damage_trauma()

func _unhandled_input(event: InputEvent) -> void:
	if not is_local_human():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative)
	state_machine.handle_input(event)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		# `is_crouching`/`current_height` sont répliquées (always,
		# SceneReplicationConfig de player.tscn) mais un MultiplayerSynchronizer
		# ne fait que POSER la variable — il ne rejoue pas `_update_crouch_height`.
		# Sans ça, la capsule d'un joueur DISTANT resterait toujours debout ici
		# (bug GF-04 : « la capsule serveur d'un humain accroupi reste debout »)
		# et le SERVEUR raycasterait contre une hitbox fausse. On applique donc
		# la valeur reçue à la capsule/tête sur TOUT pair non-autorité — y
		# compris le serveur, qui est non-autorité pour un joueur humain distant
		# (bots/hôte partagent l'autorité serveur : voir `_enter_tree` et
		# `is_local_human`, ils passent par la branche autorité ci-dessous).
		_apply_body_height()
		# GF-02 : position/rotation VISIBLES de ce pair distant, retardées et
		# lissées par le tampon d'interpolation — voir docstring de
		# `net_position` et `_apply_remote_interpolation`.
		_apply_remote_interpolation(delta)
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
		_publish_net_snapshot()
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
	# Step-up (MV-01) : AVANT move_and_slide(), tant que la vraie vélocité
	# horizontale de ce tick est encore intacte — voir StairStep.try_step_up.
	var radius := _capsule_radius()
	var step_dy := StairStep.try_step_up(self, horizontal_velocity() * delta, config.max_step_up, radius)
	move_and_slide()
	# Step-down : APRÈS move_and_slide(), une fois qu'on sait si ce tick a
	# fait perdre le contact au sol (bord d'une marche descendante) — voir
	# StairStep.try_step_down. `_was_on_floor` porte encore la valeur du DÉBUT
	# de ce tick (mise à jour plus bas), exactement le "was_grounded" attendu.
	step_dy += StairStep.try_step_down(self, _was_on_floor, config.max_step_down, radius)
	_apply_step_smoothing(step_dy, delta)
	_check_fall_stun()
	_was_on_floor = is_on_floor()
	_update_anim_state(delta, hp)
	_publish_net_snapshot()

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
	var interacting := _compute_interacting(dead)
	# GF-27, hystérésis Jog/Sprint (`CharacterAnimator.sprint_or_jog`) : la
	# locomotion PRÉCÉDENTE se relit dans `anim_state`, déjà calculé au tick
	# d'avant — AVANT de l'écraser juste en dessous.
	var previous_locomotion := CharacterAnimator.unpack_locomotion(anim_state)
	var loco := CharacterAnimator.locomotion_for(sname, horizontal_speed(), interacting, dead,
		_jump_start_t, _jump_land_t, previous_locomotion)
	anim_state = CharacterAnimator.pack_anim_state(loco, _reload_t > 0.0)
	aim_pitch = head.rotation.x
	_prev_state_name = sname

## Sentinelle de `bomb_state` pour `is_really_interacting` quand le mode
## courant n'a PAS de bombe (Mêlée, Borne, Duel, Duo, entraînement) : ces
## modes n'ont jamais de VRAIE pose/désamorçage, contrairement à SnD (Litige).
const NO_BOMB_MODE := -1

## Vrai INTERACT (contrat GF-27, docs/research/10_ammo_kits_input.md §5.2
## point 1) : `input.pickup_held` seul se déclenche N'IMPORTE OÙ (aucun autre
## effet de jeu que planter/désamorcer, voir `SnDMode._client_report_holding` —
## `WorldWeapon` utilise `pickup_PRESSED`, pas `pickup_held`), donc la pose
## INTERACT s'affichait même hors de tout site en Litige, ou dans des modes
## sans bombe. Fonction PURE, testée directement (tests/player/
## test_character_animator.gd) à partir du seul état RÉPLIQUÉ de SnDMode
## (`bomb_state`/`bomb_carrier_id`/`attacking_team()`) — jamais des champs
## serveur privés (`_plant_progress`/`_holding`, qui exigeraient en plus
## d'être précisément dans le site/à portée, hors du périmètre de ce fichier).
static func is_really_interacting(pickup_held: bool, bomb_state: int, bomb_carrier_id: int,
		my_id: int, my_team: int, attacking_team: int) -> bool:
	if not pickup_held or bomb_state == NO_BOMB_MODE:
		return false
	if bomb_state == SnDMode.BombState.CARRIED:
		return bomb_carrier_id == my_id
	if bomb_state == SnDMode.BombState.PLANTED:
		return my_team != attacking_team
	return false

## Câblage NON pur de `is_really_interacting` : retrouve le mode de jeu
## courant (groupe "game_mode", voir GameMode._ready) et lit ses champs
## RÉPLIQUÉS — `null`/un mode qui n'est pas SnD (Mêlée, Borne, Duel, Duo,
## entraînement) retombe sur `NO_BOMB_MODE` (jamais de pose INTERACT hors
## Litige). Mort : jamais interagissant (même si F reste tenu au moment du kill).
func _compute_interacting(dead: bool) -> bool:
	if dead or input == null:
		return false
	var mode := get_tree().get_first_node_in_group("game_mode") as SnDMode
	if mode == null:
		return false
	return is_really_interacting(input.pickup_held, mode.bomb_state, mode.bomb_carrier_id,
		str(name).to_int(), team, mode.attacking_team())

## AUTORITÉ uniquement (appelé en dernier dans les deux branches de
## `_physics_process` côté autorité, une fois `move_and_slide()`/le step-up
## déjà appliqués — donc avec la position FINALE de ce tick) : poste
## l'instantané réseau horodaté que les pairs NON-AUTORITÉ bufferiseront
## (voir docstring de `net_position` et `_apply_remote_interpolation`).
## Remplace l'ancienne réplication brute de `.:position`/`.:rotation`.
func _publish_net_snapshot() -> void:
	net_tick = Engine.get_physics_frames()
	net_position = position
	net_rotation_y = rotation.y

## NON-AUTORITÉ uniquement (voir la branche appelante de `_physics_process`) :
## consomme les instantanés reçus du réseau (`net_position`/`net_rotation_y`/
## `net_tick`, répliqués "always" — voir leur docstring) via `_remote_interp`
## et ÉCRIT le résultat interpolé/retardé dans `position`/`rotation` — jamais
## l'inverse. GF-02 : voir RemoteInterpolator.gd pour le principe (délai fixe
## réglable, figeage plutôt qu'extrapolation, robustesse à la gigue et au
## réordonnancement réseau).
func _apply_remote_interpolation(delta: float) -> void:
	if net_tick != _last_net_tick:
		_last_net_tick = net_tick
		var t := float(net_tick) / _remote_interp.tick_rate
		if _remote_interp.snapshot_count() > 0:
			var last_pos: Vector3 = _remote_interp.sample(_remote_interp.latest_t())["position"]
			if net_position.distance_to(last_pos) > REMOTE_TELEPORT_DISTANCE:
				_remote_interp.reset()
		_remote_interp.push_snapshot(t, net_position, Vector3(0.0, net_rotation_y, 0.0))
		if not _remote_clock_started or _remote_interp.snapshot_count() == 1:
			# `snapshot_count() == 1` couvre deux cas où le tampon vient
			# d'être (re)parti de zéro : le tout premier instantané reçu après
			# le spawn (normalement déjà amorcé par `_ready`, voir plus haut —
			# filet de sécurité si jamais un instantané "always" arrivait
			# avant que `_ready` n'ait tourné), ET juste après un
			# `_remote_interp.reset()` sur téléportation détectée ci-dessus.
			# Dans les deux cas : ancre l'horloge de rendu sur CET instantané
			# plutôt que de la laisser sur son ancienne valeur (qui rendrait
			# `render_time` incohérent avec le tampon tout juste vidé).
			_remote_clock = t
			_remote_clock_started = true
	_remote_clock += delta
	var render_time := _remote_clock - _remote_interp.delay_seconds()
	var result := _remote_interp.sample(render_time)
	position = result["position"]
	rotation.y = result["rotation"].y

## Applique le regard d'un BOT (BotBrain écrit `input.look_delta`, en radians,
## AVANT ce tick — voir process_physics_priority sur PlayerInput/BotBrain).
## Même formule que `_look()` (mouse look humain), sans multiplicateur de
## sensibilité : BotBrain fournit déjà un delta en radians borné par tick.
##
## BUG-32 (régression MV-01/BOT-03, cause racine du bot non détecté au sol
## dans tests/player/test_stair_step.gd) :
## `input.look_delta` DOIT être consommé UNE SEULE FOIS puis remis à zéro ICI,
## exactement comme `event.relative` d'un mouvement souris humain (voir
## `_look()`) n'est jamais rejoué au tick suivant. En jeu réel ça ne changeait
## rien (BotBrain, priorité -150, réécrit `look_delta` À CHAQUE tick physique
## AVANT que PlayerController (priorité par défaut) ne le lise ici — la valeur
## d'avant est donc toujours fraîche). Mais un test qui avance la physique à la
## main (`player._physics_process(delta)` en boucle, sans repasser par l'arbre
## de scène — tests/player/test_stair_step.gd::_grounded_sprinting_bot) ne fait
## plus tourner BotBrain du tout après la mise en place initiale : sans ce
## reset, le DERNIER `look_delta` non nul posé par BotBrain (ex. le balayage
## hors-combat de BotLook, BOT-03) restait appliqué IDENTIQUE à CHAQUE tick
## suivant, faisant tourner le bot en continu (~0.83°/tick mesuré) jusqu'à le
## faire dériver hors de la dalle de test (4 m de large) et tomber dans le vide
## à côté — la chute de ~6 m et le "is_on_floor() faux" observés dans BUG-32
## n'avaient donc rien à voir avec le step-up/step-down (StairStep) ni avec le
## stun de chute (GF-29) : le bot ratait purement et simplement la marche/le
## rebord parce qu'il ne marchait plus tout droit. Ce correctif rend aussi le
## comportement RÉEL plus robuste : si BotBrain venait un jour à sauter un tick
## (dé-priorisation, pause), le bot s'arrête de tourner au lieu de partir en
## vrille avec une valeur périmée.
func _apply_bot_look() -> void:
	var d: Vector2 = input.look_delta
	input.look_delta = Vector2.ZERO
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
	var sens := effective_look_sensitivity(Settings.gamepad_sensitivity, input.aim_held, Settings.ads_sensitivity_multiplier)
	rotate_y(-rx * sens * delta)
	head.rotate_x(-ry * sens * delta)
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
				# Roulade forcée par ce chemin (Air -> Roll direct, sans passer
				# par Air._land()) : un slide-jump précédent ne doit plus être
				# considéré comme "en cours" (BUG-07, docs/audit/bugs.md —
				# sinon le PROCHAIN slide perd son boost de vitesse à tort).
				slide_jumped = false
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
	if not _fall_stun_enabled_in_current_mode():
		return  # GF-29 : Duel/Duo/Litige (manches) désactivent le stun de chute.
	var s := state_machine.current_name
	if s == "Roll" or s == "Dive" or s == "Stun":
		return  # la roulade absorbe l'impact
	var t: float = remap(fall_height, config.fall_min_height, config.fall_max_height, config.stun_min_time, config.stun_max_time)
	t = clampf(t, config.stun_min_time, config.stun_max_time)
	# Même raison que la branche Roll ci-dessus : ce chemin (Air -> Stun
	# direct) ne passe pas non plus par Air._land() (BUG-07).
	slide_jumped = false
	state_machine.transition_to("Stun", {"duration": t})

## Le mode de jeu courant autorise-t-il le stun de chute (GF-29,
## GameMode.fall_stun_enabled, MV-03) ? Même patron de lecture que
## Weapon._ammo_rule()/`_buy_enabled` (groupe "game_mode", jamais mis en
## cache — le groupe peut ne pas encore exister au tout premier appel, avant
## que la scène de mode ait fini de s'instancier). Aucun mode dans le groupe
## (pas de scène de mode DU TOUT, ex. l'entraînement) => autorisé par défaut
## (comportement historique inchangé, aucune régression). Un mode qui n'expose
## pas encore ce champ (double de test minimal) est traité de la même façon —
## tout mode de PRODUCTION (GameMode et ses sous-classes) porte, lui, toujours
## `fall_stun_enabled`.
func _fall_stun_enabled_in_current_mode() -> bool:
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode == null:
		return true
	var v = mode.get("fall_stun_enabled")
	return true if v == null else bool(v)

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
	var sens := effective_look_sensitivity(Settings.mouse_sensitivity, input.aim_held, Settings.ads_sensitivity_multiplier)
	rotate_y(-relative.x * sens)
	head.rotate_x(-relative.y * sens)
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

## Sensibilité de visée EFFECTIVE (souris ou manette) une fois le
## multiplicateur ADS appliqué (UX-06, Settings.ads_sensitivity_multiplier,
## docs/research/04_ui_ux.md §2.7 : "il faut un multiplicateur ADS séparé ...
## pour garder la mémoire musculaire") : ne s'applique QUE pendant la visée
## (`aim_held` vrai) — sensibilité au jugé inchangée sinon. Fonction PURE
## (aucun accès scène), appelée par `_look`/`_gamepad_look`, testée
## directement dans tests/core/test_settings.gd.
static func effective_look_sensitivity(base_sensitivity: float, aim_held: bool, ads_multiplier: float) -> float:
	return base_sensitivity * ads_multiplier if aim_held else base_sensitivity

## Replace le joueur au point de spawn (chute hors map, etc.).
func respawn() -> void:
	velocity = Vector3.ZERO
	global_position = spawn_point
	# Téléportation : évite la traînée/le glissement fantôme que
	# l'interpolation physique (GF-03) afficherait sinon entre l'ancienne et
	# la nouvelle position pendant le tick suivant.
	reset_physics_interpolation()
	if state_machine:
		state_machine.transition_to("Idle")

## Téléportation effective (respawn) — factorisée pour être appelée SOIT par
## `net_respawn` (RPC, joueur distant), SOIT directement par `server_respawn`
## (joueur simulé ICI : hôte ou bot — voir plus bas). Ne valide RIEN elle-même :
## les deux appelants ont déjà établi la confiance (RPC vérifiée / appel serveur direct).
## RÉINITIALISE tout l'état transitoire de chute/saut (BUG-07, docs/audit/bugs.md) :
## sans ça, un `_air_peak_y` resté haut (chute d'avant la mort/le changement de
## manche) déclenche un Stun/Roll fantôme au premier atterrissage après spawn,
## et un `_jump_buffer_timer`/`_coyote_timer` resté positif (appui juste avant
## la téléportation) déclenche un saut involontaire dès le tick suivant.
func _do_respawn(pos: Vector3) -> void:
	spawn_point = pos
	velocity = Vector3.ZERO
	global_position = pos
	# Téléportation : même raison que `respawn()` — sans ce reset,
	# l'interpolation physique (GF-03) afficherait un glissement fantôme
	# depuis l'ancienne position pendant le tick suivant.
	reset_physics_interpolation()
	_air_peak_y = pos.y
	# `true` : le premier `_check_fall_stun()` après spawn ne doit JAMAIS être
	# lu comme un atterrissage (donc jamais déclencher Stun/Roll) — voir
	# `_check_fall_stun` (`if not _was_on_floor: ...`).
	_was_on_floor = true
	_roll_buffer_timer = 0.0
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	slide_jumped = false
	# Idem (MV-01) : un décalage de lissage de marche resté en cours au moment
	# du respawn n'a plus aucun sens une fois téléporté ailleurs.
	_head_step_offset = 0.0
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
## `target_speed` = vitesse visée ; `accel`/`friction` en m/s^2. `target_speed`
## est mis à l'échelle par le multiplicateur de vitesse EFFECTIF (StatusEffects.
## speed_mult, docs/research/10_ammo_kits_input.md §3.5 -- ex. Glu de Verrou :
## 0.5 pendant 1.5 s) ; la friction (aucune direction voulue) reste inchangée,
## un ralentissement ne doit pas empêcher de s'arrêter normalement.
func ground_move(target_speed: float, accel: float, friction: float, delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if wish_dir != Vector3.ZERO:
		hv = hv.move_toward(wish_dir * target_speed * _status_speed_mult(), accel * delta)
	else:
		hv = hv.move_toward(Vector3.ZERO, friction * delta)
	velocity.x = hv.x
	velocity.z = hv.z

## Prototype à interface minimale (2026-09-26) : plus aucune capacité ne pose
## d'effet de statut (Glu de Verrou et consorts ont disparu avec tout le
## système de capacités, "Abilities" n'existe plus sur player.tscn) — ces
## deux fonctions gardent leur signature PUBLIQUE (`_status_speed_mult`
## appelée par `ground_move` ci-dessus, `is_jump_locked` par `can_jump`
## ci-dessous et par les states qui décident d'une entrée en Dive/Slide) mais
## retombent désormais TOUJOURS sur le neutre : aucun effet.
func _status_speed_mult() -> float:
	return 1.0

## true si un statut verrouille le saut de ce joueur — toujours faux
## désormais (voir la docstring ci-dessus). Public : réutilisable par les
## states qui décident d'une entrée en Dive/Slide (scripts/player/states/*),
## en plus de `can_jump()` qui le lit déjà ci-dessous.
func is_jump_locked() -> bool:
	return false

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

## Le joueur peut-il sauter ? (au sol OU dans la fenêtre coyote, ET pas
## verrouillé par un statut -- voir `is_jump_locked`).
func can_jump() -> bool:
	if is_jump_locked():
		return false
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

## AUTORITÉ uniquement : fait évoluer `current_height` vers la cible (debout/
## accroupi) — `is_crouching` n'est modifié QUE par le state_machine local
## (Crouch.gd), lui-même gardé par `is_multiplayer_authority()`. La valeur
## calculée est ensuite répliquée (always) vers les autres pairs, qui
## l'appliquent via `_apply_body_height` (voir `_physics_process`).
func _update_crouch_height(delta: float) -> void:
	var target := config.crouch_height if is_crouching else config.stand_height
	current_height = lerp(current_height, target, config.crouch_lerp_speed * delta)
	# Borne défensive (BUG-22, notes du contrat / docs/audit/bugs.md) : `lerp`
	# EXTRAPOLE si le poids dépasse 1 (delta anormalement grand — hitch au
	# changement de manche en Duel/Duo). Un poids très supérieur à 1 peut alors
	# faire dépasser `current_height` la cible visée, jusqu'à devenir NÉGATIF
	# — et CapsuleShape3D refuse toute hauteur négative ("height cannot be
	# negative"). On borne donc systématiquement à [crouch_height, stand_height].
	current_height = clampf(current_height, min(config.crouch_height, config.stand_height),
		max(config.crouch_height, config.stand_height))
	_apply_body_height()

## Rayon (m) de la capsule de collision — StairStep.try_step_up/try_step_down
## s'en servent UNIQUEMENT pour calibrer une distance de sondage horizontal
## sûre autour de l'arête d'une marche (jamais pour déplacer le corps).
## Repli défensif (0.4 m, le rayon par défaut de scenes/player/player.tscn) si
## la forme n'est pas une CapsuleShape3D — ne devrait jamais arriver en jeu.
func _capsule_radius() -> float:
	var shape := collision.shape
	if shape is CapsuleShape3D:
		return shape.radius
	return 0.4

## Applique `current_height` à la capsule de collision + à la tête. Appelé
## des DEUX côtés : par l'AUTORITÉ juste après avoir recalculé la valeur
## (`_update_crouch_height`), et par TOUT AUTRE pair (dont le serveur pour un
## joueur humain distant) à chaque tick physique, pour que sa propre copie de
## la capsule reflète la valeur répliquée — c'est cette capsule-là que le
## SERVEUR raycaste dans Weapon._resolve_ray (GF-04 : hitbox fiable accroupi).
func _apply_body_height() -> void:
	var shape := collision.shape
	if shape is CapsuleShape3D:
		shape.height = current_height
		collision.position.y = current_height * 0.5
	# La tête suit la hauteur (légèrement sous le sommet), plus le décalage de
	# lissage d'un step-up/step-down éventuel (`_head_step_offset`, toujours
	# 0.0 sur un pair non-autorité — voir `_apply_step_smoothing`).
	head.position.y = current_height - 0.2 + _head_step_offset

## MV-01 : absorbe visuellement le saut de hauteur brut de CE tick (`step_dy`,
## mètres, positif si on vient de monter une marche — tel que renvoyé/cumulé
## par StairStep.try_step_up/try_step_down) en décalant `_head_step_offset`
## d'autant dans l'autre sens (la tête garde un instant sa hauteur MONDE
## d'avant le pas), puis fait décroître ce décalage vers zéro en
## ~`config.stair_step_smooth_time` secondes (décroissance exponentielle :
## après ce délai il ne reste plus qu'environ 1/e, ~37 %, du décalage
## d'origine — un saut de marche instantané deviendrait sinon un à-coup
## caméra bien visible malgré `config.max_step_up/down` restant petits).
## Appelée uniquement côté AUTORITÉ (seule instance qui appelle StairStep) :
## `_head_step_offset` reste 0.0 sur tout pair qui ne fait qu'appliquer une
## hauteur répliquée (`_apply_body_height` seule, branche non-autorité de
## `_physics_process`).
func _apply_step_smoothing(step_dy: float, delta: float) -> void:
	if step_dy != 0.0:
		_head_step_offset -= step_dy
	if config.stair_step_smooth_time > 0.0:
		_head_step_offset *= exp(-delta / config.stair_step_smooth_time)
	else:
		_head_step_offset = 0.0
	_apply_body_height()
