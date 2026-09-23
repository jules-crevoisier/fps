## ScorePanel.gd
## Case « score » (haut-centre) : glyphe/score équipe 1, minuteur, score/glyphe
## équipe 2 (design.md §8 : « [BLEU 7 ● 1:42 ▼ 5 ROUGE] »), puis la ligne
## d'objectif/état de manche (mode.hud_state). Masquée entièrement hors mode
## de jeu (entraînement sans "game_mode") — jamais un cadre vide à l'écran.
class_name ScorePanel
extends ComicPanel

var _score_label: Label
var _objective_label: Label

func _ready() -> void:
	bg_color = Comic.PANEL
	border_width = Comic.RULE_W
	Comic.anchor(self, Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_END
	offset_top = Comic.SP_2
	visible = false

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_1 / 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(v)

	_score_label = Comic.number_label("", Comic.SIZE_SUBTITLE, Comic.TEXT)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_score_label)

	_objective_label = Comic.label("", Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_objective_label)

## `timer_text` : minuteur déjà formaté (mm:ss) par l'appelant, "" si aucun
## (ex. juste après la victoire). Rien ne s'affiche si `mode` est absent
## (entraînement) — voir `GameHUD._process`, qui n'appelle `update` que si un
## nœud "game_mode" existe.
func update(team0: int, team1: int, winner: int, hud_state: String, overtime: bool, timer_text: String) -> void:
	visible = true
	if winner >= 0:
		_score_label.text = "%d   %s ÉQ.%d GAGNE   %s %d" % [team0, Comic.team_glyph(winner == 0), winner + 1, Comic.team_glyph(winner == 1), team1]
		_objective_label.text = ""
	else:
		var mid := ("   %s   " % timer_text) if timer_text != "" else "   —   "
		_score_label.text = "%s %d%s%d %s" % [Comic.team_glyph(true), team0, mid, team1, Comic.team_glyph(false)]
		_objective_label.text = "%s%s" % [hud_state, " · PROLONGATION" if overtime else ""]

func hide_panel() -> void:
	visible = false
