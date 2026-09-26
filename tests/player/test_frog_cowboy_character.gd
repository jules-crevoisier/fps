## test_frog_cowboy_character.gd
## Spec (intégration Frog Cowboy) : remplace Verrou (l'ancienne grenouille,
## assets/models/characters/verrou.glb) par le personnage peint de
## l'utilisateur (assets/models/characters/frog_cowboy.glb, rig Mixamo 65 os +
## un os `WeaponGrip`) pour les bots/joueurs distants/le corps du joueur — via
## renommage Godot des os ET des pistes d'animation vers les noms de profil
## humanoïde (scripts/import/FrogCowboyPostImport.gd +
## scripts/import/HumanoidBoneMap.gd).
##
## DÉCISION (lead, 2026-09-26) : le frog reçoit des animations NATIVES,
## authored en Blender et exportées DANS frog_cowboy.glb (19 clips livrés
## 2026-09-26, squelette 65 os Mixamo + `WeaponGrip`) — le chemin "retargeting
## UAL" (tools/rigging/bake_frog_animations.gd,
## resources/agents/anim/frog_cowboy_humanoid.tres) est abandonné POUR LE FROG
## (fichiers conservés sur disque, nettoyage prévu plus tard, jamais utilisés
## au runtime). `CharacterBody.get_anim_player()` expose désormais
## l'AnimationPlayer auto-généré par l'import glTF, ses pistes/loop_modes déjà
## traités par FrogCowboyPostImport (voir tests ci-dessous).
##
## Instances RÉELLES de scenes/player/player.tscn/scenes/characters/
## frog_cowboy.tscn (même méthode que tests/player/test_capsule_per_player.gd) :
## ce sont ces DEUX scènes qui doivent réellement se charger et s'assembler,
## pas seulement une fonction pure.
extends GdUnitTestSuite

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const FROG_SCENE_PATH := "res://scenes/characters/frog_cowboy.tscn"
const HumanoidBoneMap = preload("res://scripts/import/HumanoidBoneMap.gd")

var _next_offset_index := 0
var _next_peer_id := 101  # pairs "distants" simulés (jamais 1, jamais >= BOT_ID_START)


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


## Bot (autorité serveur, même méthode que test_capsule_per_player.gd::_bot_player) :
## AgentDatabase n'a qu'un seul agent ("Verrou") -> CharacterBody résout son
## modèle via CharacterBody.MODEL_OVERRIDE -> frog_cowboy.tscn.
func _bot_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.set("is_bot", true)
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


## Pair humain distant simulé (id < BOT_ID_START, jamais 1 — même méthode que
## test_capsule_per_player.gd::_remote_player) : `is_multiplayer_authority()`
## y est FAUX localement, exactement le cas où ThirdPersonWeapon.gd s'active
## (voir sa doc de classe, "inerte pour le joueur LOCAL" — un bot vu par le
## SERVEUR qui le simule a authority_id=1=local et ne l'active jamais, ce
## n'est donc PAS le bon double pour ce test précis).
func _remote_player(pos: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	player.name = str(_next_peer_id)
	_next_peer_id += 1
	player.position = pos
	player.set("spawn_point", pos)
	add_child(player)
	auto_free(player)
	return player


# ------------------------------------------------------------- CharacterBody.model_path_for

## Requirement "stop using Verrou for bots/remote players/player body" :
## fonction PURE (aucun changement pour les 5 autres agents Tripo).
func test_model_path_for_verrou_resolves_to_frog_cowboy_scene() -> void:
	assert_str(CharacterBody.model_path_for("verrou")).is_equal(FROG_SCENE_PATH)


func test_model_path_for_other_agents_is_unchanged() -> void:
	assert_str(CharacterBody.model_path_for("choc")).is_equal("res://assets/models/characters/choc.glb")
	assert_str(CharacterBody.model_path_for("vif")).is_equal("res://assets/models/characters/vif.glb")


# ------------------------------------------------------------------ scène éditable

## Requirement 5 : "Create scenes/characters/frog_cowboy.tscn" — une scène
## héritée du glb (chargeable indépendamment, pas seulement via CharacterBody).
func test_frog_cowboy_scene_loads() -> void:
	assert_bool(ResourceLoader.exists(FROG_SCENE_PATH)).is_true()
	var packed := load(FROG_SCENE_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var root := packed.instantiate()
	auto_free(root)
	assert_str(root.name).is_equal("frog_cowboy")


# --------------------------------------------------------- squelette humanoïde

## Requirement 8 : "skeleton exposes humanoid names (Hips, RightHand)" — le
## retargeting (BoneMap Mixamo -> SkeletonProfileHumanoid,
## FrogCowboyPostImport.gd) renomme les os mixamorig_* en noms de profil.
func test_skeleton_exposes_humanoid_bone_names() -> void:
	var packed := load(FROG_SCENE_PATH) as PackedScene
	var root := packed.instantiate()
	auto_free(root)
	var skeleton := root.get_node("Armature/Skeleton3D") as Skeleton3D
	assert_object(skeleton).is_not_null()
	assert_int(skeleton.find_bone("Hips")).append_failure_message(
		"squelette Frog Cowboy : os \"Hips\" introuvable — le renommage humanoïde a-t-il tourné ?"
	).is_greater_equal(0)
	assert_int(skeleton.find_bone("RightHand")).append_failure_message(
		"squelette Frog Cowboy : os \"RightHand\" introuvable"
	).is_greater_equal(0)
	# TOUS les os mappés (HumanoidBoneMap.MIXAMO_TO_HUMANOID) doivent avoir été
	# renommés -- les quelques os "bout de chaîne" sans équivalent humanoïde
	# (HeadTop_End, doigts "...4", voir la doc de HumanoidBoneMap) gardent
	# volontairement leur nom Mixamo brut, donc pas de garde "zéro mixamorig".
	for humanoid_name in HumanoidBoneMap.MIXAMO_TO_HUMANOID.values():
		assert_int(skeleton.find_bone(humanoid_name)).append_failure_message(
			"os de profil humanoïde manquant après retargeting : %s" % humanoid_name
		).is_greater_equal(0)


# ------------------------------------------------------------------- WeaponSocket

## Requirement (contrat GLB "native anim frog cowboy", 2026-09-26) : "a
## BoneAttachment3D on WeaponGrip containing a Node3D named WeaponSocket" —
## `WeaponGrip` (enfant de `RightHand`, axes pré-orientés canon-vers-l'avant
## par le lead) remplace l'ancien attachement direct sur `RightHand`.
func test_weapon_socket_exists_under_a_bone_attachment_on_weapon_grip() -> void:
	var packed := load(FROG_SCENE_PATH) as PackedScene
	var root := packed.instantiate()
	auto_free(root)
	var attach := root.get_node_or_null("Armature/Skeleton3D/BoneAttachment3D") as BoneAttachment3D
	assert_object(attach).append_failure_message(
		"BoneAttachment3D introuvable sous Armature/Skeleton3D"
	).is_not_null()
	assert_str(attach.bone_name).is_equal("WeaponGrip")
	var socket := attach.get_node_or_null("WeaponSocket")
	assert_object(socket).append_failure_message(
		"\"WeaponSocket\" introuvable sous le BoneAttachment3D de WeaponGrip"
	).is_not_null()
	assert_bool(socket is Node3D).is_true()


## Requirement 4 : "attach point coming from the character, not hard-coded" —
## ThirdPersonWeapon.gd doit trouver et utiliser CE nœud plutôt que de créer
## son propre BoneAttachment3D sur un nom d'os codé en dur.
func test_third_person_weapon_attaches_the_model_at_the_weapon_socket() -> void:
	# ThirdPersonWeapon.gd est inerte pour le joueur dont CE process a
	# l'autorité (voir sa doc de classe) — un bot simulé ici (comme
	# _bot_player) aurait authority_id=1=local et ne l'activerait jamais ;
	# un pair "distant" (_remote_player) reproduit le cas réel visé par la
	# requirement ("bots and remote players", vu par un AUTRE pair/le HUD).
	var player := _remote_player(_offset())
	# Modèle chargé de façon SYNCHRONE (CharacterBody._ready, voir sa doc) —
	# une frame physique laisse le temps à CharacterAnimator/ThirdPersonWeapon
	# de réagir au signal model_ready.
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Weapon._ready() diffuse le loadout de depart AVANT que ThirdPersonWeapon
	# (plus loin dans player.tscn) ait fini de se connecter a current_id_changed
	# -- course d'ordre de _ready() independante de cette tache (Weapon.gd hors
	# perimetre, lecture seule). _try_equip(0) est un no-op (deja sur ce slot) :
	# on rejoue directement le handler RPC (call_local) pour simuler la
	# diffusion, cette fois recue puisque ThirdPersonWeapon est deja connecte.
	var w := player.get_node("Weapon") as Weapon
	w._broadcast_current_id(w._inv.current_id())
	await get_tree().physics_frame

	var character_body := player.get_node("%CharacterModel") as CharacterBody
	assert_bool(character_body.is_model_ready()).append_failure_message(
		"préalable : le modèle Frog Cowboy doit être chargé"
	).is_true()

	var socket := character_body.find_child("WeaponSocket", true, false) as Node3D
	assert_object(socket).append_failure_message(
		"préalable : WeaponSocket doit exister sur le corps chargé"
	).is_not_null()

	var tp_weapon := player.get_node("ThirdPersonWeapon") as ThirdPersonWeapon
	var weapon_model: Node3D = tp_weapon.get("_model")
	assert_object(weapon_model).append_failure_message(
		"ThirdPersonWeapon n'a chargé aucun modèle d'arme (arme équipée manquante ?)"
	).is_not_null()
	assert_object(weapon_model.get_parent()).append_failure_message(
		"l'arme doit être rattachée SOUS WeaponSocket, pas sous un BoneAttachment3D codé en dur"
	).is_same(socket)


# --------------------------------------------------------------- animation (native, embarquée)

## Requirement (contrat GLB "native anim frog cowboy", clips livrés
## 2026-09-26) : les 19 clips embarqués dans frog_cowboy.glb sont exposés par
## l'AnimationPlayer auto-généré par l'import glTF (frère d'Armature),
## renommés (mixamorig_* -> humanoïde) et bouclés par FrogCowboyPostImport.
func test_frog_scene_exposes_every_contract_clip() -> void:
	var packed := load(FROG_SCENE_PATH) as PackedScene
	var root := packed.instantiate()
	auto_free(root)
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_object(ap).append_failure_message(
		"AnimationPlayer introuvable dans frog_cowboy.tscn -- le glb livré par le lead embarque pourtant 19 clips"
	).is_not_null()
	for clip in HumanoidBoneMap.FROG_FULL_BODY_CLIPS + HumanoidBoneMap.FROG_RIFLE_CLIPS:
		assert_bool(ap.has_animation(clip)).append_failure_message(
			"clip manquant sur l'AnimationPlayer de Frog Cowboy : \"%s\"" % clip
		).is_true()


## Contrat FrogCowboyPostImport._apply_loop_modes : les clips qui bouclent
## réellement en jeu ont `loop_mode == LOOP_LINEAR`, les one-shots gardent
## `LOOP_NONE` — quel que soit ce que l'export Blender a écrit dans le clip.
func test_frog_clips_have_the_contracted_loop_mode() -> void:
	var packed := load(FROG_SCENE_PATH) as PackedScene
	var root := packed.instantiate()
	auto_free(root)
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip in HumanoidBoneMap.FROG_LOOPING_CLIPS:
		assert_int(ap.get_animation(clip).loop_mode).append_failure_message(
			"\"%s\" doit boucler (LOOP_LINEAR)" % clip
		).is_equal(Animation.LOOP_LINEAR)
	for clip in ["Death01", "Rifle_Shoot", "Jump_Start", "Roll"]:
		assert_int(ap.get_animation(clip).loop_mode).append_failure_message(
			"\"%s\" est un one-shot, ne doit pas boucler" % clip
		).is_equal(Animation.LOOP_NONE)


## Requirement 1/8 : "playing a locomotion clip changes a bone pose (not stuck
## in T-pose)" — clip natif RÉEL (embarqué dans frog_cowboy.glb par le lead),
## piste renommée mixamorig_RightArm -> RightUpperArm par FrogCowboyPostImport.
func test_playing_a_locomotion_clip_moves_a_bone_away_from_rest() -> void:
	var packed := load(FROG_SCENE_PATH) as PackedScene
	var root := packed.instantiate()
	auto_free(root)
	get_tree().root.add_child(root)  # AnimationPlayer.play() a besoin d'être dans l'arbre.

	var skeleton := root.get_node("Armature/Skeleton3D") as Skeleton3D
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer

	var bone_idx := skeleton.find_bone("RightUpperArm")
	var rest_rotation := skeleton.get_bone_rest(bone_idx).basis.get_rotation_quaternion()
	ap.play("Walk")
	for i in 30:
		ap.advance(1.0 / 30.0)
	var posed_rotation := skeleton.get_bone_pose_rotation(bone_idx)

	assert_bool(posed_rotation.is_equal_approx(rest_rotation)).append_failure_message(
		"\"Walk\" ne bouge pas RightUpperArm — squelette resté figé en pose de repos (T-pose)"
	).is_false()
	root.get_parent().remove_child(root)


## Requirement 1 : le nouvel os `WeaponGrip` (contrat GLB, enfant de
## RightHand) est bien présent sur le squelette livré.
func test_skeleton_has_the_weapon_grip_bone() -> void:
	var packed := load(FROG_SCENE_PATH) as PackedScene
	var root := packed.instantiate()
	auto_free(root)
	var skeleton := root.get_node("Armature/Skeleton3D") as Skeleton3D
	assert_int(skeleton.find_bone("WeaponGrip")).append_failure_message(
		"os \"WeaponGrip\" introuvable sur le squelette Frog Cowboy"
	).is_greater_equal(0)


## Requirement 8 : un bot réel expose bien l'AnimationPlayer natif chargé (pas
## de plantage, `get_anim_player()` non nul maintenant que le glb embarque ses
## clips).
func test_bot_body_has_the_native_anim_player() -> void:
	var player := _bot_player(_offset())
	await get_tree().physics_frame
	await get_tree().physics_frame

	var character_body := player.get_node("%CharacterModel") as CharacterBody
	assert_bool(character_body.is_model_ready()).is_true()
	assert_object(character_body.get_anim_player()).append_failure_message(
		"AnimationPlayer natif attendu maintenant que frog_cowboy.glb embarque ses clips"
	).is_not_null()
	assert_str(character_body.get_model_name()).is_equal("frog_cowboy")


## Contrat CharacterAnimator.upper_body_clip_prefix : Frog Cowboy expose des
## clips Rifle_*, donc la bascule doit choisir ce préfixe (jamais Pistol_*
## pour ce personnage).
func test_bot_body_anim_player_exposes_rifle_clips_for_the_prefix_switch() -> void:
	var player := _bot_player(_offset())
	await get_tree().physics_frame
	await get_tree().physics_frame

	var character_body := player.get_node("%CharacterModel") as CharacterBody
	var ap := character_body.get_anim_player()
	assert_bool(ap.has_animation("Rifle_Idle")).is_true()
	assert_str(CharacterAnimator.upper_body_clip_prefix(ap.has_animation("Rifle_Idle"))).is_equal("Rifle_")


# ------------------------------------------------------------------- échelle de l'arme

## Addendum (2026-09-26) : CharacterBody remet le modèle du CORPS à l'échelle
## de TARGET_HEIGHT (souvent != 1 -- Frog Cowboy ≈1.8 pour son maillage source)
## ; WeaponSocket, descendant de ce modèle mis à l'échelle, hérite donc CETTE
## échelle. L'arme (Ravage) est modélisée à sa taille RÉELLE : sans contrepoids
## (ThirdPersonWeapon._apply_scale_correction/counter_scale_for), elle
## grossit/rétrécit AVEC le personnage (constaté : crosse géante ≈x1.8). Ce
## test vérifie l'échelle GLOBALE effective de l'arme une fois attachée, pas
## seulement la fonction pure (déjà couverte par
## tests/player/test_third_person_weapon_scale.gd).
func test_weapon_keeps_its_real_world_scale_on_a_scaled_character() -> void:
	var player := _remote_player(_offset())
	await get_tree().physics_frame
	await get_tree().physics_frame
	var w := player.get_node("Weapon") as Weapon
	w._broadcast_current_id(w._inv.current_id())
	await get_tree().physics_frame

	var character_body := player.get_node("%CharacterModel") as CharacterBody
	assert_bool(character_body.is_model_ready()).is_true()

	var tp_weapon := player.get_node("ThirdPersonWeapon") as ThirdPersonWeapon
	var weapon_model: Node3D = tp_weapon.get("_model")
	assert_object(weapon_model).append_failure_message(
		"préalable : l'arme doit être chargée et attachée"
	).is_not_null()

	var armature := character_body.get_skeleton().get_parent() as Node3D
	var body_scale := armature.global_transform.basis.get_scale()
	assert_float(body_scale.y).append_failure_message(
		"préalable : ce test n'a de sens que si le corps est effectivement mis à l'échelle (!= 1)"
	).is_not_equal(1.0)

	var weapon_scale := weapon_model.global_transform.basis.get_scale()
	assert_float(weapon_scale.x).append_failure_message(
		"échelle globale de l'arme = %s (corps à %s) -- doit rester ≈1 malgré l'échelle du corps" %
			[weapon_scale, body_scale]
	).is_equal_approx(1.0, 0.02)
	assert_float(weapon_scale.y).is_equal_approx(1.0, 0.02)
	assert_float(weapon_scale.z).is_equal_approx(1.0, 0.02)


## Requirement 8 : "bots spawn with the frog model" — un bot réel (voir
## _bot_player) affiche bien le maillage peint Frog Cowboy, jamais verrou.glb.
func test_bots_spawn_with_the_frog_cowboy_model() -> void:
	var player := _bot_player(_offset())
	await get_tree().physics_frame
	await get_tree().physics_frame

	var character_body := player.get_node("%CharacterModel") as CharacterBody
	assert_bool(character_body.is_model_ready()).is_true()
	var mesh := character_body.get_body_mesh()
	assert_object(mesh).is_not_null()
	assert_int(mesh.mesh.get_surface_count()).is_greater(0)
	var mat: Material = mesh.mesh.surface_get_material(0)
	assert_str(mat.resource_name).append_failure_message(
		"le bot affiche encore l'ancien matériau Verrou au lieu de Frog Cowboy"
	).is_equal("frog_cowboy_tex")
