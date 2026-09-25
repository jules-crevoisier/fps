## test_key_labels.gd
## Spec UX-13 (docs/research/10_ammo_kits_input.md §4, "Libellés réels des
## touches partout") : la barre de capacités, l'écran de sélection d'agent et
## le menu Agents affichent le libellé de la VRAIE touche (via
## `PlayerInput.action_for_slot` + `KeyLabel.for_action`), jamais
## `Ability.slot` brut ("C"/"Q"/"E"/"X", identifiant RÉSEAU/bots interne, voir
## AgentDatabase.SLOTS). En --headless, `DisplayServer.keyboard_get_label_
## from_physical` n'est pas supporté (constaté en isolant le crash au boot de
## training_ground.tscn, voir KeyLabel.gd) : `KeyLabel.for_action` retombe
## alors sur "[action]" plutôt que d'interroger l'OS -- ce test verrouille
## donc le CÂBLAGE (le bon nom d'action InputMap, jamais le slot brut affiché)
## et l'absence de SCRIPT ERROR au boot. La vérité visuelle "En AZERTY forcé,
## la barre montre C A E X" se constate par `ui_shots` sur une vraie machine
## (docs/research/10_ammo_kits_input.md §4.3), pas par une suite headless.
extends GdUnitTestSuite

# `AgentSelectScreen`/`AgentMenu` n'ont pas de `class_name` (même situation que
# `MainMenu.gd`, voir tests/ui/test_main_menu.gd) : on précharge le script et
# on type les variables locales sur leur classe MOTEUR de base (`extends`),
# comme `_menu() -> Node3D` là-bas -- les champs préfixés `_` restent lisibles
# dessus (GDScript résout les membres du script attaché à l'exécution).
const AGENT_SELECT_SCREEN_SCRIPT := preload("res://scripts/ui/AgentSelectScreen.gd")
const AGENT_MENU_SCRIPT := preload("res://scripts/ui/AgentMenu.gd")


# ================================================ PlayerInput.action_for_slot (pur)

func test_action_for_slot_maps_the_four_known_ability_slots() -> void:
	assert_str(PlayerInput.action_for_slot("C")).is_equal("ability_c")
	assert_str(PlayerInput.action_for_slot("Q")).is_equal("ability_q")
	assert_str(PlayerInput.action_for_slot("E")).is_equal("ability_e")
	assert_str(PlayerInput.action_for_slot("X")).is_equal("ultimate")


func test_action_for_slot_of_an_unknown_slot_is_empty_never_a_crash() -> void:
	assert_str(PlayerInput.action_for_slot("Z")).is_equal("")
	assert_str(PlayerInput.action_for_slot("")).is_equal("")


# ================================================ KeyLabel.for_action (headless : jamais le slot brut)

func test_key_label_for_the_four_ability_actions_is_never_the_bare_slot_letter() -> void:
	var by_slot := {"C": "ability_c", "Q": "ability_q", "E": "ability_e", "X": "ultimate"}
	for slot in by_slot:
		var action: String = by_slot[slot]
		var lbl := KeyLabel.for_action(PlayerInput.action_for_slot(slot))
		assert_str(lbl).append_failure_message(
			"slot '%s' -> libellé '%s' : Ability.slot ne doit plus jamais s'afficher tel quel" % [slot, lbl]
		).is_not_equal(slot)
		assert_str(lbl).append_failure_message(
			"libellé '%s' attendu pour l'action '%s'" % [lbl, action]
		).contains(action)


func test_key_label_headless_boot_never_touches_the_display_server_directly() -> void:
	# Le garde-fou de KeyLabel.gd existe pour que `_ready()` ne plante jamais
	# en tête headless (voir doc de classe de KeyLabel.gd) -- verrouillé ici en
	# appelant `for_action` pour les 4 actions de capacité sans qu'aucun appel
	# ne remonte d'erreur (le simple fait d'arriver ici sans exception le
	# prouve ; le format "[action]" confirme qu'on est bien sur le chemin
	# headless, pas sur celui qui interroge l'OS).
	assert_str(KeyLabel.for_action("ability_c")).is_equal("[ability_c]")
	assert_str(KeyLabel.for_action("ability_q")).is_equal("[ability_q]")
	assert_str(KeyLabel.for_action("ability_e")).is_equal("[ability_e]")
	assert_str(KeyLabel.for_action("ultimate")).is_equal("[ultimate]")


# ================================================ AbilityBar : le badge affiche l'action, jamais le slot brut

func _ability_bar() -> AbilityBar:
	var bar := AbilityBar.new()
	add_child(bar)
	auto_free(bar)
	return bar


func test_ability_bar_chip_key_is_the_key_label_never_the_raw_slot() -> void:
	var bar := _ability_bar()
	bar.refresh([
		{"slot": "Q", "name": "Fumée", "ult": false, "ratio": 1.0, "charges": 0},
	])
	# Accès direct au champ interne du badge (même patron que tests/ui/
	# test_main_menu.gd sur menu._host_btn/._mode_id : ce dépôt teste
	# directement les champs préfixés `_` plutôt que de parser l'arbre visuel).
	var chip: ComicChip = bar._chips[0]
	assert_str(chip._key).append_failure_message(
		"le badge de capacité affiche encore 'Q' (Ability.slot brut) au lieu du libellé de la vraie touche"
	).is_not_equal("Q")
	assert_str(chip._key).is_equal(KeyLabel.for_action(PlayerInput.action_for_slot("Q")))


func test_ability_bar_chip_key_matches_each_slot_action() -> void:
	var bar := _ability_bar()
	bar.refresh([
		{"slot": "C", "name": "Ruée", "ult": false, "ratio": 1.0, "charges": 2},
		{"slot": "E", "name": "Signature", "ult": false, "ratio": 1.0, "charges": 0},
		{"slot": "X", "name": "Ultime", "ult": true, "ratio": 0.4, "charges": -1},
	])
	var expected := [
		KeyLabel.for_action(PlayerInput.action_for_slot("C")),
		KeyLabel.for_action(PlayerInput.action_for_slot("E")),
		KeyLabel.for_action(PlayerInput.action_for_slot("X")),
	]
	for i in expected.size():
		var chip: ComicChip = bar._chips[i]
		assert_str(chip._key).is_equal(expected[i])


# ================================================ AgentSelectScreen / AgentMenu : idem, jamais le slot brut

func _agent_select_screen() -> CanvasLayer:
	var screen: CanvasLayer = AGENT_SELECT_SCREEN_SCRIPT.new()
	add_child(screen)
	auto_free(screen)
	return screen


func _agent_menu() -> Control:
	var menu: Control = AGENT_MENU_SCRIPT.new()
	add_child(menu)
	auto_free(menu)
	return menu


## Les DEUX formats que l'ancien code produisait avec `ab.slot` brut :
## "SLOT : nom" (liste courte des cartes) et "(SLOT)" (description détaillée).
## Ni l'un ni l'autre ne doit plus jamais apparaître, quel que soit l'agent.
func _assert_no_raw_slot_formatting(all_text: String, context: String) -> void:
	for slot in ["C", "Q", "E", "X"]:
		assert_bool(all_text.contains(slot + " : ")).append_failure_message(
			"%s affiche encore 'Ability.slot : nom' avec le slot brut '%s'" % [context, slot]
		).is_false()
		assert_bool(all_text.contains("(%s)" % slot)).append_failure_message(
			"%s affiche encore '(Ability.slot)' avec le slot brut '(%s)'" % [context, slot]
		).is_false()


func test_agent_select_screen_never_shows_a_bare_slot_letter() -> void:
	var screen := _agent_select_screen()
	var all_text := ""
	for lbl in screen.find_children("*", "Label", true, false):
		all_text += (lbl as Label).text + "\n"
	_assert_no_raw_slot_formatting(all_text, "AgentSelectScreen")


func test_agent_select_screen_desc_label_uses_the_key_label_for_the_selected_agent() -> void:
	var screen := _agent_select_screen()
	var agent: AgentConfig = AgentDatabase.all()[AgentDatabase.selected_index]
	for ab in agent.abilities:
		var expected := KeyLabel.for_action(PlayerInput.action_for_slot(ab.slot))
		assert_bool(screen._desc_label.text.contains("(%s)" % expected)).append_failure_message(
			"la description ne montre pas '(%s)' pour %s -- %s" % [expected, ab.display_name, screen._desc_label.text]
		).is_true()


func test_agent_menu_never_shows_a_bare_slot_letter() -> void:
	var menu := _agent_menu()
	var all_text := ""
	for lbl in menu.find_children("*", "Label", true, false):
		all_text += (lbl as Label).text + "\n"
	_assert_no_raw_slot_formatting(all_text, "AgentMenu")
