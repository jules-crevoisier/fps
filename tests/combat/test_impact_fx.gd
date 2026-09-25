## test_impact_fx.gd
## Spec (STYLE_BIBLE.md §9.3, tâche ART-40) : logique PURE ajoutée à
## ImpactFx.gd — le choix headshot cosmétique local (`is_headshot_height`) et
## la base orthonormée d'orientation (`basis_for_normal`, déjà présente
## depuis GF-06 mais jamais testée). Le routage réel (`spawn`,
## `_character_hit_at`, requête physique + arbre de scène) n'est pas testé
## ici, même principe que ViewModel._spawn_muzzle_flash (tests/combat/
## test_weapon_fx.gd) : seule la logique sans Node l'est.
extends GdUnitTestSuite


func test_max_pool_is_sixty_four() -> void:
	assert_int(ImpactFx.MAX_POOL).is_equal(64)


# ---------------------------------------------------------------- basis_for_normal (GF-06)
func test_basis_for_normal_z_axis_matches_the_normal() -> void:
	var n := Vector3(0, 1, 0)
	var b := ImpactFx.basis_for_normal(n)
	assert_vector(b.z).is_equal_approx(n, Vector3.ONE * 0.0001)


func test_basis_for_normal_is_orthonormal() -> void:
	var b := ImpactFx.basis_for_normal(Vector3(0.3, 0.7, -0.2).normalized())
	assert_float(b.x.length()).is_equal_approx(1.0, 0.001)
	assert_float(b.y.length()).is_equal_approx(1.0, 0.001)
	assert_float(b.z.length()).is_equal_approx(1.0, 0.001)
	assert_float(b.x.dot(b.y)).is_equal_approx(0.0, 0.001)
	assert_float(b.y.dot(b.z)).is_equal_approx(0.0, 0.001)


func test_basis_for_normal_handles_straight_up_normal_without_degenerating() -> void:
	# Cas dégénéré historique : `up.cross(n)` s'annule quand `n` est déjà UP.
	var b := ImpactFx.basis_for_normal(Vector3.UP)
	assert_float(b.x.length()).is_equal_approx(1.0, 0.001)
	assert_float(b.y.length()).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------- Headshot cosmétique local (ART-40)
func test_is_headshot_height_false_at_the_feet() -> void:
	assert_bool(ImpactFx.is_headshot_height(0.0, 0.2)).is_false()


func test_is_headshot_height_false_at_body_center() -> void:
	assert_bool(ImpactFx.is_headshot_height(0.0, 0.9)).is_false()


func test_is_headshot_height_true_at_the_head() -> void:
	assert_bool(ImpactFx.is_headshot_height(0.0, 1.7)).is_true()


func test_is_headshot_height_true_exactly_at_the_threshold() -> void:
	assert_bool(ImpactFx.is_headshot_height(0.0, ImpactFx.HEAD_HEIGHT_THRESHOLD_M)).is_true()


func test_is_headshot_height_uses_origin_relative_to_player_feet() -> void:
	# Un joueur perché (pieds à y=10) : le seuil reste RELATIF à ses pieds.
	assert_bool(ImpactFx.is_headshot_height(10.0, 10.2)).is_false()
	assert_bool(ImpactFx.is_headshot_height(10.0, 11.7)).is_true()
