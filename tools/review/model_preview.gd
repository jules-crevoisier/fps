## model_preview.gd
## Aperçu EN JEU d'un modèle importé (ex. export Tripo Studio) avant intégration :
## charge un .glb à l'exécution (GLTFDocument, aucun import Godot requis — le
## dossier assets/incoming/ est ignoré par l'éditeur), le recale à la hauteur du
## gabarit commun (1,80 m, docs/STYLE_BIBLE.md §4), remplace ses matériaux par
## le shader encré du jeu en conservant sa texture (Cartoon.character_surface +
## contour d'équipe), puis photographie face / trois-quarts / profil / dos /
## gros plan à côté d'une capsule témoin de la hitbox (rayon 0,40 m).
##
##   godot --path . -s res://tools/review/model_preview.gd -- --in=C:/chemin/modele.glb [--out=DIR] [--enemy]
##
## Écrit <out>/<nom>_<vue>.png et <out>/<nom>_planche.png, imprime
## MODEL_PREVIEW_DONE <planche> (code 0) ou MODEL_PREVIEW_FAIL <raison> (code 1).
## Fenêtré obligatoire (il faut un vrai swapchain pour lire le rendu).
extends SceneTree

const TARGET_HEIGHT := 1.8
const CAPSULE_RADIUS := 0.4
const SHOT_SIZE := Vector2i(720, 900)
const WARMUP_FRAMES := 45
const CAMERA_SETTLE_FRAMES := 4
const SAND := Color("#D2A46C")
const SKY_TOP := Color("#2F74D8")
const SKY_HORIZON := Color("#BFDDF2")
const SUN := Color("#FFE9C4")

const VIEWS := [
	{"name": "face", "pos": Vector3(0.0, 1.05, 3.4), "look": Vector3(0.0, 0.95, 0.0)},
	{"name": "trois_quarts", "pos": Vector3(2.4, 1.15, 2.4), "look": Vector3(0.0, 0.95, 0.0)},
	{"name": "profil", "pos": Vector3(3.4, 1.05, 0.0), "look": Vector3(0.0, 0.95, 0.0)},
	{"name": "dos", "pos": Vector3(0.0, 1.05, -3.4), "look": Vector3(0.0, 0.95, 0.0)},
	{"name": "gros_plan", "pos": Vector3(0.55, 1.62, 1.25), "look": Vector3(0.0, 1.55, 0.0)},
]

var _in_path := ""
var _out_dir := ""
var _is_enemy := false
var _model_name := ""
var _camera: Camera3D
var _frame := 0
var _view_index := -1
var _settle_left := 0
var _shots: Array[Image] = []
var _started := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--in="):
			_in_path = arg.substr(5)
		elif arg.begins_with("--out="):
			_out_dir = arg.substr(6)
		elif arg == "--enemy":
			_is_enemy = true
	if _in_path.is_empty() or not FileAccess.file_exists(_in_path):
		_fail("fichier introuvable : %s" % _in_path)
		return
	_model_name = _in_path.get_file().get_basename()
	if _out_dir.is_empty():
		_out_dir = _in_path.get_base_dir().path_join(_model_name + "_preview")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(SHOT_SIZE)
	root.size = SHOT_SIZE


func _process(_delta: float) -> bool:
	# Construction au premier tick : pendant _initialize la racine n'est pas
	# encore dans l'arbre, les global_transform (et donc l'AABB) seraient faux.
	if not _started:
		_build_stage()
		if not _load_model():
			return true
		_started = true
		return false
	_frame += 1
	if _frame < WARMUP_FRAMES:
		return false
	if _settle_left > 0:
		_settle_left -= 1
		if _settle_left == 0:
			var img := root.get_texture().get_image()
			img.save_png(_out_dir.path_join("%s_%s.png" % [_model_name, VIEWS[_view_index]["name"]]))
			_shots.append(img)
		return false
	_view_index += 1
	if _view_index >= VIEWS.size():
		_write_sheet()
		return true
	var v: Dictionary = VIEWS[_view_index]
	_camera.global_position = v["pos"]
	_camera.look_at(v["look"], Vector3.UP)
	_settle_left = CAMERA_SETTLE_FRAMES
	return false


func _build_stage() -> void:
	var stage := Node3D.new()
	root.add_child(stage)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_TOP
	sky_mat.sky_horizon_color = SKY_HORIZON
	sky_mat.ground_horizon_color = SKY_HORIZON
	sky_mat.ground_bottom_color = SAND.darkened(0.2)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	stage.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_color = SUN
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	stage.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	ground.mesh = plane
	ground.material_override = Cartoon.world(SAND)
	stage.add_child(ground)

	# Capsule témoin de la hitbox commune, posée à côté du modèle.
	var hitbox := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = TARGET_HEIGHT
	hitbox.mesh = capsule
	hitbox.material_override = Cartoon.character(Color("#8A8F99"))
	hitbox.position = Vector3(-1.1, TARGET_HEIGHT * 0.5, 0.0)
	stage.add_child(hitbox)

	_camera = Camera3D.new()
	_camera.fov = 40.0
	stage.add_child(_camera)
	_camera.current = true


func _load_model() -> bool:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(_in_path, state)
	if err != OK:
		_fail("import glTF impossible (%s)" % error_string(err))
		return false
	var scene := doc.generate_scene(state) as Node3D
	if scene == null:
		_fail("scène glTF vide")
		return false
	root.add_child(scene)

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(scene, meshes)
	if meshes.is_empty():
		_fail("aucun maillage dans le fichier")
		return false

	var box := AABB()
	var first := true
	for mi in meshes:
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if box.size.y <= 0.001:
		_fail("hauteur nulle")
		return false
	var s := TARGET_HEIGHT / box.size.y
	scene.scale = Vector3.ONE * s
	var center := box.get_center() * s
	scene.position = Vector3(-center.x, -box.position.y * s, -center.z)

	for mi in meshes:
		_restyle(mi)
	print("MODEL_PREVIEW_INFO hauteur_source=%.3f m echelle=%.3f largeur=%.2f m profondeur=%.2f m" % [
		box.size.y, s, box.size.x * s, box.size.z * s])
	return true


func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


## Remplace chaque surface par le shader encré du jeu en gardant la texture
## d'albédo du fichier (UV, pas de triplanar : le personnage bouge).
func _restyle(mi: MeshInstance3D) -> void:
	for i in range(mi.mesh.get_surface_count()):
		var src := mi.get_active_material(i)
		var m := Cartoon.character_surface(&"outfit", Color.WHITE)
		if src is BaseMaterial3D:
			var bm := src as BaseMaterial3D
			m.set_shader_parameter("albedo_color", bm.albedo_color)
			if bm.albedo_texture != null:
				m.set_shader_parameter("use_albedo_texture", true)
				m.set_shader_parameter("use_triplanar", false)
				m.set_shader_parameter("albedo_texture", bm.albedo_texture)
		mi.set_surface_override_material(i, m)
	Cartoon.apply_team_outline(mi, _is_enemy)


func _write_sheet() -> void:
	if _shots.is_empty():
		_fail("aucune capture")
		return
	var w := 0
	var h := 0
	for img in _shots:
		w = maxi(w, img.get_width())
		h = maxi(h, img.get_height())
	var sheet := Image.create(w * _shots.size(), h, false, Image.FORMAT_RGBA8)
	for i in _shots.size():
		var img := _shots[i]
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i * w, 0))
	var path := _out_dir.path_join("%s_planche.png" % _model_name)
	sheet.save_png(path)
	print("MODEL_PREVIEW_DONE %s" % path)
	quit(0)


func _fail(reason: String) -> void:
	printerr("MODEL_PREVIEW_FAIL %s" % reason)
	quit(1)
