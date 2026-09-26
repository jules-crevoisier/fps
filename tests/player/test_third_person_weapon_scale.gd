## test_third_person_weapon_scale.gd
## Spec (addendum 2026-09-26) : CharacterBody remet le modèle du CORPS à
## l'échelle de TARGET_HEIGHT (souvent != 1 -- ex. Frog Cowboy ≈1.8 pour son
## maillage source) -- WeaponSocket/BoneAttachment3D, descendants de ce modèle
## mis à l'échelle, héritent CETTE échelle. L'arme est modélisée à sa taille
## RÉELLE (Blender) : sans contrepoids, elle grossit/rétrécit AVEC le
## personnage (constaté : crosse géante ≈x1.8 sur Frog Cowboy).
## `ThirdPersonWeapon.counter_scale_for` est une fonction PURE (Vector3 ->
## Vector3, aucun nœud requis) : testée ici directement. Le contrôle
## d'intégration (échelle globale réellement ≈1 une fois l'arme attachée) vit
## dans tests/player/test_frog_cowboy_character.gd
## (test_weapon_keeps_its_real_world_scale_on_a_scaled_character).
extends GdUnitTestSuite


func test_counter_scale_for_uniform_scale_is_the_reciprocal() -> void:
	var result := ThirdPersonWeapon.counter_scale_for(Vector3(1.8, 1.8, 1.8))
	assert_float(result.x).is_equal_approx(1.0 / 1.8, 0.0001)
	assert_float(result.y).is_equal_approx(1.0 / 1.8, 0.0001)
	assert_float(result.z).is_equal_approx(1.0 / 1.8, 0.0001)


## Un corps plus PETIT que TARGET_HEIGHT est mis à l'échelle À LA HAUSSE (s > 1)
## -- l'arme doit alors être contre-réduite (< 1), pas grossie davantage.
func test_counter_scale_shrinks_the_weapon_when_the_body_was_scaled_up() -> void:
	var result := ThirdPersonWeapon.counter_scale_for(Vector3(2.0, 2.0, 2.0))
	assert_float(result.x).is_equal_approx(0.5, 0.0001)


## Un corps déjà à l'échelle 1 (mesh source déjà à TARGET_HEIGHT) ne doit
## produire AUCUN contrepoids (identité) -- non-régression pour les agents
## déjà bien calibrés.
func test_counter_scale_is_identity_when_the_body_is_not_scaled() -> void:
	var result := ThirdPersonWeapon.counter_scale_for(Vector3.ONE)
	assert_bool(result.is_equal_approx(Vector3.ONE)).is_true()


func test_counter_scale_handles_non_uniform_scale_componentwise() -> void:
	var result := ThirdPersonWeapon.counter_scale_for(Vector3(2.0, 1.0, 4.0))
	assert_float(result.x).is_equal_approx(0.5, 0.0001)
	assert_float(result.y).is_equal_approx(1.0, 0.0001)
	assert_float(result.z).is_equal_approx(0.25, 0.0001)


## Garde-fou : jamais de division par zéro/valeur infinie sur une composante
## quasi nulle (repli défensif à 1.0, même esprit que
## CharacterAnimator.reload_clip_speed sur un temps de rechargement invalide).
func test_counter_scale_is_defensive_against_a_zero_component() -> void:
	var result := ThirdPersonWeapon.counter_scale_for(Vector3.ZERO)
	assert_bool(result.is_equal_approx(Vector3.ONE)).is_true()
	assert_bool(is_finite(result.x) and is_finite(result.y) and is_finite(result.z)).is_true()
