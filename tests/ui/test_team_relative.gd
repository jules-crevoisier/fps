## test_team_relative.gd
## Spec UX-01 (docs/research/04_ui_ux.md §2.3/§4 #1/#9, tâche UX-01 — « HUD
## relatif au joueur local ») : `Comic.is_ally` (pure), puis chaque panneau du
## HUD recoloré/reformaté PAR RAPPORT à l'équipe locale — jamais l'indice
## d'équipe brut (l'ancien bug : « équipe 0 == Allié » codé en dur partout).
## Scénario directeur du contrat : un joueur local en ÉQUIPE 1 doit voir ses
## propres kills/son propre score en Allié, ceux de l'équipe 0 en Ennemi.
extends GdUnitTestSuite

const KILLFEED_SCRIPT := preload("res://scripts/ui/hud/KillfeedPanel.gd")
const SCORE_PANEL_SCRIPT := preload("res://scripts/ui/hud/ScorePanel.gd")
const ROUND_PANEL_SCRIPT := preload("res://scripts/ui/hud/RoundPanel.gd")
const SCOREBOARD_SCRIPT := preload("res://scripts/ui/hud/ScoreboardPanel.gd")
const END_PANEL_SCRIPT := preload("res://scripts/ui/hud/EndPanel.gd")
const GAME_HUD_SCRIPT := preload("res://scripts/ui/GameHUD.gd")
const KF_PLAYER_SCENE := preload("res://scenes/player/player.tscn")

## Pair multijoueur par défaut sauvegardé/restauré à CHAQUE test (même
## précaution que tests/modes/test_no_peer.gd) : les tests
## `test_record_kill_broadcasts_*` ci-dessous instancient un VRAI
## PlayerController (via `_kf_bot`), dont `is_local_human()`/
## `is_multiplayer_authority()` exige un pair assigné au SceneTree — or une
## suite VOISINE de ce même dossier (test_main_menu.gd, alphabétiquement
## avant) peut avoir laissé `multiplayer.multiplayer_peer` à `null`
## (NetworkManager.disconnect_from_game(), BUG-27 : remet à `null` au lieu
## d'un nouvel `OfflineMultiplayerPeer`, hors de mon périmètre d'écriture) —
## sans quoi Godot journalise "No multiplayer peer is assigned" et le
## spawn/respawn réseau échoue silencieusement. Restauré après CHAQUE test
## pour ne polluer NI cette suite NI une suite exécutée après elle dans le
## même process gdUnit4 (suite complète, `-a res://tests`).
var _saved_multiplayer_peer: MultiplayerPeer

func before_test() -> void:
	_saved_multiplayer_peer = multiplayer.multiplayer_peer
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func after_test() -> void:
	multiplayer.multiplayer_peer = _saved_multiplayer_peer

## Mode à manches minimal (voir RoundMode.alive_count) — RoundPanel ne
## connaît QUE cette méthode et l'éventuel champ `my_credits`, jamais
## RoundMode.gd lui-même (hors de la liste de fichiers de cette tâche).
class FakeRoundMode extends Node:
	func alive_count(team: int) -> int:
		return 4 if team == 0 else 2

## Mode à manches minimal AVEC crédits (suffixe optionnel de RoundPanel).
class FakeRoundModeWithCredits extends Node:
	var my_credits: int = 3900
	func alive_count(_team: int) -> int:
		return 1

## Substitut de GameWorld (Scoreboard/EndPanel ne lisent que `player_info`,
## jamais GameWorld.gd lui-même, hors de la liste de fichiers de cette tâche).
class FakeMatch extends Node:
	var player_info: Dictionary = {}


func _killfeed() -> KillfeedPanel:
	var kf: KillfeedPanel = KILLFEED_SCRIPT.new()
	add_child(kf)
	auto_free(kf)
	return kf

## L'entrée la plus récente est toujours déplacée en tête (KillfeedPanel.push,
## `move_child(panel, 0)`) : `body.get_child(0)` de ce panneau est la ligne
## (HBoxContainer) construite par `push` — killer/arme/headshot/flèche/victime.
func _kf_row(kf: KillfeedPanel) -> HBoxContainer:
	var panel: ComicPanel = kf.get_child(0)
	return panel.body.get_child(0)

func _score_panel() -> ScorePanel:
	var sp: ScorePanel = SCORE_PANEL_SCRIPT.new()
	add_child(sp)
	auto_free(sp)
	return sp

func _round_panel() -> RoundPanel:
	var rp: RoundPanel = ROUND_PANEL_SCRIPT.new()
	add_child(rp)
	auto_free(rp)
	return rp

func _scoreboard() -> ScoreboardPanel:
	var sb: ScoreboardPanel = SCOREBOARD_SCRIPT.new()
	add_child(sb)
	auto_free(sb)
	return sb

func _end_panel() -> EndPanel:
	var ep: EndPanel = END_PANEL_SCRIPT.new()
	add_child(ep)
	auto_free(ep)
	return ep

func _fake_match() -> FakeMatch:
	var m := FakeMatch.new()
	add_child(m)
	auto_free(m)
	return m


# ================================================ Comic.is_ally (pure)

func test_is_ally_true_when_team_matches_local_team() -> void:
	assert_bool(Comic.is_ally(0, 0)).is_true()
	assert_bool(Comic.is_ally(1, 1)).is_true()


func test_is_ally_false_when_team_differs_from_local_team() -> void:
	assert_bool(Comic.is_ally(1, 0)).is_false()
	assert_bool(Comic.is_ally(0, 1)).is_false()


func test_is_ally_is_relative_never_hardcoded_on_team_zero() -> void:
	# Le cœur du bug corrigé (docs/research/04_ui_ux.md §4 #1) : la même
	# équipe brute (1) est Ennemie pour un local en équipe 0, Alliée pour un
	# local en équipe 1 — jamais "équipe 0 == Allié" fixé en dur.
	assert_bool(Comic.is_ally(1, 0)).is_false()
	assert_bool(Comic.is_ally(1, 1)).is_true()


func test_is_ally_false_when_local_team_is_unknown() -> void:
	# Équipe locale non résolue (-1, ex. pas encore assignée par le serveur) :
	# personne n'est considéré allié — jamais une supposition sur l'équipe 0.
	assert_bool(Comic.is_ally(0, -1)).is_false()
	assert_bool(Comic.is_ally(1, -1)).is_false()


# ================================================ KillfeedPanel (local en équipe 1)

func test_killfeed_colors_team1_kill_as_ally_when_local_team_is_1() -> void:
	var kf := _killfeed()
	kf.push("Verrou", "BOT Renard", 1, 0, 1)

	var row := _kf_row(kf)
	var killer_label: Label = row.get_child(0)
	assert_str(killer_label.text).is_equal("● Verrou")
	assert_that(killer_label.get_theme_color("font_color")).is_equal(Comic.ALLY)


func test_killfeed_colors_team0_kill_as_enemy_when_local_team_is_1() -> void:
	var kf := _killfeed()
	kf.push("BOT Renard", "Verrou", 0, 1, 1)

	var row := _kf_row(kf)
	var killer_label: Label = row.get_child(0)
	assert_str(killer_label.text).is_equal("▼ BOT Renard")
	assert_that(killer_label.get_theme_color("font_color")).is_equal(Comic.enemy_color())


func test_killfeed_colors_victim_by_its_own_team_not_the_killers() -> void:
	var kf := _killfeed()
	# Tueur équipe 1 (Allié pour un local en équipe 1), victime équipe 0
	# (donc Ennemie) — la victime ne doit JAMAIS hériter de la couleur du
	# tueur (docs/research/04_ui_ux.md §2.3 "victime (couleur de SA propre
	# équipe)").
	kf.push("Verrou", "BOT Renard", 1, 0, 1)

	var row := _kf_row(kf)
	var victim_label: Label = row.get_child(4)
	assert_str(victim_label.text).is_equal("▼ BOT Renard")
	assert_that(victim_label.get_theme_color("font_color")).is_equal(Comic.enemy_color())


func test_killfeed_victim_is_neutral_when_its_team_is_unknown() -> void:
	var kf := _killfeed()
	# victim_team = -1 : jamais une équipe inventée pour la victime, jamais un
	# glyphe qu'on ne peut pas justifier.
	kf.push("Verrou", "Environnement", 1, -1, 1)

	var row := _kf_row(kf)
	var victim_label: Label = row.get_child(4)
	assert_str(victim_label.text).is_equal("Environnement")
	assert_that(victim_label.get_theme_color("font_color")).is_equal(Comic.TEXT_DIM)


func test_killfeed_entry_shows_weapon_tag_and_headshot_glyph() -> void:
	var kf := _killfeed()
	kf.push("Verrou", "BOT Renard", 1, 0, 1, true, "Ravage", true)

	var row := _kf_row(kf)
	var weapon_label: Label = row.get_child(1)
	var headshot_label: Label = row.get_child(2)
	assert_str(weapon_label.text).append_failure_message(
		"une entrée de killfeed doit porter l'icône de l'arme (ou de la capacité) — contrat UX-01"
	).is_equal("RAVAGE")
	assert_str(headshot_label.text).append_failure_message(
		"✦ doit marquer un headshot — contrat UX-01"
	).is_equal(KillfeedPanel.HEADSHOT_GLYPH)


func test_killfeed_entry_omits_weapon_tag_and_headshot_glyph_when_unknown() -> void:
	var kf := _killfeed()
	# Arme/headshot inconnus (kill d'un autre joueur, voir GameHUD._on_kill_logged)
	# : jamais un texte factice — les deux puces restent vides.
	kf.push("BOT Iris", "Verrou", 0, 1, 1)

	var row := _kf_row(kf)
	assert_str((row.get_child(1) as Label).text).is_equal("")
	assert_str((row.get_child(2) as Label).text).is_equal("")


func test_killfeed_local_entry_uses_a_heavier_ally_border() -> void:
	var kf := _killfeed()
	kf.push("Verrou", "BOT Renard", 1, 0, 1, true)

	var panel: ComicPanel = kf.get_child(0)
	assert_int(panel.border_width).is_equal(Comic.RULE_W_STRONG)
	assert_that(panel.border_color).is_equal(Comic.ALLY)


# ================================================ ScorePanel (local en équipe 1)

func test_score_panel_shows_ally_glyph_and_score_on_the_left_for_local_team_1() -> void:
	var sp := _score_panel()
	# Équipe 0 (adverse) : 7 ; équipe 1 (locale) : 5 — le score AFFICHÉ à
	# gauche doit être celui du joueur local (5), jamais team0 (7) par défaut.
	sp.update(7, 5, -1, "OBJECTIF", false, "1:42", 1)

	assert_str(sp._score_label.text).append_failure_message(
		"le score affiche ● à gauche pour l'équipe locale — contrat UX-01"
	).is_equal("● 5   1:42   7 ▼")
	assert_str(sp._objective_label.text).is_equal("OBJECTIF")


func test_score_panel_shows_victoire_when_local_team_wins() -> void:
	var sp := _score_panel()
	sp.update(5, 7, 1, "", false, "", 1)  # équipe 1 (locale) gagne.

	assert_str(sp._objective_label.text).append_failure_message(
		"la fin de match doit dire VICTOIRE pour le joueur local, jamais « ÉQ.%d GAGNE »"
	).is_equal("VICTOIRE")


func test_score_panel_shows_defaite_when_local_team_loses() -> void:
	var sp := _score_panel()
	sp.update(7, 5, 0, "", false, "", 1)  # équipe 0 gagne, le local est en équipe 1.

	assert_str(sp._objective_label.text).is_equal("DÉFAITE")


func test_score_panel_defaults_to_team_zero_when_local_team_unknown() -> void:
	var sp := _score_panel()
	sp.update(7, 5, -1, "OBJECTIF", false, "", -1)

	assert_str(sp._score_label.text).is_equal("● 7   —   5 ▼")


# ================================================ RoundPanel (local en équipe 1)

func test_round_panel_alive_counts_are_relative_to_local_team() -> void:
	var rp := _round_panel()
	var mode := FakeRoundMode.new()
	add_child(mode)
	auto_free(mode)

	rp.update_round(mode, 1)  # local en équipe 1 : alive_count(0)=4, alive_count(1)=2.

	assert_str(rp._extra_label.text).append_failure_message(
		"les vivants doivent être Alliés (locaux) d'abord, Ennemis ensuite — jamais équipe 0 — équipe 1 brut"
	).is_equal("VIVANTS  ● 2 — 4 ▼")


func test_round_panel_appends_credits_when_present() -> void:
	var rp := _round_panel()
	var mode := FakeRoundModeWithCredits.new()
	add_child(mode)
	auto_free(mode)

	rp.update_round(mode, 0)

	assert_str(rp._extra_label.text).is_equal("VIVANTS  ● 1 — 1 ▼    ·    %s" % HudFormat.format_credits(3900))


# ================================================ ScoreboardPanel (local en équipe 1)

func test_scoreboard_colors_local_team_as_ally_and_other_as_enemy() -> void:
	var sb := _scoreboard()
	var match_node := _fake_match()
	match_node.player_info = {
		1: {"name": "Verrou", "team": 1, "kills": 3, "deaths": 1, "is_bot": false},
		9001: {"name": "BOT Renard", "team": 0, "kills": 0, "deaths": 2, "is_bot": true},
	}

	sb.refresh(match_node, 1)

	var headers: Array = []
	for c in sb._list.get_children():
		var l := c as Label
		if l.text.begins_with("●") or l.text.begins_with("▼"):
			headers.append(l)
	assert_int(headers.size()).is_equal(2)
	assert_str((headers[0] as Label).text).is_equal("▼ ÉQUIPE 1")
	assert_that((headers[0] as Label).get_theme_color("font_color")).is_equal(Comic.enemy_color())
	assert_str((headers[1] as Label).text).is_equal("● ÉQUIPE 2")
	assert_that((headers[1] as Label).get_theme_color("font_color")).is_equal(Comic.ALLY)


# ================================================ EndPanel (local en équipe 1)

func test_end_panel_shows_victoire_and_ally_color_when_local_team_wins() -> void:
	var ep := _end_panel()
	var match_node := _fake_match()

	ep.show_result(1, 7, 5, match_node, 1)  # équipe 1 (locale) gagne.

	assert_str(ep._header.title).append_failure_message(
		"la page de fin affiche VICTOIRE si l'équipe locale gagne — contrat UX-01"
	).is_equal("Victoire")
	assert_that(ep._score_label.get_theme_color("font_color")).is_equal(Comic.ALLY)


func test_end_panel_shows_defaite_and_enemy_color_when_local_team_loses() -> void:
	var ep := _end_panel()
	var match_node := _fake_match()

	ep.show_result(0, 7, 5, match_node, 1)  # équipe 0 gagne, le local est en équipe 1.

	assert_str(ep._header.title).is_equal("Défaite")
	assert_that(ep._score_label.get_theme_color("font_color")).is_equal(Comic.enemy_color())


func test_end_panel_score_order_puts_local_team_first() -> void:
	var ep := _end_panel()
	var match_node := _fake_match()

	ep.show_result(0, 7, 5, match_node, 1)  # équipe 0 = 7, équipe 1 (locale) = 5.

	assert_str(ep._score_label.text).append_failure_message(
		"le score de la page de fin doit afficher le score du joueur local en premier"
	).is_equal("5 — 7")


func test_end_panel_roster_colors_local_team_as_ally() -> void:
	var ep := _end_panel()
	var match_node := _fake_match()
	match_node.player_info = {
		1: {"name": "Verrou", "team": 1, "kills": 3, "deaths": 1, "is_bot": false},
		9001: {"name": "BOT Renard", "team": 0, "kills": 0, "deaths": 2, "is_bot": true},
	}

	ep.show_result(1, 5, 7, match_node, 1)

	var headers: Array = []
	for c in ep._list.get_children():
		var l := c as Label
		if l.text.begins_with("●") or l.text.begins_with("▼"):
			headers.append(l)
	assert_int(headers.size()).is_equal(2)
	assert_str((headers[0] as Label).text).is_equal("▼ ÉQUIPE 1")
	assert_str((headers[1] as Label).text).is_equal("● ÉQUIPE 2")


# ================================================ GameWorld._record_kill (killfeed enrichi, RPC réseau)
## Relance QA UX-01 : le RPC `_killfeed` (GameWorld._record_kill) doit
## transporter l'arme/la capacité ET le headshot pour TOUT kill, bot contre
## bot compris — jamais seulement pour le kill du joueur LOCAL (l'ancien bug :
## GameHUD ne pouvait deviner que sa PROPRE arme via `Weapon.hit_confirmed`,
## qui ne dit rien d'un kill entre deux bots). Même patron de double que
## tests/networking/test_respawn_refill.gd::_TestGameWorld (court-circuite le
## `_ready()` réseau/UI de sélection d'agent, garde le comportement RÉEL de
## `_record_kill`/`_killfeed`).
class _TestGameWorldKillfeed extends GameWorld:
	func _ready() -> void:
		set_multiplayer_authority(1)
		add_to_group("match")

var _kf_offset_index := 0

func _kf_offset() -> Vector3:
	var o := Vector3(float(_kf_offset_index) * 60.0, 0.0, 0.0)
	_kf_offset_index += 1
	return o

func _kf_gameworld() -> GameWorld:
	var world := _TestGameWorldKillfeed.new()
	add_child(world)
	auto_free(world)
	var players := Node3D.new()
	players.name = "Players"
	world.add_child(players)
	return world

## Bot RÉEL (scène de production, même patron que test_respawn_refill.gd::
## _bot_player) — nécessaire pour que `Weapon.cfg()` résolve un loadout réel
## (Ravage/Pistolet, `WeaponDatabase.default_loadout_ids()`), jamais un double
## qui inventerait le nom d'arme.
func _kf_bot(world: GameWorld, id: int, team: int, pname: String) -> PlayerController:
	var player: PlayerController = KF_PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.set("is_bot", true)
	player.set("team", team)
	player.position = _kf_offset()
	player.set("spawn_point", player.position)
	world.get_node(world.players_root).add_child(player)
	auto_free(player)
	world.player_info[id] = {"name": pname, "team": team, "kills": 0, "deaths": 0, "is_bot": true}
	return player


func test_record_kill_broadcasts_killer_weapon_for_any_kill_bot_vs_bot() -> void:
	var world := _kf_gameworld()
	_kf_bot(world, 9201, 0, "BOT Renard")
	_kf_bot(world, 9202, 1, "BOT Iris")

	# Mutation EN PLACE (`received["k"] = v`), jamais une réaffectation
	# (`received = {...}`) : une lambda GDScript capture les variables locales
	# EXTÉRIEURES par VALEUR à sa création — réaffecter `received` DANS la
	# lambda ne rebranche que sa PROPRE copie, jamais la variable de la
	# fonction de test (vérifié empiriquement : la réaffectation laissait
	# `received` vide après l'appel).
	var received: Dictionary = {}
	world.kill_logged.connect(func(_killer, _victim, _killer_team, weapon_or_ability, headshot):
		received["weapon_or_ability"] = weapon_or_ability
		received["headshot"] = headshot
	)

	world._record_kill(9201, 9202)

	assert_str(received.get("weapon_or_ability", "")).append_failure_message(
		"un kill bot contre bot doit lui aussi porter l'arme du tueur dans le killfeed — relance QA UX-01"
	).is_equal("Ravage")
	assert_bool(received.get("headshot", true)).is_false()


func test_record_kill_broadcasts_headshot_when_reported_fresh() -> void:
	var world := _kf_gameworld()
	_kf_bot(world, 9203, 0, "BOT Renard")
	_kf_bot(world, 9204, 1, "BOT Iris")
	world._store_headshot(9203, true)

	var received: Dictionary = {}
	world.kill_logged.connect(func(_killer, _victim, _killer_team, _weapon_or_ability, headshot):
		received["headshot"] = headshot
	)

	world._record_kill(9203, 9204)

	assert_bool(received.get("headshot", false)).append_failure_message(
		"un headshot confirmé juste avant le kill doit se retrouver dans le RPC killfeed — relance QA UX-01"
	).is_true()


func test_record_kill_broadcasts_active_ability_over_weapon_when_fresh() -> void:
	var world := _kf_gameworld()
	_kf_bot(world, 9205, 0, "BOT Renard")
	_kf_bot(world, 9206, 1, "BOT Iris")
	world._store_ability(9205, "Éblouissement")

	var received: Dictionary = {}
	world.kill_logged.connect(func(_killer, _victim, _killer_team, weapon_or_ability, _headshot):
		received["weapon_or_ability"] = weapon_or_ability
	)

	world._record_kill(9205, 9206)

	assert_str(received.get("weapon_or_ability", "")).append_failure_message(
		"une capacité active récente doit primer sur l'arme dans le killfeed"
	).is_equal("Éblouissement")


# ================================================ GameHUD._trigger_kill_word (mot-bruit par arme + multi-kill)

## GameHUD nu (mêmes composants que le vrai HUD ; aucun joueur/match acquis —
## `_trigger_kill_word` n'a besoin que de `_kill_word` et, pour le mot PAR
## ARME, de `_weapon`, injecté directement ci-dessous).
func _game_hud() -> Node:
	var hud = GAME_HUD_SCRIPT.new()
	add_child(hud)
	auto_free(hud)
	return hud

## Arme réelle (Weapon.gd, hors périmètre d'écriture mais lue telle quelle) —
## `_ready()` construit un inventaire de loadout par défaut (Ravage/Pistolet)
## SANS dépendre d'un PlayerController parent (`get_parent() as PlayerController`
## renvoie simplement `null`, `_inv` reste construit).
func _real_weapon() -> Weapon:
	var w := Weapon.new()
	add_child(w)
	auto_free(w)
	return w


func test_trigger_kill_word_uses_the_weapon_kill_word_not_the_generic_one() -> void:
	var hud = _game_hud()
	hud._weapon = _real_weapon()

	hud._trigger_kill_word(false)

	assert_str(hud._kill_word._label.text).append_failure_message(
		"la confirmation de kill doit utiliser l'onomatopée DE L'ARME (STYLE_BIBLE v3 §9.4), pas le mot générique historique — relance QA UX-01"
	).is_equal(HitFeedback.weapon_kill_word("Ravage"))


func test_trigger_kill_word_still_counts_a_double_kill_faster_than_the_burst_duration() -> void:
	var hud = _game_hud()
	hud._weapon = _real_weapon()

	hud._trigger_kill_word(false)
	assert_bool(hud._kill_word.is_busy()).append_failure_message(
		"préalable du test : le burst précédent doit encore être actif (is_busy())"
	).is_true()
	hud._trigger_kill_word(false)  # doublé plus rapide que les 700 ms du burst précédent.

	assert_int(hud._kill_word._streak).append_failure_message(
		"un doublé plus rapide que KillWordBurst.is_busy() ne doit JAMAIS être ignoré par le compteur multi-kill — relance QA UX-01"
	).is_equal(2)
	assert_str(hud._kill_word._multi_label.text).is_equal(HitFeedback.multi_kill_label(2))
