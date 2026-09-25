## UiKitGallery.gd
## Galerie de démonstration du kit de composants autocollant (ART-31,
## docs/STYLE_BIBLE.md §8.2/§8.4) — `scenes/dev/ui_kit_gallery.tscn`. Capturée
## en 1920×1080 et 1280×720 comme n'importe quel écran autonome de
## `tools/review/ui_shots.gd::_load_ui_kit_gallery` (mêmes deux résolutions —
## voir sa docstring). Montre chaque famille (Charbon/Autocollant/Hexagone)
## dans ses 9 états (§8.4), plus la Couche 3 « Trame » (halftone).
##
## Discipline du pinceau (STYLE_BIBLE v3 §8.1 règle 1, CHK-36 : « 1 bandeau de
## titre + au plus 3 bandeaux de section ») : exactement 1 `BrushHeader` de
## titre + 3 de section (Charbon / Autocollant / Hexagone) — les sous-groupes
## de la section Autocollant (carte, barre inclinée, bulle, trame) utilisent
## `Comic.bullet_row` (un simple libellé à puce), jamais un second bandeau
## pinceau.
##
## Chaque composant du kit est instancié une fois par état avec
## `state_override` forcé (KitStates.State) : `ui_shots` ne bouge ni la souris
## ni le focus manette, la galerie ne peut donc pas compter sur une survol/
## focus/pression RÉELS pour montrer ces états — voir KitStates.gd.
extends Control

const SAMPLE_DISABLED_REASON := "3 200 cr requis"  # STYLE_BIBLE v3 §8.4, exemple donné par la table.

## Réserve à droite des bandeaux UNIQUEMENT (pas des cartes/lignes, qui n'ont
## rien à cacher) : la galerie loge ses bandeaux dans un `ScrollContainer`
## dont la scrollbar verticale flotte SUR le contenu plutôt que de lui
## céder de la place (mesuré : bandeau plein-largeur -> les 64 px de la queue
## sèche (`BrushHeader.tail_px`) tombent en partie sous le rail de la
## scrollbar et en partie hors du rectangle de clip du ScrollContainer —
## la queue en devient quasi invisible, capture ou pas). `Comic.SP_5` (36 px)
## au-delà de `tail_px` laisse une marge confortable après la scrollbar
## flottante (mesurée à 10 px de large en 1920×1080) sans dépendre de sa
## largeur exacte, qui vient du thème par défaut du moteur.
const _HEADER_SCROLLBAR_CLEARANCE := Comic.SP_5

var _scroll: ScrollContainer
var _list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Comic.BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_scroll = ScrollContainer.new()
	Comic.anchor(_scroll, Control.PRESET_FULL_RECT)
	_scroll.offset_left = Comic.SAFE_MARGIN
	_scroll.offset_right = -Comic.SAFE_MARGIN
	_scroll.offset_top = Comic.SAFE_MARGIN
	_scroll.offset_bottom = -Comic.SAFE_MARGIN
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", Comic.SP_6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	_add_header("Kit UI — composants autocollant")

	# v4 « Encre, jaune, italique » (UX-30, direction VALIDÉE 2026-09-25) EN
	# PREMIER : c'est elle que `tools/review/ui_shots.gd` capture au repos
	# (le ScrollContainer démarre en haut) — les sections v3 ci-dessous
	# restent affichées, pour mémoire, tant que UX-31..35 n'ont pas converti
	# les écrans qui les consomment encore.
	_build_v4_section()
	_build_charbon_section()
	_build_autocollant_section()
	_build_hexagon_section()


## Ajoute un `BrushHeader` (titre ou section) à `_list` en réservant
## `_HEADER_SCROLLBAR_CLEARANCE` de plus que sa queue sèche sur sa droite —
## voir la docstring de la constante. Les autres composants de la galerie
## (cartes, lignes, hexagones) passent par `_list.add_child` directement :
## ils ne dessinent rien hors de leur propre rect, donc rien à réserver.
func _add_header(text: String) -> void:
	var header := BrushHeader.new()
	header.title = text
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_right", int(header.tail_px + _HEADER_SCROLLBAR_CLEARANCE))
	wrap.add_child(header)
	_list.add_child(wrap)


# ==========================================================================
#  Couche 1 — Charbon
# ==========================================================================
func _build_charbon_section() -> void:
	_add_header("Charbon — liste, réglage")

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Comic.SP_2)
	_list.add_child(col)

	for state in KitStates.ALL_STATES:
		var row := KitCharbonRow.new()
		row.label_text = KitStates.label_for(state)
		row.value_text = "42"
		row.disabled_reason = SAMPLE_DISABLED_REASON
		row.error_code = "ERR_502"
		row.empty_prompt = "Aucun ami en ligne"
		row.empty_action = "INVITER"
		row.state_override = state
		if state == KitStates.State.SELECTED:
			row.selected = true  # illustre aussi le drapeau réel, pas seulement l'aperçu forcé.
		col.add_child(row)


# ==========================================================================
#  Couche 2 — Autocollant (carte / barre inclinée / bulle / trame)
# ==========================================================================
func _build_autocollant_section() -> void:
	_add_header("Autocollant — carte, barre, bulle")

	_list.add_child(Comic.bullet_row("CARTE"))
	_list.add_child(_grid_of(func(state: int) -> Control: return _make_card(state)))

	_list.add_child(Comic.bullet_row("BARRE INCLINÉE"))
	_list.add_child(_grid_of(func(state: int) -> Control: return _make_slant_bar(state)))

	_list.add_child(Comic.bullet_row("BULLE"))
	_list.add_child(_grid_of(func(state: int) -> Control: return _make_bubble(state)))

	_list.add_child(Comic.bullet_row("TRAME (MOMENT — capture figée à mi-révélation)"))
	_list.add_child(_build_trame_row())


func _make_card(state: int) -> Control:
	var c := KitCard.new()
	c.card_title = "Vif"
	c.accent_color = Comic.BRUSH
	c.disabled_reason = SAMPLE_DISABLED_REASON
	c.error_text = "raté" if state == KitStates.State.ERROR else ""
	c.state_override = state
	if state == KitStates.State.SELECTED:
		c.selected = true
	return c


func _make_slant_bar(state: int) -> Control:
	var b := KitSlantBar.new()
	b.bar_text = "JOUER"
	b.accent_color = Comic.BRUSH
	b.disabled_reason = SAMPLE_DISABLED_REASON
	b.error_text = "raté" if state == KitStates.State.ERROR else ""
	b.state_override = state
	if state == KitStates.State.SELECTED:
		b.selected = true
	return b


func _make_bubble(state: int) -> Control:
	var b := KitBubble.new()
	b.glyph_text = "!"
	b.disabled_reason = SAMPLE_DISABLED_REASON
	b.error_text = "raté" if state == KitStates.State.ERROR else ""
	b.state_override = state
	if state == KitStates.State.SELECTED:
		b.selected = true
	return b


## Trame figée PLEINEMENT révélée, variante **pinceau** (pas le repli encre
## 18 % par défaut du composant) : sur un fond `panel` déjà sombre, l'encre à
## 18 % est quasi invisible en capture statique (fidèle au jeton — c'est
## voulu EN JEU, où la trame se pose sur des fonds variés et reste discrète) ;
## la galerie a besoin de PROUVER visuellement le motif de points au lecteur
## de la capture, donc `ink_variant = false` ici uniquement. `play()` anime
## normalement en jeu (voir KitTrame.gd) ; la galerie force juste l'image
## d'un instant du moment.
func _build_trame_row() -> Control:
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(0.0, 160.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Comic.PANEL
	bg.set_corner_radius_all(Comic.PANEL_RADIUS)
	wrap.add_theme_stylebox_override("panel", bg)

	var trame := KitTrame.new()
	trame.ink_variant = false
	trame.preview_reveal = 1.0
	trame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(trame)

	var caption := Comic.label("encre 18 % (défaut) : quasi invisible sur charbon, c'est voulu — variante pinceau montrée ici pour la preuve visuelle", Comic.SIZE_FLOOR, Comic.TEXT_DIM, Comic.FONT_LABEL)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -Comic.SP_1 - Comic.SIZE_FLOOR
	caption.offset_left = Comic.SP_2
	caption.offset_right = -Comic.SP_2
	wrap.add_child(caption)
	return wrap


# ==========================================================================
#  Couche 2 (HUD) — Hexagone
# ==========================================================================
func _build_hexagon_section() -> void:
	_add_header("Hexagone — capacité")
	_list.add_child(_grid_of(func(state: int) -> Control: return _make_hexagon(state)))


func _make_hexagon(state: int) -> Control:
	if state in KitStates.HEXAGON_NA_STATES:
		var na := Comic.label("—", Comic.SIZE_DISPLAY_SM, Comic.TEXT_DIM)
		na.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		na.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		na.custom_minimum_size = Vector2(Comic.HEX_MENU_PX, Comic.HEX_MENU_PX)
		return na
	var h := KitHexagon.new()
	# "E", pas "Q" : au plancher `SIZE_FLOOR` (21 px) dans la pastille Ø 30 px,
	# le petit jambage du Q de Barlow Condensed ExtraBold est trop discret et
	# se lit comme un 0/O — un choix de lettre-témoin, pas un défaut du
	# composant (il affiche fidèlement le texte qu'on lui passe).
	h.key_label = "E"
	h.ability_title = "Voile"
	h.ready_state = true
	h.disabled_reason = SAMPLE_DISABLED_REASON
	h.error_text = "raté" if state == KitStates.State.ERROR else ""
	h.state_override = state
	return h


# ==========================================================================
#  Disposition partagée : grille 3 colonnes, une cellule = légende d'état +
#  instance (ou « — » quand l'état ne s'applique pas, ex. Hexagone).
# ==========================================================================
func _grid_of(factory: Callable) -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", Comic.SP_5)
	grid.add_theme_constant_override("v_separation", Comic.SP_5)
	for state in KitStates.ALL_STATES:
		grid.add_child(_state_cell(KitStates.label_for(state), factory.call(state)))
	return grid


func _state_cell(caption: String, node: Control) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_1)
	var lbl := Comic.label(caption, Comic.SIZE_FLOOR, Comic.TEXT_DIM, Comic.FONT_LABEL)
	v.add_child(lbl)
	var center := CenterContainer.new()
	center.add_child(node)
	v.add_child(center)
	return v


# ==========================================================================
#  v4 « Encre, jaune, italique » (UX-30, docs/UI_DIRECTION_BL3.md, fondations
#  AVANT les écrans — UX-31..35 en dépendent). Section AJOUTÉE à la galerie
#  v3 ci-dessus (INCHANGÉE) : plaque à coins coupés, tuile penchée (6 états
#  du contrat, pas les 9 de KitStates), swash (UN SEUL pour tout cet écran,
#  règle « 1 par écran »), échelle typo complète, texte encré sur fond clair
#  ET sombre.
# ==========================================================================
func _build_v4_section() -> void:
	_add_header_v4("UI v4 — Encre, jaune, italique")

	_list.add_child(Comic.bullet_row("PLAQUE — COINS COUPÉS"))
	_list.add_child(_build_plate_row())

	_list.add_child(Comic.bullet_row("TUILE PENCHÉE — 6 ÉTATS"))
	_list.add_child(_grid_of_tile_states())

	_list.add_child(Comic.bullet_row("SWASH — TITRE CHOISI (1 SEUL SUR CET ÉCRAN)"))
	_list.add_child(_build_swash_row())

	_list.add_child(Comic.bullet_row("ÉCHELLE TYPO — 21 / 28 / 37 / 50 / 66 / 88 / 118 / 157"))
	_list.add_child(_build_type_scale_column())

	_list.add_child(Comic.bullet_row("TEXTE ENCRÉ — FOND CLAIR ET FOND SOMBRE"))
	_list.add_child(_build_ink_on_light_and_dark_row())


## En-tête de section v4 — `ink_label()` plutôt que `BrushHeader` (le
## bandeau pinceau rouge est un jeton v3 ; v4 ne l'utilise plus, voir
## UI_DIRECTION_BL3.md §1 « rejeté : les bandeaux rouges supprimés »).
func _add_header_v4(text: String) -> void:
	var header := Comic.title_label_v4(text, Comic.SIZE_50)
	_list.add_child(header)


## Plaque v4 : `Comic.plate_style()` (coins coupés 16 px haut-droit +
## bas-gauche, radius 0 ailleurs, AUCUN trait) + ombre dure portée en enfant,
## comme toute plaque de menu.
func _build_plate_row() -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(360.0, 160.0)

	var shadow := Panel.new()
	shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shadow.position = Comic.SHADOW_HARD_OFFSET
	shadow.add_theme_stylebox_override("panel", _chamfered_shadow_style())
	wrap.add_child(shadow)

	var plate := PanelContainer.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.offset_right -= Comic.SHADOW_HARD_OFFSET.x
	plate.offset_bottom -= Comic.SHADOW_HARD_OFFSET.y
	plate.add_theme_stylebox_override("panel", Comic.plate_style())
	wrap.add_child(plate)

	var caption := Comic.ink_label("07 · WASTELAND", Comic.SIZE_37, Comic.TEXT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	plate.add_child(caption)
	return wrap


## Ombre dure aux MÊMES coins coupés que la plaque qu'elle porte (sinon
## l'ombre carrée dépasserait visiblement des coins tranchés de la plaque).
func _chamfered_shadow_style() -> StyleBoxFlat:
	var s := Comic.hard_shadow_style()
	s.corner_radius_top_left = 0
	s.corner_radius_top_right = Comic.CHAMFER_PX
	s.corner_radius_bottom_right = 0
	s.corner_radius_bottom_left = Comic.CHAMFER_PX
	s.corner_detail = 1
	return s


## Grille 3 colonnes des 6 états `KitSlantTile.TILE_STATES` (pas les 9 de
## `KitStates.ALL_STATES` — cette tuile n'a ni loading, ni empty, ni error,
## voir sa docstring).
func _grid_of_tile_states() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", Comic.SP_5)
	grid.add_theme_constant_override("v_separation", Comic.SP_5)
	for state in KitSlantTile.TILE_STATES:
		grid.add_child(_state_cell(KitStates.label_for(state), _make_slant_tile(state)))
	return grid


func _make_slant_tile(state: int) -> Control:
	var t := KitSlantTile.new()
	t.key_label = "E"
	t.tile_title = "Voile"
	t.accent_color = Comic.SIGNAL
	t.disabled_reason = SAMPLE_DISABLED_REASON
	t.state_override = state
	if state == KitStates.State.SELECTED:
		t.selected = true
	return t


## Swash — UN SEUL sur tout cet écran (règle « 1 par écran », tokens.json
## shape.swash.max_per_screen) : le titre choisi de la démonstration.
func _build_swash_row() -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", Comic.SP_2)
	wrap.add_theme_constant_override("margin_bottom", Comic.SP_2)
	var title := Comic.title_label_v4("VIF", Comic.SIZE_88, Comic.HARD_SHADOW_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wrap.add_child(KitSwash.wrap(title))
	return wrap


## Un échantillon par cran de l'échelle 21/28/37/50/66/88/118/157 —
## `ink_label()` (texte encré, zéro fond) à chaque taille, sur le fond
## charbon de la galerie.
func _build_type_scale_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Comic.SP_2)
	var steps := [
		Comic.SIZE_21, Comic.SIZE_28, Comic.SIZE_37, Comic.SIZE_50,
		Comic.SIZE_66, Comic.SIZE_88, Comic.SIZE_118, Comic.SIZE_157,
	]
	for px in steps:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Comic.SP_3)
		var tag := Comic.label("%d px" % px, Comic.SIZE_FLOOR, Comic.TEXT_DIM, Comic.FONT_LABEL)
		tag.custom_minimum_size = Vector2(80.0, 0.0)
		row.add_child(tag)
		row.add_child(Comic.ink_label("Aa Bb 12", px, Comic.TEXT))
		col.add_child(row)
	return col


## Preuve visuelle CHK-32/33 : le MÊME `ink_label()` (fond `paper`, contour
## `ink` + ombre dure) reste lisible posé sur un fond clair ET sur un fond
## sombre — la lisibilité vient de l'encre, jamais d'un panneau derrière
## (UI_DIRECTION_BL3.md §5 règle 1).
func _build_ink_on_light_and_dark_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Comic.SP_5)

	row.add_child(_ink_sample_panel("FOND CLAIR", Comic.paper_color()))
	row.add_child(_ink_sample_panel("FOND SOMBRE", Comic.plate_color()))
	return row


func _ink_sample_panel(caption: String, bg: Color) -> Control:
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(320.0, 120.0)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(0)
	wrap.add_theme_stylebox_override("panel", style)

	var center := CenterContainer.new()
	center.add_child(Comic.ink_label(caption, Comic.SIZE_37, Comic.TEXT))
	wrap.add_child(center)
	return wrap
