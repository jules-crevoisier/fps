## test_buy_menu.gd
## Spec UX-05 (docs/research/04_ui_ux.md §2.5/§3.3, tâche UX-05 — « Menu
## d'achat rapide ») : grille catégories × armes (5 groupes adressables au
## clavier, WeaponConfig.Category regroupé en CATEGORY_GROUPS) ; achat en 2
## touches façon CS2 — « B » ouvre, un chiffre 1–5 choisit la catégorie, un
## second chiffre 1–5 achète l'arme (« B → 3 → 2 » achète la 2e arme de la 3e
## catégorie, Fusils/Ravage) — un achat complet en ≤ 3 événements d'entrée
## (simulés via un vrai gdUnit4 scene_runner, comme demandé par le critère) ;
## « R » rachète le loadout de la manche précédente si les crédits suffisent,
## sinon avertit avec la raison ; toute la grille reste navigable à la
## manette (boutons focus_mode ALL, focus géométrique standard de Godot).
##
## Revente (titre de la tâche) : PAS testée ici, PAS implémentée dans
## BuyMenu.gd — elle demanderait une RPC de remboursement côté Weapon.gd
## (hors de la liste de fichiers de cette tâche). Voir le rendu de fin de
## tâche.
##
## Instances RÉELLES (comme tests/player/test_respawn_state_reset.gd) : un
## joueur BOT (autorité SERVEUR sans la branche "humain local", voir
## PlayerController._enter_tree) sert de "Weapon" local — placé manuellement
## dans le groupe "local_player" que `BuyMenu._local_weapon()` interroge (le
## flag bot ne fait QUE éviter la capture souris/caméra, il ne dispense pas
## de ce groupe). Un `FakeEconomyMode` (Node minimal exposant `buy_phase` et
## `my_credits`, groupe "game_mode") tient lieu de SnDMode pour les scénarios
## à économie, sans dépendre de SnDMode.gd (hors de la liste de fichiers de
## cette tâche).
extends GdUnitTestSuite

const BUY_MENU_SCRIPT := preload("res://scripts/ui/BuyMenu.gd")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

## Mode de jeu à économie minimal (voir SnDMode.my_credits/buy_phase, lues
## par BuyMenu via le groupe "game_mode" — BuyMenu ne connaît QUE ces deux
## champs, jamais SnDMode lui-même).
class FakeEconomyMode extends Node:
	var buy_phase: bool = true
	var my_credits: int = 0

var _next_offset_index := 0

## Isolation entre suites (BUG-33) : deux fuites d'état STATIQUE/GLOBAL,
## invisibles quand ce fichier tourne SEUL (voir tools/test.sh
## res://tests/ui/test_buy_menu.gd), qui ne se révèlent que lorsque TOUT
## tests/ui s'enchaîne dans le MÊME processus gdUnit4 :
##  1. `multiplayer.multiplayer_peer` (SceneTree, processus entier) : une
##     suite voisine (ex. tests/ui/test_end_screens_v4.gd, tests/ui/
##     test_team_relative.gd, même précaution qu'ici) peut le laisser à
##     `null` après son propre `after_test()` -- ou l'avoir toujours laissé
##     `null` si elle ne le sauvegarde pas. Un pair `null` (au lieu du
##     `OfflineMultiplayerPeer` par défaut de Godot, voir la docstring de
##     `GameMode._is_authoritative`) fait échouer `multiplayer.
##     get_unique_id()` (Godot journalise "No multiplayer peer is assigned")
##     et donc `player.is_multiplayer_authority()` -- exactement la garde
##     d'entrée de `Weapon.buy()`. Conséquence observée SANS ce correctif :
##     `weapon.buy(id)` n'a plus aucun effet (le garde-fou renvoie tôt), donc
##     `rebuy_restores_the_previous_rounds_loadout_after_dying_down_to_the_pistol`
##     et `rebuy_shows_a_warning_with_the_missing_amount_when_credits_are_short`
##     échouent seulement en suite complète -- jamais seuls.
##  2. `Weapon.recent_gunfire`/`Weapon.recent_impacts` (bus statiques serveur,
##     BOT-03) : voir `Weapon.reset_buses()`, tests/combat/
##     test_weapon_static_buses.gd. Aucun test de CE fichier ne les lit
##     encore, mais une future suite qui ferait tirer/toucher un bot réel
##     (`_local_bot_player()` a un vrai `BotBrain` actif, voir sa docstring)
##     hériterait sinon d'entrées "récentes" laissées par une suite
##     PRÉCÉDENTE du même run -- remis à zéro ici par précaution symétrique.
var _saved_multiplayer_peer: MultiplayerPeer

func before_test() -> void:
	_saved_multiplayer_peer = multiplayer.multiplayer_peer
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Weapon.reset_buses()

func after_test() -> void:
	multiplayer.multiplayer_peer = _saved_multiplayer_peer
	Weapon.reset_buses()


func _menu() -> CanvasLayer:
	var m: CanvasLayer = BUY_MENU_SCRIPT.new()
	add_child(m)
	auto_free(m)
	return m


## Joueur BOT réel (autorité serveur, voir la note d'en-tête), forcé dans le
## groupe "local_player" pour devenir la cible de `BuyMenu._local_weapon()`.
func _local_bot_player() -> PlayerController:
	var player: PlayerController = PLAYER_SCENE.instantiate()
	_next_offset_index += 1
	player.name = str(PlayerController.BOT_ID_START + _next_offset_index)
	player.set("is_bot", true)
	player.position = Vector3(float(_next_offset_index) * 60.0, 0.0, 0.0)
	player.set("spawn_point", player.position)
	player.add_to_group("local_player")
	add_child(player)
	auto_free(player)
	return player


func _economy_mode(credits: int, buy_phase: bool) -> FakeEconomyMode:
	var m := FakeEconomyMode.new()
	m.my_credits = credits
	m.buy_phase = buy_phase
	m.add_to_group("game_mode")
	add_child(m)
	auto_free(m)
	return m


# ================================================ Grille catégories × armes

func test_grouped_categories_has_five_groups_covering_the_whole_database() -> void:
	var menu := _menu()
	var groups: Array = menu._grouped_categories()

	assert_int(groups.size()).append_failure_message(
		"la grille catégories × armes doit tenir sur 5 touches (1–5), comme CS2 (docs/research/04_ui_ux.md §2.5)"
	).is_equal(5)

	var total := 0
	for g in groups:
		total += (g.weapons as Array).size()
	assert_int(total).append_failure_message(
		"chaque arme du catalogue doit apparaître dans exactement une catégorie de la grille"
	).is_equal(WeaponDatabase.all().size())


func test_third_category_is_rifles_with_ravage_as_its_second_weapon() -> void:
	# Base du critère « B → 3 → 2 achète la 2e arme de la 3e catégorie » :
	# fixe qui est cette arme AVANT le test d'entrée simulée plus bas.
	var menu := _menu()
	var groups: Array = menu._grouped_categories()

	var rifles: Dictionary = groups[2]
	assert_str(str(rifles.label)).is_equal("Fusils")
	var weapons: Array = rifles.weapons
	assert_int(weapons.size()).append_failure_message(
		"le critère UX-05 (3 → 2) suppose au moins 2 armes dans la 3e catégorie"
	).is_greater_equal(2)
	assert_str((weapons[1] as WeaponConfig).weapon_name).is_equal("Ravage")


func test_every_weapon_button_is_focusable_for_gamepad_navigation() -> void:
	var menu := _menu()

	assert_int(menu._categories.size()).is_greater(0)
	for cat in menu._categories:
		for entry in (cat as Dictionary).entries:
			assert_int((entry as Dictionary).button.focus_mode).append_failure_message(
				"chaque plaque d'arme doit être focusable (D-pad/stick + bouton A à la manette)"
			).is_equal(Control.FOCUS_ALL)


# ================================================ Achat en 2 touches (scene-runner)

func test_b_then_3_then_2_buys_and_equips_the_second_weapon_of_the_third_category() -> void:
	var player := _local_bot_player()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var weapon: Weapon = player.get_node("Weapon")

	var menu := BUY_MENU_SCRIPT.new()
	auto_free(menu)
	var runner := scene_runner(menu)

	# Achat COMPLET en 3 événements d'entrée (critère UX-05) : « B » ouvre,
	# « 3 » choisit Fusils (3e catégorie), « 2 » achète sa 2e arme (Ravage).
	runner.simulate_key_pressed(KEY_B)
	await runner.await_input_processed()
	runner.simulate_key_pressed(KEY_3)
	await runner.await_input_processed()
	runner.simulate_key_pressed(KEY_2)
	await runner.await_input_processed()

	assert_object(weapon.cfg()).append_failure_message(
		"« B → 3 → 2 » (3 entrées) doit acheter ET équiper Ravage — 2e arme de Fusils, la 3e catégorie"
	).is_equal(WeaponDatabase.get_by_name("Ravage"))


# La navigation manette RÉELLE (ui_up/down/left/right déplaçant le focus) et
# `Viewport.gui_get_focus_owner()` dépendent du sous-système GUI de la
# Viewport, que le GdUnitCmdTool prévient explicitement ne PAS fonctionner en
# mode headless (bannière affichée à chaque run : « tests that use UI
# interaction do not work correctly in headless mode ») — confirmé
# empiriquement ici (`grab_focus()` n'aboutit à rien d'observable). Le seul
# pré-requis de navigabilité manette vérifiable headless est structurel :
# chaque plaque est un VRAI Button focusable dans une grille de Container
# réels (test_every_weapon_button_is_focusable_for_gamepad_navigation
# ci-dessus) — Godot résout ensuite la navigation géométrique lui-même, comme
# pour tout autre menu du dépôt (aucun voisin codé en dur nulle part). La
# vérification EN JEU se fait à l'écran (tools/review/ui_shots.gd, checklist
# docs/STYLE_BIBLE.md), pas ici.


# ================================================ « R » — racheter le loadout précédent

func test_afford_check_is_ok_when_credits_cover_the_total_cost() -> void:
	var menu := _menu()
	var ravage := WeaponDatabase.get_by_name("Ravage")
	var pistolet := WeaponDatabase.get_by_name("Pistolet")
	var ids := [WeaponDatabase.id_of(ravage), WeaponDatabase.id_of(pistolet)]

	var check: Dictionary = menu._afford_check(ids, true, ravage.cost + pistolet.cost)

	assert_bool(check.ok).is_true()
	assert_int(check.missing).is_equal(0)


func test_afford_check_reports_the_exact_missing_amount() -> void:
	var menu := _menu()
	var faucheur := WeaponDatabase.get_by_name("Faucheur")  # sniper, le plus cher du catalogue (4600 cr).
	var ids := [WeaponDatabase.id_of(faucheur)]

	var check: Dictionary = menu._afford_check(ids, true, faucheur.cost - 500)

	assert_bool(check.ok).append_failure_message(
		"500 crédits manquants ne doivent jamais être arrondis à « abordable »"
	).is_false()
	assert_int(check.missing).is_equal(500)


func test_afford_check_is_always_ok_without_economy() -> void:
	var menu := _menu()

	var check: Dictionary = menu._afford_check([0, 1, 2], false, 0)

	assert_bool(check.ok).append_failure_message(
		"sans économie (entraînement / mode imposé) l'achat reste libre — pas de crédits à vérifier"
	).is_true()


func test_rebuy_without_a_previous_round_warns_and_buys_nothing() -> void:
	var player := _local_bot_player()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var weapon: Weapon = player.get_node("Weapon")
	var starting_ids := weapon.weapons.map(func(w): return WeaponDatabase.id_of(w) if w else -1)

	_economy_mode(9999, true)
	var menu := _menu()
	menu._try_open()

	menu._rebuy_previous_loadout()

	var current_ids := weapon.weapons.map(func(w): return WeaponDatabase.id_of(w) if w else -1)
	assert_array(current_ids).append_failure_message(
		"sans manche précédente mémorisée, « R » ne doit rien acheter"
	).is_equal(starting_ids)
	assert_str(menu._locked_label.text).is_equal("⚠ Aucun loadout de manche précédente")
	assert_bool(menu._locked_label.visible).is_true()


func test_rebuy_is_a_no_op_notice_when_the_loadout_is_already_owned() -> void:
	var player := _local_bot_player()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var weapon: Weapon = player.get_node("Weapon")

	var mode := _economy_mode(9999, true)
	var menu := _menu()
	menu._process(0.0)      # accroche `_mode` (get_first_node_in_group("game_mode")).
	mode.buy_phase = false
	menu._process(0.0)      # transition vrai -> faux : mémorise le loadout de départ.
	mode.buy_phase = true
	menu._process(0.0)
	menu._try_open()

	menu._rebuy_previous_loadout()

	assert_str(menu._locked_label.text).append_failure_message(
		"le loadout de départ est déjà celui de la manche précédente : rien à racheter, mais un message doit le dire"
	).is_equal("Loadout déjà possédé")


func test_rebuy_restores_the_previous_rounds_loadout_after_dying_down_to_the_pistol() -> void:
	var player := _local_bot_player()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var weapon: Weapon = player.get_node("Weapon")
	var faucheur := WeaponDatabase.get_by_name("Faucheur")
	var pistolet := WeaponDatabase.get_by_name("Pistolet")

	var mode := _economy_mode(9999, true)
	var menu := _menu()
	menu._process(0.0)

	# Manche 1 : achète le Faucheur (remplace le fusil de départ) ; la manche
	# se termine (buy_phase se referme) — ce loadout devient "la manche
	# précédente" pour le rachat suivant.
	weapon.buy(WeaponDatabase.id_of(faucheur))
	mode.buy_phase = false
	menu._process(0.0)

	# Manche 2 : mort entre-temps -> reset au pistolet seul (SnDMode.
	# _after_round_respawn), crédits larges pour le rachat.
	weapon.server_set_loadout([WeaponDatabase.id_of(pistolet)])
	mode.buy_phase = true
	menu._process(0.0)
	menu._try_open()

	menu._rebuy_previous_loadout()

	var owned_now: Array = weapon.weapons.map(func(w): return WeaponDatabase.id_of(w) if w else -1)
	assert_array(owned_now).append_failure_message(
		"« R » doit rendre exactement le Faucheur perdu à la mort (le pistolet était déjà là)"
	).contains([WeaponDatabase.id_of(faucheur)])


func test_rebuy_shows_a_warning_with_the_missing_amount_when_credits_are_short() -> void:
	var player := _local_bot_player()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var weapon: Weapon = player.get_node("Weapon")
	var faucheur := WeaponDatabase.get_by_name("Faucheur")
	var pistolet := WeaponDatabase.get_by_name("Pistolet")

	var mode := _economy_mode(9999, true)
	var menu := _menu()
	menu._process(0.0)

	weapon.buy(WeaponDatabase.id_of(faucheur))
	mode.buy_phase = false
	menu._process(0.0)

	weapon.server_set_loadout([WeaponDatabase.id_of(pistolet)])
	mode.my_credits = 200  # trop peu pour le Faucheur manquant (4600 cr).
	mode.buy_phase = true
	menu._process(0.0)
	menu._try_open()

	menu._rebuy_previous_loadout()

	var owned_now: Array = weapon.weapons.map(func(w): return WeaponDatabase.id_of(w) if w else -1)
	assert_array(owned_now).append_failure_message(
		"crédits insuffisants (200 < 4600) : le Faucheur ne doit PAS être racheté"
	).not_contains([WeaponDatabase.id_of(faucheur)])
	assert_str(menu._locked_label.text).append_failure_message(
		"crédits insuffisants : l'avertissement doit donner la raison (montant manquant)"
	).is_equal("⚠ Crédits insuffisants — manque %s" % HudFormat.format_credits(faucheur.cost - 200))


# ================================================ UX-35 — « UI v4 BL3 » (docs/UI_DIRECTION_BL3.md
# §6 « Achat / arsenal », direction VALIDÉE 2026-09-25) : cartes 240×150,
# onglets 1–5, CTA « ACHETER » jaune, « Gratuit » une seule fois. Ajoutées à
# cette tâche (POSSÉDÉE par UX-35) SANS toucher aux tests ci-dessus
# (verrouillés par ART-34/UX-05) — voir la note de tête de fichier BuyMenu.gd.

func test_weapon_cards_are_240_by_150() -> void:
	var menu := _menu()
	assert_int(menu._categories.size()).is_greater(0)
	var first_entry: Dictionary = (menu._categories[0] as Dictionary).entries[0]
	var card: KitCard = first_entry.button
	assert_that(card.custom_minimum_size).append_failure_message(
		"UI_DIRECTION_BL3.md §6 : cartes d'armes à coins coupés 240×150"
	).is_equal(Vector2(240.0, 150.0))


func test_tabs_are_numbered_one_to_five() -> void:
	var menu := _menu()
	var groups: Array = menu._grouped_categories()
	assert_int(menu._tab_bars.size()).is_equal(groups.size())
	for i in menu._tab_bars.size():
		var tab: KitSlantBar = menu._tab_bars[i]
		assert_str(tab.bar_text).append_failure_message(
			"UI_DIRECTION_BL3.md §6 : onglets 1 à 5"
		).starts_with("%d — " % (i + 1))


func test_the_active_tab_is_signal_yellow_and_the_others_stay_plate() -> void:
	var menu := _menu()
	assert_that((menu._tab_bars[0] as KitSlantBar).accent_color).append_failure_message(
		"l'onglet ACTIF (catégorie 0 par défaut) doit être en fond signal (§4.6 « choisi : fond signal »)"
	).is_equal(Comic.signal_color())
	if menu._tab_bars.size() > 1:
		assert_that((menu._tab_bars[1] as KitSlantBar).accent_color).append_failure_message(
			"un onglet INACTIF doit rester en plate_hi, jamais signal"
		).is_equal(Comic.plate_hi_color())


func test_buy_cta_is_signal_yellow() -> void:
	var menu := _menu()
	assert_that(menu._detail_cta.accent_color).append_failure_message(
		"UI_DIRECTION_BL3.md §6 : CTA « ACHETER » jaune"
	).is_equal(Comic.signal_color())


func test_free_weapon_price_appears_only_once_on_screen() -> void:
	var menu := _menu()
	var pistolet := WeaponDatabase.get_by_name("Pistolet")
	assert_int(pistolet.cost).append_failure_message(
		"ce test suppose le Pistolet comme UNIQUE arme à coût nul du catalogue"
	).is_equal(0)

	menu._show_detail(pistolet)
	assert_str(menu._detail_price.text).append_failure_message(
		"UI_DIRECTION_BL3.md §6 : « Gratuit » une seule fois — la carte le porte déjà, le panneau de détail ne doit pas le répéter"
	).is_empty()

	menu._refresh_labels()
	var found := false
	for cat in menu._categories:
		for entry in ((cat as Dictionary).entries as Array):
			if (entry as Dictionary).weapon == pistolet:
				found = true
				assert_str((entry as Dictionary).price_label.text).append_failure_message(
					"la carte du Pistolet doit afficher « Gratuit » (seule occurrence du mot pour cette arme)"
				).is_equal("Gratuit")
	assert_bool(found).append_failure_message("le Pistolet doit apparaître dans une catégorie de la grille").is_true()
