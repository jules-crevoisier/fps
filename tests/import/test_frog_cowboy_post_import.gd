## test_frog_cowboy_post_import.gd
## Spec (contrat "native anim frog cowboy", 2026-09-26) : les clips embarqués
## nativement dans frog_cowboy.glb ciblent encore les noms d'os Mixamo
## d'ORIGINE (le fichier .glb n'est jamais réécrit) -- FrogCowboyPostImport
## doit renommer CES PISTES exactement comme il renomme les os du Skeleton3D
## (même table HumanoidBoneMap.MIXAMO_TO_HUMANOID), sinon une piste viserait un
## nom d'os qui n'existe plus une fois le squelette renommé et serait
## silencieusement ignorée à la lecture. `renamed_track_path` est une fonction
## PURE (NodePath est un type valeur) : testée ici sans AnimationPlayer ni
## arbre de scène.
extends GdUnitTestSuite

const FrogCowboyPostImport = preload("res://scripts/import/FrogCowboyPostImport.gd")
const HumanoidBoneMap = preload("res://scripts/import/HumanoidBoneMap.gd")


func test_renames_a_mapped_mixamo_bone_to_its_humanoid_name() -> void:
	var path := NodePath("Armature/Skeleton3D:mixamorig_Hips")
	var renamed := FrogCowboyPostImport.renamed_track_path(path, HumanoidBoneMap.MIXAMO_TO_HUMANOID)
	assert_str(String(renamed)).is_equal("Armature/Skeleton3D:Hips")


func test_renames_every_mapped_bone_used_by_a_locomotion_clip() -> void:
	var cases := {
		"mixamorig_RightHand": "RightHand",
		"mixamorig_LeftHand": "LeftHand",
		"mixamorig_Spine1": "Chest",
	}
	for mixamo_name in cases.keys():
		var path := NodePath("Armature/Skeleton3D:%s" % mixamo_name)
		var renamed := FrogCowboyPostImport.renamed_track_path(path, HumanoidBoneMap.MIXAMO_TO_HUMANOID)
		assert_str(String(renamed)).append_failure_message(
			"piste \"%s\" mal renommée" % mixamo_name
		).is_equal("Armature/Skeleton3D:%s" % cases[mixamo_name])


## Contrat : "WeaponGrip" (os nouveau, enfant de RightHand, sans équivalent
## Mixamo) traverse INCHANGÉ -- "keep WeaponGrip as is".
func test_leaves_weapon_grip_track_unchanged() -> void:
	var path := NodePath("Armature/Skeleton3D:WeaponGrip")
	var renamed := FrogCowboyPostImport.renamed_track_path(path, HumanoidBoneMap.MIXAMO_TO_HUMANOID)
	assert_str(String(renamed)).is_equal("Armature/Skeleton3D:WeaponGrip")


## Une piste sans sous-nom (pas de squelette ciblé, ex. une piste "method" ou
## une piste de visibilité) n'a pas de ":" -- ne doit jamais planter ni être
## altérée.
func test_leaves_a_path_without_a_bone_subname_unchanged() -> void:
	var path := NodePath("Armature")
	var renamed := FrogCowboyPostImport.renamed_track_path(path, HumanoidBoneMap.MIXAMO_TO_HUMANOID)
	assert_str(String(renamed)).is_equal("Armature")


func test_leaves_the_node_path_portion_untouched() -> void:
	var path := NodePath("Some/Other/Path:mixamorig_Head")
	var renamed := FrogCowboyPostImport.renamed_track_path(path, HumanoidBoneMap.MIXAMO_TO_HUMANOID)
	assert_str(String(renamed)).is_equal("Some/Other/Path:Head")


# ------------------------------------------------------------- loop clip list

## Boucles réellement en jeu (Idle/Walk/Jog_Fwd/Sprint/Crouch_Idle/Crouch_Fwd/
## Jump/Rifle_Idle/Rifle_Aim_Down/Neutral/Up) — pas les one-shots.
func test_looping_clips_cover_locomotion_and_rifle_idle_aim() -> void:
	var expected := [
		"Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Jump",
		"Rifle_Idle", "Rifle_Aim_Down", "Rifle_Aim_Neutral", "Rifle_Aim_Up",
	]
	for name in expected:
		assert_array(HumanoidBoneMap.FROG_LOOPING_CLIPS).append_failure_message(
			"\"%s\" doit boucler (contrat)" % name
		).contains([name])


func test_one_shot_clips_are_not_in_the_looping_list() -> void:
	var one_shots := [
		"Jump_Start", "Jump_Land", "Roll", "Hit_Head", "Interact", "Death01",
		"Rifle_Shoot", "Rifle_Reload",
	]
	for name in one_shots:
		assert_bool(HumanoidBoneMap.FROG_LOOPING_CLIPS.has(name)).append_failure_message(
			"\"%s\" ne doit PAS boucler (one-shot)" % name
		).is_false()


func test_frog_full_body_clips_match_the_lead_contract() -> void:
	var expected := [
		"Idle", "Walk", "Jog_Fwd", "Sprint",
		"Crouch_Idle", "Crouch_Fwd",
		"Jump_Start", "Jump", "Jump_Land",
		"Roll", "Hit_Head", "Interact", "Death01",
	]
	assert_array(HumanoidBoneMap.FROG_FULL_BODY_CLIPS).is_equal(expected)


func test_frog_rifle_clips_match_the_lead_contract() -> void:
	var expected := [
		"Rifle_Aim_Down", "Rifle_Aim_Neutral", "Rifle_Aim_Up",
		"Rifle_Idle", "Rifle_Shoot", "Rifle_Reload",
	]
	assert_array(HumanoidBoneMap.FROG_RIFLE_CLIPS).is_equal(expected)


# --------------------------------------------------- AnimationPlayer réel (léger)

## Sonde `_rename_animation_tracks`/`_apply_loop_modes` avec un AnimationPlayer
## synthétique (pas le vrai glb, qui n'a encore aucun clip -- voir le contrat)
## : construit une bibliothèque minimale à la main, appelle les fonctions du
## post-import, vérifie piste renommée + loop_mode forcé.
func test_post_import_renames_tracks_and_forces_loop_on_a_synthetic_player() -> void:
	var anim := Animation.new()
	var track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(track, NodePath("Armature/Skeleton3D:mixamorig_Hips"))
	anim.loop_mode = Animation.LOOP_NONE

	var lib := AnimationLibrary.new()
	lib.add_animation("Idle", anim)

	var player: AnimationPlayer = auto_free(AnimationPlayer.new())
	player.add_animation_library("", lib)

	FrogCowboyPostImport._rename_animation_tracks(player)
	FrogCowboyPostImport._apply_loop_modes(player)

	assert_str(String(anim.track_get_path(0))).is_equal("Armature/Skeleton3D:Hips")
	assert_int(anim.loop_mode).is_equal(Animation.LOOP_LINEAR)


func test_post_import_does_not_force_loop_on_a_one_shot_clip() -> void:
	var anim := Animation.new()
	anim.loop_mode = Animation.LOOP_NONE

	var lib := AnimationLibrary.new()
	lib.add_animation("Death01", anim)

	var player: AnimationPlayer = auto_free(AnimationPlayer.new())
	player.add_animation_library("", lib)

	FrogCowboyPostImport._apply_loop_modes(player)

	assert_int(anim.loop_mode).is_equal(Animation.LOOP_NONE)
