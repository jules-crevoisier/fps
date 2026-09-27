## capture_revolver.gd
## Captures in-game (tâche "revolver", 2026-09-27) du Revolver — slot 2, HUD,
## ADS, fan-fire (FP) et corps tiers du bot (3P) — même famille que
## tools/rigging/capture_frog_cowboy_fp.gd (bras FP du joueur humain, actions
## pilotées par le singleton Input) et tools/rigging/capture_frog_cowboy.gd
## (caméra auxiliaire + `_force_third_person_weapon` pour voir un BOT en 3P,
## normalement invisible à sa propre fenêtre — contract-p0.md, "hôte et bots
## simulés côté serveur" : ThirdPersonWeapon.gd est inerte pour tout joueur
## dont CE process a l'autorité).
##
## FENÊTRÉ, PAS headless (voir la doc des deux scripts ci-dessus — un vrai
## swapchain est nécessaire pour lire `get_root().get_texture()`) :
##   "%GODOT%" --path . --screen 1 -s res://tools/rigging/capture_revolver.gd -- --out=reports/checkpoints/2026-09-27_revolver
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const _SETTLE_FRAMES := 130      ## joueur+bot spawn/tombent au sol/s'équipent (Ravage, FP_Draw fini).
const _POST_ACTION_SETTLE := 6   ## laisse le swapchain refléter le dernier état avant de lire la texture.

var _out_dir: String = "res://reports/checkpoints/2026-09-27_revolver"
var _frame: int = 0
var _world: Node = null
var _player: PlayerController = null
var _weapon: Weapon = null
var _bot: PlayerController = null
var _bot_weapon: Weapon = null
var _quit_at_frame: int = -1

## Bornes de capture (frames depuis _SETTLE_FRAMES) — même discipline que
## capture_frog_cowboy_fp.gd : press/release JAMAIS dans le même appel à
## _process (rythme RENDU, pas physique), espacés d'assez de frames pour
## qu'au moins un tic physique observe chaque front.
##
## RÉVISÉ 2026-09-27 (pivot "Valorant Classic", après playtest) : RMB
## (action "aim") ne vise PLUS sur le revolver — `PlayerInput.aim_held` reste
## faux quel que soit RMB (voir `weapon_aims_on_right_click`), c'est
## `alt_fire_held` (maintien BRUT de la MÊME action "aim") qui déclenche le
## fan. Presser "aim" ici produit donc directement le fan, jamais l'ADS —
## rv_b_ads.png devient une preuve d'ABSENCE de zoom/ADS, rv_c_fan.png reste
## la même capture mi-fan qu'avant (simplement déclenchée par RMB au lieu de
## LMB tenu).
const _SWITCH_PRESS_AT := 6          ## touche 2 (weapon_2) -- Revolver.
const _EQUIPPED_SHOT_AT := 46        ## switch (0.25 s) + FPP_Draw (0.45 s) largement passés.
const _RMB_PRESS_AT := 54            ## RMB (action "aim") -- fan pour le revolver, PAS d'ADS.
const _RMB_NO_ZOOM_SHOT_AT := 58     ## quelques frames après l'appui : prouve l'absence de zoom/blend ADS.
## Tenu ASSEZ PEU longtemps pour ne consommer que ~3 des 6 coups du barillet
## (immédiat + 2 tirs fan, intervalle ~8 tics/coup à 7.5 tirs/s) — sinon le
## barillet se viderait avant l'appui MANUEL sur "reload" plus bas et
## déclencherait un rechargement AUTOMATIQUE prématuré (Weapon._owner_tick,
## réserve non nulle), décalant tout le minutage des captures mi-rechargement.
const _RMB_FAN_SHOT_AT := 75
const _RMB_RELEASE_AT := 78
const _RELOAD_PRESS_AT := 96
## Captures mi-rechargement demandées par le lead (2026-09-27, Rev_Reload v2 :
## barillet qui s'ouvre, douilles qui tombent, speedloader qui rentre) — à
## ~0.35 s / 0.65 s / 1.3 s après l'appui sur "reload" (60 Hz : 21/39/78 tics).
const _RELOAD_SHOT_1_AT := _RELOAD_PRESS_AT + 21   ## ~0.35 s -- barillet ouvert.
const _RELOAD_SHOT_2_AT := _RELOAD_PRESS_AT + 39   ## ~0.65 s -- douilles qui tombent.
const _RELOAD_SHOT_3_AT := _RELOAD_PRESS_AT + 78   ## ~1.3 s -- speedloader qui rentre.
const _RELOAD_DONE_AT := _RELOAD_PRESS_AT + 150    ## 2.4 s de rechargement + marge, avant de bouger à autre chose.
const _BOT_3P_SETUP_AT := _RELOAD_DONE_AT + 4
const _BOT_3P_SHOT_AT := _BOT_3P_SETUP_AT + 6
## Garde-fou UNIQUEMENT si `_BOT_3P_SHOT_AT` n'a jamais fixé `_quit_at_frame`
## (bot introuvable) — doit rester bien AU-DELÀ de
## `_BOT_3P_SHOT_AT + _POST_ACTION_SETTLE + 10` : sinon cette branche
## `elif since >= _FINAL_QUIT_AT` (vraie à CHAQUE frame une fois franchie,
## contrairement aux autres bornes en `==`) reculerait `_quit_at_frame` d'un
## frame à chaque appel avant que la borne fixée par _BOT_3P_SHOT_AT n'ait pu
## déclencher `quit()`, et le process ne se fermerait JAMAIS (constaté sur la
## 1ère version de ce script : la marge doit être large, jamais serrée).
const _FINAL_QUIT_AT := _BOT_3P_SHOT_AT + _POST_ACTION_SETTLE + 60

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)

func _process(_delta: float) -> bool:
	if _frame == 0:
		_boot()
	_frame += 1

	if _quit_at_frame > 0 and _frame >= _quit_at_frame:
		call_deferred("quit", 0)
		return false

	if _frame == _SETTLE_FRAMES:
		_find_human()
		_find_bot()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _player == null:
		return false

	var since := _frame - _SETTLE_FRAMES
	if since == _SWITCH_PRESS_AT:
		Input.action_press("weapon_2")
	elif since == _SWITCH_PRESS_AT + 2:
		Input.action_release("weapon_2")
	elif since == _EQUIPPED_SHOT_AT:
		call_deferred("_save_current_view", "rv_a_equipped.png")
	elif since == _RMB_PRESS_AT:
		Input.action_press("aim")  # RMB -- fan pour le revolver (AltFireMode.FAN), jamais l'ADS.
	elif since == _RMB_NO_ZOOM_SHOT_AT:
		call_deferred("_save_current_view", "rv_b_rmb_no_zoom.png")
	elif since == _RMB_FAN_SHOT_AT:
		call_deferred("_save_current_view", "rv_c_fan.png")
	elif since == _RMB_RELEASE_AT:
		Input.action_release("aim")
	elif since == _RELOAD_PRESS_AT:
		Input.action_press("reload")
	elif since == _RELOAD_PRESS_AT + 2:
		Input.action_release("reload")  # `reload_pressed` est un front, pas un maintien.
	elif since == _RELOAD_SHOT_1_AT:
		call_deferred("_save_current_view", "rv_e_reload_0.35s.png")
	elif since == _RELOAD_SHOT_2_AT:
		call_deferred("_save_current_view", "rv_f_reload_0.65s.png")
	elif since == _RELOAD_SHOT_3_AT:
		call_deferred("_save_current_view", "rv_g_reload_1.3s.png")
	elif since == _BOT_3P_SETUP_AT:
		_equip_bot_revolver_and_force_third_person()
	elif since == _BOT_3P_SHOT_AT:
		_shoot_bot_third_person()
		_quit_at_frame = _frame + _POST_ACTION_SETTLE + 10
	elif since >= _FINAL_QUIT_AT:
		_quit_at_frame = _frame + _POST_ACTION_SETTLE
	return false

func _boot() -> void:
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 1
	var packed := load(_SHIPMENT) as PackedScene
	_world = packed.instantiate()
	get_root().add_child(_world)

func _find_human() -> void:
	_player = _find_player_in(get_root(), true) as PlayerController
	if _player == null:
		push_error("capture_revolver: aucun PlayerController humain local trouvé dans l'arbre")
		return
	_weapon = _player.get_node_or_null("Weapon") as Weapon
	print("capture_revolver: joueur humain trouvé à ", _player.global_position, " weapon=", _weapon)

func _find_bot() -> void:
	_bot = _find_player_in(get_root(), false) as PlayerController
	if _bot == null:
		push_error("capture_revolver: aucun PlayerController bot trouvé dans l'arbre")
		return
	_bot_weapon = _bot.get_node_or_null("Weapon") as Weapon
	print("capture_revolver: bot trouvé à ", _bot.global_position, " weapon=", _bot_weapon)

func _find_player_in(node: Node, want_human: bool) -> Node:
	var pc := node as PlayerController
	if pc and (pc.is_local_human() if want_human else pc.is_bot):
		return pc
	for c in node.get_children():
		var r := _find_player_in(c, want_human)
		if r:
			return r
	return null

## Force le bot au slot 2 (revolver) — même chemin que Weapon._try_equip pour
## un humain, appel DIRECT car ce process est le SERVEUR (hôte+bot simulés
## côté serveur, contract-p0.md) : aucune requête réseau à simuler. Rejoue
## ensuite l'initialisation que ThirdPersonWeapon.gd ferait pour un vrai pair
## distant (voir capture_frog_cowboy.gd::_force_third_person_weapon, repris
## ici tel quel) — ce bot est localement autoritaire, ThirdPersonWeapon n'y
## tourne donc normalement jamais.
func _equip_bot_revolver_and_force_third_person() -> void:
	if _bot == null or _bot_weapon == null:
		return
	_bot_weapon.equip_weapon_slot(1)
	var tp := _bot.get_node_or_null("ThirdPersonWeapon") as ThirdPersonWeapon
	var body := _bot.get_node_or_null("%CharacterModel") as CharacterBody
	if tp == null or body == null:
		push_error("capture_revolver: ThirdPersonWeapon/CharacterBody introuvable(s) pour le bot")
		return
	tp.visible = true
	tp.set_process(true)
	tp.player = _bot
	tp.set("_character_body", body)
	tp.weapon = _bot_weapon
	if body.is_model_ready():
		tp.call("_on_body_ready")
	_bot_weapon.current_id_changed.connect(tp._on_current_id_changed)
	tp._on_current_id_changed(WeaponDatabase.id_of(_bot_weapon.cfg()))
	print("capture_revolver: bot ThirdPersonWeapon forcé, _model=", tp.get("_model"), " cfg=", _bot_weapon.cfg().weapon_name if _bot_weapon.cfg() else null)

func _shoot_bot_third_person() -> void:
	if _bot == null:
		return
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.current = true
	var p: Vector3 = _bot.global_position
	cam.global_position = p + Vector3(2.6, 1.6, 0.6)
	cam.look_at(p + Vector3(0, 1.1, 0), Vector3.UP)
	call_deferred("_present_and_save", cam, "rv_d_3p.png")

func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name)
	var abs_dir := ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var err := img.save_png(path)
	print("capture_revolver: ", name, " -> ", path, " (err=", err, ")")

func _save_current_view(name: String) -> void:
	for i in _POST_ACTION_SETTLE:
		await process_frame
	var img := get_root().get_texture().get_image()
	if img:
		_save(img, name)
	else:
		push_error("capture_revolver: pas d'image (lancé --headless ? voir l'en-tête)")

func _present_and_save(cam: Camera3D, name: String) -> void:
	for i in 6:
		await process_frame
	var img := get_root().get_texture().get_image()
	if img:
		_save(img, name)
	else:
		push_error("capture_revolver: pas d'image (lancé --headless ? voir l'en-tête)")
	cam.queue_free()
