## test_settings_migration.gd
## Spec (design.md v2 §9/§11, "Next": Settings.enemy_color Magenta 0/Citron 1) :
## bornes pures de Settings.gd consommées par le menu Options v2 — couleur
## ennemi (2 valeurs, migration depuis un fichier v1), échelle d'interface,
## sensibilités souris/manette et FOV (BUG-14), application de l'échelle
## d'interface à la fenêtre (BUG-13). Isolées ici pour rester testables sans
## dépendre du garde `_loaded` (qui empêche un rechargement depuis disque une
## fois le process démarré).
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


# ------------------------------------------------------------ BUG-14 : bornes
# sensibilité souris/manette et FOV (fichier corrompu -> souris morte/inversée
# ou FOV aberrant, cf. docs/audit/bugs.md).
func test_clamp_mouse_sensitivity_within_range_is_unchanged() -> void:
	assert_float(Settings.clamp_mouse_sensitivity(0.0025)).is_equal_approx(0.0025, 0.00001)


func test_clamp_mouse_sensitivity_out_of_range_is_clamped() -> void:
	assert_float(Settings.clamp_mouse_sensitivity(-1.0)).is_equal_approx(0.0005, 0.00001)
	assert_float(Settings.clamp_mouse_sensitivity(50.0)).is_equal_approx(0.01, 0.00001)


# ------------------------------------------------------------ UX-37 : nouveau
# défaut souris + migration (retour de playtest utilisateur 2026-09-25 :
# « la sensibilité de base est beaucoup trop haute »). Un fichier qui porte
# EXACTEMENT l'ancien défaut (0.0025, jamais retouché par le joueur — rien ne
# distingue ce cas d'un choix délibéré de 0.0025) passe au nouveau défaut au
# chargement ; toute autre valeur (réglage explicite du joueur) est conservée.
func test_mouse_sensitivity_default_is_the_new_ux37_value() -> void:
	assert_float(Settings.MOUSE_SENSITIVITY_DEFAULT).is_equal_approx(0.001, 0.00001)
	assert_float(Settings.mouse_sensitivity).is_equal_approx(Settings.MOUSE_SENSITIVITY_DEFAULT, 0.00001)


func test_migrate_mouse_sensitivity_old_untouched_default_becomes_new_default() -> void:
	assert_float(Settings.migrate_mouse_sensitivity(0.0025)).is_equal_approx(
		Settings.MOUSE_SENSITIVITY_DEFAULT, 0.00001)


func test_migrate_mouse_sensitivity_other_value_is_kept() -> void:
	assert_float(Settings.migrate_mouse_sensitivity(0.0018)).is_equal_approx(0.0018, 0.00001)


func test_migrate_mouse_sensitivity_out_of_range_value_is_still_bounded() -> void:
	# BUG-14 : la migration ne contourne pas les bornes existantes pour une
	# valeur qui n'est pas l'ancien défaut.
	assert_float(Settings.migrate_mouse_sensitivity(-999.0)).is_between(0.0005, 0.01)
	assert_float(Settings.migrate_mouse_sensitivity(999.0)).is_between(0.0005, 0.01)


func test_clamp_gamepad_sensitivity_within_range_is_unchanged() -> void:
	assert_float(Settings.clamp_gamepad_sensitivity(3.0)).is_equal_approx(3.0, 0.001)


func test_clamp_gamepad_sensitivity_out_of_range_is_clamped() -> void:
	assert_float(Settings.clamp_gamepad_sensitivity(-2.0)).is_equal_approx(0.5, 0.001)
	assert_float(Settings.clamp_gamepad_sensitivity(999.0)).is_equal_approx(8.0, 0.001)


func test_clamp_fov_within_range_is_unchanged() -> void:
	assert_float(Settings.clamp_fov(90.0)).is_equal_approx(90.0, 0.001)


func test_clamp_fov_out_of_range_is_clamped() -> void:
	assert_float(Settings.clamp_fov(-40.0)).is_equal_approx(70.0, 0.001)
	assert_float(Settings.clamp_fov(1000.0)).is_equal_approx(120.0, 0.001)


func test_load_all_bounds_corrupted_sensitivity_and_fov() -> void:
	# Fichier "corrompu" simulé : valeurs hors plage écrites directement dans
	# user://settings.cfg, puis rechargées via un ConfigFile (on ne peut pas
	# rappeler `Settings.load_all()` deux fois dans le process : le garde
	# `_loaded` l'en empêche). On vérifie donc que les bornes pures
	# effectivement appliquées par `load_all()` produisent des valeurs saines
	# pour n'importe quelle entrée aberrante — couvrant la régression BUG-14.
	assert_float(Settings.clamp_mouse_sensitivity(-999.0)).is_between(0.0005, 0.01)
	assert_float(Settings.clamp_gamepad_sensitivity(-999.0)).is_between(0.5, 8.0)
	assert_float(Settings.clamp_fov(-999.0)).is_between(70.0, 120.0)


# ------------------------------------------------------------ BUG-13 : échelle
# d'interface appliquée à la fenêtre (design.md, Steam Deck).
func test_apply_ui_scale_sets_window_content_scale_factor() -> void:
	var original := Settings.ui_scale
	Settings.ui_scale = 1.25
	Settings.apply_ui_scale()
	assert_float(get_tree().root.content_scale_factor).is_equal_approx(1.25, 0.001)
	# Remet la fenêtre dans son état d'origine pour ne pas polluer les autres
	# suites de tests exécutées dans le même process headless.
	Settings.ui_scale = original
	Settings.apply_ui_scale()
