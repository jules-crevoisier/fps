## test_crosshair.gd
## Spec (GF-09, docs/research/01_game_feel.md #8) : réticule dynamique — écart
## des traits = tan(spread)/tan(fov_v/2) × hauteur_écran/2 ± 1 px (WeaponFeel.
## crosshair_gap_px, MÊME fonction que GameHUD._update_crosshair réutilise
## depuis la pipeline de tir), bloom cosmétique au spray (WeaponFeel.
## crosshair_bloom_alpha, Crosshair.notify_shot) qui ne modifie PAS l'écart,
## et option "réticule statique" (Crosshair.static_mode) qui fige l'écart et
## coupe le bloom.
extends GdUnitTestSuite


# ------------------------------------------------------------ WeaponFeel.crosshair_gap_px (formule)
func test_crosshair_gap_matches_tan_formula_within_one_pixel() -> void:
	var spread_rad := deg_to_rad(2.0)
	var fov_v_rad := deg_to_rad(90.0)
	var screen_h := 1080.0
	var expected := tan(spread_rad) / tan(fov_v_rad * 0.5) * (screen_h * 0.5)
	var gap := WeaponFeel.crosshair_gap_px(spread_rad, fov_v_rad, screen_h)
	assert_float(gap).is_equal_approx(expected, 1.0)


func test_crosshair_gap_zero_spread_is_zero() -> void:
	var gap := WeaponFeel.crosshair_gap_px(0.0, deg_to_rad(90.0), 1080.0)
	assert_float(gap).is_equal_approx(0.0, 0.001)


func test_crosshair_gap_scales_with_screen_height() -> void:
	var spread_rad := deg_to_rad(3.0)
	var fov_v_rad := deg_to_rad(90.0)
	var gap_1080 := WeaponFeel.crosshair_gap_px(spread_rad, fov_v_rad, 1080.0)
	var gap_2160 := WeaponFeel.crosshair_gap_px(spread_rad, fov_v_rad, 2160.0)
	assert_float(gap_2160).is_equal_approx(gap_1080 * 2.0, 0.01)


func test_crosshair_gap_wider_fov_gives_smaller_gap() -> void:
	# À dispersion égale, une FOV verticale plus large "dézoome" l'écran :
	# le même cône de tir occupe moins de pixels.
	var spread_rad := deg_to_rad(2.0)
	var narrow := WeaponFeel.crosshair_gap_px(spread_rad, deg_to_rad(60.0), 1080.0)
	var wide := WeaponFeel.crosshair_gap_px(spread_rad, deg_to_rad(110.0), 1080.0)
	assert_bool(wide < narrow).is_true()


func test_crosshair_gap_matches_reference_hip_fire_values() -> void:
	# Ravage (docs/BALANCE.md) : 2.0° à la hanche, FOV par défaut 90°
	# (Settings.fov), 1080p — vérifie la formule avec des valeurs de jeu réelles.
	var expected := tan(deg_to_rad(2.0)) / tan(deg_to_rad(45.0)) * 540.0
	var gap := WeaponFeel.crosshair_gap_px(deg_to_rad(2.0), deg_to_rad(90.0), 1080.0)
	assert_float(gap).is_equal_approx(expected, 1.0)


# ------------------------------------------------------------ WeaponFeel.crosshair_bloom_alpha (fondu)
func test_crosshair_bloom_alpha_full_at_shot() -> void:
	assert_float(WeaponFeel.crosshair_bloom_alpha(0.0, 0.15)).is_equal_approx(1.0, 0.001)


func test_crosshair_bloom_alpha_zero_after_duration() -> void:
	assert_float(WeaponFeel.crosshair_bloom_alpha(0.15, 0.15)).is_equal_approx(0.0, 0.001)
	assert_float(WeaponFeel.crosshair_bloom_alpha(5.0, 0.15)).is_equal_approx(0.0, 0.001)


func test_crosshair_bloom_alpha_linear_midpoint() -> void:
	assert_float(WeaponFeel.crosshair_bloom_alpha(0.075, 0.15)).is_equal_approx(0.5, 0.001)


func test_crosshair_bloom_alpha_never_negative_before_shot() -> void:
	# t_since_shot négatif (défensif, ne devrait pas arriver) -> plein, jamais < 0.
	assert_float(WeaponFeel.crosshair_bloom_alpha(-1.0, 0.15)).is_equal_approx(1.0, 0.001)


# ------------------------------------------------------------ Crosshair (nœud) — écart dynamique
func _crosshair() -> Crosshair:
	return auto_free(Crosshair.new())


func test_crosshair_default_gap_before_any_update_is_legacy_gap() -> void:
	var cross := _crosshair()
	assert_float(cross.current_gap_px()).is_equal_approx(Crosshair.DEFAULT_GAP_PX, 0.001)


func test_crosshair_update_spread_matches_weapon_feel_formula() -> void:
	var cross := _crosshair()
	var spread_rad := deg_to_rad(4.0)
	var fov_v_deg := 90.0
	var screen_h := 1080.0
	cross.update_spread(spread_rad, fov_v_deg, screen_h)
	var expected := WeaponFeel.crosshair_gap_px(spread_rad, deg_to_rad(fov_v_deg), screen_h)
	assert_float(cross.current_gap_px()).is_equal_approx(expected, 0.001)


func test_crosshair_update_spread_hip_vs_ads_gap_shrinks() -> void:
	# ADS (0.3°) doit donner un écart plus petit que la hanche (2.0°), même FOV/écran.
	var cross := _crosshair()
	cross.update_spread(deg_to_rad(2.0), 90.0, 1080.0)
	var hip_gap := cross.current_gap_px()
	cross.update_spread(deg_to_rad(0.3), 90.0, 1080.0)
	var ads_gap := cross.current_gap_px()
	assert_bool(ads_gap < hip_gap).is_true()


# ------------------------------------------------------------ Crosshair (nœud) — bloom au spray
func test_crosshair_notify_shot_triggers_full_bloom() -> void:
	var cross := _crosshair()
	assert_float(cross.current_bloom_alpha()).is_equal_approx(0.0, 0.001)  # rien avant le premier tir
	cross.notify_shot()
	assert_float(cross.current_bloom_alpha()).is_equal_approx(1.0, 0.001)


func test_crosshair_bloom_decays_after_shot() -> void:
	var cross := _crosshair()
	cross.notify_shot()
	cross._process(Crosshair.BLOOM_DURATION_S * 0.5)
	assert_float(cross.current_bloom_alpha()).is_equal_approx(0.5, 0.01)
	cross._process(Crosshair.BLOOM_DURATION_S)
	assert_float(cross.current_bloom_alpha()).is_equal_approx(0.0, 0.001)


func test_crosshair_bloom_does_not_change_the_real_gap() -> void:
	# Le bloom est cosmétique : il ne doit JAMAIS fausser l'écart réel affiché.
	var cross := _crosshair()
	cross.update_spread(deg_to_rad(2.0), 90.0, 1080.0)
	var gap_before := cross.current_gap_px()
	cross.notify_shot()
	assert_float(cross.current_gap_px()).is_equal_approx(gap_before, 0.001)


# ------------------------------------------------------------ Crosshair (nœud) — option statique
func test_crosshair_static_mode_ignores_dynamic_spread() -> void:
	var cross := _crosshair()
	cross.static_mode = true
	cross.update_spread(deg_to_rad(5.0), 90.0, 1080.0)
	assert_float(cross.current_gap_px()).is_equal_approx(Crosshair.DEFAULT_GAP_PX, 0.001)


func test_crosshair_static_mode_cuts_bloom() -> void:
	var cross := _crosshair()
	cross.static_mode = true
	cross.notify_shot()
	assert_float(cross.current_bloom_alpha()).is_equal_approx(0.0, 0.001)


func test_crosshair_leaving_static_mode_restores_dynamic_gap() -> void:
	var cross := _crosshair()
	cross.update_spread(deg_to_rad(5.0), 90.0, 1080.0)
	var dynamic_gap := cross.current_gap_px()
	cross.static_mode = true
	assert_float(cross.current_gap_px()).is_equal_approx(Crosshair.DEFAULT_GAP_PX, 0.001)
	cross.static_mode = false
	assert_float(cross.current_gap_px()).is_equal_approx(dynamic_gap, 0.001)
