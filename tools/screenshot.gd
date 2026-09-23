## screenshot.gd
## Capture d'écran EN FENÊTRÉ (pas headless : il faut un vrai swapchain pour
## lire le rendu) d'une scène donnée, avec une caméra externe optionnelle
## positionnée en ligne de commande — pratique pour juger la DA sans dépendre
## d'un joueur spawné (position/orientation imprévisibles).
##
##   godot --path . -s res://tools/screenshot.gd -- \
##       --scene=res://scenes/levels/test_arena.tscn --out=C:/tmp/shot.png \
##       [--pos=x,y,z --look=x,y,z] [--wait=N] [--map_id=port_ferraille] [--mode=tdm]
##
## `--pos`/`--look` (facultatifs) : si fournis, remplace la caméra active par
## une caméra externe (utile pour les niveaux, où le joueur local ne rend de
## toute façon pas son propre corps — voir PlayerLook.gd). Sans eux, on
## capture simplement la caméra déjà active de la scène (ex. le menu
## principal, qui a la sienne).
##
## `--map_id`/`--mode` (facultatifs) : écrivent MatchConfig.map_id/mode_id
## AVANT d'instancier la scène — LevelLook.gd lit `MatchConfig.map_id` au
## moment où le WorldEnvironment de la scène entre dans l'arbre (v2 : chaque
## carte a son propre ciel/soleil/brouillard, voir Cartoon.map_palette()) ;
## sans eux, la capture utilise la carte par défaut du préréglage.
##
## Si la scène a une propriété `agent_select` (GameWorld), elle est forcée à
## `false` avant le premier `_ready` pour spawn directement, sans attendre une
## sélection d'agent qui bloquerait la capture.
##
## Écrit `SCREENSHOT_OK <out>` puis quitte (0), ou `SCREENSHOT_FAIL <raison>`
## et quitte (1).
extends SceneTree

const _LEVEL_LOOK_SCRIPT := preload("res://scripts/core/LevelLook.gd")
const _INK_POST_SCRIPT := preload("res://scripts/core/InkPost.gd")
const DEFAULT_WAIT_FRAMES := 60

var _scene_path: String = ""
var _out_path: String = ""
var _has_pos: bool = false
var _pos: Vector3 = Vector3(0, 6, 12)
var _has_look: bool = false
var _look: Vector3 = Vector3.ZERO
var _wait_frames: int = DEFAULT_WAIT_FRAMES
var _map_id: String = ""
var _mode_id: String = ""

var _started: bool = false
var _frame: int = 0
var _cam: Camera3D

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			_scene_path = a.get_slice("=", 1)
		elif a.begins_with("--out="):
			_out_path = a.get_slice("=", 1)
		elif a.begins_with("--pos="):
			_pos = _parse_vec3(a.get_slice("=", 1))
			_has_pos = true
		elif a.begins_with("--look="):
			_look = _parse_vec3(a.get_slice("=", 1))
			_has_look = true
		elif a.begins_with("--wait="):
			_wait_frames = int(a.get_slice("=", 1))
		elif a.begins_with("--map_id="):
			_map_id = a.get_slice("=", 1)
		elif a.begins_with("--mode="):
			_mode_id = a.get_slice("=", 1)

func _parse_vec3(s: String) -> Vector3:
	var parts := s.split(",")
	if parts.size() != 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))

## `MainLoop._process` : renvoyer `true` arrête le moteur, `false` continue.
func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		return _start()
	# Un joueur peut spawn en cours de route (hébergement local différé —
	# GameWorld._ready héberge et instancie via MultiplayerSpawner) et son
	# PlayerCamera se rend `current` au moment de son propre `_ready`, APRÈS
	# la nôtre. On regagne donc la main chaque frame tant qu'on attend, pour
	# être certain d'être encore actifs à la capture.
	if _cam:
		_cam.current = true
	# En jeu, InkPost (contours plein écran) n'est porté QUE par la caméra du
	# joueur LOCAL (PlayerCamera.gd) — une caméra externe comme la nôtre, ou
	# celle du menu principal, n'a normalement pas ce post-traitement. Pour
	# que les captures reflètent le rendu RÉEL du joueur (contours visibles),
	# on l'attache nous-mêmes à quelle que soit la caméra active à ce moment
	# (idempotent : ne fait rien si elle l'a déjà). Settings.ink_edges est à
	# `true` par défaut, donc InkPost s'affiche sans réglage supplémentaire.
	_ensure_ink_post()
	_frame += 1
	if _frame < _wait_frames:
		return false
	_capture()
	return true

func _ensure_ink_post() -> void:
	var cam := root.get_camera_3d()
	if cam and cam.get_node_or_null("InkPost") == null:
		var post := _INK_POST_SCRIPT.new()
		post.name = "InkPost"
		cam.add_child(post)

func _start() -> bool:
	if _scene_path.is_empty() or _out_path.is_empty():
		return _fail("--scene et --out sont requis")
	if not _map_id.is_empty():
		MatchConfig.map_id = _map_id
	if not _mode_id.is_empty():
		MatchConfig.set_mode(_mode_id)
	# `Look` (LevelLook.gd) est un autoload normalement câblé dans
	# project.godot par la tranche audio (R-E) — on le simule ici pour que
	# les captures reflètent le rendu final même avant ce câblage.
	var look: Node = _LEVEL_LOOK_SCRIPT.new()
	root.add_child(look)
	var packed := load(_scene_path) as PackedScene
	if packed == null:
		return _fail("scène introuvable : %s" % _scene_path)
	var inst := packed.instantiate()
	# Évite l'écran de sélection d'agent (GameWorld.agent_select) qui
	# bloquerait la capture en attendant une entrée utilisateur.
	if inst.get("agent_select") != null:
		inst.set("agent_select", false)
	root.add_child(inst)
	current_scene = inst
	if _has_pos:
		_cam = Camera3D.new()
		root.add_child(_cam)
		_cam.global_position = _pos
		if _has_look:
			_cam.look_at(_look, Vector3.UP)
		_cam.current = true
	return false

func _capture() -> void:
	if _cam:
		_cam.current = true
	_ensure_ink_post()
	var img := root.get_texture().get_image()
	var dir := _out_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var save_err := img.save_png(_out_path)
	if save_err != OK:
		print("SCREENSHOT_FAIL échec de l'écriture PNG (%d)" % save_err)
		quit(1)
		return
	print("SCREENSHOT_OK ", _out_path)
	quit(0)

func _fail(reason: String) -> bool:
	print("SCREENSHOT_FAIL ", reason)
	quit(1)
	return true
