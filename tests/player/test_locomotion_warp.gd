## test_locomotion_warp.gd
## Spec (tâche "bots humains" passe 2, diagnostic lead : Walk/Jog_Fwd/Sprint
## sont DIRECTION-AGNOSTIQUES, tout strafe/recul "glisse") -- logique PURE de
## LocomotionWarp : angle déplacement/visée, hystérésis avant/arrière, lacet
## des hanches (clampé), part de contre-rotation de la colonne, lissage par
## vitesse, ressort critique amorti. Rien ici ne touche Skeleton3D/l'arbre de
## scène (même esprit que tests/player/test_character_animator.gd).
extends GdUnitTestSuite

const Warp := preload("res://scripts/player/LocomotionWarp.gd")


# ---------------------------------------------------------------- move_facing_angle_deg
func test_angle_zero_when_moving_exactly_along_facing() -> void:
	# Facing 0° = -Z (convention BotLook.yaw_forward_dir) ; se déplacer droit
	# devant donne un angle nul.
	assert_float(Warp.move_facing_angle_deg(Vector3(0, 0, -1), 0.0)).is_equal_approx(0.0, 0.001)


func test_angle_minus_ninety_when_strafing_right() -> void:
	# +X est la direction "droite" à yaw 0 (Basis identité, voir Node3D.rotation.y) ;
	# même convention que `rotation.y` (positif = lacet vers la GAUCHE, voir la
	# docstring de `move_facing_angle_deg`) -> un déplacement à DROITE donne un
	# angle NÉGATIF.
	assert_float(Warp.move_facing_angle_deg(Vector3(1, 0, 0), 0.0)).is_equal_approx(-90.0, 0.001)


func test_angle_ninety_when_strafing_left() -> void:
	assert_float(Warp.move_facing_angle_deg(Vector3(-1, 0, 0), 0.0)).is_equal_approx(90.0, 0.001)


func test_angle_180_when_moving_straight_backward() -> void:
	assert_float(absf(Warp.move_facing_angle_deg(Vector3(0, 0, 1), 0.0))).is_equal_approx(180.0, 0.001)


func test_angle_accounts_for_facing_yaw_offset() -> void:
	# yaw_forward_dir(-90°) = (1,0,0) (même convention que BotLook.yaw_forward_dir) :
	# le personnage regarde vers +X et avance droit devant lui (+X) -> angle nul,
	# quel que soit le cap absolu.
	assert_float(Warp.move_facing_angle_deg(Vector3(1, 0, 0), -90.0)).is_equal_approx(0.0, 0.001)


func test_angle_zero_when_almost_stationary() -> void:
	assert_float(Warp.move_facing_angle_deg(Vector3(0.001, 0, 0.001), 45.0)).is_equal(0.0)


# ---------------------------------------------------------------- backward detection
func test_forward_angle_at_boundary_is_forward() -> void:
	assert_bool(Warp.is_forward_angle(Warp.FORWARD_ANGLE_MAX_DEG)).is_true()
	assert_bool(Warp.is_backward_angle(Warp.FORWARD_ANGLE_MAX_DEG)).is_false()


func test_backward_angle_past_boundary_is_backward() -> void:
	assert_bool(Warp.is_backward_angle(Warp.BACKWARD_ANGLE_MIN_DEG + 0.1)).is_true()
	assert_bool(Warp.is_forward_angle(Warp.BACKWARD_ANGLE_MIN_DEG + 0.1)).is_false()


func test_dead_zone_between_boundaries_is_neither() -> void:
	var mid := (Warp.FORWARD_ANGLE_MAX_DEG + Warp.BACKWARD_ANGLE_MIN_DEG) * 0.5
	assert_bool(Warp.is_forward_angle(mid)).is_false()
	assert_bool(Warp.is_backward_angle(mid)).is_false()


func test_hysteresis_keeps_previous_mode_inside_dead_zone() -> void:
	var mid := (Warp.FORWARD_ANGLE_MAX_DEG + Warp.BACKWARD_ANGLE_MIN_DEG) * 0.5
	assert_bool(Warp.backward_mode_next(true, mid)).is_true()
	assert_bool(Warp.backward_mode_next(false, mid)).is_false()


func test_hysteresis_switches_outside_dead_zone() -> void:
	assert_bool(Warp.backward_mode_next(true, 10.0)).is_false()
	assert_bool(Warp.backward_mode_next(false, 170.0)).is_true()


# ---------------------------------------------------------------- forward hip yaw / clamp
func test_forward_hip_yaw_matches_angle_within_clamp() -> void:
	assert_float(Warp.forward_hip_yaw_deg(30.0)).is_equal_approx(30.0, 0.001)
	assert_float(Warp.forward_hip_yaw_deg(-30.0)).is_equal_approx(-30.0, 0.001)


func test_forward_hip_yaw_clamps_at_limit() -> void:
	assert_float(Warp.forward_hip_yaw_deg(100.0)).is_equal_approx(Warp.HIP_YAW_CLAMP_DEG, 0.001)
	assert_float(Warp.forward_hip_yaw_deg(-100.0)).is_equal_approx(-Warp.HIP_YAW_CLAMP_DEG, 0.001)


# ---------------------------------------------------------------- backward hip yaw / clamp
func test_backward_hip_yaw_zero_on_strict_backward() -> void:
	assert_float(Warp.backward_hip_yaw_deg(180.0)).is_equal_approx(0.0, 0.001)
	assert_float(Warp.backward_hip_yaw_deg(-180.0)).is_equal_approx(0.0, 0.001)


func test_backward_hip_yaw_residual_matches_deviation_from_180() -> void:
	assert_float(Warp.backward_hip_yaw_deg(150.0)).is_equal_approx(-30.0, 0.001)
	assert_float(Warp.backward_hip_yaw_deg(-150.0)).is_equal_approx(30.0, 0.001)


func test_backward_hip_yaw_clamps_at_limit() -> void:
	assert_float(Warp.backward_hip_yaw_deg(Warp.BACKWARD_ANGLE_MIN_DEG + 0.1)) \
		.is_between(-Warp.HIP_YAW_CLAMP_DEG - 0.001, Warp.HIP_YAW_CLAMP_DEG + 0.001)


# ---------------------------------------------------------------- speed blend
func test_speed_blend_zero_at_rest() -> void:
	assert_float(Warp.speed_blend_alpha(0.0)).is_equal(0.0)
	assert_float(Warp.speed_blend_alpha(Warp.MIN_WARP_SPEED_MPS)).is_equal(0.0)


func test_speed_blend_full_above_threshold() -> void:
	assert_float(Warp.speed_blend_alpha(Warp.FULL_WARP_SPEED_MPS)).is_equal(1.0)
	assert_float(Warp.speed_blend_alpha(Warp.FULL_WARP_SPEED_MPS + 5.0)).is_equal(1.0)


func test_speed_blend_linear_between_thresholds() -> void:
	var mid := (Warp.MIN_WARP_SPEED_MPS + Warp.FULL_WARP_SPEED_MPS) * 0.5
	assert_float(Warp.speed_blend_alpha(mid)).is_equal_approx(0.5, 0.001)


# ---------------------------------------------------------------- spine counter-yaw split
func test_spine_counter_yaw_splits_evenly_and_cancels_total() -> void:
	var share := Warp.spine_counter_yaw_deg(60.0, 3)
	assert_float(share).is_equal_approx(-20.0, 0.001)
	assert_float(share * 3.0).is_equal_approx(-60.0, 0.001)


func test_spine_counter_yaw_zero_chain_is_zero() -> void:
	assert_float(Warp.spine_counter_yaw_deg(60.0, 0)).is_equal(0.0)


func test_spine_counter_yaw_sign_follows_hip_yaw() -> void:
	assert_float(Warp.spine_counter_yaw_deg(-30.0, 3)).is_equal_approx(10.0, 0.001)


# ---------------------------------------------------------------- sanitize_velocity (téléportation)
func test_sanitize_velocity_passes_through_normal_speed() -> void:
	var v := Vector3(3.0, 0.0, 0.0)
	assert_vector(Warp.sanitize_velocity(v)).is_equal_approx(v, Vector3.ONE * 0.001)


func test_sanitize_velocity_zeroes_teleport_spike() -> void:
	var v := Vector3(500.0, 0.0, 0.0)
	assert_vector(Warp.sanitize_velocity(v)).is_equal(Vector3.ZERO)


# ---------------------------------------------------------------- critically_damped_step
func test_critically_damped_step_converges_without_overshoot() -> void:
	var state := {}
	var last_value := 0.0
	var overshot := false
	for i in 200:
		state = Warp.critically_damped_step(state, 50.0, LocomotionWarp.SMOOTH_TIME_CONSTANT_S, 1.0 / 60.0)
		var value: float = state["value"]
		if value > 50.0 + 0.01:
			overshot = true
		last_value = value
	assert_bool(overshot).append_failure_message("critically damped step overshot the target").is_false()
	assert_float(last_value).is_equal_approx(50.0, 0.5)


func test_critically_damped_step_settles_within_time_constant_budget() -> void:
	var state := {}
	# ~4 constantes de temps (voir la docstring : wn = 4/tau pour zeta=1) :
	# doit être très proche de la cible, jamais encore en train de "sauter".
	var steps := int(ceil((LocomotionWarp.SMOOTH_TIME_CONSTANT_S * 4.0) / (1.0 / 60.0)))
	for i in steps:
		state = Warp.critically_damped_step(state, 10.0, LocomotionWarp.SMOOTH_TIME_CONSTANT_S, 1.0 / 60.0)
	assert_float(state["value"]).is_equal_approx(10.0, 1.0)


func test_critically_damped_step_zero_delta_is_a_no_op() -> void:
	var state := {"value": 5.0, "speed": 2.0}
	var next := Warp.critically_damped_step(state, 50.0, LocomotionWarp.SMOOTH_TIME_CONSTANT_S, 0.0)
	assert_float(next["value"]).is_equal_approx(5.0, 0.001)
