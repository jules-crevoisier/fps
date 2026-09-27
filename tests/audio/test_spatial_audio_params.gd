## test_spatial_audio_params.gd
## Spec (tâche "son", 2026-09-27, point 2 "spatialisation 3D") : table PURE
## catégorie -> réglages AudioStreamPlayer3D (unit_size/max_distance/modèle
## d'atténuation/filtre de distance/panoramique) — gunshots entendus à travers
## toute la carte (max_distance = 0.0, Godot : pas de coupure), pas ~15 m
## (marche) / ~30 m (sprint), grenade/explosion à leurs propres portées.
extends GdUnitTestSuite


func test_category_for_sound_classifies_gunshots() -> void:
	assert_str(SpatialAudioParams.category_for_sound("gunshot_rifle")).is_equal("gunshot")
	assert_str(SpatialAudioParams.category_for_sound("gunshot_revolver_far")).is_equal("gunshot")


func test_category_for_sound_classifies_footsteps_including_metal_variant() -> void:
	assert_str(SpatialAudioParams.category_for_sound("footstep_walk")).is_equal("footstep_walk")
	assert_str(SpatialAudioParams.category_for_sound("footstep_sprint")).is_equal("footstep_sprint")
	assert_str(SpatialAudioParams.category_for_sound("footstep_metal_walk")).is_equal("footstep_walk")
	assert_str(SpatialAudioParams.category_for_sound("footstep_metal_sprint")).is_equal("footstep_sprint")


func test_category_for_sound_classifies_grenade_flight_sounds() -> void:
	assert_str(SpatialAudioParams.category_for_sound("grenade_pin")).is_equal("grenade")
	assert_str(SpatialAudioParams.category_for_sound("grenade_throw")).is_equal("grenade")
	assert_str(SpatialAudioParams.category_for_sound("grenade_bounce")).is_equal("grenade")


func test_category_for_sound_classifies_detonations_as_explosion() -> void:
	assert_str(SpatialAudioParams.category_for_sound("explosion")).is_equal("explosion")
	assert_str(SpatialAudioParams.category_for_sound("flash")).is_equal("explosion")
	assert_str(SpatialAudioParams.category_for_sound("smoke")).is_equal("explosion")


func test_category_for_sound_unknown_falls_back_to_default() -> void:
	assert_str(SpatialAudioParams.category_for_sound("dry_fire")).is_equal("default")


func test_params_for_gunshot_has_no_distance_ceiling() -> void:
	var p: Dictionary = SpatialAudioParams.params_for("gunshot")
	assert_float(p["max_distance"]).is_equal_approx(0.0, 0.001)
	assert_int(p["attenuation_model"]).is_equal(AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE)


func test_params_for_footstep_walk_is_shorter_range_than_sprint() -> void:
	var walk: Dictionary = SpatialAudioParams.params_for("footstep_walk")
	var sprint: Dictionary = SpatialAudioParams.params_for("footstep_sprint")
	assert_float(walk["max_distance"]).is_equal_approx(15.0, 0.001)
	assert_float(sprint["max_distance"]).is_equal_approx(30.0, 0.001)


func test_params_for_explosion_has_no_distance_ceiling() -> void:
	var p: Dictionary = SpatialAudioParams.params_for("explosion")
	assert_float(p["max_distance"]).is_equal_approx(0.0, 0.001)


func test_params_for_grenade_has_a_bounded_range() -> void:
	var p: Dictionary = SpatialAudioParams.params_for("grenade")
	assert_float(p["max_distance"]).is_greater(0.0)
	assert_float(p["max_distance"]).is_less(30.0)


func test_params_for_unknown_category_returns_default_table() -> void:
	var p: Dictionary = SpatialAudioParams.params_for("nope")
	assert_bool(p.has("max_distance")).is_true()
	assert_bool(p.has("unit_size")).is_true()
	assert_bool(p.has("attenuation_model")).is_true()
	assert_bool(p.has("attenuation_filter_cutoff_hz")).is_true()
	assert_bool(p.has("attenuation_filter_db")).is_true()
	assert_bool(p.has("panning_strength")).is_true()


func test_apply_to_sets_properties_on_a_real_player() -> void:
	var p3d := AudioStreamPlayer3D.new()
	SpatialAudioParams.apply_to(p3d, "footstep_sprint")
	assert_float(p3d.max_distance).is_equal_approx(30.0, 0.001)
	assert_int(p3d.doppler_tracking).is_equal(AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED)
	p3d.free()
