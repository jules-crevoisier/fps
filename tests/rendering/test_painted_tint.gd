extends GdUnitTestSuite

func test_neutral_base_kinds_take_the_full_tint() -> void:
	var red := Color(0.8, 0.1, 0.1)
	assert_that(Cartoon.effective_tint(&"container_paint", red)).is_equal(red)
	assert_that(Cartoon.effective_tint(&"painted_metal", red)).is_equal(red)

func test_baked_colour_kinds_keep_only_a_light_tint() -> void:
	var ochre := Color("c4935a")
	var t := Cartoon.effective_tint(&"sand_dirt", ochre)
	# Jamais plus sombre que 80 % de blanc + 20 % de la teinte, canal par canal.
	assert_float(t.r).is_greater_equal(0.8)
	assert_float(t.b).is_greater(0.8 * 1.0 + 0.2 * ochre.b - 0.001)
	assert_float(t.b).is_less(1.0)

func test_white_tint_is_neutral_for_every_kind() -> void:
	for k in [&"sand_dirt", &"wood_planks", &"rust", &"container_paint"]:
		assert_that(Cartoon.effective_tint(k, Color.WHITE)).is_equal(Color.WHITE)
