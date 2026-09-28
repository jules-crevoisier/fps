## test_fp_arms_rig.gd
## Spec (tâche "frog fp arms") : FPArmsRig.gd charge
## assets/models/characters/frog_cowboy_fp.glb (bras+manchon peints, rig
## Mixamo "mixamorig_*" + les deux os ajoutés "WeaponGrip"/"FPCamera", voir
## FPArmsMath.gd pour les maths d'alignement) et l'attache au monde du
## joueur : alignement caméra (`align_to_camera`), attache de l'arme sous
## l'os "WeaponGrip" (`attach_weapon`), sélection de clip par événement
## (tir/rechargement/équipement/sprint/inspection).
##
## Ces tests chargent le VRAI glb (comme test_fp_gloves.gd charge le vrai
## fp_gloves.glb) : pas de double -- FPArmsMath.gd couvre déjà les maths en
## isolation (tests/player/test_fp_arms_math.gd) avec des valeurs de repos
## FPCamera synthétiques ; ici on vérifie que le VRAI asset expose bien ce
## que FPArmsRig attend (os, clips) et que le câblage (AnimationTree,
## BoneAttachment3D) produit le résultat annoncé par le contrat.
extends GdUnitTestSuite

const FP_ARMS_PATH := "res://assets/models/characters/frog_cowboy_fp.glb"


func _loaded_rig() -> FPArmsRig:
	var rig: FPArmsRig = auto_free(FPArmsRig.new())
	add_child(rig)
	assert_bool(rig.load()).is_true()
	return rig


# ---------------------------------------------------------------- chargement / repli
func test_load_succeeds_on_the_real_asset() -> void:
	var rig: FPArmsRig = auto_free(FPArmsRig.new())
	add_child(rig)
	assert_bool(rig.load()).is_true()
	assert_bool(rig.is_loaded()).is_true()


func test_load_fails_gracefully_on_a_missing_resource() -> void:
	var rig: FPArmsRig = auto_free(FPArmsRig.new())
	add_child(rig)
	assert_bool(rig.load("res://assets/models/characters/does_not_exist.glb")).is_false()
	assert_bool(rig.is_loaded()).is_false()


func test_loaded_rig_exposes_all_seven_fp_clips() -> void:
	var rig := _loaded_rig()
	for clip in ["FP_Idle", "FP_ADS", "FP_ADS_In", "FP_Fire", "FP_Reload", "FP_Draw", "FP_Sprint", "FP_Inspect"]:
		assert_bool(rig.has_clip(clip)).is_true()


func test_clip_length_reports_a_positive_duration_for_a_known_clip() -> void:
	var rig := _loaded_rig()
	assert_float(rig.clip_length("FP_Inspect")).is_greater(0.0)


func test_clip_length_is_zero_for_an_unknown_clip() -> void:
	var rig := _loaded_rig()
	assert_float(rig.clip_length("FP_DoesNotExist")).is_equal_approx(0.0, 0.0001)


# ---------------------------------------------------------------- alignement caméra
func test_fp_camera_bone_coincides_with_the_real_camera_after_alignment() -> void:
	var rig := _loaded_rig()
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	cam.global_position = Vector3(3.0, 1.6, -4.0)
	cam.global_rotation = Vector3(0.0, deg_to_rad(52.0), 0.0)

	rig.align_to_camera(cam, Transform3D.IDENTITY, 1.0)

	var world := rig.fp_camera_global_pose()
	assert_vector(world.origin).is_equal_approx(cam.global_position, Vector3.ONE * 0.001)
	var forward_rig: Vector3 = -world.basis.z.normalized()
	var forward_cam: Vector3 = -cam.global_transform.basis.z.normalized()
	assert_float(forward_rig.dot(forward_cam)).is_greater(0.999)


func test_align_to_camera_applies_a_camera_local_procedural_offset() -> void:
	var rig := _loaded_rig()
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	cam.global_position = Vector3.ZERO
	cam.global_rotation = Vector3.ZERO

	# Sans offset : l'os FPCamera doit coïncider pile avec la caméra.
	rig.align_to_camera(cam, Transform3D.IDENTITY, 1.0)
	var base_origin: Vector3 = rig.fp_camera_global_pose().origin

	# Avec un petit offset caméra-locale (sway), l'os doit suivre le décalage
	# -- le rig existe justement pour porter ce "feel" procédural par-dessus
	# l'alignement pur (voir ViewModel._process, requirement 1).
	var nudge := Transform3D(Basis.IDENTITY, Vector3(0.02, -0.01, 0.0))
	rig.align_to_camera(cam, nudge, 1.0)
	var nudged_origin: Vector3 = rig.fp_camera_global_pose().origin

	assert_vector(nudged_origin - base_origin).is_equal_approx(Vector3(0.02, -0.01, 0.0), Vector3.ONE * 0.001)


# ---------------------------------------------------------------- attache de l'arme
func test_weapon_attaches_under_weapon_grip_with_global_scale_about_one() -> void:
	var rig := _loaded_rig()
	# `align_to_camera` porte le facteur RIG_SCALE (voir FPArmsMath -- la preuve
	# de classe : c'est la magnitude de `rig_root.global_transform.basis` qui
	# porte l'échelle, jamais une échelle statique posée une fois pour toutes)
	# -- en jeu, ViewModel._process l'appelle CHAQUE frame avant que quoi que ce
	# soit ne soit rendu, donc toujours au moins une fois avant que l'arme ne
	# soit effectivement affichée à l'écran.
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	rig.align_to_camera(cam, Transform3D.IDENTITY, 1.0)
	var weapon: Node3D = auto_free(Node3D.new())
	rig.attach_weapon(weapon)

	assert_object(weapon.get_parent()).is_not_null()
	assert_bool(weapon.get_parent() is BoneAttachment3D).is_true()
	var parent := weapon.get_parent() as BoneAttachment3D
	assert_str(parent.bone_name).is_equal("WeaponGrip")
	assert_vector(weapon.transform.origin).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.0001)

	var s: Vector3 = weapon.global_transform.basis.get_scale()
	assert_float(s.x).is_equal_approx(1.0, 0.02)
	assert_float(s.y).is_equal_approx(1.0, 0.02)
	assert_float(s.z).is_equal_approx(1.0, 0.02)


func test_attach_weapon_is_idempotent_and_reuses_the_same_attachment() -> void:
	var rig := _loaded_rig()
	var weapon_a: Node3D = auto_free(Node3D.new())
	var weapon_b: Node3D = auto_free(Node3D.new())
	rig.attach_weapon(weapon_a)
	var attach_a := weapon_a.get_parent()
	rig.attach_weapon(weapon_b)
	var attach_b := weapon_b.get_parent()
	assert_object(attach_a).is_equal(attach_b)
	assert_bool(is_instance_valid(weapon_a)).is_true()  # le repère détache mais ne libère pas l'ancienne arme (ViewModel._model gère sa propre durée de vie).


# ---------------------------------------------------------------- cadrage FP par arme (tâche "cadrage FP quatre armes")
## Ravage/Revolver (ids 0/1) HORS PÉRIMÈTRE de cette tâche (jamais retouchés, la référence de cadrage
## qui fonctionne déjà avec une transform IDENTITÉ) -- tout id sans entrée dans les tables (y compris
## un id négatif, ex. les appels de test ci-dessus/`rig.attach_weapon(weapon)` sans 3e argument) doit
## rester neutre. Verrou de calibration pour les 4 armes réglées (2, 3, 4, 5) : voir
## reports/checkpoints/2026-09-28_weapons_v3/fp_framing.json pour les mesures qui ont produit ces
## valeurs -- à mettre à jour dans le MÊME changement si ces constantes sont re-réglées.
func test_grip_offset_is_identity_for_weapons_outside_this_tasks_scope() -> void:
	for id in [-1, 0, 1, 6, 99]:
		assert_vector(FPArmsRig.grip_offset_for(id)).append_failure_message(
			"id %d devrait rester à l'identité (Vector3.ZERO)" % id
		).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.0001)


func test_grip_rotation_is_identity_for_weapons_outside_this_tasks_scope() -> void:
	# Rafale (id 2) et Fracas (id 3) ont chacun une rotation dédiée (roulis/tangage, voir
	# test_grip_table_pins_the_measured_calibration_for_the_four_tuned_weapons) -- exclus d'ici.
	for id in [-1, 0, 1, 4, 5, 6]:
		assert_vector(FPArmsRig.grip_rotation_deg_for(id)).append_failure_message(
			"id %d devrait rester à l'identité (Vector3.ZERO)" % id
		).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.0001)


func test_grip_scale_mult_is_neutral_for_weapons_outside_this_tasks_scope() -> void:
	for id in [-1, 0, 1, 6]:   # Rafale (2) a désormais son échelle propre, épinglée plus bas
		assert_float(FPArmsRig.grip_scale_mult_for(id)).append_failure_message(
			"id %d devrait rester à l'échelle neutre (1.0)" % id
		).is_equal_approx(1.0, 0.0001)


func test_grip_table_pins_the_measured_calibration_for_the_four_tuned_weapons() -> void:
	# Rafale : re-réglé (playtest utilisateur, 2026-09-28 -- « la main ne tient pas la crosse ») --
	# voir la note "3e passage, Rafale SEULE" dans FPArmsRig.gd/_GRIP_POS_BY_ID pour la mesure.
	assert_vector(FPArmsRig.grip_offset_for(2)).append_failure_message("Rafale").is_equal_approx(
		Vector3(0.0, 0.051, 0.021), Vector3.ONE * 0.0001)
	assert_vector(FPArmsRig.grip_offset_for(3)).append_failure_message("Fracas").is_equal_approx(
		Vector3(0.0, -0.02, -0.04), Vector3.ONE * 0.0001)
	assert_vector(FPArmsRig.grip_offset_for(4)).append_failure_message("Verdict").is_equal_approx(
		Vector3(0.02, 0.08, -0.05), Vector3.ONE * 0.0001)
	assert_vector(FPArmsRig.grip_offset_for(5)).append_failure_message("Aiguille").is_equal_approx(
		Vector3(0.02, -0.03, 0.0), Vector3.ONE * 0.0001)

	# Revue visuelle du lead (2026-09-28) : même repère que Ravage => aucune rotation.
	for id in [2, 3, 4, 5]:
		assert_vector(FPArmsRig.grip_rotation_deg_for(id)).append_failure_message(str(id)).is_equal(Vector3.ZERO)

	assert_float(FPArmsRig.grip_scale_mult_for(2)).append_failure_message("Rafale").is_equal_approx(0.85, 0.0001)
	assert_float(FPArmsRig.grip_scale_mult_for(3)).append_failure_message("Fracas").is_equal_approx(1.3, 0.0001)
	assert_float(FPArmsRig.grip_scale_mult_for(4)).append_failure_message("Verdict").is_equal_approx(0.85, 0.0001)
	assert_float(FPArmsRig.grip_scale_mult_for(5)).append_failure_message("Aiguille").is_equal_approx(1.05, 0.0001)


## `attach_weapon` transmet bien `weapon_id` à `grip_offset_for`/`grip_rotation_deg_for`/
## `grip_scale_mult_for` -- intégration (pas juste les fonctions pures ci-dessus) : le Fracas (id 3)
## porte à la fois un décalage ET une rotation non nuls, un bon cas pour vérifier que LES DEUX sont
## bien appliqués sur le nœud réellement attaché (pas seulement lisibles depuis les fonctions pures).
func test_attach_weapon_applies_the_per_weapon_grip_offset_and_rotation() -> void:
	var rig := _loaded_rig()
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	rig.align_to_camera(cam, Transform3D.IDENTITY, 1.0)
	var weapon: Node3D = auto_free(Node3D.new())
	rig.attach_weapon(weapon, 3)  # Fracas.

	var expected_local_pos := FPArmsMath.weapon_grip_offset(FPArmsRig.grip_offset_for(3), FPArmsMath.RIG_SCALE)
	assert_vector(weapon.position).is_equal_approx(expected_local_pos, Vector3.ONE * 0.0001)

	var rot_deg := FPArmsRig.grip_rotation_deg_for(3)
	var expected_rot := Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	assert_vector(weapon.rotation).is_equal_approx(expected_rot, Vector3.ONE * 0.0001)


## Un id SANS réglage (Ravage/Revolver, ids 0/1) garde EXACTEMENT le comportement identité mesuré par
## `test_weapon_attaches_under_weapon_grip_with_global_scale_about_one` ci-dessus, même en passant
## l'id explicitement (pas seulement le repli -1 par défaut) -- non-régression sur la référence de
## cadrage jamais retouchée par cette tâche.
func test_attach_weapon_stays_at_identity_for_ravage_and_revolver_ids() -> void:
	var rig := _loaded_rig()
	var cam: Camera3D = auto_free(Camera3D.new())
	add_child(cam)
	rig.align_to_camera(cam, Transform3D.IDENTITY, 1.0)
	for id in [0, 1]:
		var weapon: Node3D = auto_free(Node3D.new())
		rig.attach_weapon(weapon, id)
		assert_vector(weapon.position).append_failure_message("id %d" % id).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.0001)
		assert_vector(weapon.rotation).append_failure_message("id %d" % id).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.0001)


# ---------------------------------------------------------------- sélection de clip / paramètres
func test_set_ads_amount_drives_the_idle_ads_blend_parameter() -> void:
	var rig := _loaded_rig()
	rig.set_ads_amount(0.75)
	# Visée à 75 % : pose de visée pleinement retenue (au-delà du relais de 20 %).
	assert_float(rig.get_tree_param("parameters/IdleAds/blend_amount")).is_equal_approx(1.0, 0.001)


func test_set_sprint_amount_drives_the_sprint_blend_parameter() -> void:
	var rig := _loaded_rig()
	rig.set_sprint_amount(0.4)
	assert_float(rig.get_tree_param("parameters/SprintBlend/blend_amount")).is_equal_approx(0.4, 0.001)


func test_trigger_reload_sets_the_speed_scale_from_reload_time() -> void:
	var rig := _loaded_rig()
	rig.trigger_reload(1.25)  # FPArmsMath.reload_speed_for(1.25) == 2.0
	assert_float(rig.get_tree_param("parameters/ReloadSpeed/scale")).is_equal_approx(2.0, 0.001)


func test_trigger_and_cancel_inspect_do_not_error_when_called_out_of_order() -> void:
	var rig := _loaded_rig()
	# Aucune assertion de comportement AnimationTree interne ici (déjà couvert
	# par should_cancel_inspect en isolation) -- seulement l'absence de plantage
	# sur l'ordre défensif cancel -> trigger -> cancel -> cancel.
	rig.cancel_inspect()
	rig.trigger_inspect()
	rig.cancel_inspect()
	rig.cancel_inspect()
