## test_comic_fx.gd
## Spec (STYLE_BIBLE.md §9.1/§9.3, tâche ART-40) : logique PURE de ComicFx.gd
## (palette fermée, "sur deux"/12 i/s, budget "≤ 64 particules par effet",
## specs des effets §9.3) — testable sans arbre de scène, même principe que
## tests/combat/test_weapon_fx.gd (ViewModel.AnimState).
extends GdUnitTestSuite

const _FX_FLAT_SHADER := preload("res://assets/shaders/fx_flat.gdshader")


# ---------------------------------------------------------------- Palette fermée
func test_vfx_palette_matches_tokens_json() -> void:
	# docs/style/tokens.json "color.vfx" — recopié à la main (voir l'en-tête
	# de ComicFx.gd), ce test empêche toute dérive silencieuse.
	assert_that(ComicFx.FLASH_CORE).is_equal(Color("fff3d6"))
	assert_that(ComicFx.FLASH_YELLOW).is_equal(Color("ffd24a"))
	assert_that(ComicFx.FLASH_ORANGE).is_equal(Color("f59a2e"))
	assert_that(ComicFx.DUST).is_equal(Color("e6d5b8"))
	assert_that(ComicFx.SPARK).is_equal(Color("ffc24a"))
	assert_that(ComicFx.STUFFING).is_equal(Color("f4ede1"))
	assert_that(ComicFx.HEADSHOT_ORANGE).is_equal(Color("f28a1e"))


func test_frame_rate_and_outline_match_tokens_json() -> void:
	assert_float(ComicFx.FRAME_RATE_SHAPES).is_equal(12.0)
	assert_float(ComicFx.OUTLINE_PX).is_equal(2.0)
	assert_int(ComicFx.MAX_PARTICLES_PER_EFFECT).is_equal(64)
	assert_int(ComicFx.MAX_PARTICLES_ON_SCREEN).is_equal(600)


# ---------------------------------------------------------------- "Sur deux" (12 i/s)
func test_stepped_time_holds_within_a_twelfth_of_a_second() -> void:
	var a := ComicFx.stepped_time(0.0)
	var b := ComicFx.stepped_time(0.04)  # < 1/12 s (~0.0833) plus loin
	assert_float(a).is_equal_approx(b, 0.0001)


func test_stepped_time_advances_past_a_twelfth_of_a_second() -> void:
	var a := ComicFx.stepped_time(0.0)
	var b := ComicFx.stepped_time(1.0 / 12.0 + 0.001)
	assert_float(b).is_greater(a)


func test_stepped_time_is_deterministic_multiple_of_the_step() -> void:
	var t := ComicFx.stepped_time(0.5)
	var step := 1.0 / ComicFx.FRAME_RATE_SHAPES
	var multiple := t / step
	assert_float(multiple - round(multiple)).is_equal_approx(0.0, 0.0001)


# ---------------------------------------------------------------- Budget particules
func test_clamp_particle_count_never_exceeds_budget() -> void:
	assert_int(ComicFx.clamp_particle_count(9999)).is_equal(ComicFx.MAX_PARTICLES_PER_EFFECT)


func test_clamp_particle_count_never_goes_below_one() -> void:
	assert_int(ComicFx.clamp_particle_count(-5)).is_equal(1)
	assert_int(ComicFx.clamp_particle_count(0)).is_equal(1)


func test_dust_puff_spec_never_exceeds_budget() -> void:
	assert_int(ComicFx.dust_puff_spec().count).is_less_equal(ComicFx.MAX_PARTICLES_PER_EFFECT)


func test_debris_shards_spec_clamps_an_excessive_request() -> void:
	var spec := ComicFx.debris_shards_spec(Color.WHITE, 999)
	assert_int(spec.count).is_equal(ComicFx.MAX_PARTICLES_PER_EFFECT)


func test_character_hit_specs_never_exceed_budget_per_effect() -> void:
	for spec in ComicFx.character_hit_specs(Color("ee6a24"), true):
		assert_int(spec.count).is_less_equal(ComicFx.MAX_PARTICLES_PER_EFFECT)


# ---------------------------------------------------------------- §9.3 "Monde, générique"
func test_dust_puff_spec_matches_style_bible_row() -> void:
	var spec := ComicFx.dust_puff_spec()
	assert_int(spec.shape).is_equal(ComicFx.Shape.DISC)
	assert_int(spec.count).is_equal(3)
	assert_float(spec.lifetime).is_equal_approx(0.25, 0.001)
	assert_that(spec.color).is_equal(ComicFx.DUST)


func test_debris_shards_spec_uses_the_streak_shape() -> void:
	var spec := ComicFx.debris_shards_spec(Color("9c6a42"))
	assert_int(spec.shape).is_equal(ComicFx.Shape.STREAK)
	assert_int(spec.count).is_between(3, 5)


# ---------------------------------------------------------------- §9.3 "Personnage" — CHK-45
func test_character_hit_body_puff_is_always_the_stuffing_color() -> void:
	# Jamais de rouge sang (CHK-45) : quel que soit l'agent touché (couleurs-clé
	# variées, dont des rouges/oranges — Choc #BE2D25, Vif #EE6A24), le premier
	# spec (le corps) reste TOUJOURS la couleur de rembourrage fermée.
	for agent_color in [Color("ee6a24"), Color("be2d25"), Color("f2b51d"), Color("5157b8"), Color("2e9c8a"), Color("2a5fc4")]:
		var specs := ComicFx.character_hit_specs(agent_color, false)
		assert_that(specs[0].color).is_equal(ComicFx.STUFFING)


func test_character_hit_confetti_uses_the_agents_key_color() -> void:
	var agent_color := Color("2a5fc4")  # Verrou
	var specs := ComicFx.character_hit_specs(agent_color, false)
	assert_that(specs[1].color).is_equal(agent_color)


func test_character_hit_without_headshot_has_no_clonk_ring_or_stars() -> void:
	var specs := ComicFx.character_hit_specs(Color("ee6a24"), false)
	assert_int(specs.size()).is_equal(2)


func test_character_hit_headshot_adds_clonk_ring_and_two_stars() -> void:
	var specs := ComicFx.character_hit_specs(Color("ee6a24"), true)
	assert_int(specs.size()).is_equal(4)
	assert_int(specs[2].shape).is_equal(ComicFx.Shape.RING)
	assert_that(specs[2].color).is_equal(ComicFx.HEADSHOT_ORANGE)
	assert_int(specs[3].shape).is_equal(ComicFx.Shape.STAR)
	assert_int(specs[3].count).is_equal(2)


# ---------------------------------------------------------------- Matériau (Resource, sans Node)
func test_shape_material_uses_fx_flat_shader_and_given_params() -> void:
	var mat := ComicFx.shape_material(ComicFx.Shape.STAR, ComicFx.SPARK, true, false)
	assert_that(mat.shader).is_equal(_FX_FLAT_SHADER)
	assert_int(mat.get_shader_parameter("shape_kind")).is_equal(ComicFx.Shape.STAR)
	assert_that(mat.get_shader_parameter("fill_color")).is_equal(ComicFx.SPARK)
	assert_bool(mat.get_shader_parameter("draw_outline")).is_true()
	assert_bool(mat.get_shader_parameter("billboard")).is_false()


# ---------------------------------------------------------------- spawn_from_spec (intégration réelle)
func test_spawn_from_spec_creates_a_one_shot_burst_within_budget() -> void:
	var gp := ComicFx.spawn_from_spec(self, Vector3(7.0, 0.0, 0.0), Vector3.UP, ComicFx.dust_puff_spec())
	auto_free(gp)
	assert_object(gp).is_not_null()
	assert_int(gp.amount).is_equal(3)
	assert_bool(gp.one_shot).is_true()
	assert_bool(gp.emitting).is_true()
	assert_object(gp.draw_pass_1).is_instanceof(QuadMesh)
	var mat := gp.material_override as ShaderMaterial
	assert_that(mat.shader).is_equal(_FX_FLAT_SHADER)
	assert_that(mat.get_shader_parameter("fill_color")).is_equal(ComicFx.DUST)


func test_spawn_from_spec_aligns_streaks_to_velocity() -> void:
	var gp := ComicFx.spawn_from_spec(self, Vector3(8.0, 0.0, 0.0), Vector3.UP, ComicFx.debris_shards_spec(Color.WHITE))
	auto_free(gp)
	assert_int(gp.transform_align).is_equal(GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY)


func test_spawn_from_spec_returns_null_without_a_parent() -> void:
	assert_object(ComicFx.spawn_from_spec(null, Vector3.ZERO, Vector3.UP, ComicFx.dust_puff_spec())).is_null()
