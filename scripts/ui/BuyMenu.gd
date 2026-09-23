## BuyMenu.gd
## Menu d'achat / loadout (touche "buy_menu", B par défaut) — design.md v2 §11 :
## overlay à 60 % de l'écran, bandeau pinceau + plaques charcoal par arme avec
## barres de stats.
## - Sans mode de jeu (entraînement) ou mode sans économie (TDM/Hardpoint,
##   Duel/Duo — équipement imposé) : achat libre et gratuit, comme avant.
## - Mode à manches avec économie (SnD, voir SnDMode.my_credits/buy_phase) :
##   affiche le solde de crédits et le prix de chaque arme ; une arme trop
##   chère est hachurée (« Encre renforcée » : deux fois plus dense), une arme
##   déjà possédée porte un tampon « ✓ », une arme juste achetée un « ● »
##   transitoire (achat prédit, en attente de confirmation serveur).
extends CanvasLayer

var _panel: ComicPanel
var _header: BrushHeader
var _open: bool = false
var _first_button: Button
var _entries: Array = []  # Array[Dictionary] {row, button, weapon, hatch, stamp}
var _locked_label: Label
var _mode: Node
var _requested: Dictionary = {}  # weapon_id -> horodatage de la demande (état "●")

func _ready() -> void:
	layer = 9
	_build()
	_panel.visible = false
	_header.visible = false

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(Comic.BG.r, Comic.BG.g, Comic.BG.b, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.visible = false
	add_child(bg)
	_bg = bg

	# Overlay à 60 % de l'écran (design.md §11), centré : bandeau pinceau au-dessus
	# du panneau charcoal (jamais imbriqué dedans, design.md "never nested").
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	wrap.anchor_left = 0.2; wrap.anchor_right = 0.8
	wrap.anchor_top = 0.15; wrap.anchor_bottom = 0.85
	wrap.offset_left = 0; wrap.offset_right = 0; wrap.offset_top = 0; wrap.offset_bottom = 0
	add_child(wrap)

	_header = BrushHeader.new()
	_header.title = "Achat — Training (gratuit)"
	wrap.add_child(_header)

	_panel = ComicPanel.new()
	_panel.bg_color = Comic.PANEL
	_panel.border_width = Comic.RULE_W
	_panel.content_margin = Comic.SP_5
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Comic.SP_3)
	_panel.body.add_child(root)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	root.add_child(scroll)

	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", Comic.SP_2)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for w in WeaponDatabase.all():
		var row := _weapon_row(w)
		grid.add_child(row.node)
		_entries.append(row)
		if _first_button == null:
			_first_button = row.button

	var close := Button.new()
	close.text = "Fermer (B)"
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(_close)
	root.add_child(close)

	_locked_label = Comic.label("Achat verrouillé — manche en cours", Comic.SIZE_BODY, Comic.TEXT, Comic.FONT_LABEL)
	Comic.anchor(_locked_label, Control.PRESET_CENTER_BOTTOM)
	_locked_label.offset_top = -90
	_locked_label.offset_bottom = -60
	_locked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_locked_label.visible = false
	add_child(_locked_label)

var _bg: ColorRect

## Plaque encre par arme : bouton (achat) + hachures (hors de prix) + tampon ✓ (possédée).
func _weapon_row(w: WeaponConfig) -> Dictionary:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 44)
	var b := Button.new()
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(_buy.bind(w))
	wrap.add_child(b)
	var hatch := Comic.hatch_rect(Comic.SP_1, Comic.DISABLED, 0.7)
	hatch.visible = false
	hatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(hatch)
	var stamp := Comic.label("✓", Comic.SIZE_SUBTITLE, Comic.ALLY, Comic.FONT_NUMBER)
	Comic.anchor(stamp, Control.PRESET_CENTER_RIGHT)
	stamp.offset_left = -40
	stamp.visible = false
	wrap.add_child(stamp)
	return {"node": wrap, "button": b, "weapon": w, "hatch": hatch, "stamp": stamp}

func _process(_delta: float) -> void:
	if _mode == null or not is_instance_valid(_mode):
		_mode = get_tree().get_first_node_in_group("game_mode")
	if not _open:
		return
	if _mode and "buy_phase" in _mode and not bool(_mode.buy_phase):
		_close()
		return
	_refresh_labels()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("buy_menu"):
		if _open:
			_close()
		else:
			_try_open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _open:
		_close()
		get_viewport().set_input_as_handled()

## Ouverture forcée pour les captures d'écran (tests/ui/capture_shots.gd) —
## contourne la vérification de phase d'achat, jamais appelé en jeu normal.
func debug_force_open() -> void:
	_open = true
	_panel.visible = true
	_header.visible = true
	_header.replay()
	_bg.visible = true
	_refresh_labels()

func _try_open() -> void:
	if _mode and "buy_phase" in _mode and not bool(_mode.buy_phase):
		_flash_locked()
		return
	_open = true
	_panel.visible = true
	_header.visible = true
	_header.replay()
	_bg.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_labels()
	if _first_button:
		_first_button.grab_focus()

func _flash_locked() -> void:
	_locked_label.visible = true
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(_locked_label):
			_locked_label.visible = false)

func _close() -> void:
	_open = false
	_panel.visible = false
	_header.visible = false
	_bg.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _buy(w: WeaponConfig) -> void:
	var weapon := _local_weapon()
	if weapon:
		var id := WeaponDatabase.id_of(w)
		weapon.buy(id)
		_requested[id] = Time.get_ticks_msec() / 1000.0
		_play_ui_sfx("ui_buy")
	_close()

func _play_ui_sfx(name: String) -> void:
	var sfx := get_tree().root.get_node_or_null("Sfx") if get_tree() else null
	if sfx and sfx.has_method("play_ui"):
		sfx.play_ui(name)

func _local_weapon() -> Weapon:
	var arr := get_tree().get_nodes_in_group("local_player")
	if arr.is_empty():
		return null
	return arr[0].get_node_or_null("Weapon")

func _has_economy() -> bool:
	return _mode != null and is_instance_valid(_mode) and "my_credits" in _mode

func _owned_ids() -> Array:
	var weapon := _local_weapon()
	if weapon == null:
		return []
	var ids: Array = []
	for w in weapon.weapons:
		if w:
			ids.append(WeaponDatabase.id_of(w))
	return ids

func _refresh_labels() -> void:
	var economy := _has_economy()
	var credits: int = int(_mode.my_credits) if economy else -1
	_header.title = ("Achat — %s" % HudFormat.format_credits(credits)) if economy else "Achat — Training (gratuit)"
	var owned := _owned_ids()
	var now := Time.get_ticks_msec() / 1000.0
	for entry in _entries:
		var b: Button = entry.button
		var w: WeaponConfig = entry.weapon
		var id: int = WeaponDatabase.id_of(w)
		var price: String = "Gratuit" if w.cost <= 0 else "%d cr" % w.cost
		var affordable := not economy or w.cost <= credits
		var is_owned := owned.has(id)
		var requested := _requested.has(id) and (now - float(_requested[id])) < 0.6
		var suffix := ""
		if not affordable:
			suffix = "   ·   −%d cr" % (w.cost - credits)
		elif requested:
			suffix = "   ●"
		elif is_owned:
			suffix = ""
		b.text = "%s   —   %s   ·   %s%s" % [w.weapon_name, WeaponDatabase.category_name(w.category), price, suffix]
		b.disabled = not affordable
		entry.hatch.visible = not affordable
		entry.stamp.visible = is_owned and not requested
