## test_out_of_combat_tracker.gd
## Spec (contract-r2.md, R-B3 acceptance #2): le soin de base (HealAbility) ne
## fonctionne que si le joueur n'a pris aucun dégât depuis 3 s. Logique pure,
## horodatage injecté (pas d'accès à Time.get_ticks_msec ici) pour rester testable.
extends GdUnitTestSuite


func test_never_damaged_is_out_of_combat() -> void:
	var t := OutOfCombatTracker.new()
	assert_bool(t.is_out_of_combat(1000.0, 3.0)).is_true()


func test_just_damaged_is_in_combat() -> void:
	var t := OutOfCombatTracker.new()
	t.mark_damaged(10.0)
	assert_bool(t.is_out_of_combat(11.0, 3.0)).is_false()


func test_out_of_combat_after_window_elapses() -> void:
	var t := OutOfCombatTracker.new()
	t.mark_damaged(10.0)
	assert_bool(t.is_out_of_combat(12.9, 3.0)).is_false()
	assert_bool(t.is_out_of_combat(13.0, 3.0)).is_true()
	assert_bool(t.is_out_of_combat(20.0, 3.0)).is_true()


func test_repeated_damage_resets_the_window() -> void:
	var t := OutOfCombatTracker.new()
	t.mark_damaged(10.0)
	t.mark_damaged(12.0)
	assert_bool(t.is_out_of_combat(14.5, 3.0)).is_false()
	assert_bool(t.is_out_of_combat(15.0, 3.0)).is_true()
