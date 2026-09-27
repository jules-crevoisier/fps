## FPArmsRig.gd
## Bras premières-personne de Verrou (grenouille) — remplace les gants
## flottants historiques de ViewModel.gd (assets/models/characters/
## fp_gloves.glb, conservés en repli SEULEMENT si CE glb échoue à charger,
## voir `load()`) par un rig squeletté réel : assets/models/characters/
## frog_cowboy_fp.glb, manchon+mains peintes sur le rig Mixamo complet
## ("mixamorig_*", PAS renommé en noms humanoïdes -- contrairement à
## frog_cowboy.glb/FrogCowboyPostImport.gd, tiers -- voir la note "bone names
## mixamorig_*" du contrat de tâche), plus deux os ajoutés par l'export :
##  - "WeaponGrip" (enfant de mixamorig_RightHand) : une BoneAttachment3D posée
##    ICI dessus (l'export ne la crée pas, seul l'OS existe) sert de point
##    d'attache pour l'arme courante (`attach_weapon`), -Z = canon vers
##    l'avant, +Y = dessus de l'arme, transform locale IDENTITÉ pour l'arme
##    (voir `weapon_counter_scale` -- l'arme est modélisée à l'échelle réelle,
##    le rig est grossi RIG_SCALE, voir plus bas).
##  - "FPCamera" (enfant de mixamorig_Hips) : repère l'œil du personnage, sa
##    transform de REPOS sert d'ancre pour placer le rig entier (`align_to_
##    camera`, maths dans FPArmsMath.gd -- preuve complète dans sa docstring
##    de classe).
##
## RIG_SCALE (FPArmsMath.RIG_SCALE, 1.0 = 1,8 m) : même convention que
## CharacterBody.TARGET_HEIGHT (corps tiers, même rig Mixamo d'origine) --
## posée comme l'échelle PROPRE de CE nœud (voir `align_to_camera`, qui
## fabrique directement la transform monde avec cette magnitude, cf. preuve
## FPArmsMath). L'arme attachée sous "WeaponGrip" hérite cette échelle par la
## hiérarchie de nœuds standard (BoneAttachment3D -> Skeleton3D -> Armature ->
## racine importée -> CE nœud) ; `attach_weapon` la contre-échelle donc par
## `FPArmsMath.weapon_counter_scale` pour revenir à sa taille réelle.
##
## Anim : AnimationTree construit EN CODE (même principe que
## scripts/player/CharacterAnimator.gd, tiers -- fichier disjoint, jamais
## touché ici) sur les 7 clips embarqués dans le glb (FP_Idle/FP_ADS/FP_Fire/
## FP_Reload/FP_Draw/FP_Sprint/FP_Inspect) : Idle<->ADS mélangés en continu par
## `set_ads_amount` (Blend2), Sprint mélangé par-dessus par `set_sprint_amount`
## (Blend2), puis Fire/Reload/Draw/Inspect couchés en one-shot successifs
## (OneShot, même style que CharacterAnimator._build_tree -- ShootShot/
## ReloadShot). Le geste d'inspection est annulé (`cancel_inspect`) par tir/
## visée/rechargement, voir FPArmsMath.should_cancel_inspect (ViewModel.gd
## pilote cette règle chaque frame, ce fichier ne fait qu'exposer le
## déclenchement/l'annulation bruts).
class_name FPArmsRig
extends Node3D

const DEFAULT_PATH := "res://assets/models/characters/frog_cowboy_fp.glb"
const WEAPON_GRIP_BONE := "WeaponGrip"
## Os d'attache du Revolver (tâche "revolver" 2026-09-27, contrat lead : "the
## lead adds a bone 'PistolGrip' (child of the right hand)") — même transform
## locale IDENTITÉ + contre-échelle que "WeaponGrip" (voir `attach_weapon`),
## jamais un second mécanisme.
const PISTOL_GRIP_BONE := "PistolGrip"
const FP_CAMERA_BONE := "FPCamera"
const WEAPON_ATTACHMENT_NAME := "WeaponGripAttachment"
## Tâche "utilitaires" (contrat lead) : os enfant de la main GAUCHE (celle qui
## tient la grenade pendant l'armement, l'arme restant tenue à droite) où le
## mesh de la grenade tenue s'attache, transform locale IDENTITÉ (contrairement
## à `attach_weapon`, qui contre-échelle : le placeholder de grenade est déjà
## modélisé à l'échelle du rig, voir ThrownUtility._build_*_mesh). Livré par
## le lead EN PARALLÈLE des clips FP_Throw_* (voir `_THROW_CLIPS`) — jamais un
## critère d'échec de `load()`, tolérance identique (`has_grenade_grip`).
const GRENADE_GRIP_BONE := "GrenadeGrip"
const GRENADE_ATTACHMENT_NAME := "GrenadeGripAttachment"
## Grenade tenue en vue FPS : un peu plus grosse que nature (x1,5) et sortie de la
## paume (+Y de l'os, en unités du rig), sinon la grosse main de la grenouille la
## cachait entièrement (revue captures 2026-09-27). Le projectile lancé garde la
## taille réelle.
const HELD_GRENADE_FP_SCALE := 1.5
const HELD_GRENADE_PALM_OFFSET := Vector3(0.0, 0.012, 0.0)

const _CLIPS := ["FP_Idle", "FP_ADS", "FP_ADS_In", "FP_Fire", "FP_Reload", "FP_Draw", "FP_Sprint", "FP_Inspect"]

## Jeu de clips par ARME (tâche "revolver" 2026-09-27, design verrouillé
## utilisateur) — clé LOGIQUE (utilisée par `_build_tree`, indépendante du nom
## réel du clip) -> nom du clip dans `_anim_player` + os d'attache. RAVAGE
## (historique, os "WeaponGrip") reste le jeu PAR DÉFAUT (arme de départ,
## slot 1) ; REVOLVER (os "PistolGrip") n'est utilisé QUE si les DEUX
## conditions tiennent : les 7 clips FPP_* existent ET l'os "PistolGrip"
## existe (voir `_has_revolver_clip_set`/`use_weapon_clip_set`) — sinon repli
## silencieux sur RAVAGE (attache WeaponGrip, clips FP_*), exactement comme
## `_has_throw_clips` pour le lancer d'utilitaire. "fan" vide ("") côté RAVAGE :
## le Ravage n'a pas de fan_fire_rate (WeaponConfig), `trigger_fan` ci-dessous
## n'est donc jamais appelée pour lui (voir Weapon.gd/ViewModel.gd) — la clé
## existe quand même pour que `_apply_clip_set` ait un nom à assigner au nœud
## "FanClip" (jamais lu tant qu'il n'est pas déclenché).
const CLIP_SET_RAVAGE := {
	"idle": "FP_Idle", "ads_in": "FP_ADS_In", "fire": "FP_Fire", "fan": "FP_Fire",
	"reload": "FP_Reload", "draw": "FP_Draw", "inspect": "FP_Inspect",
	"grip_bone": WEAPON_GRIP_BONE,
}
const CLIP_SET_REVOLVER := {
	"idle": "FPP_Idle", "ads_in": "FPP_ADS_In", "fire": "FPP_Fire", "fan": "FPP_Fan",
	"reload": "FPP_Reload", "draw": "FPP_Draw", "inspect": "FPP_Inspect",
	"grip_bone": PISTOL_GRIP_BONE,
}
## Les 7 clips requis pour bascule vers CLIP_SET_REVOLVER (voir sa doc) — même
## discipline que `_CLIPS`/`_THROW_CLIPS` : vérifiés ENSEMBLE, jamais l'un sans
## les autres.
const _REVOLVER_CLIPS := ["FPP_Idle", "FPP_ADS_In", "FPP_Fire", "FPP_Fan", "FPP_Reload", "FPP_Draw", "FPP_Inspect"]
## Lancer d'utilitaire (frag/flash/smoke, tâche "utilitaires") — DÉLIBÉRÉMENT
## absents de `_CLIPS` ci-dessus (jamais un critère d'échec de `load()`, voir
## sa docstring) : le lead livre ces deux clips EN PARALLÈLE de cette tâche,
## et `load()` ne doit surtout pas régresser (repli sur les gants flottants,
## voir la docstring de classe) tant qu'ils ne sont pas encore dans le glb.
## `FP_Throw_Ready` : pose statique tenue tant que la touche de lancer est
## maintenue (bras cocké en arrière). `FP_Throw` : le geste de lancer,
## ≈0,4 s, joué au relâchement. Vérifiés ENSEMBLE après un `load()` réussi
## (voir `_build_tree`) — jamais l'un sans l'autre : une pose "prêt" sans
## geste de lancer (ou l'inverse) n'aurait aucun sens.
const _THROW_CLIPS := ["FP_Throw_Ready", "FP_Throw"]
## FP_ADS_In : passage hanche -> visée (1 s, chaque image calculée mains sur l'arme, voir
## art/.../anim/fp.py). On ne le joue pas : on se place à l'instant = avancement de la visée.
const _ADS_IN := "FP_ADS_In"
## Au-delà de cet avancement, la pose de visée remplace entièrement la respiration de repos.
const _ADS_HANDOVER := 0.2

const _FIRE_FADE_IN := 0.02
const _FIRE_FADE_OUT := 0.05
const _RELOAD_FADE_IN := 0.05
const _RELOAD_FADE_OUT := 0.1
const _DRAW_FADE_IN := 0.02
const _DRAW_FADE_OUT := 0.1
const _INSPECT_FADE_IN := 0.1
const _INSPECT_FADE_OUT := 0.15

var _loaded: bool = false
var _model_root: Node3D
var _skeleton: Skeleton3D
var _anim_player: AnimationPlayer
var _tree: AnimationTree
var _weapon_attachment: BoneAttachment3D
var _grenade_attachment: BoneAttachment3D
var _fp_camera_bone_idx: int = -1
var _fp_camera_rest: Transform3D = Transform3D.IDENTITY
var _ads_in_length: float = 1.0
## Vrai seulement si LES DEUX clips de `_THROW_CLIPS` sont présents (voir sa
## docstring) — pilote le câblage optionnel du lancer dans `_build_tree` et le
## no-op défensif de `set_throw_ready`/`trigger_throw`.
var _has_throw_clips: bool = false
## Jeu de clips ACTIF (voir CLIP_SET_RAVAGE/CLIP_SET_REVOLVER) — RAVAGE par
## défaut (arme de départ, slot 1). Changé par `use_weapon_clip_set`, jamais
## directement.
var _active_clip_set: Dictionary = CLIP_SET_RAVAGE
## Vrai seulement si les 7 clips FPP_* ET l'os "PistolGrip" sont TOUS présents
## (voir `_REVOLVER_CLIPS`/`PISTOL_GRIP_BONE`) — calculé UNE FOIS dans `load()`,
## jamais réévalué ensuite (le glb ne change pas en cours de partie). Pilote le
## repli silencieux de `use_weapon_clip_set` sur CLIP_SET_RAVAGE tant que le
## lead n'a pas encore livré ces clips/cet os.
var _has_revolver_clip_set: bool = false

func is_loaded() -> bool:
	return _loaded

## Charge `path` (par défaut DEFAULT_PATH), construit le squelette/
## AnimationTree/BoneAttachment3D et applique le style BD (ToonStyle.gd).
## `false` sur TOUT échec (ressource absente, scène invalide, squelette/os
## FPCamera introuvables) -- jamais d'exception, jamais d'état à moitié
## construit : l'appelant (ViewModel.gd) retombe alors sur les gants
## flottants historiques (voir la docstring de classe).
func load(path: String = DEFAULT_PATH) -> bool:
	_loaded = false
	if not ResourceLoader.exists(path):
		push_warning("FPArmsRig : introuvable (%s)" % path)
		return false
	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		push_warning("FPArmsRig : PackedScene invalide (%s)" % path)
		return false
	var instance := packed.instantiate() as Node3D
	if instance == null:
		push_warning("FPArmsRig : instanciation impossible (%s)" % path)
		return false
	_skeleton = instance.find_child("Skeleton3D", true, false) as Skeleton3D
	_anim_player = instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _skeleton == null or _anim_player == null:
		push_warning("FPArmsRig : Skeleton3D/AnimationPlayer introuvable(s) dans %s" % path)
		instance.queue_free()
		return false
	_fp_camera_bone_idx = _skeleton.find_bone(FP_CAMERA_BONE)
	if _fp_camera_bone_idx < 0:
		push_warning("FPArmsRig : os \"%s\" introuvable dans %s" % [FP_CAMERA_BONE, path])
		instance.queue_free()
		return false
	if _skeleton.find_bone(WEAPON_GRIP_BONE) < 0:
		push_warning("FPArmsRig : os \"%s\" introuvable dans %s" % [WEAPON_GRIP_BONE, path])
		instance.queue_free()
		return false
	for clip in _CLIPS:
		if not _anim_player.has_animation(clip):
			push_warning("FPArmsRig : clip \"%s\" manquant dans %s" % [clip, path])
			instance.queue_free()
			return false
	_fp_camera_rest = _skeleton.get_bone_global_rest(_fp_camera_bone_idx)
	# Tâche "revolver" (2026-09-27) : jeu de clips secondaire OPTIONNEL, jamais
	# un critère d'échec de `load()` (même tolérance que `_has_throw_clips`) —
	# vérifié ENSEMBLE (les 7 clips ET l'os "PistolGrip"), jamais partiellement.
	_has_revolver_clip_set = _skeleton.find_bone(PISTOL_GRIP_BONE) >= 0
	if _has_revolver_clip_set:
		for clip in _REVOLVER_CLIPS:
			if not _anim_player.has_animation(clip):
				_has_revolver_clip_set = false
				break
	_active_clip_set = CLIP_SET_RAVAGE
	_model_root = instance
	add_child(_model_root)
	ToonStyle.apply_to(_model_root)
	_set_loops()
	_build_tree()
	_tree.set("parameters/ADSFreeze/scale", 0.0)
	if _anim_player.has_animation(_ADS_IN):
		_ads_in_length = _anim_player.get_animation(_ADS_IN).length
	_loaded = true
	return true

## Clips en boucle (l'import glTF les laisse en lecture unique : la respiration
## figeait) — "FPP_Idle" (contrat lead, tâche "revolver" 2026-09-27) au même
## titre que "FP_Idle"/"FP_Sprint", même repli silencieux si absent (`_set_loops`
## ignore un nom que `_anim_player` n'a pas).
const _LOOPING := ["FP_Idle", "FP_Sprint", "FPP_Idle"]

## Vrai si le jeu de clips REVOLVER (FPP_*/"PistolGrip") est disponible sur le
## glb chargé — exposé pour ViewModel.gd/les tests (voir `use_weapon_clip_set`).
func has_revolver_clip_set() -> bool:
	return _has_revolver_clip_set

## Nom de clip actuellement pointé pour la clé logique `key` ("idle"/"ads_in"/
## "fire"/"fan"/"reload"/"draw"/"inspect"/"grip_bone") — exposé pour les tests
## (tests/player/test_fp_arms_rig_revolver.gd), sans dupliquer la connaissance
## du graphe de blend côté test. "" si `key` est inconnue.
func active_clip_name(key: String) -> String:
	return _active_clip_set.get(key, "")

func _set_loops() -> void:
	for n in _LOOPING:
		if _anim_player and _anim_player.has_animation(n):
			_anim_player.get_animation(n).loop_mode = Animation.LOOP_LINEAR

func has_clip(clip_name: String) -> bool:
	return _anim_player != null and _anim_player.has_animation(clip_name)

## Durée (s) authored d'un clip -- utile aux outils de capture (voir
## tools/rigging/capture_frog_cowboy_fp.gd, qui vise une progression en %
## d'un clip donné, ex. mi-inspection) pour ne jamais dupliquer une durée en
## dur qui divergerait si le clip est réexporté. `0.0` si le rig n'est pas
## chargé ou si le clip est inconnu.
func clip_length(clip_name: String) -> float:
	if not has_clip(clip_name):
		return 0.0
	return _anim_player.get_animation(clip_name).length

## Transform MONDE actuelle de l'os "FPCamera" (pose COURANTE, pas le repos --
## utile pour les tests d'intégration, voir tests/player/test_fp_arms_rig.gd).
func fp_camera_global_pose() -> Transform3D:
	if _skeleton == null or _fp_camera_bone_idx < 0:
		return global_transform
	return _skeleton.global_transform * _skeleton.get_bone_global_rest(_fp_camera_bone_idx)

## Place CE nœud (voir FPArmsMath.align_rig_transform pour la preuve) pour
## que l'os "FPCamera" coïncide avec `camera` -- `proc_offset` (transform
## LOCALE À LA CAMÉRA, ex. sway/bob/recul) et `fov_scale` (compensation de FOV,
## voir ViewModel._fov_scale) sont composés dans la caméra "virtuelle" utilisée
## pour l'alignement, PAS appliqués séparément : c'est ce qui porte le "feel"
## procédural par-dessus le rig sans jamais bouger un os individuellement
## (requirement 1 du contrat de tâche).
func align_to_camera(camera: Camera3D, proc_offset: Transform3D, fov_scale: float) -> void:
	if camera == null:
		return
	var virtual_camera := camera.global_transform * proc_offset
	var effective_scale: float = FPArmsMath.RIG_SCALE * maxf(fov_scale, 0.0001)
	global_transform = FPArmsMath.align_rig_transform(_fp_camera_rest, virtual_camera, effective_scale)

## Pose (une seule fois, idempotent) une BoneAttachment3D sur l'os d'attache du
## jeu de clips ACTIF ("WeaponGrip" ou "PistolGrip", voir `_active_clip_set`/
## `use_weapon_clip_set` -- tâche "revolver" 2026-09-27) et y attache `model`
## avec une transform locale IDENTITÉ + la contre-échelle nécessaire (voir la
## docstring de classe). Détache l'arme PRÉCÉDENTE sans la libérer
## (`remove_child`, pas `queue_free` -- ViewModel._refresh_model garde la
## responsabilité du cycle de vie de `_model`, exactement comme pour l'ancien
## chemin gants/`_place_weapon`).
##
## Suppose `align_to_camera` déjà appelé AU MOINS UNE FOIS (c'est CE nœud, pas
## un enfant à échelle fixe, qui porte RIG_SCALE dans la magnitude de sa propre
## base -- voir la preuve FPArmsMath) : la contre-échelle posée ici est un
## FACTEUR FIXE (1/RIG_SCALE), correct dès que `global_transform` reflète bien
## RIG_SCALE. En jeu, ViewModel._process appelle `align_to_camera` CHAQUE
## frame avant tout rendu, donc toujours avant que l'arme ne soit visible à
## l'écran, même si `attach_weapon` est appelé plus tôt dans la même frame
## (ex. juste après `load()`).
func attach_weapon(model: Node3D) -> void:
	if model == null:
		return
	var attach := _ensure_weapon_attachment()
	for c in attach.get_children():
		attach.remove_child(c)
	var old_parent := model.get_parent()
	if old_parent and old_parent != attach:
		old_parent.remove_child(model)
	if model.get_parent() != attach:
		attach.add_child(model)
	model.owner = null
	model.transform = Transform3D.IDENTITY
	model.scale = FPArmsMath.weapon_counter_scale(FPArmsMath.RIG_SCALE)

func _ensure_weapon_attachment() -> BoneAttachment3D:
	var grip_bone: String = _active_clip_set["grip_bone"]
	if _weapon_attachment != null:
		# Tâche "revolver" : ré-affecte le MÊME nœud si l'os d'attache a changé
		# depuis la dernière fois (bascule Ravage <-> Revolver) -- jamais un
		# second BoneAttachment3D, `BoneAttachment3D.bone_name` peut être
		# réassigné à chaud.
		if _weapon_attachment.bone_name != grip_bone:
			_weapon_attachment.bone_name = grip_bone
		return _weapon_attachment
	_weapon_attachment = BoneAttachment3D.new()
	_weapon_attachment.name = WEAPON_ATTACHMENT_NAME
	_skeleton.add_child(_weapon_attachment)
	_weapon_attachment.bone_name = grip_bone
	return _weapon_attachment

## Vrai si le jeu de clips ACTIF est CLIP_SET_REVOLVER (FPP_*/"PistolGrip") —
## ViewModel.gd s'en sert pour savoir s'il doit déclencher `trigger_fire`/
## `trigger_fan` (le Ravage, historiquement, NE joue AUCUN clip de tir sur les
## bras -- FP_Fire remplaçait la pose de visée et faisait sauter l'arme, voir
## ViewModel._on_fired -- seul le Revolver, avec ses clips FPP_Fire/FPP_Fan
## dédiés, doit les déclencher).
func is_using_revolver_clip_set() -> bool:
	return _active_clip_set == CLIP_SET_REVOLVER

## Vrai si le glb chargé expose déjà l'os "GrenadeGrip" (voir sa docstring) —
## UtilityThrower/ViewModel.gd s'en servent pour savoir s'ils doivent tenter
## d'attacher un placeholder de grenade, plutôt que de deviner depuis
## `attach_grenade` qui échouerait silencieusement de toute façon.
func has_grenade_grip() -> bool:
	return _loaded and _skeleton != null and _skeleton.find_bone(GRENADE_GRIP_BONE) >= 0

## Attache `model` sous "GrenadeGrip" : orientation IDENTITÉ (os : +Y = haut de la
## grenade, sortant de la paume) et, comme `attach_weapon`, contre-échelle du rig
## (grenades modélisées à l'échelle réelle ; sans elle, frag de 20 cm dans la main),
## puis HELD_GRENADE_FP_SCALE / HELD_GRENADE_PALM_OFFSET pour la lisibilité.
## No-op silencieux si l'os n'existe pas encore.
func attach_grenade(model: Node3D) -> void:
	if model == null or not has_grenade_grip():
		return
	if _grenade_attachment == null:
		_grenade_attachment = BoneAttachment3D.new()
		_grenade_attachment.name = GRENADE_ATTACHMENT_NAME
		_skeleton.add_child(_grenade_attachment)
		_grenade_attachment.bone_name = GRENADE_GRIP_BONE
	for c in _grenade_attachment.get_children():
		_grenade_attachment.remove_child(c)
	var old_parent := model.get_parent()
	if old_parent and old_parent != _grenade_attachment:
		old_parent.remove_child(model)
	if model.get_parent() != _grenade_attachment:
		_grenade_attachment.add_child(model)
	model.owner = null
	model.transform = Transform3D.IDENTITY
	model.position = HELD_GRENADE_PALM_OFFSET
	model.scale = FPArmsMath.weapon_counter_scale(FPArmsMath.RIG_SCALE) * HELD_GRENADE_FP_SCALE

## Retire (sans libérer) tout mesh actuellement attaché à "GrenadeGrip" —
## l'appelant (ViewModel.gd) garde la responsabilité de libérer le nœud.
func detach_grenade() -> void:
	if _grenade_attachment == null:
		return
	for c in _grenade_attachment.get_children():
		_grenade_attachment.remove_child(c)

# ---------------------------------------------------------------- AnimationTree
func _build_tree() -> void:
	_tree = AnimationTree.new()
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim_player)

	var bt := AnimationNodeBlendTree.new()

	# Hanche <-> visée : mélanger deux poses IK éloignées faisait lâcher l'arme, et des poses
	# intermédiaires donnaient un rendu saccadé. On se place dans FP_ADS_In (figé, TimeScale 0)
	# à l'instant voulu : chaque état intermédiaire est une vraie pose, mains sur l'arme.
	# Tâche "revolver" (2026-09-27) : les noms de clip viennent de `_active_clip_set`
	# (RAVAGE par défaut à la construction, voir `load()`) — `use_weapon_clip_set`
	# RE-POINTE ces mêmes nœuds ensuite (jamais un second arbre reconstruit).
	var idle := AnimationNodeAnimation.new()
	idle.animation = _active_clip_set["idle"]
	bt.add_node("Idle", idle)
	var ads_in := AnimationNodeAnimation.new()
	ads_in.animation = _active_clip_set["ads_in"]
	bt.add_node("ADSIn", ads_in)
	var ads_freeze := AnimationNodeTimeScale.new()
	bt.add_node("ADSFreeze", ads_freeze)
	bt.connect_node("ADSFreeze", 0, "ADSIn")
	var ads_seek := AnimationNodeTimeSeek.new()
	bt.add_node("ADSSeek", ads_seek)
	bt.connect_node("ADSSeek", 0, "ADSFreeze")
	var idle_ads := AnimationNodeBlend2.new()
	# `sync` : la branche visée est évaluée même à poids nul. Sinon, à la 1re frame de visée,
	# elle n'avait pas encore reçu sa position (seek) et sortait la pose de REPOS du squelette
	# (bras en A, arme de travers) : un flash d'une frame.
	idle_ads.sync = true
	bt.add_node("IdleAds", idle_ads)
	bt.connect_node("IdleAds", 0, "Idle")
	bt.connect_node("IdleAds", 1, "ADSSeek")

	var sprint := AnimationNodeAnimation.new()
	sprint.animation = "FP_Sprint"
	bt.add_node("SprintClip", sprint)
	var sprint_blend := AnimationNodeBlend2.new()
	bt.add_node("SprintBlend", sprint_blend)
	bt.connect_node("SprintBlend", 0, "IdleAds")
	bt.connect_node("SprintBlend", 1, "SprintClip")

	var fire := AnimationNodeAnimation.new()
	fire.animation = _active_clip_set["fire"]
	bt.add_node("FireClip", fire)
	var fire_shot := AnimationNodeOneShot.new()
	fire_shot.fadein_time = _FIRE_FADE_IN
	fire_shot.fadeout_time = _FIRE_FADE_OUT
	bt.add_node("FireShot", fire_shot)
	bt.connect_node("FireShot", 0, "SprintBlend")
	bt.connect_node("FireShot", 1, "FireClip")

	# Tir FAN ("fan the hammer", tâche "revolver" 2026-09-27) — nœud TOUJOURS
	# câblé (même pour le Ravage, qui n'a pas de clip fan) : `trigger_fan`
	# n'est de toute façon jamais appelée pour une arme sans `fan_fire_rate`
	# (voir Weapon.gd/ViewModel.gd), donc ce one-shot ne se déclenche jamais
	# pour elle — pas besoin d'un second arbre conditionnel comme le lancer
	# d'utilitaire (`_has_throw_clips`) : `_active_clip_set["fan"]` vaut
	# "FP_Fire" pour le Ravage (jamais lu, voir la doc de CLIP_SET_RAVAGE).
	var fan := AnimationNodeAnimation.new()
	fan.animation = _active_clip_set["fan"]
	bt.add_node("FanClip", fan)
	var fan_shot := AnimationNodeOneShot.new()
	fan_shot.fadein_time = _FIRE_FADE_IN
	fan_shot.fadeout_time = _FIRE_FADE_OUT
	bt.add_node("FanShot", fan_shot)
	bt.connect_node("FanShot", 0, "FireShot")
	bt.connect_node("FanShot", 1, "FanClip")

	var reload := AnimationNodeAnimation.new()
	reload.animation = _active_clip_set["reload"]
	bt.add_node("ReloadClip", reload)
	var reload_speed := AnimationNodeTimeScale.new()
	bt.add_node("ReloadSpeed", reload_speed)
	bt.connect_node("ReloadSpeed", 0, "ReloadClip")
	var reload_shot := AnimationNodeOneShot.new()
	reload_shot.fadein_time = _RELOAD_FADE_IN
	reload_shot.fadeout_time = _RELOAD_FADE_OUT
	bt.add_node("ReloadShot", reload_shot)
	bt.connect_node("ReloadShot", 0, "FanShot")
	bt.connect_node("ReloadShot", 1, "ReloadSpeed")

	var draw := AnimationNodeAnimation.new()
	draw.animation = _active_clip_set["draw"]
	bt.add_node("DrawClip", draw)
	var draw_shot := AnimationNodeOneShot.new()
	draw_shot.fadein_time = _DRAW_FADE_IN
	draw_shot.fadeout_time = _DRAW_FADE_OUT
	bt.add_node("DrawShot", draw_shot)
	bt.connect_node("DrawShot", 0, "ReloadShot")
	bt.connect_node("DrawShot", 1, "DrawClip")

	var inspect := AnimationNodeAnimation.new()
	inspect.animation = _active_clip_set["inspect"]
	bt.add_node("InspectClip", inspect)
	var inspect_shot := AnimationNodeOneShot.new()
	inspect_shot.fadein_time = _INSPECT_FADE_IN
	inspect_shot.fadeout_time = _INSPECT_FADE_OUT
	bt.add_node("InspectShot", inspect_shot)
	bt.connect_node("InspectShot", 0, "DrawShot")
	bt.connect_node("InspectShot", 1, "InspectClip")

	# Lancer d'utilitaire — optionnel, voir `_THROW_CLIPS`/`_has_throw_clips` :
	# câblé SEULEMENT si les deux clips existent déjà dans le glb, sinon la
	# sortie reste directement sur InspectShot comme avant cette tâche.
	_has_throw_clips = _anim_player.has_animation(_THROW_CLIPS[0]) and _anim_player.has_animation(_THROW_CLIPS[1])
	var last_node := "InspectShot"
	if _has_throw_clips:
		var throw_ready := AnimationNodeAnimation.new()
		throw_ready.animation = _THROW_CLIPS[0]
		bt.add_node("ThrowReadyClip", throw_ready)
		var throw_ready_blend := AnimationNodeBlend2.new()
		throw_ready_blend.sync = true
		bt.add_node("ThrowReadyBlend", throw_ready_blend)
		bt.connect_node("ThrowReadyBlend", 0, "InspectShot")
		bt.connect_node("ThrowReadyBlend", 1, "ThrowReadyClip")

		var throw_clip := AnimationNodeAnimation.new()
		throw_clip.animation = _THROW_CLIPS[1]
		bt.add_node("ThrowClip", throw_clip)
		var throw_shot := AnimationNodeOneShot.new()
		throw_shot.fadein_time = _INSPECT_FADE_IN
		throw_shot.fadeout_time = _INSPECT_FADE_OUT
		bt.add_node("ThrowShot", throw_shot)
		bt.connect_node("ThrowShot", 0, "ThrowReadyBlend")
		bt.connect_node("ThrowShot", 1, "ThrowClip")
		last_node = "ThrowShot"

	bt.connect_node("output", 0, last_node)

	_tree.tree_root = bt
	_tree.active = true

## Lit un paramètre de l'AnimationTree interne (ex.
## "parameters/IdleAds/blend_amount") -- utilisé par les tests d'intégration
## (tests/player/test_fp_arms_rig.gd) pour vérifier le câblage sans dupliquer
## l'arbre de blend. `null` si le rig n'est pas chargé.
func get_tree_param(path: String) -> Variant:
	return _tree.get(path) if _tree else null

## Bascule vers le jeu de clips REVOLVER (FPP_*/"PistolGrip") si `want_revolver`
## est vrai ET que `_has_revolver_clip_set` (voir `load()`) — repli SILENCIEUX
## sur CLIP_SET_RAVAGE sinon (WeaponGrip/FP_*), même discipline que
## `_has_throw_clips`/`set_throw_ready` : le lead peut livrer les clips FPP_*/
## l'os "PistolGrip" progressivement, jamais un plantage entre-temps.
## No-op si déjà sur le jeu demandé (évite de re-pointer les nœuds/relire
## `clip_length` à chaque frame — l'appelant, ViewModel._refresh_model, rappelle
## cette fonction à CHAQUE changement d'arme, pas seulement quand le jeu
## change réellement). À appeler AVANT `attach_weapon` : l'os d'attache doit
## déjà être le bon quand l'arme est reparentée (voir `_ensure_weapon_attachment`).
func use_weapon_clip_set(want_revolver: bool) -> void:
	var target: Dictionary = CLIP_SET_REVOLVER if (want_revolver and _has_revolver_clip_set) else CLIP_SET_RAVAGE
	if target == _active_clip_set:
		return
	_active_clip_set = target
	_apply_active_clip_names()

## Re-pointe (jamais ne reconstruit) chaque `AnimationNodeAnimation` du
## graphe de blend sur le nom de clip du jeu `_active_clip_set` COURANT — la
## topologie du graphe (`_build_tree`, construite UNE FOIS) reste identique
## pour toute arme FP, seuls les NOMS de clip diffèrent (contrat de tâche :
## "a per-weapon clip-name map, and a rebuilt or re-pointed AnimationTree").
func _apply_active_clip_names() -> void:
	if _tree == null:
		return
	var bt := _tree.tree_root as AnimationNodeBlendTree
	if bt == null:
		return
	_point_clip(bt, "Idle", "idle")
	_point_clip(bt, "ADSIn", "ads_in")
	_point_clip(bt, "FireClip", "fire")
	_point_clip(bt, "FanClip", "fan")
	_point_clip(bt, "ReloadClip", "reload")
	_point_clip(bt, "DrawClip", "draw")
	_point_clip(bt, "InspectClip", "inspect")
	var ads_in_name: String = _active_clip_set["ads_in"]
	if _anim_player and _anim_player.has_animation(ads_in_name):
		_ads_in_length = _anim_player.get_animation(ads_in_name).length

func _point_clip(bt: AnimationNodeBlendTree, node_name: String, clip_set_key: String) -> void:
	var node := bt.get_node(node_name) as AnimationNodeAnimation
	if node:
		node.animation = _active_clip_set[clip_set_key]

## `amount` est DÉJÀ la valeur de blend voulue (0 = FP_Idle, 1 = FP_ADS) --
## l'appelant (ViewModel._process) la dérive de `_ads_t` via
## `FPArmsMath.ads_blend_amount`, jamais recalculée ici (séparation maths
## pures / câblage, voir la docstring de classe).
func set_ads_amount(amount: float) -> void:
	if _tree:
		var u := clampf(amount, 0.0, 1.0)
		_tree.set("parameters/IdleAds/blend_amount", clampf(u / _ADS_HANDOVER, 0.0, 1.0))
		_tree.set("parameters/ADSSeek/seek_request", u * _ads_in_length)

func set_sprint_amount(t: float) -> void:
	if _tree:
		_tree.set("parameters/SprintBlend/blend_amount", clampf(t, 0.0, 1.0))

func trigger_fire() -> void:
	if _tree:
		_tree.set("parameters/FireShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## Tir FAN ("fan the hammer", tâche "revolver" 2026-09-27) — l'appelant
## (ViewModel.gd) ne la rappelle QUE pour une arme `fan_fire_rate > 0`
## (Weapon.gd), donc en pratique seulement quand CLIP_SET_REVOLVER est déjà
## actif ; la garde ci-dessous reste défensive (jamais de tir fan déclenché
## sur le jeu de clips Ravage, qui n'a pas de clip dédié).
func trigger_fan() -> void:
	if _tree and _active_clip_set == CLIP_SET_REVOLVER:
		_tree.set("parameters/FanShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

## `reload_time` (WeaponConfig.reload_time) réparti sur la durée AUTHORED
## réelle du clip de rechargement ACTIF (`_active_clip_set["reload"]`, mesurée
## via `clip_length` -- jamais une référence unique en dur qui suppose un seul
## clip possible, contrairement à avant la tâche "revolver" : FP_Reload et
## FPP_Reload n'ont pas forcément la même durée authored).
func trigger_reload(reload_time: float) -> void:
	if _tree == null:
		return
	var clip_len := clip_length(_active_clip_set["reload"])
	if clip_len <= 0.0:
		clip_len = FPArmsMath.RELOAD_CLIP_REFERENCE_DURATION_S
	_tree.set("parameters/ReloadSpeed/scale", FPArmsMath.reload_speed_for(reload_time, clip_len))
	_tree.set("parameters/ReloadShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func trigger_draw() -> void:
	if _tree:
		_tree.set("parameters/DrawShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func trigger_inspect() -> void:
	if _tree:
		_tree.set("parameters/InspectShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func cancel_inspect() -> void:
	if _tree:
		_tree.set("parameters/InspectShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)

## Vrai si `FP_Throw_Ready`/`FP_Throw` sont chargés et câblés (voir
## `_THROW_CLIPS`) — UtilityThrower.gd s'en sert pour savoir s'il doit driver
## la pose de préparation, plutôt que de deviner depuis `has_clip` deux fois.
func has_throw_clips() -> bool:
	return _has_throw_clips

## Pose "prêt à lancer" (bras cocké) — maintenue tant que `active` est vrai
## (touche de lancer enfoncée), no-op si les clips ne sont pas chargés.
func set_throw_ready(active: bool) -> void:
	if _tree and _has_throw_clips:
		_tree.set("parameters/ThrowReadyBlend/blend_amount", 1.0 if active else 0.0)

## Geste de lancer (≈0,4 s, joué au relâchement de la touche) — no-op si les
## clips ne sont pas chargés (voir docstring de `_THROW_CLIPS`).
func trigger_throw() -> void:
	if _tree and _has_throw_clips:
		_tree.set("parameters/ThrowShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
