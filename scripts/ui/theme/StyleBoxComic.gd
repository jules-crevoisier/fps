## StyleBoxComic.gd
## La plaque de BD de la direction « Planche » : parallélogramme penché (`skew_deg`, comme
## l'italique : le haut part vers la droite), rempli de `fill`, cerclé d'un trait d'encre
## `stroke_width`, posé sur une ombre DURE décalée de `drop` (effet autocollant). Utilisable
## partout où Godot prend une StyleBox (PanelContainer, Button, ProgressBar…) : le texte des
## enfants reste droit, seule la plaque penche. La plaque reste DANS le rect du contrôle (seule
## l'ombre déborde) ; les marges intérieures ajoutent le débord de la pente pour que le contenu
## ne touche jamais les bords obliques.
@tool
class_name StyleBoxComic
extends StyleBox

@export var fill: Color = Color("FFF4E0"):
	set(v):
		fill = v
		emit_changed()
@export var stroke_color: Color = Color("1B1030"):
	set(v):
		stroke_color = v
		emit_changed()
@export var stroke_width: float = 4.0:
	set(v):
		stroke_width = v
		emit_changed()
@export var skew_deg: float = -10.0:
	set(v):
		skew_deg = v
		_update_margins()
@export var drop: Vector2 = Vector2(8, 8):
	set(v):
		drop = v
		emit_changed()
@export var drop_color: Color = Color("1B1030"):
	set(v):
		drop_color = v
		emit_changed()
## Marge intérieure voulue (px) hors débord de pente.
@export var pad: Vector2 = Vector2(24, 8):
	set(v):
		pad = v
		_update_margins()
## Hauteur de référence pour calculer le débord de pente dans les marges (px). Les plaques du
## HUD font 40 à 140 px ; 80 donne une marge juste pour la plupart.
@export var slant_ref_height: float = 80.0:
	set(v):
		slant_ref_height = v
		_update_margins()


func _init() -> void:
	_update_margins()


## Décalage horizontal total haut/bas de la pente pour une hauteur `h`.
func slant(h: float) -> float:
	return tan(deg_to_rad(absf(skew_deg))) * h


func _update_margins() -> void:
	var k := slant(slant_ref_height) * 0.5
	content_margin_left = pad.x + k
	content_margin_right = pad.x + k
	content_margin_top = pad.y + stroke_width
	content_margin_bottom = pad.y + stroke_width
	emit_changed()


## Coins du parallélogramme dans `rect` (sens horaire depuis le haut-gauche). Penché « / » pour
## un angle négatif (convention CSS skewX(-10deg) des maquettes).
func corners(rect: Rect2) -> PackedVector2Array:
	var k := slant(rect.size.y)
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x
	var y1 := rect.end.y
	if skew_deg <= 0.0:
		return PackedVector2Array([Vector2(x0 + k, y0), Vector2(x1, y0), Vector2(x1 - k, y1), Vector2(x0, y1)])
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1 - k, y0), Vector2(x1, y1), Vector2(x0 + k, y1)])


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var outer := corners(rect)
	if drop != Vector2.ZERO and drop_color.a > 0.0:
		var shadow := PackedVector2Array()
		for p in outer:
			shadow.append(p + drop)
		RenderingServer.canvas_item_add_polygon(to_canvas_item, shadow, PackedColorArray([drop_color]))
	if stroke_width > 0.0 and stroke_color.a > 0.0:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, outer, PackedColorArray([stroke_color]))
		var inner_rect := rect.grow(-stroke_width)
		if inner_rect.size.x > 0.0 and inner_rect.size.y > 0.0:
			RenderingServer.canvas_item_add_polygon(to_canvas_item, corners(inner_rect), PackedColorArray([fill]))
	else:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, outer, PackedColorArray([fill]))
