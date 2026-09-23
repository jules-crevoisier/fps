## AbilityBar.gd
## Rangée de badges de capacité (bas-centre), alimentée par
## `AbilityController.slot_info()` (contrat inchangé). Reconstruit les badges
## uniquement quand le nombre de slots change (agent stable en cours de partie).
class_name AbilityBar
extends HBoxContainer

var _chips: Array = []

func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", Comic.SP_2)
	Comic.anchor(self, Control.PRESET_BOTTOM_WIDE)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Hauteur figée explicitement (ne dépend pas de la taille mini des badges,
	# qui n'existent pas encore au premier `_ready` — voir `refresh`).
	custom_minimum_size = Vector2(0, ComicChip.SIZE.y)
	offset_top = -(ComicChip.SIZE.y + Comic.SAFE_MARGIN)
	offset_bottom = -Comic.SAFE_MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func refresh(infos: Array) -> void:
	if _chips.size() != infos.size():
		for c in get_children():
			c.queue_free()
		_chips.clear()
		for i in infos.size():
			var s: Dictionary = infos[i]
			var chip := ComicChip.new()
			chip.setup(str(s.slot), str(s.name), bool(s.ult))
			chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			add_child(chip)
			_chips.append(chip)
		return
	for i in infos.size():
		var s: Dictionary = infos[i]
		var chip: ComicChip = _chips[i]
		if bool(s.ult):
			var txt := "PRÊT" if s.ready else "%d%%" % int(float(s.ratio) * 100.0)
			chip.set_status(txt, bool(s.ready), float(s.ratio), -1)
		elif int(s.charges) > 0:
			chip.set_status("PRÊT" if s.charges > 0 else "", true, 1.0, int(s.charges))
		else:
			chip.set_status("%d%%" % int(float(s.ratio) * 100.0), false, float(s.ratio), 0)
