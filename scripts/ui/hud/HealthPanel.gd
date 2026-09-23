## HealthPanel.gd
## Case « vitalité » (bas-gauche) : nombre + ComicBar, accent Allié en temps
## normal — sous 30 % (design.md v2 §12), le trait ET le remplissage passent
## en `brush` (rouge = vie basse, design.md §11 "Red means brand or low HP").
class_name HealthPanel
extends ComicPanel

const LOW_HP_RATIO := 0.3

var _bar: ComicBar
var _number: Label
var _label: HBoxContainer

func _ready() -> void:
	bg_color = Comic.PANEL
	Comic.anchor(self, Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	grow_horizontal = Control.GROW_DIRECTION_END
	offset_left = Comic.SAFE_MARGIN
	offset_bottom = -Comic.SAFE_MARGIN

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", Comic.SP_3)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(hb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Comic.SP_1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(220, 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(col)

	_label = Comic.bullet_row("Vitalité", Comic.SIZE_FLOOR)
	col.add_child(_label)

	_bar = ComicBar.new()
	_bar.custom_minimum_size = Vector2(220, Comic.SP_4)
	_bar.fill_color = Comic.ALLY
	col.add_child(_bar)

	_number = Comic.number_label("100", Comic.SIZE_DISPLAY_SM, Comic.TEXT)
	_number.custom_minimum_size = Vector2(80, 0)
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_number)

func update_health(current: float, maximum: float) -> void:
	var ratio := clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	var low := ratio < LOW_HP_RATIO
	if _bar:
		_bar.value = ratio
		_bar.fill_color = Comic.BRUSH if low else Comic.ALLY
	if _number:
		_number.text = "%d" % roundi(current)
		_number.add_theme_color_override("font_color", Comic.BRUSH if low else Comic.TEXT)
	border_color = Comic.BRUSH if low else Comic.RULE
	queue_redraw()
