## FPArmsMath.gd
## Maths PURES (aucun Node/arbre de scène) pour le rig de bras FP (grenouille,
## assets/models/characters/frog_cowboy_fp.glb) — voir FPArmsRig.gd pour le
## câblage réel (Skeleton3D/BoneAttachment3D/AnimationTree). Séparé du nœud
## comme ViewModel.AnimState / CharacterAnimator.gd (fonctions statiques) pour
## rester testable sans instancier de scène — voir
## tests/player/test_fp_arms_math.gd.
##
## ALIGNEMENT CAMÉRA (contrat tâche "frog fp arms") : le rig est posé chaque
## frame pour que l'os "FPCamera" (enfant de mixamorig_Hips, repère l'œil du
## personnage) coïncide avec la Camera3D réelle du joueur. `align_rig_transform`
## résout cette égalité pour `rig_root.global_transform` en tenant compte du
## fait que le rig est mis à l'échelle RIG_SCALE (1.0 = 1.8 m, même convention
## que CharacterBody.TARGET_HEIGHT) :
##
## Notations : Br/Or = basis/origin de la transform de repos (REST) de l'os
## FPCamera dans l'espace du squelette (unités BRUTES du glb, PAS mises à
## l'échelle) -- `Skeleton3D.get_bone_global_rest`. Cam = camera.global_transform
## (Basis pur, sans échelle -- une Camera3D n'a jamais de scale dans ce projet).
## Q := Cam.basis * Br.transposed() (Br est orthonormée -- son inverse EST sa
## transposée) : la seule rotation pure telle que Q * Br == Cam.basis EXACTEMENT
## (pas juste une direction proche, une égalité de matrice, puisque Br et Cam.basis
## sont toutes deux orthonormées).
##
## Preuve (posée ici une fois, vérifiée aussi par le test d'intégration
## FPArmsRig) : en posant rig_root.basis = Q * RIG_SCALE (rotation Q, échelle
## RIG_SCALE) et rig_root.origin = Cam.origin - RIG_SCALE * Q * Or, la transform
## MONDE résultante de l'os FPCamera (rig_root.global_transform * REST_brute)
## vaut EXACTEMENT Transform3D(Cam.basis * RIG_SCALE, Cam.origin) : l'origine
## (position de l'œil) coïncide au bit près avec la caméra réelle, et la
## direction (Cam.basis normalisée) aussi -- seule la MAGNITUDE de la base
## diffère (RIG_SCALE au lieu de 1), sans conséquence : rien ne lit la
## "transform" de l'os FPCamera après cet alignement, seule la Camera3D réelle
## pilote le rendu. C'est ce même RIG_SCALE, propagé par la hiérarchie de nœuds
## jusqu'à la BoneAttachment3D posée sur l'os "WeaponGrip", qui impose ensuite
## `weapon_counter_scale` sur l'arme (sinon elle serait RIG_SCALE fois trop
## grande).
class_name FPArmsMath
extends RefCounted

## 1.0 (unité brute du glb) = 1.8 m -- même convention que
## scripts/player/CharacterBody.gd::TARGET_HEIGHT (corps tiers, même rig
## Mixamo d'origine).
const RIG_SCALE := 1.8

## Résout `rig_root.global_transform` (voir la preuve dans la docstring de
## classe) — fonction PURE, aucun Node3D/Skeleton3D requis, seulement les deux
## transforms et le facteur d'échelle effectif (RIG_SCALE ci-dessus, multiplié
## par `_fov_scale()` côté ViewModel -- voir FPArmsRig.align_to_camera).
## Repli défensif (identité) si `rig_scale` est nul/négatif : ne devrait
## jamais arriver (RIG_SCALE est une constante positive, fov_scale > 0 par
## construction de `tan()`), mais jamais de division/inverse par zéro.
static func align_rig_transform(fp_camera_rest: Transform3D, camera_global: Transform3D, rig_scale: float) -> Transform3D:
	if rig_scale <= 0.0001:
		return camera_global
	var rest_scaled := Transform3D(fp_camera_rest.basis, fp_camera_rest.origin * rig_scale)
	var base := camera_global * rest_scaled.affine_inverse()
	return Transform3D(base.basis.scaled(Vector3.ONE * rig_scale), base.origin)

## Échelle LOCALE à poser sur l'arme attachée sous la BoneAttachment3D
## "WeaponGrip" pour annuler `rig_scale` (héritée de tout le rig, voir la
## docstring de classe) et revenir à la taille réelle de l'arme (modélisée à
## l'échelle 1:1, cf. tools/blender/fit_weapon_painted.py) — même principe que
## ThirdPersonWeapon.counter_scale_for (corps tiers), fonction INDÉPENDANTE ici
## (fichiers disjoints, voir la répartition de la tâche) mais même garantie
## défensive : jamais de composante infinie/NaN, repli identité si `rig_scale`
## est quasi nul.
static func weapon_counter_scale(rig_scale: float) -> Vector3:
	if absf(rig_scale) < 0.0001:
		return Vector3.ONE
	return Vector3.ONE / rig_scale

## Position (0..1) du blend Idle->ADS (AnimationNodeBlend2 "IdleAds", voir
## FPArmsRig._build_tree) à partir de `ads_t` — même convention que
## ViewModel._ads_t (1 = hanche/repos, 0 = pleinement visé) : 0 sur le blend
## sélectionne FP_Idle (entrée 0), 1 sélectionne FP_ADS (entrée 1), donc
## simplement l'inverse de `ads_t`.
static func ads_blend_amount(ads_t: float) -> float:
	return clampf(1.0 - ads_t, 0.0, 1.0)

## Vitesse de lecture (`parameters/ReloadSpeed/scale`) du clip FP_Reload pour
## qu'il dure `reload_time` secondes de l'arme en main — contrat tâche : "speed
## 2.5 / weapon reload_time" (2.5 = durée de référence de l'asset, cf. l'asset
## contract "FP_Reload (2.5 s, = ravage.tres reload_time)"), MÊME principe que
## CharacterAnimator.reload_clip_speed (corps tiers, RELOAD_CLIP_BASE_DURATION_S
## / reload_time) mais indépendant (fichiers disjoints). Repli défensif à 1.0
## (vitesse native) si `reload_time` est invalide (≤ 0) — jamais de division
## par zéro.
const RELOAD_CLIP_REFERENCE_DURATION_S := 2.5

static func reload_speed_for(reload_time: float) -> float:
	if reload_time <= 0.0:
		return 1.0
	return RELOAD_CLIP_REFERENCE_DURATION_S / reload_time

## Le geste d'inspection (touche "inspect", FP_Inspect) doit être interrompu
## dès que le joueur tire, vise ou recharge (acceptance tâche : "cancelled by
## firing/aiming/reloading") — fonction PURE, testée directement, consommée
## chaque frame par FPArmsRig (ABORT du one-shot "InspectShot") ET pour
## bloquer un NOUVEAU déclenchement pendant que l'une de ces actions est en
## cours.
static func should_cancel_inspect(firing: bool, aiming: bool, reloading: bool) -> bool:
	return firing or aiming or reloading
