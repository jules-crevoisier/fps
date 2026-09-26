## test_audio_helpers.gd
## Spec (contract-r2.md, "R-E audio — acceptance" #3 ; contract-r4a.md,
## "R4-AMB — ambiances et musique") : fonctions PURES d'Audio.gd (autoload
## "Sfx") — choix de variation, near/far, pitch, chemin de fichier, cadence de
## pas, catégorie d'arme, classification des capacités, détection de kill
## local, résolution d'ambiance de carte, courbe de fondu enchaîné,
## déclencheur de dernière minute, sting de résultat de match. Aucune
## dépendance à l'arbre de scène : appelées directement sur la classe, sans
## passer par l'autoload.
extends GdUnitTestSuite


# ---------------------------------------------------------------- variations

func test_pick_variation_distributes_across_range() -> void:
	assert_int(Audio.pick_variation(4, 0.0)).is_equal(0)
	assert_int(Audio.pick_variation(4, 0.99)).is_equal(3)
	assert_int(Audio.pick_variation(4, 0.26)).is_equal(1)


func test_pick_variation_single_count_always_zero() -> void:
	assert_int(Audio.pick_variation(1, 0.0)).is_equal(0)
	assert_int(Audio.pick_variation(1, 0.99)).is_equal(0)


func test_pick_variation_clamps_out_of_range_input() -> void:
	assert_int(Audio.pick_variation(3, 1.0)).is_equal(2)


func test_pick_variation_zero_count_is_zero() -> void:
	assert_int(Audio.pick_variation(0, 0.5)).is_equal(0)


# ---------------------------------------------------------------- near / far

func test_far_suffix_below_threshold_is_empty() -> void:
	assert_str(Audio.far_suffix(10.0)).is_equal("")
	assert_str(Audio.far_suffix(29.9)).is_equal("")


func test_far_suffix_at_or_beyond_threshold_is_far() -> void:
	assert_str(Audio.far_suffix(30.0)).is_equal("_far")
	assert_str(Audio.far_suffix(80.0)).is_equal("_far")


func test_far_suffix_custom_threshold() -> void:
	assert_str(Audio.far_suffix(12.0, 10.0)).is_equal("_far")
	assert_str(Audio.far_suffix(8.0, 10.0)).is_equal("")


# ---------------------------------------------------------------- pitch

func test_pitch_variation_is_centered_on_one() -> void:
	assert_float(Audio.pitch_variation(0.5)).is_equal_approx(1.0, 0.001)


func test_pitch_variation_stays_within_spread() -> void:
	assert_float(Audio.pitch_variation(0.0)).is_equal_approx(0.95, 0.001)
	assert_float(Audio.pitch_variation(1.0)).is_equal_approx(1.05, 0.001)


# ---------------------------------------------------------------- chemins

func test_sfx_path_is_one_based() -> void:
	assert_str(Audio.sfx_path("hitmarker", 0)).is_equal("res://assets/audio/sfx/hitmarker_1.wav")
	assert_str(Audio.sfx_path("hitmarker", 2)).is_equal("res://assets/audio/sfx/hitmarker_3.wav")


func test_strip_variation_suffix_removes_trailing_number() -> void:
	assert_str(Audio.strip_variation_suffix("gunshot_pistol_far_2")).is_equal("gunshot_pistol_far")
	assert_str(Audio.strip_variation_suffix("footstep_walk_4")).is_equal("footstep_walk")


func test_strip_variation_suffix_leaves_names_without_trailing_number() -> void:
	assert_str(Audio.strip_variation_suffix("menu_loop")).is_equal("menu_loop")


# ---------------------------------------------------------------- pas (cadence)

func test_footstep_stride_is_zero_when_almost_still() -> void:
	assert_float(Audio.footstep_stride(0.2, 5.2, 8.2)).is_equal_approx(0.0, 0.001)


func test_footstep_stride_walk_band() -> void:
	assert_str(Audio.footstep_sound_name(Audio.footstep_stride(3.0, 5.2, 8.2))).is_equal("footstep_walk")


func test_footstep_stride_sprint_band() -> void:
	assert_str(Audio.footstep_sound_name(Audio.footstep_stride(8.0, 5.2, 8.2))).is_equal("footstep_sprint")


func test_footstep_sound_name_empty_when_stride_zero() -> void:
	assert_str(Audio.footstep_sound_name(0.0)).is_equal("")


func test_footstep_ticks_triggers_step_past_stride() -> void:
	var r: Dictionary = Audio.footstep_ticks(0.0, 1.5, 1.3)
	assert_int(r.steps).is_equal(1)
	assert_float(r.accum).is_equal_approx(0.2, 0.001)


func test_footstep_ticks_accumulates_without_triggering() -> void:
	var r: Dictionary = Audio.footstep_ticks(0.0, 0.5, 1.3)
	assert_int(r.steps).is_equal(0)
	assert_float(r.accum).is_equal_approx(0.5, 0.001)


func test_footstep_ticks_handles_large_delta_with_multiple_steps() -> void:
	var r: Dictionary = Audio.footstep_ticks(0.0, 4.0, 1.3)
	assert_int(r.steps).is_equal(3)
	assert_float(r.accum).is_equal_approx(0.1, 0.01)


func test_footstep_ticks_zero_stride_never_triggers() -> void:
	var r: Dictionary = Audio.footstep_ticks(0.0, 10.0, 0.0)
	assert_int(r.steps).is_equal(0)
	assert_float(r.accum).is_equal_approx(0.0, 0.001)


func test_state_allows_footsteps() -> void:
	assert_bool(Audio.state_allows_footsteps("Walk")).is_true()
	assert_bool(Audio.state_allows_footsteps("Sprint")).is_true()
	assert_bool(Audio.state_allows_footsteps("Crouch")).is_true()
	assert_bool(Audio.state_allows_footsteps("Air")).is_false()
	assert_bool(Audio.state_allows_footsteps("Dive")).is_false()
	assert_bool(Audio.state_allows_footsteps("Stun")).is_false()
	assert_bool(Audio.state_allows_footsteps("Idle")).is_false()


# ---------------------------------------------------------------- catégorie d'arme

func _cfg(category: int, automatic: bool, damage: float) -> WeaponConfig:
	var c := WeaponConfig.new()
	c.category = category
	c.automatic = automatic
	c.damage = damage
	return c


func test_weapon_gunshot_name_sidearm_low_damage_is_pistol() -> void:
	var c := _cfg(WeaponConfig.Category.SIDEARM, false, 26.0)
	assert_str(Audio.weapon_gunshot_name(c)).is_equal("gunshot_pistol")


func test_weapon_gunshot_name_sidearm_high_damage_is_magnum() -> void:
	var c := _cfg(WeaponConfig.Category.SIDEARM, false, 55.0)
	assert_str(Audio.weapon_gunshot_name(c)).is_equal("gunshot_magnum")


func test_weapon_gunshot_name_rifle_automatic_is_rifle() -> void:
	var c := _cfg(WeaponConfig.Category.RIFLE, true, 40.0)
	assert_str(Audio.weapon_gunshot_name(c)).is_equal("gunshot_rifle")


func test_weapon_gunshot_name_rifle_semi_auto_is_marksman() -> void:
	var c := _cfg(WeaponConfig.Category.RIFLE, false, 65.0)
	assert_str(Audio.weapon_gunshot_name(c)).is_equal("gunshot_marksman")


func test_weapon_gunshot_name_smg() -> void:
	var c := _cfg(WeaponConfig.Category.SMG, true, 26.0)
	assert_str(Audio.weapon_gunshot_name(c)).is_equal("gunshot_smg")


func test_weapon_gunshot_name_shotgun() -> void:
	var c := _cfg(WeaponConfig.Category.SHOTGUN, true, 17.0)
	assert_str(Audio.weapon_gunshot_name(c)).is_equal("gunshot_shotgun")


func test_weapon_gunshot_name_sniper() -> void:
	var c := _cfg(WeaponConfig.Category.SNIPER, false, 150.0)
	assert_str(Audio.weapon_gunshot_name(c)).is_equal("gunshot_sniper")


func test_weapon_gunshot_name_null_config_falls_back_to_rifle() -> void:
	assert_str(Audio.weapon_gunshot_name(null)).is_equal("gunshot_rifle")


# ---------------------------------------------------------------- capacités

func test_ability_sound_name_ultimate_slot_is_always_ult() -> void:
	assert_str(Audio.ability_sound_name("X", "Anything")).is_equal("ult")


func test_ability_sound_name_matches_heal_keyword() -> void:
	assert_str(Audio.ability_sound_name("Q", "Soin d'urgence")).is_equal("heal")


func test_ability_sound_name_matches_wall_keyword() -> void:
	assert_str(Audio.ability_sound_name("C", "Mur de fortune")).is_equal("wall_slam")


func test_ability_sound_name_matches_dash_keyword() -> void:
	assert_str(Audio.ability_sound_name("C", "Ruée avant")).is_equal("dash")


func test_ability_sound_name_matches_stun_keyword() -> void:
	assert_str(Audio.ability_sound_name("E", "Piège étourdissant")).is_equal("stun_twinkle")


func test_ability_sound_name_matches_flash_keyword() -> void:
	assert_str(Audio.ability_sound_name("E", "Grenade aveuglante")).is_equal("flash")


func test_ability_sound_name_matches_smoke_keyword() -> void:
	assert_str(Audio.ability_sound_name("Q", "Voile de fumée")).is_equal("smoke")


func test_ability_sound_name_matches_reveal_keyword() -> void:
	assert_str(Audio.ability_sound_name("E", "Détection ennemie")).is_equal("reveal")


func test_ability_sound_name_unknown_falls_back_to_generic() -> void:
	assert_str(Audio.ability_sound_name("C", "Mystère")).is_equal("ability_generic")


# ---------------------------------------------------------------- kill local

func test_is_local_kill_true_when_killer_is_local_and_victim_is_not() -> void:
	assert_bool(Audio.is_local_kill(7, 7, false)).is_true()


func test_is_local_kill_false_when_victim_is_local() -> void:
	assert_bool(Audio.is_local_kill(7, 7, true)).is_false()


func test_is_local_kill_false_when_killer_is_someone_else() -> void:
	assert_bool(Audio.is_local_kill(3, 7, false)).is_false()


func test_is_local_kill_false_for_environment_kill() -> void:
	assert_bool(Audio.is_local_kill(0, 7, false)).is_false()


# ---------------------------------------------------------------- ambiance de carte

func test_ambience_name_for_map_known_ids() -> void:
	assert_str(Audio.ambience_name_for_map("port_ferraille")).is_equal("ambience_port_ferraille")
	assert_str(Audio.ambience_name_for_map("val_poussiere")).is_equal("ambience_val_poussiere")
	assert_str(Audio.ambience_name_for_map("saint_ombre")).is_equal("ambience_saint_ombre")
	assert_str(Audio.ambience_name_for_map("col_du_vautour")).is_equal("ambience_col_du_vautour")
	assert_str(Audio.ambience_name_for_map("la_fosse")).is_equal("ambience_la_fosse")
	assert_str(Audio.ambience_name_for_map("le_belvedere")).is_equal("ambience_le_belvedere")


func test_ambience_name_for_map_empty_id_is_silence() -> void:
	assert_str(Audio.ambience_name_for_map("")).is_equal("")


func test_ambience_name_for_map_unknown_id_is_silence() -> void:
	assert_str(Audio.ambience_name_for_map("carte_inconnue")).is_equal("")


# ---------------------------------------------------------------- fondu enchaîné (crossfade)

func test_crossfade_progress_clamps_to_unit_range() -> void:
	assert_float(Audio.crossfade_progress(-1.0, 2.0)).is_equal_approx(0.0, 0.001)
	assert_float(Audio.crossfade_progress(1.0, 2.0)).is_equal_approx(0.5, 0.001)
	assert_float(Audio.crossfade_progress(5.0, 2.0)).is_equal_approx(1.0, 0.001)


func test_crossfade_progress_zero_duration_is_instantaneous() -> void:
	assert_float(Audio.crossfade_progress(0.0, 0.0)).is_equal_approx(1.0, 0.001)


func test_crossfade_gain_curve_endpoints() -> void:
	assert_float(Audio.crossfade_gain_out(0.0)).is_equal_approx(1.0, 0.001)
	assert_float(Audio.crossfade_gain_out(1.0)).is_equal_approx(0.0, 0.001)
	assert_float(Audio.crossfade_gain_in(0.0)).is_equal_approx(0.0, 0.001)
	assert_float(Audio.crossfade_gain_in(1.0)).is_equal_approx(1.0, 0.001)


func test_crossfade_gain_curve_is_equal_power_at_midpoint() -> void:
	var out_g := Audio.crossfade_gain_out(0.5)
	var in_g := Audio.crossfade_gain_in(0.5)
	assert_float(out_g).is_equal_approx(in_g, 0.001)
	# Puissance constante : somme des carrés des gains == 1 partout sur la courbe.
	assert_float(out_g * out_g + in_g * in_g).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------- dernière minute

func test_is_last_minute_true_inside_window() -> void:
	assert_bool(Audio.is_last_minute(560.0, 600.0)).is_true()
	assert_bool(Audio.is_last_minute(599.9, 600.0)).is_true()


func test_is_last_minute_false_before_window() -> void:
	assert_bool(Audio.is_last_minute(539.9, 600.0)).is_false()


func test_is_last_minute_false_at_or_past_limit() -> void:
	assert_bool(Audio.is_last_minute(600.0, 600.0)).is_false()
	assert_bool(Audio.is_last_minute(650.0, 600.0)).is_false()


func test_is_last_minute_false_when_no_match_timer() -> void:
	assert_bool(Audio.is_last_minute(30.0, 0.0)).is_false()
	assert_bool(Audio.is_last_minute(30.0, -1.0)).is_false()


func test_is_last_minute_custom_window() -> void:
	assert_bool(Audio.is_last_minute(91.0, 100.0, 10.0)).is_true()
	assert_bool(Audio.is_last_minute(85.0, 100.0, 10.0)).is_false()


# ---------------------------------------------------------------- sting de résultat de match

func test_match_result_sting_victory_when_local_team_wins() -> void:
	assert_str(Audio.match_result_sting(0, 0)).is_equal("match_victory")


func test_match_result_sting_defeat_when_other_team_wins() -> void:
	assert_str(Audio.match_result_sting(1, 0)).is_equal("match_defeat")


func test_match_result_sting_empty_while_undecided() -> void:
	assert_str(Audio.match_result_sting(-1, 0)).is_equal("")


func test_match_result_sting_empty_without_local_player() -> void:
	assert_str(Audio.match_result_sting(0, -1)).is_equal("")
