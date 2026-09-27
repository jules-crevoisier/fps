## KoBanner.gd
## Bandeau de confirmation de kill LOCAL (contrat lead 2026-09-27, HUD en jeu,
## point 7) — plaque JAUNE inclinée "K.O. !" (display ROUGE) + nom de la
## victime (résolu par GameHUD.gd depuis le dernier GameWorld.kill_logged qui
## désigne le joueur local comme tueur ; "" si pas encore reçu -> le nom est
## simplement masqué). Centré horizontalement, haut fixé à `TOP_Y` (sous la
## zone centrale 40%x40%, HudFormat.center_zone_rect). Timing : pop
## (UiTokens.POP_S, échelle 1.08 -> 1), tenue 1.2 s, fondu 0.2 s.
class_name KoBanner
extends Control

const TOP_Y := 780.0
const HOLD_S := 1.2
const FADE_S := 0.2
const POP_OVERSHOOT_SCALE := 1.08

var _plate: PanelContainer
var _ko_label: Label
var _victim_label: Label
var _tween: Tween


func _ready() -> void:
	Comic.anchor(self, Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false


func _build() -> void:
	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.YELLOW, UiTokens.SKEW_DEG, UiTokens.DROP, UiTokens.STROKE, Vector2(UiTokens.S4, UiTokens.S2)))
	_plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_plate.offset_top = TOP_Y
	_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH   # centré : grandit des deux côtés
	_plate.pivot_offset = _plate.size * 0.5

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.S3)

	_ko_label = UiTokens.make_label("K.O. !", UiTokens.display(UiTokens.T_L, UiTokens.RED))
	row.add_child(_ko_label)

	_victim_label = UiTokens.make_label("", UiTokens.label(UiTokens.T_M, UiTokens.INK, 0, true), true)
	row.add_child(_victim_label)

	_plate.add_child(row)
	add_child(_plate)


## GameHUD.gd -> Weapon.hit_confirmed(_, _, _, is_kill) sur le joueur LOCAL.
## `victim_name` : "" si le kill_logged correspondant n'est pas encore arrivé
## (le bandeau montre alors juste "K.O. !", jamais un nom vide affiché).
func show_ko(victim_name: String) -> void:
	_victim_label.text = victim_name.to_upper()
	_victim_label.visible = not victim_name.is_empty()
	visible = true
	_plate.pivot_offset = _plate.size * 0.5
	_plate.scale = Vector2.ONE * POP_OVERSHOOT_SCALE
	_plate.modulate.a = 1.0
	if _tween and is_instance_valid(_tween):
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_plate, "scale", Vector2.ONE, UiTokens.POP_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(HOLD_S)
	_tween.tween_property(_plate, "modulate:a", 0.0, FADE_S)
	_tween.tween_callback(func(): visible = false)
