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


# ============================================================================
# GF-10 « Réaction visible de la cible » : recul additif du haut du corps
# (flinch, 120 ms) et gel de pose cosmétique au kill (50 ms).
# ============================================================================

# ---------------------------------------------------------------- hit_flinch_angle_rad
func test_hit_flinch_angle_is_zero_at_the_very_start() -> void:
	assert_float(CharacterAnimator.hit_flinch_angle_rad(0.0)).is_equal_approx(0.0, 0.0001)


func test_hit_flinch_angle_peaks_at_the_midpoint() -> void:
	var half := CharacterAnimator.HIT_FLINCH_DURATION_S * 0.5
	var expected := deg_to_rad(CharacterAnimator.HIT_FLINCH_MAX_ANGLE_DEG)
	assert_float(CharacterAnimator.hit_flinch_angle_rad(half)).is_equal_approx(expected, 0.0001)


## Garde-fou (même esprit que `body_squash_scale`) : jamais d'angle en dehors
## de `[0, HIT_FLINCH_DURATION_S[`, quel que soit l'appelant.
func test_hit_flinch_angle_is_zero_outside_the_duration_window() -> void:
	assert_float(CharacterAnimator.hit_flinch_angle_rad(-0.01)).is_equal(0.0)
	assert_float(CharacterAnimator.hit_flinch_angle_rad(CharacterAnimator.HIT_FLINCH_DURATION_S)).is_equal(0.0)
	assert_float(CharacterAnimator.hit_flinch_angle_rad(CharacterAnimator.HIT_FLINCH_DURATION_S + 1.0)).is_equal(0.0)


func test_hit_flinch_duration_is_a_hundred_twenty_milliseconds() -> void:
	assert_float(CharacterAnimator.HIT_FLINCH_DURATION_S).is_equal_approx(0.12, 0.0001)


# ---------------------------------------------------------------- KILL_FREEZE_DURATION_S
func test_kill_freeze_duration_is_fifty_milliseconds() -> void:
	assert_float(CharacterAnimator.KILL_FREEZE_DURATION_S).is_equal_approx(0.05, 0.0001)


# ---------------------------------------------------------------- _on_hit_reaction
func test_on_hit_reaction_starts_the_flinch_when_the_tree_is_built() -> void:
	var animator: CharacterAnimator = auto_free(CharacterAnimator.new())
	animator._built = true

	animator._on_hit_reaction(false)

	assert_float(animator._flinch_elapsed).append_failure_message(
		"un dégât confirmé doit lancer le recul additif (_flinch_elapsed remis à 0)"
	).is_equal_approx(0.0, 0.0001)


## `headshot` ne change que la couleur du flash (PlayerLook) — le recul est
## identique dans les deux cas (voir la docstring de `_on_hit_reaction`).
func test_on_hit_reaction_headshot_starts_the_same_flinch() -> void:
	var animator: CharacterAnimator = auto_free(CharacterAnimator.new())
	animator._built = true

	animator._on_hit_reaction(true)

	assert_float(animator._flinch_elapsed).is_equal_approx(0.0, 0.0001)


## Modèle pas encore chargé (`_built` = false, voir `_on_model_ready`) : le hit
## ne doit rien déclencher — pas de recul sur un squelette qui n'existe pas
## encore.
func test_on_hit_reaction_is_ignored_before_the_tree_is_built() -> void:
	var animator: CharacterAnimator = auto_free(CharacterAnimator.new())

	animator._on_hit_reaction(false)

	assert_float(animator._flinch_elapsed).append_failure_message(
		"avant que l'AnimationTree ne soit construit, un hit ne doit pas armer le recul"
	).is_equal(-1.0)


# ---------------------------------------------------------------- _on_died
func test_on_died_arms_the_kill_freeze_and_pauses_the_tree_when_built() -> void:
	var animator: CharacterAnimator = auto_free(CharacterAnimator.new())
	animator._built = true
	animator.active = true

	animator._on_died(0)

	assert_float(animator._kill_freeze_left).append_failure_message(
		"un kill confirmé doit armer le gel de pose pour KILL_FREEZE_DURATION_S"
	).is_equal_approx(CharacterAnimator.KILL_FREEZE_DURATION_S, 0.0001)
	assert_bool(animator.active).append_failure_message(
		"l'AnimationTree doit être mise en pause (active = false) pendant le gel — la pose reste EN L'ÉTAT"
	).is_false()


## Modèle pas encore chargé : aucun gel à armer (pas de squelette à figer).
func test_on_died_is_ignored_before_the_tree_is_built() -> void:
	var animator: CharacterAnimator = auto_free(CharacterAnimator.new())

	animator._on_died(0)

	assert_float(animator._kill_freeze_left).is_equal(-1.0)


# ============================================================================
# GF-27 « Boucles d'animation en jeu » : hystérésis Jog/Sprint, reset coupé
# sur les boucles, STUN/INTERACT forcés en boucle, haut du corps selon la
# locomotion, rechargement calé sur reload_time, vrai INTERACT (SnDMode).
# ============================================================================

# ---------------------------------------------------------------- sprint_or_jog (hystérésis)
func test_sprint_or_jog_stays_sprint_within_the_hysteresis_band() -> void:
	for speed in [5.8, 5.9, 6.0, 6.1, 6.2]:
		assert_int(CharacterAnimator.sprint_or_jog(speed, true)).append_failure_message(
			"vitesse=%.1f, déjà en SPRINT : doit y rester (bande [%.1f;%.1f])" %
				[speed, CharacterAnimator.JOG_SPRINT_LOW, CharacterAnimator.JOG_SPRINT_HIGH]
		).is_equal(CharacterAnimator.Locomotion.SPRINT)


func test_sprint_or_jog_stays_jog_within_the_hysteresis_band() -> void:
	for speed in [5.8, 5.9, 6.0, 6.1, 6.2]:
		assert_int(CharacterAnimator.sprint_or_jog(speed, false)).append_failure_message(
			"vitesse=%.1f, déjà en JOG : doit y rester (bande [%.1f;%.1f])" %
				[speed, CharacterAnimator.JOG_SPRINT_LOW, CharacterAnimator.JOG_SPRINT_HIGH]
		).is_equal(CharacterAnimator.Locomotion.JOG)


func test_sprint_or_jog_drops_to_jog_below_the_low_threshold() -> void:
	assert_int(CharacterAnimator.sprint_or_jog(CharacterAnimator.JOG_SPRINT_LOW - 0.1, true)) \
		.is_equal(CharacterAnimator.Locomotion.JOG)


func test_sprint_or_jog_rises_to_sprint_above_the_high_threshold() -> void:
	assert_int(CharacterAnimator.sprint_or_jog(CharacterAnimator.JOG_SPRINT_HIGH + 0.1, false)) \
		.is_equal(CharacterAnimator.Locomotion.SPRINT)


## Contrat GF-27 (test pur) : « aucun changement de locomotion quand la
## vitesse oscille entre 5,8 et 6,2 m/s ». On enchaîne les appels en
## réinjectant la locomotion retournée comme `previous_locomotion` du tick
## suivant (exactement ce que fait PlayerController._update_anim_state via
## `anim_state` déjà répliqué) et on vérifie qu'elle ne bouge jamais.
func test_no_locomotion_change_while_speed_oscillates_between_5_8_and_6_2_from_sprint() -> void:
	var speeds := [5.8, 6.2, 5.8, 6.2, 6.0, 5.9, 6.1, 5.8, 6.2, 6.2, 5.8]
	var loco := CharacterAnimator.Locomotion.SPRINT
	for speed in speeds:
		var next := CharacterAnimator.locomotion_for("Sprint", speed, false, false, 0.0, 0.0, loco)
		assert_int(next).append_failure_message(
			"vitesse=%.1f : aucun changement de locomotion attendu entre 5,8 et 6,2 m/s (hystérésis GF-27)" % speed
		).is_equal(loco)
		loco = next


func test_no_locomotion_change_while_speed_oscillates_between_5_8_and_6_2_from_jog() -> void:
	var speeds := [5.8, 6.2, 5.8, 6.2, 6.0, 5.9, 6.1, 5.8, 6.2, 6.2, 5.8]
	var loco := CharacterAnimator.Locomotion.JOG
	for speed in speeds:
		var next := CharacterAnimator.locomotion_for("Sprint", speed, false, false, 0.0, 0.0, loco)
		assert_int(next).append_failure_message(
			"vitesse=%.1f : aucun changement de locomotion attendu entre 5,8 et 6,2 m/s (hystérésis GF-27)" % speed
		).is_equal(loco)
		loco = next


## Sans locomotion précédente connue (premier appel) : repli sur l'ancien
## seuil unique, comportement inchangé depuis avant GF-27 (non-régression).
func test_locomotion_for_cold_start_still_uses_the_single_threshold() -> void:
	assert_int(CharacterAnimator.locomotion_for("Sprint", CharacterAnimator.JOG_SPEED_THRESHOLD - 0.1, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.JOG)
	assert_int(CharacterAnimator.locomotion_for("Sprint", CharacterAnimator.JOG_SPEED_THRESHOLD, false, false)) \
		.is_equal(CharacterAnimator.Locomotion.SPRINT)


# ---------------------------------------------------------------- is_looping_locomotion / reset
func test_is_looping_locomotion_covers_the_expected_set() -> void:
	var looping := [
		CharacterAnimator.Locomotion.IDLE, CharacterAnimator.Locomotion.WALK,
		CharacterAnimator.Locomotion.JOG, CharacterAnimator.Locomotion.SPRINT,
		CharacterAnimator.Locomotion.CROUCH_IDLE, CharacterAnimator.Locomotion.CROUCH_FWD,
		CharacterAnimator.Locomotion.SLIDE, CharacterAnimator.Locomotion.AIR,
		CharacterAnimator.Locomotion.STUN, CharacterAnimator.Locomotion.INTERACT,
	]
	for i in CharacterAnimator.Locomotion.size():
		assert_bool(CharacterAnimator.is_looping_locomotion(i)).append_failure_message(
			"locomotion %d : is_looping_locomotion incohérent avec l'ensemble attendu (GF-27)" % i
		).is_equal(looping.has(i))


## Contrat GF-27 (test pur) : « is_input_reset faux sur les boucles ».
## `AnimationNodeTransition` est une Resource, instanciable sans AnimationTree
## ni arbre de scène.
func test_looping_locomotions_never_reset_their_phase_on_transition() -> void:
	var t := AnimationNodeTransition.new()
	for i in CharacterAnimator.Locomotion.size():
		t.add_input("state_%d" % i)

	CharacterAnimator.configure_locomotion_transition_reset(t)

	for i in CharacterAnimator.Locomotion.size():
		var looping := CharacterAnimator.is_looping_locomotion(i)
		assert_bool(t.is_input_reset(i)).append_failure_message(
			"locomotion %d (looping=%s) : is_input_reset doit être FAUX sur une boucle" % [i, looping]
		).is_equal(not looping)


# ---------------------------------------------------------------- forced_loop_mode (STUN/INTERACT)
func test_forced_loop_mode_for_stun_is_pingpong() -> void:
	assert_int(CharacterAnimator.forced_loop_mode(CharacterAnimator.Locomotion.STUN)) \
		.is_equal(Animation.LOOP_PINGPONG)


func test_forced_loop_mode_for_interact_is_linear() -> void:
	assert_int(CharacterAnimator.forced_loop_mode(CharacterAnimator.Locomotion.INTERACT)) \
		.is_equal(Animation.LOOP_LINEAR)


func test_forced_loop_mode_for_ordinary_locomotion_is_none() -> void:
	assert_int(CharacterAnimator.forced_loop_mode(CharacterAnimator.Locomotion.IDLE)) \
		.is_equal(Animation.LOOP_NONE)
	assert_int(CharacterAnimator.forced_loop_mode(CharacterAnimator.Locomotion.DEAD)) \
		.is_equal(Animation.LOOP_NONE)


# ---------------------------------------------------------------- upper_body_blend_amount
func test_upper_body_blend_full_for_idle_walk_and_crouch() -> void:
	for l in [CharacterAnimator.Locomotion.IDLE, CharacterAnimator.Locomotion.WALK,
			CharacterAnimator.Locomotion.CROUCH_IDLE, CharacterAnimator.Locomotion.CROUCH_FWD,
			CharacterAnimator.Locomotion.AIR, CharacterAnimator.Locomotion.JUMP_START]:
		assert_float(CharacterAnimator.upper_body_blend_amount(l)).append_failure_message(
			"locomotion %d : haut du corps attendu à 100%%" % l
		).is_equal_approx(1.0, 0.0001)


func test_upper_body_blend_reduced_in_jog_and_sprint() -> void:
	assert_float(CharacterAnimator.upper_body_blend_amount(CharacterAnimator.Locomotion.JOG)) \
		.is_equal_approx(CharacterAnimator.UPPER_BODY_BLEND_JOG, 0.0001)
	assert_float(CharacterAnimator.upper_body_blend_amount(CharacterAnimator.Locomotion.SPRINT)) \
		.is_equal_approx(CharacterAnimator.UPPER_BODY_BLEND_SPRINT, 0.0001)
	assert_float(CharacterAnimator.upper_body_blend_amount(CharacterAnimator.Locomotion.SPRINT)) \
		.append_failure_message("le Sprint doit laisser MOINS de haut du corps que le Jog (bras qui balancent)") \
		.is_less(CharacterAnimator.upper_body_blend_amount(CharacterAnimator.Locomotion.JOG))


func test_upper_body_blend_zero_for_full_pose_overrides() -> void:
	for l in [CharacterAnimator.Locomotion.DEAD, CharacterAnimator.Locomotion.ROLL,
			CharacterAnimator.Locomotion.STUN, CharacterAnimator.Locomotion.INTERACT,
			CharacterAnimator.Locomotion.DIVE]:
		assert_float(CharacterAnimator.upper_body_blend_amount(l)).append_failure_message(
			"locomotion %d : pose plein corps, haut du corps attendu à 0" % l
		).is_equal(0.0)


# ---------------------------------------------------------------- reload_clip_speed
func test_reload_clip_speed_matches_the_default_reload_time() -> void:
	assert_float(CharacterAnimator.reload_clip_speed(CharacterAnimator.RELOAD_CLIP_BASE_DURATION_S)) \
		.is_equal_approx(1.0, 0.0001)


## Semeuse (4,2 s) : le clip doit tourner au RALENTI pour tenir toute la durée.
## Magnum (≈1,2 s) : le clip doit tourner PLUS VITE (docs/research/10_ammo_kits_input.md §2.3).
func test_reload_clip_speed_scales_with_reload_time() -> void:
	assert_float(CharacterAnimator.reload_clip_speed(4.2)).append_failure_message(
		"rechargement lent (4,2 s) : le clip doit tourner au ralenti (vitesse < 1)"
	).is_less(1.0)
	assert_float(CharacterAnimator.reload_clip_speed(1.2)).append_failure_message(
		"rechargement rapide (1,2 s) : le clip doit tourner plus vite (vitesse > 1)"
	).is_greater(1.0)


func test_reload_clip_speed_is_defensive_for_zero_or_negative_reload_time() -> void:
	assert_float(CharacterAnimator.reload_clip_speed(0.0)).is_equal_approx(1.0, 0.0001)
	assert_float(CharacterAnimator.reload_clip_speed(-1.0)).is_equal_approx(1.0, 0.0001)


# ---------------------------------------------------------------- PlayerController.is_really_interacting (vrai INTERACT)
func test_is_really_interacting_true_for_the_bomb_carrier_while_carried() -> void:
	assert_bool(PlayerController.is_really_interacting(true, SnDMode.BombState.CARRIED, 42, 42, 0, 1)) \
		.is_true()


func test_is_really_interacting_false_for_a_bystander_while_carried() -> void:
	assert_bool(PlayerController.is_really_interacting(true, SnDMode.BombState.CARRIED, 42, 7, 0, 1)) \
		.append_failure_message("tenir F loin de la bombe portée par un autre ne doit jamais poser") \
		.is_false()


func test_is_really_interacting_true_for_any_defender_while_planted() -> void:
	# Équipe 1 défend quand attacking_team() == 0.
	assert_bool(PlayerController.is_really_interacting(true, SnDMode.BombState.PLANTED, -1, 7, 1, 0)) \
		.is_true()


func test_is_really_interacting_false_for_an_attacker_while_planted() -> void:
	# Un attaquant (même équipe que attacking_team()) ne désamorce jamais.
	assert_bool(PlayerController.is_really_interacting(true, SnDMode.BombState.PLANTED, -1, 7, 0, 0)) \
		.is_false()


func test_is_really_interacting_false_without_pickup_held() -> void:
	assert_bool(PlayerController.is_really_interacting(false, SnDMode.BombState.CARRIED, 7, 7, 0, 1)) \
		.is_false()


func test_is_really_interacting_false_outside_snd_mode() -> void:
	assert_bool(PlayerController.is_really_interacting(true, PlayerController.NO_BOMB_MODE, -1, 7, 0, -1)) \
		.append_failure_message("Mêlée/Borne/Duel/Duo/entraînement n'ont pas de bombe : jamais de vraie pose") \
		.is_false()


func test_is_really_interacting_false_while_bomb_dropped_or_exploded() -> void:
	assert_bool(PlayerController.is_really_interacting(true, SnDMode.BombState.DROPPED, 7, 7, 0, 1)).is_false()
	assert_bool(PlayerController.is_really_interacting(true, SnDMode.BombState.EXPLODED, -1, 7, 0, 0)).is_false()
	assert_bool(PlayerController.is_really_interacting(true, SnDMode.BombState.DEFUSED, -1, 7, 0, 0)).is_false()
