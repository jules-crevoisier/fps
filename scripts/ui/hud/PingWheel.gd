## PingWheel.gd
## Roue de communication (UX-10, docs/research/04_ui_ux.md §2.8 « le maintien
## ouvre une roue (« ennemi ici », « j'y vais ») ») -- 4 options en croix
## (haut/droite/bas/gauche), pilotée par `PingController` pendant un maintien
## du bouton de ping (`open()` à l'ouverture du maintien, `update_direction`
## à chaque image tant qu'il dure, `close_and_confirm()` au relâchement).
## Souris ET manette utilisent la MÊME entrée (`dir: Vector2`, écart
## souris/centre ou stick droit brut -- voir PingController._wheel_direction) :
## la sélection d'option (`option_for_direction`, pure) ne connaît jamais le
## périphérique, ce qui rend « utilisable à la manette (roue au stick) »
## vrai par construction plutôt que par un second chemin de code à
## maintenir. Non câblée dans une scène par cette tâche (voir doc de classe
## de PingController.gd) : instanciée/assignée par la tâche qui possède le
## HUD/la scène du joueur.
class_name PingWheel
extends Control

signal option_chosen(kind: String)

## Zone morte (fraction de la magnitude de `dir`) sous laquelle AUCUNE
## option n'est considérée survolée -- la roue reste ouverte mais indécise
## (Apex : un stick/une souris encore proches du centre n'engagent aucun
## choix, relâcher à cet instant annule plutôt que de choisir au hasard).
const DEADZONE := 0.35

var _hovered_index: int = -1
var _chips: Array[ComicPanel] = []

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _chips.is_empty():
		_build_options()

## Construit les 4 jetons (icône + libellé, voir PingMarkers.icon_for_kind/
## label_for_kind -- UN SEUL jeu de glyphes/libellés pour la roue ET les
## marqueurs reçus, jamais une seconde traduction qui pourrait diverger).
func _build_options() -> void:
	for kind in PingController.WHEEL_KINDS:
		var chip := ComicPanel.new()
		chip.bg_color = Comic.PANEL
		chip.border_color = Comic.RULE
		chip.content_margin = Comic.SP_2
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.custom_minimum_size = Vector2(Comic.SP_8, Comic.SP_6)
		add_child(chip)
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		chip.body.add_child(col)
		var icon := Comic.label(PingMarkers.icon_for_kind(kind), Comic.SIZE_DISPLAY_SM, Comic.TEXT, Comic.FONT_BOLD)
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(icon)
		var lbl := Comic.label(PingMarkers.label_for_kind(kind), Comic.SIZE_FLOOR, Comic.TEXT_DIM, Comic.FONT_LABEL)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(lbl)
		_chips.append(chip)
	_layout_options()

## Disposition en croix autour du centre de l'écran -- ordre
## `PingController.WHEEL_KINDS` = [haut, droite, bas, gauche], EXACTEMENT la
## correspondance de `option_for_direction` ci-dessous (une seule convention
## d'angle pour le calcul ET l'affichage).
func _layout_options() -> void:
	var offsets := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	for i in _chips.size():
		var chip := _chips[i]
		var off: Vector2 = offsets[i] * Comic.SP_8 * 1.5
		chip.set_anchors_preset(Control.PRESET_CENTER)
		chip.position = off - chip.custom_minimum_size * 0.5

## Ouvre la roue (début de maintien) -- aucune option survolée tant que
## `update_direction` n'a pas reçu une direction hors zone morte.
func open() -> void:
	_hovered_index = -1
	visible = true
	_update_highlight()

## `dir` : direction courante (écart souris/centre normalisé, OU stick droit
## brut -- voir PingController._wheel_direction), pas de lecture Input ici :
## purement une entrée, testable sans périphérique.
func update_direction(dir: Vector2) -> void:
	_hovered_index = option_for_direction(dir)
	_update_highlight()

## Kind actuellement survolé, "" si aucun (zone morte) -- lu par
## PingController pour construire son appel, et par les tests pour vérifier
## `update_direction` sans dépendre du rendu (voir `_update_highlight`).
func hovered_kind() -> String:
	return PingController.WHEEL_KINDS[_hovered_index] if _hovered_index >= 0 else ""

## Ferme la roue et renvoie le kind choisi ("" = maintien relâché en zone
## morte, ANNULÉ -- jamais un choix par défaut) ; émet `option_chosen` pour
## un choix réel.
func close_and_confirm() -> String:
	visible = false
	var kind := hovered_kind()
	_hovered_index = -1
	_update_highlight()
	if kind != "":
		option_chosen.emit(kind)
	return kind

func _update_highlight() -> void:
	for i in _chips.size():
		var chip := _chips[i]
		if not is_instance_valid(chip):
			continue
		var on := i == _hovered_index
		chip.bg_color = Comic.PANEL_HI if on else Comic.PANEL
		chip.border_color = Comic.BULLET if on else Comic.RULE
		chip.border_width = Comic.RULE_W_STRONG if on else Comic.RULE_W

# ================================================================= PUR

## Index (0..3) de l'option la plus proche de `dir` dans
## `PingController.WHEEL_KINDS`, ou -1 si `dir.length() < deadzone` (zone
## morte, aucune intention claire). Convention d'angle : `dir = (0, -1)`
## ("haut" écran, souris/stick poussé vers le haut) -> index 0 ; sens
## horaire ensuite (droite -> index 1, bas -> index 2, gauche -> index 3),
## EXACTEMENT la disposition de `_layout_options`. Pure -- testée avec des
## `Vector2` synthétiques (souris ET manette partagent ce même calcul, voir
## doc de classe).
static func option_for_direction(dir: Vector2, deadzone: float = DEADZONE) -> int:
	if dir.length() < deadzone:
		return -1
	var count := PingController.WHEEL_KINDS.size()
	var angle := wrapf(dir.angle() + PI / 2.0, 0.0, TAU)
	var slice := TAU / count
	return int(floor((angle + slice * 0.5) / slice)) % count
