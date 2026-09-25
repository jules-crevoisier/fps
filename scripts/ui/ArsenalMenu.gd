## ArsenalMenu.gd
## Catalogue de toutes les armes avec leurs statistiques (lecture seule), en
## cartes-autocollants avec panneau de détail (docs/STYLE_BIBLE.md §8.6).
## Accessible depuis le menu principal. Émet `closed` au retour.
##
## ART-34 (2026-09-25) — « Achat et Arsenal v3 » : même grammaire visuelle que
## BuyMenu.gd (kit ART-31, scripts/ui/kit/) pour que les deux écrans d'armes
## se lisent comme UN système : colonne d'onglets inclinés par catégorie
## (`BuyMenu._grouped_categories()`, réutilisée telle quelle — même
## regroupement 5 touches que la boutique, jamais dupliquée ici), grille de
## cartes-armes (silhouette + prix, catalogue LECTURE SEULE : jamais de
## cadenas/« N cr requis », il n'y a ni crédits ni inventaire hors match) et
## panneau de détail (barres de stats + aperçu 3D tournant du modèle réel).
## `WeaponSilhouette`/`WeaponTurntable` viennent de BuyMenu.gd (`preload`,
## même fichier possédé par cette tâche) plutôt que d'être dupliqués.
##
## UX-35 (2026-09-25) — « UI v4 BL3 » (docs/UI_DIRECTION_BL3.md §6, direction
## VALIDÉE) : même grammaire que BuyMenu.gd (cartes 240×150 via `_BUY.
## CARD_SIZE`, onglet ACTIF en fond `signal` via `_BUY._tab_accent()` plutôt
## que le gris `PANEL_HI` fixe de la v3) ; « Gratuit » (Pistolet, seule arme à
## coût nul) n'apparaît plus que sur sa carte, jamais répété dans le panneau
## de détail — voir la même note dans BuyMenu.gd.
extends Control

signal closed

## BuyMenu.gd est possédé par la MÊME tâche (ART-34) : réutiliser son
## regroupement de catégories et son kit d'aperçu 3D évite de dupliquer ~90
## lignes et garantit que Boutique et Arsenal restent visuellement en phase.
const _BUY := preload("res://scripts/ui/BuyMenu.gd")
const GRID_COLUMNS := 3
const TABS_COLUMN_W := 260.0
const DETAIL_COLUMN_W := 440.0
## Voir BuyMenu.STACK_ASPECT_THRESHOLD — même seuil, même justification.
const STACK_ASPECT_THRESHOLD := 0.62

var _tab_bars: Array = []
var _category_grids: Array = []
var _active_category: int = 0
var _body_row: BoxContainer

var _detail_name: Label
var _detail_price: Label
var _detail_kind_label: Label
var _detail_bars: Dictionary = {}
var _detail_mag_label: Label
var _detail_turntable  # BuyMenu.WeaponTurntable

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	var vp := get_viewport()
	if vp:
		vp.size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Comic.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, Comic.SAFE_MARGIN)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Comic.SP_2)
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
	back_row.add_child(spacer)
	var back := Button.new()
	back.text = "Retour"
	back.custom_minimum_size = Vector2(150, 46)
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(func(): closed.emit())
	back_row.add_child(back)

	var body_row := BoxContainer.new()
	body_row.vertical = false
	body_row.add_theme_constant_override("separation", Comic.SP_3)
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body_row)
	_body_row = body_row

	var first_card := _build_tabs_and_grid(body_row)
	_build_detail_panel(body_row)

	var groups: Array = _BUY._grouped_categories()
	if not groups.is_empty() and not (groups[_active_category].weapons as Array).is_empty():
		_show_detail((groups[_active_category].weapons as Array)[0])

	if first_card:
		first_card.grab_focus()
	else:
		back.grab_focus()

## Construit la colonne d'onglets + la grille de cartes pour CHAQUE catégorie
## (même regroupement que BuyMenu, `_BUY._grouped_categories()`) et renvoie la
## première carte construite (cible du focus initial), ou `null` si le
## catalogue est vide.
func _build_tabs_and_grid(parent: Container) -> Control:
	var tabs_col := VBoxContainer.new()
	tabs_col.add_theme_constant_override("separation", Comic.SP_2)
	tabs_col.custom_minimum_size = Vector2(TABS_COLUMN_W, 0)
	parent.add_child(tabs_col)

	var grid_col := VBoxContainer.new()
	grid_col.add_theme_constant_override("separation", Comic.SP_3)
	grid_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid_col)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	grid_col.add_child(scroll)

	var grid_stack := VBoxContainer.new()
	grid_stack.add_theme_constant_override("separation", 0)
	grid_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_stack)

	var groups: Array = _BUY._grouped_categories()
	var first_card: Control = null
	for i in groups.size():
		var g: Dictionary = groups[i]

		var tab := KitSlantBar.new()
		tabs_col.add_child(tab)
		tab.bar_text = "%d — %s" % [i + 1, g.label]
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.accent_color = _BUY._tab_accent(i == _active_category)
		# Tampon « ✓ » (état SELECTED, §8.4) sur l'onglet de la catégorie
		# affichée par défaut dès la construction — sinon aucun onglet ne
		# paraît actif tant que le joueur n'a pas cliqué (bug ART-34 relevé
		# par la revue : `grid.visible` ci-dessous suivait déjà
		# `_active_category`, `tab.selected` ne le faisait pas). Même miroir
		# que BuyMenu._refresh_labels() (`_tab_bars[cat_index].selected =
		# cat_index == _active_category`), mais posé une fois à la
		# construction : ce catalogue est LECTURE SEULE, sans `_refresh_labels`
		# équivalent (pas de crédits/inventaire à rafraîchir périodiquement).
		tab.selected = i == _active_category
		tab.pressed.connect(_select_category.bind(i))
		_tab_bars.append(tab)

		var grid := GridContainer.new()
		grid_stack.add_child(grid)
		grid.columns = GRID_COLUMNS
		grid.add_theme_constant_override("h_separation", Comic.SP_3)
		grid.add_theme_constant_override("v_separation", Comic.SP_3)
		grid.visible = i == _active_category
		_category_grids.append(grid)

		var weapons: Array = g.weapons
		for w in weapons:
			var card := _weapon_card(w)
			grid.add_child(card)
			# UX-35 : `KitCard._ready()` réassigne `custom_minimum_size` à
			# `DEFAULT_SIZE` (220×140) à l'entrée dans l'arbre — 240×150 (§6)
			# doit donc être reposée APRÈS `add_child` (`_ready` tourne
			# SYNCHRONE dedans), jamais avant (voir même note, BuyMenu.gd).
			card.custom_minimum_size = _BUY.CARD_SIZE
			if first_card == null:
				first_card = card

	return first_card

func _weapon_card(w: WeaponConfig) -> KitCard:
	var card := KitCard.new()
	card.card_title = w.weapon_name
	card.accent_color = Comic.PANEL_HI
	card.mouse_entered.connect(_show_detail.bind(w))
	card.focus_entered.connect(_show_detail.bind(w))

	var silhouette: Control = _BUY.WeaponSilhouette.new()
	card.add_child(silhouette)
	silhouette.category = w.category
	silhouette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	silhouette.offset_bottom = -(Comic.SIZE_SUBTITLE + Comic.SP_2)

	var price := Comic.number_label("", Comic.SIZE_BODY, Comic.TEXT)
	card.add_child(price)
	Comic.anchor(price, Control.PRESET_TOP_RIGHT)
	price.offset_left = -140
	price.offset_top = Comic.SP_1
	price.offset_right = -Comic.SP_1
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.text = "Gratuit" if w.cost <= 0 else "%d cr" % w.cost

	return card

func _build_detail_panel(parent: Container) -> void:
	var detail := ComicPanel.new()
	parent.add_child(detail)
	detail.bg_color = Comic.PANEL
	detail.border_width = Comic.RULE_W
	detail.content_margin = Comic.SP_3
	detail.custom_minimum_size = Vector2(DETAIL_COLUMN_W, 0)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Comic.SP_2)
	detail.body.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	_detail_name = Comic.title_label("", Comic.SIZE_LABEL, Comic.TEXT)
	_detail_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_name.clip_text = true
	head.add_child(_detail_name)
	_detail_price = Comic.number_label("", Comic.SIZE_SUBTITLE, Comic.ALLY)
	head.add_child(_detail_price)

	_detail_kind_label = Comic.label("", Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL)
	col.add_child(_detail_kind_label)

	var preview_wrap := Control.new()
	preview_wrap.custom_minimum_size = Vector2(0, 260)
	col.add_child(preview_wrap)
	_detail_turntable = _BUY.WeaponTurntable.new()
	preview_wrap.add_child(_detail_turntable)
	_detail_turntable.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_detail_bars = {
		"damage": _detail_stat_row(col, "Dégâts"),
		"rate": _detail_stat_row(col, "Cadence"),
		"range": _detail_stat_row(col, "Portée"),
	}
	_detail_mag_label = Comic.label("", Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL)
	col.add_child(_detail_mag_label)

func _detail_stat_row(col: VBoxContainer, label_text: String) -> ComicBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Comic.SP_2)
	col.add_child(row)
	var lbl := Comic.label(label_text, Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL)
	lbl.custom_minimum_size = Vector2(110, 0)
	row.add_child(lbl)
	var bar := ComicBar.new()
	row.add_child(bar)
	# UX-35, §6 « 3 barres de stats ... paper, plus de bleu » — `fill_color`
	# est un `@export` PUBLIC de ComicBar.gd (hors de la liste de fichiers de
	# cette tâche, non modifié) : posé ici plutôt que d'y toucher.
	bar.fill_color = Comic.paper_color()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.ticks = 4
	return bar

func _apply_responsive_layout() -> void:
	if _body_row == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vsize := vp.get_visible_rect().size
	if vsize.x <= 0.0:
		return
	_body_row.vertical = (vsize.y / vsize.x) > STACK_ASPECT_THRESHOLD

func _select_category(i: int) -> void:
	if i < 0 or i >= _category_grids.size():
		return
	_active_category = i
	for gi in _category_grids.size():
		(_category_grids[gi] as GridContainer).visible = gi == i
	for ti in _tab_bars.size():
		var tab: KitSlantBar = _tab_bars[ti]
		tab.selected = ti == i
		tab.accent_color = _BUY._tab_accent(ti == i)
	var groups: Array = _BUY._grouped_categories()
	var weapons: Array = groups[i].weapons
	if not weapons.is_empty():
		_show_detail(weapons[0])

func _show_detail(w: WeaponConfig) -> void:
	if w == null or _detail_name == null:
		return
	_detail_name.text = w.weapon_name
	# UX-35, §6 « "Gratuit" une seule fois » — voir la même note dans BuyMenu.gd.
	_detail_price.text = "" if w.cost <= 0 else "%d cr" % w.cost
	_detail_kind_label.text = "%s · %s" % [WeaponDatabase.category_name(w.category), WeaponDatabase.type_name(w.weapon_type)]

	var max_dmg := 1.0
	var max_rate := 1.0
	var max_range := 1.0
	for c in WeaponDatabase.all():
		max_dmg = maxf(max_dmg, c.damage)
		max_rate = maxf(max_rate, c.fire_rate)
		max_range = maxf(max_range, c.max_range)
	var hs: float = w.damage * w.headshot_mult
	var dps: float = w.damage * w.fire_rate * maxi(1, w.pellets)
	(_detail_bars.damage as ComicBar).value = w.damage / max_dmg
	(_detail_bars.rate as ComicBar).value = w.fire_rate / max_rate
	(_detail_bars.range as ComicBar).value = w.max_range / max_range
	var mag_text := "Chargeur %d / %d · Tête %d · DPS ~%d" % [w.mag_size, w.reserve_ammo, int(hs), int(dps)]
	_detail_mag_label.text = mag_text

	_detail_turntable.show_weapon(WeaponDatabase.id_of(w), w.category)
