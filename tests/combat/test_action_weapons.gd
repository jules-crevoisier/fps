## test_action_weapons.gd
## Spec (tâche "quatre armes", 2026-09-28) : mécaniques génériques ajoutées
## pour Rafale/Fracas/Verdict/Aiguille SANS toucher le comportement existant
## (Ravage/Revolver) — `WeaponConfig.cycle_time`/`reload_per_round`/
## `reload_start_time`/`reload_round_time`/`pellet_spread_aim` (défauts
## neutres), `Inventory.cycle_left`/`consume_round(cycle_time)`/
## `interrupt_reload_for_fire`/rechargement PAR CARTOUCHE, et
## `WeaponFeel.pellet_cone_deg`/`scoped_sensitivity_scale`. Fichier DÉDIÉ : ne
## modifie aucun test existant (test_inventory.gd/test_weapon_feel.gd/
## test_weapon_database.gd restent intacts).
extends GdUnitTestSuite


# ---------------------------------------------------------------- WeaponConfig : défauts neutres
func test_weapon_config_new_fields_default_to_no_effect() -> void:
	var c := WeaponConfig.new()
	assert_float(c.cycle_time).is_equal_approx(0.0, 0.0001)
	assert_bool(c.reload_per_round).is_false()
	assert_float(c.reload_start_time).is_equal_approx(0.3, 0.0001)
	assert_float(c.reload_round_time).is_equal_approx(0.45, 0.0001)
	assert_float(c.pellet_spread_aim).is_equal_approx(-1.0, 0.0001)


# ---------------------------------------------------------------- WeaponFeel.pellet_cone_deg
func test_pellet_cone_deg_falls_back_to_pellet_spread_when_aim_variant_unset() -> void:
	var c := WeaponConfig.new()
	c.pellet_spread = 5.5
	assert_float(WeaponFeel.pellet_cone_deg(c, false)).is_equal_approx(5.5, 0.0001)
	# pellet_spread_aim reste -1.0 (défaut) -> retombe sur pellet_spread même en visée
	# (comportement HISTORIQUE inchangé, aucune arme du catalogue n'utilisait pellets>1
	# avant cette tâche).
	assert_float(WeaponFeel.pellet_cone_deg(c, true)).is_equal_approx(5.5, 0.0001)


func test_pellet_cone_deg_uses_dedicated_aim_value_when_configured() -> void:
	var c := WeaponConfig.new()
	c.pellet_spread = 5.5
	c.pellet_spread_aim = 4.0
	assert_float(WeaponFeel.pellet_cone_deg(c, false)).is_equal_approx(5.5, 0.0001)
	assert_float(WeaponFeel.pellet_cone_deg(c, true)).is_equal_approx(4.0, 0.0001)


# ---------------------------------------------------------------- WeaponFeel.scoped_sensitivity_scale
func test_scoped_sensitivity_scale_is_ratio_of_scoped_fov_over_base_fov() -> void:
	assert_float(WeaponFeel.scoped_sensitivity_scale(25.0, 75.0)).is_equal_approx(1.0 / 3.0, 0.0001)


func test_scoped_sensitivity_scale_is_neutral_when_fovs_match() -> void:
	assert_float(WeaponFeel.scoped_sensitivity_scale(60.0, 60.0)).is_equal_approx(1.0, 0.0001)


func test_scoped_sensitivity_scale_never_divides_by_zero() -> void:
	assert_float(WeaponFeel.scoped_sensitivity_scale(25.0, 0.0)).is_equal_approx(25.0 / 0.001, 0.1)


# ---------------------------------------------------------------- Inventory : cycle_left (pompe/levier/verrou)
func _inv_with(id: int) -> Inventory:
	var inv := Inventory.new(2)
	inv.set_loadout([id])
	return inv


# id 3 = Fracas (cycle_time 0.9, reload_per_round, mag 6) dans le catalogue
# courant (WeaponDatabase.PATHS, append-only : ravage/revolver/rafale/fracas/
# verdict/aiguille).
const FRACAS_ID := 3
const VERDICT_ID := 4
const RAVAGE_ID := 0


func test_consume_round_without_cycle_time_leaves_cycle_left_at_zero() -> void:
	var inv := _inv_with(RAVAGE_ID)  # Ravage : cycle_time = 0.0 (défaut, .tres non touché)
	inv.consume_round(0.0)
	assert_float(inv.cycle_left).is_equal_approx(0.0, 0.0001)
	assert_bool(inv.can_fire()).is_true()


func test_consume_round_with_cycle_time_arms_cycle_left_and_blocks_fire() -> void:
	var inv := _inv_with(FRACAS_ID)
	var c := WeaponDatabase.get_by_id(FRACAS_ID)
	assert_bool(inv.consume_round(c.cycle_time)).is_true()
	assert_float(inv.cycle_left).is_equal_approx(0.9, 0.0001)
	assert_bool(inv.can_fire()).append_failure_message(
		"pompe pas encore cyclée (0.9 s) -> tir refusé"
	).is_false()


func test_cycle_left_counts_down_and_reopens_fire() -> void:
	var inv := _inv_with(FRACAS_ID)
	var c := WeaponDatabase.get_by_id(FRACAS_ID)
	inv.consume_round(c.cycle_time)
	inv.tick(0.5)
	assert_float(inv.cycle_left).is_equal_approx(0.4, 0.001)
	assert_bool(inv.can_fire()).is_false()
	inv.tick(0.4)
	assert_float(inv.cycle_left).is_equal_approx(0.0, 0.001)
	assert_bool(inv.can_fire()).is_true()


func test_cycle_left_blocks_start_reload_until_cycle_finished() -> void:
	var inv := _inv_with(FRACAS_ID)
	var c := WeaponDatabase.get_by_id(FRACAS_ID)
	inv.consume_round(c.cycle_time)
	assert_bool(inv.start_reload()).append_failure_message(
		"« not interruptible except by weapon switch » -- le rechargement ne peut pas commencer pendant le cycle de pompe"
	).is_false()
	inv.tick(0.9)
	assert_bool(inv.start_reload()).is_true()


func test_equip_switch_clears_cycle_left_even_mid_cycle() -> void:
	var inv := Inventory.new(2)
	inv.set_loadout([FRACAS_ID, RAVAGE_ID])
	var c := WeaponDatabase.get_by_id(FRACAS_ID)
	inv.consume_round(c.cycle_time)
	assert_float(inv.cycle_left).is_greater(0.0)
	assert_bool(inv.equip(1)).append_failure_message(
		"« not interruptible EXCEPT by weapon switch » -- changer d'arme doit toujours marcher"
	).is_true()
	assert_float(inv.cycle_left).is_equal_approx(0.0, 0.0001)


# ---------------------------------------------------------------- Inventory : rechargement PAR CARTOUCHE
func test_start_reload_per_round_uses_reload_start_time_not_reload_time() -> void:
	var inv := _inv_with(FRACAS_ID)
	inv.consume_round(0.0)  # ne pas armer cycle_left ici -- isole le test du rechargement
	inv.cycle_left = 0.0
	assert_bool(inv.start_reload()).is_true()
	var c := WeaponDatabase.get_by_id(FRACAS_ID)
	assert_float(inv.reload_left).is_equal_approx(c.reload_start_time, 0.001)


func test_per_round_reload_inserts_one_shell_at_a_time() -> void:
	var inv := _inv_with(FRACAS_ID)
	var c := WeaponDatabase.get_by_id(FRACAS_ID)
	for i in 3:
		inv.consume_round(0.0)
	inv.cycle_left = 0.0
	assert_int(inv.mag[0]).is_equal(3)
	inv.start_reload()
	# start_time (0.3s) -> 1ère cartouche insérée, JAMAIS avant. `0.011` (pas
	# `0.01` pile) pour dépasser franchement le seuil malgré l'imprécision de
	# l'arithmétique flottante (0.3 - 0.29 - 0.01 ne tombe pas exactement sur 0.0).
	assert_bool(inv.tick(0.29)).is_false()
	assert_int(inv.mag[0]).is_equal(3)
	assert_bool(inv.tick(0.011)).is_true()
	assert_int(inv.mag[0]).is_equal(4)
	assert_bool(inv.reloading).is_true()
	# round_time (0.45s) -> 2e cartouche.
	assert_bool(inv.tick(0.45)).is_true()
	assert_int(inv.mag[0]).is_equal(5)
	assert_bool(inv.reloading).is_true()


func test_per_round_reload_stops_itself_once_mag_is_full() -> void:
	var inv := _inv_with(FRACAS_ID)
	var c := WeaponDatabase.get_by_id(FRACAS_ID)
	for i in c.mag_size:
		inv.consume_round(0.0)
	inv.cycle_left = 0.0
	assert_int(inv.mag[0]).is_equal(0)
	inv.start_reload()
	var reserve_before: int = inv.reserve[0]
	# start_time + mag_size * round_time, avec un peu de marge : le rechargement
	# doit s'être terminé TOUT SEUL (mag plein), sans jamais dépasser mag_size.
	var total: float = c.reload_start_time + c.mag_size * c.reload_round_time + 0.1
	inv.tick(total)
	assert_int(inv.mag[0]).is_equal(c.mag_size)
	assert_bool(inv.reloading).is_false()
	assert_int(inv.reserve[0]).is_equal(reserve_before - c.mag_size)


func test_per_round_reload_stops_when_reserve_runs_out() -> void:
	var inv := _inv_with(FRACAS_ID)
	var c := WeaponDatabase.get_by_id(FRACAS_ID)
	for i in c.mag_size:
		inv.consume_round(0.0)
	inv.cycle_left = 0.0
	inv.reserve[0] = 2  # moins que les 6 cartouches qu'il faudrait pour remplir le chargeur
	inv.start_reload()
	inv.tick(c.reload_start_time + 2 * c.reload_round_time + 0.1)
	assert_int(inv.mag[0]).is_equal(2)
	assert_int(inv.reserve[0]).is_equal(0)
	assert_bool(inv.reloading).is_false()


# ---------------------------------------------------------------- Inventory : tir interrompt le rechargement
func test_interrupt_reload_for_fire_does_nothing_for_block_reload_weapon() -> void:
	var inv := _inv_with(RAVAGE_ID)
	inv.consume_round(0.0)
	inv.start_reload()
	var c := WeaponDatabase.get_by_id(RAVAGE_ID)
	assert_bool(inv.interrupt_reload_for_fire(c)).append_failure_message(
		"le Ravage recharge en BLOC -- le tir ne doit jamais interrompre son rechargement"
	).is_false()
	assert_bool(inv.reloading).is_true()


func test_interrupt_reload_for_fire_does_nothing_before_first_round_is_loaded() -> void:
	var inv := _inv_with(FRACAS_ID)
	var c := WeaponDatabase.get_by_id(FRACAS_ID)
	for i in c.mag_size:
		inv.consume_round(0.0)
	inv.cycle_left = 0.0
	assert_int(inv.mag[0]).is_equal(0)
	inv.start_reload()
	# reload_left n'a pas encore atteint 0 -- aucune cartouche en chambre.
	assert_bool(inv.interrupt_reload_for_fire(c)).append_failure_message(
		"aucune cartouche encore chargée (mag == 0) -- le tir ne doit rien interrompre"
	).is_false()
	assert_bool(inv.reloading).is_true()


func test_interrupt_reload_for_fire_cancels_reload_once_a_round_is_chambered() -> void:
	var inv := _inv_with(FRACAS_ID)
	var c := WeaponDatabase.get_by_id(FRACAS_ID)
	for i in c.mag_size:
		inv.consume_round(0.0)
	inv.cycle_left = 0.0
	assert_int(inv.mag[0]).is_equal(0)
	inv.start_reload()
	inv.tick(c.reload_start_time + 0.01)  # 1 cartouche chargée
	assert_int(inv.mag[0]).is_equal(1)
	assert_bool(inv.interrupt_reload_for_fire(c)).append_failure_message(
		"« fire interrupts the reload if >= 1 shell loaded » (contrat Fracas)"
	).is_true()
	assert_bool(inv.reloading).is_false()
	assert_bool(inv.can_fire()).is_true()


func test_interrupt_reload_for_fire_refuses_with_empty_mag() -> void:
	var inv := _inv_with(FRACAS_ID)
	var c := WeaponDatabase.get_by_id(FRACAS_ID)
	for i in c.mag_size:
		inv.consume_round(0.0)
	inv.cycle_left = 0.0
	inv.start_reload()
	# Toujours 0 cartouche (reload_left n'a pas encore atteint 0).
	assert_bool(inv.interrupt_reload_for_fire(c)).is_false()
	assert_bool(inv.reloading).is_true()


# ---------------------------------------------------------------- ViewModel.action_node_name_for
func test_action_node_name_for_picks_the_right_moving_part_per_weapon() -> void:
	assert_str(ViewModel.action_node_name_for(WeaponDatabase.get_by_name("Rafale"))).is_equal("Magazine")
	assert_str(ViewModel.action_node_name_for(WeaponDatabase.get_by_name("Fracas"))).is_equal("PumpGrip")
	assert_str(ViewModel.action_node_name_for(WeaponDatabase.get_by_name("Verdict"))).is_equal("Lever")
	assert_str(ViewModel.action_node_name_for(WeaponDatabase.get_by_name("Aiguille"))).is_equal("Bolt")


func test_action_node_name_for_is_empty_for_weapons_without_a_dedicated_part() -> void:
	assert_str(ViewModel.action_node_name_for(WeaponDatabase.get_by_name("Ravage"))).is_equal("")
	assert_str(ViewModel.action_node_name_for(WeaponDatabase.get_by_name("Revolver"))).is_equal("")
	assert_str(ViewModel.action_node_name_for(null)).is_equal("")
