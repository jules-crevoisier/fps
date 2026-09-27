## test_fp_arms_rig_revolver.gd
## Spec (design verrouillé utilisateur, tâche "revolver" 2026-09-27) : quand le
## Revolver est équipé, FPArmsRig doit utiliser le jeu de clips FPP_*/l'os
## "PistolGrip" au lieu de FP_*/"WeaponGrip" — bascule PROPRE (une carte de
## noms de clip par arme, le graphe de blend RE-POINTÉ jamais reconstruit,
## voir FPArmsRig.use_weapon_clip_set) et repli SILENCIEUX sur le jeu Ravage
## tant que FPP_*/"PistolGrip" ne sont pas encore livrés (même discipline que
## `_has_throw_clips`, voir tests/player/test_fp_arms_rig_throw.gd).
##
## Le lead a livré les clips FPP_*/l'os "PistolGrip" le 2026-09-27 (voir le
## rapport de tâche) : ce fichier vérifie d'abord que le chemin RÉEL (glb
## chargé tel quel) fonctionne, puis simule l'ABSENCE (en forçant le champ
## interne `_has_revolver_clip_set`, convention déjà utilisée dans ce dépôt
## pour tester un repli sans dépendre d'un second asset factice) pour couvrir
## le repli lui-même.
extends GdUnitTestSuite


func _loaded_rig() -> FPArmsRig:
	var rig: FPArmsRig = auto_free(FPArmsRig.new())
	add_child(rig)
	assert_bool(rig.load()).is_true()
	return rig


# ---------------------------------------------------------------- livraison lead
func test_revolver_clip_set_is_delivered_on_the_real_asset() -> void:
	var rig := _loaded_rig()
	assert_bool(rig.has_revolver_clip_set()).append_failure_message(
		"les 7 clips FPP_*/l'os \"PistolGrip\" doivent être présents sur "
			+ "frog_cowboy_fp.glb (livrés par le lead, voir le rapport de tâche) -- "
			+ "si ceci échoue, le repli WeaponGrip/FP_* est encore actif"
	).is_true()


func test_fpp_idle_loops() -> void:
	var rig := _loaded_rig()
	var ap := rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_object(ap).is_not_null()
	assert_bool(ap.has_animation("FPP_Idle")).is_true()
	assert_int(ap.get_animation("FPP_Idle").loop_mode).append_failure_message(
		"FPP_Idle doit boucler (contrat lead) -- sinon la respiration se fige à la dernière image"
	).is_equal(Animation.LOOP_LINEAR)


# ---------------------------------------------------------------- bascule de jeu de clips
func test_default_clip_set_is_ravage() -> void:
	var rig := _loaded_rig()
	assert_str(rig.active_clip_name("idle")).is_equal("FP_Idle")
	assert_str(rig.active_clip_name("grip_bone")).is_equal("WeaponGrip")


func test_use_weapon_clip_set_true_switches_to_the_revolver_clip_names() -> void:
	var rig := _loaded_rig()
	rig.use_weapon_clip_set(true)
	assert_str(rig.active_clip_name("idle")).is_equal("FPP_Idle")
	assert_str(rig.active_clip_name("ads_in")).is_equal("FPP_ADS_In")
	assert_str(rig.active_clip_name("fire")).is_equal("FPP_Fire")
	assert_str(rig.active_clip_name("fan")).is_equal("FPP_Fan")
	assert_str(rig.active_clip_name("reload")).is_equal("FPP_Reload")
	assert_str(rig.active_clip_name("draw")).is_equal("FPP_Draw")
	assert_str(rig.active_clip_name("inspect")).is_equal("FPP_Inspect")
	assert_str(rig.active_clip_name("grip_bone")).is_equal("PistolGrip")


func test_use_weapon_clip_set_false_reverts_to_ravage() -> void:
	var rig := _loaded_rig()
	rig.use_weapon_clip_set(true)
	rig.use_weapon_clip_set(false)
	assert_str(rig.active_clip_name("idle")).is_equal("FP_Idle")
	assert_str(rig.active_clip_name("grip_bone")).is_equal("WeaponGrip")


func test_attach_weapon_uses_pistol_grip_after_switching_to_the_revolver_clip_set() -> void:
	var rig := _loaded_rig()
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	rig.align_to_camera(cam, Transform3D.IDENTITY, 1.0)

	rig.use_weapon_clip_set(true)
	var weapon: Node3D = auto_free(Node3D.new())
	rig.attach_weapon(weapon)

	var parent := weapon.get_parent() as BoneAttachment3D
	assert_object(parent).is_not_null()
	assert_str(parent.bone_name).append_failure_message(
		"le Revolver doit s'attacher sous l'os \"PistolGrip\", pas \"WeaponGrip\""
	).is_equal("PistolGrip")


func test_attach_weapon_reuses_weapon_grip_after_switching_back_to_ravage() -> void:
	var rig := _loaded_rig()
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	rig.align_to_camera(cam, Transform3D.IDENTITY, 1.0)

	rig.use_weapon_clip_set(true)
	var revolver_model: Node3D = auto_free(Node3D.new())
	rig.attach_weapon(revolver_model)

	rig.use_weapon_clip_set(false)
	var ravage_model: Node3D = auto_free(Node3D.new())
	rig.attach_weapon(ravage_model)

	var parent := ravage_model.get_parent() as BoneAttachment3D
	assert_object(parent).is_not_null()
	assert_str(parent.bone_name).is_equal("WeaponGrip")
	# La même BoneAttachment3D est réutilisée (jamais un second nœud) -- voir
	# `_ensure_weapon_attachment` : `bone_name` réassigné à chaud.
	assert_object(revolver_model.get_parent()).append_failure_message(
		"le Ravage réattaché doit détacher le Revolver (jamais les deux enfants à la fois)"
	).is_not_equal(parent)


func test_use_weapon_clip_set_is_idempotent_when_already_active() -> void:
	var rig := _loaded_rig()
	rig.use_weapon_clip_set(true)
	rig.use_weapon_clip_set(true)  # ne doit ni planter ni changer quoi que ce soit.
	assert_str(rig.active_clip_name("grip_bone")).is_equal("PistolGrip")


func test_trigger_reload_scales_to_the_active_reload_clip_length() -> void:
	var rig := _loaded_rig()
	rig.use_weapon_clip_set(true)
	var clip_len := rig.clip_length("FPP_Reload")
	assert_float(clip_len).append_failure_message(
		"préalable du test : FPP_Reload doit avoir une durée authored positive"
	).is_greater(0.0)
	rig.trigger_reload(2.4)  # revolver.tres reload_time
	var expected := FPArmsMath.reload_speed_for(2.4, clip_len)
	assert_float(rig.get_tree_param("parameters/ReloadSpeed/scale")).is_equal_approx(expected, 0.001)


func test_trigger_fan_does_not_crash_regardless_of_active_clip_set() -> void:
	var rig := _loaded_rig()
	rig.trigger_fan()  # jeu Ravage actif par défaut : no-op silencieux.
	rig.use_weapon_clip_set(true)
	rig.trigger_fan()  # jeu Revolver actif : doit déclencher sans planter.


# ---------------------------------------------------------------- repli sans FPP_*/PistolGrip
func test_use_weapon_clip_set_true_falls_back_silently_without_the_revolver_clip_set() -> void:
	var rig := _loaded_rig()
	# Simule l'absence des clips FPP_*/de l'os "PistolGrip" (contrat : "fall
	# back without crashing" tant que le lead ne les a pas exportés) -- champ
	# interne, même convention que le reste de ce dépôt pour tester un repli
	# sans dépendre d'un second glb factice.
	rig.set("_has_revolver_clip_set", false)
	rig.use_weapon_clip_set(true)
	assert_str(rig.active_clip_name("idle")).append_failure_message(
		"sans le jeu de clips revolver, use_weapon_clip_set(true) doit rester sur Ravage"
	).is_equal("FP_Idle")
	assert_str(rig.active_clip_name("grip_bone")).is_equal("WeaponGrip")

	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	rig.align_to_camera(cam, Transform3D.IDENTITY, 1.0)
	var weapon: Node3D = auto_free(Node3D.new())
	rig.attach_weapon(weapon)
	var parent := weapon.get_parent() as BoneAttachment3D
	assert_object(parent).is_not_null()
	assert_str(parent.bone_name).append_failure_message(
		"repli : l'arme doit rester attachée sous \"WeaponGrip\" sans le jeu revolver"
	).is_equal("WeaponGrip")
