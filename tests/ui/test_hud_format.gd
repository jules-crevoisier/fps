## test_hud_format.gd
## Spec (design.md, contract-r3.md "R3-UI — acceptance" #6) : helpers PURS du
## HUD encore en vie après la réduction au prototype minimal (2026-09-26,
## crosshair + hitmarker uniquement) — géométrie de la zone centrale et
## contraste WCAG des tokens. Les formatteurs de munitions/réserve/minuteur/
## crédits/score (AmmoPanel/RoundPanel/ScorePanel, supprimés) sont partis avec
## eux, voir HudFormat.gd.
extends GdUnitTestSuite


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
