## test_vitals_hud.gd
## Spec (contrat lead 2026-09-27, HUD en jeu, point 1 "VitalsHUD") : portrait
## carré jaune non incliné, nombre de PV (display T_3XL + "/100" T_M), 4
## segments inclinés de 25 PV chacun (VERT plein, remplissage partiel, PAPIER
## vide), nom du personnage sous la barre, PV bas (<= 30) : nombre + segments
## passent au ROUGE avec une pulsation douce.
extends GdUnitTestSuite

const VitalsHUD := preload("res://scripts/ui/hud/VitalsHUD.gd")


func _hud() -> VitalsHUD:
	var hud: VitalsHUD = auto_free(VitalsHUD.new())
	add_child(hud)
	return hud


# ---- segments_for (pure) ----

func test_segments_for_full_health_is_all_full() -> void:
	var segs := VitalsHUD.segments_for(100.0, 100.0)
	assert_int(segs.size()).is_equal(4)
	for f in segs:
		assert_float(f).is_equal_approx(1.0, 0.001)


func test_segments_for_zero_health_is_all_empty() -> void:
	var segs := VitalsHUD.segments_for(0.0, 100.0)
	for f in segs:
		assert_float(f).is_equal_approx(0.0, 0.001)


func test_segments_for_72_over_100_matches_mockup_pattern() -> void:
	# reports/ui/mockups/hud.html : 72/100 -> plein, plein, partiel, vide.
	var segs := VitalsHUD.segments_for(72.0, 100.0)
	assert_float(segs[0]).is_equal_approx(1.0, 0.001)
	assert_float(segs[1]).is_equal_approx(1.0, 0.001)
	assert_float(segs[2]).is_equal_approx(0.88, 0.001)
	assert_float(segs[3]).is_equal_approx(0.0, 0.001)


func test_segments_for_never_exceeds_bounds() -> void:
	var segs := VitalsHUD.segments_for(130.0, 100.0)
	for f in segs:
		assert_float(f).is_less_equal(1.0)
	var segs2 := VitalsHUD.segments_for(-10.0, 100.0)
	for f in segs2:
		assert_float(f).is_greater_equal(0.0)


# ---- is_low_hp (pure) ----

func test_is_low_hp_threshold() -> void:
	assert_bool(VitalsHUD.is_low_hp(30.0)).is_true()
	assert_bool(VitalsHUD.is_low_hp(31.0)).is_false()
	assert_bool(VitalsHUD.is_low_hp(0.0)).is_true()


# ---- nœuds ----

func test_portrait_is_square_and_not_skewed() -> void:
	var hud := _hud()
	assert_object(hud._portrait).is_not_null()
	assert_float(hud._portrait.custom_minimum_size.x).is_equal_approx(hud._portrait.custom_minimum_size.y, 0.01)


func test_update_hp_sets_the_number_and_max() -> void:
	var hud := _hud()
	hud.update_hp(72.0, 100.0)
	assert_str(hud._hp_label.text).is_equal("72")
	assert_str(hud._max_label.text).is_equal("/100")


func test_update_hp_turns_red_when_low() -> void:
	var hud := _hud()
	hud.update_hp(20.0, 100.0)
	assert_bool(hud._hp_label.label_settings.font_color.is_equal_approx(UiTokens.RED)).is_true()


func test_update_hp_stays_paper_when_not_low() -> void:
	var hud := _hud()
	hud.update_hp(80.0, 100.0)
	assert_bool(hud._hp_label.label_settings.font_color.is_equal_approx(UiTokens.PAPER)).is_true()


func test_set_character_name_updates_label() -> void:
	var hud := _hud()
	hud.set_character_name("Verrou")
	assert_str(hud._name_label.text).is_equal("VERROU")


func test_builds_four_segments() -> void:
	var hud := _hud()
	assert_int(hud._segments.size()).is_equal(4)
