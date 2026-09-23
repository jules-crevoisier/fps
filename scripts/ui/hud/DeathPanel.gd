## DeathPanel.gd
## Voile plein écran à la mort : teinte charcoal (jamais rouge — le rouge est
## réservé à la marque/vie basse, design.md v2 §11), titre bandeau pinceau.
class_name DeathPanel
extends Control

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var tint := ColorRect.new()
	tint.color = Color(Comic.BG.r, Comic.BG.g, Comic.BG.b, 0.6)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)

	var v := VBoxContainer.new()
	Comic.anchor(v, Control.PRESET_CENTER)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", Comic.SP_2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)

	var t := Comic.title_label("Éliminé", Comic.SIZE_DISPLAY_XL, Comic.TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := Comic.label("Réapparition imminente…", Comic.SIZE_SUBTITLE, Comic.TEXT_DIM, Comic.FONT_BODY)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)

func show_death() -> void:
	visible = true

func hide_death() -> void:
	visible = false
