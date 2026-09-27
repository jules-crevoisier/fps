## InventoryHUD.gd
## Panneau d'inventaire façon CS (contrat lead 2026-09-27, "inventaire
## CS-style", point 10) — remplace UtilityHUD.gd (3 emplacements bas-centre) :
## une liste VERTICALE de 5 rangées, bas-droite, hors de la zone centrale
## 40 %×40 % réservée au réticule/hitmarker (HudFormat.center_zone_rect,
## CHK-35).
##   - rangée = le NUMÉRO de slot (1..5, des CHIFFRES, jamais une touche
##     clavier) puis l'objet :
##       1 : nom de l'arme primaire (WeaponConfig.weapon_name, ex. "RAVAGE") ;
##       2 : "—" grisé tant qu'aucune arme secondaire n'est équipée ;
##       3/4/5 : le glyphe de grenade existant (frag/flash/smoke, voir
##               `_glyph_texture`, repris tel quel d'UtilityHUD) + "×1"/"×0".
##   - la rangée ÉQUIPÉE est surlignée (jaune signal #FFCE1F, texte encre) ;
##   - une rangée vide/épuisée est assombrie à ~35 % (même convention
##     qu'UtilityHUD.update_charges : DEUX effets distincts, opacité globale
##     ET teinte grisée, jamais l'un sans l'autre).
## Alimenté par GameHUD.gd : `update_weapon_slots`/`update_charges`/
## `set_equipped` — trois entrées séparées plutôt qu'un seul struct, chacune
## correspondant à un signal DISTINCT côté gameplay (Weapon.weapon_changed,
## UtilityThrower.charges_changed, UtilityThrower.equipped_changed) avec son
## propre rythme de mise à jour.
class_name InventoryHUD
extends Control

const _AUTHORED_PER_PHYSICAL_PX := 1920.0 / 1280.0

static func _au(physical_px: float) -> float:
	return physical_px * _AUTHORED_PER_PHYSICAL_PX

const _ROW_COUNT := 5
const _WEAPON_ROWS := 2  # rangées 1/2 : texte (nom d'arme / "—")
## Rangées 3/4/5 -> UtilityDatabase.FRAG/FLASH/SMOKE (même ordre que
## UtilityDatabase.all_ids(), voir _glyph_texture/_TYPE_COLORS).
const _GRENADE_KIND_BY_ROW := [UtilityDatabase.FRAG, UtilityDatabase.FLASH, UtilityDatabase.SMOKE]
const _TYPE_COLORS := {
	UtilityDatabase.FRAG: Color("E8392E"),
	UtilityDatabase.FLASH: Color("FFCE1F"),
	UtilityDatabase.SMOKE: Color("D9DDE3"),
}

const _INK := Color("0E0A12")
const _PAPER := Color("FFF4E0")
const _ROW_BG := Color("1E1A17")     # Comic.PANEL (valeur reprise en dur : pas de dépendance dure à Comic ici).
const _EQUIP_COLOR := Color("FFCE1F")  # jaune signal (contrat point 10).
const _EMPTY_ALPHA := 0.35
const _EMPTY_TILE_COLOR := Color(0.55, 0.55, 0.58)

const _ROW_WIDTH_PHYSICAL_PX := 210.0
const _ROW_HEIGHT_PHYSICAL_PX := 48.0   ## >= 44 px exigé (contrat), marge prise.
const _GAP_PHYSICAL_PX := 6.0
const _RIGHT_MARGIN_PHYSICAL_PX := 24.0
const _BOTTOM_MARGIN_PHYSICAL_PX := 24.0
const _BORDER_PHYSICAL_PX := 3.0
const _NUMBER_COL_PHYSICAL_PX := 34.0
const _GLYPH_PHYSICAL_PX := 30.0
const _NUMBER_FONT_PHYSICAL_PX := 20.0
const _LABEL_FONT_PHYSICAL_PX := 16.0
const _COUNT_FONT_PHYSICAL_PX := 14.0

## Police en gras réelle du projet si présente (même repli que l'ancien
## UtilityHUD : contour 4 px encre sur la police par défaut sinon).
const _BOLD_FONT_CANDIDATES := [
	"res://resources/fonts/BarlowCondensed-ExtraBold.ttf",
	"res://resources/fonts/Bangers-Regular.ttf",
]
static var _bold_font: Font
static var _bold_font_checked := false

static func _hud_font() -> Font:
	if not _bold_font_checked:
		_bold_font_checked = true
		for path in _BOLD_FONT_CANDIDATES:
			if ResourceLoader.exists(path):
				_bold_font = load(path) as Font
				break
	return _bold_font

static func _style_label(l: Label, size_physical_px: float, color: Color) -> void:
	l.add_theme_font_size_override("font_size", int(round(_au(size_physical_px))))
	l.add_theme_color_override("font_color", color)
	var f := _hud_font()
	if f:
		l.add_theme_font_override("font", f)
	else:
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", _INK)

## Un slot = {"root":Control, "style":StyleBoxFlat, "number_label":Label,
## "text_label":Label, "glyph":TextureRect|null, "count_label":Label|null}.
var _rows: Array = []

func _ready() -> void:
	Comic.anchor(self, Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

## Rectangle (espace AUTHORED fixe 1920×1080, voir project.godot
## `window/size/viewport_*`) occupé par le panneau entier — fonction PURE
## (aucun nœud), utilisée par le test de placement (hors zone centrale,
## HudFormat.overlaps_center_zone) sans dépendre de la résolution d'un layout
## Control réel (non fiable en tête sans fenêtre, voir tests/ui/test_hud_format.gd
## pour la même précaution).
static func panel_rect() -> Rect2:
	var row_w := _au(_ROW_WIDTH_PHYSICAL_PX)
	var row_h := _au(_ROW_HEIGHT_PHYSICAL_PX)
	var gap := _au(_GAP_PHYSICAL_PX)
	var total_h := row_h * _ROW_COUNT + gap * (_ROW_COUNT - 1)
	var right_margin := _au(_RIGHT_MARGIN_PHYSICAL_PX)
	var bottom_margin := _au(_BOTTOM_MARGIN_PHYSICAL_PX)
	var viewport_size := Vector2(1920.0, 1080.0)
	var x := viewport_size.x - right_margin - row_w
	var y := viewport_size.y - bottom_margin - total_h
	return Rect2(Vector2(x, y), Vector2(row_w, total_h))

func _build() -> void:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", int(round(_au(_GAP_PHYSICAL_PX))))
	col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var row_w := _au(_ROW_WIDTH_PHYSICAL_PX)
	var row_h := _au(_ROW_HEIGHT_PHYSICAL_PX)
	var total_h := row_h * _ROW_COUNT + _au(_GAP_PHYSICAL_PX) * (_ROW_COUNT - 1)
	col.offset_right = -_au(_RIGHT_MARGIN_PHYSICAL_PX)
	col.offset_left = col.offset_right - row_w
	col.offset_bottom = -_au(_BOTTOM_MARGIN_PHYSICAL_PX)
	col.offset_top = col.offset_bottom - total_h
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(col)

	for row_index in _ROW_COUNT:
		col.add_child(_build_row(row_index))

func _build_row(row_index: int) -> Control:
	var row_w := _au(_ROW_WIDTH_PHYSICAL_PX)
	var row_h := _au(_ROW_HEIGHT_PHYSICAL_PX)
	var root := Control.new()
	root.custom_minimum_size = Vector2(row_w, row_h)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := Panel.new()
	Comic.anchor(panel, Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = _ROW_BG
	sb.border_color = _INK
	sb.set_border_width_all(int(round(_au(_BORDER_PHYSICAL_PX))))
	sb.set_corner_radius_all(int(row_h * 0.12))
	sb.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	# Colonne numéro (chiffre 1..5, jamais une touche clavier — contrat point 10).
	var number_label := Label.new()
	number_label.text = str(row_index + 1)
	number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Colonne ancrée à GAUCHE : ancrée sur toute la largeur, le chiffre finissait
	# centré dans la rangée (« RAVAGE 1 »).
	number_label.anchor_right = 0.0
	number_label.offset_right = _au(_NUMBER_COL_PHYSICAL_PX)
	_style_label(number_label, _NUMBER_FONT_PHYSICAL_PX, _PAPER)
	root.add_child(number_label)

	var glyph: TextureRect = null
	var count_label: Label = null
	var text_label: Label = null

	if row_index < _WEAPON_ROWS:
		text_label = Label.new()
		text_label.text = "—" if row_index == 1 else ""  # rangée 1 : posée par update_weapon_slots.
		text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		text_label.offset_left = _au(_NUMBER_COL_PHYSICAL_PX)
		text_label.offset_right = -_au(8.0)
		text_label.clip_text = true
		_style_label(text_label, _LABEL_FONT_PHYSICAL_PX, _PAPER)
		root.add_child(text_label)
	else:
		var kind: int = _GRENADE_KIND_BY_ROW[row_index - _WEAPON_ROWS]
		glyph = TextureRect.new()
		glyph.texture = _glyph_texture(kind, _INK)
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		glyph.anchor_right = 0.0
		glyph.offset_left = _au(_NUMBER_COL_PHYSICAL_PX)
		glyph.offset_right = _au(_NUMBER_COL_PHYSICAL_PX) + _au(_GLYPH_PHYSICAL_PX)
		var glyph_inset := (row_h - _au(_GLYPH_PHYSICAL_PX)) * 0.5
		glyph.offset_top = glyph_inset
		glyph.offset_bottom = -glyph_inset
		root.add_child(glyph)

		count_label = Label.new()
		count_label.text = "×1"
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		count_label.offset_left = glyph.offset_right
		count_label.offset_right = -_au(8.0)
		_style_label(count_label, _COUNT_FONT_PHYSICAL_PX, _PAPER)
		root.add_child(count_label)

	_rows.append({
		"root": root, "style": sb, "number_label": number_label,
		"text_label": text_label, "glyph": glyph, "count_label": count_label,
	})
	return root

## Rangées 1/2 (armes) — `names[i]` = nom affiché (déjà en capitales, voir
## GameHUD._update_inventory_hud : `WeaponConfig.weapon_name.to_upper()`) ou
## "" si le slot est vide (affiche alors "—" grisé, contrat point 10).
func update_weapon_slots(names: Array) -> void:
	for i in _WEAPON_ROWS:
		if i >= _rows.size() or i >= names.size():
			continue
		var row: Dictionary = _rows[i]
		var label: Label = row["text_label"]
		var name: String = names[i]
		var empty := name.is_empty()
		label.text = "—" if empty else name
		_set_row_empty(row, empty)

## `charges` : Array[int] même ordre que UtilityDatabase.all_ids() (voir
## UtilityInventory.snapshot) — met à jour les rangées 3/4/5.
func update_charges(charges: Array) -> void:
	for row_index in range(_WEAPON_ROWS, _ROW_COUNT):
		var kind: int = _GRENADE_KIND_BY_ROW[row_index - _WEAPON_ROWS]
		if kind >= charges.size():
			continue
		var row: Dictionary = _rows[row_index]
		var count := int(charges[kind])
		var label: Label = row["count_label"]
		label.text = "×%d" % count
		_set_row_empty(row, count <= 0)

func _set_row_empty(row: Dictionary, empty: bool) -> void:
	var root: Control = row["root"]
	# Ne touche PAS l'opacité de la rangée ÉQUIPÉE (contrat : les DEUX états
	# sont indépendants et peuvent coexister, voir docstring de classe —
	# ex. juste après un lancer, la frag reste équipée le temps du retour à
	# l'arme alors que sa charge est déjà à 0) : `set_equipped` gère SA PROPRE
	# opacité (toujours pleine) après cet appel, dans l'ordre où GameHUD les
	# appelle (update_* puis set_equipped, voir GameHUD._update_inventory_hud).
	root.modulate = Color(1, 1, 1, _EMPTY_ALPHA if empty else 1.0)

## `unified_index` : 0/1 = armes, 2/3/4 = frag/flash/smoke (InventorySelection) —
## surligne la rangée équipée (jaune signal, texte encre), rétablit les
## couleurs normales des autres (fond neutre, glyphe/texte papier, ou la
## teinte du type pour un glyphe de grenade).
func set_equipped(unified_index: int) -> void:
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var sb: StyleBoxFlat = row["style"]
		var equipped := i == unified_index
		sb.bg_color = _EQUIP_COLOR if equipped else _ROW_BG
		var text_color := _INK if equipped else _PAPER
		var number_label: Label = row["number_label"]
		number_label.add_theme_color_override("font_color", text_color)
		var text_label: Label = row["text_label"]
		if text_label:
			text_label.add_theme_color_override("font_color", text_color)
		var count_label: Label = row["count_label"]
		if count_label:
			count_label.add_theme_color_override("font_color", text_color)
		_force_full_opacity_if_equipped(row, equipped)

## Force la rangée équipée à pleine opacité même si elle était assombrie
## juste avant (une grenade qu'on vient d'équiper n'est jamais "épuisée" —
## `can_select`/`InventorySelection` l'interdit ; l'arme équipée n'est jamais
## vide non plus, `Inventory.equip` refuse un slot EMPTY) — voir `_set_row_empty`.
func _force_full_opacity_if_equipped(row: Dictionary, equipped: bool) -> void:
	if equipped:
		var root: Control = row["root"]
		root.modulate = Color(1, 1, 1, 1.0)

# ---------------------------------------------------------------------------
#  Glyphes de type (repris tels quels d'UtilityHUD.gd, même contrat visuel :
#  "a simple type glyph drawn in code").
# ---------------------------------------------------------------------------
const _GLYPH_PX := 64

static func _glyph_texture(kind: int, ink: Color) -> ImageTexture:
	var img := Image.create(_GLYPH_PX, _GLYPH_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match kind:
		UtilityDatabase.FRAG:
			_draw_frag_glyph(img, ink)
		UtilityDatabase.FLASH:
			_draw_flash_glyph(img, ink)
		UtilityDatabase.SMOKE:
			_draw_smoke_glyph(img, ink)
		_:
			pass
	return ImageTexture.create_from_image(img)

static func _fill_circle(img: Image, center: Vector2, radius: float, color: Color) -> void:
	var r2 := radius * radius
	var w := img.get_width()
	var h := img.get_height()
	var min_x := maxi(0, int(center.x - radius))
	var max_x := mini(w - 1, int(center.x + radius))
	var min_y := maxi(0, int(center.y - radius))
	var max_y := mini(h - 1, int(center.y + radius))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx := float(x) - center.x
			var dy := float(y) - center.y
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, color)

static func _stroke_line(img: Image, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var dist := a.distance_to(b)
	var steps := int(dist * 2.0) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		_fill_circle(img, p, width * 0.5, color)

## Frag : un cercle (corps) + un petit levier (rectangle incliné qui dépasse).
static func _draw_frag_glyph(img: Image, ink: Color) -> void:
	var w := float(img.get_width())
	var center := Vector2(w * 0.5, w * 0.56)
	_fill_circle(img, center, w * 0.30, ink)
	var lever_start := center + Vector2(-w * 0.04, -w * 0.30)
	var lever_end := lever_start + Vector2(w * 0.22, -w * 0.16)
	_stroke_line(img, lever_start, lever_end, w * 0.09, ink)

## Flash : étoile 4 pointes (astroïde |x|^k + |y|^k <= r^k, k<1 -> silhouette
## concave à 4 branches, un "sparkle" reconnaissable en quelques pixels).
static func _draw_flash_glyph(img: Image, ink: Color) -> void:
	var w := img.get_width()
	var c := Vector2(w * 0.5, w * 0.5)
	var r := float(w) * 0.42
	const K := 0.66
	var rk := pow(r, K)
	for y in w:
		for x in w:
			var dx := absf(float(x) - c.x)
			var dy := absf(float(y) - c.y)
			if pow(dx, K) + pow(dy, K) <= rk:
				img.set_pixel(x, y, ink)

## Smoke : 3 cercles qui se chevauchent (silhouette de nuage minimale).
static func _draw_smoke_glyph(img: Image, ink: Color) -> void:
	var w := float(img.get_width())
	var r := w * 0.26
	var centers := [
		Vector2(w * 0.36, w * 0.60),
		Vector2(w * 0.64, w * 0.60),
		Vector2(w * 0.50, w * 0.36),
	]
	for c in centers:
		_fill_circle(img, c, r, ink)
