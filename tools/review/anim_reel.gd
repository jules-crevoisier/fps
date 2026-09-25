## Capture d'une « bande démo » d'animations, UN CLIP À LA FOIS : pour chaque
## clip (Idle, Walk, Jog_Fwd, Sprint, Pistol_Shoot, Roll), tous les agents
## demandés sont alignés côte à côte en train de jouer CE clip, rendus avec
## le look du jeu (Cartoon + LevelLook), animation pilotée image par image
## (seek) pour un GIF fluide.
##
## Nombre d'images par clip = arrondi(durée × 30 i/s) — PAS une valeur fixe :
## chaque clip boucle donc sur sa propre durée réelle (Idle 75, Walk 40,
## Jog_Fwd 28, Sprint 20 à ce jour). Les clips « uniques » (qui ne bouclent
## pas en jeu : Pistol_Shoot, Roll) tiennent leur dernière image 10 images de
## plus avant de reboucler dans le GIF, pour ne pas couper sec sur le geste.
## Les clips qui bouclent en jeu capturent EN PLUS une image de contrôle
## « <tag>_wrap.png » (image 0 vue une image après la fin du clip) que
## anim_gif.py compare à l'image 0 pour détecter un raccord qui saute
## (LOOP_FAIL dans summary.md).
##
##   godot --path . -s tools/review/anim_reel.gd -- --ids=verrou,vif --out=DIR
## puis : python tools/review/anim_gif.py DIR  (un GIF par clip + « equipe »
## + summary.md listant les LOOP_FAIL)
## Fenêtré obligatoire (lecture du swapchain), comme tools/character_shots.gd.
extends SceneTree

## anim_name, libellé FR affiché au-dessus de la rangée, boucle en jeu (true)
## ou clip unique (false : pas de contrôle de raccord, tient la dernière
## image FRAMES_HOLD images de plus).
const CLIPS := [
	["Idle", "Repos", true],
	["Walk", "Marche", true],
	["Jog_Fwd", "Jog", true],
	["Sprint", "Sprint", true],
	["Pistol_Shoot", "Tir", false],
	["Roll", "Roulade", false],
]
const LINEUP_ANIM := "Dance"
const FPS := 30.0
## Clips uniques (non bouclés en jeu) : images de tenue avant de reboucler.
const HOLD_FRAMES := 10
const SPACING := 1.3
const IS_ALLY := {"vif": true, "choc": true, "vanne": false, "guet": false, "roseau": true, "verrou": false}

var _ids: Array = []
var _out := ""
var _model_dir := ""  # --dir=<dossier absolu> : charge <id>.glb à l'exécution (GLTFDocument) au lieu de res://
var _clip_filter: Array = []  # --clips=Idle,Walk : ne rend que ces clips (défaut : tous)
var _cam: Camera3D
var _stage: Node3D
var _players: Array = []
var _frame := -1
var _warm := 0
var _clip_index := 0
var _tag := ""
var _plan: Array = []  # [{name: String, t: float}, ...] — une entrée par image à sauver
var _lineup_done := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			_ids = a.get_slice("=", 1).split(",")
		elif a.begins_with("--out="):
			_out = a.get_slice("=", 1)
		elif a.begins_with("--dir="):
			_model_dir = a.get_slice("=", 1)
		elif a.begins_with("--clips="):
			_clip_filter = a.get_slice("=", 1).split(",")
	DisplayServer.window_set_size(Vector2i(1280, 560))


func _process(_d: float) -> bool:
	if _stage == null:
		_setup()
		_begin_clip()
		return false
	if _warm < 6:
		_warm += 1
		_seek_all(0.0)
		return false
	if _frame >= 0:
		_save(_plan[_frame]["name"])
	_frame += 1
	if _frame >= _plan.size():
		return _next_clip()
	_seek_all(_plan[_frame]["t"])
	return false


func _next_clip() -> bool:
	_clip_index += 1
	if _clip_index < _active_clips().size():
		_begin_clip()
		return false
	if not _lineup_done:
		_lineup_done = true
		_load_lineup()
		return false
	print("REEL_DONE")
	quit(0)
	return true


func _active_clips() -> Array:
	if _clip_filter.is_empty():
		return CLIPS
	var out: Array = []
	for c in CLIPS:
		if _clip_filter.has(c[0]):
			out.append(c)
	return out


func _setup() -> void:
	root.add_child(load("res://scripts/core/LevelLook.gd").new())
	root.add_child(WorldEnvironment.new())
	root.add_child(DirectionalLight3D.new())
	_stage = Node3D.new()
	root.add_child(_stage)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 30)
	ground.mesh = plane
	ground.material_override = Cartoon.world(Cartoon.PAPER_SHADE)
	root.add_child(ground)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.fov = 38.0
	_cam.global_position = Vector3(0, 1.15, 4.9)
	_cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	_cam.current = true


func _clear() -> void:
	for c in _stage.get_children():
		c.queue_free()
	_players.clear()
	_frame = -1
	_warm = 0
	_plan = []


func _begin_clip() -> void:
	_clear()
	var clip: Array = _active_clips()[_clip_index]
	var anim_name: String = clip[0]
	var label: String = clip[1]
	var loop: bool = clip[2]
	_tag = anim_name.to_lower()
	var start_x := -SPACING * (_ids.size() - 1) / 2.0
	for i in _ids.size():
		_spawn(_ids[i], Vector3(start_x + i * SPACING, 0, 0), anim_name, String(_ids[i]).capitalize())
	_add_title(label)
	_plan = _build_plan(_measured_length(), loop)


func _load_lineup() -> void:
	_clear()
	_tag = "equipe"
	var start_x := -SPACING * (_ids.size() - 1) / 2.0
	for i in _ids.size():
		_spawn(_ids[i], Vector3(start_x + i * SPACING, 0, 0), LINEUP_ANIM, String(_ids[i]).capitalize())
	_plan = _build_plan(_measured_length(), true)


func _measured_length() -> float:
	return _players[0].current_animation_length if not _players.is_empty() else 0.0


## Une entrée par image à sauver, dans l'ordre où elle doit être capturée :
## - `n` images normales, une par image de la durée réelle du clip (30 i/s) ;
## - si le clip boucle en jeu : + 1 image de contrôle « <tag>_wrap » (une
##   image après la fin — sert à vérifier le raccord 0/N+1 dans anim_gif.py) ;
## - sinon (clip unique) : + HOLD_FRAMES images tenant la dernière pose, pour
##   ne pas couper sec quand le GIF reboucle à l'infini.
func _build_plan(len: float, loop: bool) -> Array:
	var n := maxi(roundi(len * FPS), 1)
	var plan: Array = []
	for i in n:
		plan.append({"name": "%s_%03d" % [_tag, i], "t": i / FPS})
	if loop:
		plan.append({"name": "%s_wrap" % _tag, "t": n / FPS})
	else:
		var hold_t: float = (n - 1) / FPS
		for h in HOLD_FRAMES:
			plan.append({"name": "%s_%03d" % [_tag, n + h], "t": hold_t})
	return plan


func _add_title(text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 56
	l.outline_size = 14
	l.modulate = Color(0.96, 0.93, 0.86)
	l.outline_modulate = Color(0.1, 0.08, 0.07)
	l.position = Vector3(0, 2.55, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.0042
	_stage.add_child(l)


func _spawn(id: String, pos: Vector3, anim_name: String, label: String) -> void:
	var model: Node3D = _load_model(id)
	model.position = pos
	model.rotation.y = deg_to_rad(-22.0)
	_stage.add_child(model)
	_restyle(model, id)
	var ap := _find_ap(model)
	if ap and not ap.has_animation(anim_name) and ap.has_animation(anim_name + "_Loop"):
		anim_name += "_Loop"
	if ap and ap.has_animation(anim_name):
		ap.play(anim_name)
		ap.pause()
		_players.append(ap)
	var l := Label3D.new()
	l.text = label
	l.font_size = 44
	l.outline_size = 12
	l.modulate = Color(0.96, 0.93, 0.86)
	l.outline_modulate = Color(0.1, 0.08, 0.07)
	l.position = pos + Vector3(0, 2.05, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.0036
	_stage.add_child(l)


func _seek_all(t: float) -> void:
	for ap: AnimationPlayer in _players:
		var len := ap.current_animation_length
		ap.seek(fmod(t, len) if len > 0.0 else 0.0, true)


func _restyle(model: Node3D, id: String) -> void:
	var cloth: Color = Cartoon.ally_color() if IS_ALLY.get(id, true) else Cartoon.enemy_color()
	for mesh in _meshes(model):
		if mesh.mesh == null:
			continue
		mesh.extra_cull_margin = 2.0
		for i in mesh.mesh.get_surface_count():
			var mat: Material = mesh.mesh.surface_get_material(i)
			var n: String = mat.resource_name if mat else ""
			var src := mat as BaseMaterial3D
			if n.ends_with("_tex") and src:
				var m := Cartoon.character(Color.WHITE)
				m.set_shader_parameter("paint_grain_strength", 0.0)
				m.set_shader_parameter("albedo_color", src.albedo_color)
				if src.albedo_texture:
					m.set_shader_parameter("use_albedo_texture", true)
					m.set_shader_parameter("use_triplanar", false)
					m.set_shader_parameter("albedo_texture", src.albedo_texture)
				mesh.set_surface_override_material(i, m)
			elif n == "%s_cloth" % id:
				mesh.set_surface_override_material(i, Cartoon.character(cloth))
			elif src:
				mesh.set_surface_override_material(i, Cartoon.character(src.albedo_color))


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_ap(c)
		if f:
			return f
	return null


func _save(name: String) -> void:
	if not DirAccess.dir_exists_absolute(_out):
		DirAccess.make_dir_recursive_absolute(_out)
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])


func _load_model(id: String) -> Node3D:
	if _model_dir.is_empty():
		return (load("res://assets/models/characters/%s.glb" % id) as PackedScene).instantiate()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file("%s/%s.glb" % [_model_dir, id], state)
	if err != OK:
		push_error("anim_reel : lecture impossible de %s/%s.glb (%d)" % [_model_dir, id, err])
		return Node3D.new()
	return doc.generate_scene(state) as Node3D
