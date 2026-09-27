## test_throw_mode_switch.gd
## Spec (retour utilisateur 2026-09-27) : pendant qu'on maintient un lancer, appuyer
## sur l'autre bouton bascule court <-> long (« au cas où c'est loupé la première
## fois ») ; le lancer part au relâchement du bouton actif.
extends GdUnitTestSuite


func test_left_click_during_a_short_lob_switches_to_the_long_throw() -> void:
	assert_bool(UtilityThrower.switched_throw_mode(true, true, false)).is_false()


func test_right_click_during_a_long_throw_switches_to_the_short_lob() -> void:
	assert_bool(UtilityThrower.switched_throw_mode(false, false, true)).is_true()


func test_no_new_press_keeps_the_current_mode() -> void:
	assert_bool(UtilityThrower.switched_throw_mode(true, false, false)).is_true()
	assert_bool(UtilityThrower.switched_throw_mode(false, false, false)).is_false()


func test_pressing_the_active_button_again_changes_nothing() -> void:
	assert_bool(UtilityThrower.switched_throw_mode(true, false, true)).is_true()
	assert_bool(UtilityThrower.switched_throw_mode(false, true, false)).is_false()
