## ArsenalMenu.gd
## Catalogue de toutes les armes avec leurs statistiques (lecture seule), en
## plaques charcoal avec barres de stats (design.md v2 §11). Accessible depuis
## le menu principal. Émet `closed` au retour.
extends Control

signal closed

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Comic.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, Comic.SAFE_MARGIN)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	margin.add_child(root)

	var header := BrushHeader.new()
	header.title = "Arsenal"
	root.add_child(header)

	var back_row := HBoxContainer.new()
	back_row.add_theme_constant_override("separation", Comic.SP_2)
	back_row.add_theme_constant_override("margin_top", Comic.SP_2)
	root.add_child(back_row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := Button.new()
	back.text = "Retour"
	back.custom_minimum_size = Vector2(150, 46)
	back.pressed.connect(func(): closed.emit())
	back_row.add_child(spacer)
	back_row.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", Comic.SP_2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var all := WeaponDatabase.all()
	var max_dmg := 1.0
	var max_rate := 1.0
	var max_range := 1.0
	for w in all:
		max_dmg = maxf(max_dmg, w.damage)
		max_rate = maxf(max_rate, w.fire_rate)
		max_range = maxf(max_range, w.max_range)
	for w in all:
		list.add_child(_weapon_card(w, max_dmg, max_rate, max_range))

	back.grab_focus()

func _weapon_card(w: WeaponConfig, max_dmg: float, max_rate: float, max_range: float) -> ComicPanel:
	var panel := ComicPanel.new()
	panel.bg_color = Comic.PANEL
	panel.border_width = Comic.RULE_W
	panel.content_margin = Comic.SP_3

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Comic.SP_1)
	panel.body.add_child(box)

	var head := HBoxContainer.new()
	var name_lbl := Comic.title_label(w.weapon_name, Comic.SIZE_LABEL, Comic.TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cost_lbl := Comic.number_label(("Gratuit" if w.cost <= 0 else "%d cr" % w.cost), Comic.SIZE_BODY, Comic.ALLY)
	head.add_child(name_lbl)
	head.add_child(cost_lbl)
	box.add_child(head)

	box.add_child(Comic.label("%s · %s" % [WeaponDatabase.category_name(w.category), WeaponDatabase.type_name(w.weapon_type)], Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL))

	var hs: float = w.damage * w.headshot_mult
	var dps: float = w.damage * w.fire_rate * maxi(1, w.pellets)
	var stats := "Dégâts %d (tête %d) · Cadence %.1f/s · Chargeur %d · Portée %dm" % [
		int(w.damage), int(hs), w.fire_rate, w.mag_size, int(w.max_range)]
	if w.pellets > 1:
		stats += " · %d plombs" % w.pellets
	stats += " · DPS ~%d" % int(dps)
	box.add_child(Comic.label(stats, Comic.SIZE_BODY, Comic.TEXT, Comic.FONT_BODY))

	box.add_child(_stat_bar("Dégâts", w.damage / max_dmg))
	box.add_child(_stat_bar("Cadence", w.fire_rate / max_rate))
	box.add_child(_stat_bar("Portée", w.max_range / max_range))
	return panel

func _stat_bar(label: String, ratio: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Comic.SP_2)
	var lbl := Comic.label(label, Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL)
	lbl.custom_minimum_size = Vector2(110, 0)
	row.add_child(lbl)
	var bar := ComicBar.new()
	bar.custom_minimum_size = Vector2(220, 14)
	bar.value = clampf(ratio, 0.0, 1.0)
	bar.ticks = 4
	row.add_child(bar)
	return row
