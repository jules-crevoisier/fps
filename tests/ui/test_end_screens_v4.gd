## test_end_screens_v4.gd
## Spec UX-34 « UI v4 BL3 — écrans de mort, de fin (REJOUER) et tableau des
## scores » (docs/UI_DIRECTION_BL3.md §6, direction VALIDÉE par l'utilisateur
## le 2026-09-25) : contrat de CETTE tâche pour `DeathPanel.gd`/`EndPanel.gd`/
## `ScoreboardPanel.gd` — monde désaturé 60 % + « REMBALLÉ » 157 `vital` à
## −6° + carte du tueur + barre « Retour dans N s » (Mort) ; VICTOIRE/DÉFAITE
## 157 + score 118 + MVP + CTA REJOUER jaune (Fin) ; lignes 54 px zébrées
## `plate`/`plate_hi` avec ta ligne en plein `signal` (Tableau). N'ASSERTE
## JAMAIS le contrat déjà verrouillé par tests/ui/test_team_relative.gd
## (`_header.title`, texte/couleur de `_score_label`, format des en-têtes
## "<glyphe> ÉQUIPE <n>" dans `_list`) — celui-ci reste hors périmètre
## d'écriture de cette tâche, seule la TAILLE/POLICE ajoutée en v4 y est
## vérifiée ici, jamais son texte/sa couleur déjà couverts ailleurs.
extends GdUnitTestSuite

const DEATH_PANEL_SCRIPT := preload("res://scripts/ui/hud/DeathPanel.gd")
const END_PANEL_SCRIPT := preload("res://scripts/ui/hud/EndPanel.gd")
const SCOREBOARD_SCRIPT := preload("res://scripts/ui/hud/ScoreboardPanel.gd")


## Substitut de GameWorld (Scoreboard/EndPanel ne lisent que `player_info`,
## jamais GameWorld.gd lui-même, hors de la liste de fichiers de cette
## tâche) -- même patron que `FakeMatch` de tests/ui/test_team_relative.gd,
## dupliqué ici (portée locale à CE script, aucune collision).
class _FakeMatch extends Node:
	var player_info: Dictionary = {}


## Pair multijoueur par défaut sauvegardé/restauré à CHAQUE test (même
## précaution que tests/ui/test_team_relative.gd) : `ScoreboardPanel.
## _player_row` lit `multiplayer.get_unique_id()` pour savoir quelle ligne
## est « ta ligne » -- une suite voisine peut avoir laissé
## `multiplayer.multiplayer_peer` à `null`.
var _saved_multiplayer_peer: MultiplayerPeer

func before_test() -> void:
	_saved_multiplayer_peer = multiplayer.multiplayer_peer
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func after_test() -> void:
	multiplayer.multiplayer_peer = _saved_multiplayer_peer


func _death_panel() -> DeathPanel:
	var p: DeathPanel = DEATH_PANEL_SCRIPT.new()
	add_child(p)
	auto_free(p)
	return p

func _end_panel() -> EndPanel:
	var ep: EndPanel = END_PANEL_SCRIPT.new()
	add_child(ep)
	auto_free(ep)
	return ep

func _scoreboard() -> ScoreboardPanel:
	var sb: ScoreboardPanel = SCOREBOARD_SCRIPT.new()
	add_child(sb)
	auto_free(sb)
	return sb

func _fake_match() -> _FakeMatch:
	var m := _FakeMatch.new()
	add_child(m)
	auto_free(m)
	return m


# ======================================================================
#  1. DeathPanel -- titre « REMBALLÉ » (§6, §4.1, §4.3)
# ======================================================================

func test_death_panel_title_is_remballe_157_vital_with_display_stroke_hero_shadow_and_tilt() -> void:
	var panel := _death_panel()

	assert_str(panel._title_label.text).is_equal("REMBALLÉ")
	assert_int(panel._title_label.get_theme_font_size("font_size")).append_failure_message(
		"§6/§4.1 : REMBALLÉ doit être en 157 px"
	).is_equal(Comic.SIZE_157)
	assert_that(panel._title_label.get_theme_color("font_color")).append_failure_message(
		"§6 : REMBALLÉ doit être `vital` (#E8392E), jamais le rouge pinceau v3"
	).is_equal(Comic.vital_color())
	assert_int(panel._title_label.get_theme_constant("outline_size")).append_failure_message(
		"§4.1 : titres >= 88 px -> contour 5 px (STROKE_DISPLAY)"
	).is_equal(Comic.STROKE_DISPLAY)
	assert_that(panel._title_label.get_theme_color("font_outline_color")).is_equal(Comic.ink_color())
	assert_int(panel._title_label.get_theme_constant("shadow_offset_x")).append_failure_message(
		"§4.3 : ombre dure (8, 8) sur les moments héros"
	).is_equal(8)
	assert_int(panel._title_label.get_theme_constant("shadow_offset_y")).is_equal(8)
	assert_float(panel._title_label.rotation_degrees).append_failure_message(
		"§6/§2 : titre de boss incliné à -6°"
	).is_equal_approx(-6.0, 0.001)


# ======================================================================
#  2. DeathPanel -- désaturation du monde à 60 % (§6)
# ======================================================================

func test_death_panel_desaturates_the_world_behind_it_by_60_percent() -> void:
	var panel := _death_panel()

	var mat := panel._world_dim.material as ShaderMaterial
	assert_object(mat).append_failure_message(
		"le voile de désaturation doit porter un ShaderMaterial"
	).is_not_null()
	var saturation: float = mat.get_shader_parameter("saturation")
	assert_float(saturation).append_failure_message(
		"§6 « monde désaturé à 60 % » -> saturation restante = 1 - 0,6 = 0,4"
	).is_equal_approx(1.0 - DeathPanel.WORLD_DESATURATION, 0.001)


# ======================================================================
#  3. DeathPanel -- carte du tueur / état vide (§6)
# ======================================================================

func test_death_panel_shows_killer_card_with_name_weapon_and_remaining_hp() -> void:
	var panel := _death_panel()

	panel.show_death("BOT Renard", "Ravage", 34.0)

	assert_bool(panel._killer_card.visible).is_true()
	assert_bool(panel._empty_label.visible).is_false()
	assert_str(panel._killer_name_label.text).append_failure_message(
		"§6 : le nom du tueur doit porter le glyphe ▼ (toujours Ennemi côté victime)"
	).is_equal("▼ BOT RENARD")
	assert_bool(panel._weapon_label.visible).is_true()
	assert_str(panel._weapon_label.text).is_equal("RAVAGE")
	assert_bool(panel._remaining_hp_label.visible).append_failure_message(
		"§6 « Il lui restait 34 PV » -- doit s'afficher quand l'appelant connaît les PV restants"
	).is_true()
	assert_str(panel._remaining_hp_label.text).is_equal("Il lui restait 34 PV")


func test_death_panel_omits_remaining_hp_line_when_unknown() -> void:
	var panel := _death_panel()

	panel.show_death("BOT Renard", "Ravage")  # PV restants non fournis (GameHUD.gd actuel).

	assert_bool(panel._remaining_hp_label.visible).append_failure_message(
		"jamais un chiffre de PV inventé -- la ligne reste absente si l'appelant ne le sait pas"
	).is_false()


func test_death_panel_shows_the_empty_state_when_the_killer_is_unknown() -> void:
	var panel := _death_panel()

	panel.show_death()

	assert_bool(panel._killer_card.visible).is_false()
	assert_bool(panel._empty_label.visible).is_true()
	assert_str(panel._empty_label.text).is_equal("Réapparition imminente…")


# ======================================================================
#  4. DeathPanel -- barre « Retour dans N s » (§6, §4.5)
# ======================================================================

func test_death_panel_respawn_bar_starts_at_the_configured_delay() -> void:
	var panel := _death_panel()

	panel.show_death("BOT Renard", "Ravage")

	assert_str(panel._respawn_label.text).append_failure_message(
		"§6 « barre « Retour dans 3 s » » -- délai par défaut 3.0 s (mirroir de GameWorld.respawn_delay)"
	).is_equal("Retour dans 3 s")


func test_death_panel_respawn_bar_counts_down_to_zero_and_stops() -> void:
	var panel := _death_panel()
	panel.respawn_delay_s = 0.05  # raccourci en test, même convention que world.rematch_countdown_s.

	panel.show_death("BOT Renard", "Ravage")
	await await_millis(250)

	assert_str(panel._respawn_label.text).is_equal("Retour dans 0 s")
	assert_bool(panel.is_processing()).append_failure_message(
		"le compte à rebours cosmétique doit s'arrêter une fois à 0, jamais tourner à vide"
	).is_false()


func test_death_panel_hide_death_stops_the_countdown_and_hides_the_panel() -> void:
	var panel := _death_panel()
	panel.respawn_delay_s = 5.0

	panel.show_death("BOT Renard", "Ravage")
	panel.hide_death()

	assert_bool(panel.visible).is_false()
	assert_bool(panel.is_processing()).append_failure_message(
		"hide_death() doit arrêter le traitement du compte à rebours, jamais le laisser tourner en fond"
	).is_false()


# ======================================================================
#  5. EndPanel -- VICTOIRE/DÉFAITE 157 (§6)
# ======================================================================

func test_end_panel_victory_title_is_157_signal_on_ink_band() -> void:
	var ep := _end_panel()
	var match_node := _fake_match()

	ep.show_result(1, 5, 3, match_node, 1)  # équipe 1 (locale) gagne.

	assert_int(ep._result_label.get_theme_font_size("font_size")).append_failure_message(
		"§6 : VICTOIRE/DÉFAITE doit être en 157 px"
	).is_equal(Comic.SIZE_157)
	assert_that(ep._result_label.get_theme_color("font_color")).append_failure_message(
		"§6 « VICTOIRE signal sur encre »"
	).is_equal(Comic.signal_color())
	assert_that(ep._result_band.color).is_equal(Comic.ink_color())


func test_end_panel_defeat_title_is_157_paper_on_vital_band() -> void:
	var ep := _end_panel()
	var match_node := _fake_match()

	ep.show_result(0, 5, 3, match_node, 1)  # équipe 0 gagne, le local est en équipe 1.

	assert_that(ep._result_label.get_theme_color("font_color")).append_failure_message(
		"§6 « DÉFAITE paper sur vital »"
	).is_equal(Comic.paper_color())
	assert_that(ep._result_band.color).is_equal(Comic.vital_color())


# ======================================================================
#  6. EndPanel -- score 118 (§6)
# ======================================================================

func test_end_panel_score_label_is_118px() -> void:
	var ep := _end_panel()
	var match_node := _fake_match()

	ep.show_result(1, 5, 3, match_node, 1)

	assert_int(ep._score_label.get_theme_font_size("font_size")).append_failure_message(
		"§6 « score 118 »"
	).is_equal(Comic.SIZE_118)


# ======================================================================
#  7. EndPanel -- carte MVP (§6)
# ======================================================================

func test_end_panel_shows_the_mvp_card_when_players_are_present() -> void:
	var ep := _end_panel()
	var match_node := _fake_match()
	match_node.player_info = {
		1: {"name": "Verrou", "team": 1, "kills": 5, "deaths": 1, "is_bot": false},
		9001: {"name": "BOT Renard", "team": 0, "kills": 1, "deaths": 3, "is_bot": true},
	}

	ep.show_result(1, 5, 3, match_node, 1)

	assert_int(ep._mvp_slot.get_child_count()).append_failure_message(
		"§6 : la carte MVP doit être posée dans _mvp_slot quand des joueurs sont présents"
	).is_greater(0)


func test_end_panel_omits_the_mvp_card_when_no_players_are_present() -> void:
	var ep := _end_panel()
	var match_node := _fake_match()  # player_info vide.

	ep.show_result(1, 5, 3, match_node, 1)

	assert_int(ep._mvp_slot.get_child_count()).append_failure_message(
		"état VIDE honnête : pas de carte MVP inventée quand personne n'est connu"
	).is_equal(0)


# ======================================================================
#  8. EndPanel -- CTA « REJOUER » jaune incliné (§6, §4.3)
# ======================================================================

func test_end_panel_replay_cta_is_a_yellow_slanted_button() -> void:
	var ep := _end_panel()

	assert_str(ep._replay_button.text).is_equal("REJOUER")
	var style := ep._replay_button.get_theme_stylebox("normal") as StyleBoxFlat
	assert_object(style).is_not_null()
	assert_that(style.bg_color).append_failure_message(
		"§6 « CTA REJOUER jaune » -- fond `signal` (#FFCE1F), seule couleur qui désigne"
	).is_equal(Comic.signal_color())
	assert_float(style.skew.x).append_failure_message(
		"§4.3 « boutons... inclinés » -- même cisaillement 12° que les autres formes"
	).is_equal_approx(tan(deg_to_rad(Comic.SLANT_DEG)), 0.001)


# ======================================================================
#  9. ScoreboardPanel -- lignes 54 px zébrées, ta ligne en plein signal (§6)
# ======================================================================

func test_scoreboard_rows_are_54px_tall_and_zebra_striped_with_local_row_in_full_signal() -> void:
	var sb := _scoreboard()
	var match_node := _fake_match()
	# Id 1 == joueur local (multiplayer.get_unique_id(), voir before_test) --
	# kills les plus bas, donc trié en DERNIER (index 2) : vérifie que le
	# plein `signal` de la ligne locale l'emporte sur le zébrage attendu à cet
	# index (qui serait `plate`, index pair).
	match_node.player_info = {
		1: {"name": "Joueur 1", "team": 0, "kills": 1, "deaths": 4, "is_bot": false},
		5: {"name": "BOT Renard", "team": 0, "kills": 5, "deaths": 0, "is_bot": true},
		7: {"name": "BOT Iris", "team": 0, "kills": 3, "deaths": 2, "is_bot": true},
	}

	sb.refresh(match_node, 0)

	var rows: Array = []
	for c in sb._list.get_children():
		var l := c as Label
		if not (l.text.begins_with("●") or l.text.begins_with("▼")):
			rows.append(l)
	assert_int(rows.size()).append_failure_message(
		"préalable du test : 3 lignes joueur attendues pour l'équipe 0"
	).is_equal(3)

	for r in rows:
		assert_float((r as Label).custom_minimum_size.y).append_failure_message(
			"§6 « lignes de 54 px »"
		).is_equal_approx(ScoreboardPanel.ROW_HEIGHT_PX, 0.01)

	var style0 := (rows[0] as Label).get_theme_stylebox("normal") as StyleBoxFlat
	var style1 := (rows[1] as Label).get_theme_stylebox("normal") as StyleBoxFlat
	var style_local := (rows[2] as Label).get_theme_stylebox("normal") as StyleBoxFlat
	assert_that(style0.bg_color).append_failure_message(
		"§6 « zébrées plate/plate_hi » -- première ligne (index pair) sur `plate`"
	).is_equal(Comic.plate_color())
	assert_that(style1.bg_color).append_failure_message(
		"deuxième ligne (index impair) sur `plate_hi`"
	).is_equal(Comic.plate_hi_color())
	assert_that(style_local.bg_color).append_failure_message(
		"§6 « ta ligne pleine signal » -- l'emporte sur le zébrage même à un index pair"
	).is_equal(Comic.signal_color())
	assert_that((rows[2] as Label).get_theme_color("font_color")).append_failure_message(
		"§6 « ta ligne ... texte encre »"
	).is_equal(Comic.ink_color())


# ======================================================================
#  10. EndPanel -- REVUE LEAD point 1 : VICTOIRE/DÉFAITE jamais rognée
# ======================================================================

func test_end_panel_result_stage_is_not_clipped_and_tall_enough_for_the_display_title() -> void:
	var ep := _end_panel()

	assert_bool(ep._result_stage.clip_contents).append_failure_message(
		"REVUE LEAD point 1 (capture 02) : la scène du titre ne doit plus rogner VICTOIRE/DÉFAITE"
	).is_false()
	assert_float(ep._result_stage.custom_minimum_size.y).append_failure_message(
		"REVUE LEAD point 1 : la scène doit rester plus haute qu'un glyphe 157 px + contour 5 + ombre (8, 8), sinon le panneau de score suivant le recouvre"
	).is_greater_equal(200.0)


# ======================================================================
#  11. EndPanel -- REVUE LEAD point 2 : score 118 coloré par équipe, pas par victoire
# ======================================================================

func test_end_panel_score_digits_are_colored_by_team_not_by_victory() -> void:
	var ep := _end_panel()
	var match_node := _fake_match()

	ep.show_result(0, 5, 3, match_node, 1)  # équipe 0 gagne -- le local (équipe 1) PERD.

	assert_str(ep._score_ally_label.text).is_equal("3")
	assert_that(ep._score_ally_label.get_theme_color("font_color")).append_failure_message(
		"REVUE LEAD point 2 : le chiffre ALLIÉ reste `ally` même en défaite -- jamais l'accent de victoire"
	).is_equal(Comic.ALLY)
	assert_str(ep._score_enemy_label.text).is_equal("5")
	assert_that(ep._score_enemy_label.get_theme_color("font_color")).append_failure_message(
		"REVUE LEAD point 2 : le chiffre ENNEMI reste `enemy_color()` même si son équipe gagne"
	).is_equal(Comic.enemy_color())
	var dash := ep._score_row.get_child(1) as Label
	assert_that(dash.get_theme_color("font_color")).append_failure_message(
		"REVUE LEAD point 2 : le tiret reste `paper`, ni allié ni ennemi"
	).is_equal(Comic.paper_color())


# ======================================================================
#  12. EndPanel -- REVUE LEAD point 3 : roster entier, sans défilement
# ======================================================================

func test_end_panel_roster_shows_all_eight_players_without_a_scroll_container() -> void:
	var ep := _end_panel()
	var match_node := _fake_match()
	var info := {}
	for i in range(4):
		info[i + 1] = {"name": "Joueur %d" % (i + 1), "team": 1, "kills": i, "deaths": i, "is_bot": false}
		info[9100 + i] = {"name": "BOT %d" % i, "team": 0, "kills": i, "deaths": i, "is_bot": true}
	match_node.player_info = info

	ep.show_result(1, 4, 6, match_node, 1)

	assert_int(ep._list.get_child_count()).append_failure_message(
		"REVUE LEAD point 6 : les 8 joueurs d'un 4v4 complet (+ 2 en-têtes d'équipe) doivent tous apparaître"
	).is_equal(10)
	assert_bool(ep._list.get_parent() is ScrollContainer).append_failure_message(
		"REVUE LEAD point 3 : plus de ScrollContainer autour de _list -- jamais de barre de défilement ni de rognage"
	).is_false()


# ======================================================================
#  13. ScoreboardPanel -- REVUE LEAD point 4 : bandeau pinceau rouge supprimé
# ======================================================================

func test_scoreboard_has_no_brush_header() -> void:
	var sb := _scoreboard()

	var brush_headers := sb.find_children("*", "BrushHeader", true, false)
	assert_int(brush_headers.size()).append_failure_message(
		"REVUE LEAD point 4 : le bandeau pinceau rouge (BrushHeader, banni par la direction) doit disparaître du tableau des scores"
	).is_equal(0)


func test_scoreboard_columns_header_shows_available_stats_only() -> void:
	var sb := _scoreboard()
	var match_node := _fake_match()
	match_node.player_info = {
		1: {"name": "Joueur 1", "team": 0, "kills": 1, "deaths": 0, "is_bot": false},
	}

	sb.refresh(match_node, 0)

	assert_str(sb._columns_header.text).append_failure_message(
		"REVUE LEAD point 4 : CAMP/NOM/É/M seulement -- pas de colonne A/SCORE/PING inventée sans donnée"
	).is_equal("CAMP   NOM   É   M")

	match_node.player_info = {
		1: {"name": "Joueur 1", "team": 0, "kills": 1, "deaths": 0, "assists": 2, "is_bot": false},
	}
	sb.refresh(match_node, 0)

	assert_str(sb._columns_header.text).append_failure_message(
		"la colonne A doit apparaître dès qu'un joueur porte réellement la clé `assists`"
	).is_equal("CAMP   NOM   É   M   A")


func test_scoreboard_row_text_never_repeats_toi() -> void:
	var sb := _scoreboard()
	var match_node := _fake_match()
	match_node.player_info = {
		1: {"name": "Joueur 1", "team": 0, "kills": 1, "deaths": 0, "is_bot": false},
	}

	sb.refresh(match_node, 0)  # id 1 == joueur local (multiplayer.get_unique_id(), voir before_test).

	for c in sb._list.get_children():
		var l := c as Label
		if not (l.text.begins_with("●") or l.text.begins_with("▼")):
			assert_str(l.text).append_failure_message(
				"REVUE LEAD point 4 : « (toi) » supprimé -- la ligne pleine `signal` le signale déjà"
			).not_contains("(toi)")


func test_scoreboard_score_row_hidden_without_a_real_game_mode_node() -> void:
	var sb := _scoreboard()
	var match_node := _fake_match()

	sb.refresh(match_node, 0)

	assert_bool(sb._score_row.visible).append_failure_message(
		"REVUE LEAD point 4 : pas de « 0 — 0 » inventé sans mode de jeu réel -- état VIDE honnête"
	).is_false()


func test_scoreboard_meta_header_names_the_real_mode_and_map() -> void:
	var saved_mode := MatchConfig.mode_id
	var saved_map := MatchConfig.map_id
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "wasteland"

	var sb := _scoreboard()
	var match_node := _fake_match()
	sb.refresh(match_node, 0)

	assert_str(sb._meta_header.text).append_failure_message(
		"REVUE LEAD point 4 : l'en-tête doit nommer le VRAI mode (MatchConfig.mode_id), jamais un texte inventé"
	).contains("TDM")
	assert_str(sb._meta_header.text).append_failure_message(
		"REVUE LEAD point 4 : l'en-tête doit nommer la VRAIE carte (MatchConfig.map_id -> MapCatalog)"
	).contains("WASTELAND")

	MatchConfig.mode_id = saved_mode
	MatchConfig.map_id = saved_map
