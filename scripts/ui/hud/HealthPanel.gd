## HealthPanel.gd
## Case « vitalité » (bas-gauche, UI_DIRECTION_BL3.md §5) : croix `vital` +
## nombre 66 px italique (ancre encre + ombre dure, PAS de plaque derrière —
## règle bloquante §5 #1 « zéro fond derrière le texte du HUD ») + barre
## penchée 330×26 avec crans à 25/50/75 % (§5 #3 : « VITALITÉ » supprimé, la
## croix suffit à dire ce qu'affiche le nombre).
## v4 « Encre, jaune, italique » (UX-31) : remplace le chip ComicPanel v3
## (fond charbon.bg à 80 %) par un `Control` nu — AUCUN test verrouillé
## n'instancie `HealthPanel` en dehors de GameHUD.gd (grep sur tests/, vérifié
## avant cette tâche), donc le changement de classe de base est sans risque
## de régression sur une autre suite.
## UX-36 (retour lead 2026-09-25, capture reports/checkpoints/2026-09-25_UX-31/
## 01_hud_1080p.jpg) : le remplissage de la barre passait en `paper` (blanc) à
## pleine vie et ne redevenait `vital` qu'en dessous de `LOW_HP_RATIO` -- la
## maquette bl3_hud.png montre une barre ROUGE en permanence. `bar_fill_color()`
## la fixe désormais à `vital` sans condition (voir sa doc).
class_name HealthPanel
extends Control

const LOW_HP_RATIO := 0.3
## Barre : 330×26 px à 1080p (UI_DIRECTION_BL3.md §5, ligne « bas-gauche ») —
## mise à l'échelle 720p automatique par le seul stretch canvas_items+expand
## du projet (même parti que Minimap.SIZE_PX/Comic.SAFE_MARGIN, aucune
## branche de résolution ici).
const BAR_SIZE := Vector2(330.0, 26.0)
const _CROSS_SIZE := 30.0
## Fraction de la LARGEUR TOTALE de la croix (`_CROSS_SIZE`) qu'occupe
## l'épaisseur PLEINE d'un bras (jamais la demi-épaisseur -- retour QA
## 2026-09-25 : l'ancienne lecture appliquait ce ratio directement à la
## demi-épaisseur dans `_draw_cross`, ce qui donnait des bras si épais que la
## croix se dessinait comme un carré `vital` quasi plein, plus reconnaissable
## comme une croix -- voir reports/checkpoints/2026-09-25_UX-31/01_hud_1080p.jpg,
## coin bas-gauche). 0,32 == un tiers, proportion usuelle d'une croix
## médicale/suisse (grille 3x3, la bande centrale = un tiers).
const _CROSS_ARM_RATIO := 0.32
const _GAP := Comic.SP_2
const _NOTCH_FRACTIONS := [0.25, 0.5, 0.75]

var _number: Label
var _ratio: float = 1.0
var _low: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(BAR_SIZE.x, float(Comic.SIZE_66) + _GAP + BAR_SIZE.y)
	Comic.anchor(self, Control.PRESET_BOTTOM_LEFT)
	# PRESET_BOTTOM_LEFT n'ancre qu'un POINT (bas-gauche) -- sans ceci, la
	# croissance par défaut (GROW_DIRECTION_END des deux côtés) pousse tout le
	# panneau SOUS le bord bas de l'écran (bug constaté à la capture v4 :
	# HealthPanel invisible malgré une mise à jour de _number/_ratio correcte).
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	grow_horizontal = Control.GROW_DIRECTION_END
	offset_left = Comic.SAFE_MARGIN
	offset_bottom = -Comic.SAFE_MARGIN

	# Nombre encré directement sur la 3D (§5 #1) : contour + ombre dure
	# viennent de `Comic.ink_label`, jamais d'un StyleBox derrière.
	_number = Comic.ink_label("100", Comic.SIZE_66, Comic.paper_color(), Comic.number_font_v4())
	_number.position = Vector2(_CROSS_SIZE + Comic.SP_2, 0.0)
	add_child(_number)

	resized.connect(queue_redraw)

## `current`/`maximum` : mêmes unités que `Health.current_health`/`max_health`
## (hors de mon périmètre d'écriture, lu tel quel par GameHUD._on_health_changed).
func update_health(current: float, maximum: float) -> void:
	_ratio = clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	_low = _ratio < LOW_HP_RATIO
	if _number:
		_number.text = "%d" % roundi(current)
		_number.add_theme_color_override("font_color", Comic.vital_color() if _low else Comic.paper_color())
	queue_redraw()

## Remplissage de la barre de vie (retour lead 2026-09-25, UX-36) : `vital`
## TOUJOURS -- une fonction pure (pas de branche sur `_low`) plutôt qu'un
## littéral inline dans `_draw_bar`, pour rester vérifiable directement par
## un test (`_draw` ne s'exécute pas hors rendu réel, voir tests/ui/test_hud_v4.gd).
func bar_fill_color() -> Color:
	return Comic.vital_color()


func _draw() -> void:
	_draw_cross()
	_draw_bar()

## Croix `vital` (§5 « croix vital ») : deux rectangles superposés — une
## passe `ink` légèrement plus large en dessous (contour), une passe `vital`
## par-dessus (remplissage) — même grammaire de contour que `Comic.ink_label`,
## sans dépendre d'un `Label`/glyphe de police pour ce pictogramme.
func _draw_cross() -> void:
	var center := Vector2(_CROSS_SIZE * 0.5, float(Comic.SIZE_66) * 0.5)
	# Demi-épaisseur d'un bras == moitié de l'épaisseur PLEINE (voir la doc de
	# `_CROSS_ARM_RATIO`) : sans ce `* 0.5`, l'épaisseur pleine effective
	# doublait le ratio documenté et produisait un bras bien plus large que
	# long (bug corrigé ici).
	var half_thickness := _CROSS_SIZE * _CROSS_ARM_RATIO * 0.5
	_draw_cross_shape(center, _CROSS_SIZE * 0.5, half_thickness + Comic.STROKE_INK, Comic.ink_color())
	_draw_cross_shape(center, _CROSS_SIZE * 0.5 - Comic.STROKE_INK, half_thickness, Comic.vital_color())

func _draw_cross_shape(center: Vector2, half_length: float, half_thickness: float, color: Color) -> void:
	draw_rect(Rect2(center - Vector2(half_thickness, half_length), Vector2(half_thickness * 2.0, half_length * 2.0)), color, true)
	draw_rect(Rect2(center - Vector2(half_length, half_thickness), Vector2(half_length * 2.0, half_thickness * 2.0)), color, true)

## Parallélogramme cisaillé de `tan(Comic.SLANT_DEG)` sur X (même géométrie
## que KitSlantBar/KitSlantTile, dupliquée ici : ces deux composants sont des
## `BaseButton` interactifs, pas le bon outil pour une simple barre de vie
## statique, et ne sont de toute façon pas dans mon périmètre d'écriture).
func _slant_points(origin: Vector2, sz: Vector2) -> PackedVector2Array:
	var shear := sz.y * tan(deg_to_rad(Comic.SLANT_DEG))
	return PackedVector2Array([
		origin + Vector2(shear, 0.0),
		origin + Vector2(sz.x + shear, 0.0),
		origin + Vector2(sz.x, sz.y),
		origin + Vector2(0.0, sz.y),
	])

## Barre penchée 330×26, crans à 25/50/75 % (§5 #3 : la forme remplace la
## légende « VITALITÉ »). Piste `plate`, remplissage `vital` jusqu'à `_ratio`
## (retour lead 2026-09-25, UX-36 : « remplissage vital comme la maquette,
## pas blanc » — le remplissage RESTE rouge à pleine vie, exactement comme la
## barre de vie de la maquette bl3_hud.png ; seul le nombre encré passe en
## `vital` en dessous de `LOW_HP_RATIO`, voir `update_health`), contour `ink`
## 3 px.
func _draw_bar() -> void:
	var origin := Vector2(0.0, float(Comic.SIZE_66) + _GAP)
	var track := _slant_points(origin, BAR_SIZE)
	draw_colored_polygon(track, Comic.plate_color())
	if _ratio > 0.001:
		var fill := _slant_points(origin, Vector2(BAR_SIZE.x * _ratio, BAR_SIZE.y))
		draw_colored_polygon(fill, bar_fill_color())
	var closed := track.duplicate()
	closed.append(track[0])
	draw_polyline(closed, Comic.ink_color(), Comic.STROKE_INK)
	for f in _NOTCH_FRACTIONS:
		var x: float = BAR_SIZE.x * f
		var shear := BAR_SIZE.y * tan(deg_to_rad(Comic.SLANT_DEG))
		draw_line(origin + Vector2(x + shear, 0.0), origin + Vector2(x, BAR_SIZE.y), Comic.ink_color(), 2.0)
