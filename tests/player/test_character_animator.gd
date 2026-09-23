## test_character_animator.gd
## Spec (R3-CHAR) : logique PURE de CharacterAnimator — état -> locomotion,
## seuils de vitesse, empaquetage de `anim_state` (répliqué, voir
## PlayerController.anim_state), blend de visée par pitch. Rien de ceci ne
## touche l'arbre de scène / AnimationTree (testable directement, comme
## ViewModel.AnimState dans tests/combat/test_weapon_fx.gd).
extends GdUnitTestSuite


# ---------------------------------------------------------------- pack/unpack
func test_pack_unpack_round_trip_not_reloading() -> void:
	var s := CharacterAnimator.pack_anim_state(CharacterAnimator.Locomotion.SPRINT, false)
	assert_int(CharacterAnimator.unpack_locomotion(s)).is_equal(CharacterAnimator.Locomotion.SPRINT)
	assert_bool(CharacterAnimator.unpack_reloading(s)).is_false()


func test_pack_unpack_round_trip_reloading() -> void:
	var s := CharacterAnimator.pack_anim_state(CharacterAnimator.Locomotion.WALK, true)
	assert_int(CharacterAnimator.unpack_locomotion(s)).is_equal(CharacterAnimator.Locomotion.WALK)
	assert_bool(CharacterAnimator.unpack_reloading(s)).is_true()


func test_reloading_flag_never_collides_with_a_locomotion_value() -> void:
	for i in CharacterAnimator.Locomotion.size():
		var s := CharacterAnimator.pack_anim_state(i, true)
		assert_int(CharacterAnimator.unpack_locomotion(s)).is_equal(i)


# ---------------------------------------------------------------- locomotion_for
func test_idle_state_maps_to_idle() -> void:
	assert_int(CharacterAnimator.locomotion_for("Idle", 0.0, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.IDLE)


func test_walk_state_maps_to_walk() -> void:
	assert_int(CharacterAnimator.locomotion_for("Walk", 5.2, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.WALK)


func test_sprint_state_below_jog_threshold_is_jog() -> void:
	var speed := CharacterAnimator.JOG_SPEED_THRESHOLD - 0.1
	assert_int(CharacterAnimator.locomotion_for("Sprint", speed, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.JOG)


func test_sprint_state_at_or_above_jog_threshold_is_sprint() -> void:
	var speed := CharacterAnimator.JOG_SPEED_THRESHOLD
	assert_int(CharacterAnimator.locomotion_for("Sprint", speed, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.SPRINT)
	assert_int(CharacterAnimator.locomotion_for("Sprint", 8.2, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.SPRINT)


func test_crouch_state_still_is_crouch_idle() -> void:
	assert_int(CharacterAnimator.locomotion_for("Crouch", 0.0, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.CROUCH_IDLE)


func test_crouch_state_moving_above_threshold_is_crouch_fwd() -> void:
	var speed := CharacterAnimator.CROUCH_MOVE_THRESHOLD + 0.1
	assert_int(CharacterAnimator.locomotion_for("Crouch", speed, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.CROUCH_FWD)


func test_slide_state_maps_to_slide() -> void:
	assert_int(CharacterAnimator.locomotion_for("Slide", 10.0, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.SLIDE)


func test_air_dive_roll_stun_states_map_one_to_one() -> void:
	assert_int(CharacterAnimator.locomotion_for("Air", 3.0, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.AIR)
	assert_int(CharacterAnimator.locomotion_for("Dive", 13.0, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.DIVE)
	assert_int(CharacterAnimator.locomotion_for("Roll", 6.0, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.ROLL)
	assert_int(CharacterAnimator.locomotion_for("Stun", 0.0, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.STUN)


func test_unknown_state_falls_back_to_idle() -> void:
	assert_int(CharacterAnimator.locomotion_for("NotAState", 0.0, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.IDLE)


# ---------------------------------------------------------------- priority ordering
func test_dead_overrides_everything_else() -> void:
	assert_int(CharacterAnimator.locomotion_for("Sprint", 8.0, true, true, 1.0, 1.0)) \
		.is_equal(CharacterAnimator.Locomotion.DEAD)


func test_interacting_overrides_locomotion_but_not_death() -> void:
	assert_int(CharacterAnimator.locomotion_for("Idle", 0.0, true, false)) \
		.is_equal(CharacterAnimator.Locomotion.INTERACT)
	assert_int(CharacterAnimator.locomotion_for("Idle", 0.0, true, true)) \
		.is_equal(CharacterAnimator.Locomotion.DEAD)


func test_jump_land_window_overrides_jump_start_window() -> void:
	assert_int(CharacterAnimator.locomotion_for("Air", 3.0, false, false, 1.0, 1.0)) \
		.is_equal(CharacterAnimator.Locomotion.JUMP_LAND)


func test_jump_start_window_applies_when_no_land_window() -> void:
	assert_int(CharacterAnimator.locomotion_for("Air", 3.0, false, false, 1.0, 0.0)) \
		.is_equal(CharacterAnimator.Locomotion.JUMP_START)


func test_no_jump_window_left_falls_back_to_state_mapping() -> void:
	assert_int(CharacterAnimator.locomotion_for("Air", 3.0, false, false, 0.0, 0.0)) \
		.is_equal(CharacterAnimator.Locomotion.AIR)


# ---------------------------------------------------------------- upper_body_active
func test_upper_body_active_for_ordinary_locomotion() -> void:
	assert_bool(CharacterAnimator.upper_body_active(CharacterAnimator.Locomotion.IDLE)).is_true()
	assert_bool(CharacterAnimator.upper_body_active(CharacterAnimator.Locomotion.SPRINT)).is_true()
	assert_bool(CharacterAnimator.upper_body_active(CharacterAnimator.Locomotion.CROUCH_FWD)).is_true()
	assert_bool(CharacterAnimator.upper_body_active(CharacterAnimator.Locomotion.AIR)).is_true()
	assert_bool(CharacterAnimator.upper_body_active(CharacterAnimator.Locomotion.JUMP_START)).is_true()


func test_upper_body_inactive_for_full_pose_overrides() -> void:
	assert_bool(CharacterAnimator.upper_body_active(CharacterAnimator.Locomotion.DEAD)).is_false()
	assert_bool(CharacterAnimator.upper_body_active(CharacterAnimator.Locomotion.ROLL)).is_false()
	assert_bool(CharacterAnimator.upper_body_active(CharacterAnimator.Locomotion.STUN)).is_false()
	assert_bool(CharacterAnimator.upper_body_active(CharacterAnimator.Locomotion.INTERACT)).is_false()
	assert_bool(CharacterAnimator.upper_body_active(CharacterAnimator.Locomotion.DIVE)).is_false()


# ---------------------------------------------------------------- aim_blend_t
func test_aim_blend_t_zero_pitch_is_neutral() -> void:
	assert_float(CharacterAnimator.aim_blend_t(0.0)).is_equal_approx(0.0, 0.0001)


func test_aim_blend_t_positive_pitch_is_up() -> void:
	assert_float(CharacterAnimator.aim_blend_t(CharacterAnimator.AIM_PITCH_MAX)).is_equal_approx(1.0, 0.0001)


func test_aim_blend_t_negative_pitch_is_down() -> void:
	assert_float(CharacterAnimator.aim_blend_t(-CharacterAnimator.AIM_PITCH_MAX)).is_equal_approx(-1.0, 0.0001)


func test_aim_blend_t_is_clamped_beyond_max_pitch() -> void:
	assert_float(CharacterAnimator.aim_blend_t(CharacterAnimator.AIM_PITCH_MAX * 5.0)).is_equal_approx(1.0, 0.0001)
	assert_float(CharacterAnimator.aim_blend_t(-CharacterAnimator.AIM_PITCH_MAX * 5.0)).is_equal_approx(-1.0, 0.0001)


func test_aim_blend_t_is_monotonic() -> void:
	var prev := -1.0
	var pitch := -CharacterAnimator.AIM_PITCH_MAX
	while pitch <= CharacterAnimator.AIM_PITCH_MAX:
		var t := CharacterAnimator.aim_blend_t(pitch)
		assert_float(t).is_greater_equal(prev)
		prev = t
		pitch += CharacterAnimator.AIM_PITCH_MAX / 4.0


# ---------------------------------------------------------------- clip_for
func test_clip_for_covers_every_locomotion_value_with_a_non_empty_name() -> void:
	for i in CharacterAnimator.Locomotion.size():
		assert_str(CharacterAnimator.clip_for(i)).is_not_empty()


func test_clip_for_out_of_range_falls_back_to_idle_clip() -> void:
	assert_str(CharacterAnimator.clip_for(-1)).is_equal("Idle")
	assert_str(CharacterAnimator.clip_for(9999)).is_equal("Idle")
