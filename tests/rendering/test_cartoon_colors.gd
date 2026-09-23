## test_cartoon_colors.gd
## Spec (design.md v2 §9/§11) : sélection de la palette allié/ennemi —
## Cartoon.ally_color() est fixe (jeton UI `ally` #3B8BFF), Cartoon.
## enemy_color() suit Settings.enemy_color (0 Magenta, 1 Citron — remplace le
## rouge/jaune/magenta de v1, ces teintes tombant dans les bandes de teinte
## désormais réservées au monde, design.md §9 point 1).
extends GdUnitTestSuite


func test_ally_color_is_fixed_blue() -> void:
	assert_that(Cartoon.ally_color()).is_equal(Color("3b8bff"))


func test_enemy_color_defaults_to_magenta() -> void:
	var orig := Settings.enemy_color
	Settings.enemy_color = 0
	assert_that(Cartoon.enemy_color()).is_equal(Color("ff3dc8"))
	Settings.enemy_color = orig


func test_enemy_color_citron_option() -> void:
	var orig := Settings.enemy_color
	Settings.enemy_color = 1
	assert_that(Cartoon.enemy_color()).is_equal(Color("c8ff1f"))
	Settings.enemy_color = orig


func test_enemy_color_never_equals_ally_color() -> void:
	var orig := Settings.enemy_color
	for i in range(2):
		Settings.enemy_color = i
		assert_bool(Cartoon.enemy_color() == Cartoon.ally_color()).is_false()
	Settings.enemy_color = orig


func test_enemy_color_out_of_range_falls_back_to_magenta() -> void:
	var orig := Settings.enemy_color
	Settings.enemy_color = 99
	assert_that(Cartoon.enemy_color()).is_equal(Color("ff3dc8"))
	Settings.enemy_color = orig


# ------------------------------------------------------------ map_palette()

func test_map_palette_known_map_returns_its_own_shadow_tint() -> void:
	var palette: Dictionary = Cartoon.map_palette("saint_ombre")
	assert_that(palette["shadow_tint"]).is_equal(Color("3e4f7a"))


func test_map_palette_unknown_map_falls_back_to_default() -> void:
	var unknown: Dictionary = Cartoon.map_palette("does_not_exist")
	var empty: Dictionary = Cartoon.map_palette("")
	assert_that(unknown["shadow_tint"]).is_equal(empty["shadow_tint"])


func test_map_palette_shadow_tint_is_never_grey() -> void:
	# Blue-violet family (design.md §4 "Shadows: ... never grey") -- the
	# blue channel must clearly outweigh red and green for every map.
	for id in ["wasteland", "cargo_ship", "port_ferraille", "val_poussiere", "saint_ombre", "col_du_vautour", "la_fosse", "le_belvedere"]:
		var tint: Color = Cartoon.map_palette(id)["shadow_tint"]
		assert_float(tint.b).is_greater(tint.r)
