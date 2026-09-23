## character_shots.gd
## Capture EN FENÊTRÉ (pas headless : il faut un vrai swapchain pour lire le
## rendu — même contrainte que tools/screenshot.gd et
## tools/blender/viewmodel_shots.gd) des 6 agents (assets/models/characters/
## <id>.glb) : recolore chaque slot matériau avec `Cartoon.character(Color)`
## (cloth = couleur d'équipe, gear/skin/accent gardent leur couleur exportée —
## même convention de correspondance par suffixe de nom que
## ViewModel.gd::_apply_cartoon_materials), joue Idle, capture une vue de
## face + 3/4, avance jusqu'à Sprint pour une capture de contrôle
## (clipping/flottement du gear), puis assemble une ligne de silhouettes
## 100% noires (les 6 côte à côte, matériau plein noir non éclairé) pour le
## test de lisibilité à 30 m.
##
## Les 46 actions sont exportées par tools/blender/make_characters.py avec
## leur nom Blender inchangé (ex. "Idle_Loop", "Sprint_Loop") ; c'est l'IMPORT
## glTF de Godot qui reconnaît le suffixe "_Loop", le retire du nom de clip
## ET met `loop_mode` en boucle automatiquement (vérifié par sondage :
## AnimationPlayer expose bien "Idle"/"Sprint", pas "Idle_Loop"/"Sprint_Loop")
## — c'est le mécanisme concret derrière "loop flags preserved".
##
##   godot --path . -s tools/character_shots.gd -- --out=<dossier>
##
## Écrit "<id>_front.png", "<id>_34.png", "<id>_sprint.png" par agent, plus
## "silhouette_lineup.png", dans <dossier>. Imprime CHAR_SHOT/CHAR_SHOTS_DONE
## ou CHAR_SHOTS_FAIL puis quitte.
extends SceneTree

const CHAR_IDS := ["vif", "choc", "roc", "guet", "baume", "verrou"]
# 3 alliés (bleu), 3 ennemis (rouge par défaut) — cloth recevant la couleur
# d'équipe (design.md §5 ; Settings.enemy_color=0 -> rouge par défaut).
const IS_ALLY := {"vif": true, "choc": true, "roc": false, "guet": false, "baume": true, "verrou": false}

const MODEL_DIR := "res://assets/models/characters/"
const SETTLE_FRAMES := 90
const SPRINT_ADVANCE_FRAMES := 24  # ~0.4s à 60 fps -> milieu de boucle Sprint_Loop (16 frames Blender @30fps = 0.53s)
# Godot ne recompose la texture du viewport qu'APRÈS le `_process` en cours :
# changer `_cam.global_position` puis appeler `get_texture()` dans le même
# appel capture donc l'image rendue avec la transform de caméra PRÉCÉDENTE
# (décalage d'une frame, constaté en jeu — la 1re capture "front" montrait un
# gros plan sur les pieds, la caméra par défaut à l'origine). On laisse donc
# quelques frames s'écouler après CHAQUE repositionnement de caméra, avant de
# capturer (cf. `_begin_shot`/phase "cam_wait").
const CAMERA_SETTLE_FRAMES := 4

const CAM_FRONT_POS := Vector3(0, 1.0, 3.1)
const CAM_34_POS := Vector3(2.1, 1.0, 2.35)
const CAM_SIL_POS := Vector3(0, 1.0, 9.5)
const CAM_LOOK := Vector3(0, 1.0, 0)

var _out_dir: String = ""
var _started: bool = false
var _frame: int = 0
var _phase: String = "setup"  # setup -> settle -> cam_wait(+callable) -> ... -> silhouette -> done
var _char_index: int = 0
var _settle_frames: int = 0
var _cam_wait_left: int = 0
var _after_cam_wait: Callable = Callable()

var _look: Node = null
var _model: Node3D = null
var _anim: AnimationPlayer = null
var _cam: Camera3D = null
var _light: DirectionalLight3D = null
var _env_node: WorldEnvironment = null

# Chargés une seule fois pour la ligne de silhouettes.
var _silhouette_models: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		return _start()
	if _cam:
		_cam.current = true
	_frame += 1

	match _phase:
		"settle":
			_settle_frames += 1
			if _settle_frames >= SETTLE_FRAMES:
				_begin_shot(CAM_FRONT_POS, CAM_LOOK, Callable(self, "_shoot_front"))
			return false
		"cam_wait":
			_cam_wait_left -= 1
			if _cam_wait_left > 0:
				return false
			return _after_cam_wait.call()
		"sprint_advance":
			_sprint_advance_left -= 1
			if _sprint_advance_left > 0:
				return false
			_begin_shot(CAM_FRONT_POS, CAM_LOOK, Callable(self, "_shoot_sprint"))
			return false
		"settle_silhouette":
			_settle_frames += 1
			if _settle_frames >= SETTLE_FRAMES:
				_begin_shot(CAM_SIL_POS, CAM_LOOK, Callable(self, "_shoot_silhouette"))
			return false
	return false


var _sprint_advance_left: int = 0


## Repositionne la caméra puis laisse `CAMERA_SETTLE_FRAMES` s'écouler (le
## rendu suit la transform avec un cran de retard — voir la constante) avant
## d'appeler `after` (qui capture, éventuellement enchaîne une animation, et
## programme la suite).
func _begin_shot(pos: Vector3, look_at_pos: Vector3, after: Callable) -> void:
	_frame_camera(pos, look_at_pos)
	_cam_wait_left = CAMERA_SETTLE_FRAMES
	_after_cam_wait = after
	_phase = "cam_wait"


func _shoot_front() -> bool:
	_capture("%s_front" % CHAR_IDS[_char_index])
	_begin_shot(CAM_34_POS, CAM_LOOK, Callable(self, "_shoot_34"))
	return false


func _shoot_34() -> bool:
	_capture("%s_34" % CHAR_IDS[_char_index])
	_anim.play("Sprint")
	_sprint_advance_left = SPRINT_ADVANCE_FRAMES
	_phase = "sprint_advance"
	return false


func _shoot_sprint() -> bool:
	_capture("%s_sprint" % CHAR_IDS[_char_index])
	_char_index += 1
	return _next_character()


func _shoot_silhouette() -> bool:
	_capture("silhouette_lineup")
	print("CHAR_SHOTS_DONE")
	quit(0)
	return true


func _start() -> bool:
	if _out_dir.is_empty():
		return _fail("--out requis")
	_look = load("res://scripts/core/LevelLook.gd").new()
	root.add_child(_look)

	_env_node = WorldEnvironment.new()
	root.add_child(_env_node)  # stylé automatiquement par Look (node_added)

	_light = DirectionalLight3D.new()
	root.add_child(_light)  # direction clé appliquée automatiquement par Look

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	ground.mesh = plane
	ground.material_override = Cartoon.world(Cartoon.PAPER_SHADE)
	root.add_child(ground)

	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.current = true

	return _load_character(_char_index)


func _next_character() -> bool:
	if _model:
		_model.queue_free()
		_model = null
		_anim = null
	if _char_index >= CHAR_IDS.size():
		return _start_silhouette_lineup()
	return _load_character(_char_index)


func _load_character(index: int) -> bool:
	var id: String = CHAR_IDS[index]
	var packed := load(MODEL_DIR + id + ".glb") as PackedScene
	if packed == null:
		return _fail("modèle introuvable : %s" % id)
	_model = packed.instantiate()
	root.add_child(_model)
	_anim = _find_anim_player(_model)
	if _anim == null:
		return _fail("AnimationPlayer introuvable pour %s" % id)
	_apply_cartoon_materials(_model, id, IS_ALLY.get(id, true))
	if not _play(_anim, "Idle"):
		return _fail("animation Idle introuvable pour %s" % id)
	_settle_frames = 0
	_phase = "settle"
	return false


func _start_silhouette_lineup() -> bool:
	var spacing := 1.3
	var start_x := -spacing * (CHAR_IDS.size() - 1) / 2.0
	for i in CHAR_IDS.size():
		var id: String = CHAR_IDS[i]
		var packed := load(MODEL_DIR + id + ".glb") as PackedScene
		if packed == null:
			return _fail("modèle introuvable (silhouette) : %s" % id)
		var inst := packed.instantiate()
		inst.position = Vector3(start_x + i * spacing, 0, 0)
		root.add_child(inst)
		_silhouette_models.append(inst)
		var anim := _find_anim_player(inst)
		if anim:
			_play(anim, "Idle")
		_apply_silhouette_material(inst)
	_settle_frames = 0
	_phase = "settle_silhouette"
	return false


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var found := _find_anim_player(c)
		if found:
			return found
	return null


## `Animation.has_animation(name)` ne couvre que la bibliothèque "" (globale) ;
## le glTF importe parfois les clips dans une bibliothèque nommée
## ("<nom>/Idle_Loop"). On essaie le nom nu puis on cherche un suffixe qui
## correspond dans toutes les bibliothèques.
func _play(anim: AnimationPlayer, name: String) -> bool:
	if anim.has_animation(name):
		anim.play(name)
		return true
	for lib_name in anim.get_animation_library_list():
		var lib := anim.get_animation_library(lib_name)
		if lib and lib.has_animation(name):
			var full := name if lib_name == "" else "%s/%s" % [lib_name, name]
			anim.play(full)
			return true
	return false


func _apply_cartoon_materials(model: Node3D, id: String, is_ally: bool) -> void:
	var cloth_color: Color = Cartoon.ally_color() if is_ally else Cartoon.enemy_color()
	for mesh in _find_mesh_instances(model):
		if mesh.mesh == null:
			continue
		mesh.extra_cull_margin = 2.0
		for i in mesh.mesh.get_surface_count():
			var mat: Material = mesh.mesh.surface_get_material(i)
			var mat_name: String = mat.resource_name if mat else ""
			if mat_name == "%s_cloth" % id:
				mesh.set_surface_override_material(i, Cartoon.character(cloth_color))
			elif mat_name.begins_with(id + "_"):
				# gear/skin/accent : couleur exportée conservée, mais toujours
				# passés par Cartoon.character() pour l'encrage + le contour.
				var src: BaseMaterial3D = mat as BaseMaterial3D
				var base_color: Color = src.albedo_color if src else Color.WHITE
				mesh.set_surface_override_material(i, Cartoon.character(base_color))


func _apply_silhouette_material(model: Node3D) -> void:
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	for mesh in _find_mesh_instances(model):
		mesh.material_override = black


func _find_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_mesh_instances(c))
	return out


func _frame_camera(pos: Vector3, look_at_pos: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(look_at_pos, Vector3.UP)
	_cam.current = true


func _capture(name: String) -> void:
	var img := root.get_texture().get_image()
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var path := "%s/%s.png" % [_out_dir, name]
	var err := img.save_png(path)
	print("CHAR_SHOT %s -> %s (err=%d)" % [name, path, err])


func _capture_silhouette() -> void:
	_capture("silhouette_lineup")


func _fail(reason: String) -> bool:
	print("CHAR_SHOTS_FAIL ", reason)
	quit(1)
	return true
