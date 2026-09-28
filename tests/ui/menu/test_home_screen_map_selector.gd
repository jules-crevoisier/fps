## test_home_screen_map_selector.gd
## Spec (brief lead 2026-09-28, Canyon Express -- sélecteur de carte du
## salon) : une case "Carte" au-dessus de « Compléter avec des bots »/
## « Jouer ! » ne propose que les cartes RÉELLEMENT jouables (MapCatalog.
## selectable() -- Shipment aujourd'hui ; Canyon Express apparaîtra tout
## seul, sans changement de code, le jour où sa scène existera). L'id choisi
## doit atteindre MatchConfig.map_id (donc MatchLauncher.start_local/
## configure_local, qui le lisent) exactement comme le préréglage de mode le
## fait déjà pour mode_id/team_size/bot_difficulty.
##
## Instancie un VRAI HomeScreen (comme MainMenu.gd : `HomeScreen.new()`, pas
## de scène dédiée) -- construit un héros 3D vivant (SubViewport + shaders
## toon_bd), donc UI, à lancer avec --ignoreHeadlessMode (voir CLAUDE.md
## « Tests »).
extends GdUnitTestSuite

const HomeScreen := preload("res://scripts/ui/menu/HomeScreen.gd")


func _home() -> HomeScreen:
	var h: HomeScreen = auto_free(HomeScreen.new())
	add_child(h)
	return h


func test_only_maps_with_an_existing_scene_get_a_ticket() -> void:
	var h := _home()
	var selectable := MapCatalog.selectable()
	assert_int(h._map_tickets.size()).is_equal(selectable.size())
	for entry in selectable:
		assert_bool(h._map_tickets.has(str(entry["id"]))).append_failure_message(
			"pas de ticket pour %s" % entry["id"]
		).is_true()
	# Canyon Express n'a de ticket QUE si sa scène a fini par être livrée --
	# bascule automatique, aucun changement de code à faire ce jour-là.
	assert_bool(h._map_tickets.has("canyon_express")).is_equal(
		ResourceLoader.exists("res://scenes/levels/maps/canyon_express.tscn"))


func test_default_selected_map_is_shipment_on_first_launch() -> void:
	var previous_map := MatchConfig.map_id
	var previous_mode := MatchConfig.mode_id
	MatchConfig.map_id = ""
	MatchConfig.set_mode("tdm")
	var h := _home()
	assert_str(h._selected_map_id).is_equal("shipment")
	MatchConfig.map_id = previous_map
	MatchConfig.set_mode(previous_mode)


func test_default_selected_map_keeps_a_valid_last_choice() -> void:
	# UX-08 (MatchConfig.save_last/load_last) : la carte choisie la session
	# d'avant reste sélectionnée tant qu'elle est encore jouable.
	var previous_map := MatchConfig.map_id
	MatchConfig.map_id = "shipment"
	var h := _home()
	assert_str(h._selected_map_id).is_equal("shipment")
	MatchConfig.map_id = previous_map


func test_default_selected_map_falls_back_when_the_last_choice_is_not_playable() -> void:
	# Une carte absente du catalogue (build future retirée, id corrompu) --
	# jamais un id mort transmis à MatchLauncher.
	var previous_map := MatchConfig.map_id
	var previous_mode := MatchConfig.mode_id
	MatchConfig.map_id = "does_not_exist"
	MatchConfig.set_mode("tdm")
	var h := _home()
	assert_str(h._selected_map_id).is_equal("shipment")
	MatchConfig.map_id = previous_map
	MatchConfig.set_mode(previous_mode)


func test_selecting_a_ticket_updates_selection_and_match_config() -> void:
	var h := _home()
	var previous := MatchConfig.map_id
	h._on_map_selected("shipment")
	assert_str(h._selected_map_id).is_equal("shipment")
	assert_str(MatchConfig.map_id).is_equal("shipment")
	MatchConfig.map_id = previous


## `MatchLauncher.start_local`/`configure_local` sont des fonctions statiques
## (rien à espionner) : on vérifie ici le canal qu'ils lisent réellement --
## `MatchConfig.map_id` -- déjà posé par `_on_map_selected`/`_on_mode_selected`
## AVANT tout lancement, même mécanisme que mode_id/team_size/bot_difficulty
## (voir MatchModeCatalog.params_for + MatchLauncher.configure_local).
func test_mode_card_selection_forwards_the_currently_selected_map_id() -> void:
	var h := _home()
	var previous_map := MatchConfig.map_id
	var previous_mode := MatchConfig.mode_id
	h._on_map_selected("shipment")
	h._on_mode_selected(MatchModeCatalog.TDM)
	assert_str(MatchConfig.map_id).is_equal("shipment")
	assert_str(MatchConfig.mode_id).is_equal("tdm")
	MatchConfig.map_id = previous_map
	MatchConfig.set_mode(previous_mode)


func test_map_tickets_are_at_least_44px_tall() -> void:
	var h := _home()
	for id in h._map_tickets:
		var btn: Button = h._map_tickets[id]
		assert_float(btn.custom_minimum_size.y).append_failure_message(
			"ticket de carte '%s' sous la cible tactile de 44px" % id
		).is_greater_equal(44.0)
