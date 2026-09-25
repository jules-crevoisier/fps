## ComicBar.gd
## Barre de progression v2 (vitalité, pose/désamorçage de bombe, stats
## d'arme) : piste `panel_hi`, remplissage plein à gauche jusqu'à `value`
## (0..1), trait 1 px `rule`, graduations tous les 1/`ticks` (pastilles sans
## segmenter le remplissage). Rectangle droit — design.md v2 n'a plus de barres
## inclinées (grammaire "brush", pas "comic panel biseauté").
##
## ART-35 (HUD v3) : revu contre STYLE_BIBLE v3 §8.3/§8.6 et CHK-32, CHK-33,
## CHK-34, CHK-35, CHK-40 -- aucun changement de comportement nécessaire ici.
## Ce composant est générique et sans état de jeu propre (ni taille de police,
## ni marge de sécurité, ni hexagone qui lui soit propre) ; la vie basse en
## pinceau (< 30 %, HealthPanel.update_health) pilote déjà `fill_color`/
## `border_color` via les `@export` ci-dessous, et les munitions basses
## (AmmoPanel.update_ammo) sont un texte seul, sans ComicBar. Les règles de
## taille/marge/couleur d'agent (CHK-32/33/34/40) sont posées par les
## panneaux qui instancient ce contrôle (HealthPanel, RoundPanel), pas ici.
class_name ComicBar
extends Control

@export var value: float = 1.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var fill_color: Color = Comic.ALLY
@export var bg_color: Color = Comic.PANEL_HI
@export var border_color: Color = Comic.RULE
@export var border_width: int = Comic.RULE_W
@export var ticks: int = 5

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), bg_color, true)
	if value > 0.001:
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * value, size.y)), fill_color, true)
	for i in range(1, ticks):
		var x := size.x * float(i) / float(ticks)
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), border_color, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), border_color, false, border_width)
