## style_masks.gd
## Produit les MASQUES de la revue automatisée (docs/STYLE_BIBLE.md §11.1,
## tâche ART-03) que tools/review/style_check.py consomme pour isoler le HUD,
## les personnages et le viewmodel dans les captures existantes (map_shots/
## ui_shots/char_ingame_shots/fp_shots) avant de calculer les seuils couleur
## (CHK-02, CHK-04 à CHK-06, CHK-18, CHK-20 à CHK-22, CHK-40...). Capture EN
## FENÊTRÉ (swapchain requis — même contrainte que ui_shots.gd/
## char_ingame_shots.gd/fp_shots.gd) : héberge UN SEUL match TDM avec bots sur
## scenes/levels/maps/port_ferraille.tscn — même carte, même mode et même
## stratagème `agent_select=false` que tools/char_ingame_shots.gd, POUR QUE
## les masques "personnages" s'alignent sur ses captures bot_<n>_tp.png :
## `_pick_bot`/`_frame_camera_on` ci-dessous sont le même algorithme (même
## ordre de bot, même distances de cadrage), donc le pixel (x,y) d'un masque
## personnages_mask_bot_<n>.png correspond au même pixel de bot_<n>_tp.png
## produit par char_ingame_shots.gd dans la même exécution de run_review.ps1.
##
##   godot --path . -s res://tools/review/style_masks.gd -- [--out=C:/dossier/]
##
## Écrit, sous <out>/ :
##   hud_mask_1920x1080.png, hud_mask_1280x720.png
##     Masque HUD (§11.1 : "rectangles des Control visibles") : un rectangle
##     blanc pour chaque Control VISIBLE et de taille non nulle sous le
##     CanvasLayer "HUD" du joueur local (GameHUD), sur fond noir —
##     Image.fill_rect par Control, jamais un rendu 3D. La fenêtre est
##     RÉELLEMENT redimensionnée à chaque résolution (comme ui_shots.gd :
##     `window/stretch/mode="canvas_items"` fait re-fluer les ancrages Control
##     à la vraie taille de fenêtre) puis remise à sa taille d'origine —
##     aucune mise à l'échelle linéaire approximative des rectangles.
##   personnages_mask_bot_<n>.png (n = 1..BOT_SHOTS)
##     Masque "personnages" (§11.1 : "rendu d'un ID de calque") : silhouette
##     blanche pleine du MeshInstance3D unique de
##     CharacterBody.get_body_mesh() (scripts/player/CharacterBody.gd — un
##     seul mesh à 5 surfaces par agent) pour le bot n, sur fond noir uni :
##     matériau non éclairé blanc en `material_override`, mesh et caméra
##     basculés sur un calque de rendu dédié (`MASK_RENDER_LAYER`, distinct de
##     celui de fp_shots.gd/ViewModel pour ne jamais entrer en conflit si les
##     deux scripts tournaient dans le même process), environnement fond noir
##     forcé — même stratagème que tools/fp_shots.gd::_enter_mask_mode.
##   viewmodel_mask.png
##     Masque viewmodel (§11.1) : silhouette blanche pleine de l'arme+gants du
##     joueur LOCAL, obtenue via l'API PUBLIQUE `ViewModel.set_mask_mode(true)`
##     (déjà utilisée par tools/fp_shots.gd — même calque
##     `VIEWMODEL_MASK_RENDER_LAYER = 20`, dupliqué ici comme fp_shots.gd
##     duplique la constante privée de ViewModel), même cadrage que le
##     local_fp.png de char_ingame_shots.gd.
##   style_masks.json : {"hud": [{"resolution": "1920x1080"|"1280x720",
##     "path"}, ...], "personnages": [{"index": int, "path", "found": bool},
##     ...], "viewmodel": {"path": String, "found": bool}, "done": bool}
##
## Si le joueur local, son HUD, un bot ou son ViewModel sont introuvables, le
## masque correspondant est simplement omis (`found: false` pour
## personnages/viewmodel, entrée absente pour hud) et imprimé en
## `STYLE_MASK_SKIP <genre> <raison>` — jamais un échec de tout le script :
## une revue partielle (ex. -Quick, sans bots) doit quand même produire ce
## qu'elle peut. Imprime `STYLE_MASK <genre> -> <chemin>` par masque écrit
## puis `STYLE_MASKS_DONE` (0), ou `STYLE_MASKS_FAIL <raison>` (1) si le
## bootstrap lui-même échoue (carte introuvable, etc.).
extends SceneTree

const LEVEL := "res://scenes/levels/maps/port_ferraille.tscn"
const DEFAULT_OUT := "C:/Users/srko/AppData/Local/Temp/claude/C--Users-srko-Desktop-fps/02e156fb-5e66-4722-9835-071a024d62a9/scratchpad/shots/style_masks"

## Mêmes constantes que tools/char_ingame_shots.gd (voir sa doc de classe) —
## dupliquées ici (pas de dépendance croisée entre scripts `-s`) pour que les
## deux scripts choisissent EXACTEMENT les mêmes bots au même instant logique.
const BOT_SHOTS := 3
const BOT_SHOT_INTERVAL := 8.0
const INITIAL_SETTLE := 6.0
const CAMERA_SETTLE_FRAMES := 4

## Même paire de résolutions que tools/review/ui_shots.gd (Design.md v2 §12).
const HUD_RESOLUTIONS: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1280, 720)]
## Re-flow des ancrages Control après un resize de fenêtre — même valeur que
## ui_shots.gd::RESIZE_SETTLE_FRAMES.
const HUD_RESIZE_SETTLE_FRAMES := 12
## Calque dédié à la silhouette "personnages" — DISTINCT de
## ViewModel._MASK_RENDER_LAYER (20, voir tools/fp_shots.gd) pour ne jamais
## se marcher dessus si un jour les deux masques étaient produits dans le
## même process.
const CHARACTER_MASK_RENDER_LAYER := 21
## ViewModel._MASK_RENDER_LAYER (scripts/player/ViewModel.gd), dupliqué comme
## le fait déjà tools/fp_shots.gd (voir sa doc de classe).
const VIEWMODEL_MASK_RENDER_LAYER := 20
const VIEWMODEL_MASK_SETTLE_FRAMES := 5
const CHARACTER_MASK_SETTLE_FRAMES := 5

var _out_dir: String = DEFAULT_OUT
var _started := false
var _failed := false
var _world: Node = null
var _spectator_cam: Camera3D
var _local_player: Node = null
var _hud: CanvasLayer = null
var _mask_material: StandardMaterial3D
var _mask_env: Environment
var _native_window_size: Vector2i = Vector2i.ZERO

var _t: float = 0.0
var _phase: String = "settle"
# settle -> hud_resize(i) -> hud_settle(i) -> hud_capture(i) -> ... ->
# hud_restore -> bot_wait -> bot_mask_setup -> bot_mask_settle ->
# bot_mask_capture -> ... -> viewmodel_wait -> viewmodel_mask_setup ->
# viewmodel_mask_settle -> viewmodel_mask_capture -> done
var _hud_res_index: int = 0
var _settle_frames: int = 0
var _cam_wait_left: int = 0
var _after_cam_wait: Callable = Callable()
var _bot_shot_index: int = 0
var _next_bot_shot_t: float = INITIAL_SETTLE
var _current_bot_mesh: MeshInstance3D = null
var _current_bot_prev: Dictionary = {}

var _hud_masks: Array = []
var _personnages_masks: Array = []
var _viewmodel_mask: Dictionary = {"found": false}
var _viewmodel_prev_cull_mask: int = 0
var _viewmodel_prev_environment: Environment = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		return _start()
	if _failed:
		return true
	_t += delta

	match _phase:
		"hud_resize":
			root.size = HUD_RESOLUTIONS[_hud_res_index]
			_settle_frames = 0
			_phase = "hud_settle"
			return false
		"hud_settle":
			_settle_frames += 1
			if _settle_frames < HUD_RESIZE_SETTLE_FRAMES:
				return false
			_write_hud_mask(HUD_RESOLUTIONS[_hud_res_index])
			_hud_res_index += 1
			_phase = "hud_resize" if _hud_res_index < HUD_RESOLUTIONS.size() else "hud_restore"
			return false
		"hud_restore":
			root.size = _native_window_size
			_phase = "bot_wait"
			return false
		"bot_wait":
			if _t >= _next_bot_shot_t:
				_begin_bot_mask()
			return false
		"cam_wait":
			_cam_wait_left -= 1
			if _cam_wait_left > 0:
				return false
			return _after_cam_wait.call()
		"bot_mask_settle":
			_settle_frames += 1
			if _settle_frames < CHARACTER_MASK_SETTLE_FRAMES:
				return false
			_capture_bot_mask()
			return false
		"viewmodel_mask_settle":
			_settle_frames += 1
			if _settle_frames < VIEWMODEL_MASK_SETTLE_FRAMES:
				return false
			_capture_viewmodel_mask()
			return false
	return false


func _start() -> bool:
	MatchConfig.mode_id = "tdm"
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 3
	MatchConfig.bot_difficulty = MatchConfig.Difficulty.VETERAN

	var net := NetworkManager.get_net(self)
	net.host()

	if not ResourceLoader.exists(LEVEL):
		return _fail("carte introuvable : %s" % LEVEL)
	var scene: PackedScene = load(LEVEL)
	_world = scene.instantiate()
	if _world.get("agent_select") != null:
		_world.set("agent_select", false)
	_world.set("allow_bot_fill", true)
	root.add_child(_world)
	current_scene = _world

	_spectator_cam = Camera3D.new()
	root.add_child(_spectator_cam)

	_mask_material = StandardMaterial3D.new()
	_mask_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mask_material.albedo_color = Color.WHITE

	_mask_env = Environment.new()
	_mask_env.background_mode = Environment.BG_COLOR
	_mask_env.background_color = Color.BLACK

	_native_window_size = Vector2i(root.get_visible_rect().size)
	_phase = "hud_resize"
	print("STYLE_MASKS_START level=%s" % LEVEL)
	return false


# ==========================================================================
#  HUD — rectangles des Control visibles (aucun rendu 3D)
# ==========================================================================

func _find_hud(n: Node) -> CanvasLayer:
	if n is CanvasLayer and n.name == "HUD":
		return n as CanvasLayer
	for c in n.get_children():
		var r := _find_hud(c)
		if r:
			return r
	return null


func _fill_control_rects(n: Node, img: Image, bounds: Vector2i) -> void:
	if n is Control:
		var c := n as Control
		if c.visible and c.size.x > 0.5 and c.size.y > 0.5:
			var r := c.get_global_rect()
			var x0 := clampi(int(round(r.position.x)), 0, bounds.x)
			var y0 := clampi(int(round(r.position.y)), 0, bounds.y)
			var w := clampi(int(round(r.size.x)), 0, bounds.x - x0)
			var h := clampi(int(round(r.size.y)), 0, bounds.y - y0)
			if w > 0 and h > 0:
				img.fill_rect(Rect2i(x0, y0, w, h), Color.WHITE)
	for child in n.get_children():
		_fill_control_rects(child, img, bounds)


func _write_hud_mask(res: Vector2i) -> void:
	if _hud == null:
		_hud = _find_hud(_world)
	var img := Image.create(res.x, res.y, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	if _hud:
		_fill_control_rects(_hud, img, res)
	else:
		print("STYLE_MASK_SKIP hud HUD (CanvasLayer) introuvable sous la carte")
	_ensure_out_dir()
	var name := "hud_mask_%dx%d" % [res.x, res.y]
	var path := "%s/%s.png" % [_out_dir, name]
	var err := img.save_png(path)
	print("STYLE_MASK hud -> %s (err=%d)" % [path, err])
	_hud_masks.append({"resolution": "%dx%d" % [res.x, res.y], "path": path})


# ==========================================================================
#  Personnages — un calque de rendu dédié, comme fp_shots.gd pour le viewmodel
# ==========================================================================

## Identique à tools/char_ingame_shots.gd::_pick_bot (même ordre, même
## repli cyclique) — condition d'alignement documentée en tête de fichier.
func _pick_bot(index: int) -> Node3D:
	var players := _world.get_node_or_null(_world.players_root) if _world else null
	if players == null:
		return null
	var bots: Array = []
	for p in players.get_children():
		if bool(p.get("is_bot")):
			bots.append(p)
	if bots.is_empty():
		return null
	return bots[(index - 1) % bots.size()] as Node3D


## Identique à tools/char_ingame_shots.gd::_frame_camera_on (même cadrage 3/4
## arrière, même filet anti-obstruction) — voir sa doc pour le détail.
const _FRAME_DISTANCES := [3.0, 2.0, 1.2, 0.7]

func _frame_camera_on(body: Node3D) -> void:
	var back := body.global_transform.basis.z
	var side := body.global_transform.basis.x
	var look_pos := body.global_position + Vector3(0, 1.1, 0)
	var space := root.get_world_3d().direct_space_state
	var chosen := body.global_position + back * _FRAME_DISTANCES[-1] + side * 0.5 + Vector3(0, 1.7, 0)
	for dist in _FRAME_DISTANCES:
		var d: float = dist
		var candidate: Vector3 = body.global_position + back * d + side * (d * 0.45) + Vector3(0, 1.6, 0)
		var query := PhysicsRayQueryParameters3D.create(look_pos, candidate)
		query.exclude = [body]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			chosen = candidate
			break
	_spectator_cam.global_position = chosen
	_spectator_cam.look_at(look_pos, Vector3.UP)
	_spectator_cam.current = true


func _begin_bot_mask() -> void:
	_bot_shot_index += 1
	_next_bot_shot_t = _t + BOT_SHOT_INTERVAL
	var bot := _pick_bot(_bot_shot_index)
	if bot == null:
		print("STYLE_MASK_SKIP personnages aucun bot trouvé pour l'index %d" % _bot_shot_index)
		_advance_after_bot_mask()
		return
	var body := bot.get_node_or_null("%CharacterModel") as CharacterBody
	var mesh := body.get_body_mesh() if body else null
	if mesh == null:
		print("STYLE_MASK_SKIP personnages bot %d : CharacterBody/mesh introuvable (modèle pas encore livré ?)" % _bot_shot_index)
		_advance_after_bot_mask()
		return
	_frame_camera_on(bot)
	_current_bot_mesh = mesh
	_current_bot_prev = {
		"layers": mesh.layers,
		"material_override": mesh.material_override,
		"cull_mask": _spectator_cam.cull_mask,
		"environment": _spectator_cam.environment,
	}
	mesh.material_override = _mask_material
	mesh.layers = 1 << (CHARACTER_MASK_RENDER_LAYER - 1)
	_spectator_cam.cull_mask = 1 << (CHARACTER_MASK_RENDER_LAYER - 1)
	_spectator_cam.environment = _mask_env
	_settle_frames = 0
	_begin_cam_wait(Callable(self, "_enter_bot_mask_settle"))


func _enter_bot_mask_settle() -> bool:
	_phase = "bot_mask_settle"
	_settle_frames = 0
	return false


func _capture_bot_mask() -> void:
	var name := "personnages_mask_bot_%d" % _bot_shot_index
	_ensure_out_dir()
	var path := "%s/%s.png" % [_out_dir, name]
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	print("STYLE_MASK personnages -> %s (err=%d)" % [path, err])
	_personnages_masks.append({"index": _bot_shot_index, "path": path, "found": true})
	_current_bot_mesh.material_override = _current_bot_prev["material_override"]
	_current_bot_mesh.layers = _current_bot_prev["layers"]
	_spectator_cam.cull_mask = _current_bot_prev["cull_mask"]
	_spectator_cam.environment = _current_bot_prev["environment"]
	_current_bot_mesh = null
	_current_bot_prev = {}
	_advance_after_bot_mask()


func _advance_after_bot_mask() -> void:
	if _bot_shot_index >= BOT_SHOTS:
		_begin_viewmodel_mask()
	else:
		_phase = "bot_wait"


# ==========================================================================
#  Viewmodel — même API publique que tools/fp_shots.gd (ViewModel.set_mask_mode)
# ==========================================================================

func _begin_viewmodel_mask() -> void:
	_local_player = get_first_node_in_group("local_player")
	if _local_player == null:
		print("STYLE_MASK_SKIP viewmodel joueur local introuvable")
		_finish()
		return
	var cam: Camera3D = _local_player.get("camera")
	var view_model: ViewModel = cam.get_node_or_null("ViewModel") if cam else null
	if cam == null or view_model == null:
		print("STYLE_MASK_SKIP viewmodel caméra/ViewModel introuvable sur le joueur local")
		_finish()
		return
	if _hud == null:
		_hud = _find_hud(_world)
	_viewmodel_prev_cull_mask = cam.cull_mask
	_viewmodel_prev_environment = cam.environment
	view_model.set_mask_mode(true)
	cam.cull_mask = 1 << (VIEWMODEL_MASK_RENDER_LAYER - 1)
	cam.environment = _mask_env
	if _hud:
		_hud.visible = false
	cam.current = true
	_settle_frames = 0
	_phase = "viewmodel_mask_settle"


func _capture_viewmodel_mask() -> void:
	var cam: Camera3D = _local_player.get("camera")
	var view_model: ViewModel = cam.get_node_or_null("ViewModel") if cam else null
	_ensure_out_dir()
	var path := "%s/viewmodel_mask.png" % _out_dir
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	print("STYLE_MASK viewmodel -> %s (err=%d)" % [path, err])
	_viewmodel_mask = {"path": path, "found": true}
	if view_model:
		view_model.set_mask_mode(false)
	if cam:
		cam.cull_mask = _viewmodel_prev_cull_mask
		cam.environment = _viewmodel_prev_environment
	if _hud:
		_hud.visible = true
	_finish()


# ==========================================================================
#  Utilitaires
# ==========================================================================

func _begin_cam_wait(after: Callable) -> void:
	_cam_wait_left = CAMERA_SETTLE_FRAMES
	_after_cam_wait = after
	_phase = "cam_wait"


func _ensure_out_dir() -> void:
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)


func _write_result_json() -> void:
	var data := {
		"hud": _hud_masks,
		"personnages": _personnages_masks,
		"viewmodel": _viewmodel_mask,
		"done": true,
	}
	_ensure_out_dir()
	var path := "%s/style_masks.json" % _out_dir
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


func _finish() -> void:
	_write_result_json()
	print("STYLE_MASKS_DONE")
	quit(0)


func _fail(reason: String) -> bool:
	_failed = true
	print("STYLE_MASKS_FAIL ", reason)
	quit(1)
	return true
