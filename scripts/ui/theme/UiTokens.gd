## UiTokens.gd
## Jetons de la direction d'interface « Planche » (2026-09-27, validée par l'utilisateur sur
## maquettes : reports/ui/mockups/ui.css + reports/checkpoints/2026-09-27_ui/). Chaque écran est
## une case de BD : papier crème, trait d'encre épais, ombre portée dure « autocollant », plaques
## inclinées, UN accent jaune pour l'action, bleu allié / rose ennemi, rouge = danger.
## Toutes les tailles sont en px À 1080p (project.godot : stretch canvas_items, base 1920×1080).
## SOURCE UNIQUE : un nombre ou une couleur d'interface ne se recopie jamais ailleurs.
class_name UiTokens
extends RefCounted

# ------------------------------------------------------------------ couleurs
const INK := Color("1B1030")          # trait, texte sur clair (= contour 3D toon_style.json)
const INK_SOFT := Color(0.106, 0.063, 0.188, 0.72)
const PAPER := Color("FFF4E0")        # panneaux, texte sur foncé
const PAPER_2 := Color("F3E2C4")      # fond de jauge vide
const YELLOW := Color("FFCE1F")       # LE seul accent : action, sélection, soi-même
const BLUE := Color("2E8BFF")         # alliés
const BLUE_DEEP := Color("1D5FD6")    # texte allié sur papier (contraste)
const MAGENTA := Color("FF2E9A")      # ennemis (réglage daltonisme : voir enemy_color)
const MAGENTA_DEEP := Color("D4127A") # texte ennemi sur papier
const RED := Color("E8392E")          # danger, vie basse, K.O.
const GREEN := Color("46D16B")        # vie

# ------------------------------------------------------------------ typo (échelle 1,333)
const T_XS := 18
const T_S := 24
const T_M := 32
const T_L := 43
const T_XL := 57
const T_2XL := 76
const T_3XL := 101
const T_4XL := 135

const FONT_DISPLAY := preload("res://resources/fonts/Bangers-Regular.ttf")          # titres, gros chiffres
const FONT_LABEL := preload("res://resources/fonts/BarlowCondensed-BlackItalic.ttf") # libellés, boutons
const FONT_LABEL_SEMI := preload("res://resources/fonts/BarlowCondensed-ExtraBoldItalic.ttf")
const FONT_BODY := preload("res://resources/fonts/BarlowSemiCondensed-Medium.ttf")   # textes courants

# ------------------------------------------------------------------ espacement / formes
const S1 := 8
const S2 := 16
const S3 := 24
const S4 := 32
const S5 := 48
const S6 := 64
const STROKE := 4.0
const DROP := Vector2(8, 8)
const DROP_SMALL := Vector2(4, 4)
const SKEW_DEG := -10.0               # plaques penchées comme l'italique
const EDGE_MARGIN := 40               # marge des éléments du HUD au bord de l'écran

# ------------------------------------------------------------------ mouvement
const POP_S := 0.18                   # apparition « pop » (échelle 1,08 -> 1, retour élastique)
const SLIDE_S := 0.25                 # glissement d'une entrée (fil des éliminations, bandeaux)

const ICON_DIR := "res://assets/ui/icons/"


## Couleur ennemie courante (réglage joueur Magenta/Citron, même source que le contour 3D).
static func enemy_color() -> Color:
	return Cartoon.enemy_color()


static func team_color(is_ally: bool) -> Color:
	return BLUE if is_ally else enemy_color()


## Plaque BD (StyleBoxComic) : `fill`, penchée de `skew_deg`, trait d'encre, ombre dure.
## `pad` = marge intérieure en px (le débord de la pente est ajouté par la StyleBox elle-même).
static func plate(fill: Color = PAPER, skew_deg: float = SKEW_DEG, drop: Vector2 = DROP,
		stroke: float = STROKE, pad: Vector2 = Vector2(S3, S1)) -> StyleBoxComic:
	var sb := StyleBoxComic.new()
	sb.fill = fill
	sb.skew_deg = skew_deg
	sb.drop = drop
	sb.stroke_width = stroke
	sb.pad = pad
	return sb


## Gros chiffres et titres (Bangers) : remplissage `color`, contour encre, ombre dure décalée.
static func display(size: int, color: Color = PAPER, outline: int = 8, shadow: Vector2 = Vector2(6, 6)) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = FONT_DISPLAY
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = INK
	ls.shadow_size = outline
	# sans contour (texte encre sur papier) : pas d'ombre non plus, elle doublerait le texte
	ls.shadow_color = INK if outline > 0 else Color(0, 0, 0, 0)
	ls.shadow_offset = shadow
	return ls


## Libellés (Barlow Condensed italique noir, capitales côté appelant). `outline` > 0 pour un
## libellé posé directement sur la scène 3D (sans plaque).
static func label(size: int, color: Color = INK, outline: int = 0, semi: bool = false) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = FONT_LABEL_SEMI if semi else FONT_LABEL
	ls.font_size = size
	ls.font_color = color
	if outline > 0:
		ls.outline_size = outline
		ls.outline_color = INK
		ls.shadow_size = outline
		ls.shadow_color = INK
		ls.shadow_offset = Vector2(3, 3)
	return ls


static func body(size: int = T_S, color: Color = INK) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = FONT_BODY
	ls.font_size = size
	ls.font_color = color
	return ls


## Label prêt à l'emploi (capitales pour les libellés : la direction les écrit toujours ainsi).
static func make_label(text: String, settings: LabelSettings, upper: bool = false) -> Label:
	var l := Label.new()
	l.text = text.to_upper() if upper else text
	l.label_settings = settings
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Icône de assets/ui/icons (`revolver_sil`, `frag_sticker`, `health`…) ; null si absente.
static func icon(icon_name: String) -> Texture2D:
	for ext: String in [".png", ".svg"]:
		var p: String = ICON_DIR + icon_name + ext
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null
