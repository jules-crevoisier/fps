## test_inventory_selection.gd
## Spec (contrat lead 2026-09-27, inventaire façon CS) : InventorySelection est
## la machine PURE qui décide quel emplacement unifié (0/1 = armes, 2/3/4 =
## frag/flash/smoke) devient courant, sur pression directe (touches 1..5) ou
## molette (`next_selectable`) — voir scripts/combat/InventorySelection.gd.
extends GdUnitTestSuite


# ---- is_weapon_slot / is_grenade_slot / conversions ----

func test_is_weapon_slot_true_for_0_and_1() -> void:
	assert_bool(InventorySelection.is_weapon_slot(0)).is_true()
	assert_bool(InventorySelection.is_weapon_slot(1)).is_true()


func test_is_weapon_slot_false_for_grenade_indices() -> void:
	for i in [2, 3, 4]:
		assert_bool(InventorySelection.is_weapon_slot(i)).is_false()


func test_is_grenade_slot_true_for_2_3_4() -> void:
	for i in [2, 3, 4]:
		assert_bool(InventorySelection.is_grenade_slot(i)).is_true()


func test_is_grenade_slot_false_for_weapon_indices() -> void:
	assert_bool(InventorySelection.is_grenade_slot(0)).is_false()
	assert_bool(InventorySelection.is_grenade_slot(1)).is_false()


func test_grenade_kind_of_maps_2_3_4_to_frag_flash_smoke() -> void:
	assert_int(InventorySelection.grenade_kind_of(2)).is_equal(UtilityDatabase.FRAG)
	assert_int(InventorySelection.grenade_kind_of(3)).is_equal(UtilityDatabase.FLASH)
	assert_int(InventorySelection.grenade_kind_of(4)).is_equal(UtilityDatabase.SMOKE)


func test_slot_of_grenade_is_the_inverse_of_grenade_kind_of() -> void:
	for k in [UtilityDatabase.FRAG, UtilityDatabase.FLASH, UtilityDatabase.SMOKE]:
		assert_int(InventorySelection.grenade_kind_of(InventorySelection.slot_of_grenade(k))).is_equal(k)


# ---- is_selectable ----

func test_is_selectable_weapon_slot_depends_on_filled() -> void:
	assert_bool(InventorySelection.is_selectable(0, [true, false], [1, 1, 1])).is_true()
	assert_bool(InventorySelection.is_selectable(1, [true, false], [1, 1, 1])).is_false()


func test_is_selectable_grenade_slot_depends_on_charge() -> void:
	assert_bool(InventorySelection.is_selectable(2, [true, true], [1, 0, 0])).is_true()
	assert_bool(InventorySelection.is_selectable(3, [true, true], [1, 0, 0])).is_false()
	assert_bool(InventorySelection.is_selectable(4, [true, true], [1, 0, 0])).is_false()


# ---- can_select ----

func test_can_select_refuses_already_equipped_slot() -> void:
	assert_bool(InventorySelection.can_select(0, 0, [true, true], [1, 1, 1])).is_false()


func test_can_select_refuses_empty_weapon_slot() -> void:
	assert_bool(InventorySelection.can_select(1, 0, [true, false], [1, 1, 1])).is_false()


func test_can_select_refuses_grenade_with_zero_charges() -> void:
	assert_bool(InventorySelection.can_select(2, 0, [true, true], [0, 1, 1])).is_false()


func test_can_select_allows_a_different_filled_weapon_slot() -> void:
	assert_bool(InventorySelection.can_select(1, 0, [true, true], [1, 1, 1])).is_true()


func test_can_select_allows_a_grenade_with_charge() -> void:
	assert_bool(InventorySelection.can_select(3, 0, [true, true], [1, 1, 1])).is_true()


func test_can_select_refuses_out_of_range() -> void:
	assert_bool(InventorySelection.can_select(-1, 0, [true, true], [1, 1, 1])).is_false()
	assert_bool(InventorySelection.can_select(5, 0, [true, true], [1, 1, 1])).is_false()


# ---- next_selectable : cycle 1->5, boucle, ignore vide/épuisé ----

func test_next_selectable_moves_forward_through_all_five_when_all_filled() -> void:
	var weapon_filled := [true, true]
	var charges := [1, 1, 1]
	assert_int(InventorySelection.next_selectable(0, 1, weapon_filled, charges)).is_equal(1)
	assert_int(InventorySelection.next_selectable(1, 1, weapon_filled, charges)).is_equal(2)
	assert_int(InventorySelection.next_selectable(2, 1, weapon_filled, charges)).is_equal(3)
	assert_int(InventorySelection.next_selectable(3, 1, weapon_filled, charges)).is_equal(4)


func test_next_selectable_wraps_from_last_to_first() -> void:
	assert_int(InventorySelection.next_selectable(4, 1, [true, true], [1, 1, 1])).is_equal(0)


func test_next_selectable_wraps_backward_from_first_to_last() -> void:
	assert_int(InventorySelection.next_selectable(0, -1, [true, true], [1, 1, 1])).is_equal(4)


func test_next_selectable_skips_empty_weapon_slot() -> void:
	# slot 1 (secondaire) vide -> depuis la frag (2) en reculant, on saute
	# directement à l'arme primaire (0), jamais au slot 1 vide.
	assert_int(InventorySelection.next_selectable(2, -1, [true, false], [1, 1, 1])).is_equal(0)


func test_next_selectable_skips_grenades_with_zero_charges() -> void:
	# flash (3) et smoke (4) épuisées -> depuis la frag (2) en avançant, on
	# revient directement à l'arme primaire (0).
	assert_int(InventorySelection.next_selectable(2, 1, [true, false], [1, 0, 0])).is_equal(0)


func test_next_selectable_returns_current_when_nothing_else_selectable() -> void:
	# Seule l'arme primaire est sélectionnable (secondaire vide, 0 charge partout) :
	# aucune boucle infinie, on reste sur place.
	assert_int(InventorySelection.next_selectable(0, 1, [true, false], [0, 0, 0])).is_equal(0)


func test_next_selectable_zero_direction_is_a_no_op() -> void:
	assert_int(InventorySelection.next_selectable(2, 0, [true, true], [1, 1, 1])).is_equal(2)
