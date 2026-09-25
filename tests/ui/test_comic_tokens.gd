## test_comic_tokens.gd
## Spec (design.md v2 §9/§11/§13) : jetons/fabriques purs de Comic.gd — la
## police titre italique dérivée (FontVariation, pas de fichier séparé), la
## couleur ennemi dynamique (miroir de Cartoon.enemy_color(), suit
## Settings.enemy_color), et le passe-plat mouvement réduit.
extends GdUnitTestSuite


func test_font_title_italic_derives_from_barlow_condensed_extrabold() -> void:
	var fv := Comic.font_title_italic()
	assert_object(fv).is_instanceof(FontVariation)
	assert_object(fv.base_font).is_equal(Comic.FONT_TITLE_BASE)


func test_font_title_italic_applies_a_positive_shear() -> void:
	var fv := Comic.font_title_italic()
	var t: Transform2D = fv.variation_transform
	# Cisaillement (composante x de l'axe Y, "yx" — tutoriel Godot "Faux bold
	# and italic") strictement positif, fourchette usuelle 0.2-0.4 (design.md
	# §11 : « Italic »).
	assert_float(t.y.x).is_between(0.15, 0.45)
	assert_float(t.x.x).is_equal_approx(1.0, 0.001)
	assert_float(t.y.y).is_equal_approx(1.0, 0.001)


func test_font_title_italic_is_cached_across_calls() -> void:
	assert_object(Comic.font_title_italic()).is_same(Comic.font_title_italic())


func test_enemy_color_mirrors_cartoon_enemy_color() -> void:
	var before := Settings.enemy_color
	Settings.enemy_color = 0
	assert_that(Comic.enemy_color()).is_equal(Cartoon.enemy_color())
	Settings.enemy_color = 1
	assert_that(Comic.enemy_color()).is_equal(Cartoon.enemy_color())
	Settings.enemy_color = before


func test_enemy_color_magenta_and_citron_are_distinct() -> void:
	Settings.enemy_color = 0
	var magenta := Comic.enemy_color()
	Settings.enemy_color = 1
	var citron := Comic.enemy_color()
	assert_that(magenta).is_not_equal(citron)
	assert_that(magenta).is_equal(Comic.ENEMY_MAGENTA)
	assert_that(citron).is_equal(Comic.ENEMY_CITRON)
	Settings.enemy_color = 0


func test_reduced_motion_reflects_settings() -> void:
	var before := Settings.reduced_motion
	Settings.reduced_motion = true
	assert_bool(Comic.reduced_motion()).is_true()
	Settings.reduced_motion = false
	assert_bool(Comic.reduced_motion()).is_false()
	Settings.reduced_motion = before


func test_team_glyph_is_never_colour_alone() -> void:
	assert_str(Comic.team_glyph(true)).is_equal("●")
	assert_str(Comic.team_glyph(false)).is_equal("▼")


# ===========================================================================
# UX-30 — v4 « Encre, jaune, italique » (docs/UI_DIRECTION_BL3.md §4/§7,
# docs/style/tokens.json v4.0.0). Surface ADDITIVE : l'ancienne API testée
# ci-dessus n'est jamais réécrite (elle reste inchangée, voir Comic.gd
# section « v1 -> v2 » et les constantes v3 en tête de fichier).
# ===========================================================================

func test_v4_signal_and_vital_match_tokens_json_ui_colours() -> void:
	# tokens.json color.ui.signal/vital, §7.
	assert_that(Comic.signal_color()).is_equal(Color("FFCE1F"))
	assert_that(Comic.vital_color()).is_equal(Color("E8392E"))
	assert_that(Comic.SIGNAL).is_equal(Comic.signal_color())
	assert_that(Comic.VITAL).is_equal(Comic.vital_color())


func test_v4_paper_plate_ink_reuse_the_existing_v3_constants_unchanged() -> void:
	# Mêmes valeurs que color.papier.text/dim, color.charbon.panel/panel_hi,
	# color.ink (tokens.json INCHANGÉ pour ces jetons, §7) — de simples
	# fonctions minuscules pour le nom de rôle v4 (PAPER/INK majuscules sont
	# déjà pris par le pont v1 -> v2, valeurs différentes).
	assert_that(Comic.paper_color()).is_equal(Comic.TEXT)
	assert_that(Comic.paper_dim_color()).is_equal(Comic.TEXT_DIM)
	assert_that(Comic.plate_color()).is_equal(Comic.PANEL)
	assert_that(Comic.plate_hi_color()).is_equal(Comic.PANEL_HI)
	assert_that(Comic.ink_color()).is_equal(Comic.HARD_SHADOW_COLOR)


func test_v4_type_scale_matches_tokens_json_1_333_ratio() -> void:
	# tokens.json type.ratio 1,333, type.scale_px_1080, §7.
	assert_int(Comic.SIZE_21).is_equal(21)
	assert_int(Comic.SIZE_28).is_equal(28)
	assert_int(Comic.SIZE_37).is_equal(37)
	assert_int(Comic.SIZE_50).is_equal(50)
	assert_int(Comic.SIZE_66).is_equal(66)
	assert_int(Comic.SIZE_88).is_equal(88)
	assert_int(Comic.SIZE_118).is_equal(118)
	assert_int(Comic.SIZE_157).is_equal(157)


func test_v4_title_font_is_the_real_black_italic() -> void:
	# UI_DIRECTION_BL3.md §7 : titre = Barlow Condensed Black Italic (OFL,
	# ajoutée 2026-09-25) ; le repli embolden 0,6 ne sert que si le fichier manque.
	var f := Comic.title_font_v4()
	assert_object(f).is_instanceof(FontFile)
	assert_str(f.resource_path).is_equal(Comic.TITLE_BLACK_ITALIC_PATH)


func test_v4_title_font_is_cached_across_calls() -> void:
	assert_object(Comic.title_font_v4()).is_same(Comic.title_font_v4())


func test_v4_number_font_is_tabular_italic_sharing_the_title_file() -> void:
	# tokens.json type.fonts.number : ExtraBoldItalic tabulaire — même
	# fichier réel que le titre, SANS embolden (contrairement au titre).
	assert_object(Comic.number_font_v4()).is_equal(Comic.title_font())


func test_v4_button_font_is_the_existing_bold_italic() -> void:
	# tokens.json type.fonts.button : BoldItalic — déjà `button_secondary_font()`.
	assert_object(Comic.button_font_v4()).is_equal(Comic.button_secondary_font())


func test_v4_body_font_is_unchanged_semi_condensed_medium() -> void:
	assert_object(Comic.body_font_v4()).is_equal(Comic.FONT_BODY)


func test_v4_meta_font_applies_positive_letter_spacing_proportional_to_size() -> void:
	# tokens.json type.fonts.meta.letter_spacing = 0,10 — FontVariation.
	# spacing_glyph est en PIXELS (pas relatif), dérivé de `size` ici.
	var fv21 := Comic.meta_font_v4(Comic.SIZE_21) as FontVariation
	var fv88 := Comic.meta_font_v4(Comic.SIZE_88) as FontVariation
	assert_object(fv21.base_font).is_equal(Comic.FONT_LABEL)
	assert_int(fv21.spacing_glyph).is_equal(int(round(21 * 0.10)))
	assert_int(fv88.spacing_glyph).is_equal(int(round(88 * 0.10)))
	assert_int(fv88.spacing_glyph).is_greater(fv21.spacing_glyph)


func test_v4_label_factories_build_labels_with_the_expected_case() -> void:
	assert_str(Comic.title_label_v4("vif").text).is_equal("VIF")
	assert_str(Comic.number_label_v4("88").text).is_equal("88")
	assert_str(Comic.button_label_v4("verrouiller").text).is_equal("VERROUILLER")
	assert_str(Comic.meta_label_v4("mode").text).is_equal("MODE")
	assert_str(Comic.body_label_v4("Phrase en casse mixte.").text).is_equal("Phrase en casse mixte.")


func test_v4_ink_label_has_no_background_only_outline_and_hard_shadow() -> void:
	# UI_DIRECTION_BL3.md §5 règle 1 « zéro fond derrière le texte du HUD » :
	# contour d'encre 3 px + ombre dure (4,4) — jamais un StyleBox/Panel.
	var l := Comic.ink_label("25", Comic.SIZE_88, Comic.TEXT)
	assert_int(l.get_theme_constant("outline_size")).is_equal(3)
	assert_that(l.get_theme_color("font_outline_color")).is_equal(Comic.HARD_SHADOW_COLOR)
	assert_that(l.get_theme_color("font_shadow_color")).is_equal(Comic.HARD_SHADOW_COLOR)
	assert_int(l.get_theme_constant("shadow_offset_x")).is_equal(4)
	assert_int(l.get_theme_constant("shadow_offset_y")).is_equal(4)


func test_v4_plate_style_chamfers_top_right_and_bottom_left_only() -> void:
	# tokens.json shape.chamfer_px : 16 px, coins haut-droit + bas-gauche,
	# corner_detail 1 (StyleBoxFlat : detail=1 -> coin en biseau droit, pas
	# arrondi) ; 0 (carré) ailleurs — jamais un radius arrondi en v4.
	var s := Comic.plate_style()
	assert_int(s.corner_radius_top_left).is_equal(0)
	assert_int(s.corner_radius_top_right).is_equal(16)
	assert_int(s.corner_radius_bottom_right).is_equal(0)
	assert_int(s.corner_radius_bottom_left).is_equal(16)
	assert_int(s.corner_detail).is_equal(1)
	assert_that(s.bg_color).is_equal(Comic.PANEL)


func test_v4_plate_style_accepts_a_custom_chamfer_for_the_minimap() -> void:
	var s := Comic.plate_style(Comic.PANEL, Comic.CHAMFER_PX_MINIMAP)
	assert_int(s.corner_radius_top_right).is_equal(22)
	assert_int(s.corner_radius_bottom_left).is_equal(22)
