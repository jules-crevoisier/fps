## KillWordBurst.gd
## Mot-bruit de kill LOCAL (design.md v2 §13 « Onomatopée » ; contract-r4a.md
## "R4-FX" #4) : halo ComicBurst pinceau + mot en Protest Revolution (design.md
## §11 : seul usage restant de cette police), <= 300 ms (60 in / 180 hold /
## 60 out, HitFeedback.burst_alpha/burst_scale), un seul à la fois (voir
## `is_busy`, consommé par GameHUD). Mouvement réduit (Comic.reduced_motion(),
## design.md §13 « Reduced motion: fades only ») : fondu conservé, pas de
## "pop" d'échelle.
class_name KillWordBurst
extends Control

signal finished

var _burst: ComicBurst
var _label: Label
var _elapsed: float = -1.0
var _reduced_motion: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_burst = ComicBurst.new()
	_burst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_burst)
	_label = Comic.onomatopoeia_label("", Comic.SIZE_DISPLAY_LG, Comic.TEXT_ON_BRUSH)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)
	_reduced_motion = Comic.reduced_motion()
	set_process(false)

func is_busy() -> bool:
	return _elapsed >= 0.0

## `rect` : voir HitFeedback.burst_rect (déjà hors zone centrale, design.md §4/§8).
func play(word: String, rect: Rect2) -> void:
	position = rect.position
	size = rect.size
	pivot_offset = rect.size * 0.5
	_label.text = word
	visible = true
	_elapsed = 0.0
	set_process(true)
	_apply_frame()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > HitFeedback.BURST_DURATION:
		visible = false
		_elapsed = -1.0
		set_process(false)
		finished.emit()
		return
	_apply_frame()

func _apply_frame() -> void:
	scale = Vector2.ONE if _reduced_motion else Vector2.ONE * HitFeedback.burst_scale(_elapsed)
	modulate.a = HitFeedback.burst_alpha(_elapsed)
