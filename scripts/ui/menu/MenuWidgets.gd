## MenuWidgets.gd
## Fabriques de contrôles partagées par les écrans du salon (MainMenu/Home/
## Heroes/Armory/Settings/Pause) — jamais une nouvelle couleur/taille/police :
## tout vient de UiTokens (verrouillé, ne pas modifier). Centralise les 5 états
## obligatoires d'un bouton BD (normal/hover/pressed/focus/disabled) pour ne
## pas les oublier écran par écran.
class_name MenuWidgets
extends RefCounted

## Bouton plaque BD complet (normal/hover/pressed/focus/disabled + police
## label). `fill` = couleur de la plaque au repos (PAPER pour un bouton
## secondaire, YELLOW pour l'action principale).
static func comic_button(text: String, fill: Color = UiTokens.PAPER, font_size: int = UiTokens.T_M,
		text_color: Color = UiTokens.INK, skew_deg: float = UiTokens.SKEW_DEG) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.add_theme_font_override("font", UiTokens.FONT_LABEL)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color)
	b.add_theme_color_override("font_pressed_color", text_color)
	b.add_theme_color_override("font_focus_color", text_color)
	b.add_theme_color_override("font_disabled_color", UiTokens.INK_SOFT)
	b.focus_mode = Control.FOCUS_ALL
	apply_plate_states(b, fill, skew_deg)
	return b

## Pose les 5 StyleBoxComic (normal/hover/pressed/focus/disabled) d'un
## Button/PanelContainer existant — factorisé pour que `comic_button` ET un
## bouton déjà construit ailleurs (carte de mode, rangée d'arme…) partagent
## exactement la même règle d'état.
static func apply_plate_states(c: Control, fill: Color, skew_deg: float = UiTokens.SKEW_DEG) -> void:
	c.add_theme_stylebox_override("normal", UiTokens.plate(fill, skew_deg, UiTokens.DROP))
	c.add_theme_stylebox_override("hover", UiTokens.plate(fill.lightened(0.12), skew_deg, UiTokens.DROP))
	c.add_theme_stylebox_override("pressed", UiTokens.plate(fill.darkened(0.08), skew_deg, UiTokens.DROP_SMALL))
	var focus := UiTokens.plate(fill, skew_deg, UiTokens.DROP)
	focus.stroke_color = UiTokens.YELLOW
	focus.stroke_width = UiTokens.STROKE * 1.5
	c.add_theme_stylebox_override("focus", focus)
	var dis := UiTokens.plate(fill.darkened(0.35), skew_deg, UiTokens.DROP_SMALL)
	c.add_theme_stylebox_override("disabled", dis)

## Onglet skewé (topbar / colonne Paramètres) — sélectionné = jaune, décalé.
static func tab_button(text: String, selected: bool, font_size: int = UiTokens.T_M) -> Button:
	var b := comic_button(text, UiTokens.YELLOW if selected else UiTokens.PAPER, font_size)
	if selected:
		var sb := b.get_theme_stylebox("normal") as StyleBoxComic
		sb.drop = Vector2(6, 6)
	return b

## Carte/rangée sélectionnable (mode d'accueil, rôle d'armurerie…) : jaune +
## décalage horizontal quand `selected`, comme home.html `.mode.on`.
static func selected_offset(selected: bool) -> Vector2:
	return Vector2(18, 0) if selected else Vector2.ZERO

## Étiquette de touche façon maquette (".key") : petit rectangle papier avec
## contour, pour "Échap", "Clic G"…
static func key_chip(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTokens.plate(UiTokens.PAPER, 0.0, UiTokens.DROP_SMALL, UiTokens.STROKE * 0.75, Vector2(UiTokens.S1, 2))
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(UiTokens.make_label(text, UiTokens.label(UiTokens.T_XS, UiTokens.INK)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## Interrupteur BD (".sw") — case à cocher stylée en switch skewé.
static func switch_control(pressed: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = pressed
	b.custom_minimum_size = Vector2(86, 40)
	b.focus_mode = Control.FOCUS_ALL
	_style_switch(b)
	return b

static func _style_switch(b: Button) -> void:
	var off := UiTokens.plate(UiTokens.PAPER_2, 0.0, Vector2(3, 3), UiTokens.STROKE * 0.75, Vector2.ZERO)
	var on := UiTokens.plate(UiTokens.YELLOW, 0.0, Vector2(3, 3), UiTokens.STROKE * 0.75, Vector2.ZERO)
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", off)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	var focus := UiTokens.plate(UiTokens.PAPER_2, 0.0, Vector2(3, 3), UiTokens.STROKE * 1.5, Vector2.ZERO)
	focus.stroke_color = UiTokens.YELLOW
	b.add_theme_stylebox_override("focus", focus)
	var dis := UiTokens.plate(UiTokens.PAPER_2.darkened(0.2), 0.0, Vector2(3, 3), UiTokens.STROKE * 0.75, Vector2.ZERO)
	b.add_theme_stylebox_override("disabled", dis)

static var _grabber_tex: ImageTexture

## Curseur BD (HSlider re-thémé : piste PAPER_2, remplissage BLUE, poignée
## jaune à liseré d'encre) — settings.html ".slider"/".slider b". Pas de skew
## réel sur le Control (Control n'a pas de cisaillement, contrairement à
## Node2D — voir StyleBoxComic, doc de tête) : seules les PLAQUES penchent
## dans toute cette direction, jamais le contenu, curseurs compris.
static func styled_slider(min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0, 40)
	s.focus_mode = Control.FOCUS_ALL
	var track := StyleBoxFlat.new()
	track.bg_color = UiTokens.PAPER_2
	track.set_border_width_all(3)
	track.border_color = UiTokens.INK
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTokens.BLUE
	fill.set_border_width_all(3)
	fill.border_color = UiTokens.INK
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var grabber := _grabber_texture()
	s.add_theme_icon_override("grabber", grabber)
	s.add_theme_icon_override("grabber_highlight", grabber)
	s.add_theme_icon_override("grabber_disabled", grabber)
	return s

static func _grabber_texture() -> ImageTexture:
	if _grabber_tex != null:
		return _grabber_tex
	var img := Image.create(26, 40, false, Image.FORMAT_RGBA8)
	img.fill(UiTokens.YELLOW)
	for x in 26:
		for y in 40:
			if x < 3 or x >= 23 or y < 3 or y >= 37:
				img.set_pixel(x, y, UiTokens.INK)
	_grabber_tex = ImageTexture.create_from_image(img)
	return _grabber_tex

## Groupe segmenté (settings.html ".seg") — boutons accolés, celui sélectionné
## en jaune. `on_select` reçoit l'id choisi.
static func segmented(options: Array, labels: Array, selected: String, on_select: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", -3)
	for i in options.size():
		var id = options[i]
		var b := comic_button(str(labels[i]), UiTokens.YELLOW if id == selected else UiTokens.PAPER, UiTokens.T_S, UiTokens.INK, 0.0)
		b.pressed.connect(on_select.bind(id))
		row.add_child(b)
	return row

## Glissement d'entrée façon HUD (UiTokens.SLIDE_S) — anime `node.position.x`
## depuis `from_x` vers sa position actuelle. Coupé si Settings.reduced_motion
## (Comic.reduced_motion() n'est pas repris ici : ce module reste dans le
## périmètre UiTokens, qui expose déjà Settings via aucune dépendance — on lit
## Settings directement, même source que Comic.reduced_motion()).
static func slide_in(node: Control, from_x: float) -> void:
	if Settings.reduced_motion:
		return
	var target := node.position.x
	node.position.x = from_x
	var tw := node.create_tween()
	tw.tween_property(node, "position:x", target, UiTokens.SLIDE_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

const _SUNBURST_SHADER := preload("res://assets/shaders/ui/sunburst.gdshader")

## Fond plein écran (dégradé + trame de points, rayons optionnels) — voir
## assets/shaders/ui/sunburst.gdshader. `burst_center_px`/`burst_radius_px`
## sont en pixels ÉCRAN (pas des UV) : le shader convertit lui-même via
## `rect_size_px`, tenu à jour ici sur un `resized` pour rester correct si le
## Control change de taille (fenêtre redimensionnée, aperçus à résolutions
## différentes — la capture 1280×800 du lead, par ex.).
static func sunburst_background(top: Color, mid: Color, bottom: Color,
		burst_enabled: bool = false, burst_center_px: Vector2 = Vector2(960, 540), burst_radius_px: float = 590.0,
		burst_color_a: Color = UiTokens.YELLOW, burst_color_b: Color = Color("FFB21F")) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _SUNBURST_SHADER
	mat.set_shader_parameter("grad_top", top)
	mat.set_shader_parameter("grad_mid", mid)
	mat.set_shader_parameter("grad_bottom", bottom)
	mat.set_shader_parameter("burst_enabled", burst_enabled)
	mat.set_shader_parameter("burst_radius_px", burst_radius_px)
	mat.set_shader_parameter("burst_color_a", burst_color_a)
	mat.set_shader_parameter("burst_color_b", burst_color_b)
	rect.material = mat
	var update_size := func() -> void:
		mat.set_shader_parameter("rect_size_px", rect.size)
		mat.set_shader_parameter("burst_center", Vector2(burst_center_px.x / maxf(rect.size.x, 1.0), burst_center_px.y / maxf(rect.size.y, 1.0)))
	rect.resized.connect(update_size)
	rect.ready.connect(update_size)
	return rect

## Apparition "pop" (UiTokens.POP_S) — utilisée pour un panneau qui s'ouvre
## (panneau IP, confirmation de sortie…).
static func pop_in(node: Control) -> void:
	if Settings.reduced_motion:
		node.scale = Vector2.ONE
		node.modulate.a = 1.0
		return
	node.scale = Vector2(1.08, 1.08)
	node.modulate.a = 0.0
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "scale", Vector2.ONE, UiTokens.POP_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, UiTokens.POP_S)
