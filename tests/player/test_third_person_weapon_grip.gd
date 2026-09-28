## test_third_person_weapon_grip.gd
## Spec (tâche "cadrage FP quatre armes", 2026-09-28, suite -- consigne du lead : « Fracas/Verdict ne
## se tiennent pas en main comme Ravage en 3e personne ») : `ThirdPersonWeapon.grip_transform_for`
## (fonction PURE, voir sa doc) -- PAR ARME (`_GRIP_OFFSETS_BY_ID`) EN PREMIER, `fallback` (calculé
## par l'appelant -- identité pour "WeaponSocket", `_GRIP_OFFSETS`/catégorie pour `_bone_attach`)
## sinon. Même esprit que tests/player/test_third_person_weapon_scale.gd (fonctions pures de ce
## fichier, testées en isolation).
extends GdUnitTestSuite

const FRACAS_ID := 3
const VERDICT_ID := 4


## Ravage/Revolver/Rafale/Aiguille (aucune entrée dans `_GRIP_OFFSETS_BY_ID` -- 3P jugé correct sans
## réglage PAR ARME, captures reports/checkpoints/2026-09-28_weapons_v3/*_3p.png) : retombe TOUJOURS
## sur `fallback`, identique quel que soit `fallback` (identité pour WeaponSocket, un autre transform
## quelconque pour `_bone_attach`) -- non-régression du comportement historique.
func test_falls_back_to_the_given_transform_for_weapons_without_a_per_id_entry() -> void:
	for id in [-1, 0, 1, 2, 5, 99]:
		var fallback := Transform3D(Basis.IDENTITY, Vector3.ZERO)
		assert_object(ThirdPersonWeapon.grip_transform_for(id, fallback)).append_failure_message(
			"id %d devrait retomber sur `fallback` (identité)" % id
		).is_equal(fallback)

		var other_fallback := Transform3D(Basis.from_euler(Vector3(0.1, 0.2, 0.3)), Vector3(0.5, -0.1, 0.2))
		assert_object(ThirdPersonWeapon.grip_transform_for(id, other_fallback)).append_failure_message(
			"id %d devrait retomber sur CE `fallback` (pas un fallback en dur)" % id
		).is_equal(other_fallback)


## Fracas/Verdict : une entrée PAR ARME existe -- `fallback` (quel qu'il soit) est IGNORÉ.
func test_fracas_and_verdict_ignore_the_fallback_and_use_their_own_entry() -> void:
	var fallback := Transform3D(Basis.IDENTITY, Vector3(9.0, 9.0, 9.0))  # valeur sentinelle, jamais attendue.
	var fracas := ThirdPersonWeapon.grip_transform_for(FRACAS_ID, fallback)
	assert_bool(fracas.origin.is_equal_approx(fallback.origin)).append_failure_message(
		"Fracas aurait dû ignorer `fallback`").is_false()

	var verdict := ThirdPersonWeapon.grip_transform_for(VERDICT_ID, fallback)
	assert_bool(verdict.origin.is_equal_approx(fallback.origin)).append_failure_message(
		"Verdict aurait dû ignorer `fallback`").is_false()


## Verrou de calibration -- valeurs mesurées par capture (reports/checkpoints/2026-09-28_weapons_v3/
## {fracas,verdict}_3p.png) : à mettre à jour dans le MÊME changement si ces constantes sont re-réglées.
func test_grip_table_pins_the_measured_calibration_for_fracas_and_verdict() -> void:
	var fracas := ThirdPersonWeapon.grip_transform_for(FRACAS_ID, Transform3D.IDENTITY)
	assert_vector(fracas.origin).append_failure_message("Fracas").is_equal_approx(
		Vector3(0.0, -0.05, -0.06), Vector3.ONE * 0.0001)

	var verdict := ThirdPersonWeapon.grip_transform_for(VERDICT_ID, Transform3D.IDENTITY)
	assert_vector(verdict.origin).append_failure_message("Verdict").is_equal_approx(
		Vector3(0.0, -0.05, -0.02), Vector3.ONE * 0.0001)
