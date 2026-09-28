## ArmoryScreen.gd
## Écran ARMURERIE du salon (reports/ui/mockups/armory.html, rendu
## reports/ui/renders/armory.png) — RECONVERTI en sélecteur d'arme PRIMAIRE
## (contrat lead 2026-09-28, "LOADOUT SELECTION" point 3) : le loadout n'est
## plus fixe (Ravage+Revolver imposés) depuis la tâche "quatre armes" — cinq
## primaires sélectionnables (Loadout.PRIMARY_NAMES : Ravage/Rafale/Fracas/
## Verdict/Aiguille), le Revolver restant la SECONDE arme fixe (jamais un
## slot sélectionnable, voir `_build_secondary_chip`). Une carte BD par
## primaire (icône, nom, rôle — Loadout.role_for), 4 jauges de VRAIES stats
## (ArmoryFormat, jamais un nombre recopié à la main), carte sélectionnée en
## JAUNE. Choisir une carte persiste IMMÉDIATEMENT (Settings.selected_primary,
## contrat point 2 : "persists across sessions") — cet écran vit dans le
## SALON (scenes/ui/main_menu.tscn, jamais pendant un match, voir
## MainMenu.gd/PauseMenu.gd) : aucune synchronisation réseau n'est nécessaire
## ICI (contrairement à DeathScreen.gd, qui change le choix EN PARTIE et
## avertit le serveur — voir sa doc).
class_name ArmoryScreen
extends Control

## Une carte = {"name":String, "cfg":WeaponConfig (peut être null si le .tres
## d'A n'est pas encore livré — voir `_refresh_stats`/`_refresh_stage`,
## jamais un crash), "role":String, "icon":String (radical `_sticker`)}.
## Rempli dans l'ordre VERROUILLÉ de `Loadout.PRIMARY_NAMES` — la carte n
## correspond donc toujours au numéro n (1..5) affiché.
var _cards: Array[Dictionary] = []
var _selected_number: int = 1

var _stage_title: Label
var _stage_sub: Label
var _stage_onoma: Label
var _stage_render: TextureRect
var _stats_root: VBoxContainer
var _hints_root: VBoxContainer
var _current_skin_icon: TextureRect

const _CARD_W := 520.0
const _CARD_H := 130.0
const _CARD_GAP := 16.0
const _CARD_LIST_ORIGIN := Vector2(64, 170)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_card_catalog()
	_build()


func _build_card_catalog() -> void:
	_cards = []
	for wname in Loadout.PRIMARY_NAMES:
		_cards.append({
			"name": wname,
			"cfg": WeaponDatabase.get_by_name(wname),
			"role": Loadout.role_for(wname),
			"icon": WeaponIcon.sticker(wname),
		})


func _build() -> void:
	add_child(MenuWidgets.sunburst_background(Color("3C9BFF"), Color("2E8BFF"), Color("1D5FD6")))
	_build_card_list()
	_build_secondary_chip()
	_build_stage()
	_build_skins_row()
	_build_stats_panel()
	_build_hints_panel()
	_select_slot(_initial_selected_number())


## Numéro (1..5) de la primaire déjà persistée (Settings.selected_primary,
## contrat point 2) — 1 (Ravage) si elle est absente/invalide (première
## visite, ou un nom retiré du roster).
func _initial_selected_number() -> int:
	var idx := Loadout.PRIMARY_NAMES.find(Settings.selected_primary)
	return idx + 1 if idx != -1 else 1


# ------------------------------------------------------------ liste 1-5 (cartes primaires)

func _build_card_list() -> void:
	var root := Control.new()
	root.position = _CARD_LIST_ORIGIN
	add_child(root)

	for i in _cards.size():
		var entry := _cards[i]
		var row := _build_card(entry, i + 1)
		row.position = Vector2(0, i * (_CARD_H + _CARD_GAP))
		root.add_child(row)
		entry["row"] = row


func _build_card(entry: Dictionary, number: int) -> Button:
	var btn := Button.new()
	btn.size = Vector2(_CARD_W, _CARD_H)
	btn.custom_minimum_size = Vector2(_CARD_W, _CARD_H)  # >= 44 px de tap target (contrat).
	btn.focus_mode = Control.FOCUS_ALL
	btn.tooltip_text = entry["role"]
	MenuWidgets.apply_plate_states(btn, UiTokens.PAPER)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UiTokens.S3
	row.offset_right = -UiTokens.S3
	row.add_theme_constant_override("separation", UiTokens.S3)

	var num := UiTokens.make_label(str(number), UiTokens.display(UiTokens.T_XL, UiTokens.BLUE_DEEP, 4))
	num.custom_minimum_size = Vector2(34, 0)
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(num)

	var icon := TextureRect.new()
	icon.texture = UiTokens.icon(entry["icon"])
	icon.custom_minimum_size = Vector2(140, 90)
	# EXPAND_IGNORE_SIZE + STRETCH_KEEP_ASPECT_CENTERED : le rendu tient dans
	# `custom_minimum_size` ("contain", jamais "cover") -- EXPAND_FIT_WIDTH_
	# PROPORTIONAL essayé d'abord laissait la largeur grandir librement pour
	# garder le ratio à hauteur fixe, et un sticker d'arme (très LARGE,
	# ex. ravage_sticker.png) débordait alors sur le nom/rôle du texte voisin
	# (capture menu_armory_rafale.png, carte 1 "RAVAGE" recouverte). `texture`
	# peut aussi être `null` tant que l'artiste n'a pas encore livré l'icône
	# de la nouvelle arme (WeaponIcon/UiTokens.icon renvoient déjà ce repli
	# sans planter).
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var text_col := VBoxContainer.new()
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_theme_constant_override("separation", 4)
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_child(UiTokens.make_label(String(entry["name"]).to_upper(), UiTokens.label(UiTokens.T_L), true))
	text_col.add_child(UiTokens.make_label(String(entry["role"]), UiTokens.body(UiTokens.T_S, UiTokens.INK_SOFT)))
	row.add_child(text_col)

	var equipped_tag := UiTokens.make_label("ÉQUIPÉE", UiTokens.label(UiTokens.T_XS, UiTokens.INK, 0, true), true)
	equipped_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	equipped_tag.visible = false
	row.add_child(equipped_tag)

	btn.add_child(row)
	btn.pressed.connect(_select_slot.bind(number))
	entry["equipped_tag"] = equipped_tag
	return btn


func _select_slot(number: int) -> void:
	_selected_number = clampi(number, 1, _cards.size())
	for i in _cards.size():
		var entry := _cards[i]
		var selected: bool = (i + 1) == _selected_number
		var row: Button = entry["row"]
		MenuWidgets.apply_plate_states(row, UiTokens.YELLOW if selected else UiTokens.PAPER)
		if selected:
			var sb := row.get_theme_stylebox("normal") as StyleBoxComic
			sb.drop = Vector2(12, 10)
		row.position.x = 18.0 if selected else 0.0
		var tag: Label = entry["equipped_tag"]
		tag.visible = selected
	_persist_selection()
	_refresh_stage()
	_refresh_stats()
	_refresh_hints()


## Choisir une carte persiste IMMÉDIATEMENT (contrat point 2 : "persists
## across sessions ... default Ravage") — pas de bouton "Équiper" séparé,
## le clic EST le choix (même patron que le picker de DeathScreen.gd).
func _persist_selection() -> void:
	var wname: String = String(_current_entry()["name"])
	if Settings.selected_primary != wname:
		Settings.selected_primary = wname
		Settings.save_all()


func _current_entry() -> Dictionary:
	return _cards[_selected_number - 1]


# ------------------------------------------------------------ secondaire fixe (Revolver)

## Le Revolver n'est JAMAIS une carte sélectionnable (contrat point 1 :
## "the permanent secondary") — un simple bandeau d'information sous la
## liste des primaires.
func _build_secondary_chip() -> void:
	var panel := PanelContainer.new()
	panel.position = _CARD_LIST_ORIGIN + Vector2(0, _cards.size() * (_CARD_H + _CARD_GAP) + 10.0)
	panel.custom_minimum_size = Vector2(_CARD_W, 0)
	panel.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.INK, 0.0, UiTokens.DROP_SMALL, UiTokens.STROKE, Vector2(UiTokens.S2, UiTokens.S1)))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.S2)

	var icon := TextureRect.new()
	icon.texture = UiTokens.icon(WeaponIcon.sticker(Loadout.SECONDARY_NAME))
	icon.custom_minimum_size = Vector2(64, 46)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	col.add_child(UiTokens.make_label("Secondaire fixe", UiTokens.label(UiTokens.T_XS, UiTokens.PAPER)))
	col.add_child(UiTokens.make_label(Loadout.SECONDARY_NAME.to_upper(), UiTokens.label(UiTokens.T_M, UiTokens.PAPER, 0, true), true))
	row.add_child(col)

	panel.add_child(row)
	add_child(panel)


# ------------------------------------------------------------ scène (gros rendu)

## Onomatopée par catégorie (armory.html) — étendue aux catégories des 4
## nouvelles primaires (SMG/SHOTGUN/SNIPER, tâche "quatre armes") ; toute
## catégorie non listée garde le repli "PAN !" (`.get(..., "PAN !")`
## ci-dessous), jamais un texte manquant.
const _ONOMA_BY_CATEGORY := {
	WeaponConfig.Category.PISTOL: "BANG !",
	WeaponConfig.Category.RIFLE: "TAC-TAC-TAC !",
	WeaponConfig.Category.SMG: "TATATATA !",
	WeaponConfig.Category.SHOTGUN: "BOUM !",
	WeaponConfig.Category.SNIPER: "CRAC !",
}

## PAS un PanelContainer : plusieurs enfants à des positions ABSOLUES
## (rendu/titre/sous-titre/onomatopée) — un Container les réarrangerait tous
## dans le même rect de contenu (même piège que HomeScreen._build_modes/
## MainMenu._build_topbar, voir leurs docs). Le fond jaune est un `Panel`
## simple (dessine juste sa StyleBox, ne gère aucun enfant).
func _build_stage() -> void:
	var stage := Control.new()
	stage.position = Vector2(600, 150)
	stage.size = Vector2(760, 700)
	stage.custom_minimum_size = Vector2(760, 700)
	stage.clip_contents = true

	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.YELLOW, 0.0, Vector2(12, 12)))
	stage.add_child(bg)

	var burst := MenuWidgets.sunburst_background(UiTokens.YELLOW, UiTokens.YELLOW, UiTokens.YELLOW, true, Vector2(380, 350), 480.0, UiTokens.YELLOW, Color("FFB21F"))
	burst.material.set_shader_parameter("dots_enabled", false)
	stage.add_child(burst)

	_stage_render = TextureRect.new()
	# taille FIXE centrée (EXPAND_FIT_WIDTH_PROPORTIONAL avec une hauteur nulle donnait une
	# largeur nulle : le rendu de l'arme n'apparaissait pas)
	_stage_render.set_anchors_preset(Control.PRESET_CENTER)
	_stage_render.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stage_render.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_stage_render.offset_left = -310.0
	_stage_render.offset_right = 310.0
	_stage_render.offset_top = -170.0
	_stage_render.offset_bottom = 210.0
	_stage_render.pivot_offset = Vector2(310.0, 190.0)
	_stage_render.rotation_degrees = -8.0
	stage.add_child(_stage_render)

	_stage_title = UiTokens.make_label("", UiTokens.display(UiTokens.T_3XL, UiTokens.PAPER, 5))
	_stage_title.position = Vector2(28, 20)
	stage.add_child(_stage_title)

	var sub_wrap := PanelContainer.new()
	sub_wrap.position = Vector2(34, 124)
	sub_wrap.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.INK, UiTokens.SKEW_DEG, Vector2.ZERO, 0.0, Vector2(UiTokens.S2, UiTokens.S1 * 0.6)))
	_stage_sub = UiTokens.make_label("", UiTokens.label(UiTokens.T_S, UiTokens.PAPER), true)
	sub_wrap.add_child(_stage_sub)
	stage.add_child(sub_wrap)

	_stage_onoma = UiTokens.make_label("", UiTokens.display(UiTokens.T_2XL, UiTokens.RED, 6))
	_stage_onoma.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_stage_onoma.position = Vector2(-36 - 300, -30 - 90)
	_stage_onoma.rotation_degrees = -10.0
	stage.add_child(_stage_onoma)

	add_child(stage)


func _refresh_stage() -> void:
	var entry := _current_entry()
	_stage_title.text = String(entry["name"]).to_upper()
	var render_path := "res://assets/ui/renders/%s.png" % String(entry["name"]).to_lower()
	_stage_render.texture = load(render_path) if ResourceLoader.exists(render_path) else null
	var cfg: WeaponConfig = entry["cfg"]
	if cfg:
		# Catégorie RÉELLE (WeaponDatabase.category_name, jamais un libellé
		# inventé) — armory.html ajoute un sous-titre décoratif sans source de
		# données ; on ne le reproduit pas ici.
		_stage_sub.text = WeaponDatabase.category_name(cfg.category).to_upper()
		_stage_onoma.text = _ONOMA_BY_CATEGORY.get(cfg.category, "PAN !")
	else:
		# .tres pas encore livré (A pas fini) : rôle FR (Loadout.role_for) en
		# repli plutôt qu'une catégorie inventée, aucune onomatopée à deviner.
		_stage_sub.text = String(entry["role"]).to_upper()
		_stage_onoma.text = ""
	if _current_skin_icon != null:
		_current_skin_icon.texture = UiTokens.icon(entry["icon"])


# ------------------------------------------------------------ apparences (skins)

func _build_skins_row() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(600, 890)
	row.add_theme_constant_override("separation", 14)

	var current := PanelContainer.new()
	current.custom_minimum_size = Vector2(120, 120)
	current.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.PAPER, 0.0, Vector2(5, 5)))
	var cur_icon := TextureRect.new()
	cur_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	cur_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cur_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cur_icon.name = "CurrentSkinIcon"
	current.add_child(cur_icon)
	row.add_child(current)
	_current_skin_icon = cur_icon

	for i in 3:
		var locked := PanelContainer.new()
		locked.custom_minimum_size = Vector2(120, 120)
		var sb := UiTokens.plate(Color(UiTokens.PAPER.r, UiTokens.PAPER.g, UiTokens.PAPER.b, 0.5), 0.0, Vector2(4, 4))
		locked.add_theme_stylebox_override("panel", sb)
		locked.tooltip_text = "Bientôt"
		locked.mouse_filter = Control.MOUSE_FILTER_STOP
		var lbl := UiTokens.make_label(RosterPadding.LOCKED_TAG, UiTokens.label(UiTokens.T_XS, UiTokens.INK_SOFT), true)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		locked.add_child(lbl)
		row.add_child(locked)

	row.add_child(UiTokens.make_label("Apparences", UiTokens.label(UiTokens.T_S, UiTokens.PAPER)))
	add_child(row)


# ------------------------------------------------------------ stats (vraies valeurs)

func _build_stats_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(1920 - 64 - 480, 150)
	panel.custom_minimum_size = Vector2(480, 0)
	panel.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.PAPER, 0.0, UiTokens.DROP, UiTokens.STROKE, Vector2(UiTokens.S3, UiTokens.S2 + 6)))
	_stats_root = VBoxContainer.new()
	_stats_root.add_theme_constant_override("separation", UiTokens.S3)
	panel.add_child(_stats_root)
	add_child(panel)


## 4 jauges (contrat point 3 : "4 simple stat bars ... computed from
## WeaponConfig") — Dégâts/Cadence/Portée/Mobilité, TOUJOURS dans cet ordre.
## `cfg == null` (le .tres de cette primaire n'est pas encore livré) : aucune
## stat plutôt qu'un crash sur un champ inexistant — l'écran reste utilisable
## pendant qu'A termine les 4 nouvelles armes en parallèle.
func _refresh_stats() -> void:
	for c in _stats_root.get_children():
		c.queue_free()
	var cfg: WeaponConfig = _current_entry()["cfg"]
	if cfg == null:
		return
	var rows := [
		{"label": "Dégâts", "fmt": ArmoryFormat.format_damage(cfg), "bars": ArmoryFormat.damage_bars(cfg)},
		{"label": "Cadence", "fmt": ArmoryFormat.format_fire_rate(cfg), "bars": ArmoryFormat.fire_rate_bars(cfg)},
		{"label": "Portée", "fmt": ArmoryFormat.format_range(cfg), "bars": ArmoryFormat.range_bars(cfg)},
		{"label": "Mobilité", "fmt": ArmoryFormat.format_mobility(cfg), "bars": ArmoryFormat.mobility_bars(cfg)},
	]
	for r in rows:
		_stats_root.add_child(_build_stat_row(r))


func _build_stat_row(r: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTokens.S1 * 0.5)
	var head := HBoxContainer.new()
	head.add_child(UiTokens.make_label(r["label"], UiTokens.label(UiTokens.T_S), true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(UiTokens.make_label(r["fmt"]["value"], UiTokens.display(30, UiTokens.INK, 0)))
	col.add_child(head)
	if int(r["bars"]) >= 0:
		var meter := HBoxContainer.new()
		meter.add_theme_constant_override("separation", 5)
		for i in 10:
			var seg := ColorRect.new()
			seg.custom_minimum_size = Vector2(0, 18)
			seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			seg.color = UiTokens.BLUE if i < int(r["bars"]) else UiTokens.PAPER_2
			meter.add_child(seg)
		col.add_child(meter)
	if str(r["fmt"].get("note", "")) != "":
		col.add_child(UiTokens.make_label(r["fmt"]["note"], UiTokens.body(20, UiTokens.INK_SOFT)))
	return col


# ------------------------------------------------------------ indices de tir

func _build_hints_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(1920 - 64 - 480, 720)
	panel.custom_minimum_size = Vector2(480, 0)
	panel.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.INK, 0.0, Vector2(8, 8), 0.0, Vector2(UiTokens.S3, UiTokens.S2)))
	_hints_root = VBoxContainer.new()
	_hints_root.add_theme_constant_override("separation", UiTokens.S1)
	panel.add_child(_hints_root)
	add_child(panel)
	_refresh_hints()


func _refresh_hints() -> void:
	for c in _hints_root.get_children():
		c.queue_free()
	var cfg: WeaponConfig = _current_entry()["cfg"]
	if cfg == null:
		_hints_root.get_parent().visible = false
		return
	_hints_root.get_parent().visible = true
	for hint in ArmoryFormat.fire_mode_hints(cfg):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiTokens.S2)
		row.add_child(MenuWidgets.key_chip(hint["key"]))
		row.add_child(UiTokens.make_label(hint["label"], UiTokens.label(22, UiTokens.PAPER)))
		_hints_root.add_child(row)
