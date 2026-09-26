## capture_frog_cowboy_fp.gd
## Captures in-game (requirement 8, tâche "frog fp arms") des bras première
## personne de Verrou (ViewModel.gd -> FPArmsRig.gd, remplace les gants
## flottants) : héberge Shipment en 1v1 (même convention que
## scripts/core/QuickStart.gd/tools/rigging/capture_frog_cowboy.gd, team_size
## = 1 -- le JOUEUR humain local, PAS le bot cette fois, voir `_find_human_in`)
## et écrit 5 PNG depuis la VRAIE caméra du joueur (`player.camera`, déjà
## `current = true` -- aucune caméra auxiliaire à poser, contrairement à
## capture_frog_cowboy.gd qui devait regarder un AUTRE joueur/bot) : idle, ADS,
## mi-rechargement (~40 %), mi-inspection (~35 %), sprint.
##
## Piloté par le singleton `Input` (`action_press`/`action_release`, même
## méthode que tests/input/test_player_input.gd -- standard headless/fenêtré,
## PAS de simulation de souris/clavier bas niveau) : `Input.mouse_mode =
## MOUSE_MODE_CAPTURED` d'abord, sinon PlayerInput.gather_from_devices() ne
## lit jamais les périphériques (`reads_devices`, voir sa doc) et bots/joueur
## restent figés en input neutre.
##
## FENÊTRÉ, PAS headless (voir la doc de capture_frog_cowboy.gd -- même
## piège : `get_root().get_texture()` a besoin d'un vrai swapchain) :
##   "%GODOT%" --path . --screen 1 -s res://tools/rigging/capture_frog_cowboy_fp.gd -- --out=reports/checkpoints/2026-09-26_frog_fp_ingame
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const _SETTLE_FRAMES := 120     ## joueur spawn/tombe au sol/s'équipe (FP_Draw fini).
const _POST_ACTION_SETTLE := 6  ## laisse le swapchain refléter le dernier état avant de lire la texture (même piège que capture_frog_cowboy.gd::_present_and_save).

var _out_dir: String = "res://reports/checkpoints/2026-09-26_frog_fp_ingame"
var _frame: int = 0
var _world: Node = null
var _player: PlayerController = null
var _weapon: Weapon = null
var _quit_at_frame: int = -1

## Bornes de capture (en frames depuis `_SETTLE_FRAMES`) pour chaque état --
## voir `_process` pour ce qui est pressé/relâché à chaque borne. Réglé à vue
## (60 Hz) à partir des durées authored des clips FP_* (FPArmsRig._CLIPS) :
## ADS (FP_ADS quasi instantané, ads_time Ravage = 0,2 s) se contente d'un
## court délai ; rechargement/inspection visent respectivement ~40 %/~35 % de
## leur progression réelle (voir `_frame == ` ci-dessous, lu sur
## `weapon._inv.reload_left`) plutôt qu'un délai fixe, pour rester correct
## si `resources/weapons/ravage.tres::reload_time` change.
## Presse/relâche espacés d'AU MOINS quelques frames (JAMAIS dans le même
## appel à `_process`, contrairement à un premier essai de ce script) : cette
## boucle tourne au rythme de RENDU (`SceneTree._process`), pas de la physique
## (`_physics_process`, 60 Hz fixe, où `PlayerInput.gather_from_devices` lit
## réellement `Input`) -- un press+release dans le MÊME appel peut se
## retrouver entièrement retombé avant qu'un seul tick physique n'ait eu la
## chance d'observer `is_action_just_pressed`, constaté ici sur "fire"/
## "reload" (aucune capture de rechargement produite au 1er essai alors que
## "aim", jamais relâché avant plusieurs dizaines de frames, fonctionnait).
const _IDLE_AT := 10
const _ADS_PRESS_AT := 20
const _ADS_SHOT_AT := 60          ## _ads_t (move_toward, vitesse 1/ads_time=5) atteint 0 en ~0,2 s = 12 frames ; marge large.
const _RELOAD_RELEASE_AIM_AT := 70
const _FIRE_PRESS_AT := 76  ## le chargeur spawn PLEIN -- Inventory.start_reload refuse un chargeur déjà plein, voir Inventory.gd.
const _FIRE_RELEASE_AT := 80
const _RELOAD_PRESS_AT := 84
const _RELOAD_RELEASE_AT := 88
## `FPArmsMath.should_cancel_inspect` bloque l'inspection tant que
## ViewModel._anim.reload_t (minuteur PROCÉDURAL du dip de rechargement,
## démarré par `_on_reload_started` -- 2,5 s = ravage.tres::reload_time,
## INDÉPENDANT de weapon._inv.reload_left) n'est pas retombé sous zéro --
## rechargement démarré ~frame 88, donc fini ~frame 88+150=238 (2,5 s à
## 60 Hz) : presser "inspect" AVANT ça se fait avaler par ce garde-fou
## (constaté ici -- aucune capture produite au 1er essai) sans planter, mais
## sans jamais lancer FP_Inspect non plus. Posé large (280) au-delà de 238.
const _INSPECT_PRESS_AT := 280
const _INSPECT_RELEASE_AT := 284
const _SPRINT_PRESS_AT := 420
const _SPRINT_SHOT_AT := 480
const _FINAL_QUIT_AT := 500

var _reload_shot_done: bool = false
var _reload_shot_frame: int = -1
var _inspect_shot_done: bool = false
var _inspect_press_frame: int = -1

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
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _player == null:
		return false

	var since := _frame - _SETTLE_FRAMES
	if since == _IDLE_AT:
		call_deferred("_save_current_view", "fp_arms_idle.png")
	elif since == _ADS_PRESS_AT:
		Input.action_press("aim")
	elif since == _ADS_SHOT_AT:
		call_deferred("_save_current_view", "fp_arms_ads.png")
	elif since == _RELOAD_RELEASE_AIM_AT:
		Input.action_release("aim")
	elif since == _FIRE_PRESS_AT:
		Input.action_press("fire")
	elif since == _FIRE_RELEASE_AT:
		Input.action_release("fire")
	elif since == _RELOAD_PRESS_AT:
		Input.action_press("reload")
	elif since == _RELOAD_RELEASE_AT:
		Input.action_release("reload")  # `reload_pressed` est un front, pas un maintien.
	elif since > _RELOAD_RELEASE_AT and not _reload_shot_done:
		_maybe_capture_reload_progress(since)
	elif since == _INSPECT_PRESS_AT and not _inspect_shot_done:
		Input.action_press("inspect")
		_inspect_press_frame = since
	elif since == _INSPECT_RELEASE_AT:
		Input.action_release("inspect")
	elif _inspect_press_frame >= 0 and not _inspect_shot_done:
		_maybe_capture_inspect_progress(since)
	elif since == _SPRINT_PRESS_AT:
		Input.action_press("move_forward")
	elif since == _SPRINT_SHOT_AT:
		call_deferred("_save_current_view", "fp_arms_sprint.png")
		Input.action_release("move_forward")
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
	_player = _find_human_in(get_root()) as PlayerController
	if _player == null:
		push_error("capture_frog_cowboy_fp: aucun PlayerController humain local trouvé dans l'arbre")
		return
	_weapon = _player.get_node_or_null("Weapon") as Weapon
	print("capture_frog_cowboy_fp: joueur trouvé à ", _player.global_position, " weapon=", _weapon)

func _find_human_in(node: Node) -> Node:
	var pc := node as PlayerController
	if pc and pc.is_local_human():
		return pc
	for c in node.get_children():
		var r := _find_human_in(c)
		if r:
			return r
	return null

## Capture au ~40 % de la progression du rechargement en cours (lu sur
## `weapon._inv.reload_left`/`reload_time` -- voir Inventory.gd -- plutôt
## qu'un délai fixe, pour rester correct si `reload_time` change) ; repli sur
## `_INSPECT_PRESS_AT` (délai fixe) si le rechargement n'a jamais démarré
## (arme/inventaire introuvable).
func _maybe_capture_reload_progress(since: int) -> void:
	if _weapon == null or _weapon._inv == null:
		return
	var inv: Inventory = _weapon._inv
	if not inv.reloading:
		if since > _RELOAD_PRESS_AT + 10:
			_reload_shot_done = true  # jamais démarré (arme sans rechargement ?) -- abandonne proprement.
		return
	var c := _weapon.cfg()
	var reload_time: float = c.reload_time if c else 1.0
	var reload_left: float = inv.reload_left
	var progress: float = 1.0 - (reload_left / maxf(reload_time, 0.001))
	if progress >= 0.4:
		_reload_shot_done = true
		_reload_shot_frame = since
		call_deferred("_save_current_view", "fp_arms_reload_40pct.png")

## Même principe que `_maybe_capture_reload_progress`, sur la progression du
## clip FP_Inspect -- lue via le temps écoulé depuis l'appui (l'inspection n'a
## pas d'équivalent d'Inventory.reload_left/reloading) comparé à la durée
## RÉELLE du clip (`FPArmsRig.clip_length`, jamais un nombre dupliqué en dur
## qui divergerait si le clip est réexporté).
func _maybe_capture_inspect_progress(since: int) -> void:
	var fps := float(Engine.physics_ticks_per_second) if Engine.physics_ticks_per_second > 0 else 60.0
	var elapsed := float(since - _inspect_press_frame) / fps
	var view_model := _find_view_model()
	var clip_len := 2.8  # repli si le rig/ViewModel est introuvable -- ne devrait pas arriver.
	if view_model and view_model._arms:
		clip_len = view_model._arms.clip_length("FP_Inspect")
	if elapsed >= clip_len * 0.35 or since - _inspect_press_frame > 300:
		_inspect_shot_done = true
		call_deferred("_save_current_view", "fp_arms_inspect_35pct.png")

func _find_view_model() -> ViewModel:
	if _player == null:
		return null
	return _player.camera.get_node_or_null("ViewModel") as ViewModel

func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name)
	var abs_dir := ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var err := img.save_png(path)
	print("capture_frog_cowboy_fp: ", name, " -> ", path, " (err=", err, ")")

func _save_current_view(name: String) -> void:
	for i in _POST_ACTION_SETTLE:
		await process_frame
	var img := get_root().get_texture().get_image()
	if img:
		_save(img, name)
	else:
		push_error("capture_frog_cowboy_fp: pas d'image (lancé --headless ? voir l'en-tête)")
