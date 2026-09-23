## test_inventory.gd
## Spec (contract-p0.md, Inventory): server-authoritative loadout/ammo/reload
## state machine, driven purely by WeaponDatabase.get_by_id. Weapon ids used
## below (see WeaponDatabase.PATHS): 0 Pistolet (mag 12, reserve 60, reload 1.5),
## 1 Magnum (mag 6, reserve 24), 4 Ravage (mag 25, reserve 75, reload 2.5).
## Each test builds its own Inventory instance; none share state.
extends GdUnitTestSuite


func _with_pistolet() -> Inventory:
	var inv := Inventory.new(2)
	inv.set_loadout([0])
	return inv


func test_init_default_has_two_empty_slots_and_current_zero() -> void:
	var inv := Inventory.new()
	assert_int(inv.slots.size()).is_equal(2)
	assert_int(inv.slots[0]).is_equal(Inventory.EMPTY)
	assert_int(inv.slots[1]).is_equal(Inventory.EMPTY)
	assert_int(inv.current).is_equal(0)
	assert_bool(inv.reloading).is_false()


func test_init_with_custom_slot_count() -> void:
	var inv := Inventory.new(3)
	assert_int(inv.slots.size()).is_equal(3)
	for id in inv.slots:
		assert_int(id).is_equal(Inventory.EMPTY)


func test_set_loadout_fills_slots_in_order_ignoring_extra_ids() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4, 0, 1])
	assert_int(inv.slots[0]).is_equal(4)
	assert_int(inv.slots[1]).is_equal(0)
	assert_int(inv.mag[0]).is_equal(25)
	assert_int(inv.mag[1]).is_equal(12)
	assert_int(inv.reserve[0]).is_equal(75)
	assert_int(inv.reserve[1]).is_equal(60)
	assert_int(inv.current).is_equal(0)
	assert_bool(inv.reloading).is_false()


func test_set_loadout_with_fewer_ids_than_slots_leaves_rest_empty() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4])
	assert_int(inv.slots[0]).is_equal(4)
	assert_int(inv.slots[1]).is_equal(Inventory.EMPTY)
	assert_int(inv.current).is_equal(0)


func test_set_loadout_with_no_ids_keeps_current_zero() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([])
	assert_int(inv.slots[0]).is_equal(Inventory.EMPTY)
	assert_int(inv.slots[1]).is_equal(Inventory.EMPTY)
	assert_int(inv.current).is_equal(0)


func test_set_loadout_resets_reloading_state() -> void:
	var inv := _with_pistolet()
	inv.consume_round()
	inv.start_reload()
	assert_bool(inv.reloading).is_true()
	inv.set_loadout([4, 0])
	assert_bool(inv.reloading).is_false()


func test_current_id_and_has_weapon() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4, 0])
	assert_int(inv.current_id()).is_equal(4)
	inv.equip(1)
	assert_int(inv.current_id()).is_equal(0)
	assert_bool(inv.has_weapon(4)).is_true()
	assert_bool(inv.has_weapon(0)).is_true()
	assert_bool(inv.has_weapon(1)).is_false()


func test_free_slot_returns_index_then_negative_one_when_full() -> void:
	var inv := Inventory.new(2)
	assert_int(inv.free_slot()).is_equal(0)
	inv.add_into_free(4)
	assert_int(inv.free_slot()).is_equal(1)
	inv.add_into_free(0)
	assert_int(inv.free_slot()).is_equal(-1)


func test_add_into_free_returns_slot_index_and_fills_full_ammo() -> void:
	var inv := Inventory.new(3)
	inv.current = 2  # point current at an empty slot to exercise the branch below
	var slot := inv.add_into_free(4)
	assert_int(slot).is_equal(0)
	assert_int(inv.mag[0]).is_equal(25)
	assert_int(inv.reserve[0]).is_equal(75)


func test_add_into_free_sets_current_only_when_current_slot_was_empty() -> void:
	var inv := Inventory.new(3)
	inv.current = 2  # slots[2] is EMPTY -> current should move to the filled slot
	inv.add_into_free(4)
	assert_int(inv.current).is_equal(0)

	# slots[0] is now non-empty -> a further add must NOT move current away from it
	var slot := inv.add_into_free(0)
	assert_int(slot).is_equal(1)
	assert_int(inv.current).is_equal(0)


func test_add_into_free_returns_negative_one_when_full() -> void:
	var inv := Inventory.new(2)
	inv.add_into_free(4)
	inv.add_into_free(0)
	var slot := inv.add_into_free(1)
	assert_int(slot).is_equal(-1)
	assert_int(inv.slots[0]).is_equal(4)
	assert_int(inv.slots[1]).is_equal(0)


func test_replace_current_returns_displaced_id_resets_ammo_and_cancels_reload() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4, 0])
	inv.consume_round()
	inv.start_reload()
	assert_bool(inv.reloading).is_true()

	var displaced := inv.replace_current(1)
	assert_int(displaced).is_equal(4)
	assert_int(inv.slots[0]).is_equal(1)
	assert_int(inv.mag[0]).is_equal(6)
	assert_int(inv.reserve[0]).is_equal(24)
	assert_bool(inv.reloading).is_false()


func test_replace_current_on_empty_current_returns_empty_constant() -> void:
	var inv := Inventory.new(2)
	var displaced := inv.replace_current(4)
	assert_int(displaced).is_equal(Inventory.EMPTY)
	assert_int(inv.slots[0]).is_equal(4)
	assert_int(inv.mag[0]).is_equal(25)


func test_give_on_free_slot_equips_and_returns_empty_displaced() -> void:
	var inv := Inventory.new(2)
	var displaced := inv.give(4)
	assert_int(displaced).is_equal(Inventory.EMPTY)
	assert_int(inv.slots[0]).is_equal(4)
	assert_int(inv.current).is_equal(0)

	displaced = inv.give(0)
	assert_int(displaced).is_equal(Inventory.EMPTY)
	assert_int(inv.slots[1]).is_equal(0)
	assert_int(inv.current).is_equal(1)


func test_give_on_full_inventory_replaces_current_and_returns_displaced_id() -> void:
	var inv := Inventory.new(2)
	inv.give(4)
	inv.give(0)  # both slots full now, current points at slot 1 (id 0)

	var displaced := inv.give(1)
	assert_int(displaced).is_equal(0)
	assert_int(inv.slots[1]).is_equal(1)
	assert_int(inv.current).is_equal(1)


func test_remove_current_returns_removed_id_moves_current_and_cancels_reload() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4, 0])
	inv.consume_round()
	inv.start_reload()

	var removed := inv.remove_current()
	assert_int(removed).is_equal(4)
	assert_int(inv.slots[0]).is_equal(Inventory.EMPTY)
	assert_int(inv.mag[0]).is_equal(0)
	assert_int(inv.reserve[0]).is_equal(0)
	assert_int(inv.current).is_equal(1)
	assert_bool(inv.reloading).is_false()


func test_remove_current_when_all_slots_become_empty_leaves_current_unchanged() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4])
	inv.remove_current()
	assert_int(inv.current).is_equal(0)


func test_remove_current_when_current_already_empty_returns_empty_constant() -> void:
	var inv := Inventory.new(2)
	var removed := inv.remove_current()
	assert_int(removed).is_equal(Inventory.EMPTY)
	assert_int(inv.current).is_equal(0)


func test_equip_out_of_range_returns_false() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4, 0])
	assert_bool(inv.equip(-1)).is_false()
	assert_bool(inv.equip(2)).is_false()


func test_equip_same_slot_returns_false() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4, 0])
	assert_bool(inv.equip(0)).is_false()


func test_equip_empty_slot_returns_false() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4])
	assert_bool(inv.equip(1)).is_false()


func test_equip_while_reloading_returns_false() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4, 0])
	inv.consume_round()
	inv.start_reload()
	assert_bool(inv.equip(1)).is_false()


func test_equip_valid_slot_switches_current() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4, 0])
	assert_bool(inv.equip(1)).is_true()
	assert_int(inv.current).is_equal(1)


func test_can_fire_true_when_loaded() -> void:
	var inv := _with_pistolet()
	assert_bool(inv.can_fire()).is_true()


func test_can_fire_false_when_current_empty() -> void:
	var inv := Inventory.new(2)
	assert_bool(inv.can_fire()).is_false()


func test_can_fire_false_when_reloading() -> void:
	var inv := _with_pistolet()
	inv.consume_round()
	inv.start_reload()
	assert_bool(inv.can_fire()).is_false()


func test_can_fire_false_when_mag_empty() -> void:
	var inv := _with_pistolet()
	for i in range(12):
		inv.consume_round()
	assert_int(inv.mag[0]).is_equal(0)
	assert_bool(inv.can_fire()).is_false()


func test_consume_round_decrements_mag_and_returns_true() -> void:
	var inv := _with_pistolet()
	assert_bool(inv.consume_round()).is_true()
	assert_int(inv.mag[0]).is_equal(11)


func test_consume_round_returns_false_when_cannot_fire() -> void:
	var inv := Inventory.new(2)
	assert_bool(inv.consume_round()).is_false()


func test_start_reload_refused_when_already_reloading() -> void:
	var inv := _with_pistolet()
	inv.consume_round()
	assert_bool(inv.start_reload()).is_true()
	assert_bool(inv.start_reload()).is_false()


func test_start_reload_refused_when_current_empty() -> void:
	var inv := Inventory.new(2)
	assert_bool(inv.start_reload()).is_false()


func test_start_reload_refused_when_mag_full() -> void:
	var inv := _with_pistolet()
	assert_bool(inv.start_reload()).is_false()


func test_start_reload_refused_when_reserve_zero() -> void:
	var inv := _with_pistolet()
	inv.consume_round()
	inv.reserve[0] = 0
	assert_bool(inv.start_reload()).is_false()


func test_start_reload_succeeds_and_sets_reload_left() -> void:
	var inv := _with_pistolet()
	inv.consume_round()
	assert_bool(inv.start_reload()).is_true()
	assert_bool(inv.reloading).is_true()
	assert_float(inv.reload_left).is_equal_approx(1.5, 0.001)


func test_tick_progresses_reload_without_completing() -> void:
	var inv := _with_pistolet()
	inv.consume_round()
	inv.start_reload()
	assert_bool(inv.tick(1.0)).is_false()
	assert_float(inv.reload_left).is_equal_approx(0.5, 0.001)
	assert_bool(inv.reloading).is_true()
	assert_int(inv.mag[0]).is_equal(11)


func test_tick_completes_reload_with_full_reserve() -> void:
	var inv := _with_pistolet()
	for i in range(10):
		inv.consume_round()
	assert_int(inv.mag[0]).is_equal(2)
	inv.start_reload()
	assert_bool(inv.tick(1.5)).is_true()
	assert_int(inv.mag[0]).is_equal(12)
	assert_int(inv.reserve[0]).is_equal(50)
	assert_bool(inv.reloading).is_false()


func test_tick_completes_reload_with_partial_reserve() -> void:
	var inv := _with_pistolet()
	for i in range(10):
		inv.consume_round()
	assert_int(inv.mag[0]).is_equal(2)
	inv.reserve[0] = 5  # less than the 10 rounds needed
	inv.start_reload()
	assert_bool(inv.tick(1.5)).is_true()
	assert_int(inv.mag[0]).is_equal(7)
	assert_int(inv.reserve[0]).is_equal(0)
	assert_bool(inv.reloading).is_false()


func test_tick_returns_false_when_not_reloading() -> void:
	var inv := _with_pistolet()
	assert_bool(inv.tick(1.0)).is_false()
	assert_int(inv.mag[0]).is_equal(12)


func test_to_dict_from_dict_round_trip() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4, 0])
	for i in range(5):
		inv.consume_round()
	inv.start_reload()

	var d := inv.to_dict()
	var restored := Inventory.from_dict(d)

	assert_array(restored.slots).is_equal(inv.slots)
	assert_array(restored.mag).is_equal(inv.mag)
	assert_array(restored.reserve).is_equal(inv.reserve)
	assert_int(restored.current).is_equal(inv.current)
	assert_bool(restored.reloading).is_equal(inv.reloading)
	assert_float(restored.reload_left).is_equal_approx(inv.reload_left, 0.001)


# ---- finish_reload_if_within (tolérance de latence côté serveur) ----

func test_finish_reload_if_within_completes_when_remaining_is_small() -> void:
	var inv := _with_pistolet()
	inv.consume_round()
	inv.start_reload()
	inv.tick(1.4)  # reload 1.5 s : il reste 0.1 s
	assert_bool(inv.finish_reload_if_within(0.15)).is_true()
	assert_bool(inv.reloading).is_false()
	assert_int(inv.mag[0]).is_equal(12)
	assert_int(inv.reserve[0]).is_equal(59)


func test_finish_reload_if_within_refuses_when_remaining_is_large() -> void:
	var inv := _with_pistolet()
	inv.consume_round()
	inv.start_reload()
	inv.tick(0.5)  # il reste 1.0 s
	assert_bool(inv.finish_reload_if_within(0.15)).is_false()
	assert_bool(inv.reloading).is_true()
	assert_int(inv.mag[0]).is_equal(11)


func test_finish_reload_if_within_refuses_when_not_reloading() -> void:
	var inv := _with_pistolet()
	assert_bool(inv.finish_reload_if_within(0.15)).is_false()
	assert_int(inv.mag[0]).is_equal(12)
