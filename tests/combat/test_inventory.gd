## test_inventory.gd
## Spec (contract-p0.md, Inventory): server-authoritative loadout/ammo/reload
## state machine, driven purely by WeaponDatabase.get_by_id. Weapon ids used
## below (see WeaponDatabase.PATHS): 0 Pistolet (mag 12, reserve 60, reload 1.5),
## 1 Magnum (mag 6, reserve 24, arena 30), 4 Ravage (mag 25, reserve 75, arena
## 125, reload 2.5), 8 Semeuse (reserve == arena == 200).
## Each test builds its own Inventory instance; none share state.
##
## GF-21 (docs/research/10_ammo_kits_input.md §2.2/§2.3/§2.6) ajoute deux
## groupes de tests, seul fichier de test possédé par cette tâche :
##  - la règle de munitions par mode (Inventory.RULE_ROUND/RULE_ARENA/
##    RULE_INFINITE, `reserve_for`) sur `set_loadout`/`give`/`replace_current`/
##    `add_into_free` ;
##  - `Weapon.arena_buy_allowed`, fonction STATIQUE et PURE (aucune dépendance
##    à une scène ou à un pair réseau) qui porte la fenêtre d'achat de l'arène
##    — testée ici directement, comme WeaponMath/WeaponFeel/RateLimiter/
##    ShotValidator le sont dans les autres fichiers de tests/combat/ : la
##    logique réseau qui l'appelle (`Weapon._server_buy`) reste, elle,
##    intégration seule (aucun fichier de test dédié à Weapon.gd dans ce
##    dépôt), la partie décisionnelle testable sans scène en est extraite.
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


# ---- GF-21 : règle de munitions par mode (ammo_rule, §2.2/§2.3) ----
# RULE_ROUND (défaut, sans argument) = réserve des .tres (WeaponConfig.
# reserve_ammo, comportement HISTORIQUE, voir tous les tests ci-dessus qui
# n'en passent aucun). RULE_ARENA = réserve élargie (WeaponConfig.
# arena_reserve_ammo, §2.3). RULE_INFINITE = entraînement (INFINITE_RESERVE).
# Ravage (id 4) : mag 25, reserve_ammo 75 (.tres), arena_reserve_ammo 125.
# Magnum (id 1) : mag 6, reserve_ammo 24 (.tres), arena_reserve_ammo 30.
# Semeuse (id 8) : reserve_ammo == arena_reserve_ammo == 200 (§2.3 : déjà au
# max, inchangée par la règle).

func test_set_loadout_round_rule_matches_default_and_tres_reserve() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4, 1], Inventory.RULE_ROUND)
	assert_int(inv.reserve[0]).is_equal(75)
	assert_int(inv.reserve[1]).is_equal(24)


func test_set_loadout_arena_rule_uses_arena_reserve_ammo() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([4, 1], Inventory.RULE_ARENA)
	assert_int(inv.mag[0]).is_equal(25)      # le chargeur ne change jamais avec la règle
	assert_int(inv.reserve[0]).is_equal(125)  # Ravage : ×5 chargeurs (§2.3)
	assert_int(inv.reserve[1]).is_equal(30)   # Magnum : ×5 chargeurs


func test_set_loadout_arena_rule_leaves_already_maxed_weapon_unchanged() -> void:
	var inv := Inventory.new(1)
	inv.set_loadout([8], Inventory.RULE_ARENA)  # Semeuse : 200 dans les deux cas
	assert_int(inv.reserve[0]).is_equal(200)


func test_set_loadout_infinite_rule_uses_infinite_reserve_sentinel() -> void:
	var inv := Inventory.new(1)
	inv.set_loadout([4], Inventory.RULE_INFINITE)
	assert_int(inv.reserve[0]).is_equal(Inventory.INFINITE_RESERVE)


func test_reserve_for_returns_zero_for_null_config() -> void:
	assert_int(Inventory.reserve_for(null, Inventory.RULE_ARENA)).is_equal(0)


func test_give_on_free_slot_respects_ammo_rule() -> void:
	var inv := Inventory.new(2)
	inv.give(4, Inventory.RULE_ARENA)
	assert_int(inv.reserve[0]).is_equal(125)


func test_replace_current_respects_ammo_rule() -> void:
	var inv := Inventory.new(1)
	inv.set_loadout([1])  # Magnum, réserve .tres (24) au départ
	inv.replace_current(4, Inventory.RULE_ARENA)
	assert_int(inv.reserve[0]).is_equal(125)


func test_add_into_free_respects_ammo_rule() -> void:
	var inv := Inventory.new(2)
	inv.current = 1  # slot courant vide -> add_into_free l'équipe (branche déjà couverte plus haut)
	inv.add_into_free(4, Inventory.RULE_ARENA)
	assert_int(inv.reserve[0]).is_equal(125)


# ---- GF-21 : fenêtre d'achat en arène (Weapon.arena_buy_allowed, §2.6) ----
# Pure et statique (aucune scène/pair réseau requis) : rejet de l'achat arène
# passé ARENA_BUY_WINDOW (10 s) depuis le spawn — Litige/Duel/entraînement
# (toute règle != "arena") restent SANS restriction ici (leur propre
# mécanisme, phase d'achat ou absence de boutique, vit ailleurs).

func test_arena_buy_allowed_true_within_window() -> void:
	assert_bool(Weapon.arena_buy_allowed(Inventory.RULE_ARENA, 0.0)).is_true()
	assert_bool(Weapon.arena_buy_allowed(Inventory.RULE_ARENA, 9.99)).is_true()


func test_arena_buy_allowed_true_exactly_at_window_boundary() -> void:
	assert_bool(Weapon.arena_buy_allowed(Inventory.RULE_ARENA, 10.0)).is_true()


func test_arena_buy_allowed_false_past_window() -> void:
	assert_bool(Weapon.arena_buy_allowed(Inventory.RULE_ARENA, 10.01)).is_false()
	assert_bool(Weapon.arena_buy_allowed(Inventory.RULE_ARENA, 600.0)).is_false()


func test_arena_buy_allowed_unrestricted_outside_arena_rule() -> void:
	assert_bool(Weapon.arena_buy_allowed(Inventory.RULE_ROUND, 600.0)).is_true()
	assert_bool(Weapon.arena_buy_allowed(Inventory.RULE_INFINITE, 600.0)).is_true()
