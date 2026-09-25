## test_hit_feedback.gd
## Spec (contract-r4a.md "R4-FX — acceptance" #1-#4, design.md §8/§10, GF-07) :
## helpers PURS des retours de combat — variante de hitmarker, agrégation des
## plombs d'un tir par cible, empilement des chiffres de dégâts, angle de la
## flèche de dégâts, courbe de fondu, choix du mot-bruit, position hors zone
## centrale, vignette de vie basse.
extends GdUnitTestSuite


# ------------------------------------------------------------ Hitmarker (variante)
func test_marker_variant_normal_by_default() -> void:
	assert_str(HitFeedback.marker_variant(false, false)).is_equal(HitFeedback.MARKER_NORMAL)


func test_marker_variant_headshot() -> void:
	assert_str(HitFeedback.marker_variant(true, false)).is_equal(HitFeedback.MARKER_HEADSHOT)


func test_marker_variant_kill_overrides_headshot() -> void:
	assert_str(HitFeedback.marker_variant(true, true)).is_equal(HitFeedback.MARKER_KILL)
	assert_str(HitFeedback.marker_variant(false, true)).is_equal(HitFeedback.MARKER_KILL)


# ------------------------------------------------------------ Agrégation des plombs (GF-07)
func test_aggregate_shot_hits_sums_damage_for_same_target() -> void:
	var hits: Array = []
	for i in range(12):
		hits.append({"target": 42, "dmg": 8.0, "headshot": false})
	var agg := HitFeedback.aggregate_shot_hits(hits)
	assert_int(agg.size()).is_equal(1)
	assert_int(agg[0]["target"]).is_equal(42)
	assert_float(agg[0]["dmg"]).is_equal_approx(96.0, 0.001)
	assert_bool(agg[0]["headshot"]).is_false()


func test_aggregate_shot_hits_headshot_true_if_any_pellet_headshot() -> void:
	var hits: Array = [
		{"target": 7, "dmg": 10.0, "headshot": false},
		{"target": 7, "dmg": 20.0, "headshot": true},
		{"target": 7, "dmg": 10.0, "headshot": false},
	]
	var agg := HitFeedback.aggregate_shot_hits(hits)
	assert_int(agg.size()).is_equal(1)
	assert_bool(agg[0]["headshot"]).is_true()
	assert_float(agg[0]["dmg"]).is_equal_approx(40.0, 0.001)


func test_aggregate_shot_hits_separates_distinct_targets_in_order() -> void:
	var hits: Array = [
		{"target": 5, "dmg": 5.0, "headshot": false},
		{"target": 9, "dmg": 7.0, "headshot": false},
		{"target": 5, "dmg": 5.0, "headshot": false},
	]
	var agg := HitFeedback.aggregate_shot_hits(hits)
	assert_int(agg.size()).is_equal(2)
	assert_int(agg[0]["target"]).is_equal(5)
	assert_float(agg[0]["dmg"]).is_equal_approx(10.0, 0.001)
	assert_int(agg[1]["target"]).is_equal(9)
	assert_float(agg[1]["dmg"]).is_equal_approx(7.0, 0.001)


func test_aggregate_shot_hits_empty_for_no_hits() -> void:
	assert_array(HitFeedback.aggregate_shot_hits([])).is_empty()


# ------------------------------------------------------------ Empilement des chiffres (GF-07)
func test_should_stack_damage_true_within_window() -> void:
	assert_bool(HitFeedback.should_stack_damage(0.0)).is_true()
	assert_bool(HitFeedback.should_stack_damage(0.1)).is_true()
	assert_bool(HitFeedback.should_stack_damage(HitFeedback.DAMAGE_STACK_WINDOW)).is_true()


func test_should_stack_damage_false_outside_window() -> void:
	assert_bool(HitFeedback.should_stack_damage(HitFeedback.DAMAGE_STACK_WINDOW + 0.01)).is_false()
	assert_bool(HitFeedback.should_stack_damage(5.0)).is_false()


func test_should_stack_damage_false_when_negative() -> void:
	assert_bool(HitFeedback.should_stack_damage(-0.1)).is_false()


func test_damage_stack_scale_is_normal_for_first_hit() -> void:
	assert_float(HitFeedback.damage_stack_scale(1)).is_equal_approx(1.0, 0.001)


func test_damage_stack_scale_grows_with_stack_count() -> void:
	var one := HitFeedback.damage_stack_scale(1)
	var two := HitFeedback.damage_stack_scale(2)
	var three := HitFeedback.damage_stack_scale(3)
	assert_bool(two > one).is_true()
	assert_bool(three > two).is_true()


func test_damage_stack_scale_caps_out() -> void:
	assert_float(HitFeedback.damage_stack_scale(100)).is_equal_approx(HitFeedback.DAMAGE_STACK_SCALE_MAX, 0.001)


# ------------------------------------------------------------ Angle de la flèche de dégâts
func test_wedge_angle_zero_when_source_directly_ahead() -> void:
	var a := HitFeedback.wedge_angle_deg(Vector3.ZERO, Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, -5))
	assert_float(a).is_equal_approx(0.0, 0.01)


func test_wedge_angle_ninety_when_source_directly_right() -> void:
	var a := HitFeedback.wedge_angle_deg(Vector3.ZERO, Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(5, 0, 0))
	assert_float(a).is_equal_approx(90.0, 0.01)


func test_wedge_angle_negative_ninety_when_source_directly_left() -> void:
	var a := HitFeedback.wedge_angle_deg(Vector3.ZERO, Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-5, 0, 0))
	assert_float(a).is_equal_approx(-90.0, 0.01)


func test_wedge_angle_180_when_source_directly_behind() -> void:
	var a := HitFeedback.wedge_angle_deg(Vector3.ZERO, Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 5))
	assert_float(absf(a)).is_equal_approx(180.0, 0.01)


func test_wedge_angle_ignores_vertical_offset() -> void:
	var a := HitFeedback.wedge_angle_deg(Vector3(0, 2, 0), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 40, -5))
	assert_float(a).is_equal_approx(0.0, 0.01)


func test_wedge_angle_zero_when_source_at_origin() -> void:
	var a := HitFeedback.wedge_angle_deg(Vector3(3, 0, 3), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(3, 0, 3))
	assert_float(a).is_equal_approx(0.0, 0.01)


# ------------------------------------------------------------ Fondu (1 s, design.md #2)
func test_wedge_alpha_full_at_start() -> void:
	assert_float(HitFeedback.wedge_alpha(0.0)).is_equal_approx(1.0, 0.001)


func test_wedge_alpha_zero_after_duration() -> void:
	assert_float(HitFeedback.wedge_alpha(1.0)).is_equal_approx(0.0, 0.001)
	assert_float(HitFeedback.wedge_alpha(5.0)).is_equal_approx(0.0, 0.001)


func test_wedge_alpha_midpoint() -> void:
	assert_float(HitFeedback.wedge_alpha(0.5)).is_equal_approx(0.5, 0.001)


# ------------------------------------------------------------ Mot-bruit (design.md #4)
func test_sound_word_headshot_is_always_crac() -> void:
	assert_str(HitFeedback.sound_word(true, 0)).is_equal("CRAC!")
	assert_str(HitFeedback.sound_word(true, 7)).is_equal("CRAC!")


func test_sound_word_non_headshot_cycles_words() -> void:
	assert_str(HitFeedback.sound_word(false, 0)).is_equal("PAF!")
	assert_str(HitFeedback.sound_word(false, 1)).is_equal("BLAM!")
	assert_str(HitFeedback.sound_word(false, 2)).is_equal("VLAN!")
	assert_str(HitFeedback.sound_word(false, 3)).is_equal("PAF!")


func test_sound_word_never_crac_when_not_headshot() -> void:
	for pick in range(6):
		assert_str(HitFeedback.sound_word(false, pick)).is_not_equal("CRAC!")


# ------------------------------------------------------------ Position hors zone centrale (design.md #4/#8)
func test_burst_rect_left_never_overlaps_center_zone() -> void:
	var vp := Vector2(1920, 1080)
	var r := HitFeedback.burst_rect(false, vp)
	assert_bool(HudFormat.overlaps_center_zone(r, vp)).is_false()


func test_burst_rect_right_never_overlaps_center_zone() -> void:
	var vp := Vector2(1920, 1080)
	var r := HitFeedback.burst_rect(true, vp)
	assert_bool(HudFormat.overlaps_center_zone(r, vp)).is_false()


func test_burst_rect_sides_are_on_opposite_sides() -> void:
	var vp := Vector2(1920, 1080)
	var left := HitFeedback.burst_rect(false, vp)
	var right := HitFeedback.burst_rect(true, vp)
	assert_bool(left.position.x < right.position.x).is_true()


# ------------------------------------------------------------ Chronologie du burst (60/180/60, design.md §10)
func test_burst_alpha_zero_before_start() -> void:
	assert_float(HitFeedback.burst_alpha(-0.1)).is_equal_approx(0.0, 0.001)


func test_burst_alpha_ramps_in() -> void:
	assert_float(HitFeedback.burst_alpha(0.0)).is_equal_approx(0.0, 0.001)
	assert_float(HitFeedback.burst_alpha(HitFeedback.BURST_IN)).is_equal_approx(1.0, 0.001)


func test_burst_alpha_holds_full() -> void:
	assert_float(HitFeedback.burst_alpha(HitFeedback.BURST_IN + HitFeedback.BURST_HOLD * 0.5)).is_equal_approx(1.0, 0.001)


func test_burst_alpha_ramps_out_to_zero() -> void:
	assert_float(HitFeedback.burst_alpha(HitFeedback.BURST_DURATION)).is_equal_approx(0.0, 0.001)


func test_burst_total_duration_is_at_most_300ms() -> void:
	assert_float(HitFeedback.BURST_DURATION).is_less_equal(0.3)


func test_burst_scale_pops_in_then_settles() -> void:
	assert_float(HitFeedback.burst_scale(0.0)).is_equal_approx(0.6, 0.001)
	assert_float(HitFeedback.burst_scale(HitFeedback.BURST_IN)).is_equal_approx(1.0, 0.001)
	assert_float(HitFeedback.burst_scale(HitFeedback.BURST_IN + HitFeedback.BURST_HOLD)).is_equal_approx(1.0, 0.001)


# ------------------------------------------------------------ Vignette de vie basse (design.md #3)
func test_vignette_thickness_zero_above_threshold() -> void:
	assert_float(HitFeedback.vignette_thickness(0.35)).is_equal_approx(0.0, 0.001)
	assert_float(HitFeedback.vignette_thickness(1.0)).is_equal_approx(0.0, 0.001)


func test_vignette_thickness_max_at_zero_hp() -> void:
	assert_float(HitFeedback.vignette_thickness(0.0, 200.0)).is_equal_approx(200.0, 0.001)


func test_vignette_thickness_scales_linearly() -> void:
	assert_float(HitFeedback.vignette_thickness(0.175, 200.0)).is_equal_approx(100.0, 0.001)


func test_vignette_pulse_stays_within_bounds() -> void:
	for i in range(20):
		var t := float(i) * 0.1
		var v := HitFeedback.vignette_pulse(t)
		assert_float(v).is_between(0.59, 1.01)


func test_vignette_pulse_frequency_is_at_most_1hz() -> void:
	assert_float(HitFeedback.VIGNETTE_PULSE_HZ).is_less_equal(1.0)
