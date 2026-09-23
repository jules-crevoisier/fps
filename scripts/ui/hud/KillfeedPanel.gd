## KillfeedPanel.gd
## Pile de cartouches (haut-droite), 5 maximum, 4 s chacune (design.md v2 §12).
## Convention d'équipe reprise du reste du HUD : équipe 0 = Allié (●), équipe 1
## = ennemi (▼, Comic.enemy_color() — suit Settings.enemy_color, Magenta/Citron).
## Une entrée de kill LOCAL (contract-r4a.md "R4-FX" #4) est mise en évidence :
## trait Allié alourdi, même langage que ComicChip (ultime prêt)/HealthPanel
## (vie basse) — jamais le rouge `brush`, réservé à la marque/vie basse.
class_name KillfeedPanel
extends VBoxContainer

const MAX_ENTRIES := 5
const ENTRY_LIFETIME := 4.0

func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", Comic.SP_1)
	Comic.anchor(self, Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_top = Comic.SP_7
	offset_right = -Comic.SAFE_MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func push(killer: String, victim: String, killer_team: int, is_local: bool = false) -> void:
	var color := Comic.ALLY if killer_team == 0 else Comic.enemy_color()
	var glyph := Comic.team_glyph(killer_team == 0)

	var panel := ComicPanel.new()
	panel.bg_color = Comic.PANEL_HI if is_local else Comic.PANEL
	panel.border_width = Comic.RULE_W_STRONG if is_local else Comic.RULE_W
	panel.border_color = Comic.ALLY if is_local else Comic.RULE
	panel.content_margin = Comic.SP_2
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	move_child(panel, 0)

	var l := Comic.label("%s %s   ▸   %s" % [glyph, killer, victim], Comic.SIZE_BODY, color, Comic.FONT_BOLD)
	panel.body.add_child(l)

	if get_child_count() > MAX_ENTRIES:
		get_child(get_child_count() - 1).queue_free()

	get_tree().create_timer(ENTRY_LIFETIME).timeout.connect(func():
		if is_instance_valid(panel):
			panel.queue_free())
