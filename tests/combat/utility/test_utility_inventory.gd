## test_utility_inventory.gd
## Spec (contrat lead, tâche "utilitaires") : 1 charge de chaque type par vie,
## rechargées à chaque spawn (refill), perdues à la mort (clear) ; aucun jet
## sans charge disponible.
extends GdUnitTestSuite


func test_starts_with_one_charge_of_each_kind() -> void:
	var inv := UtilityInventory.new()
	assert_bool(inv.has_charge(UtilityDatabase.FRAG)).is_true()
	assert_bool(inv.has_charge(UtilityDatabase.FLASH)).is_true()
	assert_bool(inv.has_charge(UtilityDatabase.SMOKE)).is_true()


func test_consume_removes_one_charge_and_returns_true() -> void:
	var inv := UtilityInventory.new()
	assert_bool(inv.consume(UtilityDatabase.FRAG)).is_true()
	assert_bool(inv.has_charge(UtilityDatabase.FRAG)).is_false()
	# les deux autres types restent intacts (les charges sont PAR TYPE).
	assert_bool(inv.has_charge(UtilityDatabase.FLASH)).is_true()
	assert_bool(inv.has_charge(UtilityDatabase.SMOKE)).is_true()


func test_consume_without_charge_returns_false_and_stays_at_zero() -> void:
	var inv := UtilityInventory.new()
	inv.consume(UtilityDatabase.FRAG)
	assert_bool(inv.consume(UtilityDatabase.FRAG)).append_failure_message(
		"une seconde frag sans recharge doit être refusée"
	).is_false()
	assert_int(inv.charges[UtilityDatabase.FRAG]).is_equal(0)


func test_refill_restores_all_charges_to_one() -> void:
	var inv := UtilityInventory.new()
	inv.consume(UtilityDatabase.FRAG)
	inv.consume(UtilityDatabase.FLASH)
	inv.consume(UtilityDatabase.SMOKE)

	inv.refill()

	assert_bool(inv.has_charge(UtilityDatabase.FRAG)).is_true()
	assert_bool(inv.has_charge(UtilityDatabase.FLASH)).is_true()
	assert_bool(inv.has_charge(UtilityDatabase.SMOKE)).is_true()


func test_clear_empties_all_charges_on_death() -> void:
	var inv := UtilityInventory.new()

	inv.clear()

	assert_bool(inv.has_charge(UtilityDatabase.FRAG)).is_false()
	assert_bool(inv.has_charge(UtilityDatabase.FLASH)).is_false()
	assert_bool(inv.has_charge(UtilityDatabase.SMOKE)).is_false()


func test_out_of_range_kind_has_no_charge_and_cannot_be_consumed() -> void:
	var inv := UtilityInventory.new()
	assert_bool(inv.has_charge(99)).is_false()
	assert_bool(inv.consume(99)).is_false()
	assert_bool(inv.has_charge(-1)).is_false()


func test_snapshot_is_a_defensive_copy() -> void:
	var inv := UtilityInventory.new()
	var snap := inv.snapshot()
	snap[UtilityDatabase.FRAG] = 0

	assert_bool(inv.has_charge(UtilityDatabase.FRAG)).append_failure_message(
		"modifier la copie renvoyée par snapshot() ne doit jamais affecter l'état réel"
	).is_true()


func test_to_dict_and_from_dict_round_trip() -> void:
	var inv := UtilityInventory.new()
	inv.consume(UtilityDatabase.SMOKE)
	var d := inv.to_dict()

	var restored := UtilityInventory.from_dict(d)

	assert_bool(restored.has_charge(UtilityDatabase.SMOKE)).is_false()
	assert_bool(restored.has_charge(UtilityDatabase.FRAG)).is_true()
	assert_bool(restored.has_charge(UtilityDatabase.FLASH)).is_true()
