## CharacterAnimator.gd
## Anime le CharacterBody (squelette + AnimationPlayer chargés dynamiquement,
## voir CharacterBody.gd) via un AnimationTree construit EN CODE (le squelette
## n'existe qu'après le chargement du glb de l'agent — impossible de le
## câbler dans le .tscn à l'avance, chaque agent a son propre AnimationPlayer
## interne). Nœud "CharacterAnimator" (extends AnimationTree), frère de
## "%CharacterModel" dans scenes/player/player.tscn.
##
## Les pairs DISTANTS ne font PAS tourner la state machine du joueur
## (scripts/player/states/*, PlayerStateMachine) : ce nœud lit uniquement
## `player.anim_state` (packé : locomotion + bit "en rechargement", voir
## `pack_anim_state`/`unpack_locomotion`/`unpack_reloading`) et
## `player.aim_pitch`, deux champs répliqués TOUJOURS (SceneReplicationConfig)
## posés CHAQUE tick par l'AUTORITÉ (PlayerController._update_anim_state) —
## que ce soit le PROPRIÉTAIRE réel (humain) ou le SERVEUR (bot). Même code
## pour un corps LOCAL (valeurs déjà à jour, pas de latence réseau) et un
## corps DISTANT (valeurs répliquées) : aucune branche "suis-je propriétaire ?"
## ici, hors le cas "humain local" (corps caché, voir PlayerLook — inutile de
## piloter l'AnimationTree pour un corps que personne ne voit jamais).
##
## Deux couches :
##  - "Locomotion" (AnimationNodeTransition, PLEIN CORPS) : un clip par valeur
##    de `Locomotion`, sélectionné par `locomotion_for()` (logique pure, voir
##    tests/player/test_character_animator.gd).
##  - "UpperBody" (AnimationNodeBlend2, FILTRÉ colonne/bras — design : "filtered
##    to spine/arms") : pose de visée continue (AnimationNodeBlendSpace1D,
##    Pistol_Aim_Down/Neutral/Up mélangés par `aim_blend_t(aim_pitch)`) +
##    deux one-shots empilés (Pistol_Shoot au tir, Pistol_Reload au
##    rechargement) — masquée pendant les états pleine-pose (mort/roulade/
##    étourdi/interaction/plongeon, voir `_NO_UPPER_BODY`/`upper_body_active`).
## Tir : `Weapon.fired` (prédiction LOCALE — humain propriétaire, ou SERVEUR
## pour un bot, cf. scripts/combat/Weapon.gd) + `Weapon.remote_fired`
## (broadcast serveur -> tout le monde SAUF le tireur) : les deux couvrent
## exactement l'ensemble des corps qui doivent voir le one-shot Pistol_Shoot.
## Rechargement : PAS de signal broadcast équivalent dans Weapon.gd (lecture
## SEULE autorisée sur ce fichier, hors de portée de cette tranche) — d'où le
## bit RELOADING_FLAG sur `anim_state`, posé par PlayerController en écoutant
## SON PROPRE `Weapon.reload_started` (qui ne s'émet que là où la prédiction
## tourne, càd exactement là où `anim_state` est calculé — voir plus haut) et
## répliqué à tous comme le reste de `anim_state`.
class_name CharacterAnimator
extends AnimationTree

## -- Locomotion (couche PLEIN CORPS) ----------------------------------------
## Valeurs STABLES : répliquées dans PlayerController.anim_state (packées
## avec RELOADING_FLAG) — ne jamais réordonner en cours de route (casserait
## la réplication hôte/client en vol).
enum Locomotion {
	IDLE, WALK, JOG, SPRINT,
	CROUCH_IDLE, CROUCH_FWD, SLIDE,
	AIR, JUMP_START, JUMP_LAND, DIVE,
	ROLL, STUN, INTERACT, DEAD,
}

## Bit posé sur `anim_state` EN PLUS de la locomotion (rechargement en cours,
## indépendant du bas du corps) — choisi loin des valeurs de `Locomotion`
## (qui tiennent sur 4 bits, 0..14) pour ne jamais s'y superposer.
const RELOADING_FLAG := 1 << 8

## Un clip par valeur de `Locomotion`, même ordre que l'enum (voir `clip_for`).
## Slide réutilise Crouch_Fwd (design : "Slide = pose accroupie penchée" —
## l'inclinaison vient de `_drive_lean`, pas d'un clip dédié) ; Dive réutilise
## Jump (design : "Dive = pose de saut penchée en avant", même mécanisme).
const _CLIPS := [
	"Idle", "Walk", "Jog_Fwd", "Sprint",
	"Crouch_Idle", "Crouch_Fwd", "Crouch_Fwd",
	"Jump", "Jump_Start", "Jump_Land", "Jump",
	"Roll", "Hit_Head", "Interact", "Death01",
]

## États PLEIN CORPS pendant lesquels la couche "haut du corps" (visée/tir/
## rechargement) reste masquée — la pose complète du clip domine (un mort qui
## vise, ou un plongeon aux bras qui blendent vers Pistol_Aim, n'aurait aucun
## sens visuel).
const _NO_UPPER_BODY: Array[int] = [
	Locomotion.DEAD, Locomotion.ROLL, Locomotion.STUN, Locomotion.INTERACT, Locomotion.DIVE,
]

## Vitesse (m/s) séparant Jog et Sprint À L'INTÉRIEUR de l'état "Sprint" (pas
## un état dédié : le sprint démarre en Jog tant que l'accélération n'a pas
## atteint `MovementConfig.sprint_speed` = 8.2 — voir scripts/player/states/Sprint.gd).
const JOG_SPEED_THRESHOLD := 6.0
## Vitesse (m/s) au-delà de laquelle "Crouch" affiche Crouch_Fwd plutôt que
## Crouch_Idle (les deux sont le même état de la state machine, voir
## scripts/player/states/Crouch.gd — la locomotion en dérive par la vitesse).
const CROUCH_MOVE_THRESHOLD := 0.3
## Durées (s) des fenêtres Jump_Start / Jump_Land — gérées par
## PlayerController (détection de transition sur `state_machine.current_name`).
const JUMP_START_DUR := 0.15
const JUMP_LAND_DUR := 0.18

## Amplitude de pitch (rad) qui sature le blend Pistol_Aim_Down/Neutral/Up —
## au-delà, la pose Up/Down pleine suffit (le regard va jusqu'à 89°, bien plus
## que ce qu'une pose figée doit exagérer).
const AIM_PITCH_MAX := 0.87266463  # deg_to_rad(50.0), constante => pas d'appel en dehors d'une fonction

## Os filtrés pour la couche "haut du corps" (design : "filtered to
## spine/arms" — jamais les jambes ni la tête/nuque : le regard reste porté
## par la caméra du joueur, pas par cette couche).
const _UPPER_BODY_BONES := [
	"DEF-spine.001", "DEF-spine.002", "DEF-spine.003",
	"DEF-shoulder.L", "DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L",
	"DEF-shoulder.R", "DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R",
]
const _FINGER_CHAINS := ["f_index", "f_middle", "f_pinky", "f_ring", "thumb"]
## Chemin du squelette DANS les pistes d'animation (relatif à
## `AnimationPlayer.root_node`, PAS à ce nœud) — identique sur les 6 glb
## personnages ET fp_arms.glb (même pipeline : racine glTF "Rig" ->
## "Skeleton3D", vérifié par sondage direct des pistes d'un clip importé).
const _SKELETON_TRACK_PREFIX := "Rig/Skeleton3D:"

# ------------------------------------------------------------------
#  API PURE — testée directement (tests/player/test_character_animator.gd),
#  sans AnimationTree ni arbre de scène.
# ------------------------------------------------------------------

## Empaquette la locomotion + le bit "en rechargement" dans l'entier répliqué.
static func pack_anim_state(locomotion: int, reloading: bool) -> int:
	return locomotion | (RELOADING_FLAG if reloading else 0)

static func unpack_locomotion(anim_state: int) -> int:
	return anim_state & (RELOADING_FLAG - 1)

static func unpack_reloading(anim_state: int) -> bool:
	return (anim_state & RELOADING_FLAG) != 0

## Mappe (nom d'état de la state machine + vitesse + petites fenêtres de
## timing) vers une valeur de `Locomotion`. `jump_start_left`/`jump_land_left` :
## temps restant (s) dans la fenêtre Jump_Start/Jump_Land, géré par
## PlayerController (transitions détectées sur `state_machine.current_name`).
static func locomotion_for(state_name: String, speed: float, is_interacting: bool,
		is_dead: bool, jump_start_left: float = 0.0, jump_land_left: float = 0.0) -> int:
	if is_dead:
		return Locomotion.DEAD
	if is_interacting:
		return Locomotion.INTERACT
	if jump_land_left > 0.0:
		return Locomotion.JUMP_LAND
	if jump_start_left > 0.0:
		return Locomotion.JUMP_START
	match state_name:
		"Idle":
			return Locomotion.IDLE
		"Walk":
			return Locomotion.WALK
		"Sprint":
			return Locomotion.JOG if speed < JOG_SPEED_THRESHOLD else Locomotion.SPRINT
		"Crouch":
			return Locomotion.CROUCH_FWD if speed > CROUCH_MOVE_THRESHOLD else Locomotion.CROUCH_IDLE
		"Slide":
			return Locomotion.SLIDE
		"Air":
			return Locomotion.AIR
		"Dive":
			return Locomotion.DIVE
		"Roll":
			return Locomotion.ROLL
		"Stun":
			return Locomotion.STUN
	return Locomotion.IDLE

## `true` si la couche haut-du-corps (visée/tir/rechargement) doit être
## visible pour cette locomotion (voir `_NO_UPPER_BODY`).
static func upper_body_active(locomotion: int) -> bool:
	return not _NO_UPPER_BODY.has(locomotion)

## Position (-1..1) dans le blend de visée Pistol_Aim_Down/Neutral/Up — pitch
## en radians, positif = regarde vers le haut (convention
## PlayerController._look : `head.rotate_x(-relative.y * sensibilité)`, voir
## docstring `aim_pitch`).
static func aim_blend_t(pitch_rad: float) -> float:
	return clampf(pitch_rad / AIM_PITCH_MAX, -1.0, 1.0)

## Nom du clip pour une valeur de `Locomotion`.
static func clip_for(locomotion: int) -> String:
	if locomotion < 0 or locomotion >= _CLIPS.size():
		return "Idle"
	return _CLIPS[locomotion]

# ------------------------------------------------------------------
#  INSTANCE
# ------------------------------------------------------------------

var _character_body: CharacterBody
var _player: PlayerController
var _weapon: Weapon
var _built: bool = false
var _current_locomotion: int = -1
var _was_reloading: bool = false
var _lean: float = 0.0   ## Inclinaison procédurale (slide/dive), lissée.

func _ready() -> void:
	_player = get_parent() as PlayerController
	if _player and _player.is_local_human():
		# Corps caché pour l'humain local (vue FPS, voir PlayerLook) : ce
		# corps ne sera jamais visible, inutile de piloter l'AnimationTree.
		set_process(false)
		active = false
		return
	_character_body = get_node_or_null("%CharacterModel") as CharacterBody
	if _character_body == null:
		push_warning("CharacterAnimator : %CharacterModel introuvable.")
		set_process(false)
		return
	if _character_body.is_model_ready():
		_on_model_ready()
	else:
		_character_body.model_ready.connect(_on_model_ready)
	_weapon = _player.get_node_or_null("Weapon") as Weapon if _player else null
	if _weapon:
		_weapon.fired.connect(_on_fired)
		_weapon.remote_fired.connect(_on_remote_fired)

func _on_model_ready() -> void:
	if _built or _character_body.get_anim_player() == null:
		return
	_build_tree()
	_built = true

func _process(delta: float) -> void:
	if not _built or _player == null or not is_instance_valid(_player):
		return
	var state: int = _player.anim_state
	var locomotion := unpack_locomotion(state)
	var reloading := unpack_reloading(state)
	_drive_locomotion(locomotion)
	_drive_upper_body(locomotion, _player.aim_pitch, reloading)
	_drive_lean(locomotion, delta)

func _drive_locomotion(locomotion: int) -> void:
	if locomotion == _current_locomotion:
		return
	_current_locomotion = locomotion
	set("parameters/Locomotion/transition_request", "state_%d" % locomotion)

func _drive_upper_body(locomotion: int, pitch: float, reloading: bool) -> void:
	var active_amount := 1.0 if upper_body_active(locomotion) else 0.0
	set("parameters/UpperBody/blend_amount", active_amount)
	set("parameters/AimPose/blend_position", aim_blend_t(pitch))
	if reloading and not _was_reloading:
		set("parameters/ReloadShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_was_reloading = reloading

func _on_fired(_cfg: WeaponConfig) -> void:
	_trigger_shoot()

func _on_remote_fired(_cfg: WeaponConfig, _origin: Vector3, _dirs: Array) -> void:
	_trigger_shoot()

func _trigger_shoot() -> void:
	if not _built:
		return
	set("parameters/ShootShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## Inclinaison procédurale plein-corps (pas une piste d'anim) : Slide penche
## en avant façon glissade, Dive pique du nez — appliquée sur le MODÈLE
## (`_character_body`), jamais sur ce nœud (qui reste l'AnimationTree pur).
func _drive_lean(locomotion: int, delta: float) -> void:
	var target := 0.0
	if locomotion == Locomotion.SLIDE:
		target = deg_to_rad(18.0)
	elif locomotion == Locomotion.DIVE:
		target = deg_to_rad(35.0)
	_lean = move_toward(_lean, target, deg_to_rad(200.0) * delta)
	if _character_body:
		_character_body.rotation.x = _lean

# ------------------------------------------------------------------
#  Construction de l'AnimationTree EN CODE — le squelette/AnimationPlayer
#  n'existent qu'après le chargement dynamique du glb (un par agent), donc
#  impossible de câbler ça dans le .tscn à l'avance.
# ------------------------------------------------------------------

func _build_tree() -> void:
	anim_player = get_path_to(_character_body.get_anim_player())

	var bt := AnimationNodeBlendTree.new()

	# -- Couche "Locomotion" (plein corps, sélection par transition) --------
	var locomotion_node := AnimationNodeTransition.new()
	for i in Locomotion.size():
		locomotion_node.add_input("state_%d" % i)
	locomotion_node.xfade_time = 0.15
	bt.add_node("Locomotion", locomotion_node)
	for i in Locomotion.size():
		var leaf := AnimationNodeAnimation.new()
		leaf.animation = clip_for(i)
		var leaf_name := "Loco_%d" % i
		bt.add_node(leaf_name, leaf)
		bt.connect_node("Locomotion", i, leaf_name)

	# -- Couche "haut du corps" (visée continue + one-shots tir/recharge) ---
	var aim_pose := AnimationNodeBlendSpace1D.new()
	var aim_down := AnimationNodeAnimation.new()
	aim_down.animation = "Pistol_Aim_Down"
	var aim_neutral := AnimationNodeAnimation.new()
	aim_neutral.animation = "Pistol_Aim_Neutral"
	var aim_up := AnimationNodeAnimation.new()
	aim_up.animation = "Pistol_Aim_Up"
	aim_pose.add_blend_point(aim_down, -1.0, -1, &"down")
	aim_pose.add_blend_point(aim_neutral, 0.0, -1, &"neutral")
	aim_pose.add_blend_point(aim_up, 1.0, -1, &"up")
	bt.add_node("AimPose", aim_pose)

	var shoot_shot := AnimationNodeOneShot.new()
	shoot_shot.fadein_time = 0.03
	shoot_shot.fadeout_time = 0.08
	bt.add_node("ShootShot", shoot_shot)
	bt.connect_node("ShootShot", 0, "AimPose")
	var shoot_clip := AnimationNodeAnimation.new()
	shoot_clip.animation = "Pistol_Shoot"
	bt.add_node("ShootClip", shoot_clip)
	bt.connect_node("ShootShot", 1, "ShootClip")

	var reload_shot := AnimationNodeOneShot.new()
	reload_shot.fadein_time = 0.05
	reload_shot.fadeout_time = 0.15
	bt.add_node("ReloadShot", reload_shot)
	bt.connect_node("ReloadShot", 0, "ShootShot")
	var reload_clip := AnimationNodeAnimation.new()
	reload_clip.animation = "Pistol_Reload"
	bt.add_node("ReloadClip", reload_clip)
	bt.connect_node("ReloadShot", 1, "ReloadClip")

	# -- Fusion : plein corps (base) + haut du corps (filtré spine/bras) ----
	var upper_body := AnimationNodeBlend2.new()
	upper_body.filter_enabled = true
	for path in _filter_paths():
		upper_body.set_filter_path(path, true)
	bt.add_node("UpperBody", upper_body)
	bt.connect_node("UpperBody", 0, "Locomotion")
	bt.connect_node("UpperBody", 1, "ReloadShot")

	bt.connect_node("output", 0, "UpperBody")

	tree_root = bt
	active = true

## Chemins de piste (relatifs à `AnimationPlayer.root_node`) pour la couche
## "haut du corps" : colonne + les deux bras, doigts inclus.
func _filter_paths() -> Array:
	var names: Array = _UPPER_BODY_BONES.duplicate()
	for side in ["L", "R"]:
		for chain in _FINGER_CHAINS:
			for seg in [1, 2, 3]:
				names.append("DEF-%s.0%d.%s" % [chain, seg, side])
	var paths: Array = []
	for n in names:
		paths.append(NodePath(_SKELETON_TRACK_PREFIX + n))
	return paths
