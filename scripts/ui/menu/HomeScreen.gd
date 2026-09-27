## HomeScreen.gd
## Écran ACCUEIL du salon (reports/ui/mockups/home.html, rendu reports/ui/renders/home.png).
## Fond dégradé bleu + trame de points + rayons de soleil derrière le héros
## (MenuWidgets.sunburst_background), héros 3D VIVANT (SubViewport, repli sur
## assets/ui/renders/frog_aim.png si la scène/l'arme/l'os manquent — jamais un
## écran vide), bulle de BD, cartes de mode (MatchModeCatalog), groupe (1 vrai
## + 3 emplacements « Bientôt »), bouton « Compléter avec des bots » et gros
## bouton JAUNE « JOUER ! » -> MatchLauncher.
class_name HomeScreen
extends Control

const _HERO_BOX_POS := Vector2(820, 120)
const _HERO_BOX_SIZE := Vector2(700, 1000)
const _FALLBACK_HERO_IMG := "res://assets/ui/renders/frog_aim.png"
const _FROG_SCENE := "res://scenes/characters/frog_cowboy.tscn"
const _REVOLVER_SCENE := "res://assets/models/weapons/revolver.glb"

var _selected_preset_id: String = MatchModeCatalog.TDM
var _mode_cards: Dictionary = {}
var _bots_switch: Button
var _join_panel: Control
var _join_backdrop: ColorRect
var _ip_edit: LineEdit
var _join_status: Label
var _join_button: Button
var _host_button: Button
var _play_button: Button
var _net: NetworkManager


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()


func _build() -> void:
	add_child(MenuWidgets.sunburst_background(
		Color("3C9BFF"), Color("2E8BFF"), Color("1D5FD6"),
		true, Vector2(1230, 510), 590.0))
	_build_hero()
	_build_bubble()
	_build_modes()
	_build_party()
	_build_go_panel()
	_build_join_panel()
	_sync_bots_switch()


# ------------------------------------------------------------ héros 3D (ou repli image)

func _build_hero() -> void:
	if _try_build_live_hero():
		return
	var img := TextureRect.new()
	if ResourceLoader.exists(_FALLBACK_HERO_IMG):
		img.texture = load(_FALLBACK_HERO_IMG)
	img.position = _HERO_BOX_POS
	img.size = _HERO_BOX_SIZE
	img.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(img)


## SubViewport avec Verrou animé (clip "Pistol_Aim_Neutral" en boucle), revolver
## attaché à l'os "PistolGrip" (ThirdPersonWeapon.counter_scale_for pour la
## contre-échelle), même recette que tools/ui/render_ui_assets.gd. Faux si la
## scène, l'arme ou l'os attendu manquent — jamais une erreur, l'appelant
## retombe alors sur l'image statique.
##
## IMPORTANT (bug trouvé à la capture 2026-09-27) : `Node3D.global_transform`
## renvoie l'identité et logue une erreur tant que le nœud n'est pas
## `is_inside_tree()` — contrairement à render_ui_assets.gd, où tout se
## construit sous un nœud (Driver) déjà en arbre. On ajoute donc `container`
## à CET écran (`add_child`) AVANT de lire un seul `global_transform` (contre-
## échelle de l'arme, cadrage caméra depuis les AABB) — jamais après.
func _try_build_live_hero() -> bool:
	if not ResourceLoader.exists(_FROG_SCENE) or not ResourceLoader.exists(_REVOLVER_SCENE):
		return false
	var packed := load(_FROG_SCENE) as PackedScene
	var model := packed.instantiate() if packed else null
	if model == null or not (model is Node3D):
		return false
	ToonStyle.apply_to(model)

	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		model.queue_free()
		return false
	var skel := skeletons[0] as Skeleton3D
	if skel.find_bone("PistolGrip") < 0:
		model.queue_free()
		return false
	var att := BoneAttachment3D.new()
	att.bone_name = "PistolGrip"
	skel.add_child(att)
	var gun_packed := load(_REVOLVER_SCENE) as PackedScene
	var gun := gun_packed.instantiate() as Node3D
	att.add_child(gun)
	ToonStyle.apply_to(gun)

	# lancé une fois DANS l'arbre (hors arbre, le clip ne s'appliquait pas : pose neutre)
	model.tree_entered.connect(func() -> void: _play_looping_clip.call_deferred(model, "Pistol_Aim_Neutral"), CONNECT_ONE_SHOT)

	var holder := Node3D.new()
	holder.add_child(model)

	var sub := SubViewport.new()
	sub.size = Vector2i(_HERO_BOX_SIZE)
	sub.transparent_bg = true
	sub.add_child(holder)

	var env := ToonStyle.environment()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.fog_enabled = false
	env.glow_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	sub.add_child(we)

	var sun := DirectionalLight3D.new()
	sub.add_child(sun)
	ToonStyle.apply_sun(sun)

	var cam := Camera3D.new()
	sub.add_child(cam)
	cam.current = true

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = _HERO_BOX_SIZE
	container.size = _HERO_BOX_SIZE
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.position = _HERO_BOX_POS
	container.add_child(sub)
	add_child(container)  # entre en arbre ICI — global_transform devient valable en dessous.

	gun.scale = ThirdPersonWeapon.counter_scale_for(att.global_transform.basis.get_scale())
	ToonStyle.add_outline_pass(cam)
	_frame_camera(cam, _bounds_of(model))
	return true


func _play_looping_clip(model: Node3D, clip_suffix: String) -> void:
	# Le modèle porte DEUX AnimationPlayer (Verrou + le revolver attaché, clips Rev_*) : on prend
	# celui qui possède vraiment le clip, jamais simplement le premier trouvé.
	for node in model.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for a in player.get_animation_list():
			if a.ends_with(clip_suffix):
				var anim := player.get_animation(a)
				if anim:
					anim.loop_mode = Animation.LOOP_LINEAR
				player.play(a)
				player.seek(0.0, true)   # applique la pose tout de suite
				return


func _frame_camera(cam: Camera3D, box: AABB) -> void:
	var center := box.get_center()
	cam.fov = 28.0
	var dist: float = 1.4 if box.size.y <= 0.0 else box.size.y * 0.56 / tan(deg_to_rad(cam.fov * 0.5))
	cam.look_at_from_position(center + Vector3(0.42, 0.12, 1.0).normalized() * dist, center, Vector3.UP)


func _bounds_of(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for vi in n.find_children("*", "VisualInstance3D", true, false):
		var v := vi as VisualInstance3D
		if v is Light3D or not v.visible:
			continue
		var b := v.global_transform * v.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


# ------------------------------------------------------------ bulle de BD

func _build_bubble() -> void:
	var bubble := PanelContainer.new()
	bubble.position = Vector2(1420, 150)
	bubble.custom_minimum_size = Vector2(360, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.border_color = UiTokens.INK
	sb.set_border_width_all(int(UiTokens.STROKE))
	sb.set_corner_radius_all(56)
	sb.shadow_color = UiTokens.INK
	sb.shadow_size = 0
	bubble.add_theme_stylebox_override("panel", sb)
	var l := UiTokens.make_label("On règle ça\nà midi ?", UiTokens.display(UiTokens.T_L, UiTokens.INK, 0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	bubble.add_child(l)
	add_child(bubble)


# ------------------------------------------------------------ « Choisis ton match »

## PAS un Container : un VBoxContainer réécrirait `position.x` de chaque carte
## à chaque passe de tri (résolution différente, ajout/retrait…), effaçant le
## décalage jaune posé par `_refresh_mode_cards` — positions ABSOLUES, comme le
## reste de l'écran (mêmes valeurs px que home.html).
func _build_modes() -> void:
	var root := Control.new()
	root.position = Vector2(64, 178)
	root.custom_minimum_size = Vector2(640, 0)
	root.mouse_filter = Control.MOUSE_FILTER_PASS

	var title := UiTokens.make_label("Choisis ton match", UiTokens.display(UiTokens.T_XL, UiTokens.PAPER, 6))
	root.add_child(title)

	var y := 70.0
	const ROW_H := 92.0
	const GAP := 18.0
	for preset in MatchModeCatalog.PRESETS:
		var card := _build_mode_card(preset)
		card.position = Vector2(0, y)
		root.add_child(card)
		y += ROW_H + GAP
	add_child(root)
	_refresh_mode_cards()


func _build_mode_card(preset: Dictionary) -> Control:
	var btn := Button.new()
	btn.size = Vector2(640, 92)
	btn.custom_minimum_size = Vector2(640, 92)
	btn.focus_mode = Control.FOCUS_ALL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	MenuWidgets.apply_plate_states(btn, UiTokens.PAPER)
	btn.tooltip_text = ""

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", UiTokens.S3)
	row.offset_left = UiTokens.S3
	row.offset_top = UiTokens.S1

	var num := UiTokens.make_label(preset["num"], UiTokens.display(UiTokens.T_2XL, UiTokens.BLUE_DEEP, 4))
	num.custom_minimum_size = Vector2(64, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.set_meta("is_num", true)
	row.add_child(num)

	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 2)
	texts.add_child(UiTokens.make_label(preset["name"], UiTokens.label(UiTokens.T_M), true))
	texts.add_child(UiTokens.make_label(preset["sub"], UiTokens.body(21, UiTokens.INK_SOFT)))
	row.add_child(texts)

	btn.add_child(row)
	btn.pressed.connect(_on_mode_selected.bind(preset["id"]))
	_mode_cards[preset["id"]] = {"button": btn, "num_label": num}
	return btn


func _on_mode_selected(preset_id: String) -> void:
	_selected_preset_id = preset_id
	if MatchModeCatalog.is_join_host(preset_id):
		_show_join_panel()
	else:
		_hide_join_panel()
		var params := MatchModeCatalog.params_for(preset_id)
		MatchLauncher.configure_local(params["mode_id"], params["team_size"], MatchConfig.bots_enabled, params["bot_difficulty"])
	_refresh_mode_cards()


func _refresh_mode_cards() -> void:
	for id in _mode_cards:
		var entry: Dictionary = _mode_cards[id]
		var btn: Button = entry["button"]
		var selected: bool = id == _selected_preset_id
		MenuWidgets.apply_plate_states(btn, UiTokens.YELLOW if selected else UiTokens.PAPER)
		if selected:
			var sb := btn.get_theme_stylebox("normal") as StyleBoxComic
			sb.drop = Vector2(12, 10)
		btn.position.x = 18.0 if selected else 0.0
		var num: Label = entry["num_label"]
		num.label_settings.font_color = UiTokens.RED if selected else UiTokens.BLUE_DEEP


# ------------------------------------------------------------ groupe (party)

func _build_party() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	col.position = Vector2(64, -56 - 104 - 40)
	col.add_theme_constant_override("separation", UiTokens.S2)
	col.add_child(UiTokens.make_label("Ton groupe", UiTokens.label(UiTokens.T_S, UiTokens.PAPER)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_build_party_slot(true))
	for i in 3:
		row.add_child(_build_party_slot(false))
	col.add_child(row)
	add_child(col)


func _build_party_slot(is_me: bool) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(104, 104)
	if is_me:
		p.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.YELLOW, 0.0, Vector2(6, 6)))
		var portrait := TextureRect.new()
		portrait.texture = UiTokens.icon("portrait_verrou")
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		p.add_child(portrait)
	else:
		var sb := UiTokens.plate(Color(UiTokens.PAPER.r, UiTokens.PAPER.g, UiTokens.PAPER.b, 0.35), 0.0, Vector2(4, 4))
		p.add_theme_stylebox_override("panel", sb)
		p.tooltip_text = "Bientôt"
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		var plus := UiTokens.make_label("+", UiTokens.display(UiTokens.T_2XL, UiTokens.INK_SOFT, 0))
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(plus)
	return p


# ------------------------------------------------------------ « Compléter avec des bots » + JOUER !

func _build_go_panel() -> void:
	var col := VBoxContainer.new()
	# ancré en bas-droite et grandit vers le HAUT/la GAUCHE (sinon « JOUER ! » sortait de l'écran)
	col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	col.offset_right = -72.0
	col.offset_bottom = -64.0
	col.offset_left = -72.0 - 520.0
	col.offset_top = -64.0
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", UiTokens.S3)
	col.alignment = BoxContainer.ALIGNMENT_END

	var bots_row := HBoxContainer.new()
	bots_row.alignment = BoxContainer.ALIGNMENT_END
	bots_row.add_theme_constant_override("separation", UiTokens.S2)
	bots_row.add_child(UiTokens.make_label("Compléter avec des bots", UiTokens.label(UiTokens.T_S, UiTokens.PAPER)))
	_bots_switch = MenuWidgets.switch_control(true)
	_bots_switch.toggled.connect(func(pressed: bool) -> void: MatchConfig.bots_enabled = pressed)
	bots_row.add_child(_bots_switch)
	col.add_child(bots_row)

	_play_button = MenuWidgets.comic_button("Jouer !", UiTokens.YELLOW, UiTokens.T_3XL)
	_play_button.add_theme_font_override("font", UiTokens.FONT_DISPLAY)
	_play_button.custom_minimum_size = Vector2(0, 110)
	_play_button.set_meta("sfx_click", "ui_confirm")  # tâche "son" : la grosse action -> ui_confirm, pas le clic générique.
	_play_button.pressed.connect(_on_play_pressed)
	col.add_child(_play_button)
	add_child(col)


func _sync_bots_switch() -> void:
	if _bots_switch:
		_bots_switch.button_pressed = MatchConfig.bots_enabled


func _on_play_pressed() -> void:
	if MatchModeCatalog.is_join_host(_selected_preset_id):
		_show_join_panel()
		return
	var params := MatchModeCatalog.params_for(_selected_preset_id)
	if params.is_empty():
		return
	await MatchLauncher.start_local(get_tree(), params["mode_id"], params["team_size"], MatchConfig.bots_enabled, params["bot_difficulty"])


# ------------------------------------------------------------ panneau « Rejoindre / héberger »

func _build_join_panel() -> void:
	_join_backdrop = ColorRect.new()
	_join_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_join_backdrop.color = Color(UiTokens.INK.r, UiTokens.INK.g, UiTokens.INK.b, 0.55)
	_join_backdrop.visible = false
	_join_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_join_backdrop)

	_join_panel = PanelContainer.new()
	_join_panel.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.PAPER, 0.0, Vector2(12, 12), UiTokens.STROKE, Vector2(UiTokens.S4, UiTokens.S3)))
	# PAS de set_anchors_preset(CENTER) : avec des ancres à 0.5, `position`
	# devient un DÉCALAGE depuis le centre (960,540), pas un coin haut-gauche
	# absolu — bug trouvé à la capture 2026-09-27 (le panneau apparaissait en
	# bas à droite). Ancres par défaut (haut-gauche), comme partout ailleurs
	# dans cet écran : `position` reste directement le coin haut-gauche voulu.
	_join_panel.position = Vector2(960 - 260, 540 - 190)
	_join_panel.custom_minimum_size = Vector2(520, 380)
	_join_panel.visible = false

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.S3)
	col.add_child(UiTokens.make_label("Rejoindre / héberger", UiTokens.display(UiTokens.T_L, UiTokens.INK, 0)))
	col.add_child(UiTokens.make_label("Partie privée entre amis", UiTokens.body(UiTokens.T_S, UiTokens.INK_SOFT)))

	_ip_edit = LineEdit.new()
	_ip_edit.text = NetAddress.DEFAULT_IP
	_ip_edit.custom_minimum_size = Vector2(0, 56)
	_ip_edit.add_theme_font_override("font", UiTokens.FONT_BODY)
	_ip_edit.add_theme_font_size_override("font_size", UiTokens.T_M)
	_ip_edit.text_changed.connect(func(_t: String) -> void: _update_join_buttons())
	col.add_child(_ip_edit)

	_join_status = UiTokens.make_label("", UiTokens.body(UiTokens.T_XS, UiTokens.RED))
	col.add_child(_join_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.S2)
	_join_button = MenuWidgets.comic_button("Rejoindre", UiTokens.YELLOW)
	_join_button.pressed.connect(_on_join_pressed)
	_host_button = MenuWidgets.comic_button("Héberger", UiTokens.PAPER)
	_host_button.pressed.connect(_on_host_pressed)
	row.add_child(_join_button)
	row.add_child(_host_button)
	col.add_child(row)

	var close_btn := MenuWidgets.comic_button("Fermer", UiTokens.PAPER, UiTokens.T_S)
	close_btn.pressed.connect(_hide_join_panel)
	col.add_child(close_btn)

	_join_panel.add_child(col)
	add_child(_join_panel)


func _show_join_panel() -> void:
	_join_backdrop.visible = true
	_join_panel.visible = true
	_join_status.text = ""
	_update_join_buttons()
	MenuWidgets.pop_in(_join_panel)
	_ip_edit.grab_focus()


func _hide_join_panel() -> void:
	_join_backdrop.visible = false
	_join_panel.visible = false


func _update_join_buttons() -> void:
	var valid := NetAddress.is_valid_ip(_ip_edit.text)
	_join_button.disabled = not valid


func _on_join_pressed() -> void:
	if not NetAddress.is_valid_ip(_ip_edit.text):
		return
	_net = NetworkManager.get_net(get_tree())
	if not _net.connection_failed.is_connected(_on_join_failed):
		_net.connection_failed.connect(_on_join_failed)
	_join_status.text = "Connexion…"
	_join_status.label_settings.font_color = UiTokens.INK_SOFT
	var err := await MatchLauncher.join(get_tree(), _ip_edit.text.strip_edges())
	if err != OK:
		_on_join_failed()


func _on_join_failed() -> void:
	_join_status.text = "Connexion impossible."
	_join_status.label_settings.font_color = UiTokens.RED
	var sfx := get_node_or_null("/root/Sfx")  # tâche "son" : erreur de connexion -> ui_error.
	if sfx and sfx.has_method("play_ui"):
		sfx.call("play_ui", "ui_error")


func _on_host_pressed() -> void:
	await MatchLauncher.host_lan(get_tree())


# ------------------------------------------------------------ interface pour MainMenu (Esc)

func has_open_subpanel() -> bool:
	return _join_panel != null and _join_panel.visible


func close_subpanel() -> void:
	_hide_join_panel()
