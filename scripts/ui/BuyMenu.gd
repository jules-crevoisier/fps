## BuyMenu.gd
## Menu d'achat / loadout (touche "buy_menu", B par défaut). En mode training,
## tout est GRATUIT (argent infini) : cliquer une arme l'équipe directement.
## À mettre comme CanvasLayer dans les scènes de jeu.
extends CanvasLayer

var _panel: Control
var _open: bool = false
var _first_button: Button

func _ready() -> void:
	layer = 9
	_build()
	_panel.visible = false

func _build() -> void:
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 0.88)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 50)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "ACHAT — TRAINING (gratuit)"
	title.add_theme_font_size_override("font_size", 36)
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	root.add_child(scroll)

	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for w in WeaponDatabase.all():
		var b := Button.new()
		var price: String = "Gratuit" if w.cost <= 0 else "%d cr" % w.cost
		b.text = "%s   —   %s   ·   %s" % [w.weapon_name, WeaponDatabase.category_name(w.category), price]
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(_buy.bind(w))
		grid.add_child(b)
		if _first_button == null:
			_first_button = b

	var close := Button.new()
	close.text = "Fermer (B)"
	close.custom_minimum_size = Vector2(0, 42)
	close.pressed.connect(_close)
	root.add_child(close)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("buy_menu"):
		if _open:
			_close()
		else:
			_pause_open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _open:
		_close()
		get_viewport().set_input_as_handled()

func _pause_open() -> void:
	_open = true
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _first_button:
		_first_button.grab_focus()

func _close() -> void:
	_open = false
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _buy(w: WeaponConfig) -> void:
	var weapon := _local_weapon()
	if weapon:
		weapon.give_weapon(w)
	_close()

func _local_weapon() -> Weapon:
	var arr := get_tree().get_nodes_in_group("local_player")
	if arr.is_empty():
		return null
	return arr[0].get_node_or_null("Weapon")
