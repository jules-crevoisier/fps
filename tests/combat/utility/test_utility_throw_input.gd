## test_utility_throw_input.gd
## Spec (contrat lead) : appui court -> lance immédiatement (pas d'arc) ;
## maintien -> affiche l'arc, lance au relâchement ; frag maintenue au-delà de
## l'amorce explose en main.
extends GdUnitTestSuite


func test_short_hold_does_not_show_arc() -> void:
	assert_bool(UtilityThrowInput.should_show_arc(0.05)).is_false()


func test_hold_past_threshold_shows_arc() -> void:
	assert_bool(UtilityThrowInput.should_show_arc(0.2)).is_true()


func test_threshold_boundary_shows_arc() -> void:
	assert_bool(UtilityThrowInput.should_show_arc(UtilityThrowInput.HOLD_THRESHOLD_S)).is_true()


func test_should_explode_in_hand_once_fuse_fully_held() -> void:
	assert_bool(UtilityThrowInput.should_explode_in_hand(2.5, 2.5)).is_true()
	assert_bool(UtilityThrowInput.should_explode_in_hand(2.4, 2.5)).is_false()


func test_fuse_left_on_release_counts_down_from_press() -> void:
	assert_float(UtilityThrowInput.fuse_left_on_release(1.0, 2.5)).is_equal_approx(1.5, 0.001)


func test_fuse_left_on_release_never_negative() -> void:
	assert_float(UtilityThrowInput.fuse_left_on_release(9.0, 2.5)).is_equal_approx(0.0, 0.001)
