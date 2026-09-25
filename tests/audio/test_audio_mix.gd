## test_audio_mix.gd
## Spec (GF-11, docs/research/01_game_feel.md §2.5 "Audio d'arme en couches" +
## tasks/backlog.yaml) : fonctions PURES du mix priorisé d'Audio.gd (autoload
## "Sfx") — nom de couche de tir LOCAL, sélection de la queue de réverbération
## (raycast plafond, intérieur/extérieur), routage + courbe de ducking du bus
## Feedback (hitmarker/headshot/kill jamais masqués par les tirs), écart de
## volume pas ennemi/allié, seuil du son d'atterrissage. Aucune dépendance à
## l'arbre de scène : appelées directement sur la classe, sans passer par
## l'autoload (même principe que tests/audio/test_audio_helpers.gd).
extends GdUnitTestSuite


func _cfg(category: int, automatic: bool, damage: float) -> WeaponConfig:
	var c := WeaponConfig.new()
	c.category = category
	c.automatic = automatic
	c.damage = damage
	return c


# ---------------------------------------------------------------- couches de tir LOCAL

func test_weapon_layer_name_appends_layer_to_gunshot_name() -> void:
	var c := _cfg(WeaponConfig.Category.RIFLE, true, 40.0)
	assert_str(Audio.weapon_layer_name(c, "transient")).is_equal("gunshot_rifle_transient")
	assert_str(Audio.weapon_layer_name(c, "body")).is_equal("gunshot_rifle_body")
	assert_str(Audio.weapon_layer_name(c, "mech")).is_equal("gunshot_rifle_mech")
	assert_str(Audio.weapon_layer_name(c, "sub")).is_equal("gunshot_rifle_sub")


func test_weapon_layer_name_null_config_falls_back_to_rifle() -> void:
	assert_str(Audio.weapon_layer_name(null, "body")).is_equal("gunshot_rifle_body")


func test_weapon_layer_name_distinguishes_weapon_classes() -> void:
	var shotgun := _cfg(WeaponConfig.Category.SHOTGUN, true, 17.0)
	var sniper := _cfg(WeaponConfig.Category.SNIPER, false, 150.0)
	assert_str(Audio.weapon_layer_name(shotgun, "mech")).is_equal("gunshot_shotgun_mech")
	assert_str(Audio.weapon_layer_name(sniper, "mech")).is_equal("gunshot_sniper_mech")


# ---------------------------------------------------------------- sélection de la queue (intérieur/extérieur)

func test_gunshot_tail_name_no_ceiling_hit_is_outdoor() -> void:
	assert_str(Audio.gunshot_tail_name(false, 0.0)).is_equal("tail_outdoor")


func test_gunshot_tail_name_ceiling_hit_far_beyond_max_is_outdoor() -> void:
	# Un raycast qui touche quelque chose (has_ceiling_hit=true) mais très loin
	# (hangar, auvent) doit quand même être considéré extérieur.
	assert_str(Audio.gunshot_tail_name(true, 40.0)).is_equal("tail_outdoor")


func test_gunshot_tail_name_close_ceiling_is_indoor() -> void:
	assert_str(Audio.gunshot_tail_name(true, 2.5)).is_equal("tail_indoor")


func test_gunshot_tail_name_at_max_range_is_indoor() -> void:
	assert_str(Audio.gunshot_tail_name(true, Audio.INDOOR_CEILING_MAX)).is_equal("tail_indoor")


func test_gunshot_tail_name_ceiling_just_beyond_max_range_is_outdoor() -> void:
	assert_str(Audio.gunshot_tail_name(true, Audio.INDOOR_CEILING_MAX + 0.01)).is_equal("tail_outdoor")


# ---------------------------------------------------------------- bus Feedback (hit/kill jamais masqué)

func test_is_feedback_sound_true_for_hit_and_kill_sounds() -> void:
	assert_bool(Audio.is_feedback_sound("hitmarker")).is_true()
	assert_bool(Audio.is_feedback_sound("headshot")).is_true()
	assert_bool(Audio.is_feedback_sound("kill_confirm")).is_true()


func test_is_feedback_sound_false_for_other_sounds() -> void:
	assert_bool(Audio.is_feedback_sound("gunshot_rifle")).is_false()
	assert_bool(Audio.is_feedback_sound("footstep_walk")).is_false()
	assert_bool(Audio.is_feedback_sound("damage_taken")).is_false()
	assert_bool(Audio.is_feedback_sound("")).is_false()


# ---------------------------------------------------------------- règles de ducking (sidechain manuel)

func test_duck_gain_db_full_depth_immediately_on_trigger() -> void:
	# Pas de rampe d'attaque : le hit doit couper le bus des tirs dès la
	# première frame, sinon l'instant le plus important du son Feedback reste masqué.
	assert_float(Audio.duck_gain_db(0.0)).is_equal_approx(-4.0, 0.001)


func test_duck_gain_db_holds_full_depth_before_release_window() -> void:
	assert_float(Audio.duck_gain_db(0.05)).is_equal_approx(-4.0, 0.001)
	assert_float(Audio.duck_gain_db(0.089)).is_equal_approx(-4.0, 0.001)


func test_duck_gain_db_releases_linearly_towards_zero() -> void:
	assert_float(Audio.duck_gain_db(0.105)).is_equal_approx(-2.0, 0.01)


func test_duck_gain_db_zero_at_and_after_duration() -> void:
	assert_float(Audio.duck_gain_db(0.12)).is_equal_approx(0.0, 0.001)
	assert_float(Audio.duck_gain_db(0.5)).is_equal_approx(0.0, 0.001)


func test_duck_gain_db_zero_before_trigger() -> void:
	assert_float(Audio.duck_gain_db(-1.0)).is_equal_approx(0.0, 0.001)


func test_duck_gain_db_custom_duration_and_depth() -> void:
	assert_float(Audio.duck_gain_db(0.0, 1.0, -6.0)).is_equal_approx(-6.0, 0.001)
	assert_float(Audio.duck_gain_db(1.0, 1.0, -6.0)).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------- pas ennemis +3 dB vs alliés

func test_footstep_team_volume_offset_enemy_is_boosted() -> void:
	assert_float(Audio.footstep_team_volume_offset_db(0, 1)).is_equal_approx(3.0, 0.001)


func test_footstep_team_volume_offset_ally_is_neutral() -> void:
	assert_float(Audio.footstep_team_volume_offset_db(0, 0)).is_equal_approx(0.0, 0.001)
	assert_float(Audio.footstep_team_volume_offset_db(1, 1)).is_equal_approx(0.0, 0.001)


func test_footstep_team_volume_offset_unknown_team_is_neutral() -> void:
	assert_float(Audio.footstep_team_volume_offset_db(-1, 1)).is_equal_approx(0.0, 0.001)
	assert_float(Audio.footstep_team_volume_offset_db(0, -1)).is_equal_approx(0.0, 0.001)


# ---------------------------------------------------------------- son de réception d'atterrissage

func test_should_play_landing_true_above_threshold() -> void:
	assert_bool(Audio.should_play_landing(1.5)).is_true()


func test_should_play_landing_false_below_threshold() -> void:
	assert_bool(Audio.should_play_landing(0.2)).is_false()


func test_should_play_landing_true_at_threshold() -> void:
	assert_bool(Audio.should_play_landing(Audio.LANDING_MIN_FALL_HEIGHT)).is_true()


func test_should_play_landing_false_for_no_fall() -> void:
	assert_bool(Audio.should_play_landing(0.0)).is_false()
