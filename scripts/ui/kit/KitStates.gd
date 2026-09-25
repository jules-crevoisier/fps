## KitStates.gd
## Espace de noms partagé par le kit de composants autocollant (ART-31,
## docs/STYLE_BIBLE.md §8.2 « Jetons » et §8.4 « États des composants ») :
## l'énumération des 9 états que chaque famille (Charbon/Autocollant/Hexagone)
## sait représenter — exactement les 9 lignes de la table §8.4 (défaut,
## survol, focus visible, pressé, sélectionné, désactivé avec raison,
## chargement, vide, erreur) — et quelques constantes partagées.
##
## Chaque composant du kit (KitCharbonRow, KitCard, KitSlantBar, KitBubble,
## KitHexagon) expose un champ `state_override: int` (une des valeurs
## `State.*` ci-dessous, ou -1). À -1 (par défaut, usage en jeu), l'état
## affiché se calcule depuis l'entrée RÉELLE (survol/focus/pression natifs de
## `BaseButton`, plus les drapeaux de données `selected`/`loading`/`empty`/
## `error_text`/`disabled`). À une valeur >= 0 (usage de la galerie de
## démonstration, `scenes/dev/ui_kit_gallery.tscn`), l'état est FORCÉ pour la
## capture statique — indispensable puisque `ui_shots` ne bouge ni la souris
## ni le focus manette.
class_name KitStates
extends RefCounted

enum State {
	DEFAULT,
	HOVER,
	FOCUS,
	PRESSED,
	SELECTED,
	DISABLED,
	LOADING,
	EMPTY,
	ERROR,
}

## Ordre d'affichage de la galerie — exactement l'ordre des lignes de
## STYLE_BIBLE.md §8.4.
const ALL_STATES: Array[int] = [
	State.DEFAULT, State.HOVER, State.FOCUS, State.PRESSED, State.SELECTED,
	State.DISABLED, State.LOADING, State.EMPTY, State.ERROR,
]

const LABELS := {
	State.DEFAULT: "Défaut",
	State.HOVER: "Survol",
	State.FOCUS: "Focus visible",
	State.PRESSED: "Pressé",
	State.SELECTED: "Sélectionné",
	State.DISABLED: "Désactivé",
	State.LOADING: "Chargement",
	State.EMPTY: "Vide",
	State.ERROR: "Erreur",
}

static func label_for(s: int) -> String:
	return LABELS.get(s, "?")

## Repli de dernier recours si un appelant désactive un contrôle sans fournir
## de raison (CHK-37 : « chaque contrôle désactivé expose une raison — non
## vide »). Ne doit jamais servir en usage réel : chaque composant du kit
## documente `disabled_reason` comme un paramètre attendu, pas optionnel.
const DEFAULT_DISABLED_REASON := "Indisponible"

## `CanvasItem.draw_string()` positionne la LIGNE DE BASE, pas le coin
## haut-gauche du glyphe (piège classique — un texte posé à `center.y` déborde
## visiblement au-dessus de son point d'ancrage, l'ascendant part vers le
## haut). Centre un texte à la fois horizontalement (largeur) et verticalement
## (ascendant/descendant réels de la police) autour de `center` — utilisé par
## tous les tampons/glyphes du kit (✓, ▶, RATÉ, glyphe de bulle, touche
## d'hexagone) plutôt que de refaire ce calcul à chaque appelant.
static func draw_centered_string(ci: CanvasItem, font: Font, center: Vector2, text: String, font_size: int, color: Color) -> void:
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var pos := Vector2(center.x - ts.x * 0.5, center.y + (ascent - descent) * 0.5)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## États pour lesquels la colonne « Hexagone » de STYLE_BIBLE.md §8.4 porte
## « — » (non applicable : un hexagone de capacité n'a pas de notion de
## sélection/chargement/vide propre — ce sont des états de LISTE/CARTE). La
## galerie affiche un tiret à leur place plutôt que d'inventer un rendu hors
## spec pour KitHexagon.
const HEXAGON_NA_STATES: Array[int] = [State.SELECTED, State.LOADING, State.EMPTY]
