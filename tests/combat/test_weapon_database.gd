## test_weapon_database.gd
## Spec (contract-p0.md, WeaponDatabase "add"): get_by_id / id_of / default_loadout_ids.
## IDs are the index in WeaponDatabase.PATHS (append-only order):
## 0 Pistolet, 1 Magnum, 2 Rafale, 3 Marqueur, 4 Ravage, 5 Fracas, 6 Faucheur.
extends GdUnitTestSuite


func test_get_by_id_returns_matching_weapon_config() -> void:
	var pistolet := WeaponDatabase.get_by_id(0)
	assert_object(pistolet).is_not_null()
	assert_str(pistolet.weapon_name).is_equal("Pistolet")

	var ravage := WeaponDatabase.get_by_id(4)
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


func test_default_loadout_ids_contains_ravage_and_pistolet() -> void:
	var ravage_id := WeaponDatabase.id_of(WeaponDatabase.get_by_name("Ravage"))
	var pistolet_id := WeaponDatabase.id_of(WeaponDatabase.get_by_name("Pistolet"))

	var ids := WeaponDatabase.default_loadout_ids()
	assert_array(ids).contains([ravage_id, pistolet_id])
