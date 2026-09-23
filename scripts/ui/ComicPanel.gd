## ComicPanel.gd
## Panneau charcoal v2 (design.md §11 "Panels: radius 2, a 1 px rule, never
## nested") : StyleBoxFlat dessiné via `draw_style_box` (coins arrondis,
## anti-aliasing gratuits). Bloc de base du HUD et des menus. Le contenu se
## place dans `body`, un MarginContainer déjà ajouté en enfant (marge =
## `content_margin`). `selected` ajoute un soulignement pinceau (design.md §11
## "Selected: brush underline") SANS imbriquer un second panneau.
class_name ComicPanel
extends Control

@export var bg_color: Color = Comic.PANEL:
	set(v):
		bg_color = v
		_rebuild_style()
@export var border_color: Color = Comic.RULE:
	set(v):
		border_color = v
		_rebuild_style()
@export var border_width: int = Comic.RULE_W:
	set(v):
		border_width = v
		_rebuild_style()
@export var radius: int = Comic.PANEL_RADIUS:
	set(v):
		radius = v
		_rebuild_style()
@export var content_margin: int = Comic.SP_4:
	set(v):
		content_margin = v
		if body:
			for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
				body.add_theme_constant_override(m, content_margin)
## Soulignement pinceau (design.md §11 "Selected") — jamais un second panneau.
@export var selected: bool = false:
	set(v):
		selected = v
		queue_redraw()

var body: MarginContainer
var _style: StyleBoxFlat

## `body` est construit ici (PAS dans `_ready()`) : un appelant construit
## très souvent tout un sous-arbre détaché (`ComicPanel.new()` puis
## `panel.body.add_child(...)` plusieurs fois) AVANT de l'attacher où que ce
## soit — un nœud détaché (ou dont aucun ancêtre n'est encore dans l'arbre)
## n'a jamais reçu `_ready()`, donc `body` y serait encore `null`. `_init()`
## s'exécute IMMÉDIATEMENT à `.new()`, sans dépendre de l'arbre : `body`
## existe donc toujours dès la ligne suivant le constructeur.
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	body = MarginContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		body.add_theme_constant_override(m, content_margin)
	add_child(body)
	resized.connect(queue_redraw)
	# `body` (MarginContainer) réémet lui-même `minimum_size_changed` à CHAQUE
	# changement de taille mini d'un descendant, à n'importe quelle profondeur
	# (comportement standard des Container Godot). C'est le signal à écouter
	# ici — `child_entered_tree` ne se déclenche qu'une fois (premier enfant
	# direct de `body`) et ratait tout contenu ajouté plus profondément après.
	body.minimum_size_changed.connect(update_minimum_size)
	_rebuild_style()

## Remonte la taille min du contenu (comme le ferait un PanelContainer natif).
func _get_minimum_size() -> Vector2:
	if body == null:
		return Vector2.ZERO
	return body.get_combined_minimum_size()

func set_style(bg: Color, border: Color = Comic.RULE, w: int = Comic.RULE_W) -> void:
	bg_color = bg
	border_color = border
	border_width = w
	_rebuild_style()

func _rebuild_style() -> void:
	_style = Comic.panel_style(bg_color, border_color, radius, border_width)
	queue_redraw()

func _draw() -> void:
	if _style == null:
		return
	draw_style_box(_style, Rect2(Vector2.ZERO, size))
	if selected and size.x > 0.0:
		var t := maxf(3.0, size.y * 0.02)
		draw_rect(Rect2(Vector2(0, size.y - t), Vector2(size.x, t)), Comic.BRUSH, true)
