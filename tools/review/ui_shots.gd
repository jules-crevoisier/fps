## ui_shots.gd
## Sonde de revue automatisée FENÊTRÉE (vrai swapchain requis — contrat agent
## parallèle, voir docs/REVIEW.md) : capture CHAQUE écran d'interface (menu,
## sélection d'agent, arsenal, options, galerie du kit UI, pause, achat, HUD
## complet, six états du panneau munitions, killfeed enrichi, tableau des
## scores, mort, fin) en 1920x1080 ET 1280x720, PNG + un JSON récapitulatif.
## Killfeed/fin sont chacun capturés pour les
## DEUX perspectives d'équipe locale (relance QA UX-01, voir
## `_shot_match_screens` : "_team0"/"_team1") — le HUD est RELATIF au joueur
## local (Comic.is_ally), jamais un côté fixe, donc la revue visuelle doit
## pouvoir comparer les deux.
##
## UX-36 (retour lead 2026-09-25) — écran "hud_wasteland" (`_shot_wasteland_
## hud`) : le seul écran ci-dessus qui force `MatchConfig.map_id` à
## "wasteland" (les autres captures « en match » suivent la carte par défaut
## du mode TDM, jamais Wasteland) — voir sa docstring.
##
## GF-23 (2e passage, 2026-09-25) — panneau munitions (STYLE_BIBLE §8.3,
## docs/research/10_ammo_kits_input.md §2.6) : le seul état capturé jusqu'ici
## était celui, quelconque, du match TDM en cours ("hud"). Aucun outil ne
## pouvait donc vérifier les seuils/couleurs de réserve ni les invites — voir
## `_shot_ammo_panel_states`, qui pilote `AmmoPanel` directement (accès en
## lecture/écriture à `GameHUD._ammo_panel`, hors de la liste de fichiers de
## cette tâche, via `Object.get()` — même patron que `mode.get("_zone")` dans
## GameWorld.gd/`stuck.get("_phase")` dans BotBrain.gd) pour forcer, dans
## l'ordre, six écrans déterministes : réserve normale (crème), réserve basse
## (ocre, ≤ 1 chargeur), réserve VIDE (rouge d'encre), invite RECHARGER,
## invite CHANGER D'ARME, toast de ramassage « +N ARME ».
##
## Usage :
##   godot --path . -s res://tools/review/ui_shots.gd -- --out=DIR
##
## Écrit "<out>/<écran>_<largeur>x<hauteur>.png" pour chaque écran x
## résolution et "<out>/ui_shots.json" ({"shots":[{"screen","resolution",
## "path"}], "done":bool}). Imprime "UI_SHOT <écran> <résolution> <chemin>"
## par capture puis "UI_SHOTS_DONE" et quitte (0), ou "UI_SHOTS_FAIL <raison>"
## et quitte (1) — jamais un crash de toute la pipeline (run_review.ps1::
## Step-UiShots donne le statut `missing`, jamais un plantage, si ce fichier
## est absent).
##
## Une seule fenêtre, redimensionnée au RUNTIME entre chaque capture (`root.
## size`) plutôt que relancée deux fois via le flag moteur `--resolution`
## (comme le faisait l'ancien tests/ui/capture_shots.gd, lu mais non modifié,
## une cible par process séparé) : project.godot [display] fixe
## `window/stretch/mode="canvas_items"`, donc le rendu suit la taille RÉELLE
## de la fenêtre (pas un rendu à résolution interne fixe re-mis à l'échelle),
## et les deux résolutions demandées sont au même ratio 16:9 — aucun
## letterboxing entre les deux passes.
##
## Écrans autonomes (menu/sélection d'agent/arsenal/options/galerie du kit
## UI) : une instance par écran, comme tests/ui/capture_shots.gd::_run_standalone.
## Écrans EN MATCH (pause,
## achat, HUD, tableau des scores, mort, fin) : UN SEUL match TDM avec bots
## (scenes/levels/tdm_map.tscn) réutilisé pour les six, dans cet ordre
## technique (pause/achat d'abord — se rouvrent/referment sans effet de bord ;
## mort puis fin en dernier, puisque les deux laissent le joueur/la partie
## dans un état terminal). Pause/achat sont déclenchés comme un VRAI joueur
## le ferait (`Input.parse_input_event` sur les actions "pause"/"buy_menu",
## lues par PauseMenu/BuyMenu._unhandled_input) ; le tableau des scores lit
## directement `Input.is_action_pressed("scoreboard")` (GameHUD._process),
## donc un simple `Input.action_press` suffit, sans passer par
## `_unhandled_input`. Achat/fin réutilisent les crochets de démonstration
## PUBLICS déjà exposés pour les captures d'écran (BuyMenu.debug_force_open,
## GameHUD.debug_force_end — jamais appelés en jeu normal, voir leurs
## docstrings). La mort est obtenue en tuant réellement le joueur hôte
## (Health.apply_damage), sans crochet de triche : c'est le chemin normal du
## jeu (Health.died -> GameHUD._on_died -> DeathPanel.show_death).
extends SceneTree

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const MATCH_SCENE := "res://scenes/levels/tdm_map.tscn"
## ART-31 (relance QA) : galerie de démonstration du kit de composants
## autocollant (BrushHeader + Charbon/Autocollant/Hexagone, KitStates §8.4) —
## capturée comme un écran autonome de plus, exactement comme menu/sélection
## d'agent/options ci-dessous. Rend CHK-33 (contraste) et CHK-37 (états
## complets) mesurables par tools/review/style_check.py, qui scanne tout
## `ui_shots/*.png` sans distinguer les écrans (voir sa docstring
## `resolve_ui_shots`).
const UI_KIT_GALLERY_SCENE := "res://scenes/dev/ui_kit_gallery.tscn"
const AGENT_SELECT_SCRIPT := preload("res://scripts/ui/AgentSelectScreen.gd")
## ART-34 (2e passage) : catalogue d'armes en lecture seule (onglet ARSENAL
## de MainMenu) — jamais capturé jusqu'ici, ce qui rendait CHK-32 à CHK-37
## invérifiables sur cet écran (note de revue de la vague 32). Même script
## autonome que AGENT_SELECT_SCRIPT/OPTIONS_SCRIPT ci-dessus : ArsenalMenu.gd
## se construit seul (accessible aussi depuis MainMenu, TAB_ARSENAL), sans
## dépendre d'un match en cours.
const ARSENAL_SCRIPT := preload("res://scripts/ui/ArsenalMenu.gd")
const OPTIONS_SCRIPT := preload("res://scripts/ui/OptionsMenu.gd")
const LEVEL_LOOK_SCRIPT := preload("res://scripts/core/LevelLook.gd")

## Design.md v2 §12 : "1920×1080 ... 1280×720" — mêmes 16:9, aucun
## letterboxing entre les deux passes (voir note d'en-tête).
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1280, 720)]
## Attente initiale après le chargement/déclenchement d'un écran (laisse les
## textures/tweens/le premier _process se stabiliser) — même ordre de
## grandeur que tools/map_shots.gd (50) / tests/ui/capture_shots.gd (90).
const SETTLE_FRAMES := 50
## Attente, plus courte, après un simple redimensionnement de fenêtre (le
## re-flow des ancrages Control est quasi immédiat, pas besoin du plein délai
## de settle ci-dessus une seconde fois).
const RESIZE_SETTLE_FRAMES := 12
## Attente avant la capture de l'invite RECHARGER (`_shot_ammo_panel_states`) :
## `HudFormat.RELOAD_PROMPT_DELAY` (1,5 s) après la rafale simulée, à
## `physics_ticks_per_second` = 60 (project.godot) → 90 tics. Marge à 110
## tics (≈ 1,83 s) au cas où le process (`AmmoPanel._process`, qui fait
## vieillir le délai) tournerait légèrement sous le taux des tics physiques
## qu'on attend ici.
const RELOAD_PROMPT_SETTLE_FRAMES := 110
## Réserve arène du Ravage (docs/research/10_ammo_kits_input.md §2.3) — armes
## FIXÉES ici plutôt que lues sur le loadout réel du joueur hôte (variable
## selon le mode/l'ordre d'achat) pour que les six états de
## `_shot_ammo_panel_states` restent des seuils déterministes, indépendants
## de l'arme réellement équipée pendant le match TDM de fond.
const AMMO_DEMO_WEAPON_NAME := "RAVAGE"
const AMMO_DEMO_MAG_SIZE := 25
const DEFAULT_OUT := "res://.ui_shots_out"

var _out_dir: String = DEFAULT_OUT
var _shots: Array = []  # [{"screen": String, "resolution": String, "path": String}]
var _started := false
var _failed := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
		return false
	return false  # `_run()` appelle `_finish()` (donc `quit()`) lui-même à la fin.

# ==========================================================================
#  ORCHESTRATION
# ==========================================================================
func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	await _shot_standalone("menu", _load_menu)
	await _shot_standalone("agent_select", _load_agent_select)
	await _shot_standalone("arsenal", _load_arsenal)
	await _shot_standalone("options", _load_options)
	await _shot_standalone("ui_kit_gallery", _load_ui_kit_gallery)
	await _shot_match_screens()
	await _shot_wasteland_hud()
	_finish()

func _finish() -> void:
	_write_json()
	if _failed:
		quit(1)
	else:
		print("UI_SHOTS_DONE")
		quit(0)

# ==========================================================================
#  ÉCRANS AUTONOMES (pas de match derrière)
# ==========================================================================
func _load_menu() -> Node:
	var packed := load(MAIN_MENU_SCENE) as PackedScene
	if packed == null:
		_fail("scène introuvable : %s" % MAIN_MENU_SCENE)
		return null
	return packed.instantiate()

## Compte à rebours large : ne doit jamais verrouiller pendant les ~2 s que
## prend une capture double-résolution (même garde que
## tests/ui/capture_shots.gd::_run_agent_select, countdown=45).
func _load_agent_select() -> Node:
	var scr := AGENT_SELECT_SCRIPT.new()
	scr.countdown = 60.0
	return scr

func _load_options() -> Node:
	var scr := OPTIONS_SCRIPT.new()
	if scr is Control:
		scr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return scr

## Arsenal (§8.6 même grammaire que l'Achat, catalogue en lecture seule) :
## `ArsenalMenu._ready()` pose déjà lui-même son ancrage plein-rect (voir sa
## docstring) — aucun réglage supplémentaire ici, contrairement à
## `_load_options()` ci-dessus qui charge un script nu.
func _load_arsenal() -> Node:
	return ARSENAL_SCRIPT.new()

## Galerie du kit (ART-31) : `UiKitGallery._ready()` s'occupe déjà elle-même
## de son ancrage plein-rect (voir sa docstring) — aucun réglage supplémentaire
## nécessaire ici, contrairement à `_load_options()` ci-dessus qui charge un
## script nu plutôt qu'une `.tscn`.
func _load_ui_kit_gallery() -> Node:
	var packed := load(UI_KIT_GALLERY_SCENE) as PackedScene
	if packed == null:
		_fail("scène introuvable : %s" % UI_KIT_GALLERY_SCENE)
		return null
	return packed.instantiate()

## Instancie `factory()`, capture aux DEUX résolutions, libère. `factory`
## renvoie null en cas d'échec (déjà signalé via `_fail`, qui a mis `_failed`
## à vrai — chaque étape suivante se saute d'elle-même en tête de fonction).
func _shot_standalone(screen: String, factory: Callable) -> void:
	if _failed:
		return
	var inst: Node = factory.call()
	if inst == null:
		return
	root.add_child(inst)
	current_scene = inst
	await _wait_physics(SETTLE_FRAMES)
	await _capture_all_resolutions(screen)
	inst.queue_free()
	await _wait_physics(4)

# ==========================================================================
#  ÉCRANS EN MATCH (un seul boot TDM+bots, réutilisé pour les six)
# ==========================================================================
func _shot_match_screens() -> void:
	if _failed:
		return
	var look: Node = LEVEL_LOOK_SCRIPT.new()
	root.add_child(look)

	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = ""
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 1

	var packed := load(MATCH_SCENE) as PackedScene
	if packed == null:
		_fail("scène introuvable : %s" % MATCH_SCENE)
		return
	var inst := packed.instantiate()
	if inst.get("agent_select") != null:
		inst.set("agent_select", false)
	if inst.get("allow_bot_fill") != null:
		inst.set("allow_bot_fill", true)  # HUD/scoreboard/killfeed peuplés, pas une salle vide.
	root.add_child(inst)
	current_scene = inst

	var player := await _wait_for_local_player(8.0)
	if player == null:
		_fail("joueur hôte jamais spawné dans %s" % MATCH_SCENE)
		return
	var hp := player.get_node_or_null("Health") as Health
	if hp == null:
		_fail("nœud Health introuvable sur le joueur hôte")
		return
	# TDM + bots (allow_bot_fill=true, pour un HUD/scoreboard peuplés) : le bot
	# ennemi riposte réellement et peut tuer l'hôte à tout moment pendant les
	# captures pause/achat/HUD/tableau des scores — invulnérabilité longue
	# jusqu'à ce qu'ON déclenche nous-mêmes la mort (`end_spawn_protection()`
	# juste avant, plus bas), pour que ces écrans montrent bien un joueur VIVANT
	# et non un mort aléatoire selon la chance du combat.
	hp.spawn_protection(9999.0)
	# Laisse le bot de remplissage apparaître et le HUD se brancher
	# (GameHUD._acquire_player, voir son commentaire) avant la première capture.
	await _wait_physics(SETTLE_FRAMES)

	var hud := inst.get_node_or_null("HUD")
	var pause_menu := inst.get_node_or_null("PauseMenu")
	var buy_menu := inst.get_node_or_null("BuyMenu")

	if pause_menu:
		_press_action("pause")  # ouvre (PauseMenu._unhandled_input : ni _options ni _open -> _pause()).
		await _wait_physics(SETTLE_FRAMES)
		await _capture_all_resolutions("pause")
		_press_action("pause")  # referme (_open déjà vrai -> _close()).
		await _wait_physics(4)
	else:
		_fail("nœud PauseMenu introuvable dans %s" % MATCH_SCENE)
		return

	if buy_menu and buy_menu.has_method("debug_force_open"):
		buy_menu.debug_force_open()
		await _wait_physics(SETTLE_FRAMES)
		await _capture_all_resolutions("buy")
		_press_action("buy_menu")  # referme (toggle réel : _open est vrai, aucun verrou à l'ouverture).
		await _wait_physics(4)
	else:
		_fail("BuyMenu.debug_force_open introuvable dans %s" % MATCH_SCENE)
		return

	await _wait_physics(SETTLE_FRAMES)
	await _capture_all_resolutions("hud")

	await _shot_ammo_panel_states(hud)
	if _failed:
		return

	# Killfeed enrichi RELATIF au joueur local (UX-01, relance QA) : les DEUX
	# perspectives (équipe locale forcée à 0 puis 1) sur les 2 MÊMES kills —
	# prouve que allié/ennemi (couleur, ✦ headshot, tag arme/capacité) suit
	# bien l'équipe locale, jamais l'indice d'équipe brut. `debug_force_killfeed_local`
	# ne modifie que le killfeed (pas l'état de match) : sûr à enchaîner ici,
	# avant scoreboard/mort/fin ci-dessous.
	if hud and hud.has_method("debug_force_killfeed_local"):
		hud.debug_force_killfeed_local(0)
		await _wait_physics(SETTLE_FRAMES)
		await _capture_all_resolutions("killfeed_local_team0")
		hud.debug_force_killfeed_local(1)
		await _wait_physics(SETTLE_FRAMES)
		await _capture_all_resolutions("killfeed_local_team1")
	else:
		_fail("GameHUD.debug_force_killfeed_local introuvable dans %s" % MATCH_SCENE)
		return

	Input.action_press("scoreboard")
	await _wait_physics(SETTLE_FRAMES)
	await _capture_all_resolutions("scoreboard")
	Input.action_release("scoreboard")
	await _wait_physics(4)

	hp.end_spawn_protection()  # lève l'invulnérabilité posée plus haut : CETTE mort doit passer.
	hp.apply_damage(999999.0, _host_id())
	await _wait_physics(SETTLE_FRAMES)
	await _capture_all_resolutions("death")

	if hud and hud.has_method("debug_force_end"):
		# UX-01 (relance QA) : le HUD est RELATIF au joueur local — capturer
		# les DEUX perspectives (équipe locale forcée à 0 puis 1) sur le MÊME
		# score (team0=40, team1=27) prouve que VICTOIRE/DÉFAITE et l'ordre
		# des colonnes suivent bien l'équipe locale, jamais un côté fixe.
		hud.debug_force_end(0, 40, 27, 0)
		await _wait_physics(SETTLE_FRAMES)
		await _capture_all_resolutions("end_local_team0")
		hud.debug_force_end(0, 40, 27, 1)
		await _wait_physics(SETTLE_FRAMES)
		await _capture_all_resolutions("end_local_team1")
	else:
		_fail("GameHUD.debug_force_end introuvable dans %s" % MATCH_SCENE)
		return

	inst.free()
	await _wait_physics(4)

## UX-36 (retour lead 2026-09-25) — HUD EN MATCH sur la carte Wasteland
## SPÉCIFIQUEMENT : `_shot_match_screens()` ci-dessus utilise la carte PAR
## DÉFAUT du mode TDM (`MapCatalog.default_for("tdm")` -> "port_ferraille",
## jamais Wasteland, `MatchConfig.map_id` y reste ""), donc aucune capture
## précédente ne montrait la seule carte du proto que le lead garde pour
## l'instant (décision produit hors de mon périmètre). Lance un DEUXIÈME match
## TDM+bots dédié, `MatchConfig.map_id` forcé à "wasteland", pour produire la
## capture "à côté de bl3_hud.png" exigée par le contrat -- sans toucher au
## reste du pipeline ci-dessus (pause/achat/tableau des scores/mort/fin
## restent sur la carte par défaut). "bots actifs" : `allow_bot_fill` (même
## réglage que `_shot_match_screens`) ; "arme en main" : le joueur hôte spawn
## avec son loadout par défaut équipé, comme dans tout match réel, aucun
## crochet supplémentaire nécessaire ici.
func _shot_wasteland_hud() -> void:
	if _failed:
		return
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "wasteland"
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 1

	var packed := load(MATCH_SCENE) as PackedScene
	if packed == null:
		_fail("scène introuvable : %s" % MATCH_SCENE)
		return
	var inst := packed.instantiate()
	if inst.get("agent_select") != null:
		inst.set("agent_select", false)
	if inst.get("allow_bot_fill") != null:
		inst.set("allow_bot_fill", true)  # bots actifs (contrat UX-36).
	root.add_child(inst)
	current_scene = inst

	var player := await _wait_for_local_player(8.0)
	if player == null:
		_fail("joueur hôte jamais spawné sur wasteland dans %s" % MATCH_SCENE)
		return
	var hp := player.get_node_or_null("Health") as Health
	if hp != null:
		hp.spawn_protection(9999.0)  # capture de démonstration : jamais tué pendant la prise de vue.
	# Laisse le bot de remplissage apparaître et le HUD se brancher
	# (GameHUD._acquire_player) avant la capture.
	await _wait_physics(SETTLE_FRAMES)

	await _capture_all_resolutions("hud_wasteland")

	inst.free()
	await _wait_physics(4)
	MatchConfig.map_id = ""  # repli neutre pour tout appelant ultérieur du process.

## GF-23 (2e passage) — six états déterministes du panneau munitions
## (STYLE_BIBLE §8.3, docs/research/10_ammo_kits_input.md §2.6), pilotés
## directement sur `AmmoPanel` (API publique `update_weapon`/`update_ammo`/
## `show_pickup_toast`, voir sa docstring) plutôt que via une vraie rafale —
## seule façon d'obtenir des seuils REPRODUCTIBLES (réserve exacte, délai
## depuis la dernière rafale) indépendamment de l'IA du bot de remplissage.
## `hud` : nœud "HUD" (GameHUD) du match TDM déjà en cours, voir l'appelant.
func _shot_ammo_panel_states(hud: Node) -> void:
	if _failed or hud == null:
		return
	var ammo_panel := hud.get("_ammo_panel") as AmmoPanel
	if ammo_panel == null:
		_fail("nœud AmmoPanel introuvable sur GameHUD")
		return

	# Chargeur FIXÉ (voir AMMO_DEMO_WEAPON_NAME/AMMO_DEMO_MAG_SIZE) : mag_size
	# inchangé d'un état à l'autre ci-dessous (jamais un "switched" au sens
	# d'AmmoPanel.update_weapon), donc `_mag_prev`/`_reserve_prev` ne sont
	# JAMAIS remis à -1 par ce seul appel — seule une VRAIE variation de
	# `current`/`reserve` (ci-dessous) fait bouger la détection rafale/
	# ramassage.
	ammo_panel.update_weapon(AMMO_DEMO_WEAPON_NAME, AMMO_DEMO_MAG_SIZE)

	# 1) Réserve normale (crème) : chargeur plein, réserve largement au-dessus
	# d'un chargeur (125, réserve arène du Ravage §2.3).
	ammo_panel.update_ammo(AMMO_DEMO_MAG_SIZE, 125)
	await _wait_physics(SETTLE_FRAMES)
	await _capture_all_resolutions("ammo_reserve_normal")
	if _failed:
		return

	# 2) Réserve basse (ocre) : ≤ 1 chargeur en réserve (§2.6). Chargeur
	# INCHANGÉ (25 -> 25, pas de baisse) : jamais lu comme une rafale, et la
	# réserve BAISSE (125 -> 20) donc jamais lu comme un ramassage non plus
	# (`HudFormat.reserve_pickup_magazines` — aucun toast parasite).
	ammo_panel.update_ammo(AMMO_DEMO_MAG_SIZE, 20)
	await _wait_physics(SETTLE_FRAMES)
	await _capture_all_resolutions("ammo_reserve_low")
	if _failed:
		return

	# 3) Réserve VIDE (rouge d'encre, mention "VIDE") : chargeur toujours
	# plein (25) pour isoler CET état de l'invite CHANGER D'ARME (§5 ci-
	# dessous, qui exige aussi le chargeur à 0).
	ammo_panel.update_ammo(AMMO_DEMO_MAG_SIZE, 0)
	await _wait_physics(SETTLE_FRAMES)
	await _capture_all_resolutions("ammo_reserve_empty")
	if _failed:
		return

	# 4) Invite "[touche] RECHARGER" : chargeur ≤ 25 % (6/25), de la réserve
	# (90), et ≥ 1,5 s depuis la dernière rafale. Le chargeur BAISSE ici
	# (25 -> 6) : `AmmoPanel` lit ça comme une rafale et remet son délai à 0
	# (voir `_mag_prev`) — d'où l'attente `RELOAD_PROMPT_SETTLE_FRAMES` avant
	# la capture, pas le settle court habituel. Le chargeur changeant EN MÊME
	# TEMPS que la réserve monte, `reserve_pickup_magazines` ne le lit jamais
	# comme un ramassage (garde "respawn/resynchro") : aucun toast parasite.
	ammo_panel.update_ammo(6, 90)
	await _wait_physics(RELOAD_PROMPT_SETTLE_FRAMES)
	await _capture_all_resolutions("ammo_prompt_reload")
	if _failed:
		return

	# 5) Invite "[touche] CHANGER D'ARME" : chargeur ET réserve à 0 (§2.6).
	# Prend toujours le pas sur l'invite RECHARGER dans `AmmoPanel._update_
	# prompt` (voir sa doc) : aucune attente de délai nécessaire ici.
	ammo_panel.update_ammo(0, 0)
	await _wait_physics(SETTLE_FRAMES)
	await _capture_all_resolutions("ammo_prompt_switch")
	if _failed:
		return

	# 6) Toast de ramassage "+N ARME" (1,2 s, §2.6) : état de fond remis à
	# quelque chose de cohérent (chargeur haut, réserve confortable) AVANT le
	# déclenchement, plutôt que de laisser le "VIDE"/CHANGER D'ARME de l'état
	# précédent en toile de fond d'un ramassage. `show_pickup_toast` est
	# appelée directement (API publique de AmmoPanel) : le toast est
	# indépendant de la détection automatique de `update_ammo` ci-dessus,
	# voir sa docstring ("reste une méthode publique pour un déclenchement
	# manuel... captures d'écran").
	ammo_panel.update_ammo(19, 90)
	await _wait_physics(4)
	ammo_panel.show_pickup_toast(3)
	await _capture_all_resolutions("ammo_toast_pickup")  # < 1,2 s : le toast reste visible aux deux résolutions.
	if _failed:
		return

	# Restaure un état neutre (chargeur plein, réserve normale) : les écrans
	# suivants (killfeed/tableau des scores/mort/fin) partagent le même HUD
	# de fond et ne doivent pas hériter d'un "VIDE"/toast laissé par cette
	# séquence de démonstration.
	ammo_panel.update_ammo(AMMO_DEMO_MAG_SIZE, 125)
	await _wait_physics(4)

func _host_id() -> int:
	return get_multiplayer().get_unique_id()

func _wait_for_local_player(timeout: float) -> PlayerController:
	var t := 0.0
	while t < timeout:
		for n in get_nodes_in_group("local_player"):
			if is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
				return n as PlayerController
		await physics_frame
		t += 1.0 / 60.0
	return null

## Simule une VRAIE pression de touche (pas juste `Input.action_press`, qui ne
## fait que poser l'état interne sans jamais traverser `_unhandled_input` —
## voir la doc officielle de `Input.parse_input_event`) : nécessaire pour
## Pause/Achat, qui écoutent `_unhandled_input`, contrairement au tableau des
## scores (lu par un simple polling `Input.is_action_pressed`).
func _press_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)

# ==========================================================================
#  CAPTURE
# ==========================================================================
func _wait_physics(n: int) -> void:
	for i in n:
		await physics_frame

func _capture_all_resolutions(screen: String) -> void:
	for res in RESOLUTIONS:
		if _failed:
			return
		root.size = res
		await _wait_physics(RESIZE_SETTLE_FRAMES)
		_capture(screen, res)

func _capture(screen: String, res: Vector2i) -> void:
	if _failed:
		return
	var res_tag := "%dx%d" % [res.x, res.y]
	var out_path := _globalize("%s/%s_%s.png" % [_out_dir, screen, res_tag])
	var dir := out_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var img := root.get_texture().get_image()
	var err := img.save_png(out_path)
	if err != OK:
		_fail("échec écriture PNG (%d) : %s" % [err, out_path])
		return
	_shots.append({"screen": screen, "resolution": res_tag, "path": out_path})
	print("UI_SHOT ", screen, " ", res_tag, " ", out_path)

func _globalize(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") else path

func _fail(reason: String) -> void:
	if _failed:
		return  # garde la toute PREMIÈRE raison (la plus utile pour diagnostiquer).
	_failed = true
	print("UI_SHOTS_FAIL ", reason)

func _write_json() -> void:
	var abs_path := _globalize(_out_dir.path_join("ui_shots.json"))
	var dir := abs_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var data := {"shots": _shots, "done": not _failed}
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
	else:
		print("UI_SHOTS_WARN impossible d'écrire ", abs_path)
