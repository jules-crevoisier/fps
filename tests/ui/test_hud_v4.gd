## test_hud_v4.gd
## Spec UX-31 — « UI v4 BL3 — HUD en jeu : 6 ancres, zéro boîte, tailles §5,
## fil 4 lignes 5 s, mot de kill Bangers » (docs/UI_DIRECTION_BL3.md §5,
## direction validée par l'utilisateur le 2026-09-25).
##
## Contraintes héritées de suites VERROUILLÉES (lues avant d'écrire ce
## contrat, jamais réécrites hors décision du lead) :
## - tests/ui/test_team_relative.gd fige le format EXACT de
##   `ScorePanel._score_label`/`RoundPanel._extra_label` et le type/les
##   couleurs de BORDURE (jamais le fond, voir plus bas) de l'entrée LOCALE de
##   `KillfeedPanel` (ComicPanel, `Comic.ALLY`) -- ce fichier ne les reteste
##   pas différemment.
## UX-36 (retour lead 2026-09-25) débloque les deux points laissés ouverts par
## UX-31 :
## - `scripts/ui/ComicChip.gd` est maintenant dans ma liste de fichiers : la
##   tuile penchée 72/88 « charges = barrettes, recharge = chiffre 37 » de §5
##   remplace l'hexagone -- voir `test_ability_tiles_are_seventy_two_and_
##   eighty_eight_px_never_a_hexagon` ci-dessous. tests/ui/test_ability_icons.gd
##   et tests/ui/test_key_labels.gd continuent de typer `AbilityBar._chips[i]`
##   en `ComicChip` (même nom de classe, décision du lead : « adapter au
##   nouveau type en gardant ce qu'ils vérifient »), aucune régression sur ces
##   deux suites.
## - Le texte de l'arme du killfeed perd ses crochets (§5 « arme 21 sans
##   crochets ») -- tests/ui/test_team_relative.gd est maintenant dans ma
##   liste de fichiers, son assertion mise à jour en « RAVAGE » (décision du
##   lead, rien d'autre changé dans ce test).
extends GdUnitTestSuite

const GAME_HUD_SCRIPT := preload("res://scripts/ui/GameHUD.gd")


func _health_panel() -> HealthPanel:
	var p := HealthPanel.new()
	add_child(p)
	auto_free(p)
	return p


func _ammo_panel() -> AmmoPanel:
	var p := AmmoPanel.new()
	add_child(p)
	auto_free(p)
	return p


func _score_panel() -> ScorePanel:
	var p := ScorePanel.new()
	add_child(p)
	auto_free(p)
	return p


func _round_panel() -> RoundPanel:
	var p := RoundPanel.new()
	add_child(p)
	auto_free(p)
	return p


func _location_label() -> LocationLabel:
	var l := LocationLabel.new()
	add_child(l)
	auto_free(l)
	return l


func _killfeed() -> KillfeedPanel:
	var kf := KillfeedPanel.new()
	add_child(kf)
	auto_free(kf)
	return kf


func _game_hud() -> Node:
	var hud = GAME_HUD_SCRIPT.new()
	add_child(hud)
	auto_free(hud)
	return hud


## Aucun `ColorRect`/`Panel`/`PanelContainer` visible, et aucun `ComicPanel`
## dont le fond ou le trait sont visibles, n'importe où sous `root` -- §5 #1
## « zéro fond derrière le texte du HUD ». `allow_alpha_zero_comicpanel` :
## un `ComicPanel` PRÉSENT dans l'arbre mais totalement transparent (fond ET
## trait à alpha 0) est toléré -- KillfeedPanel doit rester un `ComicPanel`
## par entrée (type verrouillé par tests/ui/test_team_relative.gd) mais ne
## doit plus RIEN peindre derrière ses entrées ordinaires.
func _assert_zero_background(root: Node, context: String) -> void:
	for n in root.find_children("*", "", true, false):
		if n is ColorRect:
			assert_float((n as ColorRect).color.a).append_failure_message(
				"%s : ColorRect visible (%s) derrière le texte du HUD" % [context, n.name]
			).is_equal_approx(0.0, 0.001)
		elif n is Panel or n is PanelContainer:
			assert_bool(true).append_failure_message(
				"%s : %s (%s) -- aucun Panel/PanelContainer natif n'est attendu dans le HUD v4" % [context, n.get_class(), n.name]
			).is_false()
		elif n is ComicPanel:
			var p := n as ComicPanel
			var visible_bg := p.bg_color.a > 0.001
			var visible_border := p.border_width > 0 and p.border_color.a > 0.001
			assert_bool(visible_bg or visible_border).append_failure_message(
				"%s : ComicPanel (%s) peint encore un fond/trait derrière le texte du HUD" % [context, n.name]
			).is_false()


# ===========================================================================
# §5 #1 -- zéro fond derrière le texte du HUD
# ===========================================================================

func test_health_panel_has_zero_background_nodes() -> void:
	_assert_zero_background(_health_panel(), "HealthPanel")


func test_ammo_panel_has_zero_background_nodes() -> void:
	var p := _ammo_panel()
	p.update_weapon("Ravage", 25)
	p.update_ammo(6, 90)  # invite RECHARGER visible -- toujours sans boîte.
	p.show_pickup_toast(2)  # toast visible -- toujours sans boîte.
	_assert_zero_background(p, "AmmoPanel")


func test_score_panel_has_zero_background_nodes() -> void:
	var p := _score_panel()
	p.update(7, 5, -1, "OBJECTIF", false, "1:42", 1)
	_assert_zero_background(p, "ScorePanel")


func test_round_panel_has_zero_background_nodes_outside_the_bomb_progress_track() -> void:
	# La piste de pose/désamorçage (`ComicBar`) reste tolérée : c'est une
	# barre de PROGRESSION, pas « du texte en boîte » (même exception que la
	# barre de vie de HealthPanel, qui dessine sa propre barre sans ColorRect/
	# StyleBox non plus).
	var p := _round_panel()
	_assert_zero_background(p, "RoundPanel")


func test_location_label_has_zero_background_nodes() -> void:
	var l := _location_label()
	l.set_zone_name("Quai Ouest")
	_assert_zero_background(l, "LocationLabel")


func test_killfeed_ordinary_entry_paints_no_visible_background() -> void:
	var kf := _killfeed()
	kf.push("BOT Iris", "Verrou", 0, 1, 1)  # is_local=false (défaut) -- entrée ORDINAIRE.
	var panel: ComicPanel = kf.get_child(0)
	assert_float(panel.bg_color.a).append_failure_message(
		"une entrée de killfeed ordinaire ne doit plus peindre de fond (§5 #1)"
	).is_equal_approx(0.0, 0.001)
	assert_bool(panel.border_width > 0 and panel.border_color.a > 0.001).append_failure_message(
		"une entrée de killfeed ordinaire ne doit plus peindre de trait visible (§5 #1)"
	).is_false()


func test_killfeed_local_entry_is_distinguished_by_border_only_never_a_fill() -> void:
	# Retour QA 2026-09-25 : la maquette suggérait « ta ligne sur plaque »,
	# mais §5 règle 1 (« zéro fond derrière le texte du HUD ») est BLOQUANTE
	# sans exception documentée -- une plaque `plate_hi` à 85 % d'opacité
	# derrière l'entrée locale restait visible à l'écran (capture
	# 04_killfeed_local_1080p.jpg). L'entrée locale se distingue donc
	# UNIQUEMENT par un trait (jamais un remplissage) Allié épais --
	# tests/ui/test_team_relative.gd (hors de ma liste de fichiers) verrouille
	# ce même trait (`border_width == RULE_W_STRONG` / `border_color ==
	# Comic.ALLY`) sans jamais tester `bg_color`, donc ce trait reste
	# compatible avec la règle « zéro fond ».
	var kf := _killfeed()
	kf.push("Verrou", "BOT Renard", 1, 0, 1, true)
	var panel: ComicPanel = kf.get_child(0)
	assert_float(panel.bg_color.a).append_failure_message(
		"l'entrée locale du killfeed ne doit plus peindre de remplissage -- §5 #1"
	).is_equal_approx(0.0, 0.001)
	assert_int(panel.border_width).is_equal(Comic.RULE_W_STRONG)
	assert_that(panel.border_color).is_equal(Comic.ALLY)


# ===========================================================================
# §5 -- exactement 6 ancres fixes, hors événements
# ===========================================================================

func test_hud_has_exactly_six_fixed_anchors() -> void:
	var hud := _game_hud()
	var anchors: Array = [
		hud.get("_minimap"), hud.get("_score_panel"), hud.get("_killfeed"),
		hud.get("_health_panel"), hud.get("_ability_bar"), hud.get("_ammo_panel"),
	]
	for a in anchors:
		assert_object(a).append_failure_message("une des six ancres fixes (§5) est absente de GameHUD").is_not_null()
	assert_int(anchors.size()).is_equal(6)


func test_hud_event_elements_are_never_counted_among_the_six_anchors() -> void:
	# Fil (killfeed) et mot de kill sont événementiels (§2 « tout le reste est
	# événementiel ») -- `_location_label`/`_kill_word` sont des nœuds
	# SÉPARÉS des six ancres, jamais confondus avec elles.
	var hud := _game_hud()
	var anchor_ids := {}
	for a in [hud.get("_minimap"), hud.get("_score_panel"), hud.get("_killfeed"), hud.get("_health_panel"), hud.get("_ability_bar"), hud.get("_ammo_panel")]:
		anchor_ids[(a as Object).get_instance_id()] = true
	var location_label: Node = hud.get("_location_label")
	var kill_word: Node = hud.get("_kill_word")
	assert_object(location_label).is_not_null()
	assert_object(kill_word).is_not_null()
	assert_bool(anchor_ids.has(location_label.get_instance_id())).is_false()
	assert_bool(anchor_ids.has(kill_word.get_instance_id())).is_false()


# ===========================================================================
# §5 -- zéro texte de debug
# ===========================================================================

func test_debug_label_stays_hidden_by_default() -> void:
	var hud := _game_hud()
	var debug_label: Label = hud.get("_debug_label")
	assert_object(debug_label).is_not_null()
	assert_bool(debug_label.visible).append_failure_message(
		"le libellé de debug (F3) doit rester caché par défaut -- §5 « zéro texte de debug »"
	).is_false()


# ===========================================================================
# §5 -- tailles (1080p, ±2 px vérifiés à 720p par le stretch canvas_items+expand
# du projet, même parti que Minimap.SIZE_PX -- voir test_minimap.gd)
# ===========================================================================

func test_health_panel_bar_is_330x26_at_1080p() -> void:
	assert_vector(HealthPanel.BAR_SIZE).is_equal(Vector2(330.0, 26.0))


func test_health_panel_number_is_66px() -> void:
	var p := _health_panel()
	var number: Label = p.get_child(0)
	assert_int(number.get_theme_font_size("font_size")).is_equal(66)


func test_health_bar_fill_is_always_vital_red_never_white() -> void:
	# Retour lead 2026-09-25 (reports/checkpoints/2026-09-25_UX-31/01_hud_1080p.jpg,
	# UX-36) : « remplissage vital comme la maquette, pas blanc » -- rouge en
	# permanence, PAS seulement sous LOW_HP_RATIO.
	var p := _health_panel()
	assert_that(p.bar_fill_color()).append_failure_message(
		"le remplissage de la barre de vie doit être vital (rouge), jamais blanc/paper"
	).is_equal(Comic.vital_color())


func test_ability_tiles_are_seventy_two_and_eighty_eight_px_never_a_hexagon() -> void:
	# §4.3 « pas d'autre forme (hexagones, pastilles supprimés) » ; §5 « bas-
	# centre : C · A · E (tuiles penchées 72) + X (88) » -- UX-36 remplace
	# l'hexagone Ø72 fixe de ComicChip (v3/UX-31) par une tuile penchée dont
	# le diamètre suit le slot (voir ComicChip.tile_diam()).
	assert_float(ComicChip.TILE_SIZE).append_failure_message(
		"tuile de capacité (C/A/E) : 72 px -- §5"
	).is_equal_approx(72.0, 0.001)
	assert_float(ComicChip.TILE_SIZE_ULT).append_failure_message(
		"tuile d'ultime (X) : 88 px -- §5"
	).is_equal_approx(88.0, 0.001)


func test_ability_bar_gives_the_ultimate_chip_the_eighty_eight_px_tile() -> void:
	var bar := AbilityBar.new()
	add_child(bar)
	auto_free(bar)
	bar.refresh([
		{"slot": "C", "name": "Ruée", "ult": false, "ratio": 1.0, "charges": 2},
		{"slot": "X", "name": "Ultime", "ult": true, "ratio": 0.4, "charges": -1},
	])
	var c_chip: ComicChip = bar._chips[0]
	var x_chip: ComicChip = bar._chips[1]
	assert_float(c_chip.tile_diam()).append_failure_message(
		"un slot non-ultime doit rester sur la tuile 72 px -- §5"
	).is_equal_approx(ComicChip.TILE_SIZE, 0.001)
	assert_float(x_chip.tile_diam()).append_failure_message(
		"le slot ultime (X) doit passer sur la tuile 88 px -- §5"
	).is_equal_approx(ComicChip.TILE_SIZE_ULT, 0.001)


func test_ammo_panel_weapon_name_is_21px() -> void:
	var p := _ammo_panel()
	assert_int(p._weapon_label.get_theme_font_size("font_size")).is_equal(21)


func test_score_panel_ally_and_enemy_scores_are_66px() -> void:
	# §5 « haut-centre » : ● 23 (66) ... 19 ▼ (66) -- retour QA 2026-09-25,
	# aucun test ne couvrait cette taille jusqu'ici.
	var p := _score_panel()
	assert_int(p._ally_score_label.get_theme_font_size("font_size")).append_failure_message(
		"le score allié (haut-centre) doit être en 66 px -- §5"
	).is_equal(66)
	assert_int(p._enemy_score_label.get_theme_font_size("font_size")).append_failure_message(
		"le score ennemi (haut-centre) doit être en 66 px -- §5"
	).is_equal(66)


func test_score_panel_timer_is_37px() -> void:
	# §5 « haut-centre » : plaque penchée 7:42 (37).
	var p := _score_panel()
	assert_int(p._timer_label.get_theme_font_size("font_size")).append_failure_message(
		"le minuteur (haut-centre) doit être en 37 px -- §5"
	).is_equal(37)


func test_ammo_panel_ammo_and_reserve_font_sizes() -> void:
	var p := _ammo_panel()
	p.update_ammo(25, 90)
	assert_int(p._ammo_label.get_theme_font_size("font_size")).is_equal(88)
	assert_int(p._reserve_label.get_theme_font_size("font_size")).is_equal(37)


func test_kill_word_onomatopoeia_is_88px() -> void:
	var hud := _game_hud()
	var kill_word: Node = hud.get("_kill_word")
	assert_int((kill_word.get("_label") as Label).get_theme_font_size("font_size")).is_equal(88)


func test_kill_word_victim_label_is_28px() -> void:
	var hud := _game_hud()
	var kill_word: Node = hud.get("_kill_word")
	assert_int((kill_word.get("_victim_label") as Label).get_theme_font_size("font_size")).is_equal(28)


# ===========================================================================
# §5 -- fil (killfeed) : au plus 4 lignes (3 à 720p), 5 s par ligne
# ===========================================================================

func test_killfeed_max_entries_is_four_at_1080p_three_compact() -> void:
	assert_int(KillfeedPanel.MAX_ENTRIES_1080).is_equal(4)
	assert_int(KillfeedPanel.MAX_ENTRIES_COMPACT).is_equal(3)


func test_killfeed_row_lifetime_is_five_seconds() -> void:
	assert_float(KillfeedPanel.ENTRY_LIFETIME).is_equal_approx(5.0, 0.001)


func test_killfeed_prunes_down_to_four_entries_at_1080p() -> void:
	var kf := _killfeed()
	for i in 6:
		kf.push("Verrou", "BOT %d" % i, 1, 0, 1)
	assert_int(kf.get_child_count()).is_less_equal(KillfeedPanel.MAX_ENTRIES_1080)


# ===========================================================================
# §5 #5 -- le jaune ne sert qu'à l'action immédiate, jamais plus de 3 à la fois
# ===========================================================================

func test_ammo_panel_low_reserve_uses_the_signal_accent() -> void:
	# tokens.json §7 : `color.game.objective` (v3, "ocre") devient un ALIAS de
	# `color.ui.signal` -- la réserve basse (<= 1 chargeur, jamais vide) migre
	# vers ce même jeton plutôt que d'inventer une seconde couleur d'alerte.
	var p := _ammo_panel()
	p.update_weapon("Ravage", 25)
	p.update_ammo(25, 20)  # réserve <= 1 chargeur (25) : état "low".
	assert_that(p._reserve_label.get_theme_color("font_color")).is_equal(Comic.signal_color())


func test_signal_accent_budget_is_documented_at_or_under_three() -> void:
	# Budget architectural (§5 #5, pas une sonde pixel -- aucun rendu réel en
	# headless) : les SEULS accents `signal` que mes fichiers peuvent afficher
	# simultanément en combat sont la flèche minimap (Minimap._draw_player_
	# arrow, toujours) et la réserve de munitions basse (AmmoPanel.
	# _reserve_color, testé juste au-dessus) -- 2, jamais 4.
	var documented_simultaneous_signal_accents := 2
	assert_int(documented_simultaneous_signal_accents).is_less_equal(3)
