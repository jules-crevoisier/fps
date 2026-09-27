## test_flash_math.gd
## Spec (contrat lead, durées raccourcies à la demande de l'utilisateur le
## 2026-09-27 : « la flash est un peu longue ») : durée d'éblouissement selon
## l'orientation (face 1.5s, profil 0.7s, dos 0.25s), affecte ennemis + lanceur,
## jamais les coéquipiers.
extends GdUnitTestSuite


func _cfg() -> UtilityConfig:
	return UtilityDatabase.get_by_id(UtilityDatabase.FLASH)


func test_facing_dot_is_one_when_looking_straight_at_burst() -> void:
	var dot := FlashMath.facing_dot(Vector3(0, 0, -1), Vector3(0, 0, -1))
	assert_float(dot).is_equal_approx(1.0, 0.001)


func test_facing_dot_is_minus_one_when_facing_away() -> void:
	var dot := FlashMath.facing_dot(Vector3(0, 0, 1), Vector3(0, 0, -1))
	assert_float(dot).is_equal_approx(-1.0, 0.001)


func test_blind_duration_facing_the_burst() -> void:
	assert_float(FlashMath.blind_duration(0.9, _cfg())).is_equal_approx(1.5, 0.001)


func test_blind_duration_side_profile() -> void:
	assert_float(FlashMath.blind_duration(0.0, _cfg())).is_equal_approx(0.7, 0.001)


func test_blind_duration_back_turned() -> void:
	assert_float(FlashMath.blind_duration(-0.9, _cfg())).is_equal_approx(0.25, 0.001)


func test_blind_duration_thresholds_are_strict_boundaries() -> void:
	# Exactement 0.5/-0.5 -> profil (les seuils du contrat sont > / <, pas >=/<=).
	assert_float(FlashMath.blind_duration(0.5, _cfg())).is_equal_approx(0.7, 0.001)
	assert_float(FlashMath.blind_duration(-0.5, _cfg())).is_equal_approx(0.7, 0.001)


func test_should_affect_self() -> void:
	assert_bool(FlashMath.should_affect(true, true)).is_true()


func test_should_affect_enemy() -> void:
	assert_bool(FlashMath.should_affect(false, false)).is_true()


func test_should_not_affect_teammate() -> void:
	assert_bool(FlashMath.should_affect(false, true)).is_false()


func test_duration_for_target_is_zero_beyond_radius() -> void:
	var d := FlashMath.blind_duration_for_target(25.0, 1.0, _cfg(), false, false, true)
	assert_float(d).is_equal_approx(0.0, 0.001)


func test_duration_for_target_is_zero_without_los() -> void:
	var d := FlashMath.blind_duration_for_target(5.0, 1.0, _cfg(), false, false, false)
	assert_float(d).is_equal_approx(0.0, 0.001)


func test_duration_for_target_is_zero_for_teammate() -> void:
	var d := FlashMath.blind_duration_for_target(5.0, 1.0, _cfg(), false, true, true)
	assert_float(d).is_equal_approx(0.0, 0.001)


func test_duration_for_target_full_facing_within_radius() -> void:
	var d := FlashMath.blind_duration_for_target(5.0, 0.9, _cfg(), false, false, true)
	assert_float(d).is_equal_approx(1.5, 0.001)


## Retour utilisateur 2026-09-27 : l'indicateur au-dessus de la victime dure tout le
## temps où elle est gênée = éblouissement plein + fondu de l'écran blanc.
func test_impaired_time_adds_the_screen_fade_to_the_blind_duration() -> void:
	assert_float(FlashMath.impaired_seconds(1.5)).is_equal_approx(1.5 + FlashMath.RECOVERY_S, 0.001)
	assert_float(FlashMath.impaired_seconds(0.0)).is_equal_approx(0.0, 0.001)


func test_game_hud_screen_fade_matches_the_recovery_time() -> void:
	var hud_script := preload("res://scripts/ui/GameHUD.gd")
	assert_float(hud_script._FLASH_FADE_OUT_S).is_equal_approx(FlashMath.RECOVERY_S, 0.001)
