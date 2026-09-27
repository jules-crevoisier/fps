## test_weapon_database.gd
## Spec (contract-p0.md, WeaponDatabase "add"): get_by_id / id_of / default_loadout_ids.
## Depuis la tâche "revolver" (2026-09-27) : id 0 = Ravage, id 1 = Revolver
## (WeaponDatabase.PATHS, append-only).
extends GdUnitTestSuite


func test_get_by_id_returns_matching_weapon_config() -> void:
	var ravage := WeaponDatabase.get_by_id(0)
	assert_object(ravage).is_not_null()
	assert_str(ravage.weapon_name).is_equal("Ravage")


func test_get_by_id_out_of_range_returns_null() -> void:
	# Premier id libre = taille de PATHS (la liste ne fait que grandir).
	assert_object(WeaponDatabase.get_by_id(WeaponDatabase.PATHS.size())).is_null()
	assert_object(WeaponDatabase.get_by_id(100)).is_null()


func test_get_by_id_negative_one_returns_null() -> void:
	assert_object(WeaponDatabase.get_by_id(-1)).is_null()


func test_id_of_round_trips_for_every_weapon() -> void:
	var path_count := WeaponDatabase.PATHS.size()
	for id in range(path_count):
		var cfg := WeaponDatabase.get_by_id(id)
		assert_object(cfg).is_not_null()
		assert_int(WeaponDatabase.id_of(cfg)).is_equal(id)


func test_id_of_unknown_config_returns_negative_one() -> void:
	var unknown := WeaponConfig.new()
	assert_int(WeaponDatabase.id_of(unknown)).is_equal(-1)


func test_default_loadout_ids_contains_ravage_then_revolver() -> void:
	var ravage_id := WeaponDatabase.id_of(WeaponDatabase.get_by_name("Ravage"))
	var revolver_id := WeaponDatabase.id_of(WeaponDatabase.get_by_name("Revolver"))
	var ids := WeaponDatabase.default_loadout_ids()
	assert_array(ids).is_equal([ravage_id, revolver_id])


func test_revolver_is_registered_with_the_expected_stats() -> void:
	var revolver := WeaponDatabase.get_by_name("Revolver")
	assert_object(revolver).is_not_null()
	assert_int(revolver.category).is_equal(WeaponConfig.Category.PISTOL)
	assert_float(revolver.damage).is_equal_approx(55.0, 0.001)
	assert_float(revolver.damage_min).is_equal_approx(35.0, 0.001)
	assert_float(revolver.falloff_start).is_equal_approx(20.0, 0.001)
	assert_float(revolver.falloff_end).is_equal_approx(45.0, 0.001)
	assert_float(revolver.headshot_mult).is_equal_approx(2.0, 0.001)
	assert_float(revolver.fire_rate).is_equal_approx(3.0, 0.001)
	assert_bool(revolver.automatic).is_false()
	assert_float(revolver.spread_hip).is_equal_approx(1.2, 0.001)
	assert_float(revolver.spread_aim).is_equal_approx(0.2, 0.001)
	assert_int(revolver.mag_size).is_equal(6)
	assert_int(revolver.reserve_ammo).is_equal(36)
	assert_int(revolver.arena_reserve_ammo).is_equal(36)
	assert_float(revolver.reload_time).is_equal_approx(2.4, 0.001)
	assert_float(revolver.aim_fov).is_equal_approx(60.0, 0.001)
	assert_float(revolver.recoil_vertical).is_equal_approx(1.6, 0.001)
	assert_float(revolver.recoil_horizontal).is_equal_approx(0.3, 0.001)
	assert_float(revolver.recoil_recovery).is_equal_approx(8.0, 0.001)
	assert_float(revolver.fan_fire_rate).is_equal_approx(7.5, 0.001)
	assert_float(revolver.fan_spread_add_hip).is_equal_approx(4.0, 0.001)
	assert_float(revolver.fan_spread_add_aim).is_equal_approx(3.0, 0.001)
	assert_float(revolver.fan_recoil_mult).is_equal_approx(1.6, 0.001)
	# Pivot "Valorant Classic" (révisé 2026-09-27, design verrouillé
	# utilisateur après playtest) : RMB fanne, ne vise JAMAIS.
	assert_int(revolver.alt_fire_mode).is_equal(WeaponConfig.AltFireMode.FAN)
	assert_bool(revolver.aims_on_right_click()).append_failure_message(
		"le Revolver ne doit jamais viser au clic droit (alt_fire_mode = FAN)"
	).is_false()
	assert_bool(revolver.has_fan_fire()).is_true()


func test_ravage_has_fan_fire_disabled() -> void:
	# fan_fire_rate = 0.0 sur le Ravage (défaut de WeaponConfig, .tres non
	# touché par cette tâche) : le Ravage reste inchangé, jamais de mode fan.
	var ravage := WeaponDatabase.get_by_name("Ravage")
	assert_float(ravage.fan_fire_rate).is_equal_approx(0.0, 0.0001)
	assert_bool(ravage.has_fan_fire()).is_false()
	# Le Ravage garde RMB = ADS (alt_fire_mode NONE par défaut, jamais touché
	# dans ravage.tres) — comportement historique inchangé.
	assert_int(ravage.alt_fire_mode).is_equal(WeaponConfig.AltFireMode.NONE)
	assert_bool(ravage.aims_on_right_click()).is_true()
