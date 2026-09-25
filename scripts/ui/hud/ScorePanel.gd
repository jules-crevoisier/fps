## ScorePanel.gd
## Case « score » (haut-centre, UI_DIRECTION_BL3.md §5) : glyphe/score ALLIÉ à
## gauche, minuteur, score/glyphe ENNEMI à droite — RELATIF au joueur local
## (docs/research/04_ui_ux.md §2.3 : équipe 1 locale voit SON score à gauche,
## jamais l'équipe 0 par défaut), puis la ligne d'objectif/état de manche
## (mode.hud_state). En fin de match, cette ligne devient VICTOIRE/DÉFAITE
## pour le joueur local (jamais « ÉQ.%d GAGNE », §2.3 « Fin de match »).
## Masquée entièrement hors mode de jeu (entraînement sans "game_mode") —
## jamais un cadre vide à l'écran.
## v4 « Encre, jaune, italique » (UX-31) : remplace le chip ComicPanel v3
## (fond charbon.bg à 80 %) par du texte encré direct (§5 #1 « zéro fond
## derrière le texte du HUD »). Le format EXACT de `_score_label.text`/
## `_objective_label.text` (espaces, ordre, « VICTOIRE »/« DÉFAITE ») est
## VERROUILLÉ par tests/ui/test_team_relative.gd (hors de ma liste de
## fichiers) : `update()` reste caractère pour caractère identique.
##
## Retour QA 2026-09-25 : §5 exige TROIS tailles distinctes sur l'ancre
## haut-centre (score allié 66, minuteur 37 -- « plaque penchée », score
## ennemi 66 -- « bloc h 52 »), impossible à obtenir avec un SEUL `Label`
## (Godot n'a qu'une taille de police par `Label`) sans casser le test
## verrouillé ci-dessus, qui fige `_score_label.text` comme une phrase UNIQUE
## combinant les trois. `_score_label` reste donc un porteur de TEXTE, jamais
## ajouté à l'arbre (`add_child`), UNIQUEMENT pour ce contrat de test externe
## -- l'affichage RÉEL passe par `_ally_score_label`/`_timer_label`/
## `_enemy_score_label` ci-dessous, aux tailles §5 exactes. Pas de plaque
## peinte derrière le minuteur (§5 #1 étant bloquante, sans exception
## documentée -- même lecture que KillfeedPanel.gd) : seule l'italique du
## nombre en suggère l'inclinaison.
class_name ScorePanel
extends Control

var _score_label: Label
var _objective_label: Label
var _ally_score_label: Label
var _timer_label: Label
var _enemy_score_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Comic.anchor(self, Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_END
	offset_top = Comic.SAFE_MARGIN
	visible = false

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_1 / 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)

	# Ligne RÉELLE de l'ancre haut-centre (§5) : score allié 66 · minuteur 37 ·
	# score ennemi 66, zéro fond -- voir la doc de classe pour `_score_label`.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", Comic.SP_3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)

	_ally_score_label = Comic.ink_label("", Comic.SIZE_66, Comic.ALLY, Comic.number_font_v4())
	row.add_child(_ally_score_label)
	_timer_label = Comic.ink_label("", Comic.SIZE_37, Comic.paper_color(), Comic.number_font_v4())
	row.add_child(_timer_label)
	_enemy_score_label = Comic.ink_label("", Comic.SIZE_66, Comic.enemy_color(), Comic.number_font_v4())
	row.add_child(_enemy_score_label)

	_objective_label = Comic.ink_label("", Comic.SIZE_21, Comic.paper_dim_color(), Comic.meta_font_v4(Comic.SIZE_21))
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_objective_label)

	# `_score_label` : jamais ajouté à l'arbre -- pur porteur de texte pour
	# tests/ui/test_team_relative.gd (voir la doc de classe).
	_score_label = Label.new()

## `timer_text` : minuteur déjà formaté (mm:ss) par l'appelant, "" si aucun
## (ex. juste après la victoire). `local_team` : équipe du joueur local
## (`PlayerController.team`) — décide quel score va à gauche (allié) et à
## droite (ennemi), voir `Comic.is_ally`. Rien ne s'affiche si `mode` est
## absent (entraînement) — voir `GameHUD._process`, qui n'appelle `update` que
## si un nœud "game_mode" existe.
func update(team0: int, team1: int, winner: int, hud_state: String, overtime: bool, timer_text: String, local_team: int) -> void:
	visible = true
	var my_index := local_team if local_team in [0, 1] else 0
	var other_index := 1 - my_index
	var scores := [team0, team1]
	var my_score: int = scores[my_index]
	var other_score: int = scores[other_index]
	_ally_score_label.text = "%s %d" % [Comic.team_glyph(true), my_score]
	_enemy_score_label.text = "%d %s" % [other_score, Comic.team_glyph(false)]
	if winner >= 0:
		var victory := Comic.is_ally(winner, local_team)
		_timer_label.text = "—"
		_score_label.text = "%s %d   —   %d %s" % [Comic.team_glyph(true), my_score, other_score, Comic.team_glyph(false)]
		_objective_label.text = "VICTOIRE" if victory else "DÉFAITE"
	else:
		_timer_label.text = timer_text if timer_text != "" else "—"
		var mid := ("   %s   " % timer_text) if timer_text != "" else "   —   "
		_score_label.text = "%s %d%s%d %s" % [Comic.team_glyph(true), my_score, mid, other_score, Comic.team_glyph(false)]
		_objective_label.text = "%s%s" % [hud_state, " · PROLONGATION" if overtime else ""]

func hide_panel() -> void:
	visible = false
