## ArsenalMenu.gd
## Catalogue de toutes les armes avec leurs statistiques (lecture seule).
## Accessible depuis le menu principal. Émet `closed` au retour.
extends Control

signal closed

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 40)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "ARSENAL"
	title.add_theme_font_size_override("font_size", 40)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := Button.new()
	back.text = "Retour"
	back.custom_minimum_size = Vector2(140, 40)
	back.pressed.connect(func(): closed.emit())
	header.add_child(title)
	header.add_child(back)
	root.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for w in WeaponDatabase.all():
		list.add_child(_weapon_card(w))

	back.grab_focus()

func _weapon_card(w: WeaponConfig) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.18, 1.0)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	# Ligne titre : nom + coût.
	var head := HBoxContainer.new()
	var name_lbl := _lbl(w.weapon_name, 26, Color(1, 1, 1))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cost_lbl := _lbl(("Gratuit" if w.cost <= 0 else "%d cr" % w.cost), 22, Color(1.0, 0.85, 0.3))
	head.add_child(name_lbl)
	head.add_child(cost_lbl)
	box.add_child(head)

	# Catégorie / type.
	box.add_child(_lbl("%s · %s" % [WeaponDatabase.category_name(w.category), WeaponDatabase.type_name(w.weapon_type)], 16, Color(0.6, 0.8, 1.0)))

	# Stats.
	var hs: float = w.damage * w.headshot_mult
	var dps: float = w.damage * w.fire_rate * maxi(1, w.pellets)
	var stats := "Dégâts %d (tête %d) · Cadence %.1f/s · Chargeur %d · Portée %dm" % [
		int(w.damage), int(hs), w.fire_rate, w.mag_size, int(w.max_range)]
	if w.pellets > 1:
		stats += " · %d plombs" % w.pellets
	stats += " · DPS ~%d" % int(dps)
	box.add_child(_lbl(stats, 15, Color(0.85, 0.87, 0.9)))
	return panel

func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
