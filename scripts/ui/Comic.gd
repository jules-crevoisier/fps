## Comic.gd
## Boîte à outils direction artistique v3 « Bric-à-brac peint »
## (docs/STYLE_BIBLE.md §8, verrouillé ; jetons machine docs/style/tokens.json) :
## tokens (couleurs, espacement, échelle typo, formes, ombres dures, durées)
## et fabriques (StyleBox, Label, textures de hachures) partagés par tout le
## HUD et les menus. v3 reprend la structure v2 « Peint au soleil, encré gras »
## (pages/panneaux charcoal, bandeau pinceau rouge, titres italiques capitales,
## labels à puce rouge) et resserre les jetons sur tokens.json : neutres
## réchauffés (abandon des gris froids `#101113…`), vraies coupes italiques
## Barlow (fin du faux italique généralisé), Bangers remplace Protest
## Revolution. Voir BrushHeader.gd (bandeau pinceau), ComicPanel.gd (panneau
## charcoal), ComicBar.gd/ComicChip.gd (HUD).
class_name Comic
extends RefCounted

# ------------------------------------------------------------ Surfaces (tokens.json color.charbon,
# STYLE_BIBLE v3 §8.2 : neutres teintés chaud, h ≈ 55-60°, C ≤ 0,02 — les gris
# froids de v2 (`#101113`…) sont abandonnés).
const BG := Color("14110F")
const PANEL := Color("1E1A17")
const PANEL_HI := Color("2A2521")
const RULE := Color("3A332D")

# ------------------------------------------------------------ Texte (tokens.json color.papier)
const TEXT := Color("F4EDE1")          # 14.9:1 sur `panel`
const TEXT_DIM := Color("B3AA9E")      # 7.5:1
const DISABLED := Color("726A60")      # 3.25:1

# ------------------------------------------------------------ Pinceau (brand / vie basse)
const BRUSH := Color("c8242c")
const PRESSED := Color("9e1c22")
const BULLET := Color("e23b33")        # 4.0:1
## Texte posé DIRECTEMENT sur `brush`/`pressed` (bandeau pinceau, boutons
## pleins rouge) : blanc pur, pas `TEXT` (#F4EDE1, légèrement chaud) — design.md
## §11 « white text on it 5.6:1 » mesure spécifiquement le blanc pur.
const TEXT_ON_BRUSH := Color.WHITE

# ------------------------------------------------------------ Jeu
## Allié fixe (miroir de Cartoon.ally_color(), design.md §11 jeton `ally`).
const ALLY := Color("3b8bff")          # 5.2:1
## Ennemi : Magenta (défaut) / Citron — voir `enemy_color()`, suit
## Settings.enemy_color (miroir de Cartoon.enemy_color()).
const ENEMY_MAGENTA := Color("ff3dc8") # 5.5:1
const ENEMY_CITRON := Color("c8ff1f")  # 14.6:1
const OBJECTIVE := Color("f2c230")
## Warning (jamais le rouge, réservé à la marque/vie basse — design.md §11
## "Red means brand or low HP; errors use a yellow ⚠").
const WARNING := OBJECTIVE

## Couleur ennemi courante (Settings.enemy_color : 0 Magenta, 1 Citron —
## design.md §9). Fonction (pas une constante) : suit le réglage joueur en
## direct, y compris dans les écrans qui n'ont pas encore de dépendance
## directe à Cartoon. Miroir exact de Cartoon.enemy_color() (ne PAS dupliquer
## la logique ailleurs).
static func enemy_color() -> Color:
	return Cartoon.enemy_color()

## Glyphe de camp (design.md §9 « jamais la couleur seule ») : ● allié, ▼ ennemi.
static func team_glyph(is_ally: bool) -> String:
	return "●" if is_ally else "▼"

## Allié/ennemi RELATIF au joueur local — JAMAIS par rapport à l'indice
## d'équipe brut (docs/research/04_ui_ux.md §2.3 « Couleurs relatives au
## joueur : allié et ennemi se calculent par rapport à l'équipe locale »).
## Un joueur en équipe 1 doit voir SES kills en Allié, pas ceux de l'équipe 0.
## `local_team < 0` (équipe locale inconnue — pas encore assignée par le
## serveur, spectateur) : personne n'est considéré allié, jamais une
## supposition par défaut sur l'équipe 0.
static func is_ally(team: int, local_team: int) -> bool:
	return local_team >= 0 and team == local_team

## `Control.set_anchors_preset()` seul NE remet PAS les 4 offsets à zéro : il
## les recalcule pour préserver le rect PIXEL actuel du nœud (souvent déjà
## non nul à cet instant), laissant des offsets énormes et invisibles sur les
## côtés qu'on ne fixe pas ensuite -> panneaux géants ou nuls. Toujours passer
## par ce helper (anchors + les 4 offsets à zéro), puis ne fixer QUE les
## offsets voulus par-dessus.
static func anchor(c: Control, preset: int) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0

# ------------------------------------------------------------ Espacement (grille de 6, design.md §11)
const SP_1 := 6
const SP_2 := 12
const SP_3 := 18
const SP_4 := 24
const SP_5 := 36
const SP_6 := 48
const SP_7 := 72
const SP_8 := 96
const SAFE_MARGIN := 48

# ------------------------------------------------------------ Formes (tokens.json shape,
# STYLE_BIBLE v3 §8.2 "Formes")
## Panneaux : radius 2, trait 1 px, jamais imbriqués.
const PANEL_RADIUS := 2
const RULE_W := 1
## Trait plus marqué (focus/emphase ponctuelle) — jamais utilisé pour
## imbriquer un second panneau, seulement pour une bordure d'accent.
const RULE_W_STRONG := 2
## Autocollants (cartes agent/carte/mode/arme, non inclinés) : radius 6.
const RADIUS_STICKER := 6
## Barres/boutons/onglets inclinés (couche 2 "autocollant", jamais un radius).
const RADIUS_SLANT := 0
## Contour d'encre d'un autocollant (3 px) et liseré papier découpé de l'état
## sélectionné, à l'EXTÉRIEUR de l'encre (4 px).
const STROKE_STICKER := 3
const STROKE_DIECUT := 4
## Une seule inclinaison, 12°, pour les formes (barres, boutons, onglets) —
## la même que `_ITALIC_SLANT` en cisaillement (STYLE_BIBLE v3 §8.1 règle 5).
const SLANT_DEG := 12
## Hexagones de capacité (pointe en haut) : Ø HUD 72 px (48 px à 720p), Ø menus
## 96 px ; onglet de touche en bas à gauche Ø 30 px.
const HEX_HUD_PX := 72
const HEX_HUD_PX_720 := 48
const HEX_MENU_PX := 96
const HEX_KEY_TAB_PX := 30
## Bandeau pinceau : NinePatch à 1,5x la hauteur du titre, fin sèche de 64 px
## à droite — la queue en « poisson » de v2 est supprimée (BrushHeader.gd, hors
## périmètre de cette tranche).
const BRUSH_HEIGHT_RATIO := 1.5
const BRUSH_DRY_TAIL_PX := 64
## Trame de points (couche 3 "célébrer" UNIQUEMENT — jamais permanente) : points
## de 4 px au pas de 8 px, 45°, encre à 18 % d'opacité.
const HALFTONE_DOT_PX := 4
const HALFTONE_PITCH_PX := 8
const HALFTONE_ANGLE_DEG := 45
const HALFTONE_INK_ALPHA := 0.18
## Cible tactile minimale (accessibilité, toutes plateformes).
const MIN_TAP_TARGET_PX := 44
## Décalage de l'anneau de focus autour du contrôle (`focus_style()`).
const FOCUS_RING_OFFSET_PX := 4.0

# ------------------------------------------------------------ Ombres dures (tokens.json
# shape.shadow, STYLE_BIBLE v3 §8.2 "shadow.hard" ; CHK-38 interdit tout
# `StyleBoxFlat.shadow_size` > 0 — le relief vient TOUJOURS d'un décalage
# opaque, jamais d'un flou natif. Voir `hard_shadow_style()`.)
## `encre` (tokens.json color.ink) : la seule quasi-noire de l'image, traits,
## texte sur fonds clairs ET ombres dures.
const HARD_SHADOW_COLOR := Color("1A1410")
const SHADOW_HARD_OFFSET := Vector2(6, 6)
## Chips et hexagones ≤ 72 px : ombre resserrée.
const SHADOW_HARD_SMALL_OFFSET := Vector2(3, 3)
const SHADOW_HOVER_OFFSET := Vector2(8, 8)
const SHADOW_HOVER_TRANSLATE := Vector2(-2, -2)
const SHADOW_PRESSED_OFFSET := Vector2(3, 3)
const SHADOW_PRESSED_TRANSLATE := Vector2(3, 3)

# ------------------------------------------------------------ Échelle typo (tokens.json type,
# STYLE_BIBLE v3 §8.2 "Échelle")
## Authored 1920x1080, ratio 1,25, base/plancher 21 px (le plancher de 21 px
## donne 14 px rendus à 720p — CHK-32). Le stretch canvas_items+expand remet à
## l'échelle automatiquement (1280x800 = ×0,667).
const SIZE_FLOOR := 21          # caption — légendes, touches, plancher absolu
const SIZE_BODY := 26           # phrases, killfeed
const SIZE_SUBTITLE := 33       # libellés importants, noms dans les listes
const SIZE_LABEL := 41          # label_lg — timer, onglets principaux
const SIZE_DISPLAY_SM := 51     # h3 — PV, titres de section
const SIZE_DISPLAY_MD := 64     # h2 — munitions, titre de page
const SIZE_DISPLAY_LG := 80     # h1 — nom d'agent, score de fin
const SIZE_DISPLAY_XL := 100    # display — VICTOIRE / DÉFAITE
const SIZE_DISPLAY_XXL := 125   # hero — logo, onomatopée de moment

# ------------------------------------------------------------ Polices (tokens.json type.fonts,
# STYLE_BIBLE v3 §8.2 "Typographie" ; CHK-39 : seuls Barlow (Condensed et Semi
# Condensed) et Bangers sont chargés — plus aucune référence à Protest
# Revolution ni à Lato, toutes deux retirées de resources/fonts/.)
## Titres (bandeau pinceau, pages de fin) : Barlow Condensed ExtraBold,
## capitales — base de la VRAIE coupe italique (`title_font()`) et repli de
## secours du cisaillement synthétique (`font_title_italic()`).
const FONT_TITLE_BASE := preload("res://resources/fonts/BarlowCondensed-ExtraBold.ttf")
## Labels (petits libellés de chrome, à puce rouge) : Barlow Condensed SemiBold caps.
const FONT_LABEL := preload("res://resources/fonts/BarlowCondensed-SemiBold.ttf")
## Nombres (munitions, vie, timer, score, crédits) : ExtraBold, tabulaire —
## jamais Bangers (pas de vrais chiffres tabulaires, STYLE_BIBLE v3 §8.2).
const FONT_NUMBER := preload("res://resources/fonts/BarlowCondensed-ExtraBold.ttf")
## Boutons/actions (poids intermédiaire, lisible en continu) — base des
## boutons secondaires (droit) et de leur VRAIE coupe italique (`button_secondary_font()`).
const FONT_BOLD := preload("res://resources/fonts/BarlowCondensed-Bold.ttf")
## Phrases longues (sous-titres, descriptions).
const FONT_BODY := preload("res://resources/fonts/BarlowSemiCondensed-Medium.ttf")

## Chemins des VRAIES coupes italiques/onomatopée (STYLE_BIBLE v3 §8.2 :
## « on remplace le faux italique par la vraie coupe » ; « Bangers... remplace
## Protest Revolution »). `load()` à l'exécution — JAMAIS `preload()`, qui
## ferait échouer l'import tant que le fichier n'a pas été ajouté — via
## `ResourceLoader.exists()` : absent, on replie sur le cisaillement
## synthétique (titres/boutons) ou sur `FONT_TITLE_BASE` (onomatopée), jamais
## sur Protest Revolution ni Lato (retirées, CHK-39).
const FONT_TITLE_ITALIC_REAL_PATH := "res://resources/fonts/BarlowCondensed-ExtraBoldItalic.ttf"
const FONT_BOLD_ITALIC_REAL_PATH := "res://resources/fonts/BarlowCondensed-BoldItalic.ttf"
const FONT_ONOMATOPOEIA_REAL_PATH := "res://resources/fonts/Bangers-Regular.ttf"

## Cisaillement synthétique — REPLI uniquement, tant que la vraie coupe n'est
## pas chargée (`title_font()`, `button_secondary_font()`). Godot 4.7
## (tutoriel "Faux bold and italic") : « faux italic ... setting the yx
## component [Transform2D.y.x] to a positive value between 0.2 and 0.4 » —
## x_axis reste (1,0), y_axis penche de `_ITALIC_SLANT` sur X. Voir
## FontVariation.variation_transform. STYLE_BIBLE v3 §8.1 règle 5 : une seule
## inclinaison, 12° = tan 12° = 0,2126 (== `SLANT_DEG`, aussi pour les formes).
const _ITALIC_SLANT := 0.2126
static var _title_italic: FontVariation
static var _button_secondary_italic: FontVariation
static var _title_italic_real: Font
static var _title_italic_real_checked := false
static var _button_secondary_italic_real: Font
static var _button_secondary_italic_real_checked := false
static var _onomatopoeia_font: Font
static var _onomatopoeia_checked := false

## Police titre italique DÉRIVÉE (cisaillement, jamais un fichier séparé) —
## repli de secours de `title_font()`, construite une seule fois (FontVariation
## est une ressource RUNTIME, ne peut pas être un `const`).
static func font_title_italic() -> FontVariation:
	if _title_italic == null:
		var fv := FontVariation.new()
		fv.base_font = FONT_TITLE_BASE
		fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(_ITALIC_SLANT, 1.0), Vector2(0.0, 0.0))
		_title_italic = fv
	return _title_italic

## Police titre EFFECTIVE (`title_label()`) : la vraie coupe
## `BarlowCondensed-ExtraBoldItalic.ttf` si le fichier a été ajouté, sinon le
## cisaillement synthétique de `font_title_italic()` en repli.
static func title_font() -> Font:
	if not _title_italic_real_checked:
		_title_italic_real_checked = true
		if ResourceLoader.exists(FONT_TITLE_ITALIC_REAL_PATH):
			_title_italic_real = load(FONT_TITLE_ITALIC_REAL_PATH)
	return _title_italic_real if _title_italic_real != null else font_title_italic()

## Cisaillement synthétique des boutons secondaires — même angle que les
## titres, repli de secours de `button_secondary_font()`.
static func _button_secondary_italic_synthetic() -> FontVariation:
	if _button_secondary_italic == null:
		var fv := FontVariation.new()
		fv.base_font = FONT_BOLD
		fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(_ITALIC_SLANT, 1.0), Vector2(0.0, 0.0))
		_button_secondary_italic = fv
	return _button_secondary_italic

## Police bouton secondaire EFFECTIVE (`button_secondary_label()`) : la vraie
## coupe `BarlowCondensed-BoldItalic.ttf` si présente, sinon le repli cisaillé
## sur `FONT_BOLD`.
static func button_secondary_font() -> Font:
	if not _button_secondary_italic_real_checked:
		_button_secondary_italic_real_checked = true
		if ResourceLoader.exists(FONT_BOLD_ITALIC_REAL_PATH):
			_button_secondary_italic_real = load(FONT_BOLD_ITALIC_REAL_PATH)
	return _button_secondary_italic_real if _button_secondary_italic_real != null else _button_secondary_italic_synthetic()

## Police onomatopée EFFECTIVE (`onomatopoeia_label()`, mot-bruit de kill
## UNIQUEMENT, ≤ 6 mots distincts, jamais de chiffre) : `Bangers-Regular.ttf`
## si présente, sinon repli sur `FONT_TITLE_BASE` — jamais Protest Revolution
## ni Lato (retirées, CHK-39).
static func font_onomatopoeia() -> Font:
	if not _onomatopoeia_checked:
		_onomatopoeia_checked = true
		if ResourceLoader.exists(FONT_ONOMATOPOEIA_REAL_PATH):
			_onomatopoeia_font = load(FONT_ONOMATOPOEIA_REAL_PATH)
	return _onomatopoeia_font if _onomatopoeia_font != null else FONT_TITLE_BASE

# ------------------------------------------------------------ Motion (tokens.json motion,
# STYLE_BIBLE v3 §8.2 "Mouvement" — durées en secondes, familles cubic sauf
# `slap`, seule exception back-out)
const DUR_PRESS := 0.09    # l'autocollant s'écrase sur son ombre, cubic out
const DUR_FOCUS := 0.15    # survol, focus, cubic out
## Autocollant qui se colle : échelle 1,08 -> 1, rotation -3° -> 0 — SEULE
## exception à la famille cubique (back out, surdépassement 1,2).
const DUR_SLAP := 0.22
const SLAP_OVERSHOOT_SCALE := 1.08
const SLAP_OVERSHOOT_ROTATE_DEG := -3.0
const DUR_WIPE := 0.28     # bandeau pinceau de gauche à droite, cubic out
const DUR_REVEAL := 0.25   # apparition de panneau (translation + fondu), cubic out
const REVEAL_TRANSLATE_PX := 24
const DUR_SWAP := 0.2
const DUR_END := 0.4       # changement d'écran, fin de match, cubic in-out
const DUR_PAGE := DUR_END  # alias du nom tokens.json `page` (même valeur)
const DUR_BURST_MIN := 0.6 # moments de trame : cubic out, maintien, cubic in
const DUR_BURST_MAX := 1.2
const STAGGER_S := 0.03
const STAGGER_MAX_ITEMS := 6
## Fondu de repli en mouvement réduit (tokens.json "reduced_motion.fade_ms")
## — SEULE animation permise quand `reduced_motion` est actif (le reste de la
## liste "forbid" : scale/rotation/position/shake/pulse/blink). Utilisé par
## UiFx.gd (reveal/wipe/press) à la place de DUR_REVEAL/DUR_WIPE dès que
## `reduced_motion()` est vrai.
const DUR_REDUCED_FADE := 0.12

## Mouvement réduit (Settings.reduced_motion) — lu "en sécurité" via une
## instance (`Settings` est `extends RefCounted` statique ; `Settings.get(...)`
## sur la CLASSE ne compile pas). Centralisé ici : tous les contrôles animés
## (BrushHeader, KillWordBurst, LowHealthVignette, …) appellent ce helper au
## lieu de dupliquer la même prudence.
static func reduced_motion() -> bool:
	var v = Settings.new().get("reduced_motion")
	return false if v == null else bool(v)

# ============================================================== Fabriques StyleBox
## Panneau charcoal (design.md §11 "Panels: radius 2, a 1 px rule, never
## nested") : fond plein `bg`, trait `border` de `w` px, coins `radius`.
static func panel_style(bg: Color = PANEL, border: Color = RULE, radius: int = PANEL_RADIUS, w: int = RULE_W) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(w)
	s.border_color = border
	s.set_corner_radius_all(radius)
	s.content_margin_left = SP_4
	s.content_margin_right = SP_4
	s.content_margin_top = SP_3
	s.content_margin_bottom = SP_3
	s.anti_aliasing = true
	return s

## Cartouche compacte (killfeed, sous-titres, chips HUD) : mêmes tokens,
## marges resserrées.
static func cartouche_style(bg: Color = PANEL, border: Color = RULE, radius: int = PANEL_RADIUS, w: int = RULE_W) -> StyleBoxFlat:
	var s := panel_style(bg, border, radius, w)
	s.content_margin_left = SP_2
	s.content_margin_right = SP_2
	s.content_margin_top = SP_1
	s.content_margin_bottom = SP_1
	return s

## État désactivé (design.md §11 "Disabled: hatching + reason") : fond
## panel_hi, trait `disabled`. À COMBINER avec `hatch_rect` par-dessus pour le
## motif diagonal, et un libellé de raison affiché à côté (pas de troncature
## muette).
static func disabled_style() -> StyleBoxFlat:
	return panel_style(PANEL_HI, DISABLED)

## Anneau de focus manette (design.md §11 "Focus-visible: brush underlay +
## 2 px outline, offset 4 px"). Godot dessine le style `focus` d'un Button EN
## SURCOUCHE du style de base (normal/pressed) — jamais à sa place (doc
## Godot 4.7, Button "Theme Property Descriptions" : « use a partially
## transparent StyleBox... to keep the underlying style visible »). `bg_color`
## reste donc translucide (jamais opaque), sous peine de cacher tout le
## contenu du contrôle focalisé derrière un aplat plein.
static func focus_style() -> StyleBoxFlat:
	var s := panel_style(Color(PRESSED.r, PRESSED.g, PRESSED.b, 0.35), BULLET, PANEL_RADIUS, RULE_W_STRONG)
	s.expand_margin_left = FOCUS_RING_OFFSET_PX
	s.expand_margin_top = FOCUS_RING_OFFSET_PX
	s.expand_margin_right = FOCUS_RING_OFFSET_PX
	s.expand_margin_bottom = FOCUS_RING_OFFSET_PX
	return s

## Ombre dure à poser en enfant DERRIÈRE un `panel_style()`/`cartouche_style()`,
## décalée de `SHADOW_HARD_OFFSET` (ou `SHADOW_HARD_SMALL_OFFSET` pour les
## chips/hexagones ≤ 72 px) : aplat `encre` opaque, jamais de flou (CHK-38
## interdit tout `StyleBoxFlat.shadow_size` > 0 — cette fabrique n'y touche
## JAMAIS, le relief vient uniquement du décalage).
static func hard_shadow_style(radius: int = PANEL_RADIUS) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = HARD_SHADOW_COLOR
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s

# ============================================================== Fabriques Label
## Label générique. `font` force une police précise (ex. `font_title_italic()`
## pour un titre) ; sinon choisi par taille (label >= SIZE_LABEL, sinon body).
static func label(text: String, size: int, color: Color = TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", 0)
	var f := font
	if f == null:
		f = FONT_LABEL if size >= SIZE_LABEL else FONT_BODY
	l.add_theme_font_override("font", f)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Nombre tabulaire (munitions, vie, timer, score, crédits) — toujours
## Barlow Condensed ExtraBold.
static func number_label(text: String, size: int, color: Color = TEXT) -> Label:
	return label(text, size, color, FONT_NUMBER)

## Titre bandeau pinceau / page de fin — capitales, VRAIE coupe italique si
## présente, sinon cisaillement en repli (STYLE_BIBLE v3 §8.2, `title_font()`).
static func title_label(text: String, size: int, color: Color = TEXT) -> Label:
	return label(text.to_upper(), size, color, title_font())

## Bouton secondaire — VRAIE coupe Bold Italic si présente, sinon repli
## cisaillé sur `FONT_BOLD` (STYLE_BIBLE v3 §8.2, `button_secondary_font()`).
static func button_secondary_label(text: String, size: int = SIZE_LABEL, color: Color = TEXT) -> Label:
	return label(text, size, color, button_secondary_font())

## Onomatopée (mot-bruit de kill UNIQUEMENT, ≤ 6 mots distincts, jamais de
## chiffre) — Bangers si présente, sinon repli (STYLE_BIBLE v3 §8.2,
## `font_onomatopoeia()`).
static func onomatopoeia_label(text: String, size: int, color: Color = TEXT) -> Label:
	return label(text, size, color, font_onomatopoeia())

## Libellé de chrome à puce rouge (design.md §11 "Labels: each takes a red
## bullet") : "• MODE", "• CARTE", "• VITALITÉ"… Toujours Barlow Condensed
## SemiBold caps.
static func bullet_row(text: String, size: int = SIZE_FLOOR, color: Color = TEXT_DIM) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", SP_1)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := label("•", size, BULLET, FONT_LABEL)
	h.add_child(dot)
	var lbl := label(text.to_upper(), size, color, FONT_LABEL)
	h.add_child(lbl)
	return h

# ============================================================== Textures procédurales
## Tuile de hachures diagonales — désactivé/hors de prix/vide (design.md §11
## "Disabled: hatching + reason"). `line_w` double en « Encre renforcée »
## (accessibilité, design.md §5).
static func hatch_texture(pitch: int = 10, line_w: int = 2, fg: Color = DISABLED, bg: Color = Color(0, 0, 0, 0)) -> ImageTexture:
	var s := maxi(pitch, 4)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	for y in s:
		for x in s:
			if (x + y) % s < line_w:
				img.set_pixel(x, y, fg)
	return ImageTexture.create_from_image(img)

## Rect hachuré prêt à poser en enfant (mouse_filter ignore, tuile répétée).
static func hatch_rect(pitch: int = 10, fg: Color = DISABLED, alpha: float = 0.7) -> TextureRect:
	var t := TextureRect.new()
	t.texture = hatch_texture(pitch, 2, Color(fg.r, fg.g, fg.b, alpha))
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return t

# ============================================================== Alias hérités (v1 -> v2)
## Ponts de compatibilité UNIQUEMENT pour les fichiers HORS du périmètre
## d'écriture de cette tranche qui consomment encore les noms v1 « encre et
## papier » (scripts/training/** : AbilitiesCorner.gd, MovementTutorial.gd,
## ShootingRange.gd, TimeTrialCourse.gd). Recalés sur la palette/les fontes v2
## (donc déjà charcoal/pinceau à l'écran sans toucher ces fichiers) plutôt que
## sur les anciennes valeurs papier/encre littérales. Ne JAMAIS utiliser ces
## alias dans du code NEUF de cette tranche — les jetons v2 ci-dessus
## directement.
const PAPER := PANEL
const PAPER_SHADE := PANEL_HI
const INK := TEXT
const GRAPHITE := TEXT_DIM
const SHADOW_TINT := BG
const STROKE_HAIR := RULE_W
const STROKE_LINE := RULE_W
const STROKE_FRAME := RULE_W_STRONG
const FONT_SEMI := FONT_LABEL
const FONT_HEAVY := FONT_NUMBER
## v1 « affichage » pinceau sec == la police onomatopée v3 (Bangers si
## présente, sinon repli — `font_onomatopoeia()`). Ne peut plus être un
## `const` : résolution à l'exécution (`ResourceLoader.exists()`), comme sa
## cible.
static func font_display() -> Font:
	return font_onomatopoeia()

# ==============================================================================
#  v4 « Encre, jaune, italique » (UX-30, docs/UI_DIRECTION_BL3.md §4/§7,
#  docs/style/tokens.json v4.0.0 — direction VALIDÉE par l'utilisateur le
#  2026-09-25). Surface PUBLIQUE additive de la nouvelle direction : jetons
#  signal/vital/paper/paper_dim/plate/plate_hi/ink + équipes (ALLY/ENEMY_*,
#  inchangées ci-dessus), échelle 21/28/37/50/66/88/118/157, polices
#  title/number/button/meta/body, l'aide `ink_label()` (texte encré, zéro
#  fond) et `plate_style()` (coins coupés). KitSlantTile.gd et KitSwash.gd
#  (scripts/ui/kit/) complètent ce kit.
#
#  `paper`/`plate`/`plate_hi`/`ink` reprennent EXACTEMENT les valeurs déjà
#  exposées par `TEXT`/`PANEL`/`PANEL_HI`/`HARD_SHADOW_COLOR` ci-dessus
#  (tokens.json INCHANGÉ pour ces 4 jetons, §7) : ce sont des fonctions
#  minuscules pour le nom de rôle v4, PAS de nouvelles constantes — `PAPER`/
#  `INK` en MAJUSCULES sont déjà pris par le pont de compatibilité v1 -> v2
#  ci-dessus (valeurs DIFFÉRENTES, réservées à scripts/training/**) ;
#  GDScript étant sensible à la casse, une fonction minuscule ne rentre
#  jamais en collision avec une constante MAJUSCULE existante.
# ==============================================================================

## `color.ui.signal` (tokens.json §7) : la seule couleur qui désigne —
## sélection, CTA, focus, objectif, ultime prêt, ta ligne du fil. Remplace le
## rôle « marque » de l'ancien `BRUSH` (#C8242C, INCHANGÉ ci-dessus pour ne
## pas casser les écrans non convertis) pour tout code NEUF v4. Pas plus de
## 3 éléments `SIGNAL` simultanés dans le HUD (UI_DIRECTION_BL3.md §5).
const SIGNAL := Color("FFCE1F")     # encre dessus 12,3:1, OKLCH h 90,7°
## `color.ui.vital` (tokens.json §7, nouveau) : vie, dégâts, erreur.
const VITAL := Color("E8392E")      # 4,2:1 sur `plate_color()`

static func signal_color() -> Color:
	return SIGNAL

static func vital_color() -> Color:
	return VITAL

## `paper` v4 == `color.papier.text` (tokens.json) : valeur INCHANGÉE de `TEXT`.
static func paper_color() -> Color:
	return TEXT

## `paper_dim` v4 == `color.papier.dim` : valeur INCHANGÉE de `TEXT_DIM`.
static func paper_dim_color() -> Color:
	return TEXT_DIM

## `plate` v4 (plaques de menu à coins coupés) == `color.charbon.panel` :
## valeur INCHANGÉE de `PANEL`.
static func plate_color() -> Color:
	return PANEL

## `plate_hi` v4 (survol) == `color.charbon.panel_hi` : valeur INCHANGÉE de
## `PANEL_HI`.
static func plate_hi_color() -> Color:
	return PANEL_HI

## `ink` v4 (contours, ombres, texte sur jaune) == `color.ink` : valeur
## INCHANGÉE de `HARD_SHADOW_COLOR`.
static func ink_color() -> Color:
	return HARD_SHADOW_COLOR

# ------------------------------------------------------------ Échelle typo v4 (tokens.json
# type.ratio 1,333 à 8 crans, type.scale_px_1080, §7) — remplace le ratio
# 1,25 à 9 crans de v3 pour le code NEUF ; `SIZE_FLOOR`..`SIZE_DISPLAY_XXL`
# restent INCHANGÉS ci-dessus (écrans non convertis). Facteur 720p = 2/3,
# automatique via le stretch canvas_items+expand du viewport (voir la note
## de `SIZE_FLOOR`) — aucune paire de constantes _720 séparée n'est
# nécessaire ici.
const SIZE_21 := 21
const SIZE_28 := 28
const SIZE_37 := 37
const SIZE_50 := 50
const SIZE_66 := 66
const SIZE_88 := 88
const SIZE_118 := 118
const SIZE_157 := 157

# ------------------------------------------------------------ Formes v4 (tokens.json shape, §7)
## Traits (tokens.json shape.stroke, §7 — remplace rule/focus/sticker/diecut
## de v3 pour le code NEUF ; `RULE_W`/`RULE_W_STRONG`/`STROKE_STICKER`/
## `STROKE_DIECUT` ci-dessus restent INCHANGÉS pour les écrans non convertis).
const STROKE_INK := 3        # plaques, tuiles, texte sur 3D
const STROKE_SELECT := 4     # liseré découpé de l'état sélectionné
const STROKE_DISPLAY := 5    # titres >= 88 px
const STROKE_FOCUS := 3      # anneau focus manette (+ FOCUS_RING_OFFSET_PX)

## Coin coupé (tokens.json shape.chamfer_px, §7) : `StyleBoxFlat.corner_detail
## = 1` avec un `corner_radius` produit un coin en BISEAU DROIT, jamais
## arrondi (Godot 4.7, class_styleboxflat.html : « Setting the detail to 1
## produces chamfered corners instead of rounded curves »). 16 px par défaut
## (22 px minimap), en haut-à-droite et en bas-à-gauche seulement — `shape.
## radius` reste à 0 partout ailleurs (§7, plus de coin arrondi en v4).
const CHAMFER_PX := 16
const CHAMFER_PX_MINIMAP := 22

## Plaque v4 (menus, cartes, panneaux à coins coupés) : fond `plate_color()`
## par défaut, coins coupés `chamfer_px` en haut-droit + bas-gauche, radius 0
## ailleurs. AUCUN trait de bordure (v4 supprime le filet 1 px de v3, §7
## `color.charbon.rule` supprimé) : le relief vient de l'ombre dure portée en
## enfant (`hard_shadow_style()`), jamais d'une bordure peinte ici.
static func plate_style(bg: Color = PANEL, chamfer_px: int = CHAMFER_PX) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = 0
	s.corner_radius_top_right = chamfer_px
	s.corner_radius_bottom_right = 0
	s.corner_radius_bottom_left = chamfer_px
	s.corner_detail = 1
	s.content_margin_left = SP_4
	s.content_margin_right = SP_4
	s.content_margin_top = SP_3
	s.content_margin_bottom = SP_3
	s.anti_aliasing = true
	return s

# ------------------------------------------------------------ Polices v4 (tokens.json type.fonts, §7)
## Titre v4 : la vraie coupe Black Italic n'existe pas encore (`to_add`,
## tokens.json) — en attendant, ExtraBold Italic (déjà réelle, `title_font()`
## ci-dessus, INCHANGÉE) + un embolden de 0,6 (`FontVariation.
## variation_embolden`, Godot 4.7) simule le poids Black. Point d'entrée v4
## pour KitSlantTile/KitSwash/UiKitGallery ; les écrans non convertis gardent
## `title_font()` sans embolden.
const TITLE_EMBOLDEN_V4 := 0.6
static var _title_font_v4: Font

const TITLE_BLACK_ITALIC_PATH := "res://resources/fonts/BarlowCondensed-BlackItalic.ttf"

static func title_font_v4() -> Font:
	if _title_font_v4 == null:
		# Vraie coupe Black Italic (OFL, ajoutée 2026-09-25) ; repli ExtraBold
		# Italic + embolden si le fichier venait à manquer.
		if ResourceLoader.exists(TITLE_BLACK_ITALIC_PATH):
			_title_font_v4 = load(TITLE_BLACK_ITALIC_PATH) as Font
		if _title_font_v4 == null:
			var fv := FontVariation.new()
			fv.base_font = title_font()
			fv.variation_embolden = TITLE_EMBOLDEN_V4
			_title_font_v4 = fv
	return _title_font_v4

## Nombre v4 : ExtraBold Italic TABULAIRE (v3 `FONT_NUMBER` ci-dessus reste
## droit, pour les écrans non convertis) — même fichier réel que le titre
## (`BarlowCondensed-ExtraBoldItalic.ttf`), sans embolden.
static func number_font_v4() -> Font:
	return title_font()

## Bouton v4 : Bold Italic — alias direct de `button_secondary_font()`
## (déjà la vraie coupe), sous le nom du rôle v4 (tokens.json type.fonts.button).
static func button_font_v4() -> Font:
	return button_secondary_font()

## Méta v4 (sur-titres, touches, fil) : Barlow Condensed SemiBold, capitales,
## +0,10 d'approche (tokens.json type.fonts.meta.letter_spacing).
## `FontVariation.spacing_glyph` est en PIXELS, pas relatif à la taille de
## police (Godot 4.7) — dérivé de `size` à chaque appel plutôt qu'une valeur
## fixe, pour que l'approche reste proportionnelle à tous les crans de
## l'échelle.
const META_LETTER_SPACING_RATIO := 0.10

static func meta_font_v4(size: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = FONT_LABEL
	fv.spacing_glyph = int(round(size * META_LETTER_SPACING_RATIO))
	return fv

## Corps v4 : identique à v3 (`FONT_BODY`, Barlow Semi Condensed Medium,
## INCHANGÉ au §7) — alias sous le nom du rôle v4.
static func body_font_v4() -> Font:
	return FONT_BODY

# ------------------------------------------------------------ Fabriques Label v4
## Titre v4 — capitales, `title_font_v4()` (embolden 0,6).
static func title_label_v4(text: String, size: int = SIZE_88, color: Color = TEXT) -> Label:
	return label(text.to_upper(), size, color, title_font_v4())

## Nombre v4 — tabulaire italique.
static func number_label_v4(text: String, size: int = SIZE_66, color: Color = TEXT) -> Label:
	return label(text, size, color, number_font_v4())

## Bouton v4 — capitales italiques.
static func button_label_v4(text: String, size: int = SIZE_50, color: Color = TEXT) -> Label:
	return label(text.to_upper(), size, color, button_font_v4())

## Méta v4 — capitales, +0,10 d'approche.
static func meta_label_v4(text: String, size: int = SIZE_21, color: Color = TEXT_DIM) -> Label:
	return label(text.to_upper(), size, color, meta_font_v4(size))

## Corps v4 — casse mixte.
static func body_label_v4(text: String, size: int = SIZE_28, color: Color = TEXT) -> Label:
	return label(text, size, color, FONT_BODY)

# ------------------------------------------------------------ Texte encré (UI_DIRECTION_BL3.md
# §5 règle 1 « zéro fond derrière le texte du HUD » — la lisibilité vient
# UNIQUEMENT de l'encre et de l'ombre. Même mécanisme déjà en jeu dans
# KillWordBurst.gd (outline_size/font_outline_color/font_shadow_color/
# shadow_offset_x/y — propriétés de thème Label natives à Godot 4.7,
# tutoriel « Font outlines and shadows »), généralisé ici pour tout texte
# HUD v4 plutôt que ré-écrit à chaque appelant.
const INK_OUTLINE_PX := STROKE_INK
const INK_LABEL_SHADOW_OFFSET := Vector2(4, 4)

## Texte posé DIRECTEMENT sur la 3D, sans aucun panneau derrière : contour
## d'encre 3 px + ombre dure (4,4). `size`/`color` sont les valeurs 1080p —
## le stretch canvas_items+expand du viewport (voir la note de `SIZE_FLOOR`
## ci-dessus) ramène automatiquement le contour à 2 px à 720p, sans code
## séparé (3 × 2/3 = 2).
static func ink_label(text: String, size: int, color: Color = TEXT, font: Font = null) -> Label:
	var l := label(text, size, color, font)
	l.add_theme_constant_override("outline_size", INK_OUTLINE_PX)
	l.add_theme_color_override("font_outline_color", HARD_SHADOW_COLOR)
	l.add_theme_color_override("font_shadow_color", HARD_SHADOW_COLOR)
	l.add_theme_constant_override("shadow_offset_x", int(INK_LABEL_SHADOW_OFFSET.x))
	l.add_theme_constant_override("shadow_offset_y", int(INK_LABEL_SHADOW_OFFSET.y))
	return l
