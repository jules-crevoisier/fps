## test_fp_arms_rig_throw.gd
## Spec (tâche "utilitaires", contrat lead : "write the code against this
## contract and don't crash if they are missing") : FP_Throw_Ready/FP_Throw
## sont livrés par le lead EN PARALLÈLE de cette tâche sur le MÊME glb
## (assets/models/characters/frog_cowboy_fp.glb) que les 7 clips existants.
## Ce fichier ne suppose RIEN sur leur présence au moment où il tourne (les
## deux tâches avancent en parallèle) : il prouve seulement que
## - le chargement du rig ne régresse JAMAIS (les clips optionnels ne font
##   PAS partie du critère d'échec de `load()`, voir FPArmsRig._CLIPS) ;
## - has_throw_clips()/set_throw_ready()/trigger_throw() ne plantent jamais,
##   qu'ils soient câblés ou non.
extends GdUnitTestSuite


func _loaded_rig() -> FPArmsRig:
	var rig: FPArmsRig = auto_free(FPArmsRig.new())
	add_child(rig)
	assert_bool(rig.load()).is_true()
	return rig


func test_rig_still_loads_regardless_of_optional_throw_clips() -> void:
	var rig := _loaded_rig()
	assert_bool(rig.is_loaded()).is_true()
	for clip in ["FP_Idle", "FP_ADS", "FP_Fire", "FP_Reload", "FP_Draw", "FP_Sprint", "FP_Inspect"]:
		assert_bool(rig.has_clip(clip)).append_failure_message(
			"les clips obligatoires ne doivent JAMAIS dépendre des clips de lancer optionnels"
		).is_true()


func test_throw_controls_never_crash_whether_or_not_clips_are_present() -> void:
	var rig := _loaded_rig()
	# Ne présume rien du résultat (dépend de l'avancement du lead sur le glb) :
	# seul le fait de pouvoir appeler ces méthodes sans exception est vérifié.
	rig.set_throw_ready(true)
	rig.set_throw_ready(false)
	rig.trigger_throw()
	assert_bool(rig.has_throw_clips()).is_equal(rig.has_clip("FP_Throw_Ready") and rig.has_clip("FP_Throw"))


func test_throw_ready_blend_param_only_exists_when_both_clips_are_present() -> void:
	var rig := _loaded_rig()
	if not rig.has_throw_clips():
		return  # clips pas encore livrés au moment de ce run -- rien à vérifier de plus.
	rig.set_throw_ready(true)
	assert_float(rig.get_tree_param("parameters/ThrowReadyBlend/blend_amount")).is_equal_approx(1.0, 0.001)
	rig.set_throw_ready(false)
	assert_float(rig.get_tree_param("parameters/ThrowReadyBlend/blend_amount")).is_equal_approx(0.0, 0.001)


## Livrés par le lead le 2026-09-27 : les clips de lancer et l'os GrenadeGrip font
## désormais partie du glb FP (plus de tolérance « pas encore là »).
func test_throw_clips_and_grenade_grip_are_delivered() -> void:
	var rig := _loaded_rig()
	assert_bool(rig.has_throw_clips()).is_true()
	assert_bool(rig.has_grenade_grip()).is_true()


## Grenade modélisée à l'échelle réelle : attachée sous l'os d'un rig mis à
## l'échelle RIG_SCALE, elle est contre-échelonnée (sinon frag de 20 cm) puis
## grossie de HELD_GRENADE_FP_SCALE seulement, pour rester lisible dans le poing.
func test_attached_grenade_is_counter_scaled_then_readability_scaled() -> void:
	var rig := _loaded_rig()
	var nade: Node3D = auto_free(Node3D.new())
	rig.attach_grenade(nade)
	assert_object(nade.get_parent()).is_not_null()
	var expected := FPArmsMath.weapon_counter_scale(FPArmsMath.RIG_SCALE) * FPArmsRig.HELD_GRENADE_FP_SCALE
	assert_vector(nade.scale).is_equal_approx(expected, Vector3.ONE * 0.001)
	var world_scale := nade.global_transform.basis.get_scale()
	var rig_scale := rig.global_transform.basis.get_scale()
	assert_float(world_scale.x).is_equal_approx(rig_scale.x / FPArmsMath.RIG_SCALE * FPArmsRig.HELD_GRENADE_FP_SCALE, 0.001)
