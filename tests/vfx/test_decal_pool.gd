## test_decal_pool.gd
## Spec (STYLE_BIBLE.md §9.1 #6, tâche ART-40) : "décalques en pool de 64
## (FIFO), durée de vie 8 s, fondu de 1 s" — budget/constantes, lecture de
## l'atlas ART-04 (docs/style/tokens.json "vfx.decals"), et un aller-retour
## réel de `spawn()` (Node3D ajouté à l'arbre, comme tests/agents/
## test_ability_rays.gd `_decor_body` — `self`, le test suite, est déjà dans
## l'arbre pendant l'exécution).
extends GdUnitTestSuite


func test_pool_budget_matches_style_bible() -> void:
	assert_int(DecalPool.MAX_POOL).is_equal(64)
	assert_float(DecalPool.LIFETIME_S).is_equal(8.0)
	assert_float(DecalPool.FADE_S).is_equal(1.0)


func test_known_decal_names_includes_the_art04_impact_stars() -> void:
	var names := DecalPool.known_decal_names()
	assert_array(names).contains(["impact_star_small", "impact_star_large"])


func test_known_decal_names_includes_cracks_and_burns() -> void:
	var names := DecalPool.known_decal_names()
	assert_array(names).contains(["crack_branch", "crack_wavy", "burn_small", "burn_large"])


# ---------------------------------------------------------------- spawn() (intégration réelle)
func test_spawn_creates_a_visible_quad_textured_with_the_atlas_region() -> void:
	var inst := DecalPool.spawn(self, Vector3(5.0, 0.0, 0.0), Vector3.UP, "impact_star_small", 0.2)
	auto_free(inst)
	assert_object(inst).is_not_null()
	assert_bool(inst.visible).is_true()
	var mat := inst.material_override as StandardMaterial3D
	assert_object(mat).is_not_null()
	var atlas := mat.albedo_texture as AtlasTexture
	assert_object(atlas).is_not_null()
	assert_that(atlas.region).is_equal(Rect2(208, 344, 160, 160))
	assert_that((inst.mesh as QuadMesh).size).is_equal(Vector2(0.2, 0.2))


func test_spawn_returns_null_for_an_unknown_decal_name() -> void:
	var inst := DecalPool.spawn(self, Vector3(6.0, 0.0, 0.0), Vector3.UP, "does_not_exist", 0.2)
	assert_object(inst).is_null()
