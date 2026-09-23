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
