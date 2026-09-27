## test_score_hud.gd
## Spec (contrat lead 2026-09-27, HUD en jeu, point 4 "ScoreHUD") : plaque
## ALLIÉS bleue + score, plaque chrono papier (mm:ss + "PREMIER À N"), plaque
## ENNEMIS (enemy_color()) + score — scores mappés sur l'équipe du joueur
## LOCAL (jamais l'équipe brute 0/1), chrono ROUGE dans les 30 dernières
## secondes.
extends GdUnitTestSuite

const ScoreHUD := preload("res://scripts/ui/hud/ScoreHUD.gd")


func _hud() -> ScoreHUD:
	var hud: ScoreHUD = auto_free(ScoreHUD.new())
	add_child(hud)
	return hud


# ---- format_clock (pure) ----

func test_format_clock_matches_mockup() -> void:
	assert_str(ScoreHUD.format_clock(272.0)).is_equal("04:32")


func test_format_clock_pads_seconds() -> void:
	assert_str(ScoreHUD.format_clock(65.0)).is_equal("01:05")


func test_format_clock_zero() -> void:
	assert_str(ScoreHUD.format_clock(0.0)).is_equal("00:00")


func test_format_clock_never_negative() -> void:
	assert_str(ScoreHUD.format_clock(-5.0)).is_equal("00:00")


# ---- is_final_countdown (pure) ----

func test_is_final_countdown_last_30_seconds() -> void:
	assert_bool(ScoreHUD.is_final_countdown(30.0)).is_true()
	assert_bool(ScoreHUD.is_final_countdown(31.0)).is_false()
	assert_bool(ScoreHUD.is_final_countdown(0.0)).is_true()


# ---- map_scores (pure) : mappé sur l'équipe LOCALE, jamais 0/1 brut ----

func test_map_scores_local_team_0_is_ally() -> void:
	var m := ScoreHUD.map_scores([12, 9], 0)
	assert_int(m["ally"]).is_equal(12)
	assert_int(m["enemy"]).is_equal(9)


func test_map_scores_local_team_1_swaps_ally_and_enemy() -> void:
	var m := ScoreHUD.map_scores([12, 9], 1)
	assert_int(m["ally"]).is_equal(9)
	assert_int(m["enemy"]).is_equal(12)


func test_map_scores_unknown_local_team_defaults_to_team_0() -> void:
	var m := ScoreHUD.map_scores([12, 9], -1)
	assert_int(m["ally"]).is_equal(12)
	assert_int(m["enemy"]).is_equal(9)


# ---- nœuds ----

func test_update_sets_scores_and_goal_text() -> void:
	var hud := _hud()
	hud.update_scores([12, 9], 0, 50)
	assert_str(hud._ally_score_label.text).is_equal("12")
	assert_str(hud._enemy_score_label.text).is_equal("9")
	assert_str(hud._goal_label.text).is_equal("PREMIER À 50")


## Le chrono affiche le temps RESTANT (maquette lead : « 04:32 » à côté de « premier à 50 »).
func test_update_clock_shows_remaining_time() -> void:
	var hud := _hud()
	hud.update_clock(328.0, 600.0)
	assert_str(hud._clock_label.text).is_equal("04:32")


## Sans limite de temps, il n'y a rien à décompter : le chrono montre le temps écoulé.
func test_update_clock_without_limit_shows_elapsed_time() -> void:
	var hud := _hud()
	hud.update_clock(75.0, 0.0)
	assert_str(hud._clock_label.text).is_equal("01:15")


func test_update_clock_turns_red_in_final_countdown() -> void:
	var hud := _hud()
	hud.update_clock(590.0, 600.0)
	assert_bool(hud._clock_label.label_settings.font_color.is_equal_approx(UiTokens.RED)).is_true()


func test_update_clock_stays_ink_outside_final_countdown() -> void:
	var hud := _hud()
	hud.update_clock(100.0, 600.0)
	assert_bool(hud._clock_label.label_settings.font_color.is_equal_approx(UiTokens.INK)).is_true()
