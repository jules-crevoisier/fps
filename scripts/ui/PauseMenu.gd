## PauseMenu.gd
## Menu pause v4 « Encre, jaune, italique » (UX-32, docs/UI_DIRECTION_BL3.md
## §6 « Pause : la pile du menu principal (66 px) sur le jeu assombri à
## 70 %, sans cadre ») — remplace le bandeau pinceau + la case charcoal v2/v3
## (BrushHeader + ComicPanel, tous deux boîtés) : « sans cadre » est un
## critère d'acceptation bloquant, donc plus aucun panneau/bordure ici, juste
## le texte (capitales italiques papier 66 px, zéro fond au repos, plate_hi
## au survol/pressé, anneau papier au focus manette — même traitement que la
## pile de navigation de MainMenu.gd, dupliqué ici : les deux fichiers restent
## indépendants par contrat, voir leurs docstrings d'en-tête respectives).
##
## Ouvert par l'action "pause" (Échap clavier / bouton Start manette).
## Navigable au clavier ET à la manette (focus + actions ui_*). Ne met pas
## l'arbre en pause (sûr en multijoueur) ; libère la souris et gèle les
## entrées du joueur.
extends CanvasLayer

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const OPTIONS_SCRIPT := preload("res://scripts/ui/OptionsMenu.gd")

## Assombrissement du jeu derrière la pause (direction v4 §6 « assombri à
## 70 % ») — remplace l'alpha 0,65 v2/v3. Teinte `ink` (la plus sombre du
## jeton v4), pas `BG` (v2/v3) : cohérent avec le vocabulaire « encre » de
## cette direction.
const DIM_ALPHA := 0.70

## Pile partagée des overlays modaux (Pause/Achat/fin de match, BUG-U01) :
## chaque overlay s'ajoute au groupe à l'ouverture et s'en retire à la
## fermeture ; `Input.mouse_mode` n'est recapturé que quand la pile est vide,
## pour ne jamais voler la souris à un overlay resté ouvert en dessous.
const MODAL_GROUP := "ui_modal_stack"
## Groupe dédié : BuyMenu s'appuie dessus pour geler la touche "buy_menu"
## pendant que Pause est affiché (BUG-U01).
const PAUSE_GROUP := "ui_pause_open"

var _bg: ColorRect
## Pile « Reprendre / Options / Quitter au menu » — direction v4 §6, AUCUN
## panneau autour (« sans cadre »).
var _stack: VBoxContainer
var _options: Control
var _first_button: Button
var _open: bool = false

func _ready() -> void:
	layer = 10
	_build()
	_bg.visible = false
	_stack.visible = false

func _build() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(Comic.ink_color().r, Comic.ink_color().g, Comic.ink_color().b, DIM_ALPHA)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_stack = VBoxContainer.new()
	_stack.add_theme_constant_override("separation", Comic.SP_4)
	center.add_child(_stack)

	_first_button = _add_item(_stack, "Reprendre", _close)
	_add_item(_stack, "Options", _open_options)
	_add_item(_stack, "Quitter au menu", _quit_to_menu)

## Anneau de focus manette v4 (direction §4.6 « focus manette : contour
## paper 3 px décalé de 4 px ») — jamais un contour rouge (v3, marque
## abandonnée en v4).
func _nav_focus_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	s.border_color = Comic.paper_color()
	s.set_border_width_all(Comic.STROKE_FOCUS)
	s.expand_margin_left = Comic.FOCUS_RING_OFFSET_PX
	s.expand_margin_top = Comic.FOCUS_RING_OFFSET_PX
	s.expand_margin_right = Comic.FOCUS_RING_OFFSET_PX
	s.expand_margin_bottom = Comic.FOCUS_RING_OFFSET_PX
	return s

## Survol/pressé v4 (direction §4.6 « survol : plate_hi ») — jamais un
## second panneau, juste une plaque derrière le texte.
func _nav_hover_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Comic.plate_hi_color()
	s.expand_margin_left = Comic.SP_3
	s.expand_margin_right = Comic.SP_3
	s.expand_margin_top = Comic.SP_1
	s.expand_margin_bottom = Comic.SP_1
	return s

## Entrée de la pile pause — capitales italiques papier 66 px (direction v4
## §6/§4.1), `focus_mode = ALL` : atteignable clavier ET manette.
func _add_item(box: VBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_override("font", Comic.title_font_v4())
	b.add_theme_font_size_override("font_size", Comic.SIZE_66)
	b.add_theme_color_override("font_color", Comic.paper_color())
	b.add_theme_color_override("font_hover_color", Comic.paper_color())
	b.add_theme_color_override("font_focus_color", Comic.paper_color())
	b.add_theme_color_override("font_pressed_color", Comic.signal_color())
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", _nav_hover_style())
	b.add_theme_stylebox_override("pressed", _nav_hover_style())
	b.add_theme_stylebox_override("focus", _nav_focus_style())
	b.pressed.connect(cb)
	box.add_child(b)
	UiFx.press(b)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _options and is_instance_valid(_options):
			_close_options()
		elif _open:
			_close()
		else:
			_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and (_open or _options):
		if _options and is_instance_valid(_options):
			_close_options()
		else:
			_close()
		get_viewport().set_input_as_handled()

func _pause() -> void:
	_open = true
	_bg.visible = true
	_stack.visible = true
	# Fondu d'opacité seul (jamais `UiFx.reveal`, qui translate les OFFSETS) :
	# `_stack` vit dans un `CenterContainer`, qui réattribue sa position à
	# chaque re-tri de mise en page (déclenché par `visible = true` juste
	# au-dessus) — un `Tween` qui parte des offsets lus AVANT ce re-tri les
	# ramènerait ensuite vers des valeurs PÉRIMÉES pendant toute l'animation
	# (même piège que MainMenu.gd::_fade_in, documenté là-bas). `modulate:a`
	# seul ne touche ni position ni taille : sûr sur un enfant de Container.
	_stack.modulate.a = 0.0
	var tw := _stack.create_tween()
	tw.tween_property(_stack, "modulate:a", 1.0, Comic.DUR_REDUCED_FADE if Comic.reduced_motion() else Comic.DUR_REVEAL)
	add_to_group(MODAL_GROUP)
	add_to_group(PAUSE_GROUP)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _first_button:
		_first_button.grab_focus()

func _close() -> void:
	_open = false
	_bg.visible = false
	_stack.visible = false
	remove_from_group(PAUSE_GROUP)
	remove_from_group(MODAL_GROUP)
	if get_tree().get_nodes_in_group(MODAL_GROUP).is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _open_options() -> void:
	_stack.visible = false
	_options = OPTIONS_SCRIPT.new()
	_options.closed.connect(_close_options)
	add_child(_options)
	UiFx.reveal(_options)

func _close_options() -> void:
	if _options and is_instance_valid(_options):
		_options.queue_free()
	_options = null
	_stack.visible = true
	if _first_button:
		_first_button.grab_focus()

func _quit_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU)
