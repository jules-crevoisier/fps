## test_settings_migration.gd
## Spec (design.md v2 §9/§11, "Next": Settings.enemy_color Magenta 0/Citron 1) :
## bornes pures de Settings.gd consommées par le menu Options v2 — couleur
## ennemi (2 valeurs, migration depuis un fichier v1), échelle d'interface.
## Isolées ici pour rester testables sans dépendre du garde `_loaded` (qui
## empêche un rechargement depuis disque une fois le process démarré).
extends GdUnitTestSuite


func test_enemy_color_default_is_magenta() -> void:
	assert_int(Settings.enemy_color).is_equal(0)


func test_reduced_motion_default_is_false() -> void:
	assert_bool(Settings.reduced_motion).is_false()


func test_ui_scale_default_is_one() -> void:
	assert_float(Settings.ui_scale).is_equal_approx(1.0, 0.001)


func test_clamp_enemy_color_within_range_is_unchanged() -> void:
	assert_int(Settings.clamp_enemy_color(0)).is_equal(0)
	assert_int(Settings.clamp_enemy_color(1)).is_equal(1)


func test_clamp_enemy_color_out_of_range_is_clamped_to_magenta_or_citron() -> void:
	assert_int(Settings.clamp_enemy_color(-1)).is_equal(0)
	assert_int(Settings.clamp_enemy_color(2)).is_equal(1)
	assert_int(Settings.clamp_enemy_color(99)).is_equal(1)


func test_migrate_enemy_color_without_v2_key_always_resets_to_magenta() -> void:
	# Un fichier v1 (rouge/jaune/violet) n'a pas la clé `enemy_palette_version` :
	# sa valeur numérique ne veut plus rien dire dans la palette v2, donc on ne
	# la réinterprète jamais — toujours Magenta (0), quelle que soit la valeur stockée.
	assert_int(Settings.migrate_enemy_color(0, false)).is_equal(0)
	assert_int(Settings.migrate_enemy_color(1, false)).is_equal(0)
	assert_int(Settings.migrate_enemy_color(2, false)).is_equal(0)


func test_migrate_enemy_color_with_v2_key_keeps_stored_value_clamped() -> void:
	assert_int(Settings.migrate_enemy_color(0, true)).is_equal(0)
	assert_int(Settings.migrate_enemy_color(1, true)).is_equal(1)
	assert_int(Settings.migrate_enemy_color(5, true)).is_equal(1)


func test_clamp_ui_scale_within_range_is_unchanged() -> void:
	assert_float(Settings.clamp_ui_scale(1.15)).is_equal_approx(1.15, 0.001)


func test_clamp_ui_scale_out_of_range_is_clamped() -> void:
	assert_float(Settings.clamp_ui_scale(0.1)).is_equal_approx(0.8, 0.001)
	assert_float(Settings.clamp_ui_scale(3.0)).is_equal_approx(1.5, 0.001)
