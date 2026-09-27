## test_scoreboard_hud.gd
## Spec (contrat lead 2026-09-27, "TAB SCOREBOARD") : voile d'encre + trame de
## points pendant que l'action "scoreboard" (Tab) est MAINTENUE, deux colonnes
## d'équipe (ALLIÉS/ENNEMIS, RELATIVES au joueur local), rangées triées par
## élims desc puis morts asc, rangée locale JAUNE, tag "bot" pour les bots.
## Seules les colonnes RÉELLEMENT présentes dans GameWorld.player_info (Élim.,
## Morts) sont affichées -- aucune Aide/Dégâts/Ping inventés (absents de
## player_info, voir scripts/networking/GameWorld.gd).
extends GdUnitTestSuite

const ScoreboardHUD := preload("res://scripts/ui/hud/ScoreboardHUD.gd")


func _hud() -> ScoreboardHUD:
	var hud: ScoreboardHUD = auto_free(ScoreboardHUD.new())
	add_child(hud)
	return hud


# ---- rows_from_player_info (pure) ----

func _sample_info() -> Dictionary:
	return {
		1: {"name": "Joueur", "team": 0, "kills": 6, "deaths": 3, "is_bot": false},
		9001: {"name": "Têtard", "team": 0, "kills": 3, "deaths": 4, "is_bot": true},
		9002: {"name": "Grenouillette", "team": 0, "kills": 2, "deaths": 2, "is_bot": true},
		9003: {"name": "Crapaud", "team": 1, "kills": 4, "deaths": 4, "is_bot": true},
		9004: {"name": "Rainette", "team": 1, "kills": 4, "deaths": 3, "is_bot": true},
	}


func test_rows_split_by_team_relative_to_local_team() -> void:
	var grouped := ScoreboardHUD.rows_from_player_info(_sample_info(), 0)
	assert_int(grouped["allies"].size()).is_equal(3)
	assert_int(grouped["enemies"].size()).is_equal(2)


func test_rows_split_flips_when_local_team_is_1() -> void:
	var grouped := ScoreboardHUD.rows_from_player_info(_sample_info(), 1)
	assert_int(grouped["allies"].size()).is_equal(2)
	assert_int(grouped["enemies"].size()).is_equal(3)


func test_rows_sorted_by_kills_descending() -> void:
	var grouped := ScoreboardHUD.rows_from_player_info(_sample_info(), 0)
	var allies: Array = grouped["allies"]
	assert_str(allies[0]["name"]).is_equal("Joueur")
	assert_str(allies[1]["name"]).is_equal("Têtard")
	assert_str(allies[2]["name"]).is_equal("Grenouillette")


## Crapaud et Rainette ont tous deux 4 élims -- départage par morts ASCENDANT
## (Rainette 3 morts passe avant Crapaud 4 morts).
func test_rows_tie_broken_by_deaths_ascending() -> void:
	var grouped := ScoreboardHUD.rows_from_player_info(_sample_info(), 0)
	var enemies: Array = grouped["enemies"]
	assert_str(enemies[0]["name"]).is_equal("Rainette")
	assert_str(enemies[1]["name"]).is_equal("Crapaud")


func test_rows_carry_only_real_player_info_fields() -> void:
	var grouped := ScoreboardHUD.rows_from_player_info(_sample_info(), 0)
	var row: Dictionary = grouped["allies"][0]
	assert_bool(row.has("kills")).is_true()
	assert_bool(row.has("deaths")).is_true()
	assert_bool(row.has("assists")).append_failure_message(
		"aucune Aide inventée -- absente de GameWorld.player_info"
	).is_false()
	assert_bool(row.has("damage")).append_failure_message(
		"aucun Dégâts inventé -- absent de GameWorld.player_info"
	).is_false()
	assert_bool(row.has("ping")).append_failure_message(
		"aucun Ping inventé -- absent de GameWorld.player_info"
	).is_false()


func test_rows_carry_bot_flag() -> void:
	var grouped := ScoreboardHUD.rows_from_player_info(_sample_info(), 0)
	var row: Dictionary = grouped["allies"][1]
	assert_bool(row["is_bot"]).is_true()


# ---- header_title / header_subtitle (pure) ----

func test_header_title_translates_tdm_mode_name() -> void:
	assert_str(ScoreboardHUD.header_title("Team Deathmatch")).is_equal("MATCH À MORT PAR ÉQUIPE")


func test_header_title_falls_back_to_uppercase_for_unknown_mode() -> void:
	assert_str(ScoreboardHUD.header_title("Hardpoint")).is_equal("HARDPOINT")


func test_header_subtitle_matches_mockup() -> void:
	assert_str(ScoreboardHUD.header_subtitle("shipment", 328.0, 600.0, 50)).is_equal(
		"SHIPMENT · 04:32 RESTANTES · PREMIER À 50"
	)


func test_header_subtitle_without_time_limit_shows_elapsed() -> void:
	assert_str(ScoreboardHUD.header_subtitle("shipment", 75.0, 0.0, 50)).is_equal(
		"SHIPMENT · 01:15 RESTANTES · PREMIER À 50"
	)


# ---- nœuds ----

func test_hidden_by_default() -> void:
	var hud := _hud()
	assert_bool(hud.visible).is_false()


func test_set_shown_toggles_visibility() -> void:
	var hud := _hud()
	hud.set_shown(true)
	assert_bool(hud.visible).is_true()
	hud.set_shown(false)
	assert_bool(hud.visible).is_false()


func test_update_rows_builds_one_row_per_player_and_team() -> void:
	var hud := _hud()
	hud.update_rows(_sample_info(), 0, 1)
	assert_int(hud._ally_column.get_child_count()).is_equal(3)
	assert_int(hud._enemy_column.get_child_count()).is_equal(2)


func test_update_rows_highlights_local_row_in_yellow() -> void:
	var hud := _hud()
	hud.update_rows(_sample_info(), 0, 1)
	var local_row: PanelContainer = hud._ally_column.get_child(0)
	var sb: StyleBoxComic = local_row.get_theme_stylebox("panel")
	assert_bool(sb.fill.is_equal_approx(UiTokens.YELLOW)).append_failure_message(
		"la rangée du joueur LOCAL doit être en plaque jaune"
	).is_true()


func test_update_rows_does_not_highlight_other_rows() -> void:
	var hud := _hud()
	hud.update_rows(_sample_info(), 0, 1)
	var other_row: PanelContainer = hud._ally_column.get_child(1)
	var sb: StyleBoxComic = other_row.get_theme_stylebox("panel")
	assert_bool(sb.fill.is_equal_approx(UiTokens.YELLOW)).is_false()


func test_update_rows_shows_bot_tag_only_for_bots() -> void:
	var hud := _hud()
	hud.update_rows(_sample_info(), 0, 1)
	var human_row: PanelContainer = hud._ally_column.get_child(0)
	var bot_row: PanelContainer = hud._ally_column.get_child(1)
	assert_bool((human_row.get_meta("bot_label") as Label).visible).is_false()
	assert_bool((bot_row.get_meta("bot_label") as Label).visible).is_true()


func test_update_header_sets_title_and_subtitle() -> void:
	var hud := _hud()
	hud.update_header("Team Deathmatch", "shipment", 328.0, 600.0, 50)
	assert_str(hud._title_label.text).is_equal("MATCH À MORT PAR ÉQUIPE")
	assert_str(hud._subtitle_label.text).is_equal("SHIPMENT · 04:32 RESTANTES · PREMIER À 50")


func test_update_scores_maps_to_local_team() -> void:
	var hud := _hud()
	hud.update_scores([12, 9], 0)
	assert_str(hud._ally_score_label.text).is_equal("12")
	assert_str(hud._enemy_score_label.text).is_equal("9")
