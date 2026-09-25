## test_settings.gd
## Spec (UX-06, docs/research/04_ui_ux.md §2.7 "Réglages qu'un shooter PC doit
## avoir" — Affichage, sensibilité ADS, maintien/bascule, secousses/head-bob,
## volumes voix/UI/ambiance, audio mono, FPS/réseau, réinitialisation par
## page) : défauts, bornes pures, aller-retour de persistance (Settings.
## save_all -> relecture indépendante du fichier, même principe que
## tests/ui/test_settings_migration.gd, qui reste hors du périmètre de cette
## tâche), application moteur (DisplayServer/Engine/Viewport) et
## réinitialisation isolée par page. Le bus Master/Voice/Ambience (Audio.gd,
## autoload "Sfx") est déjà démarré par l'arbre de scène du test runner —
## voir tests/ui/test_settings_migration.gd::test_apply_ui_scale_sets_window_content_scale_factor
## pour le même principe (accès direct à `get_tree().root`/aux singletons
## sans reconstruire de scène).
##
## Relance après QA (UX-06) : les réglages ADS/maintien-bascule étaient
## persistés mais jamais LUS en jeu. Les deux sections "APPLICATION EN JEU"
## ci-dessous prouvent l'EFFET (pas seulement la persistance) via les
## fonctions PURES qui portent désormais ce comportement —
## `PlayerController.effective_look_sensitivity` (scripts/player/
## PlayerController.gd::_look/_gamepad_look) et `PlayerInput.resolve_hold_or_toggle`
## (scripts/player/PlayerInput.gd::gather_from_devices) — plutôt que de piloter
## le singleton Input (voir tests/input/test_player_input.gd, hors du périmètre
## de cette tâche, pour l'explication de pourquoi les fronts "just_pressed" ne
## sont pas fiables à travers ce singleton dans un test headless sans boucle).
extends GdUnitTestSuite


# ============================================================ DÉFAUTS (UX-06)

func test_default_window_mode_is_windowed() -> void:
	assert_str(Settings.window_mode).is_equal("windowed")


func test_default_render_scale_is_one() -> void:
	assert_float(Settings.render_scale).is_equal_approx(1.0, 0.001)


func test_default_vsync_enabled_is_true() -> void:
	assert_bool(Settings.vsync_enabled).is_true()


func test_default_fps_limit_is_unlimited() -> void:
	assert_int(Settings.fps_limit).is_equal(0)


func test_default_graphics_preset_is_quality() -> void:
	assert_str(Settings.graphics_preset).is_equal("quality")


func test_default_ads_sensitivity_multiplier_is_one() -> void:
	assert_float(Settings.ads_sensitivity_multiplier).is_equal_approx(1.0, 0.001)


func test_default_hold_to_aim_crouch_walk_are_true() -> void:
	# Comportement actuel inchangé par défaut (maintien), voir docstring Settings.gd.
	assert_bool(Settings.hold_to_aim).is_true()
	assert_bool(Settings.hold_to_crouch).is_true()
	assert_bool(Settings.hold_to_walk).is_true()


func test_default_camera_shake_enabled_is_true() -> void:
	assert_bool(Settings.camera_shake_enabled).is_true()


func test_default_head_bob_enabled_is_true_and_intensity_is_one() -> void:
	assert_bool(Settings.head_bob_enabled).is_true()
	assert_float(Settings.head_bob_intensity).is_equal_approx(1.0, 0.001)


func test_default_volume_ui_voice_ambience_are_full() -> void:
	assert_float(Settings.volume_ui).is_equal_approx(1.0, 0.001)
	assert_float(Settings.volume_voice).is_equal_approx(1.0, 0.001)
	assert_float(Settings.volume_ambience).is_equal_approx(1.0, 0.001)


func test_default_audio_mono_is_false() -> void:
	assert_bool(Settings.audio_mono).is_false()


func test_default_show_perf_overlay_is_false() -> void:
	assert_bool(Settings.show_perf_overlay).is_false()


# ============================================================ BORNES PURES (UX-06)

func test_clamp_window_mode_accepts_known_values() -> void:
	assert_str(Settings.clamp_window_mode("windowed")).is_equal("windowed")
	assert_str(Settings.clamp_window_mode("borderless")).is_equal("borderless")
	assert_str(Settings.clamp_window_mode("fullscreen")).is_equal("fullscreen")


func test_clamp_window_mode_unknown_value_resets_to_windowed() -> void:
	assert_str(Settings.clamp_window_mode("ultra-wide")).is_equal("windowed")
	assert_str(Settings.clamp_window_mode("")).is_equal("windowed")


func test_clamp_render_scale_within_range_is_unchanged() -> void:
	assert_float(Settings.clamp_render_scale(0.75)).is_equal_approx(0.75, 0.001)


func test_clamp_render_scale_out_of_range_is_clamped_50_to_100_percent() -> void:
	assert_float(Settings.clamp_render_scale(0.1)).is_equal_approx(0.5, 0.001)
	assert_float(Settings.clamp_render_scale(4.0)).is_equal_approx(1.0, 0.001)


func test_clamp_fps_limit_accepts_the_four_options() -> void:
	for v in Settings.FPS_LIMIT_OPTIONS:
		assert_int(Settings.clamp_fps_limit(v)).is_equal(v)


func test_clamp_fps_limit_unknown_value_resets_to_unlimited() -> void:
	assert_int(Settings.clamp_fps_limit(30)).is_equal(0)
	assert_int(Settings.clamp_fps_limit(-1)).is_equal(0)
	assert_int(Settings.clamp_fps_limit(999)).is_equal(0)


func test_clamp_graphics_preset_accepts_known_presets() -> void:
	for k in Settings.GRAPHICS_PRESETS:
		assert_str(Settings.clamp_graphics_preset(k)).is_equal(k)


func test_clamp_graphics_preset_unknown_value_resets_to_default() -> void:
	assert_str(Settings.clamp_graphics_preset("ultra-nightmare")).is_equal(Settings.GRAPHICS_PRESET_DEFAULT)


func test_clamp_ads_sensitivity_multiplier_within_range_is_unchanged() -> void:
	assert_float(Settings.clamp_ads_sensitivity_multiplier(0.8)).is_equal_approx(0.8, 0.001)


func test_clamp_ads_sensitivity_multiplier_out_of_range_is_clamped() -> void:
	assert_float(Settings.clamp_ads_sensitivity_multiplier(-1.0)).is_equal_approx(0.3, 0.001)
	assert_float(Settings.clamp_ads_sensitivity_multiplier(50.0)).is_equal_approx(2.0, 0.001)


func test_clamp_head_bob_intensity_within_range_is_unchanged() -> void:
	assert_float(Settings.clamp_head_bob_intensity(1.5)).is_equal_approx(1.5, 0.001)


func test_clamp_head_bob_intensity_out_of_range_is_clamped() -> void:
	assert_float(Settings.clamp_head_bob_intensity(-3.0)).is_equal_approx(0.0, 0.001)
	assert_float(Settings.clamp_head_bob_intensity(9.0)).is_equal_approx(2.0, 0.001)


# ============================================================ ALLER-RETOUR DE PERSISTANCE
# "chaque réglage est persisté puis relu" (acceptance UX-06) : Settings.save_all
# écrit sur disque, puis une relecture INDÉPENDANTE (ConfigFile frais, jamais
# Settings.load_all — le garde `_loaded` empêche un second chargement dans le
# même process, voir tests/ui/test_settings_migration.gd) vérifie que les
# valeurs stockées correspondent bien à ce que load_all() relirait ensuite au
# prochain lancement.

func test_round_trip_persists_and_rereads_every_ux06_setting() -> void:
	# Capture pour restaurer exactement l'état d'avant ce test (les statics de
	# Settings sont partagés par toute la suite headless).
	var before := _snapshot()

	Settings.window_mode = "fullscreen"
	Settings.render_scale = 0.65
	Settings.vsync_enabled = false
	Settings.fps_limit = 144
	Settings.graphics_preset = "steam_deck"
	Settings.ads_sensitivity_multiplier = 0.75
	Settings.hold_to_aim = false
	Settings.hold_to_crouch = false
	Settings.hold_to_walk = false
	Settings.camera_shake_enabled = false
	Settings.head_bob_enabled = false
	Settings.head_bob_intensity = 1.6
	Settings.volume_ui = 0.42
	Settings.volume_voice = 0.33
	Settings.volume_ambience = 0.77
	Settings.audio_mono = true
	Settings.show_perf_overlay = true
	Settings.save_all()

	var cfg := ConfigFile.new()
	assert_int(cfg.load(Settings.PATH)).is_equal(OK)
	assert_str(str(cfg.get_value("video", "window_mode"))).is_equal("fullscreen")
	assert_float(float(cfg.get_value("video", "render_scale"))).is_equal_approx(0.65, 0.001)
	assert_bool(bool(cfg.get_value("video", "vsync_enabled"))).is_false()
	assert_int(int(cfg.get_value("video", "fps_limit"))).is_equal(144)
	assert_str(str(cfg.get_value("video", "graphics_preset"))).is_equal("steam_deck")
	assert_float(float(cfg.get_value("input", "ads_sensitivity_multiplier"))).is_equal_approx(0.75, 0.001)
	assert_bool(bool(cfg.get_value("input", "hold_to_aim"))).is_false()
	assert_bool(bool(cfg.get_value("input", "hold_to_crouch"))).is_false()
	assert_bool(bool(cfg.get_value("input", "hold_to_walk"))).is_false()
	assert_bool(bool(cfg.get_value("camera", "camera_shake_enabled"))).is_false()
	assert_bool(bool(cfg.get_value("camera", "head_bob_enabled"))).is_false()
	assert_float(float(cfg.get_value("camera", "head_bob_intensity"))).is_equal_approx(1.6, 0.001)
	assert_float(float(cfg.get_value("audio", "volume_ui"))).is_equal_approx(0.42, 0.001)
	assert_float(float(cfg.get_value("audio", "volume_voice"))).is_equal_approx(0.33, 0.001)
	assert_float(float(cfg.get_value("audio", "volume_ambience"))).is_equal_approx(0.77, 0.001)
	assert_bool(bool(cfg.get_value("audio", "audio_mono"))).is_true()
	assert_bool(bool(cfg.get_value("debug", "show_perf_overlay"))).is_true()

	# Les bornes de load_all() (BUG-14 : fichier corrompu -> valeur saine) sont
	# déjà couvertes par les tests clamp_* ci-dessus (mêmes fonctions, exactes) :
	# load_all() ne fait que `champ = clamp_x(cfg.get_value(...))` pour chacun.

	_restore(before)


# ============================================================ APPLICATION MOTEUR (UX-06)

func test_apply_render_scale_sets_viewport_scaling_3d_scale() -> void:
	var original := Settings.render_scale
	Settings.render_scale = 0.7
	Settings.apply_render_scale()
	assert_float(get_tree().root.scaling_3d_scale).is_equal_approx(0.7, 0.001)
	Settings.render_scale = original
	Settings.apply_render_scale()


func test_apply_vsync_calls_display_server_without_crashing() -> void:
	# Bruit connu (comme les erreurs "material is null" en headless, voir
	# CLAUDE.md) : le pilote d'affichage headless ignore `window_set_vsync_mode`
	# et `window_get_vsync_mode()` renvoie toujours la même valeur quel que soit
	# l'appel — pas de fenêtre réelle à synchroniser. On vérifie donc seulement
	# que l'appel ne plante pas ; la valeur PERSISTÉE (`Settings.vsync_enabled`)
	# est déjà couverte par le test d'aller-retour ci-dessus.
	var original := Settings.vsync_enabled
	Settings.vsync_enabled = false
	Settings.apply_vsync()
	Settings.vsync_enabled = true
	Settings.apply_vsync()
	Settings.vsync_enabled = original
	Settings.apply_vsync()


func test_apply_fps_limit_sets_engine_max_fps() -> void:
	var original := Settings.fps_limit
	Settings.fps_limit = 144
	Settings.apply_fps_limit()
	assert_int(Engine.max_fps).is_equal(144)
	Settings.fps_limit = original
	Settings.apply_fps_limit()


func test_apply_graphics_preset_steam_deck_sets_the_four_fields_and_engine_state() -> void:
	var before := _snapshot()
	Settings.apply_graphics_preset("steam_deck")
	assert_str(Settings.graphics_preset).is_equal("steam_deck")
	assert_float(Settings.render_scale).is_equal_approx(0.7, 0.001)
	assert_int(Settings.fps_limit).is_equal(60)
	assert_bool(Settings.ink_edges).is_false()
	assert_float(Settings.ui_scale).is_equal_approx(1.15, 0.001)
	assert_float(get_tree().root.scaling_3d_scale).is_equal_approx(0.7, 0.001)
	assert_int(Engine.max_fps).is_equal(60)
	assert_float(get_tree().root.content_scale_factor).is_equal_approx(1.15, 0.001)
	_restore(before)


func test_apply_graphics_preset_unknown_name_falls_back_to_default() -> void:
	var before := _snapshot()
	Settings.apply_graphics_preset("nightmare")
	assert_str(Settings.graphics_preset).is_equal(Settings.GRAPHICS_PRESET_DEFAULT)
	_restore(before)


# ============================================================ RÉINITIALISATION PAR PAGE (UX-06)
# "« Réinitialiser » remet les valeurs par défaut de la page seulement" —
# chaque test change un réglage de la page ciblée ET un réglage d'une AUTRE
# page, puis vérifie que seule la page ciblée revient à son défaut.

func test_reset_kb_page_resets_only_keyboard_mouse_settings() -> void:
	var before := _snapshot()
	Settings.mouse_sensitivity = 0.009
	Settings.fov = 90.0
	Settings.fov_effects_enabled = false
	Settings.ads_sensitivity_multiplier = 0.5
	Settings.hold_to_aim = false
	Settings.hold_to_crouch = false
	Settings.hold_to_walk = false
	Settings.layout = "azerty"
	Settings.gamepad_sensitivity = 6.0  # page "Manette" — ne doit PAS être touché
	Settings.volume_master = 0.2         # page "Affichage & Son" — ne doit PAS être touché

	Settings.reset_kb_page()

	assert_float(Settings.mouse_sensitivity).is_equal_approx(Settings.MOUSE_SENSITIVITY_DEFAULT, 0.00001)
	assert_float(Settings.fov).is_equal_approx(Settings.DEFAULT_FOV_H, 0.01)
	assert_bool(Settings.fov_effects_enabled).is_true()
	assert_float(Settings.ads_sensitivity_multiplier).is_equal_approx(1.0, 0.001)
	assert_bool(Settings.hold_to_aim).is_true()
	assert_bool(Settings.hold_to_crouch).is_true()
	assert_bool(Settings.hold_to_walk).is_true()
	# UX-14 : "Réinitialiser" ne force plus jamais QWERTY (voir Bug 2,
	# Settings.LAYOUT_OPTIONS) — il revient au mode "auto" (détection à
	# l'affichage), pas à une valeur logique forcée.
	assert_str(Settings.layout).is_equal("auto")
	assert_float(Settings.gamepad_sensitivity).is_equal_approx(6.0, 0.001)
	assert_float(Settings.volume_master).is_equal_approx(0.2, 0.001)

	_restore(before)


# ============================================================ DISPOSITION CLAVIER (UX-14)
# `Auto / AZERTY / QWERTY` — un LIBELLÉ seulement (les liaisons restent
# toujours physiques), migration des anciennes sauvegardes LOGIQUES, et
# réinitialisation qui ne peut plus recréer le Bug 2 (double action
# Gauche + Capacité 1 sur un OS AZERTY, docs/research/10_ammo_kits_input.md
# §4.1/§4.2).

func test_default_layout_is_auto() -> void:
	assert_str(Settings.layout).is_equal("auto")


func test_clamp_layout_accepts_the_three_modes() -> void:
	for v in Settings.LAYOUT_OPTIONS:
		assert_str(Settings.clamp_layout(v)).is_equal(v)


func test_clamp_layout_unknown_value_resets_to_auto() -> void:
	assert_str(Settings.clamp_layout("dvorak")).is_equal("auto")
	assert_str(Settings.clamp_layout("")).is_equal("auto")


func test_migrate_layout_qwerty_becomes_auto() -> void:
	# "qwerty" était le défaut ET la valeur FORCÉE par l'ancien reset : il ne
	# prouve rien sur le clavier réel du joueur.
	assert_str(Settings.migrate_layout("qwerty")).is_equal("auto")


func test_migrate_layout_keeps_an_explicit_azerty_choice() -> void:
	assert_str(Settings.migrate_layout("azerty")).is_equal("azerty")


func test_migrate_layout_unknown_value_resets_to_auto() -> void:
	assert_str(Settings.migrate_layout("dvorak")).is_equal("auto")


# ------------------------------------------------------ label_for_physical, 3 modes

func test_label_for_physical_azerty_mode_translates_the_moved_letters() -> void:
	var original := Settings.layout
	Settings.layout = "azerty"
	assert_str(Settings.label_for_physical(KEY_Q)).is_equal("A")
	assert_str(Settings.label_for_physical(KEY_W)).is_equal("Z")
	assert_str(Settings.label_for_physical(KEY_A)).is_equal("Q")
	assert_str(Settings.label_for_physical(KEY_Z)).is_equal("W")
	Settings.layout = original


func test_label_for_physical_qwerty_mode_is_the_raw_us_label() -> void:
	var original := Settings.layout
	Settings.layout = "qwerty"
	assert_str(Settings.label_for_physical(KEY_Q)).is_equal(OS.get_keycode_string(KEY_Q))
	assert_str(Settings.label_for_physical(KEY_A)).is_equal(OS.get_keycode_string(KEY_A))
	Settings.layout = original


func test_label_for_physical_auto_mode_falls_back_to_us_label_when_headless() -> void:
	# Suite gdUnit4 : toujours en tête headless (voir KeyLabel.gd, hors de ce
	# lot, même garde) — `DisplayServer.keyboard_get_label_from_physical` n'a
	# aucun clavier réel à consulter, on retombe sur le libellé US brut.
	var original := Settings.layout
	Settings.layout = "auto"
	assert_bool(DisplayServer.get_name() == "headless").is_true()
	assert_str(Settings.label_for_physical(KEY_Q)).is_equal(OS.get_keycode_string(KEY_Q))
	Settings.layout = original


func test_label_for_physical_never_retranslates_the_digit_row() -> void:
	# Un joueur FR presse la même touche physique quel que soit le mode : la
	# rangée de chiffres reste "1".."0", jamais "&"/"é"/"\"".
	var original := Settings.layout
	for mode in Settings.LAYOUT_OPTIONS:
		Settings.layout = mode
		assert_str(Settings.label_for_physical(KEY_1)).is_equal("1")
		assert_str(Settings.label_for_physical(KEY_0)).is_equal("0")
	Settings.layout = original


# ------------------------------------------------------ migration des sauvegardes LOGIQUES

func test_migrate_logical_key_event_azerty_maps_zqsd_to_physical_wasd() -> void:
	var z := InputEventKey.new()
	z.keycode = KEY_Z
	var migrated_z := Settings.migrate_logical_key_event(z, true)
	assert_int(migrated_z.physical_keycode).is_equal(KEY_W)
	assert_int(migrated_z.keycode).is_equal(0)

	var q := InputEventKey.new()
	q.keycode = KEY_Q
	var migrated_q := Settings.migrate_logical_key_event(q, true)
	assert_int(migrated_q.physical_keycode).is_equal(KEY_A)
	assert_int(migrated_q.keycode).is_equal(0)

	var s := InputEventKey.new()
	s.keycode = KEY_S
	assert_int(Settings.migrate_logical_key_event(s, true).physical_keycode).is_equal(KEY_S)

	var d := InputEventKey.new()
	d.keycode = KEY_D
	assert_int(Settings.migrate_logical_key_event(d, true).physical_keycode).is_equal(KEY_D)


func test_migrate_logical_key_event_qwerty_save_is_identity_mapping() -> void:
	var w := InputEventKey.new()
	w.keycode = KEY_W
	var migrated := Settings.migrate_logical_key_event(w, false)
	assert_int(migrated.physical_keycode).is_equal(KEY_W)
	assert_int(migrated.keycode).is_equal(0)


func test_migrate_logical_key_event_already_physical_is_left_untouched() -> void:
	var already := InputEventKey.new()
	already.physical_keycode = KEY_A
	already.keycode = 0
	var result := Settings.migrate_logical_key_event(already, true)
	assert_int(result.physical_keycode).is_equal(KEY_A)
	assert_int(result.keycode).is_equal(0)


# ------------------------------------------------------ Bug 2 : plus de double action

func test_reset_kb_page_movement_bindings_become_physical_never_logical() -> void:
	# Bug historique (UX-14, docs/research/10_ammo_kits_input.md §4.1 Bug 2) :
	# l'ancien apply_layout("qwerty") liait Gauche en clavier LOGIQUE (keycode
	# KEY_A). Sur un OS AZERTY, la position physique Q (liée à Capacité 2,
	# `project.godot` : action "ability_q", physical_keycode 81) TAPE la
	# lettre "A" — Gauche ET Capacité 2 se déclenchaient sur LA MÊME pression.
	# On simule cette liaison logique historique, puis on vérifie que la
	# réinitialisation la remplace par une liaison PHYSIQUE (donc indépendante
	# de la disposition de l'OS, et qui ne peut plus coïncider avec Capacité 2).
	var before := _snapshot()
	var legacy := InputEventKey.new()
	legacy.keycode = KEY_A
	legacy.physical_keycode = 0
	Settings.set_binding("move_left", legacy)

	Settings.reset_kb_page()

	var found := false
	for e in InputMap.action_get_events("move_left"):
		if e is InputEventKey:
			found = true
			assert_int(e.keycode).is_equal(0)
			assert_int(e.physical_keycode).is_not_equal(0)
			# La position physique de Capacité 2 (project.godot : physique 81,
			# "Q") ne doit plus jamais coïncider avec Gauche.
			assert_bool(InputMap.event_is_action(e, "ability_q")).is_false()
	assert_bool(found).is_true()

	_restore(before)


func test_reset_pad_page_resets_only_gamepad_settings() -> void:
	var before := _snapshot()
	Settings.gamepad_sensitivity = 7.5
	Settings.invert_y = true
	Settings.mouse_sensitivity = 0.009  # page "Clavier / Souris" — ne doit PAS être touché

	Settings.reset_pad_page()

	assert_float(Settings.gamepad_sensitivity).is_equal_approx(3.0, 0.001)
	assert_bool(Settings.invert_y).is_false()
	assert_float(Settings.mouse_sensitivity).is_equal_approx(0.009, 0.00001)

	_restore(before)


func test_reset_render_page_resets_only_display_and_audio_settings() -> void:
	var before := _snapshot()
	Settings.window_mode = "fullscreen"
	Settings.render_scale = 0.6
	Settings.vsync_enabled = false
	Settings.fps_limit = 240
	Settings.graphics_preset = "steam_deck"
	Settings.ink_edges = false
	Settings.volume_master = 0.1
	Settings.volume_sfx = 0.1
	Settings.volume_music = 0.1
	Settings.volume_ui = 0.1
	Settings.volume_voice = 0.1
	Settings.volume_ambience = 0.1
	Settings.audio_mono = true
	Settings.show_perf_overlay = true
	Settings.ui_scale = 1.4  # page "Accessibilité" — ne doit PAS être touché

	Settings.reset_render_page()

	assert_str(Settings.window_mode).is_equal("windowed")
	assert_float(Settings.render_scale).is_equal_approx(1.0, 0.001)
	assert_bool(Settings.vsync_enabled).is_true()
	assert_int(Settings.fps_limit).is_equal(0)
	assert_str(Settings.graphics_preset).is_equal(Settings.GRAPHICS_PRESET_DEFAULT)
	assert_bool(Settings.ink_edges).is_true()
	assert_float(Settings.volume_master).is_equal_approx(1.0, 0.001)
	assert_float(Settings.volume_sfx).is_equal_approx(1.0, 0.001)
	assert_float(Settings.volume_music).is_equal_approx(0.7, 0.001)
	assert_float(Settings.volume_ui).is_equal_approx(1.0, 0.001)
	assert_float(Settings.volume_voice).is_equal_approx(1.0, 0.001)
	assert_float(Settings.volume_ambience).is_equal_approx(1.0, 0.001)
	assert_bool(Settings.audio_mono).is_false()
	assert_bool(Settings.show_perf_overlay).is_false()
	assert_float(Settings.ui_scale).is_equal_approx(1.4, 0.001)

	_restore(before)


func test_reset_access_page_resets_only_accessibility_and_comfort_settings() -> void:
	var before := _snapshot()
	Settings.enemy_color = 1
	Settings.ui_scale = 1.3
	Settings.reduced_motion = true
	Settings.camera_shake_enabled = false
	Settings.head_bob_enabled = false
	Settings.head_bob_intensity = 0.2
	Settings.render_scale = 0.6  # page "Affichage & Son" — ne doit PAS être touché

	Settings.reset_access_page()

	assert_int(Settings.enemy_color).is_equal(0)
	assert_float(Settings.ui_scale).is_equal_approx(1.0, 0.001)
	assert_bool(Settings.reduced_motion).is_false()
	assert_bool(Settings.camera_shake_enabled).is_true()
	assert_bool(Settings.head_bob_enabled).is_true()
	assert_float(Settings.head_bob_intensity).is_equal_approx(1.0, 0.001)
	assert_float(Settings.render_scale).is_equal_approx(0.6, 0.001)

	_restore(before)


# ============================================================ AUDIO MONO (UX-06)
# "audio mono = canal gauche = droit (test de bus)" : `pan_pullout` à 0 sur
# `AudioEffectStereoEnhance` downmixe les canaux latéraux en mono (doc Godot
# "AudioEffectStereoEnhance" "pan_pullout" : "A value of 0 will downmix stereo
# to mono") — voir Audio.mono_pan_pullout (pure) et Audio._setup_mono_effect/
# apply_audio_mono (bus Master réel, posé une seule fois par l'autoload "Sfx").

func test_mono_pan_pullout_is_zero_when_enabled_one_when_disabled() -> void:
	assert_float(Audio.mono_pan_pullout(true)).is_equal_approx(0.0, 0.001)
	assert_float(Audio.mono_pan_pullout(false)).is_equal_approx(1.0, 0.001)


func test_audio_mono_downmixes_the_real_master_bus_when_enabled() -> void:
	var sfx := get_tree().root.get_node_or_null("Sfx")
	assert_object(sfx).is_not_null()
	var master_idx := AudioServer.get_bus_index("Master")
	assert_int(master_idx).is_greater_equal(0)

	var effect: AudioEffectStereoEnhance = null
	for i in AudioServer.get_bus_effect_count(master_idx):
		var e := AudioServer.get_bus_effect(master_idx, i)
		if e is AudioEffectStereoEnhance:
			effect = e
			break
	assert_object(effect).is_not_null()

	var original := Settings.audio_mono
	Settings.audio_mono = true
	sfx.apply_audio_mono()
	assert_float(effect.pan_pullout).is_equal_approx(0.0, 0.001)  # gauche = droit

	Settings.audio_mono = false
	sfx.apply_audio_mono()
	assert_float(effect.pan_pullout).is_equal_approx(1.0, 0.001)  # stéréo intacte

	Settings.audio_mono = original
	sfx.apply_audio_mono()


# ============================================================ SENSIBILITÉ ADS EN JEU (UX-06)
# "chaque réglage ... est appliqué sans redémarrage" — `ads_sensitivity_multiplier`
# doit réellement changer la sensibilité de visée pendant l'ADS, pas seulement
# être persisté. Voir PlayerController.effective_look_sensitivity (pure,
# appelée par _look/_gamepad_look).

func test_effective_look_sensitivity_unchanged_when_not_aiming() -> void:
	assert_float(PlayerController.effective_look_sensitivity(0.0025, false, 0.5)).is_equal_approx(0.0025, 0.00001)
	assert_float(PlayerController.effective_look_sensitivity(0.0025, false, 2.0)).is_equal_approx(0.0025, 0.00001)


func test_effective_look_sensitivity_scaled_by_ads_multiplier_when_aiming() -> void:
	assert_float(PlayerController.effective_look_sensitivity(0.0025, true, 0.5)).is_equal_approx(0.00125, 0.000001)
	assert_float(PlayerController.effective_look_sensitivity(4.0, true, 2.0)).is_equal_approx(8.0, 0.001)


func test_effective_look_sensitivity_default_multiplier_is_a_no_op() -> void:
	# Settings.ads_sensitivity_multiplier par défaut (1.0) : visée ou non, la
	# sensibilité reste inchangée — comportement d'avant cette tâche préservé.
	assert_float(PlayerController.effective_look_sensitivity(0.0025, true, Settings.ads_sensitivity_multiplier)).is_equal_approx(0.0025, 0.00001)


# ============================================================ MAINTIEN / BASCULE EN JEU (UX-06)
# "maintien ou bascule (accroupi, ADS, marche)" appliqué EN JEU — voir
# PlayerInput.resolve_hold_or_toggle (pure, appelée par gather_from_devices
# pour crouch_held/aim_held/walk_held). `toggled` est l'état mémorisé par
# l'appelant (PlayerInput._crouch_toggle_active et consorts) d'un appel au
# suivant.

func test_resolve_hold_or_toggle_in_hold_mode_follows_raw_held_state() -> void:
	# Maintien (hold_enabled = true) : comportement actuel inchangé, le
	# résultat suit directement l'état brut de la touche, quel que soit `toggled`.
	assert_bool(PlayerInput.resolve_hold_or_toggle(false, true, true, false)).is_true()
	assert_bool(PlayerInput.resolve_hold_or_toggle(false, false, true, true)).is_false()
	assert_bool(PlayerInput.resolve_hold_or_toggle(true, true, true, true)).is_true()


func test_resolve_hold_or_toggle_in_toggle_mode_activates_on_first_press() -> void:
	# Bascule (hold_enabled = false), état initial inactif : un appui active,
	# même si la touche n'est plus tenue (`held` faux) sur ce mappage —
	# l'action reste active jusqu'au PROCHAIN appui.
	assert_bool(PlayerInput.resolve_hold_or_toggle(true, false, false, false)).is_true()


func test_resolve_hold_or_toggle_in_toggle_mode_deactivates_on_second_press() -> void:
	assert_bool(PlayerInput.resolve_hold_or_toggle(true, false, false, true)).is_false()


func test_resolve_hold_or_toggle_in_toggle_mode_ignores_release_between_presses() -> void:
	# Relâcher la touche entre deux appuis n'a AUCUN effet en bascule : sans
	# nouvel appui (`just_pressed` faux), l'état mémorisé est reconduit tel
	# quel, que la touche soit tenue ou non.
	assert_bool(PlayerInput.resolve_hold_or_toggle(false, false, false, true)).is_true()
	assert_bool(PlayerInput.resolve_hold_or_toggle(false, true, false, false)).is_false()


func test_resolve_hold_or_toggle_full_press_release_press_cycle() -> void:
	# Simule gather_from_devices() appelé frame après frame en bascule :
	# appui (actif) -> relâché maintenu (toujours actif) -> nouvel appui (inactif).
	var toggled := false
	toggled = PlayerInput.resolve_hold_or_toggle(true, true, false, toggled)
	assert_bool(toggled).is_true()  # 1er appui : accroupi/ADS/marche s'active
	toggled = PlayerInput.resolve_hold_or_toggle(false, false, false, toggled)
	assert_bool(toggled).is_true()  # touche relâchée entre-temps : reste actif
	toggled = PlayerInput.resolve_hold_or_toggle(true, true, false, toggled)
	assert_bool(toggled).is_false()  # 2e appui : se désactive


# ============================================================ OVERLAY FPS/RÉSEAU EN JEU (UX-06)
# Relance n°3 : Settings.show_perf_overlay n'était lu qu'au démarrage (nulle
# part en fait — seul F3 bascule manuellement l'affichage) : le réglage était
# mort. `PerfOverlay.apply_show_perf_overlay()` (appelée par `_ready()` ET par
# OptionsMenu à chaque bascule de la case, voir OptionsMenu._build_render)
# rend ce réglage vivant, sans redémarrage. La limite d'images (Settings.
# fps_limit) doit aussi être visible dans le texte de l'overlay.

func test_perf_overlay_apply_show_perf_overlay_reflects_the_setting_live() -> void:
	var perf := get_tree().root.get_node_or_null("Perf")
	assert_object(perf).is_not_null()
	var original := Settings.show_perf_overlay

	Settings.show_perf_overlay = true
	perf.apply_show_perf_overlay()
	assert_bool(perf.visible).is_true()

	Settings.show_perf_overlay = false
	perf.apply_show_perf_overlay()
	assert_bool(perf.visible).is_false()

	Settings.show_perf_overlay = original
	perf.apply_show_perf_overlay()


func test_perf_overlay_displays_the_current_fps_limit() -> void:
	var perf := get_tree().root.get_node_or_null("Perf")
	assert_object(perf).is_not_null()
	var original := Settings.fps_limit

	Settings.fps_limit = 144
	assert_str(perf._format_text(0.016)).contains("144")

	Settings.fps_limit = 0
	assert_str(perf._format_text(0.016).to_lower()).contains("illimit")

	Settings.fps_limit = original


func test_voice_and_ambience_buses_exist_and_follow_their_dedicated_volume() -> void:
	# UX-06 : volumes voix/ambiance dédiés — bus créés par Audio._ensure_bus
	# (default_bus_layout.tres, hors du périmètre de cette tâche, ne les
	# définit pas).
	var sfx := get_tree().root.get_node_or_null("Sfx")
	assert_object(sfx).is_not_null()
	var voice_idx := AudioServer.get_bus_index("Voice")
	var ambience_idx := AudioServer.get_bus_index("Ambience")
	assert_int(voice_idx).is_greater_equal(0)
	assert_int(ambience_idx).is_greater_equal(0)

	var before := _snapshot()
	Settings.volume_voice = 0.5
	Settings.volume_ambience = 0.25
	sfx._apply_volumes()
	assert_float(AudioServer.get_bus_volume_db(voice_idx)).is_equal_approx(linear_to_db(0.5), 0.01)
	assert_float(AudioServer.get_bus_volume_db(ambience_idx)).is_equal_approx(linear_to_db(0.25), 0.01)
	_restore(before)
	sfx._apply_volumes()


# ============================================================ HELPERS

## Capture l'état COMPLET des statics touchés par au moins un test ci-dessus,
## pour restaurer exactement l'état d'avant le test (statics partagés par
## toute la suite headless — même précaution que
## tests/ui/test_settings_migration.gd::test_apply_ui_scale_sets_window_content_scale_factor).
func _snapshot() -> Dictionary:
	return {
		"window_mode": Settings.window_mode,
		"render_scale": Settings.render_scale,
		"vsync_enabled": Settings.vsync_enabled,
		"fps_limit": Settings.fps_limit,
		"graphics_preset": Settings.graphics_preset,
		"ink_edges": Settings.ink_edges,
		"ui_scale": Settings.ui_scale,
		"mouse_sensitivity": Settings.mouse_sensitivity,
		"gamepad_sensitivity": Settings.gamepad_sensitivity,
		"invert_y": Settings.invert_y,
		"fov": Settings.fov,
		"fov_effects_enabled": Settings.fov_effects_enabled,
		"layout": Settings.layout,
		"ads_sensitivity_multiplier": Settings.ads_sensitivity_multiplier,
		"hold_to_aim": Settings.hold_to_aim,
		"hold_to_crouch": Settings.hold_to_crouch,
		"hold_to_walk": Settings.hold_to_walk,
		"camera_shake_enabled": Settings.camera_shake_enabled,
		"head_bob_enabled": Settings.head_bob_enabled,
		"head_bob_intensity": Settings.head_bob_intensity,
		"enemy_color": Settings.enemy_color,
		"reduced_motion": Settings.reduced_motion,
		"volume_master": Settings.volume_master,
		"volume_sfx": Settings.volume_sfx,
		"volume_music": Settings.volume_music,
		"volume_ui": Settings.volume_ui,
		"volume_voice": Settings.volume_voice,
		"volume_ambience": Settings.volume_ambience,
		"audio_mono": Settings.audio_mono,
		"show_perf_overlay": Settings.show_perf_overlay,
	}


## Restaure un instantané pris par `_snapshot`, ré-applique l'état moteur
## (fenêtre/viewport/Engine/bus Master) et sauvegarde — un test suivant qui
## relirait `user://settings.cfg` doit retrouver l'état d'avant ce test.
func _restore(s: Dictionary) -> void:
	Settings.window_mode = s.window_mode
	Settings.render_scale = s.render_scale
	Settings.vsync_enabled = s.vsync_enabled
	Settings.fps_limit = s.fps_limit
	Settings.graphics_preset = s.graphics_preset
	Settings.ink_edges = s.ink_edges
	Settings.ui_scale = s.ui_scale
	Settings.mouse_sensitivity = s.mouse_sensitivity
	Settings.gamepad_sensitivity = s.gamepad_sensitivity
	Settings.invert_y = s.invert_y
	Settings.fov = s.fov
	Settings.fov_effects_enabled = s.fov_effects_enabled
	Settings.layout = s.layout
	Settings.ads_sensitivity_multiplier = s.ads_sensitivity_multiplier
	Settings.hold_to_aim = s.hold_to_aim
	Settings.hold_to_crouch = s.hold_to_crouch
	Settings.hold_to_walk = s.hold_to_walk
	Settings.camera_shake_enabled = s.camera_shake_enabled
	Settings.head_bob_enabled = s.head_bob_enabled
	Settings.head_bob_intensity = s.head_bob_intensity
	Settings.enemy_color = s.enemy_color
	Settings.reduced_motion = s.reduced_motion
	Settings.volume_master = s.volume_master
	Settings.volume_sfx = s.volume_sfx
	Settings.volume_music = s.volume_music
	Settings.volume_ui = s.volume_ui
	Settings.volume_voice = s.volume_voice
	Settings.volume_ambience = s.volume_ambience
	Settings.audio_mono = s.audio_mono
	Settings.show_perf_overlay = s.show_perf_overlay
	Settings.apply_window_mode()
	Settings.apply_render_scale()
	Settings.apply_vsync()
	Settings.apply_fps_limit()
	Settings.apply_ui_scale()
	Settings.save_all()
