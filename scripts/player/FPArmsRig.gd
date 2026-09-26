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
const FP_CAMERA_BONE := "FPCamera"
const WEAPON_ATTACHMENT_NAME := "WeaponGripAttachment"

const _CLIPS := ["FP_Idle", "FP_ADS", "FP_ADS_In", "FP_Fire", "FP_Reload", "FP_Draw", "FP_Sprint", "FP_Inspect"]
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
var _fp_camera_bone_idx: int = -1
var _fp_camera_rest: Transform3D = Transform3D.IDENTITY
var _ads_in_length: float = 1.0

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

## Clips en boucle (l'import glTF les laisse en lecture unique : la respiration figeait).
const _LOOPING := ["FP_Idle", "FP_Sprint"]

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

## Pose (une seule fois, idempotent) une BoneAttachment3D sur "WeaponGrip" et
## y attache `model` avec une transform locale IDENTITÉ + la contre-échelle
## nécessaire (voir la docstring de classe). Détache l'arme PRÉCÉDENTE sans la
## libérer (`remove_child`, pas `queue_free` -- ViewModel._refresh_model garde
## la responsabilité du cycle de vie de `_model`, exactement comme pour
## l'ancien chemin gants/`_place_weapon`).
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
	if _weapon_attachment != null:
		return _weapon_attachment
	_weapon_attachment = BoneAttachment3D.new()
	_weapon_attachment.name = WEAPON_ATTACHMENT_NAME
	_skeleton.add_child(_weapon_attachment)
	_weapon_attachment.bone_name = WEAPON_GRIP_BONE
	return _weapon_attachment

# ---------------------------------------------------------------- AnimationTree
func _build_tree() -> void:
	_tree = AnimationTree.new()
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim_player)

	var bt := AnimationNodeBlendTree.new()

	# Hanche <-> visée : mélanger deux poses IK éloignées faisait lâcher l'arme, et des poses
	# intermédiaires donnaient un rendu saccadé. On se place dans FP_ADS_In (figé, TimeScale 0)
	# à l'instant voulu : chaque état intermédiaire est une vraie pose, mains sur l'arme.
	var idle := AnimationNodeAnimation.new()
	idle.animation = "FP_Idle"
	bt.add_node("Idle", idle)
	var ads_in := AnimationNodeAnimation.new()
	ads_in.animation = _ADS_IN
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
	fire.animation = "FP_Fire"
	bt.add_node("FireClip", fire)
	var fire_shot := AnimationNodeOneShot.new()
	fire_shot.fadein_time = _FIRE_FADE_IN
	fire_shot.fadeout_time = _FIRE_FADE_OUT
	bt.add_node("FireShot", fire_shot)
	bt.connect_node("FireShot", 0, "SprintBlend")
	bt.connect_node("FireShot", 1, "FireClip")

	var reload := AnimationNodeAnimation.new()
	reload.animation = "FP_Reload"
	bt.add_node("ReloadClip", reload)
	var reload_speed := AnimationNodeTimeScale.new()
	bt.add_node("ReloadSpeed", reload_speed)
	bt.connect_node("ReloadSpeed", 0, "ReloadClip")
	var reload_shot := AnimationNodeOneShot.new()
	reload_shot.fadein_time = _RELOAD_FADE_IN
	reload_shot.fadeout_time = _RELOAD_FADE_OUT
	bt.add_node("ReloadShot", reload_shot)
	bt.connect_node("ReloadShot", 0, "FireShot")
	bt.connect_node("ReloadShot", 1, "ReloadSpeed")

	var draw := AnimationNodeAnimation.new()
	draw.animation = "FP_Draw"
	bt.add_node("DrawClip", draw)
	var draw_shot := AnimationNodeOneShot.new()
	draw_shot.fadein_time = _DRAW_FADE_IN
	draw_shot.fadeout_time = _DRAW_FADE_OUT
	bt.add_node("DrawShot", draw_shot)
	bt.connect_node("DrawShot", 0, "ReloadShot")
	bt.connect_node("DrawShot", 1, "DrawClip")

	var inspect := AnimationNodeAnimation.new()
	inspect.animation = "FP_Inspect"
	bt.add_node("InspectClip", inspect)
	var inspect_shot := AnimationNodeOneShot.new()
	inspect_shot.fadein_time = _INSPECT_FADE_IN
	inspect_shot.fadeout_time = _INSPECT_FADE_OUT
	bt.add_node("InspectShot", inspect_shot)
	bt.connect_node("InspectShot", 0, "DrawShot")
	bt.connect_node("InspectShot", 1, "InspectClip")

	bt.connect_node("output", 0, "InspectShot")

	_tree.tree_root = bt
	_tree.active = true

## Lit un paramètre de l'AnimationTree interne (ex.
## "parameters/IdleAds/blend_amount") -- utilisé par les tests d'intégration
## (tests/player/test_fp_arms_rig.gd) pour vérifier le câblage sans dupliquer
## l'arbre de blend. `null` si le rig n'est pas chargé.
func get_tree_param(path: String) -> Variant:
	return _tree.get(path) if _tree else null

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

func trigger_reload(reload_time: float) -> void:
	if _tree == null:
		return
	_tree.set("parameters/ReloadSpeed/scale", FPArmsMath.reload_speed_for(reload_time))
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
