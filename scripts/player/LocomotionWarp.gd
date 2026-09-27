## LocomotionWarp.gd
## Correction visuelle du bas du corps (tâche "bots humains", passe 2,
## diagnostic du lead) : la locomotion du personnage (`CharacterAnimator.
## locomotion_for`/`_CLIPS`) est DIRECTION-AGNOSTIQUE -- Idle/Walk/Jog_Fwd/
## Sprint sont choisis par ÉTAT + VITESSE seulement, aucun clip de côté ni de
## recul n'existe. Un personnage qui strafe ou recule (visée qui diverge du
## déplacement -- ~60° en moyenne pour un bot d'après la sonde de la passe 1,
## et tout humain distant qui strafe) joue donc un cycle de marche AVANT tout
## en glissant visiblement de côté : « il ne tourne pas les jambes ».
##
## Ce `SkeletonModifier3D` (enfant DIRECT du Skeleton3D -- voir
## `CharacterAnimator._attach_locomotion_warp`, jamais construit ailleurs)
## corrige ça EN AVAL de l'AnimationTree, à CHAQUE frame de squelette
## (`_process_modification_with_delta`, API Godot 4.7 courante -- voir
## class_skeletonmodifier3d.html, `_process_modification()` sans delta est
## DÉPRÉCIÉE) :
##  - calcule l'angle (monde) entre le déplacement RÉEL du personnage et son
##    cap (visée) ;
##  - si |angle| <= ~100° (déplacement plutôt vers l'avant/le côté) : fait
##    pivoter les HANCHES vers le déplacement (± HIP_YAW_CLAMP_DEG), et
##    contre-pivote la COLONNE (Spine/Chest/UpperChest, à parts égales) pour
##    que le buste/les bras/l'arme restent orientés vers la visée d'origine ;
##  - si |angle| > ~110° (déplacement plutôt vers l'arrière) : pivote les
##    hanches par (angle - 180°) -- résiduel une fois qu'on suppose la lecture
##    du clip INVERSÉE (`is_backward_locomotion()`, lu par CharacterAnimator
##    pour poser un `AnimationNodeTimeScale` négatif sur "Locomotion") ; à 180°
##    pile (recul strict), le résiduel est nul : les hanches restent face à la
##    visée, les jambes reculent par la seule inversion du clip ;
##  - bande morte 100-110° : hystérésis (garde le mode précédent) pour ne
##    jamais osciller entre les deux formules à la frontière ;
##  - lissé en VITESSE (aucun warp à l'arrêt/quasi arrêt, `speed_blend_alpha`)
##    ET dans le TEMPS (ressort critique amorti ~0.12 s, `critically_damped_
##    step`) -- jamais un à-coup, même sur un changement brutal de direction.
##
## Os ciblés par NOM DE PROFIL HUMANOÏDE (`scripts/import/HumanoidBoneMap.gd`,
## table `MIXAMO_TO_HUMANOID` -- Frog Cowboy est RENOMMÉ vers ces noms à
## l'import, voir FrogCowboyPostImport.gd : `Skeleton3D.find_bone("Hips")`
## fonctionne directement) -- jamais les noms "DEF-*" du rig legacy partagé
## (Verrou/5 autres agents Tripo, hors du prototype minimal actuel). Repli
## défensif total (aucun os "Hips" trouvé -> `_hips_idx == -1`, ce modifier ne
## touche plus rien) : jamais un plantage sur un rig qui ne les expose pas.
##
## Toutes les rotations sont appliquées en POSE GLOBALE (`Skeleton3D.
## get_bone_global_pose`/`set_bone_global_pose`, jamais la pose LOCALE comme
## `_apply_flinch`/`_apply_body_squash` de CharacterAnimator.gd) : la pose
## globale est déjà composée à travers toute la chaîne de parenté et reste
## donc alignée sur les axes MONDE du squelette (Y = haut, -Z = face du
## personnage au repos) quelle que soit l'orientation locale propre à chaque
## os -- une rotation "lacet" (Vector3.UP) n'a de sens géométrique simple que
## dans cet espace-là. Une hanche modifiée EN PREMIER (`_apply_warp`) rend
## `get_bone_global_pose` de la colonne DÉJÀ tourné (composition automatique
## de Skeleton3D à travers la chaîne de parenté) : contre-pivoter chaque
## articulation de la chaîne, TOP-DOWN, avec la MÊME part à chaque fois,
## cumule donc exactement la contre-rotation totale voulue une fois arrivé en
## haut de la chaîne (UpperChest) -- tête/épaules/bras/arme, enfants de
## UpperChest, héritent alors d'une orientation intacte.
##
## Vitesse RECALCULÉE par différence de position du Skeleton3D d'une frame à
## l'autre (`global_transform.origin`), jamais lue sur `PlayerController.
## velocity` (CharacterBody3D) : ce champ n'est réel que côté AUTORITÉ (bot
## sur le serveur, humain sur son propre client) -- un pair DISTANT ne fait
## jamais tourner sa physique (`_apply_remote_interpolation` n'écrit que
## `position`/`rotation.y`, jamais `velocity`), et resterait donc à vitesse
## nulle en permanence pour ce modifier. Différencier la position affichée
## (déjà interpolée pour un pair distant, déjà réelle pour l'autorité) est
## la SEULE source valable pour "bots, humains distants ET le modèle 3P local"
## à la fois (contrat de cette tâche) -- décision prise ici, pas héritée d'un
## champ existant.
class_name LocomotionWarp
extends SkeletonModifier3D

## Noms de profil humanoïde (HumanoidBoneMap.MIXAMO_TO_HUMANOID/DEF_TO_HUMANOID
## retombent tous deux sur les mêmes 52 noms, voir sa docstring).
const HIPS_BONE_NAME := "Hips"
const SPINE_CHAIN_BONE_NAMES := ["Spine", "Chest", "UpperChest"]

## Clamp du lacet des hanches (deg) -- "clamped to ±70°" (contrat lead).
const HIP_YAW_CLAMP_DEG := 70.0
## |angle| <= ce seuil : warp "avant" (hanches vers le déplacement).
const FORWARD_ANGLE_MAX_DEG := 100.0
## |angle| > ce seuil : warp "arrière" (résiduel + lecture inversée).
const BACKWARD_ANGLE_MIN_DEG := 110.0

## Vitesse (m/s) sous laquelle le warp est totalement nul (arrêt/quasi arrêt)
## et au-dessus de laquelle il est pleinement actif -- lissage LINÉAIRE entre
## les deux (`speed_blend_alpha`), avant le lissage temporel du ressort.
const MIN_WARP_SPEED_MPS := 0.3
const FULL_WARP_SPEED_MPS := 1.5

## Temps de réponse (s) du ressort critique amorti appliqué au lacet final des
## hanches -- "critically-damped, ~0.12 s" (contrat lead) : voir
## `critically_damped_step`.
const SMOOTH_TIME_CONSTANT_S := 0.12

## Norme de vitesse (m/s) au-delà de laquelle une frame est considérée comme
## une téléportation (respawn/reset) plutôt qu'un déplacement réel -- bien
## au-dessus de MovementConfig.sprint_speed (8,2 m/s) : jamais un warp basé sur
## un saut de position d'une frame à l'autre.
const TELEPORT_SPEED_MPS := 20.0

var _hips_idx := -1
var _spine_idx: Array[int] = []
var _prev_pos := Vector3.INF
var _backward_mode := false
var _hip_yaw_state: Dictionary = {}
## Lu par CharacterAnimator._drive_locomotion_speed (parameters/LocomotionSpeed/
## scale) -- vrai seulement si le mode "arrière" est actif ET qu'il reste assez
## de vitesse pour que ça compte (jamais d'inversion de clip à l'arrêt).
var _backward_locomotion := false


func is_backward_locomotion() -> bool:
	return _backward_locomotion


func _ready() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	_hips_idx = skeleton.find_bone(HIPS_BONE_NAME)
	_spine_idx.clear()
	for bone_name in SPINE_CHAIN_BONE_NAMES:
		var idx := skeleton.find_bone(bone_name)
		if idx != -1:
			_spine_idx.append(idx)


func _process_modification_with_delta(delta: float) -> void:
	if _hips_idx == -1 or delta <= 0.0:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return

	var xform := skeleton.global_transform
	var pos := xform.origin
	var world_vel := Vector3.ZERO
	if _prev_pos.is_finite():
		world_vel = sanitize_velocity((pos - _prev_pos) / delta)
	_prev_pos = pos

	var forward := -xform.basis.z
	var facing_yaw_deg := rad_to_deg(atan2(-forward.x, -forward.z))
	var speed := Vector2(world_vel.x, world_vel.z).length()
	var alpha := speed_blend_alpha(speed)
	var angle_deg := move_facing_angle_deg(world_vel, facing_yaw_deg)

	_backward_mode = backward_mode_next(_backward_mode, angle_deg)
	_backward_locomotion = _backward_mode and alpha > 0.0

	var raw_hip_yaw := backward_hip_yaw_deg(angle_deg) if _backward_mode else forward_hip_yaw_deg(angle_deg)
	var target := raw_hip_yaw * alpha
	_hip_yaw_state = critically_damped_step(_hip_yaw_state, target, SMOOTH_TIME_CONSTANT_S, delta)

	_apply_warp(skeleton, float(_hip_yaw_state.get("value", 0.0)))


## Applique `hip_yaw_deg` aux hanches (pose GLOBALE, voir la docstring d'en-
## tête) puis contre-pivote la colonne à parts égales -- no-op sur la colonne
## si `_spine_idx` est vide (rig sans ces os : les hanches tournent quand même,
## repli dégradé plutôt qu'un plantage).
func _apply_warp(skeleton: Skeleton3D, hip_yaw_deg: float) -> void:
	var hip_rot := Basis(Vector3.UP, deg_to_rad(hip_yaw_deg))
	var hips_pose := skeleton.get_bone_global_pose(_hips_idx)
	hips_pose.basis = hip_rot * hips_pose.basis
	skeleton.set_bone_global_pose(_hips_idx, hips_pose)

	if _spine_idx.is_empty():
		return
	var share_deg := spine_counter_yaw_deg(hip_yaw_deg, _spine_idx.size())
	if is_zero_approx(share_deg):
		return
	var share_rot := Basis(Vector3.UP, deg_to_rad(share_deg))
	for idx in _spine_idx:
		var pose := skeleton.get_bone_global_pose(idx)
		pose.basis = share_rot * pose.basis
		skeleton.set_bone_global_pose(idx, pose)


# ======================================================================
#  API PURE -- testée directement (tests/player/test_locomotion_warp.gd),
#  sans Skeleton3D ni arbre de scène (même esprit que CharacterAnimator.gd).
# ======================================================================

## Écarte une vitesse aberrante (téléportation -- respawn/reset physique
## d'interpolation) : `Vector3.ZERO` au-delà de `max_speed`, `v` inchangé
## sinon.
static func sanitize_velocity(v: Vector3, max_speed: float = TELEPORT_SPEED_MPS) -> Vector3:
	return Vector3.ZERO if v.length() > max_speed else v


## Angle SIGNÉ (deg, -180..180] entre la direction de déplacement MONDE
## `move_dir` (plan XZ) et `facing_yaw_deg` -- même convention que
## `PlayerController.rotation.y`/`BotLook.yaw_forward_dir` (atan2(-x,-z),
## POSITIF = lacet vers la GAUCHE, comme `rotation.y` lui-même : un yaw
## positif tourne `yaw_forward_dir` vers -X à partir de -Z ; le déplacement
## est donc "à gauche" pour un angle positif). `move_dir` quasi nul (arrêt) :
## 0.0, aucun angle défini. Le sens exact n'a pas d'importance pour le résultat
## VISUEL (`_apply_warp` applique la MÊME rotation `Basis(Vector3.UP, ...)`
## que `rotation.y`, donc les deux se corrigent mutuellement) -- seulement
## documenté ici pour ne pas se tromper en lisant `angle_deg` dans les tests.
static func move_facing_angle_deg(move_dir: Vector3, facing_yaw_deg: float) -> float:
	if Vector2(move_dir.x, move_dir.z).length() < 0.05:
		return 0.0
	var move_yaw_deg := rad_to_deg(atan2(-move_dir.x, -move_dir.z))
	return wrapf(move_yaw_deg - facing_yaw_deg, -180.0, 180.0)


static func is_backward_angle(angle_deg: float) -> bool:
	return absf(angle_deg) > BACKWARD_ANGLE_MIN_DEG


static func is_forward_angle(angle_deg: float) -> bool:
	return absf(angle_deg) <= FORWARD_ANGLE_MAX_DEG


## Hystérésis avant/arrière (bande morte ]100°, 110°]) : `previous` (mode de
## la frame d'avant) est reconduit tant que `angle_deg` reste dans la bande,
## jamais d'oscillation à la frontière.
static func backward_mode_next(previous: bool, angle_deg: float) -> bool:
	if is_backward_angle(angle_deg):
		return true
	if is_forward_angle(angle_deg):
		return false
	return previous


## Lacet des hanches (deg) en mode AVANT -- l'angle lui-même, clampé.
static func forward_hip_yaw_deg(angle_deg: float) -> float:
	return clampf(angle_deg, -HIP_YAW_CLAMP_DEG, HIP_YAW_CLAMP_DEG)


## Lacet des hanches (deg) en mode ARRIÈRE -- résiduel une fois la lecture du
## clip supposée INVERSÉE (voir la docstring d'en-tête : nul pile à 180°,
## grandit à mesure qu'on s'éloigne du recul strict), clampé.
static func backward_hip_yaw_deg(angle_deg: float) -> float:
	var residual := wrapf(angle_deg - 180.0, -180.0, 180.0)
	return clampf(residual, -HIP_YAW_CLAMP_DEG, HIP_YAW_CLAMP_DEG)


## Lissage LINÉAIRE 0..1 par vitesse (m/s) -- nul à l'arrêt/quasi arrêt, plein
## au-delà de `full_speed`.
static func speed_blend_alpha(speed_mps: float, min_speed: float = MIN_WARP_SPEED_MPS, full_speed: float = FULL_WARP_SPEED_MPS) -> float:
	if speed_mps <= min_speed:
		return 0.0
	if speed_mps >= full_speed:
		return 1.0
	return (speed_mps - min_speed) / (full_speed - min_speed)


## Part ÉGALE de contre-rotation (deg) par articulation de la colonne, pour
## que la somme cumulée (TOP-DOWN, voir `_apply_warp`) annule EXACTEMENT
## `hip_yaw_deg` une fois arrivé en haut de la chaîne. `0.0` si `chain_size`
## est nul (aucun os de colonne trouvé -- l'appelant ne boucle alors sur
## rien de toute façon).
static func spine_counter_yaw_deg(hip_yaw_deg: float, chain_size: int) -> float:
	if chain_size <= 0:
		return 0.0
	return -hip_yaw_deg / float(chain_size)


## Un pas de ressort-amortisseur CRITIQUEMENT amorti (zeta=1, aucun
## dépassement) vers `target`, avec un temps de réponse `time_constant_s`
## (réglé pour un régime établi -- ~98 % de l'écart -- à `t ~= time_constant_s`,
## soit wn = 4/time_constant_s pour zeta=1) -- même famille de formule que
## `BotLook.spring_step_capped`/`BotAim.spring_natural_freq` (zeta=0,9, un
## léger dépassement toléré pour le regard) : ici AUCUN dépassement n'est
## toléré (contrat lead "no snaps"). État `{"value": float, "speed": float}`
## (`{}` = première invocation, valeur/vitesse nulles).
static func critically_damped_step(state: Dictionary, target: float, time_constant_s: float, delta: float) -> Dictionary:
	var value: float = float(state.get("value", 0.0))
	var speed: float = float(state.get("speed", 0.0))
	var wn := 4.0 / maxf(time_constant_s, 0.001)
	var k := wn * wn
	var d := 2.0 * wn
	var accel := k * (target - value) - d * speed
	var new_speed := speed + accel * delta
	var new_value := value + new_speed * delta
	return {"value": new_value, "speed": new_speed}
