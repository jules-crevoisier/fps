## test_humanoid_bone_map.gd
## Spec (HumanoidBoneMap.gd, retargeting Frog Cowboy) : les deux tables
## (Mixamo -> profil humanoïde, DEF-* UAL -> profil humanoïde) doivent
## retomber sur EXACTEMENT le même ensemble de 52 noms de profil — sinon un
## clip retargeté depuis l'UAL viserait un os que le squelette Frog Cowboy
## n'expose pas (ou l'inverse), et la piste correspondante serait
## silencieusement ignorée (voir tools/rigging/bake_frog_animations.gd).
extends GdUnitTestSuite

const HumanoidBoneMap = preload("res://scripts/import/HumanoidBoneMap.gd")


func test_both_tables_map_to_the_same_set_of_humanoid_names() -> void:
	var mixamo_targets: Array = HumanoidBoneMap.MIXAMO_TO_HUMANOID.values()
	var def_targets: Array = HumanoidBoneMap.DEF_TO_HUMANOID.values()
	var a := mixamo_targets.duplicate()
	var b := def_targets.duplicate()
	a.sort()
	b.sort()
	assert_array(a).append_failure_message(
		"MIXAMO_TO_HUMANOID et DEF_TO_HUMANOID ne couvrent pas le même ensemble d'os humanoïdes"
	).is_equal(b)


func test_no_duplicate_humanoid_target_within_a_table() -> void:
	for table in [HumanoidBoneMap.MIXAMO_TO_HUMANOID, HumanoidBoneMap.DEF_TO_HUMANOID]:
		var seen: Dictionary = {}
		for humanoid_name in table.values():
			assert_bool(seen.has(humanoid_name)).append_failure_message(
				"\"%s\" ciblé par deux os source différents dans la même table" % humanoid_name
			).is_false()
			seen[humanoid_name] = true


func test_key_bones_used_by_the_weapon_socket_and_tests_are_mapped() -> void:
	assert_array(HumanoidBoneMap.MIXAMO_TO_HUMANOID.values()).contains(["Hips", "RightHand", "LeftHand"])
	assert_array(HumanoidBoneMap.DEF_TO_HUMANOID.values()).contains(["Hips", "RightHand", "LeftHand"])


## Le bake tool (tools/rigging/bake_frog_animations.gd) lit ces noms de clip
## directement sur l'AnimationPlayer d'assets/incoming/quaternius/ual.glb —
## verrouille la liste pour ne pas la faire dériver silencieusement de
## CharacterAnimator._CLIPS/upper body sans mettre celle-ci à jour.
func test_needed_clips_cover_every_locomotion_clip_used_by_character_animator() -> void:
	var expected := [
		"Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd",
		"Jump", "Jump_Start", "Jump_Land", "Roll", "Hit_Head", "Interact", "Death01",
	]
	for clip in expected:
		assert_array(HumanoidBoneMap.NEEDED_CLIPS).append_failure_message(
			"clip de locomotion \"%s\" (CharacterAnimator._CLIPS) absent de NEEDED_CLIPS" % clip
		).contains([clip])
