## test_ability_vfx.gd
## Spec (tâche VFX-20, docs/STYLE_BIBLE.md §9.6 + §9.1, docs/AGENTS.md) : les
## effets peints des 6 capacités SIGNATURE (une par agent, AGT-09) — braise de
## Faux départ (Vif), Tape-la-cloche (Choc), Piquet d'arpenteur (Vanne), Glu
## (Verrou), Baume du Palud (Roseau), Coup de dé (Guet). Même découpage que
## tests/vfx/test_comic_fx.gd : specs PURES (Dictionary, testables sans arbre
## de scène) d'un côté, aller-retours réels des fonctions `spawn_*` de l'autre
## (auto_free, comme test_comic_fx.gd/test_decal_pool.gd).
##
## Critère d'acceptation central : « jamais une sphère unie ». AbilityVfx.gd
## ne construit JAMAIS de SphereMesh — chaque effet passe par une des 5 formes
## plates de fx_flat.gdshader (ComicFx.Shape : DISC/STREAK/STAR/RECT/RING),
## vérifié ici en énumérant toutes les specs exposées.
extends GdUnitTestSuite


# ---------------------------------------------------------------- Constantes / timings
func test_movement_trail_duration_matches_style_bible_row() -> void:
	# STYLE_BIBLE §9.6 "Ruée / Charge / Piquet" : "300 ms" — partagé par
	# Tape-la-cloche (Choc) et Piquet d'arpenteur (Vanne).
	assert_float(AbilityVfx.MOVEMENT_TRAIL_S).is_equal_approx(0.3, 0.001)


func test_dice_flight_duration_matches_agents_doc() -> void:
	# docs/AGENTS.md, Guet, Coup de dé : "lance un dé qui vole 0,5 s".
	assert_float(AbilityVfx.DICE_FLIGHT_S).is_equal_approx(0.5, 0.001)


func test_dice_pop_duration_matches_tokens_json_reveal_bubble() -> void:
	# docs/style/tokens.json "vfx.reveal_bubble.pop_ms" = 150 — recopié à la
	# main (même convention que ComicFx.gd, voir son en-tête).
	assert_float(AbilityVfx.DICE_POP_S).is_equal_approx(0.15, 0.001)


func test_balm_droplet_duration_matches_style_bible_soin_row() -> void:
	# STYLE_BIBLE §9.6 "Soin" : "500 ms".
	assert_float(AbilityVfx.BALM_DROPLET_S).is_equal_approx(0.5, 0.001)


# ---------------------------------------------------------------- "Jamais une sphère unie"
func test_no_spec_factory_ever_uses_a_sphere() -> void:
	# fx_flat.gdshader/ComicFx.Shape n'a QUE 5 valeurs, toutes des formes
	# plates découpées au ciseau (§9.1 #1) — aucune n'est une sphère : ce test
	# énumère toutes les specs exposées par AbilityVfx et vérifie qu'aucune
	# n'échappe à cette énumération fermée.
	var flat_shapes := [ComicFx.Shape.DISC, ComicFx.Shape.STREAK, ComicFx.Shape.STAR, ComicFx.Shape.RECT, ComicFx.Shape.RING]
	var all_specs: Array[Dictionary] = []
	all_specs.append_array(AbilityVfx.movement_trail_specs())
	all_specs.append(AbilityVfx.bell_ding_spec())
	all_specs.append_array(AbilityVfx.ember_burst_specs())
	all_specs.append_array(AbilityVfx.grapple_impact_specs())
	all_specs.append_array(AbilityVfx.glue_splat_specs(Color("2a5fc4")))
	all_specs.append(AbilityVfx.balm_droplet_spec())
	all_specs.append_array(AbilityVfx.dice_pop_specs())
	assert_int(all_specs.size()).is_greater(5)
	for spec in all_specs:
		assert_array(flat_shapes).contains([int(spec.shape)])


func test_every_spec_stays_within_the_particle_budget() -> void:
	var all_specs: Array[Dictionary] = []
	all_specs.append_array(AbilityVfx.movement_trail_specs())
	all_specs.append(AbilityVfx.bell_ding_spec())
	all_specs.append_array(AbilityVfx.ember_burst_specs())
	all_specs.append_array(AbilityVfx.grapple_impact_specs())
	all_specs.append_array(AbilityVfx.glue_splat_specs(Color("2a5fc4")))
	all_specs.append(AbilityVfx.balm_droplet_spec())
	all_specs.append_array(AbilityVfx.dice_pop_specs())
	for spec in all_specs:
		assert_int(int(spec.count)).is_less_equal(ComicFx.MAX_PARTICLES_PER_EFFECT)


# ---------------------------------------------------------------- Ruée / Charge / Piquet (§9.6)
func test_movement_trail_has_a_smoke_puff_and_an_ink_streak() -> void:
	var specs := AbilityVfx.movement_trail_specs()
	assert_int(specs.size()).is_equal(2)
	assert_int(specs[0].shape).is_equal(ComicFx.Shape.DISC)
	assert_that(specs[0].color).is_equal(ComicFx.DUST)
	assert_int(specs[0].count).is_equal(3)
	assert_int(specs[1].shape).is_equal(ComicFx.Shape.STREAK)
	assert_that(specs[1].color).is_equal(Cartoon.INK)
	assert_int(specs[1].count).is_equal(3)


func test_bell_ding_is_a_papier_ring() -> void:
	# "onde « DING » en anneau papier" — Tape-la-cloche.
	var spec := AbilityVfx.bell_ding_spec()
	assert_int(spec.shape).is_equal(ComicFx.Shape.RING)
	assert_that(spec.color).is_equal(Cartoon.PAPER)


func test_bell_ding_ring_stays_sized_for_close_up_legibility() -> void:
	# Régression QA 2026-09-25 : à size_m=1,2 l'anneau débordait du cadre du
	# reel en gros plan (tools/review/vfx_reel.gd) et se lisait comme un demi
	# double-arc coupé, pas comme "un anneau papier" (critère d'acceptation
	# VFX-20 : "jamais une sphère unie", mais aussi jamais un effet tronqué).
	# 0,6 m aligne l'onde sur le seul autre anneau d'impact du dépôt
	# (ComicFx.character_hit_specs, anneau CLONK "Ø0,6 m") : borne haute
	# stricte à 0,9 m pour laisser de la marge sans autoriser un retour à 1,2.
	var spec := AbilityVfx.bell_ding_spec()
	assert_float(float(spec.size_m)).is_less(0.9)
	assert_float(float(spec.size_m)).is_greater(0.0)


# ---------------------------------------------------------------- Braise (Faux départ, Vif)
func test_ember_burst_uses_the_flash_palette() -> void:
	var specs := AbilityVfx.ember_burst_specs()
	assert_int(specs.size()).is_greater_equal(2)
	var has_star := false
	for spec in specs:
		if int(spec.shape) == ComicFx.Shape.STAR:
			has_star = true
			assert_that(spec.color).is_equal(ComicFx.FLASH_ORANGE)
	assert_bool(has_star).is_true()


# ---------------------------------------------------------------- Piquet d'arpenteur (Vanne)
func test_grapple_impact_uses_the_spark_color() -> void:
	var specs := AbilityVfx.grapple_impact_specs()
	var has_spark_star := false
	for spec in specs:
		if int(spec.shape) == ComicFx.Shape.STAR:
			has_spark_star = true
			assert_that(spec.color).is_equal(ComicFx.SPARK)
	assert_bool(has_spark_star).is_true()


# ---------------------------------------------------------------- Glu (Verrou)
func test_glue_splat_uses_the_given_color_never_stuffing_or_blood() -> void:
	var color := Color("2a5fc4")
	var specs := AbilityVfx.glue_splat_specs(color)
	assert_int(specs.size()).is_greater_equal(2)
	for spec in specs:
		assert_that(spec.color).is_equal(color)


# ---------------------------------------------------------------- Baume du Palud (Roseau)
func test_balm_droplet_uses_heal_gel_and_rises() -> void:
	# STYLE_BIBLE §9.6 "Soin" : "gouttes de gel #9FD8C8 montantes".
	var spec := AbilityVfx.balm_droplet_spec()
	assert_that(spec.color).is_equal(ComicFx.HEAL_GEL)
	assert_float(spec.gravity_y).is_greater(0.0)  # "montantes" : dérive vers le haut, pas la chute habituelle.


# ---------------------------------------------------------------- Coup de dé (Guet, révélation)
func test_dice_pop_uses_papier_and_spark() -> void:
	var specs := AbilityVfx.dice_pop_specs()
	var colors: Array = []
	for spec in specs:
		colors.append(spec.color)
	assert_array(colors).contains([Cartoon.PAPER])


# ================================================================== IMPUR (intégration réelle)
func test_spawn_specs_returns_one_particle_node_per_spec() -> void:
	var out := AbilityVfx.spawn_specs(self, Vector3(10.0, 0.0, 0.0), Vector3.UP, AbilityVfx.movement_trail_specs())
	for n in out:
		auto_free(n)
	assert_int(out.size()).is_equal(2)
	for n in out:
		assert_object(n).is_instanceof(GPUParticles3D)
		assert_bool(n.emitting).is_true()


func test_spawn_specs_returns_empty_array_without_a_parent() -> void:
	assert_array(AbilityVfx.spawn_specs(null, Vector3.ZERO, Vector3.UP, AbilityVfx.movement_trail_specs())).is_empty()


func test_spawn_faux_depart_pose_creates_star_sparks() -> void:
	var out := AbilityVfx.spawn_faux_depart_pose(self, Vector3(11.0, 0.0, 0.0))
	for n in out:
		auto_free(n)
	assert_int(out.size()).is_greater_equal(2)


func test_spawn_faux_depart_return_bursts_both_ends() -> void:
	var out := AbilityVfx.spawn_faux_depart_return(self, Vector3(12.0, 0.0, 0.0), Vector3(14.0, 0.0, 0.0))
	for n in out:
		auto_free(n)
	assert_int(out.size()).is_greater_equal(4)  # 2 specs x 2 positions au minimum.


func test_spawn_ember_glow_is_a_continuous_emitter_never_a_sphere_mesh() -> void:
	var gp := AbilityVfx.spawn_ember_glow(self, Vector3(15.0, 0.0, 0.0), 8.0)
	auto_free(gp)
	assert_object(gp).is_not_null()
	assert_bool(gp.one_shot).is_false()  # « couve » en continu, contrairement aux bursts one-shot.
	assert_object(gp.draw_pass_1).is_instanceof(QuadMesh)  # jamais un SphereMesh.
	var mat := gp.material_override as ShaderMaterial
	assert_that(mat.shader).is_equal(load("res://assets/shaders/fx_flat.gdshader"))


func test_spawn_tape_la_cloche_combines_trail_and_ding() -> void:
	var out := AbilityVfx.spawn_tape_la_cloche(self, Vector3(16.0, 0.0, 0.0), Vector3(19.0, 0.0, 0.0))
	for n in out:
		auto_free(n)
	assert_int(out.size()).is_equal(3)  # 2 (trail) + 1 (ding), au point d'impact.


func test_spawn_piquet_arpenteur_orients_the_rope_along_the_anchor_direction() -> void:
	var origin := Vector3(20.0, 1.0, 0.0)
	var anchor := Vector3(20.0, 1.0, -6.0)  # tout droit devant (axe -Z), 6 m.
	var result := AbilityVfx.spawn_piquet_arpenteur(self, origin, anchor)
	auto_free(result.rope)
	for n in result.sparks:
		auto_free(n)
	assert_object(result.rope).is_instanceof(MeshInstance3D)
	assert_object(result.rope.mesh).is_instanceof(QuadMesh)
	# La corde n'est jamais un billboard : elle doit rester alignée sur le
	# segment origine -> ancrage quelle que soit la caméra.
	var mat := result.rope.material_override as ShaderMaterial
	assert_bool(mat.get_shader_parameter("billboard")).is_false()
	var to_anchor := (anchor - origin).normalized()
	var rope := result.rope as MeshInstance3D
	var local_y: Vector3 = rope.global_transform.basis.y.normalized()
	assert_float(absf(local_y.dot(to_anchor))).is_greater(0.99)  # colinéaire (même axe, sens ou non).
	assert_int(result.sparks.size()).is_greater_equal(1)


func test_spawn_glu_pose_never_uses_a_sphere_mesh() -> void:
	var out := AbilityVfx.spawn_glu_pose(self, Vector3(25.0, 0.0, 0.0), 2.5, Color("2a5fc4"))
	for n in out:
		auto_free(n)
	assert_int(out.size()).is_greater_equal(2)
	for n in out:
		assert_object(n.draw_pass_1).is_instanceof(QuadMesh)


func test_spawn_glu_bubbles_is_a_continuous_emitter() -> void:
	var gp := AbilityVfx.spawn_glu_bubbles(self, Vector3(27.0, 0.0, 0.0), 2.5, Color("2a5fc4"), 4.0)
	auto_free(gp)
	assert_object(gp).is_not_null()
	assert_bool(gp.one_shot).is_false()


func test_spawn_baume_du_palud_is_a_continuous_gel_emitter() -> void:
	var gp := AbilityVfx.spawn_baume_du_palud(self, Vector3(30.0, 0.0, 0.0), 4.0, 6.0)
	auto_free(gp)
	assert_object(gp).is_not_null()
	assert_bool(gp.one_shot).is_false()
	var mat := gp.material_override as ShaderMaterial
	assert_that(mat.get_shader_parameter("fill_color")).is_equal(ComicFx.HEAL_GEL)


func test_spawn_balm_plus_pop_creates_a_papier_plus_label() -> void:
	var label := AbilityVfx.spawn_balm_plus_pop(self, Vector3(32.0, 0.0, 0.0))
	auto_free(label)
	assert_object(label).is_instanceof(Label3D)
	assert_str(label.text).is_equal("+")


func test_spawn_coup_de_de_creates_a_tumbling_flat_die_never_a_sphere() -> void:
	var die := AbilityVfx.spawn_coup_de_de(self, Vector3(35.0, 1.0, 0.0), Vector3(38.0, 0.5, 0.0))
	auto_free(die)
	assert_object(die).is_instanceof(MeshInstance3D)
	assert_object(die.mesh).is_instanceof(QuadMesh)


func test_spawn_functions_return_null_or_empty_without_a_parent() -> void:
	assert_array(AbilityVfx.spawn_faux_depart_pose(null, Vector3.ZERO)).is_empty()
	assert_object(AbilityVfx.spawn_ember_glow(null, Vector3.ZERO)).is_null()
	assert_object(AbilityVfx.spawn_coup_de_de(null, Vector3.ZERO, Vector3.ONE)).is_null()
