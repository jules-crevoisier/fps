## KitCard.gd
## Kit de composants autocollant (ART-31, docs/STYLE_BIBLE.md §8.1/§8.2/§8.4)
## — famille « Autocollant », variante **carte** (§8.2 jeton `radius.sticker` :
## « cartes non inclinées : agents, armes » — contrairement à `KitSlantBar`,
## qui porte l'inclinaison à 12° des barres/boutons/onglets). Utilisée pour
## les cartes agent/carte/mode/arme/cosmétique (§8.1 Couche 2).
##
## Ses 9 états (§8.4, colonne « Autocollant (carte, CTA) ») :
##   Défaut       — couleur (agent/carte/mode), contour encre 3 px, ombre
##                  dure (6, 6).
##   Survol       — translation (−2, −2), ombre (8, 8), `Comic.DUR_FOCUS`.
##   Focus visible— liseré papier découpé 4 px + flèche ▶ pinceau à gauche.
##   Pressé       — translation (3, 3), ombre (3, 3), `Comic.DUR_PRESS`.
##   Sélectionné  — liseré papier découpé 4 px permanent + tampon « ✓ » encre.
##   Désactivé    — désaturé à 30 %, ombre (2, 2), cadenas + RAISON (jamais
##                  vide, CHK-37).
##   Chargement   — squelette : `panel_hi` sans ombre, pulsation d'opacité
##                  0,6–1 à 1 Hz (aucune pulsation en mouvement réduit).
##   Vide         — autocollant pointillé `papier.dim`, glyphe « + ».
##   Erreur       — tampon encre « RATÉ » incliné −8°.
##
## `extends BaseButton` : survol/focus/pression/désactivé/infobulle natifs du
## moteur (CHK-37), tout le rendu vient de `_draw()`. `state_override`
## (KitStates.State, -1 = auto) force l'état pour la galerie statique —
## voir KitStates.gd.
class_name KitCard
extends BaseButton

const DEFAULT_SIZE := Vector2(220.0, 140.0)
## Pulsation du squelette de chargement — 1 Hz, amplitude 0,6–1 (STYLE_BIBLE
## v3 §8.4 « Chargement »), jamais en mouvement réduit (tokens.json
## "reduced_motion.forbid": pulse).
const SKELETON_HZ := 1.0
const SKELETON_MIN_ALPHA := 0.6
const SKELETON_MAX_ALPHA := 1.0

@export var card_title: String = "":
	set(v):
		card_title = v
		if _title_label:
			_title_label.text = card_title.to_upper()
## Couleur-clé (agent/carte/mode/arme) — jamais dans le HUD de combat
## (STYLE_BIBLE v3 §8.3), réservée aux menus.
@export var accent_color: Color = Comic.BRUSH:
	set(v):
		accent_color = v
		queue_redraw()
@export var disabled_reason: String = "":
	set(v):
		disabled_reason = v
		_refresh()
@export var selected: bool = false:
	set(v):
		selected = v
		_refresh()
@export var loading: bool = false:
	set(v):
		loading = v
		_skeleton_t = 0.0
		_refresh()
@export var empty: bool = false:
	set(v):
		empty = v
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
var _shadow_off := Comic.SHADOW_HARD_OFFSET
var _translate := Vector2.ZERO
var _shadow_tween: Tween
var _skeleton_t := 0.0
var _title_label: Label
var _reason_label: Label
var _last_state := -1


func _ready() -> void:
	custom_minimum_size = DEFAULT_SIZE
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

	_title_label = Comic.title_label(card_title, Comic.SIZE_SUBTITLE, Comic.TEXT_ON_BRUSH)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_title_label.clip_text = true
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
	if empty:
		return KitStates.State.EMPTY
	if loading:
		return KitStates.State.LOADING
	if disabled:
		return KitStates.State.DISABLED
	if selected:
		return KitStates.State.SELECTED
	if _held:
		return KitStates.State.PRESSED
	if has_focus():
		return KitStates.State.FOCUS
	if is_hovered():
		return KitStates.State.HOVER
	return KitStates.State.DEFAULT


func _process(delta: float) -> void:
	if current_state() != KitStates.State.LOADING:
		set_process(false)
		return
	if Comic.reduced_motion():
		modulate.a = 0.8
		set_process(false)
		return
	_skeleton_t += delta
	var phase := sin(_skeleton_t * TAU * SKELETON_HZ) * 0.5 + 0.5
	modulate.a = lerpf(SKELETON_MIN_ALPHA, SKELETON_MAX_ALPHA, phase)


func _refresh() -> void:
	if _title_label == null or not is_inside_tree():
		return
	var s := current_state()
	tooltip_text = disabled_reason if (s == KitStates.State.DISABLED and disabled_reason != "") else ""

	modulate.a = 1.0
	_title_label.visible = s != KitStates.State.EMPTY and s != KitStates.State.LOADING
	_title_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_title_label.offset_left = Comic.SP_2
	_title_label.offset_right = -Comic.SP_2
	_title_label.offset_top = -(Comic.SIZE_SUBTITLE + Comic.SP_2)
	_title_label.offset_bottom = -Comic.SP_1

	_reason_label.visible = s == KitStates.State.DISABLED
	if _reason_label.visible:
		_reason_label.text = disabled_reason if disabled_reason != "" else KitStates.DEFAULT_DISABLED_REASON
		# Sous la carte (hors de son rect, `clip_contents=false` l'autorise) —
		# une légende de raison, jamais tronquée ni cachée sous le titre.
		_reason_label.position = Vector2(0.0, size.y + Comic.SP_1)
		_reason_label.size = Vector2(size.x, Comic.SIZE_FLOOR + Comic.SP_1)

	set_process(s == KitStates.State.LOADING)
	if s != KitStates.State.LOADING:
		modulate.a = 1.0

	var target_shadow := Comic.SHADOW_HARD_OFFSET
	var target_translate := Vector2.ZERO
	var anim_dur := Comic.DUR_FOCUS
	match s:
		KitStates.State.HOVER:
			target_shadow = Comic.SHADOW_HOVER_OFFSET
			target_translate = Comic.SHADOW_HOVER_TRANSLATE
			anim_dur = Comic.DUR_FOCUS
		KitStates.State.PRESSED:
			target_shadow = Comic.SHADOW_PRESSED_OFFSET
			target_translate = Comic.SHADOW_PRESSED_TRANSLATE
			anim_dur = Comic.DUR_PRESS
		KitStates.State.DISABLED:
			target_shadow = Vector2(2.0, 2.0)
			anim_dur = Comic.DUR_FOCUS
		KitStates.State.LOADING, KitStates.State.EMPTY:
			target_shadow = Vector2.ZERO
			anim_dur = Comic.DUR_FOCUS
	_animate_shadow(target_shadow, target_translate, anim_dur, s)
	_last_state = s
	queue_redraw()


func _animate_shadow(target_shadow: Vector2, target_translate: Vector2, dur: float, s: int) -> void:
	if Comic.reduced_motion() or s == _last_state:
		_shadow_off = target_shadow
		_translate = target_translate
		queue_redraw()
		return
	if _shadow_tween and _shadow_tween.is_valid():
		_shadow_tween.kill()
	_shadow_tween = create_tween()
	_shadow_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_shadow_tween.set_parallel(true)
	_shadow_tween.tween_method(_set_shadow_off, _shadow_off, target_shadow, dur)
	_shadow_tween.tween_method(_set_translate, _translate, target_translate, dur)


func _set_shadow_off(v: Vector2) -> void:
	_shadow_off = v
	queue_redraw()


func _set_translate(v: Vector2) -> void:
	_translate = v
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var s := current_state()
	var body_rect := Rect2(_translate, size)
	var radius := Comic.RADIUS_STICKER

	if s == KitStates.State.EMPTY:
		_draw_dashed_rounded_rect(body_rect, radius, Comic.TEXT_DIM, 2.0)
		_draw_plus_glyph(body_rect.get_center(), Comic.TEXT_DIM)
		return

	# Ombre dure opaque (jamais un flou natif — CHK-38) : un aplat encre
	# décalé sous le corps, seulement si l'état en réclame une.
	if _shadow_off != Vector2.ZERO:
		var shadow_rect := Rect2(_translate + _shadow_off, size)
		draw_style_box(Comic.hard_shadow_style(radius), shadow_rect)

	var fill := accent_color
	if s == KitStates.State.LOADING:
		fill = Comic.PANEL_HI
	elif s == KitStates.State.DISABLED:
		fill = Color.from_hsv(accent_color.h, accent_color.s * 0.3, accent_color.v, accent_color.a)

	var body_style := Comic.panel_style(fill, Comic.HARD_SHADOW_COLOR, radius, Comic.STROKE_STICKER)
	body_style.content_margin_left = 0
	body_style.content_margin_right = 0
	body_style.content_margin_top = 0
	body_style.content_margin_bottom = 0
	draw_style_box(body_style, body_rect)

	if s == KitStates.State.SELECTED or s == KitStates.State.FOCUS:
		_draw_diecut_border(body_rect, radius)
	if s == KitStates.State.SELECTED:
		_draw_check_stamp(body_rect)
	if s == KitStates.State.FOCUS:
		_draw_focus_arrow(body_rect)
	if s == KitStates.State.DISABLED:
		_draw_lock(body_rect)
	if s == KitStates.State.ERROR:
		_draw_error_stamp(body_rect)


## Liseré papier « découpé » (§8.2 `stroke.diecut` 4 px) à l'EXTÉRIEUR du
## contour d'encre — jamais un second panneau imbriqué, juste un trait.
func _draw_diecut_border(body_rect: Rect2, radius: int) -> void:
	var expand := Comic.STROKE_STICKER + Comic.STROKE_DIECUT * 0.5
	var r := body_rect.grow(expand)
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(Comic.STROKE_DIECUT)
	style.border_color = Comic.TEXT
	style.set_corner_radius_all(radius + int(expand))
	style.anti_aliasing = true
	draw_style_box(style, r)


func _draw_check_stamp(body_rect: Rect2) -> void:
	var center := body_rect.position + Vector2(body_rect.size.x - 20.0, 20.0)
	KitStates.draw_centered_string(self, Comic.FONT_NUMBER, center, "✓", Comic.SIZE_SUBTITLE, Comic.HARD_SHADOW_COLOR)


func _draw_focus_arrow(body_rect: Rect2) -> void:
	var cy := body_rect.position.y + body_rect.size.y * 0.5
	var x := body_rect.position.x - 22.0
	var pts := PackedVector2Array([Vector2(x, cy - 9.0), Vector2(x + 14.0, cy), Vector2(x, cy + 9.0)])
	draw_colored_polygon(pts, Comic.BRUSH)


## Cadenas vectoriel — jamais un émoji (règle globale « pas d'ensemble d'icônes
## emoji ») : anse en arc + corps rectangulaire, en encre.
func _draw_lock(body_rect: Rect2) -> void:
	var c := body_rect.position + Vector2(body_rect.size.x - 26.0, body_rect.size.y - 30.0)
	var body := Rect2(c + Vector2(-9.0, 0.0), Vector2(18.0, 14.0))
	draw_arc(c, 8.0, PI, TAU, 16, Comic.HARD_SHADOW_COLOR, 3.0, true)
	draw_rect(body, Comic.HARD_SHADOW_COLOR, true)


## Tampon encre « RATÉ » incliné −8° (§8.4 « Erreur » — Autocollant) : rotation
## via `draw_set_transform`, jamais une image bitmap pré-inclinée.
func _draw_error_stamp(body_rect: Rect2) -> void:
	var center := body_rect.get_center()
	draw_set_transform(center, deg_to_rad(-8.0), Vector2.ONE)
	var text := "RATÉ"
	var font := Comic.title_font()
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Comic.SIZE_DISPLAY_SM)
	var stamp_rect := Rect2(-text_size * 0.5 - Vector2(Comic.SP_2, Comic.SP_1), text_size + Vector2(Comic.SP_2, Comic.SP_1) * 2.0)
	draw_rect(stamp_rect, Comic.HARD_SHADOW_COLOR, false, 3.0)
	KitStates.draw_centered_string(self, font, Vector2.ZERO, text, Comic.SIZE_DISPLAY_SM, Comic.HARD_SHADOW_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_plus_glyph(center: Vector2, color: Color) -> void:
	var half := 12.0
	draw_line(center + Vector2(-half, 0.0), center + Vector2(half, 0.0), color, 3.0)
	draw_line(center + Vector2(0.0, -half), center + Vector2(0.0, half), color, 3.0)


func _draw_dashed_rounded_rect(r: Rect2, radius: int, color: Color, width: float) -> void:
	# `draw_dashed_line` ne gère pas les coins arrondis : on approxime le
	# contour du rectangle par un polygone à coins coupés puis on trace
	# chaque segment en pointillé (assez proche visuellement à ce rayon).
	var cut := float(radius)
	var p := r.position
	var s := r.size
	var pts := PackedVector2Array([
		Vector2(p.x + cut, p.y), Vector2(p.x + s.x - cut, p.y),
		Vector2(p.x + s.x, p.y + cut), Vector2(p.x + s.x, p.y + s.y - cut),
		Vector2(p.x + s.x - cut, p.y + s.y), Vector2(p.x + cut, p.y + s.y),
		Vector2(p.x, p.y + s.y - cut), Vector2(p.x, p.y + cut),
	])
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		draw_dashed_line(a, b, color, width, 6.0)


# ==============================================================================
#  v4 « Encre, jaune, italique » (UX-33, docs/UI_DIRECTION_BL3.md §6/§9) :
#  ligne de kit PARTAGÉE par l'écran de sélection d'agent (colonne de droite,
#  5 lignes : passif + 3 aptitudes + ultime) et le menu Agents (AgentMenu.gd)
#  -- remplace les deux méthodes statiques `_ability_row` dupliquées qui
#  existaient séparément dans ces deux écrans avant cette tranche (icône seule
#  + texte, v3).
# ==============================================================================

## Tuile d'icône (icône + touche) d'une ligne de kit -- 64 px (§6 « tuile
## 64 »), plus petite que les tuiles de capacités du HUD (hors périmètre ici)
## puisqu'elle n'est qu'INFORMATIVE : jamais interactive à elle seule (c'est
## la LIGNE entière, retournée par `ability_row_v4`, qui porte le focus/survol).
const KIT_TILE_PX := 64.0

## Budget de largeur (px 1080p) que la colonne de texte d'une ligne de kit
## DOIT garantir à son nom (37 px, capitales) -- §9 « risque honnête » :
## « ÉBLOUISSEMENT » (Vif, aptitude Q) en 37 px ≈ 250 px, testé contre ce
## budget par tests/ui/test_agent_select_v4.gd. Les appelants (AgentSelectScreen,
## AgentMenu) réservent au moins cette largeur à la colonne de texte.
const KIT_NAME_COLUMN_MIN_PX := 360.0

## Ligne "kit" v4 : icône penchée (`KitSlantTile`, réutilisée telle quelle,
## purement décorative ici -- `focus_mode`/`mouse_filter` neutralisés, c'est
## la ligne entière qui est focusable) + touche + nom 37 (+ tag court, ex.
## "PASSIF" / "ULTIME · N POINTS") + description À UNE LIGNE 28, jamais de
## retour à la ligne qui décalerait les lignes suivantes (§6 « kit en 5
## lignes »). Le texte COMPLET de la description apparaît en info-bulle à la
## fois à la souris (tooltip natif Godot, `tooltip_text`) et au clavier/
## manette (§9 « le texte long d'une aptitude passe en info-bulle au focus » —
## le tooltip natif ne réagit qu'à la souris, d'où le label `tip` géré ici en
## plus, sur `focus_entered`/`focus_exited`, même patron que les labels de
## raison positionnés par état ailleurs dans ce fichier/KitSlantTile.gd).
##
## `icon` peut être `null` (planche pas encore livrée) : la tuile garde sa
## mise en page, juste sans TextureRect superposé -- jamais une case vide
## marquée autrement. `key_label` vide (passif, jamais de touche) : la tuile
## n'affiche alors aucune lettre de touche.
static func ability_row_v4(icon: Texture2D, key_label: String, title: String, tag: String,
		description: String, is_ultimate: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Comic.SP_3)
	row.custom_minimum_size = Vector2(0.0, KIT_TILE_PX)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.focus_mode = Control.FOCUS_ALL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = description

	var tile := KitSlantTile.new()
	tile.custom_minimum_size = Vector2(KIT_TILE_PX, KIT_TILE_PX)
	tile.key_label = key_label
	tile.focus_mode = Control.FOCUS_NONE
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_ultimate:
		# §4.6 « choisi : fond signal » -- réutilisé ici pour marquer l'ultime
		# (seule ligne "prête à agir" du kit), jamais pour une aptitude normale.
		tile.accent_color = Comic.SIGNAL
		tile.state_override = KitStates.State.SELECTED
	row.add_child(tile)
	if icon:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon
		# Plein rect de la tuile (`tile` n'est pas un Container -- ancrage
		# PRESET_FULL_RECT, jamais un `custom_minimum_size`/offset manuel qui se
		# figerait à la taille de CE frame, voir Comic.anchor()) : `KEEP_ASPECT_
		# CENTERED` recentre et met à l'échelle le picto DEDANS tout seul.
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		Comic.anchor(icon_rect, Control.PRESET_FULL_RECT)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(icon_rect)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 0)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_box)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", Comic.SP_2)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(name_row)
	var accent := Comic.SIGNAL if is_ultimate else Comic.paper_color()
	name_row.add_child(Comic.title_label_v4(title, Comic.SIZE_37, accent))
	if tag != "":
		name_row.add_child(Comic.meta_label_v4(
			tag, Comic.SIZE_21, Comic.SIGNAL if is_ultimate else Comic.paper_dim_color()))

	# Description À UNE LIGNE (§6), tronquée « … » plutôt qu'un retour à la
	# ligne. PIÈGE Godot (constaté en capture, UX-33) : `Control.custom_
	# minimum_size` est un PLANCHER (`get_combined_minimum_size` = max(naturel,
	# custom)), jamais un plafond -- `clip_text` seul (rendu uniquement)
	# laisse donc `get_minimum_size()` à la largeur NATURELLE du texte
	# COMPLET, qui pousse toute la chaîne de conteneurs parents plus large que
	# l'écran au lieu d'être tronquée dans sa ligne. `text_overrun_behavior`
	# (contrairement à `clip_text`) fait explicitement redescendre cette
	# largeur naturelle -- c'est lui qui rend la ligne compressible.
	var desc := Comic.body_label_v4(description, Comic.SIZE_28, Comic.paper_dim_color())
	desc.clip_text = true
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(desc)

	# Bulle "texte complet" (§9) -- cachée par défaut, révélée à la souris ET
	# au clavier/manette ci-dessous ; un `VBoxContainer` EXCLUT un enfant
	# invisible de son calcul de taille minimale (Godot), donc `row` ne
	# grandit QUE quand `tip` est visible (aucun coût de mise en page sinon).
	var tip := Comic.body_label_v4(description, Comic.SIZE_28, Comic.paper_color())
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	text_box.add_child(tip)

	row.mouse_entered.connect(func(): tip.visible = true)
	row.mouse_exited.connect(func(): tip.visible = false)
	row.focus_entered.connect(func(): tip.visible = true)
	row.focus_exited.connect(func(): tip.visible = false)
	return row
