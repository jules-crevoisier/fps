## ArmoryScreen.gd
## Écran ARMURERIE du salon (reports/ui/mockups/armory.html, rendu
## reports/ui/renders/armory.png). Le loadout est FIXE en jeu aujourd'hui
## (Inventory.set_loadout(WeaponDatabase.default_loadout_ids()) au spawn +
## UtilityDatabase.all_ids() pour les grenades, voir GameWorld.gd/Inventory.gd) :
## cet écran ne fait QUE consulter les vraies stats (ArmoryFormat), jamais de
## vente/achat — le bouton lit "ÉQUIPÉ" et reste désactivé.
class_name ArmoryScreen
extends Control

## slot -> {kind:"weapon"|"utility", id:int, name, icon, render}. Ordre =
## slots 1-5 de la maquette (Ravage/Revolver puis Frag/Flash/Fumigène).
var _slots: Array[Dictionary] = []
var _selected_slot: int = 1

var _stage_title: Label
var _stage_sub: Label
var _stage_onoma: Label
var _stage_render: TextureRect
var _stats_root: VBoxContainer
var _hints_root: VBoxContainer
var _rows: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_slot_catalog()
	_build()


func _build_slot_catalog() -> void:
	var w_ravage := WeaponDatabase.get_by_name("Ravage")
	var w_revolver := WeaponDatabase.get_by_name("Revolver")
	_slots = [
		{"kind": "weapon", "cfg": w_ravage, "name": "Ravage", "icon": "ravage_sticker", "render": "ravage"},
		{"kind": "weapon", "cfg": w_revolver, "name": "Revolver", "icon": "revolver_sticker", "render": "revolver"},
		{"kind": "utility", "cfg": UtilityDatabase.get_by_id(UtilityDatabase.FRAG), "name": "Frag", "icon": "frag_sticker", "render": "frag"},
		{"kind": "utility", "cfg": UtilityDatabase.get_by_id(UtilityDatabase.FLASH), "name": "Flash", "icon": "flash_sticker", "render": "flash"},
		{"kind": "utility", "cfg": UtilityDatabase.get_by_id(UtilityDatabase.SMOKE), "name": "Fumigène", "icon": "smoke_sticker", "render": "smoke"},
	]


func _build() -> void:
	add_child(MenuWidgets.sunburst_background(Color("3C9BFF"), Color("2E8BFF"), Color("1D5FD6")))
	_build_slot_list()
	_build_stage()
	_build_skins_row()
	_build_stats_panel()
	_build_hints_panel()
	_build_equip_button()
	_select_slot(1)


# ------------------------------------------------------------ liste 1-5

func _build_slot_list() -> void:
	var root := Control.new()
	root.position = Vector2(64, 170)
	add_child(root)

	var y := 0.0
	const ROW_H := 92.0
	const GAP := 14.0
	var group_added := {"weapon": false, "utility": false}
	for i in _slots.size():
		var entry := _slots[i]
		if not group_added[entry["kind"]]:
			var grp := UiTokens.make_label("Armes" if entry["kind"] == "weapon" else "Grenades", UiTokens.label(UiTokens.T_XS, UiTokens.PAPER))
			grp.position = Vector2(0, y)
			root.add_child(grp)
			y += 30.0
			group_added[entry["kind"]] = true
		var row := _build_slot_row(entry, i + 1)
		row.position = Vector2(0, y)
		root.add_child(row)
		entry["row"] = row
		entry["number"] = i + 1
		y += ROW_H + GAP


func _build_slot_row(entry: Dictionary, number: int) -> Button:
	var btn := Button.new()
	btn.size = Vector2(470, 92)
	btn.custom_minimum_size = Vector2(470, 92)
	btn.focus_mode = Control.FOCUS_ALL
	MenuWidgets.apply_plate_states(btn, UiTokens.PAPER)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UiTokens.S3
	row.add_theme_constant_override("separation", UiTokens.S2)
	var num := UiTokens.make_label(str(number), UiTokens.display(UiTokens.T_XL, UiTokens.BLUE_DEEP, 4))
	num.custom_minimum_size = Vector2(34, 0)
	row.add_child(num)
	var icon := TextureRect.new()
	icon.texture = UiTokens.icon(entry["icon"])
	icon.custom_minimum_size = Vector2(150, 58)
	# EXPAND_FIT_WIDTH_PROPORTIONAL : sans lui, le TextureRect garde la taille
	# NATIVE du sticker (défaut EXPAND_KEEP_SIZE) et déborde sur les rangées
	# voisines — bug trouvé à la capture 2026-09-27 (icônes qui débordent).
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	row.add_child(UiTokens.make_label(entry["name"], UiTokens.label(UiTokens.T_M), true))
	btn.add_child(row)
	btn.pressed.connect(_select_slot.bind(number))
	entry["num_label"] = num
	return btn


func _select_slot(number: int) -> void:
	_selected_slot = number
	for entry in _slots:
		var selected: bool = entry["number"] == number
		var row: Button = entry["row"]
		MenuWidgets.apply_plate_states(row, UiTokens.YELLOW if selected else UiTokens.PAPER)
		if selected:
			var sb := row.get_theme_stylebox("normal") as StyleBoxComic
			sb.drop = Vector2(12, 10)
		row.position.x = 18.0 if selected else 0.0
		var num: Label = entry["num_label"]
		num.label_settings.font_color = UiTokens.RED if selected else UiTokens.BLUE_DEEP
	_refresh_stage()
	_refresh_stats()
	_refresh_hints()   # les touches suivent l'arme choisie (éventail au revolver)


func _current_entry() -> Dictionary:
	return _slots[_selected_slot - 1]


# ------------------------------------------------------------ scène (gros rendu)

const _ONOMA_BY_CATEGORY := {
	WeaponConfig.Category.PISTOL: "BANG !",
	WeaponConfig.Category.RIFLE: "TAC-TAC-TAC !",
}
const _ONOMA_BY_UTILITY_KIND := {
	UtilityConfig.Kind.FRAG: "BOUM !",
	UtilityConfig.Kind.FLASH: "FLASH !",
	UtilityConfig.Kind.SMOKE: "PSHHT…",
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
	_stage_title.text = entry["name"].to_upper()
	var render_path := "res://assets/ui/renders/%s.png" % entry["render"]
	_stage_render.texture = load(render_path) if ResourceLoader.exists(render_path) else null
	if entry["kind"] == "weapon":
		var cfg: WeaponConfig = entry["cfg"]
		# Catégorie RÉELLE (WeaponDatabase.category_name, jamais un libellé
		# inventé) — armory.html ajoute un sous-titre décoratif ("Frontier
		# nénuphar") sans source de données ; on ne le reproduit pas ici.
		_stage_sub.text = WeaponDatabase.category_name(cfg.category).to_upper()
		_stage_onoma.text = _ONOMA_BY_CATEGORY.get(cfg.category, "PAN !")
	else:
		var cfg: UtilityConfig = entry["cfg"]
		_stage_sub.text = "Grenade"
		_stage_onoma.text = _ONOMA_BY_UTILITY_KIND.get(cfg.kind, "!")
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


var _current_skin_icon: TextureRect


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


func _refresh_stats() -> void:
	for c in _stats_root.get_children():
		c.queue_free()
	var entry := _current_entry()
	var rows: Array
	if entry["kind"] == "weapon":
		var cfg: WeaponConfig = entry["cfg"]
		rows = [
			{"label": "Dégâts", "fmt": ArmoryFormat.format_damage(cfg), "bars": ArmoryFormat.damage_bars(cfg)},
			{"label": "Cadence", "fmt": ArmoryFormat.format_fire_rate(cfg), "bars": ArmoryFormat.fire_rate_bars(cfg)},
			{"label": "Dispersion", "fmt": ArmoryFormat.format_spread(cfg), "bars": ArmoryFormat.precision_bars(cfg)},
			{"label": "Chargeur", "fmt": ArmoryFormat.format_magazine(cfg), "bars": -1},
		]
	else:
		rows = []
		for r in ArmoryFormat.format_utility(entry["cfg"]):
			rows.append({"label": r["label"], "fmt": r, "bars": -1})
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
	var entry := _current_entry()
	if entry["kind"] != "weapon":
		_hints_root.get_parent().visible = false
		return
	_hints_root.get_parent().visible = true
	for hint in ArmoryFormat.fire_mode_hints(entry["cfg"]):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiTokens.S2)
		row.add_child(MenuWidgets.key_chip(hint["key"]))
		row.add_child(UiTokens.make_label(hint["label"], UiTokens.label(22, UiTokens.PAPER)))
		_hints_root.add_child(row)


# ------------------------------------------------------------ bouton (loadout fixe)

func _build_equip_button() -> void:
	var btn := MenuWidgets.comic_button("Équipé", UiTokens.YELLOW, UiTokens.T_3XL)
	btn.add_theme_font_override("font", UiTokens.FONT_DISPLAY)
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.position = Vector2(-64 - 260, -64 - 100)
	btn.custom_minimum_size = Vector2(260, 100)
	# Le loadout est FIXE (WeaponDatabase.default_loadout_ids/UtilityDatabase.all_ids,
	# voir doc de tête) : jamais une action réelle ici, seulement l'état — pas
	# de vente/achat/équipement possible dans ce prototype.
	btn.disabled = true
	add_child(btn)
