## ScoreboardHUD.gd
## Tableau des scores (contrat lead 2026-09-27, "TAB SCOREBOARD") : affiché
## plein écran tant que l'action "scoreboard" (Tab) est MAINTENUE (voir
## GameHUD.gd, `_update_scoreboard`), masqué au relâchement. Voile d'encre
## (~62 % alpha) + trame de points, deux colonnes d'équipe RELATIVES au joueur
## LOCAL (jamais l'index brut 0/1, même convention que ScoreHUD.map_scores/
## Comic.is_ally) : ALLIÉS (plaque bleue) à gauche, ENNEMIS (plaque
## `enemy_color()`) à droite. Rangées = plaques papier triées par élims
## DESC puis morts ASC ; la rangée du joueur LOCAL est jaune. Seules les
## colonnes RÉELLEMENT présentes dans `GameWorld.player_info` (name/team/
## kills/deaths/is_bot) sont affichées -- aucune Aide/Dégâts/Ping inventés
## (absents de player_info, voir sa doc d'en-tête).
class_name ScoreboardHUD
extends Control

const _SIDE_MARGIN := 110.0
const _TEAMS_TOP := 190.0
const _ROW_HEIGHT := 68.0
const _ROW_GAP := 10.0
const _PORTRAIT_W := 64.0
const _STAT_COL_W := 140.0
const _DOTS_ALPHA := 0.12

## Traduction FR des noms de mode connus (prototype : TDM seul, voir
## MatchConfig.MODES) -- un mode non répertorié retombe sur son nom
## simplement mis en capitales, jamais un texte inventé.
const _MODE_NAME_FR := {
	"Team Deathmatch": "MATCH À MORT PAR ÉQUIPE",
}

var _title_label: Label
var _subtitle_label: Label
var _ally_plate: PanelContainer
var _enemy_plate: PanelContainer
var _ally_score_label: Label
var _enemy_score_label: Label
var _ally_column: VBoxContainer
var _enemy_column: VBoxContainer


## Répartit `info` (GameWorld.player_info : id -> {name, team, kills, deaths,
## is_bot}) en {"allies": Array, "enemies": Array} RELATIF à `local_team`
## (Comic.is_ally, jamais l'index brut) -- chaque rangée = {"id", "name",
## "is_bot", "kills", "deaths"}, triée par élims DESC puis morts ASC puis id
## (stabilité). Fonction PURE (aucun nœud) : testable directement.
static func rows_from_player_info(info: Dictionary, local_team: int) -> Dictionary:
	var allies: Array = []
	var enemies: Array = []
	for id in info.keys():
		var p: Dictionary = info[id]
		var row := {
			"id": int(id),
			"name": String(p.get("name", "")),
			"is_bot": bool(p.get("is_bot", false)),
			"kills": int(p.get("kills", 0)),
			"deaths": int(p.get("deaths", 0)),
		}
		if Comic.is_ally(int(p.get("team", -1)), local_team):
			allies.append(row)
		else:
			enemies.append(row)
	allies.sort_custom(_row_less_than)
	enemies.sort_custom(_row_less_than)
	return {"allies": allies, "enemies": enemies}


static func _row_less_than(a: Dictionary, b: Dictionary) -> bool:
	if a["kills"] != b["kills"]:
		return a["kills"] > b["kills"]
	if a["deaths"] != b["deaths"]:
		return a["deaths"] < b["deaths"]
	return a["id"] < b["id"]


## Titre d'en-tête (display, capitales) -- traduit le nom de mode connu,
## replie sur `mode_name.to_upper()` sinon (jamais un texte inventé).
static func header_title(mode_name: String) -> String:
	return _MODE_NAME_FR.get(mode_name, mode_name.to_upper())


## Sous-titre "CARTE · mm:ss RESTANTES · PREMIER À N" -- même calcul de temps
## RESTANT que ScoreHUD.update_clock (jamais négatif, écoulé si pas de limite).
static func header_subtitle(map_id: String, match_elapsed: float, match_time_limit: float, score_to_win: int) -> String:
	var remaining := maxf(match_time_limit - match_elapsed, 0.0)
	var clock_text := ScoreHUD.format_clock(remaining if match_time_limit > 0.0 else match_elapsed)
	return "%s · %s RESTANTES · PREMIER À %d" % [map_id.to_upper(), clock_text, score_to_win]


func _ready() -> void:
	Comic.anchor(self, Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func _build() -> void:
	_build_veil()
	_build_header()
	_build_teams()


func _build_veil() -> void:
	var veil := ColorRect.new()
	Comic.anchor(veil, Control.PRESET_FULL_RECT)
	veil.color = Color(UiTokens.INK.r, UiTokens.INK.g, UiTokens.INK.b, 0.62)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var dots := TextureRect.new()
	Comic.anchor(dots, Control.PRESET_FULL_RECT)
	dots.texture = _dots_texture()
	dots.stretch_mode = TextureRect.STRETCH_TILE
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dots)


## Trame de points signature de la direction « Planche » -- tuile 16 px,
## point encre à faible opacité (repli local : ni Comic ni UiTokens n'exposent
## de fabrique de trame pour cette direction, voir le rapport de tâche).
static func _dots_texture() -> ImageTexture:
	var pitch := 16
	var img := Image.create(pitch, pitch, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(pitch, pitch) * 0.5
	var r := pitch * 0.16
	for y in pitch:
		for x in pitch:
			if Vector2(x, y).distance_to(center) <= r:
				img.set_pixel(x, y, Color(UiTokens.INK.r, UiTokens.INK.g, UiTokens.INK.b, _DOTS_ALPHA))
	return ImageTexture.create_from_image(img)


func _build_header() -> void:
	var wrap := CenterContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	wrap.offset_top = 46.0
	wrap.offset_bottom = 160.0
	add_child(wrap)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_label = UiTokens.make_label("", UiTokens.display(UiTokens.T_XL, UiTokens.PAPER))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title_label)
	_subtitle_label = UiTokens.make_label("", UiTokens.label(UiTokens.T_S, Color(UiTokens.PAPER.r, UiTokens.PAPER.g, UiTokens.PAPER.b, 0.85), 0, true))
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_subtitle_label)
	wrap.add_child(col)


func _build_teams() -> void:
	var teams := HBoxContainer.new()
	Comic.anchor(teams, Control.PRESET_FULL_RECT)
	teams.mouse_filter = Control.MOUSE_FILTER_IGNORE
	teams.offset_left = _SIDE_MARGIN
	teams.offset_right = -_SIDE_MARGIN
	teams.offset_top = _TEAMS_TOP
	teams.offset_bottom = -60.0
	teams.add_theme_constant_override("separation", 48)
	add_child(teams)

	var ally_built := _build_team_column(UiTokens.BLUE, "ALLIÉS")
	teams.add_child(ally_built["root"])
	_ally_plate = ally_built["plate"]
	_ally_score_label = ally_built["score_label"]
	_ally_column = ally_built["rows"]

	var enemy_built := _build_team_column(UiTokens.enemy_color(), "ENNEMIS")
	teams.add_child(enemy_built["root"])
	_enemy_plate = enemy_built["plate"]
	_enemy_score_label = enemy_built["score_label"]
	_enemy_column = enemy_built["rows"]


func _build_team_column(team_color: Color, label_text: String) -> Dictionary:
	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 14)

	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", UiTokens.plate(team_color, UiTokens.SKEW_DEG, UiTokens.DROP, UiTokens.STROKE, Vector2(UiTokens.S4, UiTokens.S2)))
	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := UiTokens.make_label(label_text, UiTokens.label(UiTokens.T_M, UiTokens.PAPER, 0, true), true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(name_label)
	var score_label := UiTokens.make_label("0", UiTokens.display(UiTokens.T_2XL, UiTokens.PAPER))
	top_row.add_child(score_label)
	plate.add_child(top_row)
	root.add_child(plate)

	var head_row := _build_header_row()
	root.add_child(head_row)

	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", int(_ROW_GAP))
	root.add_child(rows)

	return {"root": root, "plate": plate, "score_label": score_label, "rows": rows}


func _build_header_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(_PORTRAIT_W, 0)
	row.add_child(spacer)
	var name_head := UiTokens.make_label("Joueur", UiTokens.label(UiTokens.T_XS, Color(UiTokens.PAPER.r, UiTokens.PAPER.g, UiTokens.PAPER.b, 0.85), 0, true), true)
	name_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_head)
	for head_text in ["Élim.", "Morts"]:
		var head := UiTokens.make_label(head_text, UiTokens.label(UiTokens.T_XS, Color(UiTokens.PAPER.r, UiTokens.PAPER.g, UiTokens.PAPER.b, 0.85), 0, true), true)
		head.custom_minimum_size = Vector2(_STAT_COL_W, 0)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(head)
	return row


## Affiche/masque le tableau (Tab maintenu/relâché) -- GameHUD.gd.
func set_shown(shown: bool) -> void:
	visible = shown


## En-tête (mode, carte, chrono, objectif) -- GameHUD.gd, chaque frame tant
## que `visible` (le chrono avance en continu, même patron que ScoreHUD).
func update_header(mode_name: String, map_id: String, match_elapsed: float, match_time_limit: float, score_to_win: int) -> void:
	_title_label.text = header_title(mode_name)
	_subtitle_label.text = header_subtitle(map_id, match_elapsed, match_time_limit, score_to_win)


## Scores d'équipe (GameMode.team_scores) -- RELATIFS au joueur local, réutilise
## ScoreHUD.map_scores (même convention que ScoreHUD, jamais une seconde
## logique qui pourrait diverger).
func update_scores(team_scores: Array, local_team: int) -> void:
	var m := ScoreHUD.map_scores(team_scores, local_team)
	_ally_score_label.text = str(m["ally"])
	_enemy_score_label.text = str(m["enemy"])


## Rangées des deux colonnes -- GameHUD.gd sur GameWorld.stats_changed et à
## l'ouverture du tableau. Reconstruit les colonnes (nombre de joueurs
## variable) plutôt que de patcher en place : rare (kill/mort), jamais par
## frame.
func update_rows(player_info: Dictionary, local_team: int, local_id: int) -> void:
	var grouped := rows_from_player_info(player_info, local_team)
	_rebuild_column(_ally_column, grouped["allies"], local_id)
	_rebuild_column(_enemy_column, grouped["enemies"], local_id)


func _rebuild_column(column: VBoxContainer, rows: Array, local_id: int) -> void:
	for c in column.get_children():
		c.queue_free()
	for row in rows:
		column.add_child(_build_row(row, int(row["id"]) == local_id))


func _build_row(row: Dictionary, is_local: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(0, _ROW_HEIGHT)
	var fill := UiTokens.YELLOW if is_local else UiTokens.PAPER
	panel.add_theme_stylebox_override("panel", UiTokens.plate(fill, 0.0, UiTokens.DROP_SMALL, UiTokens.STROKE, Vector2(UiTokens.S2, UiTokens.S1)))

	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", UiTokens.S2)

	var portrait := TextureRect.new()
	portrait.texture = UiTokens.icon("portrait_verrou")
	portrait.custom_minimum_size = Vector2(_PORTRAIT_W, _ROW_HEIGHT - UiTokens.S2)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(portrait)

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_theme_constant_override("separation", UiTokens.S1)
	name_row.add_child(UiTokens.make_label(String(row["name"]), UiTokens.label(UiTokens.T_S, UiTokens.INK, 0, true), true))
	var bot_label := UiTokens.make_label("bot", UiTokens.body(UiTokens.T_XS, UiTokens.INK_SOFT))
	bot_label.visible = bool(row["is_bot"])
	name_row.add_child(bot_label)
	content.add_child(name_row)
	panel.set_meta("bot_label", bot_label)

	for value in [int(row["kills"]), int(row["deaths"])]:
		var value_label := UiTokens.make_label(str(value), UiTokens.display(UiTokens.T_M, UiTokens.INK, 0))
		value_label.custom_minimum_size = Vector2(_STAT_COL_W, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(value_label)

	panel.add_child(content)
	return panel
