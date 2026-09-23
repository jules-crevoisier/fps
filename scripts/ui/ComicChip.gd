## ComicChip.gd
## Badge de capacité v2 (design.md §12 HUD "[C][Q][E] [X 72%]") : case
## charcoal, touche en pastille pinceau, nom, statut. Hachures qui se vident
## pendant le cooldown, charges en pastilles, trait pinceau + fond `panel_hi`
## quand l'ultime est prêt.
class_name ComicChip
extends Control

const SIZE := Vector2(84, 122)
const MAX_FIT_SIZE := 24

## Dernier recours (design de secours après le plancher deux-lignes) — noms
## dont même le mot le plus long déborde encore à `Comic.SIZE_FLOOR`.
const ABBREVIATIONS := {
	"Éblouissement": "Éblouiss.",
	"Résurgence": "Résurg.",
	"Vision totale": "Vision tot.",
	"Chausse-trape": "Chausse-tr.",
	"Poste avancé": "Poste av.",
}

var _key := ""
var _title := ""
var _is_ult := false
var _panel: ComicPanel
var _key_chip: Control
var _key_label: Label
var _title_label: Label
var _status_label: Label
var _pip_row: HBoxContainer
var _hatch: TextureRect

func setup(key: String, title: String, is_ult: bool = false) -> void:
	_key = key
	_title = title
	_is_ult = is_ult

func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = ComicPanel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.bg_color = Comic.PANEL
	_panel.border_width = Comic.RULE_W
	_panel.content_margin = Comic.SP_1
	add_child(_panel)  # _ready() de ComicPanel s'exécute immédiatement (nœud déjà dans l'arbre) : `body` existe ci-dessous.

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.body.add_child(v)

	_key_chip = Control.new()
	_key_chip.custom_minimum_size = Vector2(0, Comic.SIZE_BODY + Comic.SP_1)
	_key_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_key_chip)
	var key_bg := ColorRect.new()
	key_bg.color = Comic.BRUSH
	key_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Comic.anchor(key_bg, Control.PRESET_CENTER)
	key_bg.offset_left = -20; key_bg.offset_right = 20
	key_bg.offset_top = -14; key_bg.offset_bottom = 14
	_key_chip.add_child(key_bg)
	_key_label = Comic.label(_key, Comic.SIZE_BODY, Comic.TEXT, Comic.FONT_NUMBER)
	_key_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_key_chip.add_child(_key_label)

	_title_label = Comic.label("", Comic.SIZE_FLOOR, Comic.TEXT_DIM, Comic.FONT_LABEL)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title_label)
	_fit_title()

	_status_label = Comic.number_label("", Comic.SIZE_FLOOR, Comic.ALLY)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status_label)

	_pip_row = HBoxContainer.new()
	_pip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_pip_row.add_theme_constant_override("separation", 3)
	_pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_pip_row)

	_hatch = Comic.hatch_rect(Comic.SP_1, Comic.DISABLED, 0.55)
	_hatch.visible = false
	add_child(_hatch)

## Ajuste le nom de la capacité pour qu'il ne soit JAMAIS coupé (retour lead
## R3) : 1) une ligne, taille décroissante jusqu'au plancher SIZE_FLOOR ;
## 2) deux lignes au plancher si aucun mot seul ne déborde ; 3) table
## d'abréviation en dernier recours (jamais de troncature muette "...").
func _fit_title() -> void:
	if _title_label == null:
		return
	var upper := _title.to_upper()
	var max_w: float = SIZE.x - _panel.content_margin * 2 - 4.0
	_title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	for size in range(MAX_FIT_SIZE, Comic.SIZE_FLOOR - 1, -1):
		if Comic.FONT_LABEL.get_string_size(upper, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
			_title_label.add_theme_font_size_override("font_size", size)
			_title_label.custom_minimum_size = Vector2(0, Comic.FONT_LABEL.get_height(size) * 1.15)
			_title_label.text = upper
			return
	var floor_size := Comic.SIZE_FLOOR
	var widest_word := 0.0
	for w in upper.split(" "):
		widest_word = maxf(widest_word, Comic.FONT_LABEL.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, floor_size).x)
	_title_label.add_theme_font_size_override("font_size", floor_size)
	if widest_word <= max_w:
		_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_title_label.custom_minimum_size = Vector2(0, Comic.FONT_LABEL.get_height(floor_size) * 2.3)
		_title_label.text = upper
		return
	var abbr: String = ABBREVIATIONS.get(_title, "")
	if abbr == "":
		abbr = (_title.substr(0, 7) + ".") if _title.length() > 8 else _title
	_title_label.custom_minimum_size = Vector2(0, Comic.FONT_LABEL.get_height(floor_size) * 1.15)
	_title_label.text = abbr.to_upper()

## `ratio` (0..1) : progression cooldown/ultime. `charges` : nb de pastilles à
## afficher (-1 = ne pas afficher de pastilles, ex. ultime).
func set_status(text: String, ready_state: bool, ratio: float, charges: int) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", Comic.ALLY if ready_state else Comic.TEXT_DIM)
	if _hatch:
		var cooling := not ready_state and charges <= 0
		_hatch.visible = cooling
		if cooling:
			# Hachures qui se vident depuis le bas au fil du cooldown (design.md §11).
			_hatch.anchor_top = 0.0
			_hatch.anchor_bottom = clampf(1.0 - ratio, 0.0, 1.0)
			_hatch.offset_top = 0.0
			_hatch.offset_bottom = 0.0
	if _panel:
		var ult_ready := ready_state and _is_ult
		_panel.bg_color = Comic.PANEL_HI if ult_ready else Comic.PANEL
		_panel.border_color = Comic.BRUSH if ult_ready else Comic.RULE
		_panel.border_width = Comic.RULE_W_STRONG if ult_ready else Comic.RULE_W
	_refresh_pips(charges)

func _refresh_pips(charges: int) -> void:
	if _pip_row == null:
		return
	for c in _pip_row.get_children():
		c.queue_free()
	if charges < 0:
		return
	for i in charges:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(6, 6)
		pip.color = Comic.ALLY
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pip_row.add_child(pip)
