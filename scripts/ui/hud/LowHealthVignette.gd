## LowHealthVignette.gd
## Vignette de vie basse (design.md v2 §11 « Red means brand or low HP » ;
## contract-r4a.md "R4-FX" #3) : hachures ROUGE PINCEAU rampant depuis les 4
## bords sous 35 % PV (HitFeedback.vignette_thickness), pulsation <= 1 Hz
## (vignette_pulse) — désactivée si Comic.reduced_motion() (Settings.reduced_motion).
## Bandes en cadre uniquement : ne recouvre JAMAIS la zone centrale
## (design.md §12), même à 0 PV (VIGNETTE_MAX_THICKNESS reste petit devant la
## moitié de l'écran).
class_name LowHealthVignette
extends Control

var _ratio: float = 1.0
var _time: float = 0.0
var _reduced_motion: bool = false

var _top: TextureRect
var _bottom: TextureRect
var _left: TextureRect
var _right: TextureRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Comic.anchor(self, Control.PRESET_FULL_RECT)
	_top = _make_band(Control.PRESET_TOP_WIDE)
	_bottom = _make_band(Control.PRESET_BOTTOM_WIDE)
	_left = _make_band(Control.PRESET_LEFT_WIDE)
	_right = _make_band(Control.PRESET_RIGHT_WIDE)
	for b in [_top, _bottom, _left, _right]:
		add_child(b)
	_reduced_motion = Comic.reduced_motion()
	visible = false
	set_process(true)

func _make_band(preset: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Comic.hatch_texture(Comic.SP_2, 3, Comic.BRUSH, Color(0, 0, 0, 0))
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Comic.anchor(t, preset)
	return t

func update_health(current: float, maximum: float) -> void:
	_ratio = clampf(current / maxf(maximum, 1.0), 0.0, 1.0)

func _process(delta: float) -> void:
	if _ratio >= HitFeedback.VIGNETTE_HP_THRESHOLD:
		visible = false
		return
	visible = true
	_apply_thickness(HitFeedback.vignette_thickness(_ratio))
	var alpha := 1.0
	if not _reduced_motion:
		_time += delta
		alpha = HitFeedback.vignette_pulse(_time)
	modulate.a = alpha

func _apply_thickness(t: float) -> void:
	_top.offset_bottom = t
	_bottom.offset_top = -t
	_left.offset_right = t
	_right.offset_left = -t

## Capture d'écran (tests/ui/capture_shots.gd) : force un ratio de vie sans
## dépendre d'un vrai combat.
func debug_force_ratio(ratio: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
