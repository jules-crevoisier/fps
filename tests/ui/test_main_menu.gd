## test_main_menu.gd
## Spec UX-08 (docs/research/04_ui_ux.md §5, tâche UX-08 — « Menu principal en
## 1 clic ») : le bouton « JOUER » a le focus au démarrage et lance une partie
## en 1 activation (dernier mode/carte/bots/difficulté mémorisés, ou Arène vs
## bots au premier lancement) ; le champ IP et « Rejoindre » — ainsi que le
## sélecteur de mode/carte — n'apparaissent que dans le panneau replié
## « Partie personnalisée » ; le dernier mode/la dernière carte/la difficulté
## sont mémorisés (MatchConfig.save_last()/load_last(), `user://match_config.
## cfg`) ; les états chargement (> 1 s), vide et erreur + Réessayer existent.
##
## Instance RÉELLE de MainMenu.gd (comme tests/agents/test_round_props_
## cleanup.gd instancie player.tscn) : `_ready()` ne fait AUCUN appel réseau
## réel (NetworkManager.get_net().disconnect_from_game() est un no-op sans
## pair), donc sûr en headless. En revanche `_on_host()`/`_net.join()`
## lieraient un VRAI port ENet — jamais appelés ici (même règle que
## test_round_props_cleanup.gd vis-à-vis de GameWorld._ready()) : les états
## réseau sont exercés via les méthodes privées qu'ils délèguent
## (_show_error/_show_empty/_process), exactement comme d'autres suites du
## dépôt appellent directement des méthodes préfixées `_` (ex.
## tests/ai/test_bot_goals.gd::_compute_bot_goal).
extends GdUnitTestSuite

const MAIN_MENU_SCRIPT := preload("res://scripts/ui/MainMenu.gd")
const PAUSE_MENU_SCRIPT := preload("res://scripts/ui/PauseMenu.gd")

var _saved_mode_id: String
var _saved_map_id: String
var _saved_bots_enabled: bool
var _saved_bot_difficulty: int
var _saved_team_size: int


func before_test() -> void:
	# MatchConfig est statique (survit au changement de scène, voir son
	# commentaire d'en-tête) : sauvegarder/restaurer évite qu'un test qui le
	# modifie n'en pollue un autre de cette suite ou d'une suite voisine
	# (même patron que tests/networking/test_match_config_sync.gd). Le
	# fichier `user://match_config.cfg` est en plus effacé pour rejouer,
	# quand un test le demande, le scénario « premier lancement ».
	_saved_mode_id = MatchConfig.mode_id
	_saved_map_id = MatchConfig.map_id
	_saved_bots_enabled = MatchConfig.bots_enabled
	_saved_bot_difficulty = MatchConfig.bot_difficulty
	_saved_team_size = MatchConfig.team_size
	MatchConfig._debug_clear()


func after_test() -> void:
	MatchConfig.mode_id = _saved_mode_id
	MatchConfig.map_id = _saved_map_id
	MatchConfig.bots_enabled = _saved_bots_enabled
	MatchConfig.bot_difficulty = _saved_bot_difficulty
	MatchConfig.team_size = _saved_team_size
	MatchConfig._debug_clear()


## Instance réelle du menu, montée dans l'arbre (comme _bot_player() dans
## test_respawn_state_reset.gd). `_ready()` construit tout le décor 3D et
## l'UI de façon synchrone (add_child n'est pas différé ici) ; un `await`
## laisse quand même le temps à `call_deferred("_focus_play")` de s'exécuter
## pour les tests qui n'appellent pas `_focus_play()` eux-mêmes.
func _menu() -> Node3D:
	var m: Node3D = MAIN_MENU_SCRIPT.new()
	add_child(m)
	auto_free(m)
	return m


# ================================================ Premier lancement (Arène vs bots)

func test_first_launch_defaults_to_tdm_arena_with_bots() -> void:
	# Fichier `user://match_config.cfg` absent (before_test vient de
	# l'effacer) = premier lancement (docs/research/04_ui_ux.md #153 :
	# « Jouer lance ... Arène vs bots au premier lancement »).
	var menu := _menu()
	await get_tree().process_frame

	assert_str(menu._mode_id).append_failure_message(
		"premier lancement : le mode par défaut doit être l'Arène (tdm)"
	).is_equal("tdm")
	assert_bool(MatchConfig.bots_enabled).append_failure_message(
		"premier lancement : les bots doivent être activés par défaut"
	).is_true()


# ================================================ 1 clic : focus + lancement

func test_play_button_has_focus_at_startup() -> void:
	var menu := _menu()
	menu._focus_play()

	assert_bool(menu._host_btn.has_focus()).append_failure_message(
		"le bouton JOUER doit avoir le focus au démarrage — 1 activation (clic/Entrée/A manette) doit suffire"
	).is_true()


func test_play_button_label_carries_no_hosting_or_ip_jargon() -> void:
	# Retour research (#5) : « JOUER (héberger) » + IP au premier niveau « ça
	# fait prototype ». Le CTA principal reste un verbe d'action simple.
	var menu := _menu()

	assert_str(menu._host_btn.text).is_equal("▶  JOUER")


func test_apply_match_config_syncs_the_selected_mode_and_map_before_launch() -> void:
	# _on_host()/_on_join() appellent _apply_match_config() avant de lancer —
	# vérifié ici sans jamais appeler _on_host() (lierait un vrai port ENet,
	# voir la note d'en-tête).
	var menu := _menu()

	menu._select_mode("hardpoint")
	menu._select_map({
		"id": "col_du_vautour", "name": "Col du Vautour",
		"scene": "res://scenes/levels/maps/col_du_vautour.tscn",
	})
	menu._apply_match_config()

	assert_str(MatchConfig.mode_id).is_equal("hardpoint")
	assert_str(MatchConfig.map_id).is_equal("col_du_vautour")


func test_resolve_start_scene_uses_the_selected_maps_scene() -> void:
	var menu := _menu()

	menu._select_map({
		"id": "wasteland", "name": "Wasteland",
		"scene": "res://scenes/levels/maps/wasteland.tscn",
	})

	assert_str(menu._resolve_start_scene()).is_equal("res://scenes/levels/maps/wasteland.tscn")


# ================================================ « Partie personnalisée » repliée

func test_custom_panel_is_collapsed_by_default() -> void:
	var menu := _menu()

	assert_bool(menu._custom_panel.visible).append_failure_message(
		"le panneau « Partie personnalisée » doit rester replié par défaut (1 clic = pas de menu à traverser)"
	).is_false()


func test_ip_field_and_join_button_only_appear_inside_custom_game() -> void:
	var menu := _menu()

	assert_bool(menu._ip_field.is_visible_in_tree()).append_failure_message(
		"le champ IP ne doit apparaître que dans « Partie personnalisée »"
	).is_false()
	assert_bool(menu._join_btn.is_visible_in_tree()).append_failure_message(
		"« Rejoindre » ne doit apparaître que dans « Partie personnalisée »"
	).is_false()

	menu._on_toggle_custom()

	assert_bool(menu._custom_panel.visible).is_true()
	assert_bool(menu._ip_field.is_visible_in_tree()).append_failure_message(
		"le champ IP doit apparaître une fois « Partie personnalisée » ouverte"
	).is_true()
	assert_bool(menu._join_btn.is_visible_in_tree()).append_failure_message(
		"« Rejoindre » doit apparaître une fois « Partie personnalisée » ouverte"
	).is_true()


func test_toggling_custom_game_twice_closes_it_again() -> void:
	var menu := _menu()

	menu._on_toggle_custom()
	menu._on_toggle_custom()

	assert_bool(menu._custom_panel.visible).is_false()
	assert_bool(menu._ip_field.is_visible_in_tree()).is_false()


func test_mode_and_map_selectors_live_inside_custom_game_too() -> void:
	# Le sélecteur de mode/carte fait partie de la personnalisation, pas du
	# chemin 1 clic par défaut (docs/research/04_ui_ux.md #5).
	var menu := _menu()

	assert_bool(menu._custom_panel.is_ancestor_of(menu._map_list)).is_true()
	for c in menu._mode_cards:
		assert_bool(menu._custom_panel.is_ancestor_of(c.button)).append_failure_message(
			"le sélecteur de mode doit vivre dans « Partie personnalisée »"
		).is_true()


# ================================================ Mémorisation (mode/carte/difficulté)

func test_selecting_a_mode_and_map_persists_to_disk() -> void:
	var menu := _menu()

	menu._select_mode("snd")
	menu._select_map({
		"id": "cargo_ship", "name": "Cargo Ship",
		"scene": "res://scenes/levels/maps/cargo_ship.tscn",
	})
	menu._on_difficulty(MatchConfig.Difficulty.ELITE)

	# Simule un redémarrage de l'appli : l'état en mémoire est remis aux
	# défauts déclarés dans MatchConfig.gd, puis rechargé depuis le disque
	# exactement comme MainMenu._ready() le fait au lancement suivant.
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = ""
	MatchConfig.bot_difficulty = MatchConfig.Difficulty.RECRUE
	MatchConfig.load_last()

	assert_str(MatchConfig.mode_id).append_failure_message(
		"le dernier mode joué (snd) doit survivre à un redémarrage"
	).is_equal("snd")
	assert_str(MatchConfig.map_id).append_failure_message(
		"la dernière carte jouée (cargo_ship) doit survivre à un redémarrage"
	).is_equal("cargo_ship")
	assert_int(MatchConfig.bot_difficulty).append_failure_message(
		"la dernière difficulté choisie (Élite) doit survivre à un redémarrage"
	).is_equal(MatchConfig.Difficulty.ELITE)


func test_a_freshly_opened_menu_reloads_the_last_saved_configuration() -> void:
	# Bout en bout : une première session sauvegarde, une NOUVELLE instance de
	# MainMenu (= prochain lancement) doit repartir directement dessus.
	MatchConfig.set_mode("duel")
	MatchConfig.map_id = "la_fosse"
	MatchConfig.bots_enabled = false
	MatchConfig.bot_difficulty = MatchConfig.Difficulty.ELITE
	MatchConfig.save_last()

	var menu := _menu()

	assert_str(menu._mode_id).is_equal("duel")
	assert_str(str(menu._map_choice.get("id", ""))).is_equal("la_fosse")
	assert_bool(MatchConfig.bots_enabled).is_false()
	assert_int(MatchConfig.bot_difficulty).is_equal(MatchConfig.Difficulty.ELITE)


func test_refresh_maps_restores_the_remembered_map_when_returning_to_a_mode() -> void:
	# UX-37 (proto une seule carte) : tdm/hardpoint/snd sont désormais bornés à
	# Wasteland seule dans le menu (MapCatalog.proto_single_map, voir
	# MainMenu._maps_for_mode()) — un seul choix ne permet plus de distinguer
	# « la carte mémorisée » de « la première ». Duel/Duo restent, eux, à
	# plusieurs cartes (bypass_proto_filter explicite dans _maps_for_mode(),
	# La Fosse/Le Belvédère) : mode de fixture qui garde ce test significatif
	# sans affaiblir son assertion (toujours « > 1 carte », toujours le même
	# scénario aller-retour + mémorisation).
	var menu := _menu()

	menu._select_mode("duel")
	var duel_maps: Array = menu._maps_for_mode()
	assert_int(duel_maps.size()).append_failure_message(
		"ce test suppose au moins 2 cartes duel dans MapCatalog pour distinguer « la remembered » de « la première »"
	).is_greater(1)
	var target_id: String = str(duel_maps[1].get("id", ""))
	menu._select_map(duel_maps[1])

	menu._select_mode("duo")  # reconstruit la grille sur un autre mode.
	menu._select_mode("duel")  # revient : doit retrouver `target_id`, pas la 1ère carte.

	assert_str(MatchConfig.map_id).append_failure_message(
		"de retour sur duel, la carte mémorisée (%s) doit rester sélectionnée" % target_id
	).is_equal(target_id)
	assert_str(str(menu._map_choice.get("id", ""))).is_equal(target_id)


func test_toggling_bots_persists_immediately() -> void:
	var menu := _menu()

	menu._on_bots_toggled(false)
	MatchConfig.bots_enabled = true  # remis en mémoire pour prouver que load_last() relit bien le disque.
	MatchConfig.load_last()

	assert_bool(MatchConfig.bots_enabled).is_false()


# ================================================ États : chargement / vide / erreur

func test_loading_state_appears_only_after_one_second() -> void:
	var menu := _menu()
	menu._status_label.text = "avant"

	# < 1 s écoulée : le texte de connexion ne doit pas encore apparaître.
	menu._loading_t = 0.4
	menu._process(0.3)
	assert_str(menu._status_label.text).append_failure_message(
		"avant 1 s de chargement, le libellé de connexion ne doit pas encore s'afficher"
	).is_equal("avant")

	# > 1 s écoulée : le libellé de connexion doit s'afficher avec la durée.
	menu._process(0.5)
	assert_str(menu._status_label.text).append_failure_message(
		"au-delà de 1 s de chargement, le menu doit afficher la durée écoulée"
	).is_equal("Connexion au serveur… 1 s")


func test_join_with_an_empty_ip_shows_the_empty_state() -> void:
	# Chemin RÉEL de _on_join() — sûr : il retourne AVANT tout appel réseau
	# quand le champ IP est vide (voir sa doc).
	var menu := _menu()
	menu._ip_field.text = ""

	menu._on_join()

	assert_bool(menu._status.visible).is_true()
	assert_str(menu._status_label.text).is_equal("Aucune adresse — saisis une IP de serveur.")
	assert_bool(menu._retry_btn.visible).append_failure_message(
		"l'état vide n'a pas de bouton Réessayer (il n'y a rien à réessayer, juste un champ à remplir)"
	).is_false()


func test_show_error_displays_the_message_and_a_retry_button() -> void:
	var menu := _menu()

	menu._show_error("Échec de l'hébergement.", menu._on_host)

	assert_str(menu._status_label.text).is_equal("⚠ ÉCHEC — Échec de l'hébergement.")
	assert_bool(menu._retry_btn.visible).append_failure_message(
		"une erreur avec une action de reprise valide doit afficher Réessayer"
	).is_true()


func test_show_error_without_a_retry_action_hides_the_retry_button() -> void:
	var menu := _menu()

	menu._show_error("Connexion échouée.")

	assert_bool(menu._retry_btn.visible).append_failure_message(
		"sans action de reprise fournie, Réessayer ne doit pas apparaître"
	).is_false()


# ================================================ UX-32 (UI v4 BL3 — menu principal + pause)
# docs/UI_DIRECTION_BL3.md §6 : pile de navigation JOUER/AGENTS/ARSENAL/
# OPTIONS/QUITTER à gauche, un seul pinceau jaune (KitSwash) à l'écran, et la
# carte courante rappelée en bas à gauche.

func test_quitter_entry_exists_and_is_reachable_by_keyboard_and_gamepad() -> void:
	# Garder toutes les entrées actuelles (contrat UX-32) : QUITTER était un
	# bouton séparé de la barre du haut en v3, il doit rester atteignable
	# dans la pile de navigation v4.
	var menu := _menu()

	assert_object(menu._quit_btn).append_failure_message(
		"QUITTER doit rester une entrée du menu (contrat UX-32 : garder toutes les entrées actuelles)"
	).is_not_null()
	assert_bool(menu._quit_btn.is_visible_in_tree()).is_true()
	assert_int(menu._quit_btn.focus_mode).append_failure_message(
		"QUITTER doit être atteignable au clavier ET à la manette (focus_mode ALL)"
	).is_equal(Control.FOCUS_ALL)


func test_only_one_swash_is_visible_at_a_time() -> void:
	# Critère d'acceptation : « un seul swash » (docs/UI_DIRECTION_BL3.md §4.5
	# « max_per_screen 1, sélection seulement ») — JOUER porte le seul
	# KitSwash de l'écran, au repos ET une fois « Partie personnalisée » ouverte
	# (ne doit rien ajouter).
	var menu := _menu()

	assert_int(_count_visible_swashes(menu)).append_failure_message(
		"un seul pinceau jaune (KitSwash) doit être visible sur le menu principal"
	).is_equal(1)

	menu._on_toggle_custom()

	assert_int(_count_visible_swashes(menu)).append_failure_message(
		"ouvrir « Partie personnalisée » ne doit pas faire apparaître un second pinceau jaune"
	).is_equal(1)


func _count_visible_swashes(node: Node) -> int:
	var count := 0
	if node is KitSwash and (node as CanvasItem).is_visible_in_tree():
		count += 1
	for c in node.get_children():
		count += _count_visible_swashes(c)
	return count


func test_current_map_plate_reflects_the_selected_map() -> void:
	# Carte courante rappelée en bas à gauche (docs/UI_DIRECTION_BL3.md §6) —
	# doit suivre `_select_map()`, jamais rester sur son texte initial.
	var menu := _menu()

	menu._select_map({
		"id": "wasteland", "name": "Wasteland",
		"description": "Relais pétrolier désertique, fin d'après-midi — asymétrique.",
		"scene": "res://scenes/levels/maps/wasteland.tscn",
	})

	assert_str(menu._map_plate_title.text).append_failure_message(
		"la plaque « carte courante » doit afficher la carte tout juste sélectionnée"
	).is_equal(menu._map_display_name(menu._map_choice))
	assert_str(menu._map_plate_desc.text).is_equal("Relais pétrolier désertique, fin d'après-midi — asymétrique.")


func test_all_current_menu_entries_stay_reachable_when_switching_tabs() -> void:
	# Garder toutes les entrées et raccourcis actuels : les raccourcis
	# menu_tab_next/menu_tab_prev doivent toujours faire cycler TAB_PLAY ->
	# AGENTS -> ARSENAL -> OPTIONS -> TAB_PLAY (inchangé depuis v3), et JOUER
	# doit redevenir focalisable en revenant sur TAB_PLAY.
	var menu := _menu()

	menu._show_tab(menu.TAB_AGENTS)
	assert_bool(menu._play_panel.visible).append_failure_message(
		"le chrome du menu principal (JOUER/AGENTS/ARSENAL/OPTIONS/QUITTER) doit se masquer pendant un écran embarqué"
	).is_false()

	menu._show_tab(menu.TAB_PLAY)
	assert_bool(menu._play_panel.visible).is_true()
	menu._focus_play()
	assert_bool(menu._host_btn.has_focus()).append_failure_message(
		"JOUER doit redevenir focalisable au retour sur l'onglet Play"
	).is_true()


# ================================================ UX-37 (retour lead 2026-09-25, §1 :
# « le fond doit être la VRAIE Wasteland » — remplace la rue procédurale
# codée à la main, voir la docstring d'en-tête de MainMenu.gd « UX-37 »).

func test_backdrop_uses_a_real_texture_from_assets_ui_menu() -> void:
	var menu := _menu()

	assert_object(menu._backdrop).append_failure_message(
		"le menu doit poser un fond peint (MeshInstance3D texturé) — plus de rue procédurale codée à la main"
	).is_not_null()
	var mat: StandardMaterial3D = menu._backdrop.material_override
	assert_object(mat).append_failure_message(
		"le fond doit porter un StandardMaterial3D avec la capture Wasteland"
	).is_not_null()
	assert_object(mat.albedo_texture).append_failure_message(
		"le fond doit charger une texture (la capture Wasteland), pas juste un aplat de couleur"
	).is_not_null()
	assert_str(mat.albedo_texture.resource_path).append_failure_message(
		"le fond doit être une capture rangée dans assets/ui/menu/ (retour lead : « la VRAIE Wasteland », pas un décor inventé)"
	).contains("assets/ui/menu/")


func test_backdrop_is_unshaded_and_double_sided() -> void:
	# Unshaded : la capture est déjà peinte/éclairée, jamais re-modulée par
	# les lumières du lobby. Double face (CULL_DISABLED) : filet de sécurité
	# si l'orientation du quad changeait un jour, jamais une face invisible.
	var menu := _menu()
	var mat: StandardMaterial3D = menu._backdrop.material_override

	assert_int(mat.shading_mode).is_equal(BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_int(mat.cull_mode).is_equal(BaseMaterial3D.CULL_DISABLED)


func test_backdrop_plane_is_behind_the_agent_showcase() -> void:
	# L'agent est posé à x=2.4 (voir _refresh_lobby_characters) devant la
	# caméra (z=7.6) : le fond doit rester loin derrière (z très négatif),
	# jamais devant/au milieu de la scène.
	var menu := _menu()

	assert_float(menu._backdrop.position.z).append_failure_message(
		"le fond doit rester loin DERRIÈRE l'agent affiché, jamais devant la caméra"
	).is_less(-10.0)


func test_sky_gradient_is_not_a_near_flat_band() -> void:
	# Retour vérificateur : « un ciel procédural qui bande visiblement » — le
	# haut et l'horizon du ciel doivent avoir un écart de clarté suffisant
	# pour qu'un vrai dégradé bleu s'affiche, pas un aplat quasi uniforme.
	var menu := _menu()

	assert_object(menu._environment).is_not_null()
	var sky_mat: ProceduralSkyMaterial = menu._environment.sky.sky_material
	assert_object(sky_mat).append_failure_message(
		"le ciel doit utiliser un ProceduralSkyMaterial"
	).is_not_null()
	var top: Color = sky_mat.sky_top_color
	var horizon: Color = sky_mat.sky_horizon_color
	assert_bool(top.is_equal_approx(horizon)).append_failure_message(
		"le haut et l'horizon du ciel sont quasi identiques (%s / %s) : le dégradé va bander" % [top, horizon]
	).is_false()
	assert_float(absf(top.v - horizon.v)).append_failure_message(
		"le ciel doit avoir un vrai écart de clarté entre le haut et l'horizon, pas un dégradé quasi plat"
	).is_greater(0.1)


func test_pause_stack_matches_the_66px_no_frame_dim_70_contract() -> void:
	# docs/UI_DIRECTION_BL3.md §6 « Pause : la pile du menu principal (66 px)
	# sur le jeu assombri à 70 %, sans cadre ».
	var pause: CanvasLayer = PAUSE_MENU_SCRIPT.new()
	add_child(pause)
	auto_free(pause)

	assert_float(pause._bg.color.a).append_failure_message(
		"le fond de pause doit assombrir le jeu à 70%% (alpha 0.70)"
	).is_equal_approx(0.70, 0.001)
	assert_object(pause._stack).is_not_null()
	assert_int(pause._stack.get_child_count()).append_failure_message(
		"la pause doit garder ses 3 entrées (Reprendre/Options/Quitter au menu)"
	).is_equal(3)
	for entry in pause._stack.get_children():
		assert_int(entry.get_theme_font_size("font_size")).append_failure_message(
			"chaque entrée de la pile de pause doit être en 66 px (direction v4 §6)"
		).is_equal(Comic.SIZE_66)
		var normal_style: StyleBox = entry.get_theme_stylebox("normal")
		assert_bool(normal_style is StyleBoxEmpty).append_failure_message(
			"la pile de pause ne doit porter aucun cadre au repos (« sans cadre »), trouvé %s" % normal_style.get_class()
		).is_true()
