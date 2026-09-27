## menu_capture.gd
## Vérification visuelle du salon (tâche "lobby / menus", 2026-09-27) — charge
## scenes/ui/main_menu.tscn et capture chaque écran à 1920×1080 (+ une capture
## de l'accueil à 1280×800), pour comparaison avec reports/ui/renders/*.png.
##   "%GODOT%" --screen 1 --resolution 1920x1080 --path . -s res://tools/ui/menu_capture.gd
## Images : reports/checkpoints/2026-09-27_ui/menu_*.png
extends SceneTree

const OUT_DIR := "res://reports/checkpoints/2026-09-27_ui"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_run.call_deferred()


func _wait(frames: int = 8) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw


## `-- --size=WxH` : tous les écrans à cette taille (contrôle d'adaptation 16:10, ultra-large…),
## fichiers préfixés « WxH_ » pour ne pas écraser les captures de référence en 1920×1080.
var _base_size := Vector2i(1920, 1080)
var _prefix := ""


func _save(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join(_prefix + file_name)))
	print("MENU_CAPTURE_OK ", file_name)


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var wh := arg.trim_prefix("--size=").split("x")
			_base_size = Vector2i(int(wh[0]), int(wh[1]))
			_prefix = "%dx%d_" % [_base_size.x, _base_size.y]
	get_root().size = _base_size
	Settings.load_all()
	MatchConfig.load_last()

	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	get_root().add_child(menu)
	await _wait(15)
	await _save("menu_home.png")

	get_root().size = Vector2i(1280, 800)
	await _wait(8)
	await _save("menu_home_1280x800.png")
	get_root().size = _base_size
	await _wait(8)

	var home := menu._screens["accueil"] as HomeScreen
	home._show_join_panel()
	# Le pop-in (UiTokens.POP_S = 0.18 s, Tween) met plus de 20 frames à finir
	# sous --screen 1 + WINDOW_FLAG_NO_FOCUS (fenêtre jamais active : Windows
	# ralentit visiblement la cadence réelle de traitement) — large marge ici,
	# capture seulement (le comportement réel en jeu, fenêtre active, n'a pas
	# ce problème).
	await _wait(90)
	await _save("menu_home_join.png")
	home._hide_join_panel()
	await _wait(2)

	menu._show_tab("persos")
	await _wait(12)
	await _save("menu_heroes.png")

	menu._show_tab("armurerie")
	await _wait(8)
	var armory := menu._screens["armurerie"] as ArmoryScreen
	armory._select_slot(2)  # Revolver
	await _wait(8)
	await _save("menu_armory_revolver.png")

	menu._show_tab("parametres")
	await _wait(12)
	await _save("menu_settings_mouse.png")
	var settings_panel := (menu._screens["parametres"] as Control).get_child(1) as SettingsPanel
	settings_panel._show_tab("keys")
	await _wait(8)
	await _save("menu_settings_keys.png")
	settings_panel._show_tab("video")
	await _wait(8)
	await _save("menu_settings_video.png")
	settings_panel._show_tab("crosshair")
	await _wait(8)
	await _save("menu_settings_crosshair.png")

	menu.queue_free()
	await _wait(4)

	# Menu pause par-dessus une VRAIE partie locale (bots) — repli silencieux sur
	# un simple voile si l'hébergement échoue (n'invalide pas le reste des
	# captures, déjà sauvegardées).
	var err := await MatchLauncher.start_local(self, "tdm", 4, true, MatchConfig.Difficulty.VETERAN, "shipment")
	if err == OK:
		await _wait(40)
	var pause := PauseMenu.new()
	get_root().add_child(pause)
	pause.open()
	await _wait(8)
	await _save("menu_pause.png")

	print("MENU_CAPTURE_DONE")
	quit()
