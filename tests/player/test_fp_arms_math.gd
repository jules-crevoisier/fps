## test_fp_arms_math.gd
## Spec (tâche "frog fp arms") : maths PURES de FPArmsMath.gd (aucun Node3D/
## Skeleton3D/arbre de scène) — voir sa docstring de classe pour la preuve de
## `align_rig_transform`. Ce fichier vérifie cette preuve NUMÉRIQUEMENT (avec
## une transform de repos "FPCamera" non triviale, comme le vrai
## frog_cowboy_fp.glb -- voir test_fp_arms_rig.gd pour l'intégration avec le
## vrai glb) et couvre les autres fonctions pures (échelle de contrepoids de
## l'arme, blend ADS, vitesse de rechargement, annulation de l'inspection).
extends GdUnitTestSuite

const DT := 1.0 / 60.0


# ---------------------------------------------------------------- align_rig_transform
## Repos "FPCamera" non trivial (rotation 180° autour de Y + une origine
## décalée) -- même famille de valeurs que le vrai glb (voir docstring de
## FPArmsMath), pour ne PAS valider seulement le cas dégénéré identité.
func _sample_fp_camera_rest() -> Transform3D:
	var basis := Basis(Vector3.UP, PI)  # 180° autour de Y, comme le vrai rig.
	return Transform3D(basis, Vector3(0.0, 0.93, 0.06))


func test_align_rig_transform_makes_fp_camera_bone_coincide_with_the_real_camera() -> void:
	var rest := _sample_fp_camera_rest()
	var cam := Transform3D(Basis(Vector3.UP, deg_to_rad(37.0)), Vector3(1.5, 1.7, -2.2))
	var rig_scale := 1.8

	var rig_root := FPArmsMath.align_rig_transform(rest, cam, rig_scale)

	# Transform MONDE réelle de l'os FPCamera une fois le rig placé à
	# `rig_root` (aucune échelle supplémentaire ici -- même composition que
	# Skeleton3D.global_transform * bone_global_rest en jeu).
	var fp_camera_world := rig_root * rest

	assert_vector(fp_camera_world.origin).is_equal_approx(cam.origin, Vector3.ONE * 0.0005)
	# Direction (colonnes normalisées) -- la magnitude de la base diffère
	# volontairement (rig_scale), voir la preuve de la docstring de classe.
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for axis: Vector3 in axes:
		var world_dir: Vector3 = (fp_camera_world.basis * axis).normalized()
		var cam_dir: Vector3 = (cam.basis * axis).normalized()
		assert_vector(world_dir).is_equal_approx(cam_dir, Vector3.ONE * 0.0005)


func test_align_rig_transform_bakes_rig_scale_into_the_result_basis_magnitude() -> void:
	var rest := _sample_fp_camera_rest()
	var cam := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var rig_root := FPArmsMath.align_rig_transform(rest, cam, 1.8)
	# Colonne X de la base résultante : magnitude RIG_SCALE (voir la preuve) --
	# c'est ce qui, propagé par la hiérarchie de nœuds jusqu'à la
	# BoneAttachment3D "WeaponGrip", impose `weapon_counter_scale`.
	assert_float(rig_root.basis.x.length()).is_equal_approx(1.8, 0.001)


func test_align_rig_transform_is_defensive_against_a_zero_rig_scale() -> void:
	var rest := _sample_fp_camera_rest()
	var cam := Transform3D(Basis(Vector3.UP, 0.3), Vector3(1, 2, 3))
	var result := FPArmsMath.align_rig_transform(rest, cam, 0.0)
	assert_bool(result.origin.is_finite()).is_true()


# ---------------------------------------------------------------- weapon_counter_scale
func test_weapon_counter_scale_is_the_reciprocal_of_rig_scale() -> void:
	var s := FPArmsMath.weapon_counter_scale(1.8)
	assert_float(s.x).is_equal_approx(1.0 / 1.8, 0.0001)
	assert_float(s.y).is_equal_approx(1.0 / 1.8, 0.0001)
	assert_float(s.z).is_equal_approx(1.0 / 1.8, 0.0001)


func test_weapon_counter_scale_is_identity_at_rig_scale_one() -> void:
	var s := FPArmsMath.weapon_counter_scale(1.0)
	assert_bool(s.is_equal_approx(Vector3.ONE)).is_true()


func test_weapon_counter_scale_is_defensive_against_a_zero_rig_scale() -> void:
	var s := FPArmsMath.weapon_counter_scale(0.0)
	assert_bool(s.is_equal_approx(Vector3.ONE)).is_true()
	assert_bool(is_finite(s.x) and is_finite(s.y) and is_finite(s.z)).is_true()


# ---------------------------------------------------------------- ads_blend_amount
func test_ads_blend_amount_is_zero_at_hip_ads_t_one() -> void:
	assert_float(FPArmsMath.ads_blend_amount(1.0)).is_equal_approx(0.0, 0.0001)


func test_ads_blend_amount_is_one_fully_aimed_ads_t_zero() -> void:
	assert_float(FPArmsMath.ads_blend_amount(0.0)).is_equal_approx(1.0, 0.0001)


func test_ads_blend_amount_is_clamped_within_0_1() -> void:
	assert_float(FPArmsMath.ads_blend_amount(1.5)).is_equal_approx(0.0, 0.0001)
	assert_float(FPArmsMath.ads_blend_amount(-0.5)).is_equal_approx(1.0, 0.0001)


# ---------------------------------------------------------------- reload_speed_for
func test_reload_speed_for_matches_the_reference_duration_on_ravage() -> void:
	# Ravage : resources/weapons/ravage.tres::reload_time = 2.5 -- le clip FP_Reload
	# doit alors jouer à vitesse 1.0 (référence 2.5 s).
	assert_float(FPArmsMath.reload_speed_for(2.5)).is_equal_approx(1.0, 0.0001)


func test_reload_speed_for_speeds_up_a_faster_weapon() -> void:
	assert_float(FPArmsMath.reload_speed_for(1.25)).is_equal_approx(2.0, 0.0001)


func test_reload_speed_for_slows_down_a_slower_weapon() -> void:
	assert_float(FPArmsMath.reload_speed_for(5.0)).is_equal_approx(0.5, 0.0001)


func test_reload_speed_for_is_defensive_against_an_invalid_reload_time() -> void:
	assert_float(FPArmsMath.reload_speed_for(0.0)).is_equal_approx(1.0, 0.0001)
	assert_float(FPArmsMath.reload_speed_for(-1.0)).is_equal_approx(1.0, 0.0001)


# ---------------------------------------------------------------- should_cancel_inspect
func test_should_cancel_inspect_is_false_when_idle() -> void:
	assert_bool(FPArmsMath.should_cancel_inspect(false, false, false)).is_false()


func test_should_cancel_inspect_is_true_when_firing() -> void:
	assert_bool(FPArmsMath.should_cancel_inspect(true, false, false)).is_true()


func test_should_cancel_inspect_is_true_when_aiming() -> void:
	assert_bool(FPArmsMath.should_cancel_inspect(false, true, false)).is_true()


func test_should_cancel_inspect_is_true_when_reloading() -> void:
	assert_bool(FPArmsMath.should_cancel_inspect(false, false, true)).is_true()
