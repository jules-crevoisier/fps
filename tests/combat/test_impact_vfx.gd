## test_impact_vfx.gd
## Spec (tâche "impacts sur les murs", 2026-09-27) : logique PURE d'ImpactVfx.gd
## (décalques de balle natifs `Decal` + FX cosmétiques poussière/étincelle par
## surface, voir sa docstring de fichier) — même principe que test_impact_fx.gd/
## test_decal_pool.gd : la logique sans Node (bascule surface, courbe de fondu,
## repère depuis une normale, rejet de collider) est testée directement ; le
## pool RÉEL (cap + recyclage FIFO), lui, est vérifié par un aller-retour
## `spawn_bullet_hole`/`spawn_impact_puff` avec `self` (le test suite, déjà
## dans l'arbre pendant l'exécution) comme parent, comme test_decal_pool.gd.
extends GdUnitTestSuite


func _make_world_collider() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	add_child(body)
	auto_free(body)
	return body


func _make_smoke_vision_collider() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.VISION
	add_child(body)
	auto_free(body)
	return body


func _make_character_collider() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	var health := Node.new()
	health.name = "Health"
	body.add_child(health)
	add_child(body)
	auto_free(body)
	return body


func _make_metal_collider() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.set_meta("surface", "metal")
	add_child(body)
	auto_free(body)
	return body


# ---------------------------------------------------------------- constantes
func test_max_pool_is_sixty_four() -> void:
	assert_int(ImpactVfx.MAX_POOL).is_equal(64)


# ---------------------------------------------------------------- basis_for_normal
# Axe Y (pas Z) : un `Decal` natif projette le long de son -Y local, jamais
# -Z (à la différence d'ImpactFx.basis_for_normal/DecalPool._basis_for_normal,
# qui orientent un QuadMesh classique -- voir la docstring de la fonction).
func test_basis_for_normal_y_axis_matches_the_normal() -> void:
	var n := Vector3(0, 1, 0)
	var b := ImpactVfx.basis_for_normal(n)
	assert_vector(b.y).is_equal_approx(n, Vector3.ONE * 0.0001)


func test_basis_for_normal_is_orthonormal() -> void:
	var b := ImpactVfx.basis_for_normal(Vector3(0.3, 0.7, -0.2).normalized())
	assert_float(b.x.length()).is_equal_approx(1.0, 0.001)
	assert_float(b.y.length()).is_equal_approx(1.0, 0.001)
	assert_float(b.z.length()).is_equal_approx(1.0, 0.001)
	assert_float(b.x.dot(b.y)).is_equal_approx(0.0, 0.001)
	assert_float(b.y.dot(b.z)).is_equal_approx(0.0, 0.001)


func test_basis_for_normal_handles_straight_up_normal_without_degenerating() -> void:
	var b := ImpactVfx.basis_for_normal(Vector3.UP)
	assert_float(b.x.length()).is_equal_approx(1.0, 0.001)
	assert_float(b.y.length()).is_equal_approx(1.0, 0.001)


func test_basis_for_normal_handles_straight_down_normal_without_degenerating() -> void:
	var b := ImpactVfx.basis_for_normal(Vector3.DOWN)
	assert_float(b.x.length()).is_equal_approx(1.0, 0.001)
	assert_float(b.y.length()).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------- rolled_basis_for_normal
# La rotation se fait dans le plan (x, z) -- Y reste l'axe fixe (`n`), voir la
# docstring de `basis_for_normal`/`rolled_basis_for_normal`.
func test_rolled_basis_for_normal_keeps_the_y_axis_unchanged() -> void:
	var n := Vector3(0.3, 0.7, -0.2).normalized()
	var b := ImpactVfx.rolled_basis_for_normal(n, deg_to_rad(57.0))
	assert_vector(b.y).is_equal_approx(n, Vector3.ONE * 0.0001)


func test_rolled_basis_for_normal_stays_orthonormal() -> void:
	var n := Vector3(0.3, 0.7, -0.2).normalized()
	var b := ImpactVfx.rolled_basis_for_normal(n, deg_to_rad(123.0))
	assert_float(b.x.length()).is_equal_approx(1.0, 0.001)
	assert_float(b.y.length()).is_equal_approx(1.0, 0.001)
	assert_float(b.z.length()).is_equal_approx(1.0, 0.001)
	assert_float(b.x.dot(b.y)).is_equal_approx(0.0, 0.001)
	assert_float(b.y.dot(b.z)).is_equal_approx(0.0, 0.001)


func test_rolled_basis_for_normal_zero_roll_matches_basis_for_normal() -> void:
	var n := Vector3.UP
	var a := ImpactVfx.basis_for_normal(n)
	var b := ImpactVfx.rolled_basis_for_normal(n, 0.0)
	assert_vector(b.x).is_equal_approx(a.x, Vector3.ONE * 0.0001)
	assert_vector(b.z).is_equal_approx(a.z, Vector3.ONE * 0.0001)


func test_rolled_basis_for_normal_actually_rotates_x_axis() -> void:
	var n := Vector3.UP
	var a := ImpactVfx.basis_for_normal(n)
	var b := ImpactVfx.rolled_basis_for_normal(n, deg_to_rad(90.0))
	# Une rotation de 90° autour de `n` (dans le plan x-z) envoie X sur (l'ancien) Z.
	assert_vector(b.x).is_equal_approx(a.z, Vector3.ONE * 0.001)


# ---------------------------------------------------------------- rejet de collider
func test_is_world_collider_false_for_null() -> void:
	assert_bool(ImpactVfx.is_world_collider(null)).is_false()


func test_is_world_collider_false_for_a_non_collision_object() -> void:
	var n := Node.new()
	add_child(n)
	auto_free(n)
	assert_bool(ImpactVfx.is_world_collider(n)).is_false()


func test_is_world_collider_true_for_a_plain_world_body() -> void:
	assert_bool(ImpactVfx.is_world_collider(_make_world_collider())).is_true()


func test_is_world_collider_false_for_a_smoke_vision_body() -> void:
	assert_bool(ImpactVfx.is_world_collider(_make_smoke_vision_collider())).is_false()


func test_is_world_collider_false_for_a_character_hit() -> void:
	assert_bool(ImpactVfx.is_world_collider(_make_character_collider())).is_false()


# ---------------------------------------------------------------- texture par surface
func test_texture_for_surface_concrete_variant_zero() -> void:
	var tex := ImpactVfx.texture_for_surface(SurfaceSound.CONCRETE, 0)
	assert_object(tex).is_not_null()
	assert_bool(tex.resource_path.contains("bullet_hole_concrete_1")).is_true()


func test_texture_for_surface_metal_variant_one() -> void:
	var tex := ImpactVfx.texture_for_surface(SurfaceSound.METAL, 1)
	assert_object(tex).is_not_null()
	assert_bool(tex.resource_path.contains("bullet_hole_metal_2")).is_true()


func test_texture_for_surface_wraps_variants_with_modulo() -> void:
	var a := ImpactVfx.texture_for_surface(SurfaceSound.CONCRETE, 0)
	var b := ImpactVfx.texture_for_surface(SurfaceSound.CONCRETE, 3)
	assert_object(a).is_equal(b)


# ---------------------------------------------------------------- taille/nombre par tirage
func test_decal_size_m_at_roll_zero_is_the_minimum() -> void:
	assert_float(ImpactVfx.decal_size_m(0.0)).is_equal_approx(ImpactVfx.DECAL_SIZE_MIN_M, 0.0001)


func test_decal_size_m_at_roll_one_is_the_maximum() -> void:
	assert_float(ImpactVfx.decal_size_m(1.0)).is_equal_approx(ImpactVfx.DECAL_SIZE_MAX_M, 0.0001)


func test_decal_size_m_clamps_outside_zero_one() -> void:
	assert_float(ImpactVfx.decal_size_m(-5.0)).is_equal_approx(ImpactVfx.DECAL_SIZE_MIN_M, 0.0001)
	assert_float(ImpactVfx.decal_size_m(5.0)).is_equal_approx(ImpactVfx.DECAL_SIZE_MAX_M, 0.0001)


func test_puff_count_for_roll_is_one_or_two() -> void:
	assert_int(ImpactVfx.puff_count_for_roll(0)).is_equal(1)
	assert_int(ImpactVfx.puff_count_for_roll(1)).is_equal(2)
	assert_int(ImpactVfx.puff_count_for_roll(2)).is_equal(1)
	assert_int(ImpactVfx.puff_count_for_roll(3)).is_equal(2)


# ---------------------------------------------------------------- budget par frame
func test_can_spawn_more_true_under_the_budget() -> void:
	assert_bool(ImpactVfx.can_spawn_more(0)).is_true()
	assert_bool(ImpactVfx.can_spawn_more(ImpactVfx.MAX_SPAWNS_PER_FRAME - 1)).is_true()


func test_can_spawn_more_false_at_the_budget() -> void:
	assert_bool(ImpactVfx.can_spawn_more(ImpactVfx.MAX_SPAWNS_PER_FRAME)).is_false()
	assert_bool(ImpactVfx.can_spawn_more(ImpactVfx.MAX_SPAWNS_PER_FRAME + 10)).is_false()


# ---------------------------------------------------------------- courbe de fondu du décalque
func test_decal_fade_alpha_is_one_before_the_fade_window() -> void:
	assert_float(ImpactVfx.decal_fade_alpha(0.0)).is_equal_approx(1.0, 0.0001)
	assert_float(ImpactVfx.decal_fade_alpha(ImpactVfx.DECAL_LIFETIME_S - ImpactVfx.DECAL_FADE_S)).is_equal_approx(1.0, 0.0001)


func test_decal_fade_alpha_is_half_at_the_middle_of_the_fade() -> void:
	var t: float = ImpactVfx.DECAL_LIFETIME_S - ImpactVfx.DECAL_FADE_S * 0.5
	assert_float(ImpactVfx.decal_fade_alpha(t)).is_equal_approx(0.5, 0.0001)


func test_decal_fade_alpha_is_zero_at_and_after_lifetime() -> void:
	assert_float(ImpactVfx.decal_fade_alpha(ImpactVfx.DECAL_LIFETIME_S)).is_equal_approx(0.0, 0.0001)
	assert_float(ImpactVfx.decal_fade_alpha(ImpactVfx.DECAL_LIFETIME_S + 5.0)).is_equal_approx(0.0, 0.0001)


# ---------------------------------------------------------------- spawn_bullet_hole (intégration réelle)
func test_spawn_bullet_hole_creates_a_visible_decal_textured_and_sized() -> void:
	var inst := ImpactVfx.spawn_bullet_hole(self, Vector3(3.0, 0.0, 0.0), Vector3.UP, SurfaceSound.CONCRETE, 0, 0.12)
	auto_free(inst)
	assert_object(inst).is_not_null()
	assert_bool(inst.visible).is_true()
	assert_object(inst.texture_albedo).is_not_null()
	# `.y` = profondeur de projection (axe -Y local d'un `Decal` natif),
	# `.x`/`.z` = l'empreinte carrée posée sur la surface -- voir la docstring
	# de `spawn_bullet_hole`.
	assert_that(inst.size).is_equal(Vector3(0.12, ImpactVfx.DECAL_DEPTH_M, 0.12))
	assert_int(inst.cull_mask).is_equal(ImpactVfx.DECAL_CULL_MASK)
	assert_float(inst.normal_fade).is_equal_approx(ImpactVfx.DECAL_NORMAL_FADE, 0.0001)


func test_spawn_bullet_hole_caps_the_pool_and_recycles_without_unbounded_growth() -> void:
	# Le pool statique est PARTAGÉ par tout le run de tests (comme
	# ImpactFx._pool/DecalPool._pool) : on ne suppose donc jamais qu'il parte
	# vide ici. En ciblant le MÊME `root` MAX_POOL+5 fois de suite, TOUTES les
	# instances existantes du pool finissent reparentées sous `root` (le
	# round-robin visite chaque case au moins une fois) -- le nombre d'enfants
	# plafonne donc à MAX_POOL quel que soit l'état de départ, ce qui prouve à
	# la fois le plafond ET le recyclage (pas de croissance sans fin).
	var root := Node3D.new()
	add_child(root)
	auto_free(root)
	for i in ImpactVfx.MAX_POOL + 5:
		ImpactVfx.spawn_bullet_hole(root, Vector3(float(i), 0.0, 0.0), Vector3.UP, SurfaceSound.CONCRETE, 0, 0.1)
	assert_int(root.get_child_count()).is_equal(ImpactVfx.MAX_POOL)
	# Un appel de plus (rafale prolongée) ne fait TOUJOURS pas grandir le pool.
	ImpactVfx.spawn_bullet_hole(root, Vector3(999.0, 0.0, 0.0), Vector3.UP, SurfaceSound.METAL, 0, 0.1)
	assert_int(root.get_child_count()).is_equal(ImpactVfx.MAX_POOL)


func test_spawn_bullet_hole_returns_null_when_parent_is_not_in_tree() -> void:
	var orphan := Node3D.new()
	var inst := ImpactVfx.spawn_bullet_hole(orphan, Vector3.ZERO, Vector3.UP, SurfaceSound.CONCRETE, 0, 0.1)
	assert_object(inst).is_null()
	orphan.free()


# ---------------------------------------------------------------- FX puff/spark (intégration réelle)
func test_spawn_impact_puff_creates_a_visible_billboard_at_the_puff_start_scale() -> void:
	var inst := ImpactVfx.spawn_impact_puff(self, Vector3(4.0, 0.0, 0.0), Vector3.UP)
	auto_free(inst)
	assert_object(inst).is_not_null()
	assert_bool(inst.visible).is_true()
	var mat := inst.material_override as StandardMaterial3D
	assert_object(mat).is_not_null()
	assert_bool(mat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED).is_true()
	assert_that((inst.mesh as QuadMesh).size).is_equal(Vector2.ONE * ImpactVfx.PUFF_SCALE_START_M)


func test_spawn_impact_spark_creates_a_visible_billboard_at_the_spark_start_scale() -> void:
	var inst := ImpactVfx.spawn_impact_spark(self, Vector3(4.5, 0.0, 0.0), Vector3.UP)
	auto_free(inst)
	assert_object(inst).is_not_null()
	assert_bool(inst.visible).is_true()
	assert_that((inst.mesh as QuadMesh).size).is_equal(Vector2.ONE * ImpactVfx.SPARK_SCALE_START_M)


func test_spawn_impact_puff_caps_the_pool_and_recycles_without_unbounded_growth() -> void:
	# Même raisonnement que le test de recyclage des décalques ci-dessus
	# (pool statique partagé, on ne suppose jamais un départ vide).
	var root := Node3D.new()
	add_child(root)
	auto_free(root)
	for i in ImpactVfx.MAX_POOL + 5:
		ImpactVfx.spawn_impact_puff(root, Vector3(float(i), 0.0, 0.0), Vector3.UP)
	assert_int(root.get_child_count()).is_equal(ImpactVfx.MAX_POOL)
	ImpactVfx.spawn_impact_spark(root, Vector3(999.0, 0.0, 0.0), Vector3.UP)
	assert_int(root.get_child_count()).is_equal(ImpactVfx.MAX_POOL)


# ---------------------------------------------------------------- spawn() -- routage plein (intégration)
func test_spawn_does_nothing_for_a_character_hit() -> void:
	var root := Node3D.new()
	add_child(root)
	auto_free(root)
	var before := root.get_child_count()
	ImpactVfx.spawn(root, Vector3(2.0, 0.0, 0.0), Vector3.UP, _make_character_collider())
	assert_int(root.get_child_count()).is_equal(before)


func test_spawn_creates_children_for_a_legitimate_world_hit() -> void:
	# Repart d'un budget par-frame propre -- `spawn()` compte les appels
	# RÉUSSIS de tout le run de tests sur la frame moteur courante (laquelle
	# ne change pas forcément d'une méthode de test à l'autre en exécution
	# synchrone) ; ce reset est réservé aux tests, voir sa docstring.
	ImpactVfx.reset_frame_budget_for_test()
	var root := Node3D.new()
	add_child(root)
	auto_free(root)
	var before := root.get_child_count()
	ImpactVfx.spawn(root, Vector3(2.0, 0.0, 0.0), Vector3.UP, _make_world_collider())
	assert_int(root.get_child_count()).is_greater(before)


## Régression (revue lead, captures rafale du 2026-09-27) : un carré
## translucide non texturé apparaissait par-dessus le trou de balle/la
## bouffée lors d'une rafale -- traqué jusqu'à `ImpactFx.spawn()` (éclat
## générique, quad PLAT SANS texture, `Color(1.0, 0.85, 0.45)`) appelé EN
## PLUS d'`ImpactVfx.spawn()` au même point pour un hit MONDE (voir Weapon.gd
## `_spawn_impact`, désormais corrigé pour ne plus appeler `ImpactFx.spawn()`
## sur un collider MONDE légitime). Le carré ne venait pas d'ici : ce test
## verrouille le CÔTÉ testable de la correction dans CE fichier -- `spawn()`
## ne crée jamais QUE ses trois pièces attendues pour un hit métal (décalque
## + étincelle + bouffée), jamais un quatrième enfant superflu qui
## réintroduirait le même genre de doublon depuis ImpactVfx lui-même.
func test_spawn_creates_exactly_three_children_for_a_metal_hit() -> void:
	ImpactVfx.reset_frame_budget_for_test()
	var root := Node3D.new()
	add_child(root)
	auto_free(root)
	var before := root.get_child_count()
	ImpactVfx.spawn(root, Vector3(2.0, 0.0, 0.0), Vector3.UP, _make_metal_collider())
	assert_int(root.get_child_count() - before).is_equal(3)
