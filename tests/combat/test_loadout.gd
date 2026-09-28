## test_loadout.gd
## Spec (contrat lead 2026-09-28, "LOADOUT SELECTION") : Loadout.gd résout les
## 5 primaires par NOM (WeaponDatabase.get_by_name), sans jamais planter tant
## que "Rafale"/"Fracas"/"Verdict"/"Aiguille" n'ont pas encore leur .tres (les
## 4 sont arrivées entre-temps, en parallèle, voir WeaponDatabase.PATHS) — ce
## test reste volontairement robuste aux DEUX états (`available_primary_ids`
## est interrogé dynamiquement plutôt que comparé à une liste figée) pour ne
## jamais dépendre de l'ordre d'arrivée des deux tâches en parallèle.
extends GdUnitTestSuite

const _Loadout = preload("res://scripts/combat/Loadout.gd")


func _ravage_id() -> int:
	return WeaponDatabase.id_of(WeaponDatabase.get_by_name("Ravage"))


func _revolver_id() -> int:
	return WeaponDatabase.id_of(WeaponDatabase.get_by_name("Revolver"))


func test_primary_names_order_is_locked() -> void:
	assert_array(_Loadout.PRIMARY_NAMES).is_equal(["Ravage", "Rafale", "Fracas", "Verdict", "Aiguille"])


func test_secondary_is_always_revolver() -> void:
	assert_str(_Loadout.SECONDARY_NAME).is_equal("Revolver")
	assert_int(_Loadout.secondary_id()).is_equal(_revolver_id())


func test_available_primary_ids_only_contains_loaded_weapons() -> void:
	# Le Ravage existe dans TOUTE version du catalogue (jamais retiré) ; le
	# Revolver n'est JAMAIS une primaire, que ses 4 collègues aient déjà leur
	# .tres ou pas encore.
	var ids := _Loadout.available_primary_ids()
	assert_array(ids).contains([_ravage_id()])
	assert_bool(ids.has(_revolver_id())).append_failure_message(
		"le Revolver est la SECONDE arme fixe, jamais une primaire sélectionnable"
	).is_false()
	# Aucun id hors des 5 noms verrouillés ne doit jamais s'y glisser.
	for id in ids:
		var wname := WeaponDatabase.get_by_id(id).weapon_name
		assert_bool(_Loadout.PRIMARY_NAMES.has(wname)).append_failure_message(
			"un id résolu par available_primary_ids() doit correspondre à l'un des PRIMARY_NAMES (obtenu %s)" % wname
		).is_true()


func test_default_primary_id_is_ravage() -> void:
	assert_int(_Loadout.default_primary_id()).is_equal(_ravage_id())


func test_is_valid_primary_id_true_for_ravage_false_for_unknown() -> void:
	assert_bool(_Loadout.is_valid_primary_id(_ravage_id())).is_true()
	assert_bool(_Loadout.is_valid_primary_id(_revolver_id())).append_failure_message(
		"le Revolver n'est jamais une primaire valide"
	).is_false()
	assert_bool(_Loadout.is_valid_primary_id(9999)).is_false()
	assert_bool(_Loadout.is_valid_primary_id(-1)).is_false()


func test_loadout_for_ravage_returns_ravage_then_revolver() -> void:
	var ids := _Loadout.loadout_for(_ravage_id())
	assert_array(ids).is_equal([_ravage_id(), _revolver_id()])


func test_loadout_for_invalid_primary_falls_back_to_ravage() -> void:
	var ids := _Loadout.loadout_for(-1)
	assert_array(ids).is_equal([_ravage_id(), _revolver_id()])
	var ids2 := _Loadout.loadout_for(9999)
	assert_array(ids2).is_equal([_ravage_id(), _revolver_id()])
	# Le Revolver n'est jamais une primaire valide, même transmis par erreur.
	var ids3 := _Loadout.loadout_for(_revolver_id())
	assert_array(ids3).is_equal([_ravage_id(), _revolver_id()])


func test_random_primary_only_picks_among_loaded_ids() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var available := _Loadout.available_primary_ids()
	for i in 20:
		var pid := _Loadout.random_primary(rng)
		assert_bool(available.has(pid)).append_failure_message(
			"random_primary a renvoyé un id (%d) hors des primaires chargées %s" % [pid, available]
		).is_true()


func test_primary_id_for_name_resolves_known_name() -> void:
	assert_int(_Loadout.primary_id_for_name("Ravage")).is_equal(_ravage_id())


func test_primary_id_for_name_unknown_falls_back_to_ravage() -> void:
	# "Nom Inconnu" ne résoudra JAMAIS (aucune arme de ce nom, dans aucune
	# version du catalogue) — repli permanent, contrairement aux 4 nouveaux
	# noms (Rafale/Fracas/Verdict/Aiguille) qui résolvent correctement une
	# fois leur .tres livré (voir `test_primary_id_for_name_resolves_known_name`).
	assert_int(_Loadout.primary_id_for_name("Nom Inconnu")).is_equal(_ravage_id())
	assert_int(_Loadout.primary_id_for_name("Revolver")).append_failure_message(
		"le Revolver n'est jamais une primaire, même demandé par son vrai nom"
	).is_equal(_ravage_id())


func test_name_for_primary_id_round_trips() -> void:
	assert_str(_Loadout.name_for_primary_id(_ravage_id())).is_equal("Ravage")
	assert_str(_Loadout.name_for_primary_id(-1)).is_equal("Ravage")


func test_role_for_locked_french_labels() -> void:
	assert_str(_Loadout.role_for("Ravage")).is_equal("Fusil d'assaut")
	assert_str(_Loadout.role_for("Rafale")).is_equal("Mitraillette")
	assert_str(_Loadout.role_for("Fracas")).is_equal("Fusil à pompe")
	assert_str(_Loadout.role_for("Verdict")).is_equal("Carabine à levier")
	assert_str(_Loadout.role_for("Aiguille")).is_equal("Fusil de précision")
	assert_str(_Loadout.role_for("Nom Inconnu")).is_equal("")
