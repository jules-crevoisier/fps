## theme_smoke.gd
## Planche de contrôle du thème « Planche » dans Godot (StyleBoxComic + LabelSettings + icônes),
## à comparer aux maquettes HTML. Image : reports/ui/renders/godot_theme_smoke.png
##   "%GODOT%" --screen 1 --resolution 1920x1080 --path . -s res://tools/ui/theme_smoke.gd
extends SceneTree

const OUT := "res://reports/ui/renders/godot_theme_smoke.png"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTokens.BLUE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var col := VBoxContainer.new()
	col.position = Vector2(64, 64)
	col.add_theme_constant_override("separation", 28)
	root.add_child(col)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	col.add_child(row)
	for spec in [[UiTokens.BLUE, "12"], [UiTokens.PAPER, "04:32"], [UiTokens.MAGENTA, "9"]]:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiTokens.plate(spec[0], UiTokens.SKEW_DEG, Vector2(6, 6)))
		var l := UiTokens.make_label(spec[1], UiTokens.display(UiTokens.T_2XL, UiTokens.INK if spec[0] == UiTokens.PAPER else UiTokens.PAPER, 0 if spec[0] == UiTokens.PAPER else 8))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(l)
		row.add_child(p)

	var mode := PanelContainer.new()
	mode.custom_minimum_size = Vector2(640, 0)
	mode.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.YELLOW, UiTokens.SKEW_DEG, Vector2(12, 10)))
	var mv := VBoxContainer.new()
	mv.add_child(UiTokens.make_label("Match à mort par équipe", UiTokens.label(UiTokens.T_M), true))
	mv.add_child(UiTokens.make_label("4 contre 4 · Shipment · 50 éliminations", UiTokens.body(21, UiTokens.INK_SOFT)))
	mode.add_child(mv)
	col.add_child(mode)

	var hp := HBoxContainer.new()
	hp.add_theme_constant_override("separation", 18)
	var portrait := TextureRect.new()
	portrait.texture = UiTokens.icon("portrait_verrou")
	portrait.custom_minimum_size = Vector2(128, 128)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var pp := PanelContainer.new()
	var psb := UiTokens.plate(UiTokens.YELLOW, 0.0, Vector2(6, 6))
	psb.pad = Vector2.ZERO
	pp.add_theme_stylebox_override("panel", psb)
	pp.add_child(portrait)
	hp.add_child(pp)
	hp.add_child(UiTokens.make_label("72", UiTokens.display(UiTokens.T_3XL)))
	col.add_child(hp)

	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 20)
	for n in ["revolver_sil", "ravage_sil", "frag_sticker", "flash_sticker", "smoke_sticker", "health", "kill", "settings"]:
		var t := TextureRect.new()
		t.texture = UiTokens.icon(n)
		t.custom_minimum_size = Vector2(0, 72)
		t.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icons.add_child(t)
	col.add_child(icons)

	var go := Button.new()
	go.text = "JOUER !"
	go.add_theme_font_override("font", UiTokens.FONT_DISPLAY)
	go.add_theme_font_size_override("font_size", UiTokens.T_3XL)
	go.add_theme_color_override("font_color", UiTokens.INK)
	var gsb := UiTokens.plate(UiTokens.YELLOW, UiTokens.SKEW_DEG, Vector2(12, 12))
	gsb.pad = Vector2(64, 6)
	gsb.slant_ref_height = 120.0
	go.add_theme_stylebox_override("normal", gsb)
	go.position = Vector2(1380, 880)
	root.add_child(go)

	get_root().add_child(root)
	_save.call_deferred()


func _save() -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("THEME_SMOKE_OK")
	quit()
