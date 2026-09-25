## test_hud_format.gd
## Spec (design.md, contract-r3.md "R3-UI — acceptance" #6) : helpers PURS du
## HUD — formatage de texte, maths de mise en page, contraste des tokens.
extends GdUnitTestSuite


func test_format_ammo_never_negative() -> void:
	assert_str(HudFormat.format_ammo(25)).is_equal("25")
	assert_str(HudFormat.format_ammo(-3)).is_equal("0")


func test_format_reserve_prefixes_slash() -> void:
	assert_str(HudFormat.format_reserve(90)).is_equal("/ 90")


func test_format_timer_rounds_up_and_pads_seconds() -> void:
	assert_str(HudFormat.format_timer(102.2)).is_equal("1:43")
	assert_str(HudFormat.format_timer(5.0)).is_equal("0:05")
	assert_str(HudFormat.format_timer(-4.0)).is_equal("0:00")


func test_format_credits_groups_thousands() -> void:
	assert_str(HudFormat.format_credits(3900)).is_equal("3 900 ¤")
	assert_str(HudFormat.format_credits(400)).is_equal("400 ¤")
	assert_str(HudFormat.format_credits(1234567)).is_equal("1 234 567 ¤")


func test_format_score_line() -> void:
	assert_str(HudFormat.format_score_line(7, 5)).is_equal("ÉQ.1   7   —   5   ÉQ.2")


func test_center_zone_is_40_percent_and_centered() -> void:
	var r := HudFormat.center_zone_rect(Vector2(1920, 1080))
	assert_float(r.size.x).is_equal_approx(768.0, 0.01)
	assert_float(r.size.y).is_equal_approx(432.0, 0.01)
	assert_float(r.position.x).is_equal_approx((1920.0 - 768.0) * 0.5, 0.01)
	assert_float(r.position.y).is_equal_approx((1080.0 - 432.0) * 0.5, 0.01)


func test_overlaps_center_zone() -> void:
	var vp := Vector2(1920, 1080)
	assert_bool(HudFormat.overlaps_center_zone(Rect2(900, 500, 50, 50), vp)).is_true()
	assert_bool(HudFormat.overlaps_center_zone(Rect2(0, 0, 40, 40), vp)).is_false()


func test_contrast_ratio_text_on_panel_matches_design_doc_v2() -> void:
	# design.md v2 §11 : text (#F2EFE9) sur panel (#1A1B1E) = 15.0:1.
	var r := HudFormat.contrast_ratio(Comic.TEXT, Comic.PANEL)
	assert_float(r).is_between(14.3, 15.7)


func test_contrast_ratio_text_dim_on_panel_matches_design_doc_v2() -> void:
	# design.md v2 §11 : text_dim (#A9A6A0) sur panel = 7.1:1.
	var r := HudFormat.contrast_ratio(Comic.TEXT_DIM, Comic.PANEL)
	assert_float(r).is_between(6.6, 7.6)


func test_contrast_ratio_disabled_on_panel_matches_design_doc_v2() -> void:
	# design.md v2 §11 : disabled (#6E6C68) sur panel = 3.3:1.
	var r := HudFormat.contrast_ratio(Comic.DISABLED, Comic.PANEL)
	assert_float(r).is_between(2.9, 3.7)


func test_contrast_ratio_white_text_on_brush_matches_design_doc_v2() -> void:
	# design.md v2 §11 : texte blanc sur brush (#C8242C) = 5.6:1.
	var r := HudFormat.contrast_ratio(Comic.TEXT_ON_BRUSH, Comic.BRUSH)
	assert_float(r).is_between(5.1, 6.1)


func test_contrast_ratio_bullet_on_panel_matches_design_doc_v2() -> void:
	# design.md v2 §11 : bullet (#E23B33) = 4.0:1.
	var r := HudFormat.contrast_ratio(Comic.BULLET, Comic.PANEL)
	assert_float(r).is_between(3.5, 4.5)


func test_contrast_ratio_is_symmetric() -> void:
	var a := HudFormat.contrast_ratio(Comic.TEXT, Comic.PANEL)
	var b := HudFormat.contrast_ratio(Comic.PANEL, Comic.TEXT)
	assert_float(a).is_equal_approx(b, 0.0001)


func test_contrast_ratio_identical_colors_is_one() -> void:
	assert_float(HudFormat.contrast_ratio(Comic.PANEL, Comic.PANEL)).is_equal_approx(1.0, 0.0001)


func test_contrast_ratio_ally_on_panel_matches_design_doc_v2() -> void:
	# design.md v2 §11 : ally (#3B8BFF) = 5.2:1.
	var r := HudFormat.contrast_ratio(Comic.ALLY, Comic.PANEL)
	assert_float(r).is_between(4.7, 5.7)


func test_contrast_ratio_enemy_colors_clear_aa_on_panel() -> void:
	# design.md v2 §11/§9 : Magenta 5.5:1, Citron 14.6:1 — les deux passent
	# largement le seuil AA texte large/UI (3:1) sur `panel`.
	for c in [Comic.ENEMY_MAGENTA, Comic.ENEMY_CITRON]:
		assert_float(HudFormat.contrast_ratio(c, Comic.PANEL)).is_greater_equal(3.0)


# ===========================================================================
# GF-23 — HUD munitions : états de la réserve, invites RECHARGER/CHANGER
# D'ARME, toast de ramassage (docs/research/10_ammo_kits_input.md §2.6).
# ===========================================================================

func test_reserve_state_is_normal_above_one_magazine() -> void:
	assert_str(HudFormat.reserve_state(90, 25)).is_equal("normal")
	assert_str(HudFormat.reserve_state(26, 25)).is_equal("normal")


func test_reserve_state_is_low_at_one_magazine_or_less() -> void:
	assert_str(HudFormat.reserve_state(25, 25)).is_equal("low")
	assert_str(HudFormat.reserve_state(1, 25)).is_equal("low")


func test_reserve_state_is_empty_at_zero() -> void:
	assert_str(HudFormat.reserve_state(0, 25)).is_equal("empty")
	assert_str(HudFormat.reserve_state(-5, 25)).is_equal("empty")


func test_reserve_state_without_mag_size_is_never_low() -> void:
	# Arme pas encore annoncée (`_mag_size` à 0 dans AmmoPanel) : aucun ratio
	# calculable, seuls "empty"/"normal" restent possibles.
	assert_str(HudFormat.reserve_state(0, 0)).is_equal("empty")
	assert_str(HudFormat.reserve_state(1, 0)).is_equal("normal")


func test_format_reserve_label_shows_vide_at_zero() -> void:
	assert_str(HudFormat.format_reserve_label(0)).is_equal("VIDE")
	assert_str(HudFormat.format_reserve_label(-3)).is_equal("VIDE")


func test_format_reserve_label_matches_format_reserve_above_zero() -> void:
	assert_str(HudFormat.format_reserve_label(90)).is_equal("/ 90")


func test_should_show_reload_prompt_true_when_low_mag_reserve_and_idle() -> void:
	assert_bool(HudFormat.should_show_reload_prompt(6, 25, 90, 1.5)).is_true()
	assert_bool(HudFormat.should_show_reload_prompt(0, 25, 90, 3.0)).is_true()


func test_should_show_reload_prompt_false_while_mag_above_threshold() -> void:
	assert_bool(HudFormat.should_show_reload_prompt(10, 25, 90, 3.0)).is_false()


func test_should_show_reload_prompt_false_right_after_a_shot() -> void:
	# "jamais pendant le tir" : la dernière rafale remet le délai à 0 à
	# chaque coup, donc moins de RELOAD_PROMPT_DELAY (1,5 s) écoulées bloque
	# l'invite même si le chargeur est bas.
	assert_bool(HudFormat.should_show_reload_prompt(6, 25, 90, 0.0)).is_false()
	assert_bool(HudFormat.should_show_reload_prompt(6, 25, 90, 1.49)).is_false()


func test_should_show_reload_prompt_false_without_reserve() -> void:
	assert_bool(HudFormat.should_show_reload_prompt(6, 25, 0, 3.0)).is_false()


func test_should_show_reload_prompt_false_without_known_mag_size() -> void:
	assert_bool(HudFormat.should_show_reload_prompt(0, 0, 90, 3.0)).is_false()


func test_should_show_switch_weapon_prompt_true_at_zero_zero() -> void:
	assert_bool(HudFormat.should_show_switch_weapon_prompt(0, 0)).is_true()


func test_should_show_switch_weapon_prompt_false_with_any_ammo_left() -> void:
	assert_bool(HudFormat.should_show_switch_weapon_prompt(1, 0)).is_false()
	assert_bool(HudFormat.should_show_switch_weapon_prompt(0, 1)).is_false()


func test_format_reload_prompt_uses_real_key_label() -> void:
	assert_str(HudFormat.format_reload_prompt("R")).is_equal("[R] RECHARGER")


func test_format_switch_weapon_prompt_uses_real_key_label() -> void:
	assert_str(HudFormat.format_switch_weapon_prompt("1")).is_equal("[1] CHANGER D'ARME")


func test_next_weapon_action_cycles_to_the_following_slot() -> void:
	assert_str(HudFormat.next_weapon_action(0, 2)).is_equal("weapon_2")
	assert_str(HudFormat.next_weapon_action(1, 2)).is_equal("weapon_1")


func test_next_weapon_action_falls_back_without_known_inventory() -> void:
	assert_str(HudFormat.next_weapon_action(0, 0)).is_equal("weapon_2")


func test_format_ammo_pickup_toast() -> void:
	assert_str(HudFormat.format_ammo_pickup_toast(1)).is_equal("+1 ARME")
	assert_str(HudFormat.format_ammo_pickup_toast(3)).is_equal("+3 ARME")


func test_reserve_pickup_magazines_detects_a_full_magazine_added() -> void:
	# Chargeur INCHANGÉ (6 -> 6) entre les deux appels : seule la réserve a
	# bougé, signature d'un ramassage réel (`server_add_reserve_mags` ne
	# touche jamais le chargeur).
	assert_int(HudFormat.reserve_pickup_magazines(6, 6, 65, 90, 25)).is_equal(1)


func test_reserve_pickup_magazines_detects_several_magazines_added() -> void:
	assert_int(HudFormat.reserve_pickup_magazines(6, 6, 0, 75, 25)).is_equal(3)


func test_reserve_pickup_magazines_is_zero_without_previous_state() -> void:
	# `_mag_prev`/`_reserve_prev` à -1 : premier appel (ou juste après un
	# VRAI changement d'arme) — jamais un ramassage.
	assert_int(HudFormat.reserve_pickup_magazines(-1, 6, 90, 90, 25)).is_equal(0)
	assert_int(HudFormat.reserve_pickup_magazines(6, 6, -1, 90, 25)).is_equal(0)


func test_reserve_pickup_magazines_is_zero_when_reserve_did_not_increase() -> void:
	assert_int(HudFormat.reserve_pickup_magazines(6, 6, 90, 90, 25)).is_equal(0)
	assert_int(HudFormat.reserve_pickup_magazines(6, 6, 90, 65, 25)).is_equal(0)


func test_reserve_pickup_magazines_is_zero_without_known_mag_size() -> void:
	assert_int(HudFormat.reserve_pickup_magazines(6, 6, 0, 90, 0)).is_equal(0)


func test_reserve_pickup_magazines_is_zero_when_the_magazine_also_changed() -> void:
	# Respawn/resynchro serveur (`Weapon._server_respawn_reset`) : mag ET
	# réserve remplis ENSEMBLE — jamais un ramassage, même si la réserve a
	# bien augmenté (sinon chaque réapparition afficherait « +N ARME »).
	assert_int(HudFormat.reserve_pickup_magazines(0, 25, 0, 90, 25)).is_equal(0)


func test_reserve_pickup_magazines_rounds_to_the_nearest_magazine_when_capped() -> void:
	# Ramassage plafonné par `Inventory.reserve_for` (réserve déjà proche du
	# plafond) : moins d'un chargeur plein ajouté, arrondi au plus proche
	# plutôt qu'un « +1 » trompeur pour un delta négligeable.
	assert_int(HudFormat.reserve_pickup_magazines(6, 6, 90, 94, 25)).is_equal(0)
	assert_int(HudFormat.reserve_pickup_magazines(6, 6, 90, 100, 25)).is_equal(0)
	assert_int(HudFormat.reserve_pickup_magazines(6, 6, 78, 100, 25)).is_equal(1)
