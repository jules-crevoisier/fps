## AmmoPanel.gd
## Case « munitions » (bas-droite) : nom d'arme, chargeur / réserve, pips
## d'inventaire (arme active pleine, les autres creuses) — design.md v2 §12
## HUD "[▬ RAVAGE] 25/90".
class_name AmmoPanel
extends ComicPanel

var _weapon_label: Label
var _ammo_label: Label
var _reserve_label: Label
var _inv_row: HBoxContainer

func _ready() -> void:
	bg_color = Comic.PANEL
	Comic.anchor(self, Control.PRESET_BOTTOM_RIGHT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -Comic.SAFE_MARGIN
	offset_bottom = -Comic.SAFE_MARGIN

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_1)
	v.alignment = BoxContainer.ALIGNMENT_END
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(v)

	_weapon_label = Comic.label("", int(Comic.SIZE_BODY), Comic.TEXT_DIM, Comic.FONT_LABEL)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_weapon_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", Comic.SP_1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	_ammo_label = Comic.number_label("--", Comic.SIZE_DISPLAY_MD, Comic.TEXT)
	row.add_child(_ammo_label)
	_reserve_label = Comic.number_label("/ --", Comic.SIZE_SUBTITLE, Comic.TEXT_DIM)
	_reserve_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_reserve_label)

	_inv_row = HBoxContainer.new()
	_inv_row.alignment = BoxContainer.ALIGNMENT_END
	_inv_row.add_theme_constant_override("separation", Comic.SP_2)
	_inv_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_inv_row)

func update_ammo(current: int, reserve: int) -> void:
	if _ammo_label:
		_ammo_label.text = HudFormat.format_ammo(current)
	if _reserve_label:
		_reserve_label.text = HudFormat.format_reserve(reserve)

func update_weapon(name: String) -> void:
	if _weapon_label:
		_weapon_label.text = name.to_upper()

## `weapons` : Array de WeaponConfig (ou null pour un slot vide) ; `current_index` :
## index de l'arme active. Un chiffre par slot (● pleine, ○ creuse — sans couleur,
## la forme suffit).
func update_inventory(weapons: Array, current_index: int) -> void:
	if _inv_row == null:
		return
	if _inv_row.get_child_count() != weapons.size():
		for c in _inv_row.get_children():
			c.queue_free()
		for i in weapons.size():
			_inv_row.add_child(Comic.number_label(str(i + 1), Comic.SIZE_BODY, Comic.TEXT_DIM))
	for i in weapons.size():
		var lbl: Label = _inv_row.get_child(i)
		var active := i == current_index
		lbl.text = str(i + 1)
		lbl.add_theme_color_override("font_color", Comic.ALLY if active else Comic.TEXT_DIM)
