## render_parity_godot.gd
## Rendu Godot de "parity_scene" (art/style/toon_style.json v2) : même caméra,
## mêmes objets (sphère/cube/Verrou/sol), même style ToonStyle -- comparé au
## rendu Blender équivalent (art/style/blender/render_parity.py) par
## tools/style/compare_parity.py. FENÊTRÉ volontairement (le contrat de tâche
## le demande explicitement) : un swapchain réel donne un rendu plus proche du
## jeu qu'un `--headless` (SSAO/ombres/tonemap passent par le même chemin GPU
## que la fenêtre de jeu, jamais garanti identique en mode dummy) -- voir aussi
## tests/rendering/test_ink_toon_params.gd, qui documente cette même limite
## pour l'ancien pipeline ("il faut un vrai swapchain").
##
## Usage :
##   "%GODOT%" --path . -s res://tools/style/render_parity_godot.gd -- --out reports/checkpoints/2026-09-26_toon_bd/parity_godot.png
##
## (PAS `--headless` : voir ci-dessus. La fenêtre peut rester ouverte/petite,
## le script se ferme de lui-même une fois la capture écrite.)
extends SceneTree

const _STYLE_PATH := "res://art/style/toon_style.json"
const _VERROU_PATH := "res://assets/models/characters/verrou.glb"
const _DEFAULT_OUT := "res://reports/checkpoints/2026-09-26_toon_bd/parity_godot.png"
## Frames à laisser passer avant la capture -- ombres/SSAO/TAA ont besoin de
## quelques frames pour converger, un vrai swapchain fenêtré (pas headless)
## peut aussi prendre 1-2 frames de plus à présenter sa première image réelle.
const _WARMUP_FRAMES := 12

var _out_path: String = _DEFAULT_OUT
var _frame: int = 0
var _root: Node3D
var _cam: Camera3D

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_path = a.get_slice("=", 1)

func _process(_delta: float) -> bool:
	if _frame == 0:
		_build_scene()
	_frame += 1
	if _frame <= _WARMUP_FRAMES:
		return false
	_capture_and_quit()
	return false

func _load_style() -> Dictionary:
	var f := FileAccess.open(_STYLE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func _hex(v: String, fallback: Color = Color.WHITE) -> Color:
	return Color(v) if not v.is_empty() else fallback

func _build_scene() -> void:
	var style := _load_style()
	var scene_cfg: Dictionary = style.get("parity_scene", {})
	var objects: Array = scene_cfg.get("objects", [])
	var cam_cfg: Dictionary = scene_cfg.get("camera", {})
	var res: Array = scene_cfg.get("resolution", [1280, 720])

	_root = Node3D.new()
	get_root().add_child(_root)

	var we := WorldEnvironment.new()
	_root.add_child(we)
	var sun := DirectionalLight3D.new()
	_root.add_child(sun)
	ToonStyle.setup_environment(we, sun)

	for obj_cfg in objects:
		_spawn_object(obj_cfg)

	_cam = Camera3D.new()
	_root.add_child(_cam)
	var cam_pos: Array = cam_cfg.get("position", [0.0, 1.4, 3.2])
	var look_at: Array = cam_cfg.get("look_at", [0.0, 0.9, 0.0])
	_cam.fov = cam_cfg.get("fov_v_deg", 45.0)
	_cam.position = Vector3(cam_pos[0], cam_pos[1], cam_pos[2])
	_cam.look_at(Vector3(look_at[0], look_at[1], look_at[2]), Vector3.UP)
	_cam.current = true
	ToonStyle.add_outline_pass(_cam)

	var win := get_root()
	win.size = Vector2i(int(res[0]), int(res[1]))

func _spawn_object(cfg: Dictionary) -> void:
	var kind: String = cfg.get("type", "")
	var pos: Array = cfg.get("position", [0.0, 0.0, 0.0])
	var position := Vector3(pos[0], pos[1], pos[2])
	var rot_y := deg_to_rad(float(cfg.get("rotation_y_deg", 0.0)))

	if kind == "model":
		var packed := load(_VERROU_PATH) as PackedScene
		if packed == null:
			return
		var inst := packed.instantiate() as Node3D
		_root.add_child(inst)
		inst.position = position
		inst.rotation.y = rot_y
		ToonStyle.apply_to(inst)
		return

	var mesh_inst := MeshInstance3D.new()
	var albedo := _hex(cfg.get("albedo", "#FFFFFF"))
	match kind:
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = float(cfg.get("radius", 0.45))
			sphere.height = sphere.radius * 2.0
			mesh_inst.mesh = sphere
		"cube":
			var box := BoxMesh.new()
			var size := float(cfg.get("size", 0.7))
			box.size = Vector3.ONE * size
			mesh_inst.mesh = box
		"plane":
			var plane := PlaneMesh.new()
			var size := float(cfg.get("size", 8.0))
			plane.size = Vector2(size, size)
			mesh_inst.mesh = plane
		_:
			return
	_root.add_child(mesh_inst)
	mesh_inst.position = position
	mesh_inst.rotation.y = rot_y
	mesh_inst.material_override = ToonStyle.toon_material(null, albedo)

func _capture_and_quit() -> void:
	# `get_root().get_texture()` renvoie `null` en `--headless` (pilote de rendu
	# "dummy", jamais de vraie image -- ERR_FAIL confirmé à l'exécution) : garde
	# explicite pour ne JAMAIS reboucler indéfiniment dans `_process` (une
	# erreur de script en plein milieu de cette fonction, non rattrapée,
	# abandonne juste CET appel sans jamais atteindre `quit()` plus bas -- vécu
	# ici avant cette garde). Ce script est documenté FENÊTRÉ (pas headless,
	# voir l'en-tête) précisément pour cette raison.
	var viewport_tex := get_root().get_texture()
	if viewport_tex == null:
		push_error("render_parity_godot: aucune texture de viewport (lancé en --headless ? ce script doit tourner FENÊTRE, voir l'en-tête)")
		quit(1)
		return
	var img := viewport_tex.get_image()
	if img == null:
		push_error("render_parity_godot: get_image() a échoué")
		quit(1)
		return
	var dir := _out_path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var err := img.save_png(_out_path)
	if err != OK:
		push_error("render_parity_godot: save_png a échoué (%s) -> %s" % [err, _out_path])
		quit(1)
		return
	print("render_parity_godot: capture ecrite -> ", _out_path)
	quit(0)
