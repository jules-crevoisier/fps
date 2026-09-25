## KitTrame.gd
## Kit de composants autocollant (ART-31, docs/STYLE_BIBLE.md §8.1/§8.2) —
## Couche 3 « Trame » : *célébrer* un moment (match trouvé, verrouillage
## d'agent, manche gagnée, multi-kill, MVP, niveau de compte) puis
## disparaître. Enveloppe fine autour de `assets/shaders/ui_halftone.gdshader`
## (jeton `halftone` : points de 4 px au pas de 8 px, 45°, encre à 18 %
## d'opacité ou pinceau).
##
## Règle d'or #4 (§8.1) : « la trame ne dure pas » — jamais posée en
## permanence. `play()` anime une révélation radiale sur
## `Comic.DUR_BURST_MIN..MAX` (600–1200 ms) puis s'efface, SAUF `hold_flat`
## (usage menu : « puis elle se fige en aplat », §8.1 règle 4) qui la laisse
## en aplat plein jusqu'au prochain `play()`/`clear()`. Mouvement réduit : pas
## d'animation — la trame apparaît statique (tokens.json
## "reduced_motion.allow": fade — mais la trame elle-même n'a pas de fondu
## d'entrée séparé prévu par le jeton, donc `reveal` est posé directement à 1
## sans transition, jamais un tween).
class_name KitTrame
extends ColorRect

const SHADER := preload("res://assets/shaders/ui_halftone.gdshader")
## Opacité « pinceau » (variante non-encre) — plus marquée que l'encre 18 %
## pour rester lisible sur un fond déjà rouge/saturé au moment d'un multi-kill.
const BRUSH_OPACITY := 0.35

## true = encre (défaut, 18 % — jeton `halftone`) ; false = pinceau.
@export var ink_variant: bool = true:
	set(v):
		ink_variant = v
		_apply_color()
## Valeurs de DÉPART de `reveal`/`freeze` appliquées dès `_ready()` — utilisé
## par la galerie statique (`scenes/dev/ui_kit_gallery.tscn`) pour figer une
## capture à mi-révélation ; en jeu normal, laisser à leurs défauts et piloter
## uniquement via `play()`/`clear()`.
@export var preview_reveal: float = 0.0:
	set(v):
		preview_reveal = v
		if _mat:
			_mat.set_shader_parameter("reveal", v)
@export var preview_freeze: float = 0.0:
	set(v):
		preview_freeze = v
		if _mat:
			_mat.set_shader_parameter("freeze", v)

var _mat: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0.0, 0.0, 0.0, 0.0)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	resized.connect(_sync_rect_size)
	_sync_rect_size()
	_apply_color()
	_mat.set_shader_parameter("reveal", preview_reveal)
	_mat.set_shader_parameter("freeze", preview_freeze)


func _sync_rect_size() -> void:
	if _mat:
		_mat.set_shader_parameter("rect_size", size)


func _apply_color() -> void:
	if _mat == null:
		return
	var c := Comic.HARD_SHADOW_COLOR if ink_variant else Comic.BRUSH
	_mat.set_shader_parameter("dot_color", Color(c.r, c.g, c.b, 1.0))
	_mat.set_shader_parameter("dot_opacity", Comic.HALFTONE_INK_ALPHA if ink_variant else BRUSH_OPACITY)


## Joue un moment. `hold_flat` (menus) : reste figée en aplat plein après la
## révélation, jusqu'au `clear()` explicite de l'appelant — jamais livrée à
## une horloge interne (§8.1 règle 4 : « ≤ 2 s » est la responsabilité de
## l'écran qui affiche le moment, pas de ce composant).
func play(hold_flat: bool = false) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if Comic.reduced_motion():
		_mat.set_shader_parameter("reveal", 1.0)
		_mat.set_shader_parameter("freeze", 1.0 if hold_flat else 0.0)
		return
	_mat.set_shader_parameter("reveal", 0.0)
	_mat.set_shader_parameter("freeze", 0.0)
	_tween = create_tween()
	_tween.tween_method(_set_reveal, 0.0, 1.0, Comic.DUR_BURST_MIN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if hold_flat:
		_tween.tween_property(_mat, "shader_parameter/freeze", 1.0, 0.2)
	else:
		_tween.tween_interval(0.3)
		_tween.tween_method(_set_reveal, 1.0, 0.0, Comic.DUR_BURST_MIN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


## Efface immédiatement (retour d'un menu qui avait figé la trame en aplat).
func clear() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_mat.set_shader_parameter("reveal", 0.0)
	_mat.set_shader_parameter("freeze", 0.0)


func _set_reveal(v: float) -> void:
	_mat.set_shader_parameter("reveal", v)
