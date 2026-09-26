## HumanoidBoneMap.gd
## Tables de correspondance figées entre deux squelettes humanoïdes et le
## profil SkeletonProfileHumanoid de Godot (56 os, groupes Body/LeftHand/
## RightHand — voir docs/assets_pipeline/retargeting_3d_skeletons.html et
## class_skeletonprofilehumanoid.html) :
##  - `MIXAMO_TO_HUMANOID` : squelette Mixamo de Frog Cowboy
##    (assets/models/characters/frog_cowboy.glb, 65 os `mixamorig_*` — les ":"
##    du glTF source deviennent des "_" une fois importés par Godot) ;
##  - `DEF_TO_HUMANOID` : squelette Rigify partagé "DEF-*" de la bibliothèque
##    d'animations UAL (assets/incoming/quaternius/ual.glb, 53 os, EXACTEMENT
##    le même rig que verrou.glb/choc.glb/etc. — vérifié par sondage direct des
##    deux fichiers).
## Chaque table oublie volontairement les os "bout de chaîne" sans réel
## équivalent dans le profil humanoïde (Mixamo : *_End, doigts ".../*4" ; UAL :
## le seul os "root" au-dessus de "DEF-hips", que Frog Cowboy n'a pas — ses
## "mixamorig_Hips" est déjà la racine) : 65 os Mixamo - 13 bouts de chaîne =
## 52 ; 53 os UAL - 1 "root" = 52. Les deux tables retombent donc sur
## EXACTEMENT le même ensemble de 52 noms de profil, vérifié par
## tests/player/test_humanoid_bone_map.gd.
class_name HumanoidBoneMap
extends RefCounted

const MIXAMO_TO_HUMANOID := {
	"mixamorig_Hips": "Hips",
	"mixamorig_Spine": "Spine",
	"mixamorig_Spine1": "Chest",
	"mixamorig_Spine2": "UpperChest",
	"mixamorig_Neck": "Neck",
	"mixamorig_Head": "Head",
	"mixamorig_LeftShoulder": "LeftShoulder",
	"mixamorig_LeftArm": "LeftUpperArm",
	"mixamorig_LeftForeArm": "LeftLowerArm",
	"mixamorig_LeftHand": "LeftHand",
	"mixamorig_LeftHandThumb1": "LeftThumbMetacarpal",
	"mixamorig_LeftHandThumb2": "LeftThumbProximal",
	"mixamorig_LeftHandThumb3": "LeftThumbDistal",
	"mixamorig_LeftHandIndex1": "LeftIndexProximal",
	"mixamorig_LeftHandIndex2": "LeftIndexIntermediate",
	"mixamorig_LeftHandIndex3": "LeftIndexDistal",
	"mixamorig_LeftHandMiddle1": "LeftMiddleProximal",
	"mixamorig_LeftHandMiddle2": "LeftMiddleIntermediate",
	"mixamorig_LeftHandMiddle3": "LeftMiddleDistal",
	"mixamorig_LeftHandRing1": "LeftRingProximal",
	"mixamorig_LeftHandRing2": "LeftRingIntermediate",
	"mixamorig_LeftHandRing3": "LeftRingDistal",
	"mixamorig_LeftHandPinky1": "LeftLittleProximal",
	"mixamorig_LeftHandPinky2": "LeftLittleIntermediate",
	"mixamorig_LeftHandPinky3": "LeftLittleDistal",
	"mixamorig_RightShoulder": "RightShoulder",
	"mixamorig_RightArm": "RightUpperArm",
	"mixamorig_RightForeArm": "RightLowerArm",
	"mixamorig_RightHand": "RightHand",
	"mixamorig_RightHandThumb1": "RightThumbMetacarpal",
	"mixamorig_RightHandThumb2": "RightThumbProximal",
	"mixamorig_RightHandThumb3": "RightThumbDistal",
	"mixamorig_RightHandIndex1": "RightIndexProximal",
	"mixamorig_RightHandIndex2": "RightIndexIntermediate",
	"mixamorig_RightHandIndex3": "RightIndexDistal",
	"mixamorig_RightHandMiddle1": "RightMiddleProximal",
	"mixamorig_RightHandMiddle2": "RightMiddleIntermediate",
	"mixamorig_RightHandMiddle3": "RightMiddleDistal",
	"mixamorig_RightHandRing1": "RightRingProximal",
	"mixamorig_RightHandRing2": "RightRingIntermediate",
	"mixamorig_RightHandRing3": "RightRingDistal",
	"mixamorig_RightHandPinky1": "RightLittleProximal",
	"mixamorig_RightHandPinky2": "RightLittleIntermediate",
	"mixamorig_RightHandPinky3": "RightLittleDistal",
	"mixamorig_LeftUpLeg": "LeftUpperLeg",
	"mixamorig_LeftLeg": "LeftLowerLeg",
	"mixamorig_LeftFoot": "LeftFoot",
	"mixamorig_LeftToeBase": "LeftToes",
	"mixamorig_RightUpLeg": "RightUpperLeg",
	"mixamorig_RightLeg": "RightLowerLeg",
	"mixamorig_RightFoot": "RightFoot",
	"mixamorig_RightToeBase": "RightToes",
}

const DEF_TO_HUMANOID := {
	"DEF-hips": "Hips",
	"DEF-spine.001": "Spine",
	"DEF-spine.002": "Chest",
	"DEF-spine.003": "UpperChest",
	"DEF-neck": "Neck",
	"DEF-head": "Head",
	"DEF-shoulder.L": "LeftShoulder",
	"DEF-upper_arm.L": "LeftUpperArm",
	"DEF-forearm.L": "LeftLowerArm",
	"DEF-hand.L": "LeftHand",
	"DEF-thumb.01.L": "LeftThumbMetacarpal",
	"DEF-thumb.02.L": "LeftThumbProximal",
	"DEF-thumb.03.L": "LeftThumbDistal",
	"DEF-f_index.01.L": "LeftIndexProximal",
	"DEF-f_index.02.L": "LeftIndexIntermediate",
	"DEF-f_index.03.L": "LeftIndexDistal",
	"DEF-f_middle.01.L": "LeftMiddleProximal",
	"DEF-f_middle.02.L": "LeftMiddleIntermediate",
	"DEF-f_middle.03.L": "LeftMiddleDistal",
	"DEF-f_ring.01.L": "LeftRingProximal",
	"DEF-f_ring.02.L": "LeftRingIntermediate",
	"DEF-f_ring.03.L": "LeftRingDistal",
	"DEF-f_pinky.01.L": "LeftLittleProximal",
	"DEF-f_pinky.02.L": "LeftLittleIntermediate",
	"DEF-f_pinky.03.L": "LeftLittleDistal",
	"DEF-shoulder.R": "RightShoulder",
	"DEF-upper_arm.R": "RightUpperArm",
	"DEF-forearm.R": "RightLowerArm",
	"DEF-hand.R": "RightHand",
	"DEF-thumb.01.R": "RightThumbMetacarpal",
	"DEF-thumb.02.R": "RightThumbProximal",
	"DEF-thumb.03.R": "RightThumbDistal",
	"DEF-f_index.01.R": "RightIndexProximal",
	"DEF-f_index.02.R": "RightIndexIntermediate",
	"DEF-f_index.03.R": "RightIndexDistal",
	"DEF-f_middle.01.R": "RightMiddleProximal",
	"DEF-f_middle.02.R": "RightMiddleIntermediate",
	"DEF-f_middle.03.R": "RightMiddleDistal",
	"DEF-f_ring.01.R": "RightRingProximal",
	"DEF-f_ring.02.R": "RightRingIntermediate",
	"DEF-f_ring.03.R": "RightRingDistal",
	"DEF-f_pinky.01.R": "RightLittleProximal",
	"DEF-f_pinky.02.R": "RightLittleIntermediate",
	"DEF-f_pinky.03.R": "RightLittleDistal",
	"DEF-thigh.L": "LeftUpperLeg",
	"DEF-shin.L": "LeftLowerLeg",
	"DEF-foot.L": "LeftFoot",
	"DEF-toe.L": "LeftToes",
	"DEF-thigh.R": "RightUpperLeg",
	"DEF-shin.R": "RightLowerLeg",
	"DEF-foot.R": "RightFoot",
	"DEF-toe.R": "RightToes",
}

## Clips lus par CharacterAnimator.gd (voir `_CLIPS`/upper body dans ce
## fichier) — mêmes noms EXACTS côté UAL (assets/incoming/quaternius/ual.glb),
## vérifié par sondage direct (aucun suffixe "_Loop" contrairement à une
## bibliothèque UAL générique : cet export Quaternius les a déjà sans
## suffixe). Liste photographiée ici pour que le bake tool et les tests
## partagent la même source de vérité.
const NEEDED_CLIPS := [
	"Idle", "Walk", "Jog_Fwd", "Sprint",
	"Crouch_Idle", "Crouch_Fwd",
	"Jump", "Jump_Start", "Jump_Land",
	"Roll", "Hit_Head", "Interact", "Death01",
	"Pistol_Aim_Down", "Pistol_Aim_Neutral", "Pistol_Aim_Up",
	"Pistol_Idle", "Pistol_Shoot", "Pistol_Reload",
]

## Clips EMBARQUÉS nativement dans le frog_cowboy.glb livré par le lead
## ("DECISION: frog gets NATIVE animations authored... exported INSIDE
## frog_cowboy.glb", 2026-09-26) — remplace le chemin UAL/retargeting
## ci-dessus POUR FROG COWBOY UNIQUEMENT (NEEDED_CLIPS/
## tools/rigging/bake_frog_animations.gd restent en l'état, dossier de
## nettoyage ultérieur : "do not delete its files"). Noms EXACTS attendus par
## CharacterAnimator.gd (`_CLIPS`) et FrogCowboyPostImport.gd (renommage des
## pistes + mode de boucle).
const FROG_FULL_BODY_CLIPS := [
	"Idle", "Walk", "Jog_Fwd", "Sprint",
	"Crouch_Idle", "Crouch_Fwd",
	"Jump_Start", "Jump", "Jump_Land",
	"Roll", "Hit_Head", "Interact", "Death01",
]

## Clips « haut du corps » classe fusil (préfixe résolu par
## CharacterAnimator.upper_body_clip_prefix — bascule Rifle_*/Pistol_* selon ce
## que l'AnimationPlayer courant expose réellement, jamais les deux mélangés
## pour un même personnage).
const FROG_RIFLE_CLIPS := [
	"Rifle_Aim_Down", "Rifle_Aim_Neutral", "Rifle_Aim_Up",
	"Rifle_Idle", "Rifle_Shoot", "Rifle_Reload",
]

## Sous-ensemble de FROG_FULL_BODY_CLIPS/FROG_RIFLE_CLIPS qui BOUCLE réellement
## en jeu (contrat livré par le lead) — les autres (Jump_Start/Jump_Land/Roll/
## Hit_Head/Interact/Death01/Rifle_Shoot/Rifle_Reload) jouent une seule fois.
## Consommé par FrogCowboyPostImport._apply_loop_modes (mode de boucle FORCÉ à
## l'import, indépendant de ce que l'export Blender a écrit dans le clip).
const FROG_LOOPING_CLIPS := [
	"Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Jump",
	"Rifle_Idle", "Rifle_Aim_Down", "Rifle_Aim_Neutral", "Rifle_Aim_Up",
]
