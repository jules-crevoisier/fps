## ScoreHUD.gd
## Bandeau score + chrono (contrat lead 2026-09-27, HUD en jeu, point 4) —
## haut-centre : plaque ALLIÉS bleue, plaque chrono papier (mm:ss + "PREMIER
## À <score_to_win>"), plaque ENNEMIS (`UiTokens.enemy_color()`). Les scores
## sont mappés sur l'équipe du joueur LOCAL (`map_scores`, fonction PURE) —
## JAMAIS l'index brut 0/1 (un joueur en équipe 1 doit voir SES scores comme
## "alliés", même convention que `Comic.is_ally`). Le chrono affiche le temps
## RESTANT (`match_time_limit - match_elapsed`, compte à rebours) et passe au ROUGE
## dans les 30 dernières secondes RESTANTES avant `match_time_limit`.
class_name ScoreHUD
extends Control

const _FINAL_COUNTDOWN_S := 30.0

var _ally_plate: PanelContainer
var _enemy_plate: PanelContainer
var _ally_score_label: Label
var _enemy_score_label: Label
var _clock_label: Label
var _goal_label: Label


## "mm:ss", jamais négatif (contrat : une horloge ne remonte pas sous zéro).
static func format_clock(seconds: float) -> String:
	var s: int = int(round(maxf(seconds, 0.0)))
	return "%02d:%02d" % [s / 60, s % 60]


## Contrat : "the clock text turns RED in the last 30 seconds" — `seconds` =
## temps RESTANT (jamais l'écoulé), fonction PURE.
static func is_final_countdown(seconds_remaining: float) -> bool:
	return seconds_remaining <= _FINAL_COUNTDOWN_S


## Mappe `team_scores` (index brut 0/1, GameMode.team_scores) sur les rôles
## "ally"/"enemy" RELATIFS au joueur local — `local_team` inconnu (< 0,
## spectateur) retombe sur la convention par défaut équipe 0 = alliés, même
## repli que `Comic.is_ally` (jamais une supposition différente ici).
static func map_scores(team_scores: Array, local_team: int) -> Dictionary:
	if local_team == 1:
		return {"ally": int(team_scores[1]), "enemy": int(team_scores[0])}
	return {"ally": int(team_scores[0]), "enemy": int(team_scores[1])}


func _ready() -> void:
	Comic.anchor(self, Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	# CenterContainer (un vrai Container) centre `row` sur SA taille minimale
	# réelle (armes/scores à largeur variable) plutôt qu'un calcul de largeur
	# à la main — toujours juste, même quand un score passe de 1 à 2 chiffres.
	var wrap := CenterContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	wrap.offset_top = UiTokens.EDGE_MARGIN * 0.7
	wrap.offset_bottom = wrap.offset_top + 170.0
	add_child(wrap)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	wrap.add_child(row)

	_ally_plate = PanelContainer.new()
	_ally_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ally_plate.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.BLUE, UiTokens.SKEW_DEG, Vector2(6, 6), UiTokens.STROKE, Vector2(UiTokens.S4, UiTokens.S1)))
	var ally_col := VBoxContainer.new()
	ally_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ally_score_label = UiTokens.make_label("0", UiTokens.display(UiTokens.T_2XL, UiTokens.PAPER))
	_ally_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ally_col.add_child(_ally_score_label)
	var ally_who := UiTokens.make_label("Alliés", UiTokens.label(UiTokens.T_XS, UiTokens.PAPER, 0, true), true)
	ally_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ally_col.add_child(ally_who)
	_ally_plate.add_child(ally_col)
	row.add_child(_ally_plate)

	var clock_plate := PanelContainer.new()
	clock_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_plate.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.PAPER, UiTokens.SKEW_DEG, Vector2(0, 6), UiTokens.STROKE, Vector2(UiTokens.S4, UiTokens.S1)))
	var clock_col := VBoxContainer.new()
	clock_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_label = UiTokens.make_label("00:00", UiTokens.display(UiTokens.T_XL, UiTokens.INK, 0))
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_col.add_child(_clock_label)
	_goal_label = UiTokens.make_label("", UiTokens.label(UiTokens.T_XS, UiTokens.INK_SOFT, 0, true), true)
	_goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_col.add_child(_goal_label)
	clock_plate.add_child(clock_col)
	row.add_child(clock_plate)

	_enemy_plate = PanelContainer.new()
	_enemy_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_plate.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.enemy_color(), UiTokens.SKEW_DEG, Vector2(6, 6), UiTokens.STROKE, Vector2(UiTokens.S4, UiTokens.S1)))
	var enemy_col := VBoxContainer.new()
	enemy_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_score_label = UiTokens.make_label("0", UiTokens.display(UiTokens.T_2XL, UiTokens.PAPER))
	_enemy_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_col.add_child(_enemy_score_label)
	var enemy_who := UiTokens.make_label("Ennemis", UiTokens.label(UiTokens.T_XS, UiTokens.PAPER, 0, true), true)
	enemy_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_col.add_child(enemy_who)
	_enemy_plate.add_child(enemy_col)
	row.add_child(_enemy_plate)


## GameHUD.gd -> GameMode.updated (team_scores/hud_state ont changé).
func update_scores(team_scores: Array, local_team: int, score_to_win: int) -> void:
	var m := map_scores(team_scores, local_team)
	_ally_score_label.text = str(m["ally"])
	_enemy_score_label.text = str(m["enemy"])
	_goal_label.text = "PREMIER À %d" % score_to_win


## GameHUD.gd -> GameMode.match_elapsed (polling, comme InventoryHUD).
func update_clock(elapsed: float, limit: float) -> void:
	var remaining := maxf(limit - elapsed, 0.0)
	# temps RESTANT (maquette : « 04:32 » à côté de « premier à 50 ») ; écoulé sans limite
	_clock_label.text = format_clock(remaining if limit > 0.0 else elapsed)
	var final := limit > 0.0 and is_final_countdown(remaining)
	_clock_label.label_settings = UiTokens.display(UiTokens.T_XL, UiTokens.RED if final else UiTokens.INK, 0)
