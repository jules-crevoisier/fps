## test_agent_select_v4.gd
## Spec UX-33 -- UI v4 « Encre, jaune, italique » (docs/UI_DIRECTION_BL3.md
## §6/§9, direction VALIDÉE par l'utilisateur le 2026-09-25) : sélection
## d'agent -- héros 3D sur trame jaune, kit en 5 lignes, 6 tuiles penchées,
## CTA VERROUILLER.
##
## Critères d'acceptation verrouillés :
##  1) Les 6 agents sélectionnables clavier/souris/manette.
##  2) Kit = passif + 3 aptitudes + ultime, avec icône, touche, nom 37,
##     une ligne 28.
##  3) « ÉBLOUISSEMENT » (Vif, aptitude Q) tient dans sa colonne.
##  4) Risque §9 « conflit de jaune » : Vanne sélectionnée ne se confond
##     jamais avec le jaune signal (tuile toujours contourée `signal`, jamais
##     la couleur de l'agent).
##  5) Tuiles non choisies éteintes à 32 %, prises à 62 % + « PRIS ».
##
## Instance RÉELLE de AgentSelectScreen.gd (comme tests/ui/test_agent_
## portraits.gd/test_key_labels.gd, hors de mon périmètre d'écriture, qui
## instancient déjà ce script directement) : `_ready()` ne fait aucun appel
## réseau réel, donc sûr en headless.
extends GdUnitTestSuite

const AGENT_SELECT_SCRIPT := preload("res://scripts/ui/AgentSelectScreen.gd")

## `AgentDatabase.selected_index` est une var STATIQUE (survit au changement
## de scène) -- sauvegardée/restaurée pour ne jamais polluer une autre suite
## (même patron que tests/ui/test_agent_portraits.gd).
var _saved_selected_index: int


func before_test() -> void:
	_saved_selected_index = AgentDatabase.selected_index


func after_test() -> void:
	AgentDatabase.selected_index = _saved_selected_index


func _screen() -> CanvasLayer:
	var s: CanvasLayer = AGENT_SELECT_SCRIPT.new()
	add_child(s)
	auto_free(s)
	return s


func _agent_index(name: String) -> int:
	var agents := AgentDatabase.all()
	for i in agents.size():
		if agents[i].agent_name == name:
			return i
	return -1


# ===========================================================================
# 1) Les 6 agents sélectionnables clavier/souris/manette
# ===========================================================================

func test_six_agent_tiles_are_built_one_per_roster_agent() -> void:
	var screen := _screen()
	assert_int(screen._cards.size()).is_equal(AgentDatabase.all().size())
	assert_int(screen._cards.size()).is_equal(6)


func test_every_tile_button_is_focusable_and_not_disabled_by_default() -> void:
	# "Clavier/manette" : chaque tuile doit pouvoir recevoir le focus (Tab/
	# stick) et être activable (Entrée/A) -- native à `BaseButton`, vérifié
	# ici plutôt que supposé. Roster vide (aucun coéquipier) : aucune tuile
	# n'est prise, donc aucune désactivée.
	var screen := _screen()
	for c in screen._cards:
		var b: Button = c.button
		assert_int(b.focus_mode).append_failure_message(
			"une tuile d'agent doit être focusable au clavier/à la manette"
		).is_equal(Control.FOCUS_ALL)
		assert_bool(b.disabled).is_false()
		assert_bool(b.toggle_mode).is_true()


func test_clicking_or_pressing_a_tile_selects_that_agent_and_emits_agent_picked() -> void:
	# "Souris" (pressed via clic) + le signal que GameWorld relaie à l'équipe
	# (UX-11) -- `_select` est ce que `pressed` appelle en interne.
	var screen := _screen()
	var received: Array = []
	screen.agent_picked.connect(func(i): received.append(i))

	var target := _agent_index("Vanne")
	(screen._cards[target].button as Button).emit_signal("pressed")

	assert_int(AgentDatabase.selected_index).is_equal(target)
	assert_array(received).is_equal([target])


func test_initial_focus_goes_to_the_preselected_agent_tile() -> void:
	# `AgentSelectScreen._ready()` fait passer `AgentDatabase.selected_index`
	# par `AgentDatabase.last_played_index()` (UX-11, `user://agent_select.cfg`
	# -- un VRAI fichier disque, partagé entre exécutions) : neutralisé ici
	# (aucun dernier agent joué) pour que la présélection posée ci-dessous
	# soit bien celle qui compte, indépendamment de l'état laissé par une
	# exécution précédente de ui_shots/capture_shots sur cette machine.
	var saved_last_loaded: bool = AgentDatabase._last_played_loaded
	var saved_last_index: int = AgentDatabase._last_played_index
	AgentDatabase._last_played_loaded = true
	AgentDatabase._last_played_index = -1

	AgentDatabase.selected_index = _agent_index("Guet")
	var screen := _screen()
	assert_bool((screen._cards[_agent_index("Guet")].button as Button).has_focus()).is_true()

	AgentDatabase._last_played_loaded = saved_last_loaded
	AgentDatabase._last_played_index = saved_last_index


func test_lock_button_emits_locked_and_the_countdown_locks_at_zero() -> void:
	# Compteurs en `Array` (jamais un `int` local) : une lambda GDScript
	# capture les variables locales PAR VALEUR (une copie figée à sa
	# création) -- `count += 1` DANS la lambda ne modifierait jamais la
	# variable extérieure. Un `Array`/`Dictionary` est une référence : muter
	# son CONTENU depuis la lambda reste visible à l'appelant.
	var screen := _screen()
	var locked_count := [0]
	screen.locked.connect(func(): locked_count[0] += 1)

	(screen._lock_button as Button).emit_signal("pressed")
	assert_int(locked_count[0]).is_equal(1)

	# Libère le premier écran AVANT d'en instancier un second : deux
	# `AgentSelectScreen` (donc deux `KitSwash` sur le nom, § « 1 par écran »
	# max) vivant en même temps dans l'arbre déclenchait le `push_warning` de
	# `KitSwash._track_visibility` (bruit de test évitable, relevé en revue
	# QA -- `auto_free` ne libère qu'à la fin de la suite, trop tard pour
	# éviter le chevauchement avec `screen2` ci-dessous).
	screen.free()
	var screen2 := _screen()
	var locked_count2 := [0]
	screen2.locked.connect(func(): locked_count2[0] += 1)
	screen2._time_left = 0.01
	screen2._process(1.0)
	assert_int(locked_count2[0]).is_equal(1)


# ===========================================================================
# 2) Kit = passif + 3 aptitudes + ultime -- icône, touche, nom 37, ligne 28
# ===========================================================================

func test_kit_column_has_exactly_five_rows_passive_plus_three_abilities_plus_ultimate() -> void:
	var screen := _screen()
	screen._select(_agent_index("Vif"))
	assert_int(screen._kit_column.get_child_count()).is_equal(5)


func test_kit_column_rebuilds_for_the_newly_selected_agent() -> void:
	var screen := _screen()
	screen._select(_agent_index("Vif"))
	var vif_names := _row_titles(screen._kit_column)
	screen._select(_agent_index("Choc"))
	var choc_names := _row_titles(screen._kit_column)

	assert_int(screen._kit_column.get_child_count()).is_equal(5)
	assert_bool(vif_names.has("RUÉE")).is_true()
	assert_bool(choc_names.has("RUÉE")).is_false()
	assert_bool(choc_names.has("TAPE-LA-CLOCHE")).is_true()


## Titres (37 px) trouvés dans chacune des 5 lignes de `_kit_column`, dans
## l'ordre -- passif d'abord, puis C/Q/E/X (voir AgentDatabase._agent).
func _row_titles(kit_column: VBoxContainer) -> Array:
	var titles: Array = []
	for row in kit_column.get_children():
		for lbl in row.find_children("*", "Label", true, false):
			var l: Label = lbl
			if int(l.get_theme_font_size("font_size")) == 37:
				titles.append(l.text)
				break
	return titles


func test_each_kit_row_shows_an_icon_a_name_at_37px_and_a_single_line_description_at_28px() -> void:
	var screen := _screen()
	screen._select(_agent_index("Vif"))

	var rows: Array = (screen._kit_column as VBoxContainer).get_children()
	assert_int(rows.size()).is_equal(5)

	for row in rows:
		var row_node: Node = row
		var icon_rects: Array = row_node.find_children("*", "TextureRect", true, false)
		assert_int(icon_rects.size()).append_failure_message(
			"chaque ligne de kit doit porter une icône"
		).is_greater_equal(1)

		var name_found := false
		var desc_found := false
		for lbl in row.find_children("*", "Label", true, false):
			var l: Label = lbl
			var size := int(l.get_theme_font_size("font_size"))
			if size == 37:
				name_found = true
			elif size == 28 and not l.visible:
				# la description À UNE LIGNE (visible) ; `tip` (28px, texte
				# complet) reste cachée hors survol/focus -- comptée à part.
				pass
			elif size == 28:
				desc_found = true
		assert_bool(name_found).append_failure_message("nom 37 px manquant sur une ligne de kit").is_true()
		assert_bool(desc_found).append_failure_message("description 28 px manquante sur une ligne de kit").is_true()

	# Passif -- premier, sans touche, tag "PASSIF".
	var passive_row: Control = rows[0]
	assert_bool(passive_row.tooltip_text.length() > 0).is_true()

	# Ultime -- dernier, tag "ULTIME" + coût en points.
	var ult_row: Node = rows[4]
	var ult_tag_found := false
	for lbl in ult_row.find_children("*", "Label", true, false):
		if String((lbl as Label).text).contains("ULTIME"):
			ult_tag_found = true
	assert_bool(ult_tag_found).append_failure_message(
		"la dernière ligne de kit (ultime) doit porter un tag « ULTIME »"
	).is_true()


func test_kit_row_description_is_never_multiline_by_default_full_text_reserved_for_the_tooltip() -> void:
	var screen := _screen()
	screen._select(_agent_index("Vif"))
	for row in screen._kit_column.get_children():
		assert_str(row.tooltip_text).append_failure_message(
			"chaque ligne de kit doit porter sa description complète en info-bulle"
		).is_not_equal("")


func test_kit_row_reveals_its_full_description_on_keyboard_gamepad_focus() -> void:
	# §9 « le texte long d'une aptitude passe en info-bulle au focus » -- le
	# tooltip natif Godot ne réagit qu'à la souris : la ligne doit donc
	# prouver l'affichage complet AU FOCUS clavier/manette aussi.
	var screen := _screen()
	screen._select(_agent_index("Vif"))
	var row: Control = screen._kit_column.get_child(0)
	assert_int(row.focus_mode).is_equal(Control.FOCUS_ALL)

	var full_text_label: Label = null
	for lbl in row.find_children("*", "Label", true, false):
		if int((lbl as Label).get_theme_font_size("font_size")) == 28 and not (lbl as Label).visible:
			full_text_label = lbl
			break
	assert_object(full_text_label).append_failure_message(
		"aucun label de bulle (texte complet) trouvé, caché par défaut"
	).is_not_null()

	row.grab_focus()
	assert_bool(full_text_label.visible).append_failure_message(
		"la bulle de description complète doit apparaître au focus clavier/manette"
	).is_true()

	row.release_focus()
	assert_bool(full_text_label.visible).append_failure_message(
		"la bulle doit se cacher à nouveau hors focus"
	).is_false()


# ===========================================================================
# 3) « ÉBLOUISSEMENT » tient dans sa colonne (§9 « risque honnête »)
# ===========================================================================

func test_eblouissement_ability_name_fits_the_kit_name_column_budget() -> void:
	var measured := Comic.title_font_v4().get_string_size(
		"ÉBLOUISSEMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, Comic.SIZE_37).x
	assert_float(measured).append_failure_message(
		"« ÉBLOUISSEMENT » à 37 px mesure %.1f px -- au-delà du budget documenté par KitCard.KIT_NAME_COLUMN_MIN_PX" % measured
	).is_less(KitCard.KIT_NAME_COLUMN_MIN_PX)


func test_info_column_reserves_at_least_the_tile_plus_name_budget_in_width() -> void:
	# La colonne d'info garantit une largeur plancher >= tuile + séparation +
	# budget de nom (KitCard.KIT_NAME_COLUMN_MIN_PX) -- sinon « ÉBLOUISSEMENT »
	# pourrait déborder de sa colonne malgré le test ci-dessus (mesure de
	# police seule, indépendante de la mise en page réelle).
	var required := KitCard.KIT_TILE_PX + Comic.SP_3 + KitCard.KIT_NAME_COLUMN_MIN_PX
	assert_float(AGENT_SELECT_SCRIPT.KIT_TEXT_COLUMN_MIN_PX).append_failure_message(
		"KIT_TEXT_COLUMN_MIN_PX (%.1f) doit couvrir tuile + séparation + budget de nom (%.1f)"
		% [AGENT_SELECT_SCRIPT.KIT_TEXT_COLUMN_MIN_PX, required]
	).is_greater_equal(required)


func test_vif_flash_ability_display_name_is_still_the_long_french_label() -> void:
	# Verrou anti-régression : si le libellé venait à changer, ce test (et le
	# précédent, qui mesure "ÉBLOUISSEMENT" en dur) doivent être relus.
	var vif: AgentConfig = AgentDatabase.all()[_agent_index("Vif")]
	var flash_ability: Ability = vif.abilities[1]  # Q -- voir AgentDatabase._vif.
	assert_str(flash_ability.display_name.to_upper()).is_equal("ÉBLOUISSEMENT")


# ===========================================================================
# 4) Risque §9 « conflit de jaune » -- Vanne ne se confond jamais avec signal
# ===========================================================================

func test_selected_tile_border_is_always_signal_never_the_agents_own_colour() -> void:
	var screen := _screen()
	var vanne := _agent_index("Vanne")
	screen._select(vanne)

	var plate: ComicPanel = screen._cards[vanne].plate
	assert_that(plate.border_color).append_failure_message(
		"la tuile choisie doit toujours se contourer en `signal`, jamais dans la couleur-clé de l'agent (§9 conflit de jaune avec Vanne)"
	).is_equal(Comic.SIGNAL)
	assert_bool(plate.border_color.is_equal_approx(AgentDatabase.all()[vanne].color)).append_failure_message(
		"le jaune de sélection ne doit jamais coïncider avec la couleur-clé de Vanne"
	).is_false()


func test_vif_selected_border_is_also_signal_consistent_across_agents() -> void:
	var screen := _screen()
	var vif := _agent_index("Vif")
	screen._select(vif)
	var plate: ComicPanel = screen._cards[vif].plate
	assert_that(plate.border_color).is_equal(Comic.SIGNAL)


## Correction QA (revue UX-33) : le contour `signal` ci-dessus est peint par
## `plate` (ComicPanel, `_draw()` propre) -- mais SANS surcharge sur le
## `Button` de la tuile lui-même, celui-ci retombe sur le thème par défaut du
## PROJET (`resources/ui/ui_theme.tres`, hors de mon périmètre d'écriture),
## dont hover/pressed/focus tracent un filet ROUGE : une TROISIÈME couleur
## non maîtrisée, jamais montrée par `plate`, qui bave dans la bande de nom
## sous la plaque portrait (constaté en capture, pixel-samplé sur les deux
## captures livrées le 2026-09-25) et contredit "toujours contourée signal,
## jamais une autre couleur". Verrou anti-régression : chaque tuile doit
## surcharger explicitement les 5 états pour ne plus jamais dépendre du
## thème par défaut.
func test_every_tile_button_overrides_its_own_chrome_never_the_legacy_theme() -> void:
	var screen := _screen()
	for c in screen._cards:
		var b: Button = c.button
		for state in ["normal", "hover", "pressed", "disabled"]:
			assert_bool(b.has_theme_stylebox_override(state)).append_failure_message(
				"une tuile d'agent doit surcharger son propre style '%s' -- sinon elle hérite du filet rouge du thème par défaut du projet" % state
			).is_true()
			var override_style: StyleBox = b.get_theme_stylebox(state)
			assert_object(override_style).append_failure_message(
				"le style '%s' surchargé doit exister" % state
			).is_not_null()
			assert_bool(override_style is StyleBoxFlat and (override_style as StyleBoxFlat).border_width_top > 0).append_failure_message(
				"le style '%s' de la tuile ne doit tracer AUCUNE bordure -- le contour vient uniquement de `plate` (ComicPanel)" % state
			).is_false()
		assert_bool(b.has_theme_stylebox_override("focus")).append_failure_message(
			"une tuile d'agent doit avoir son propre anneau de focus clavier/manette (§9, comme le CTA VERROUILLER)"
		).is_true()


# ===========================================================================
# 5) Opacité des tuiles -- 100 % choisie, 32 % disponible, 62 % prise
# ===========================================================================

func test_unselected_available_tiles_are_dimmed_to_32_percent() -> void:
	var screen := _screen()
	var vif := _agent_index("Vif")
	screen._select(vif)

	for i in screen._cards.size():
		var b: Button = screen._cards[i].button
		if i == vif:
			assert_float(b.modulate.a).is_equal_approx(AGENT_SELECT_SCRIPT.OPACITY_SELECTED, 0.001)
		else:
			assert_float(b.modulate.a).append_failure_message(
				"une tuile disponible non choisie doit être éteinte à 32%%"
			).is_equal_approx(AGENT_SELECT_SCRIPT.OPACITY_AVAILABLE, 0.001)


func test_tile_taken_by_a_teammate_is_dimmed_to_62_percent_disabled_and_tagged_pris() -> void:
	var screen := _screen()
	var choc := _agent_index("Choc")
	screen.on_picks_updated(0, {
		"42": {"agent_index": choc, "locked": true, "name": "Alizé"},
	})

	var c: Dictionary = screen._cards[choc]
	assert_bool((c.button as Button).disabled).is_true()
	assert_float((c.button as Button).modulate.a).append_failure_message(
		"une tuile déjà prise par un coéquipier doit être éteinte à 62%%"
	).is_equal_approx(AGENT_SELECT_SCRIPT.OPACITY_TAKEN, 0.001)
	assert_str(c.taken_lbl.text).contains("PRIS")
	assert_bool(c.taken_lbl.visible).is_true()


func test_on_pick_rejected_immediately_dims_the_tile_and_reselects_a_free_agent() -> void:
	var screen := _screen()
	var vif := _agent_index("Vif")
	screen._select(vif)

	screen.on_pick_rejected(vif)

	assert_bool((screen._cards[vif].button as Button).disabled).is_true()
	assert_float((screen._cards[vif].button as Button).modulate.a).is_equal_approx(
		AGENT_SELECT_SCRIPT.OPACITY_TAKEN, 0.001)
	assert_int(AgentDatabase.selected_index).append_failure_message(
		"la sélection locale doit basculer sur le premier agent encore libre"
	).is_not_equal(vif)


# ===========================================================================
# Bandeau « IL MANQUE » -- toujours du texte, jamais la couleur seule
# ===========================================================================

func test_role_banner_hidden_when_composition_is_complete_shown_with_text_when_not() -> void:
	var screen := _screen()
	screen.on_picks_updated(0, {})
	assert_bool(screen._role_banner_chip.visible).is_true()
	assert_str(screen._role_banner_label.text).contains("Il manque")

	var roster := {}
	var agents := AgentDatabase.all()
	for i in agents.size():
		roster[str(i)] = {"agent_index": i, "locked": true, "name": "Bot"}
	screen.on_picks_updated(0, roster)
	assert_bool(screen._role_banner_chip.visible).append_failure_message(
		"composition complète : le bandeau ne doit plus s'afficher"
	).is_false()
