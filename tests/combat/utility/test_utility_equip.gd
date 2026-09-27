## test_utility_equip.gd
## Spec (contrat lead 2026-09-27, inventaire CS-style, points 4/6/7/8) :
## UtilityEquip est la machine PURE de "l'objet en main" -- voir
## scripts/combat/utility/UtilityEquip.gd. Couvre les règles d'état d'équipement
## explicitement demandées par les tests de la tâche : "can't fire while a
## grenade is equipped" et "the throw returns to the last weapon".
extends GdUnitTestSuite


func test_starts_unequipped() -> void:
	var e := UtilityEquip.new()
	assert_bool(e.is_equipped()).is_false()
	assert_bool(e.blocks_weapon_actions()).is_false()


func test_equip_sets_kind_and_starts_deploy_delay() -> void:
	var e := UtilityEquip.new()
	e.equip(UtilityDatabase.FRAG)
	assert_int(e.kind).is_equal(UtilityDatabase.FRAG)
	assert_bool(e.is_equipped()).is_true()
	assert_float(e.deploy_left).is_equal_approx(UtilityEquip.DEPLOY_DELAY_S, 0.001)


# ---- "can't fire while a grenade is equipped" ----

func test_blocks_weapon_actions_while_equipped() -> void:
	var e := UtilityEquip.new()
	e.equip(UtilityDatabase.SMOKE)
	assert_bool(e.blocks_weapon_actions()).append_failure_message(
		"la gâchette/le rechargement/l'ADS/l'inspection doivent être bloqués tant qu'une grenade est en main"
	).is_true()


func test_does_not_block_weapon_actions_once_unequipped() -> void:
	var e := UtilityEquip.new()
	e.equip(UtilityDatabase.SMOKE)
	e.unequip()
	assert_bool(e.blocks_weapon_actions()).is_false()


# ---- délai de déploiement (0.25 s) avant de pouvoir lancer ----

func test_cannot_start_throw_immediately_after_equip() -> void:
	var e := UtilityEquip.new()
	e.equip(UtilityDatabase.FRAG)
	assert_bool(e.can_start_throw()).is_false()


func test_can_start_throw_once_deploy_delay_elapses() -> void:
	var e := UtilityEquip.new()
	e.equip(UtilityDatabase.FRAG)
	e.tick(UtilityEquip.DEPLOY_DELAY_S)
	assert_bool(e.can_start_throw()).is_true()


func test_cannot_start_throw_when_nothing_equipped() -> void:
	var e := UtilityEquip.new()
	assert_bool(e.can_start_throw()).is_false()


# ---- "the throw returns to the last weapon" (retour automatique après FP_Throw) ----

func test_start_return_after_throw_does_not_unequip_immediately() -> void:
	var e := UtilityEquip.new()
	e.equip(UtilityDatabase.FRAG)
	e.start_return_after_throw()
	assert_bool(e.is_equipped()).append_failure_message(
		"la pose de lancer doit rester visible jusqu'à la fin du geste FP_Throw"
	).is_true()


func test_tick_returns_false_while_return_in_progress() -> void:
	var e := UtilityEquip.new()
	e.equip(UtilityDatabase.FRAG)
	e.start_return_after_throw()
	assert_bool(e.tick(UtilityEquip.RETURN_DELAY_S * 0.5)).is_false()
	assert_bool(e.is_equipped()).is_true()


func test_tick_unequips_exactly_when_return_delay_elapses() -> void:
	var e := UtilityEquip.new()
	e.equip(UtilityDatabase.FRAG)
	e.start_return_after_throw()
	assert_bool(e.tick(UtilityEquip.RETURN_DELAY_S)).append_failure_message(
		"tick() doit renvoyer vrai UNE fois, au tick où le retour se termine"
	).is_true()
	assert_bool(e.is_equipped()).is_false()
	assert_int(e.kind).is_equal(UtilityEquip.NONE)


func test_tick_without_a_return_in_progress_is_a_no_op() -> void:
	var e := UtilityEquip.new()
	e.equip(UtilityDatabase.FLASH)
	assert_bool(e.tick(10.0)).is_false()
	assert_bool(e.is_equipped()).append_failure_message(
		"sans lancer, rien ne doit forcer un retour à l'arme"
	).is_true()


# ---- unequip immédiat (touche d'arme directe / molette vers une arme) ----

func test_unequip_clears_kind_and_timers() -> void:
	var e := UtilityEquip.new()
	e.equip(UtilityDatabase.FRAG)
	e.start_return_after_throw()
	e.unequip()
	assert_bool(e.is_equipped()).is_false()
	assert_float(e.deploy_left).is_equal_approx(0.0, 0.001)


# ---- reset mort/respawn (contrat point 7) ----

func test_reset_on_death_or_respawn_returns_to_primary_weapon() -> void:
	var e := UtilityEquip.new()
	e.equip(UtilityDatabase.SMOKE)
	e.reset_on_death_or_respawn()
	assert_bool(e.is_equipped()).append_failure_message(
		"la mort/le respawn doivent toujours ramener sur l'arme principale"
	).is_false()


# ---- ré-équiper pendant un retour en cours annule le retour ----

func test_equip_again_during_a_pending_return_cancels_it() -> void:
	var e := UtilityEquip.new()
	e.equip(UtilityDatabase.FRAG)
	e.start_return_after_throw()
	e.equip(UtilityDatabase.FLASH)
	assert_int(e.kind).is_equal(UtilityDatabase.FLASH)
	# Un `tick` qui suit ne doit plus renvoyer vrai à l'ancienne échéance :
	# le nouveau `equip` a redémarré le délai de déploiement, pas de retour.
	assert_bool(e.tick(UtilityEquip.RETURN_DELAY_S)).is_false()
	assert_bool(e.is_equipped()).is_true()


# ---- to_dict / from_dict round-trip (synchro serveur -> propriétaire) ----

func test_to_dict_from_dict_round_trip() -> void:
	var e := UtilityEquip.new()
	e.equip(UtilityDatabase.FLASH)
	e.tick(0.1)
	var d := e.to_dict()
	var restored := UtilityEquip.from_dict(d)
	assert_int(restored.kind).is_equal(e.kind)
	assert_float(restored.deploy_left).is_equal_approx(e.deploy_left, 0.001)
	assert_float(restored.return_left).is_equal_approx(e.return_left, 0.001)


func test_from_dict_defaults_to_unequipped_for_empty_dict() -> void:
	var restored := UtilityEquip.from_dict({})
	assert_bool(restored.is_equipped()).is_false()
