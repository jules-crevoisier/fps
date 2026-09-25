## beauty_shot.gd
## ART-82 (docs/art/WASTELAND_ART_RESET.md « Coin beauté d'abord ») : capture
## EN FENÊTRÉ (swapchain réel requis, comme tools/screenshot.gd/
## tools/map_shots.gd -- jamais headless) de scenes/dev/beauty_corner.tscn à
## 1920×1080 SANS HUD (scène de dev autonome, Node3D pur : aucun GameHUD
## n'entre jamais dans cet arbre, contrairement à une vraie scène de niveau,
## donc rien à masquer ici, à la différence de tools/map_shots.gd::_hide_hud),
## mesure le FPS moyen sur la caméra fixe de la scène (FrameStats.gd, la même
## classe pure que tools/review/perf_bench.gd/l'overlay F3), puis écrit une
## planche côte à côte avec .orchestrator/refs/wasteland_hero.png (sa moitié
## basse -- la vue de rue, sans le bandeau carte/titre du haut).
##
##   godot --path . -s res://tools/review/beauty_shot.gd -- \
##       [--out=C:/dossier/] [--warmup=90] [--measure=120]
##
## Écrit "<out>/beauty_corner.png" (capture brute) et "<out>/side_by_side.png"
## (planche), imprime `BEAUTY_SHOT_FPS avg_fps=.. threshold=120 pass=true|false`
## puis `BEAUTY_SHOT_OK <side_by_side>` et quitte (0), ou `BEAUTY_SHOT_FAIL
## <raison>` (1) sur un échec de rendu/écriture -- JAMAIS sur le seuil FPS
## lui-même (contrat ART-82 : « la planche est montrée à l'utilisateur, qui
## valide ou annote » -- le gate est humain, pas ce script ; `pass=false`
## reste visible dans la sortie, imprimé avant `BEAUTY_SHOT_OK`).
extends SceneTree

const _LEVEL_LOOK_SCRIPT := preload("res://scripts/core/LevelLook.gd")
const _INK_POST_SCRIPT := preload("res://scripts/core/InkPost.gd")
const _SCENE_PATH := "res://scenes/dev/beauty_corner.tscn"
const _REF_PATH := "res://.orchestrator/refs/wasteland_hero.png"

const RENDER_SIZE := Vector2i(1920, 1080)
const DEFAULT_WARMUP_FRAMES := 90
const DEFAULT_MEASURE_FRAMES := 120
const FPS_THRESHOLD := 120.0

## Moitié basse de la planche de référence (la vue de rue, sans le bandeau
## carte/titre du haut) -- bornes mesurées UNE FOIS sur le PNG source (bandeau
## quasi noir jusqu'à y=356, la photo débute à y=357 ; largeur pleine,
## 711 px) : le fichier de référence ne bouge pas, jamais recalculées à la
## volée.
const _REF_PHOTO_RECT := Rect2i(0, 357, 711, 229)
const _BOARD_GAP_PX := 24
const _BOARD_BG := Color(0.09, 0.09, 0.1, 1.0)

var _out_dir: String = ""
var _warmup_frames: int = DEFAULT_WARMUP_FRAMES
var _measure_frames: int = DEFAULT_MEASURE_FRAMES

var _started := false
var _failed := false
var _frame := 0
var _stats: FrameStats
var _scene_inst: Node


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path("res://reports/beauty")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)
		elif a.begins_with("--warmup="):
			_warmup_frames = int(a.get_slice("=", 1))
		elif a.begins_with("--measure="):
			_measure_frames = int(a.get_slice("=", 1))


## `MainLoop._process` : renvoyer `true` arrête le moteur, `false` continue.
func _process(delta: float) -> bool:
	if not _started:
		_started = true
		return _start()
	if _failed:
		return true
	_ensure_ink_post()
	_frame += 1
	if _frame <= _warmup_frames:
		return false
	_stats.add(delta * 1000.0)
	if _stats.count() < _measure_frames:
		return false
	return _finish()


func _start() -> bool:
	DisplayServer.window_set_size(RENDER_SIZE)
	root.size = RENDER_SIZE
	# Simule l'autoload "Look" (LevelLook.gd, déjà câblé dans project.godot,
	# mais jamais instancié automatiquement dans ce contexte SceneTree
	# scripté) -- même convention que tools/screenshot.gd/tools/map_shots.gd.
	var look: Node = _LEVEL_LOOK_SCRIPT.new()
	root.add_child(look)
	var packed := load(_SCENE_PATH) as PackedScene
	if packed == null:
		return _fail("scène introuvable : %s" % _SCENE_PATH)
	_scene_inst = packed.instantiate()
	root.add_child(_scene_inst)
	current_scene = _scene_inst
	_stats = FrameStats.new(_measure_frames)
	return false


## En jeu, InkPost (contours plein écran) n'est porté QUE par la caméra du
## joueur LOCAL -- une caméra externe comme celle de beauty_corner.tscn ne
## l'a pas par défaut. On l'attache nous-mêmes (idempotent), même geste que
## tools/screenshot.gd/tools/map_shots.gd, pour que la capture reflète le
## rendu RÉEL du joueur (contours encrés visibles).
func _ensure_ink_post() -> void:
	var cam := root.get_camera_3d()
	if cam and cam.get_node_or_null("InkPost") == null:
		var post := _INK_POST_SCRIPT.new()
		post.name = "InkPost"
		cam.add_child(post)


func _finish() -> bool:
	var avg_fps := _stats.avg_fps()
	var mine := root.get_texture().get_image()
	mine.convert(Image.FORMAT_RGBA8)
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var shot_path := _out_dir.path_join("beauty_corner.png")
	var err := mine.save_png(shot_path)
	if err != OK:
		return _fail("échec écriture PNG (%d) : %s" % [err, shot_path])
	print("BEAUTY_SHOT_CAPTURE ", shot_path)

	var board_path := _out_dir.path_join("side_by_side.png")
	if not _write_side_by_side(mine, board_path):
		return _fail("échec planche côte à côte : %s" % board_path)
	print("BEAUTY_SHOT_BOARD ", board_path)

	var pass_fps := avg_fps >= FPS_THRESHOLD
	print("BEAUTY_SHOT_FPS avg_fps=%.1f threshold=%.0f pass=%s" % [avg_fps, FPS_THRESHOLD, str(pass_fps)])
	print("BEAUTY_SHOT_OK ", board_path)
	quit(0)
	return true


## Planche côte à côte (contrat : « une planche côte à côte avec
## .orchestrator/refs/wasteland_hero.png ») : la référence (sa moitié basse,
## `_REF_PHOTO_RECT`) est mise à l'échelle sur la MÊME hauteur que la
## capture (`mine`, gardée à sa résolution native 1920×1080) -- comparaison
## directe possible malgré la faible résolution native de la référence
## (229 px de haut) ; agrandissement en CUBIC (adapté à l'AGRANDISSEMENT --
## contrairement à LANCZOS, réservé par la doc Godot 4.7 au rétrécissement).
func _write_side_by_side(mine: Image, out_path: String) -> bool:
	var ref_full := Image.load_from_file(_REF_PATH)
	if ref_full == null:
		return false
	var ref_photo := ref_full.get_region(_REF_PHOTO_RECT)
	var target_h := mine.get_height()
	var ref_w := int(round(float(ref_photo.get_width()) * float(target_h) / float(ref_photo.get_height())))
	ref_photo.resize(ref_w, target_h, Image.INTERPOLATE_CUBIC)
	ref_photo.convert(Image.FORMAT_RGBA8)

	var board_w := mine.get_width() + _BOARD_GAP_PX + ref_photo.get_width()
	var board := Image.create_empty(board_w, target_h, false, Image.FORMAT_RGBA8)
	board.fill(_BOARD_BG)
	board.blit_rect(mine, Rect2i(Vector2i.ZERO, mine.get_size()), Vector2i.ZERO)
	board.blit_rect(ref_photo, Rect2i(Vector2i.ZERO, ref_photo.get_size()),
		Vector2i(mine.get_width() + _BOARD_GAP_PX, 0))
	return board.save_png(out_path) == OK


func _fail(reason: String) -> bool:
	print("BEAUTY_SHOT_FAIL ", reason)
	_failed = true
	quit(1)
	return true
