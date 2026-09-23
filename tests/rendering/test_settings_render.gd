## test_settings_render.gd
## Spec (contrat R2, "Settings (R-A)") : enemy_color/ink_edges/volume_* par
## défaut, et les bornes pures utilisées par `load_all()` (isolées pour rester
## testables sans dépendre du garde `_loaded`, qui empêche un rechargement
## depuis disque une fois le process démarré). `clamp_enemy_color` borne
## désormais à {0, 1} (design.md v2 §9 : Magenta/Citron remplace le
## rouge/jaune/violet à 3 options de v1 — mis à jour ici avec la migration
## faite côté Settings.gd par la tranche UI).
extends GdUnitTestSuite


func test_defaults() -> void:
	assert_int(Settings.enemy_color).is_equal(0)
	assert_bool(Settings.ink_edges).is_true()
	assert_float(Settings.volume_master).is_equal_approx(1.0, 0.001)
	assert_float(Settings.volume_sfx).is_equal_approx(1.0, 0.001)
	assert_float(Settings.volume_music).is_equal_approx(0.7, 0.001)


func test_clamp_enemy_color_within_range_is_unchanged() -> void:
	assert_int(Settings.clamp_enemy_color(0)).is_equal(0)
	assert_int(Settings.clamp_enemy_color(1)).is_equal(1)


func test_clamp_enemy_color_out_of_range_is_clamped() -> void:
	assert_int(Settings.clamp_enemy_color(-1)).is_equal(0)
	assert_int(Settings.clamp_enemy_color(99)).is_equal(1)


func test_clamp_volume_within_range_is_unchanged() -> void:
	assert_float(Settings.clamp_volume(0.5)).is_equal_approx(0.5, 0.001)


func test_clamp_volume_out_of_range_is_clamped() -> void:
	assert_float(Settings.clamp_volume(-0.5)).is_equal_approx(0.0, 0.001)
	assert_float(Settings.clamp_volume(2.0)).is_equal_approx(1.0, 0.001)
