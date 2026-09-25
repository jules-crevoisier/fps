## KitHexagon.gd
## Kit de composants autocollant (ART-31, docs/STYLE_BIBLE.md §8.2/§8.3/§8.4)
## — famille « Hexagone » : l'hexagone de capacité, pointe en haut (§8.2 jeton
## `hex` : Ø 96 px en menus, Ø 72/48 px au HUD — c'est le SEUL autocollant
## toléré dans le HUD, §8.1 Couche 2 « Où »), onglet de touche Ø 30 px en bas
## à gauche (épingle 02).
##
## Ses 9 états (§8.4, colonne « Hexagone ») :
##   Défaut       — papier (prêt) ou charbon (recharge), selon l'état de jeu
##                  (`ready_state`).
##   Survol       — liseré papier 2 px.
##   Focus visible— idem survol + flèche ▶ pinceau à gauche.
##   Pressé       — idem (table §8.4 : « idem » réfère à Focus visible).
##   Sélectionné, Chargement, Vide — « — » : NON APPLICABLE (un hexagone n'a
##                  pas de notion de sélection/chargement/liste vide propre —
##                  ce sont des états de liste/carte). Rendu = Défaut ; voir
##                  `KitStates.HEXAGON_NA_STATES` (la galerie affiche un tiret
##                  à leur place plutôt que d'inventer un rendu hors spec).
##   Désactivé    — charbon + hachures.
##   Erreur       — tremblement de 3 px sur 200 ms (aucun en mouvement
##                  réduit) — capture statique : voir la légende de la
##                  galerie, une capture PNG ne montre pas un tremblement.
##
## `extends BaseButton` : survol/focus/pression/désactivé/infobulle natifs
## (CHK-37). `state_override` (KitStates.State, -1 = auto) force l'état pour
## la galerie — voir KitStates.gd.
class_name KitHexagon
extends BaseButton

const DEFAULT_DIAMETER := Comic.HEX_MENU_PX
const KEY_TAB_DIAMETER := Comic.HEX_KEY_TAB_PX

@export var key_label: String = "Q"
@export var ability_title: String = "Capacité"
## Prêt (papier) / en recharge (charbon) — état de JEU, indépendant des 9
## états d'interaction ci-dessus (§8.4 : « papier ou charbon selon l'état de
## jeu »).
@export var ready_state: bool = true:
	set(v):
		ready_state = v
		queue_redraw()
@export var disabled_reason: String = "":
	set(v):
		disabled_reason = v
		_refresh()
@export var error_text: String = "":
	set(v):
		error_text = v
		_refresh()
@export var state_override: int = -1:
	set(v):
		state_override = v
		_refresh()

var _held := false
var _shake_offset := Vector2.ZERO
var _shake_tween: Tween
var _last_state := -1
var _title_label: Label
var _reason_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(DEFAULT_DIAMETER, DEFAULT_DIAMETER + (Comic.SIZE_FLOOR + Comic.SP_1) * 2)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	mouse_entered.connect(_refresh)
	mouse_exited.connect(_refresh)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	resized.connect(_refresh)

	_title_label = Comic.label(ability_title.to_upper(), Comic.SIZE_FLOOR, Comic.TEXT_DIM, Comic.FONT_LABEL)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title_label)

	_reason_label = Comic.label("", Comic.SIZE_FLOOR, Comic.DISABLED)
	_reason_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason_label.visible = false
	add_child(_reason_label)

	_refresh()


func _on_button_down() -> void:
	_held = true
	_refresh()


func _on_button_up() -> void:
	_held = false
	_refresh()


func set_disabled_with_reason(reason: String) -> void:
	disabled_reason = reason
	disabled = true
	_refresh()


func current_state() -> int:
	if state_override >= 0:
		return state_override
	if error_text != "":
		return KitStates.State.ERROR
	if disabled:
		return KitStates.State.DISABLED
	if _held:
		return KitStates.State.PRESSED
	if has_focus():
		return KitStates.State.FOCUS
	if is_hovered():
		return KitStates.State.HOVER
	return KitStates.State.DEFAULT


func _refresh() -> void:
	if _title_label == null or not is_inside_tree():
		return
	var s := current_state()
	tooltip_text = disabled_reason if (s == KitStates.State.DISABLED and disabled_reason != "") else ""

	var d := DEFAULT_DIAMETER
	_title_label.position = Vector2(0.0, d + Comic.SP_1)
	_title_label.size = Vector2(size.x, Comic.SIZE_FLOOR)

	_reason_label.visible = s == KitStates.State.DISABLED
	if _reason_label.visible:
		_reason_label.text = disabled_reason if disabled_reason != "" else KitStates.DEFAULT_DISABLED_REASON
		_reason_label.position = Vector2(0.0, d + Comic.SIZE_FLOOR + Comic.SP_2)
		_reason_label.size = Vector2(size.x, Comic.SIZE_FLOOR)

	if s == KitStates.State.ERROR and _last_state != KitStates.State.ERROR:
		_play_shake()
	_last_state = s
	queue_redraw()


func _play_shake() -> void:
	_shake_offset = Vector2.ZERO
	if Comic.reduced_motion():
		return  # tokens.json reduced_motion.forbid: shake — aucune interpolation.
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	var amp := 3.0
	var seg := 0.04  # 5 segments x 40 ms = 200 ms (STYLE_BIBLE v3 §8.4).
	var keys := [amp, -amp, amp * 0.6, -amp * 0.6, 0.0]
	var prev := 0.0
	for k in keys:
		_shake_tween.tween_method(_set_shake_x, prev, k, seg)
		prev = k


func _set_shake_x(v: float) -> void:
	_shake_offset = Vector2(v, 0.0)
	queue_redraw()


## Hexagone pointe en haut, centré sur `center`, de diamètre `d`.
func _hex_points(center: Vector2, d: float) -> PackedVector2Array:
	var r := d * 0.5
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(-90.0 + 60.0 * float(i))
		pts.append(center + Vector2(cos(ang), sin(ang)) * r)
	return pts


func _draw() -> void:
	var d := DEFAULT_DIAMETER
	if size.x <= 0.0 or d <= 0.0:
		return
	var s := current_state()
	var center := Vector2(size.x * 0.5, d * 0.5) + _shake_offset

	var fill := Comic.TEXT if ready_state else Comic.PANEL
	var glyph_color := Comic.HARD_SHADOW_COLOR if ready_state else Comic.TEXT_DIM
	if s == KitStates.State.DISABLED:
		fill = Comic.PANEL
		glyph_color = Comic.DISABLED

	var hex := _hex_points(center, d)
	draw_colored_polygon(hex, fill)
	var closed := PackedVector2Array()
	for p in hex:
		closed.append(p)
	closed.append(hex[0])
	draw_polyline(closed, Comic.HARD_SHADOW_COLOR, Comic.STROKE_STICKER)

	if s == KitStates.State.DISABLED:
		_draw_hatch_hex(hex)

	# Survol/Focus/Pressé (idem, §8.4 : « idem » réfère à la ligne du dessus) —
	# liseré papier 2 px.
	if s == KitStates.State.HOVER or s == KitStates.State.FOCUS or s == KitStates.State.PRESSED:
		var outline := _hex_points(center, d + 6.0)
		var outline_closed := PackedVector2Array()
		for p in outline:
			outline_closed.append(p)
		outline_closed.append(outline[0])
		draw_polyline(outline_closed, Comic.TEXT, 2.0)
	if s == KitStates.State.FOCUS or s == KitStates.State.PRESSED:
		var x := center.x - d * 0.5 - 22.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, center.y - 9.0), Vector2(x + 14.0, center.y), Vector2(x, center.y + 9.0)]), Comic.BRUSH)

	# Onglet de touche (épingle 02) : pastille pinceau en bas à gauche du
	# rect du composant, Ø 30 px.
	var tab_c := Vector2(KEY_TAB_DIAMETER * 0.55, d - KEY_TAB_DIAMETER * 0.25)
	draw_circle(tab_c, KEY_TAB_DIAMETER * 0.5, Comic.BRUSH)
	draw_arc(tab_c, KEY_TAB_DIAMETER * 0.5, 0.0, TAU, 24, Comic.HARD_SHADOW_COLOR, 1.5, true)
	KitStates.draw_centered_string(self, Comic.FONT_NUMBER, tab_c, key_label, Comic.SIZE_FLOOR, Comic.TEXT_ON_BRUSH)

	# Glyphe de capacité (abstrait — losange encre, jamais un pictogramme
	# figuratif hors périmètre de cette tâche) centré dans l'hexagone.
	var half := d * 0.16
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -half), center + Vector2(half, 0.0),
		center + Vector2(0.0, half), center + Vector2(-half, 0.0),
	]), glyph_color)


## Hachures 45° confinées au polygone hexagonal (§8.4 « Désactivé : charbon +
## hachures ») : `Geometry2D.clip_polyline_with_polygon` découpe chaque
## diagonale sur la silhouette réelle de l'hexagone — jamais un rectangle
## englobant, qui déborderait dans le fond transparent autour des pointes.
func _draw_hatch_hex(hex: PackedVector2Array) -> void:
	var min_x := hex[0].x
	var max_x := hex[0].x
	var min_y := hex[0].y
	var max_y := hex[0].y
	for p in hex:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	var diag := max_y - min_y
	var hatch_color := Comic.HARD_SHADOW_COLOR
	hatch_color.a = 0.25
	var step := 6.0
	var x := min_x - diag
	while x < max_x:
		var line := PackedVector2Array([Vector2(x, min_y), Vector2(x + diag, max_y)])
		var clipped: Array = Geometry2D.clip_polyline_with_polygon(line, hex)
		for seg in clipped:
			if (seg as PackedVector2Array).size() >= 2:
				draw_polyline(seg, hatch_color, 2.0)
		x += step
