## InventoryHUD.gd
## Rangée d'inventaire façon CS (contrat lead 2026-09-27, "inventaire
## CS-style" point 10, RESTYLÉE 2026-09-27 "HUD en jeu" point 3) — 5
## emplacements INCLINÉS en ligne HORIZONTALE, centrée en BAS de l'écran (choix
## utilisateur 2026-09-27 « bas-centre », façon Valorant/Marvel Rivals : la place
## au-dessus des munitions ne lui plaisait pas), hors de la zone centrale
## 40 %×40 % (HudFormat.center_zone_rect, CHK-35) :
##   - emplacement = étiquette NUMÉRO flottante (1..5, un CHIFFRE, jamais une
##     touche clavier) + icône :
##       1/2 : silhouette de l'arme (WeaponIcon.sil, "—" grisé si le slot est
##             vide — aucune icône pour "aucune arme") ;
##       3/4/5 : autocollant couleur de la grenade (WeaponIcon.grenade_stem +
##               "_sticker", UtilityDatabase.FRAG/FLASH/SMOKE) + "×N".
##   - l'emplacement ÉQUIPÉ est surligné (jaune signal UiTokens.YELLOW, texte
##     encre) ET plus HAUT (contrat point 3 : "taller") ;
##   - un emplacement vide/épuisé est assombri à ~35 % (deux effets
##     indépendants : opacité globale ET fond/texte grisés, jamais l'un sans
##     l'autre, voir `_set_row_empty`).
## Alimenté par GameHUD.gd : `update_weapon_slots`/`update_charges`/
## `set_equipped` — API PUBLIQUE INCHANGÉE (contrat : "GameHUD and existing
## tests keep working").
class_name InventoryHUD
extends Control

const _ROW_COUNT := 5
const _WEAPON_ROWS := 2
## Rangées 3/4/5 -> UtilityDatabase.FRAG/FLASH/SMOKE (même ordre que
## UtilityDatabase.all_ids(), voir `_glyph_texture`/`_TYPE_COLORS`, conservés
## en repli si un autocollant venait à manquer sur le disque).
const _GRENADE_KIND_BY_ROW := [UtilityDatabase.FRAG, UtilityDatabase.FLASH, UtilityDatabase.SMOKE]
const _TYPE_COLORS := {
	UtilityDatabase.FRAG: Color("E8392E"),
	UtilityDatabase.FLASH: Color("FFCE1F"),
	UtilityDatabase.SMOKE: Color("D9DDE3"),
}

## >= 44 px physiques à 1280x800 exigé (contrat) : 70 * (1280/1920) ≈ 46.7 px.
const _SLOT_W := 90.0
const _SLOT_H_NORMAL := 70.0
const _SLOT_H_EQUIPPED := 84.0
const _GAP := 10.0
## Posée sur la marge basse commune du HUD (même ligne que la vie et les munitions).
const _BOTTOM_MARGIN := UiTokens.EDGE_MARGIN
const _BADGE_OFFSET := Vector2(-4.0, -16.0)

## Un slot = {"root":Control, "plate":PanelContainer, "style":StyleBoxComic,
## "number_label":Label, "icon":TextureRect, "text_label":Label|null,
## "count_label":Label|null}.
var _rows: Array = []

func _ready() -> void:
	Comic.anchor(self, Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

## Rectangle (espace AUTHORED 1920x1080) occupé par le panneau entier —
## fonction PURE (aucun nœud), utilisée par le test de placement (hors zone
## centrale) sans dépendre d'un layout Control réel. Hauteur = l'état
## ÉQUIPÉ (le plus grand), le plus conservateur pour la vérification de
## chevauchement.
static func panel_rect() -> Rect2:
	var total_w := _SLOT_W * _ROW_COUNT + _GAP * (_ROW_COUNT - 1)
	var viewport_size := Vector2(1920.0, 1080.0)
	var x := (viewport_size.x - total_w) * 0.5
	var y := viewport_size.y - _BOTTOM_MARGIN - _SLOT_H_EQUIPPED
	return Rect2(Vector2(x, y), Vector2(total_w, _SLOT_H_EQUIPPED))

func _build() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(_GAP))
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var total_w := _SLOT_W * _ROW_COUNT + _GAP * (_ROW_COUNT - 1)
	row.offset_left = -total_w * 0.5
	row.offset_right = total_w * 0.5
	row.offset_bottom = -_BOTTOM_MARGIN
	row.offset_top = row.offset_bottom - _SLOT_H_EQUIPPED
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(row)

	for row_index in _ROW_COUNT:
		row.add_child(_build_slot(row_index))

func _build_slot(row_index: int) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(_SLOT_W, _SLOT_H_EQUIPPED)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size_flags_vertical = Control.SIZE_SHRINK_END

	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiTokens.plate(UiTokens.INK_SOFT, UiTokens.SKEW_DEG, UiTokens.DROP_SMALL, UiTokens.STROKE, Vector2(UiTokens.S1, 4.0))
	plate.add_theme_stylebox_override("panel", sb)
	plate.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	plate.offset_top = -_SLOT_H_NORMAL
	plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(plate)

	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Comic.anchor(inner, Control.PRESET_FULL_RECT)
	plate.add_child(inner)

	var icon: TextureRect = null
	var count_label: Label = null
	var text_label: Label = null

	if row_index < _WEAPON_ROWS:
		icon = _build_icon()
		inner.add_child(icon)
		text_label = UiTokens.make_label("—", UiTokens.label(UiTokens.T_M, UiTokens.PAPER, 0, true), true)
		text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Comic.anchor(text_label, Control.PRESET_FULL_RECT)
		inner.add_child(text_label)
	else:
		icon = _build_icon()
		inner.add_child(icon)
		var kind: int = _GRENADE_KIND_BY_ROW[row_index - _WEAPON_ROWS]
		icon.texture = _grenade_icon(kind)
		count_label = Label.new()
		count_label.text = "×1"
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count_label.add_theme_font_size_override("font_size", int(UiTokens.T_XS))
		count_label.add_theme_color_override("font_color", UiTokens.PAPER)
		count_label.add_theme_font_override("font", UiTokens.FONT_LABEL)
		Comic.anchor(count_label, Control.PRESET_FULL_RECT)
		inner.add_child(count_label)

	# Étiquette NUMÉRO flottante (contrat : "number tag") — SIBLING de la
	# plaque inclinée (pas son enfant : elle échapperait sinon aux marges de
	# pente et se retrouverait recadrée), posée hors du coin haut-gauche.
	# `number_label` (clé historique du dictionnaire de rangée, testée par
	# tests/ui/test_inventory_hud.gd) reste le LABEL du chiffre lui-même —
	# `badge` (la plaque encre qui le porte) n'est utile qu'ici.
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.INK, 0.0, Vector2.ZERO, 0.0, Vector2(6.0, 1.0)))
	badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
	badge.offset_left = _BADGE_OFFSET.x
	badge.offset_top = _BADGE_OFFSET.y
	var number_label := UiTokens.make_label(str(row_index + 1), UiTokens.label(UiTokens.T_XS, UiTokens.PAPER, 0, true))
	badge.add_child(number_label)
	root.add_child(badge)

	_rows.append({
		"root": root, "plate": plate, "style": sb, "number_label": number_label,
		"icon": icon, "glyph": icon, "text_label": text_label, "count_label": count_label,
	})
	return root

func _build_icon() -> TextureRect:
	var icon := TextureRect.new()
	# `expand_mode` par défaut (EXPAND_KEEP_SIZE) impose la taille NATIVE du
	# fichier comme taille minimale du contrôle (ex. frag_sticker.png fait
	# 201x256 px) -- IGNORE_SIZE laisse les ancres ci-dessous décider seules,
	# sans quoi l'icône explosait hors du slot dès qu'une texture réelle lui
	# était assignée (les rangées d'armes, sans texture au premier rendu,
	# ne révélaient jamais ce bogue).
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Comic.anchor(icon, Control.PRESET_FULL_RECT)
	icon.offset_top = 6
	icon.offset_bottom = -14
	return icon

## Rangées 1/2 (armes) — `names[i]` = nom AFFICHÉ (déjà en capitales, voir
## GameHUD._update_inventory_hud) ou "" si le slot est vide (icône masquée,
## "—" grisé affiché à la place, contrat point 3).
func update_weapon_slots(names: Array) -> void:
	for i in _WEAPON_ROWS:
		if i >= _rows.size() or i >= names.size():
			continue
		var row: Dictionary = _rows[i]
		var name: String = names[i]
		var empty := name.is_empty()
		var icon: TextureRect = row["icon"]
		var text_label: Label = row["text_label"]
		if empty:
			icon.texture = null
			icon.visible = false
			text_label.visible = true
		else:
			icon.texture = UiTokens.icon(WeaponIcon.sil(name))
			icon.visible = icon.texture != null
			text_label.visible = not icon.visible
		_set_row_empty(row, empty)

## `charges` : Array[int] même ordre que UtilityDatabase.all_ids() — met à
## jour les rangées 3/4/5.
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
	root.modulate = Color(1, 1, 1, 0.35 if empty else 1.0)

## `unified_index` : 0/1 = armes, 2/3/4 = frag/flash/smoke (InventorySelection).
## Surligne la rangée équipée (jaune signal, texte encre) et l'agrandit
## (contrat point 3 : "Equipped slot: YELLOW and taller").
func set_equipped(unified_index: int) -> void:
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var sb: StyleBoxComic = row["style"]
		var equipped := i == unified_index
		sb.fill = UiTokens.YELLOW if equipped else UiTokens.INK_SOFT
		var plate: PanelContainer = row["plate"]
		plate.offset_top = -(_SLOT_H_EQUIPPED if equipped else _SLOT_H_NORMAL)
		var text_color := UiTokens.INK if equipped else UiTokens.PAPER
		var text_label: Label = row["text_label"]
		if text_label:
			text_label.add_theme_color_override("font_color", text_color)
		var count_label: Label = row["count_label"]
		if count_label:
			count_label.add_theme_color_override("font_color", text_color)
		_force_full_opacity_if_equipped(row, equipped)

## Force la rangée équipée à pleine opacité même si elle était assombrie
## juste avant (une grenade qu'on vient d'équiper n'est jamais "épuisée").
func _force_full_opacity_if_equipped(row: Dictionary, equipped: bool) -> void:
	if equipped:
		var root: Control = row["root"]
		root.modulate = Color(1, 1, 1, 1.0)

func _grenade_icon(kind: int) -> Texture2D:
	var stem := WeaponIcon.grenade_stem(kind)
	var tex := UiTokens.icon(stem + "_sticker") if stem != "" else null
	return tex if tex != null else _glyph_texture(kind, UiTokens.PAPER)

# ---------------------------------------------------------------------------
#  Glyphes de type (repli si l'autocollant est absent du disque) — repris
#  d'UtilityHUD/de la version verticale de ce fichier, INCHANGÉS (le test
#  `test_glyph_textures_are_generated_without_crashing` continue de les
#  exercer directement).
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

static func _draw_frag_glyph(img: Image, ink: Color) -> void:
	var w := float(img.get_width())
	var center := Vector2(w * 0.5, w * 0.56)
	_fill_circle(img, center, w * 0.30, ink)
	var lever_start := center + Vector2(-w * 0.04, -w * 0.30)
	var lever_end := lever_start + Vector2(w * 0.22, -w * 0.16)
	_stroke_line(img, lever_start, lever_end, w * 0.09, ink)

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
