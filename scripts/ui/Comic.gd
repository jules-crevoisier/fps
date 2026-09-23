## Comic.gd
## Boîte à outils direction artistique v2 « Peint au soleil, encré gras »
## (.orchestrator/design.md §11, locked) : tokens (couleurs, espacement,
## échelle typo) et fabriques (StyleBox, Label, textures de hachures) partagés
## par tout le HUD et les menus. Remplace v1 « encre et papier, joueurs en
## couleur » (rejetée) : pages/panneaux charcoal, bandeaux pinceau rouge,
## titres blancs italiques capitales, labels à puce rouge. Voir BrushHeader.gd
## (bandeau pinceau), ComicPanel.gd (panneau charcoal), ComicBar.gd/ComicChip.gd
## (HUD).
class_name Comic
extends RefCounted

# ------------------------------------------------------------ Surfaces (design.md §11 "Colour")
const BG := Color("101113")
const PANEL := Color("1a1b1e")
const PANEL_HI := Color("232428")
const RULE := Color("2e3034")

# ------------------------------------------------------------ Texte
const TEXT := Color("f2efe9")          # 15.0:1 sur `panel`
const TEXT_DIM := Color("a9a6a0")      # 7.1:1
const DISABLED := Color("6e6c68")      # 3.3:1

# ------------------------------------------------------------ Pinceau (brand / vie basse)
const BRUSH := Color("c8242c")
const PRESSED := Color("9e1c22")
const BULLET := Color("e23b33")        # 4.0:1
## Texte posé DIRECTEMENT sur `brush`/`pressed` (bandeau pinceau, boutons
## pleins rouge) : blanc pur, pas `TEXT` (#F2EFE9, légèrement chaud) — design.md
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

# ------------------------------------------------------------ Formes (design.md §11 "Shapes")
## Panneaux : radius 2, trait 1 px, jamais imbriqués.
const PANEL_RADIUS := 2
const RULE_W := 1
## Trait plus marqué (focus/emphase ponctuelle) — jamais utilisé pour
## imbriquer un second panneau, seulement pour une bordure d'accent.
const RULE_W_STRONG := 2

# ------------------------------------------------------------ Échelle typo
## Authored 1920x1080, ratio 1,25, plancher 20 (design.md §11). Le stretch
## canvas_items+expand remet à l'échelle automatiquement (1280x800 = ×0,667).
const SIZE_FLOOR := 20
const SIZE_BODY := 25
const SIZE_SUBTITLE := 31
const SIZE_LABEL := 39
const SIZE_DISPLAY_SM := 49
const SIZE_DISPLAY_MD := 61
const SIZE_DISPLAY_LG := 76
const SIZE_DISPLAY_XL := 95
const SIZE_DISPLAY_XXL := 119

# ------------------------------------------------------------ Polices (design.md §11 "Type (OFL)")
## Titres (bandeau pinceau, pages de fin) : Barlow Condensed ExtraBold,
## capitales — l'italique est DÉRIVÉ via FontVariation (cisaillement), jamais
## un fichier de police séparé. Voir `font_title_italic()`.
const FONT_TITLE_BASE := preload("res://resources/fonts/BarlowCondensed-ExtraBold.ttf")
## Labels (petits libellés de chrome, à puce rouge) : Barlow Condensed SemiBold caps.
const FONT_LABEL := preload("res://resources/fonts/BarlowCondensed-SemiBold.ttf")
## Nombres (munitions, vie, timer, score, crédits) : ExtraBold, tabulaire —
## jamais Protest Revolution (pas de vrais chiffres tabulaires).
const FONT_NUMBER := preload("res://resources/fonts/BarlowCondensed-ExtraBold.ttf")
## Boutons/actions (poids intermédiaire, lisible en continu).
const FONT_BOLD := preload("res://resources/fonts/BarlowCondensed-Bold.ttf")
## Phrases longues (sous-titres, descriptions).
const FONT_BODY := preload("res://resources/fonts/BarlowSemiCondensed-Medium.ttf")
## Onomatopées UNIQUEMENT (mot-bruit de kill) — design.md §11 : « Lato est
## abandonné », Protest Revolution ne sert plus qu'ici.
const FONT_ONOMATOPOEIA := preload("res://resources/fonts/ProtestRevolution-Regular.ttf")

## Cisaillement synthétique (design.md §11 "Titles: ... Italic" — dérivé,
## pas de fichier séparé). Godot 4.7 (tutoriel "Faux bold and italic") :
## « faux italic ... setting the yx component [Transform2D.y.x] to a
## positive value between 0.2 and 0.4 » — x_axis reste (1,0), y_axis penche
## de `_ITALIC_SLANT` sur X. Voir FontVariation.variation_transform.
const _ITALIC_SLANT := 0.24
static var _title_italic: FontVariation

## Police titre italique, construite une seule fois (FontVariation est une
## ressource RUNTIME, ne peut pas être un `const`).
static func font_title_italic() -> FontVariation:
	if _title_italic == null:
		var fv := FontVariation.new()
		fv.base_font = FONT_TITLE_BASE
		fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(_ITALIC_SLANT, 1.0), Vector2(0.0, 0.0))
		_title_italic = fv
	return _title_italic

# ------------------------------------------------------------ Motion (design.md §13)
const DUR_FOCUS := 0.15
const DUR_SWAP := 0.2
const DUR_REVEAL := 0.25
const DUR_END := 0.4

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
	s.expand_margin_left = 4.0
	s.expand_margin_top = 4.0
	s.expand_margin_right = 4.0
	s.expand_margin_bottom = 4.0
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

## Titre bandeau pinceau / page de fin — capitales, italique dérivé
## (design.md §11 "Titles: Barlow Condensed ExtraBold Italic in caps").
static func title_label(text: String, size: int, color: Color = TEXT) -> Label:
	return label(text.to_upper(), size, color, font_title_italic())

## Onomatopée (mot-bruit de kill UNIQUEMENT, design.md §11).
static func onomatopoeia_label(text: String, size: int, color: Color = TEXT) -> Label:
	return label(text, size, color, FONT_ONOMATOPOEIA)

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
## v1 « affichage » pinceau sec == la seule police encore hors labels/nombres
## en v2 (onomatopées, design.md §11).
const FONT_DISPLAY := FONT_ONOMATOPOEIA
