## agent_portraits.gd
## UX-20 — Outil REJOUABLE et FENÊTRÉ (vrai swapchain requis pour lire le
## rendu, même contrat que tools/character_shots.gd et
## tools/review/model_preview.gd) qui rend un PORTRAIT BUSTE par agent depuis
## assets/models/characters/<id>.glb : ink-toon + contour d'encre (même
## convention "<id>_tex" que PlayerLook.gd::_textured_character_material /
## tools/character_shots.gd::_apply_cartoon_materials — la texture 2K déjà
## peinte du modèle est CONSERVÉE, jamais repeinte en aplat blanc), fond
## couleur-clé de l'agent (aplat, AgentConfig.color), pose "Idle", export PNG
## 512×512 dans assets/ui/portraits/<id>.png.
##
## Remplace, côté cartes de sélection et vitrine du menu, la grosse initiale
## et les silhouettes blanches unies constatées le 2026-09-25 (capture
## agent_select_1920/menu_1920) — cause racine : `MainMenu.gd` recolorait le
## slot "tex" avec `albedo_color` (blanc, la vraie couleur vit dans la
## texture) au lieu de garder `albedo_texture` (corrigé dans le même ticket,
## voir MainMenu.gd::_apply_character_materials).
##
##   godot --path . -s res://tools/review/agent_portraits.gd -- [--out=DIR]
##
## `--out` : dossier de sortie, `res://...` ou chemin OS absolu (par défaut
## `res://assets/ui/portraits`, le dossier livré par cette tâche). Rejouable
## à volonté : chaque exécution écrase les 6 PNG existants sans état caché.
## Écrit "<out>/<id>.png" (id = AgentConfig.agent_name en minuscules) pour
## chacun des 6 agents de AgentDatabase.all(). Imprime "AGENT_PORTRAIT <id> ->
## <chemin>" par capture puis "AGENT_PORTRAITS_DONE" (code 0), ou
## "AGENT_PORTRAITS_FAIL <raison>" (code 1) — jamais un crash de la pipeline.
extends SceneTree

const MODEL_DIR := "res://assets/models/characters/"
const DEFAULT_OUT := "res://assets/ui/portraits"
const SHOT_SIZE := Vector2i(512, 512)

## Frames laissées à l'anim "Idle" pour se stabiliser avant la capture (même
## ordre de grandeur que tools/character_shots.gd::SETTLE_FRAMES).
const SETTLE_FRAMES := 90
## Le rendu suit la transform de caméra avec un cran de retard (constaté par
## tools/character_shots.gd) : quelques frames après le placement, avant de
## lire `root.get_texture()`.
const CAMERA_SETTLE_FRAMES := 4

## Cadrage "buste" (chef, cou, épaules, haut du torse) sur le gabarit commun
## STYLE_BIBLE.md §4.1 (1,80 m debout, col à 1,40 m, menton 1,49 m, yeux
## 1,62 m) : caméra de face, À NIVEAU (jamais de plongée/contre-plongée —
## lisibilité avant le drame), visée à mi-hauteur entre menton et yeux.
## Distance/FOV choisis pour que le champ vertical visible (2·d·tan(fov/2) ≈
## 0,83 m) couvre de ~1,14 m (haut du torse, sous le col) à ~1,96 m (au-dessus
## du sommet du crâne, marge de sécurité).
const CAM_HEIGHT := 1.55
const CAM_DISTANCE := 1.55
const CAM_FOV := 30.0

## Énergie du soleil — sa DIRECTION et sa COULEUR sont entièrement reprises
## par l'autoload "Look" (LevelLook.gd::_apply_key_light, câblé sur
## `node_added` DANS TOUT L'ARBRE, y compris celui d'un outil `SceneTree`) dès
## que la lumière entre dans l'arbre ; seule `light_energy` reste à notre
## charge (LevelLook ne la touche pas).
const SUN_ENERGY := 1.15
## Ambiance neutre (jamais teintée par le fond couleur-clé, WYSIWYG
## STYLE_BIBLE.md §1.1 "Un hex de la palette est ce qu'on voit au soleil") —
## seul le FOND porte la couleur de l'agent, pas l'éclairage du personnage.
const AMBIENT_COLOR := Color(0.92, 0.9, 0.86)
const AMBIENT_ENERGY := 0.85
## Nom posé par LevelLook.gd::_add_backdrop (anneau de silhouettes lointaines,
## 150-600 m) sur CHAQUE WorldEnvironment ajouté à un arbre, carte ou pas —
## retiré ici (voir `_strip_stray_backdrop`) : un portrait buste veut un aplat
## couleur-clé PROPRE, jamais une silhouette de décor à l'horizon.
const BACKDROP_NODE_NAME := "Backdrop"

var _out_dir: String = DEFAULT_OUT
var _agents: Array = []
var _env: Environment = null
var _cam: Camera3D = null
var _model: Node3D = null
var _anim: AnimationPlayer = null
var _started := false
var _index: int = 0
var _phase := "settle"  # settle -> cam_wait -> (capture + charge le suivant)
var _settle_left := 0
var _cam_wait_left := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)
	_agents = AgentDatabase.all()


func _process(_delta: float) -> bool:
	_strip_stray_backdrop()
	if not _started:
		_started = true
		return _start()
	match _phase:
		"settle":
			_settle_left -= 1
			if _settle_left <= 0:
				_cam_wait_left = CAMERA_SETTLE_FRAMES
				_phase = "cam_wait"
			return false
		"cam_wait":
			_cam_wait_left -= 1
			if _cam_wait_left > 0:
				return false
			_capture_current()
			_index += 1
			return _load_next()
	return false


func _start() -> bool:
	if _agents.is_empty():
		return _fail("AgentDatabase.all() est vide")
	root.mode = Window.MODE_WINDOWED
	DisplayServer.window_set_size(SHOT_SIZE)
	root.size = SHOT_SIZE
	_build_stage()
	_index = 0
	return _load_next()


func _build_stage() -> void:
	var sun := DirectionalLight3D.new()
	root.add_child(sun)  # LevelLook fixe direction/couleur/ombre dès l'ajout.
	sun.light_energy = SUN_ENERGY

	var we := WorldEnvironment.new()
	root.add_child(we)
	# LevelLook a DÉJÀ remplacé `we.environment` de façon SYNCHRONE (autoload
	# "Look", branché sur `node_added` -- constaté à la 1re génération : le
	# fond restait le ciel procédural de carte au lieu de l'aplat couleur-clé
	# demandé). On récupère CETTE instance plutôt que d'en poser une neuve
	# ignorée, et on la force en aplat (STYLE_BIBLE.md, UX-20).
	_env = we.environment
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = AMBIENT_COLOR
	_env.ambient_light_energy = AMBIENT_ENERGY
	_env.fog_enabled = false  # jamais de brume sur un aplat couleur-clé.
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	_cam = Camera3D.new()
	_cam.fov = CAM_FOV
	# `global_position`/`look_at` exigent un nœud DÉJÀ dans l'arbre (sinon
	# `get_global_transform()` échoue silencieusement, constaté à l'exécution) :
	# `add_child` d'abord, la transform ensuite.
	root.add_child(_cam)
	_cam.global_position = Vector3(0.0, CAM_HEIGHT, CAM_DISTANCE)
	_cam.look_at(Vector3(0.0, CAM_HEIGHT, 0.0), Vector3.UP)
	_cam.current = true


## LevelLook.gd::_add_backdrop pose un anneau de silhouettes lointaines
## (150-600 m) en enfant DIFFÉRÉ de `root` dès qu'un WorldEnvironment entre
## dans l'arbre, carte de jeu ou pas -- jamais désiré sur un aplat couleur-clé
## de portrait. Appelé CHAQUE frame (`_process`) : le `call_deferred` de
## LevelLook peut n'avoir pris effet qu'à la frame suivant `_build_stage()`.
## Idempotent (`get_node_or_null` renvoie null une fois le nœud libéré) --
## LevelLook ne le repose jamais deux fois sur le même `root` (métadonnée
## `_backdrop_pending`, voir sa docstring).
func _strip_stray_backdrop() -> void:
	var stray := root.get_node_or_null(BACKDROP_NODE_NAME)
	if stray:
		stray.queue_free()


## Charge l'agent `_index` (queue_free l'ancien modèle d'abord). `_index` est
## déjà >= _agents.size() une fois les 6 agents traités : imprime le
## marqueur de succès et quitte proprement.
func _load_next() -> bool:
	if _model:
		_model.queue_free()
		_model = null
		_anim = null
	if _index >= _agents.size():
		print("AGENT_PORTRAITS_DONE")
		quit(0)
		return true

	var agent: AgentConfig = _agents[_index]
	var id: String = agent.agent_name.to_lower()
	var path := "%s%s.glb" % [MODEL_DIR, id]
	if not ResourceLoader.exists(path):
		return _fail("modèle introuvable : %s" % path)
	var packed := load(path) as PackedScene
	if packed == null:
		return _fail("scène invalide : %s" % path)
	_model = packed.instantiate() as Node3D
	if _model == null:
		return _fail("racine 3D introuvable : %s" % path)
	root.add_child(_model)

	_anim = _find_anim_player(_model)
	if _anim == null:
		return _fail("AnimationPlayer introuvable pour %s" % id)
	_apply_portrait_materials(_model)
	if not _play_idle(_anim):
		return _fail("animation Idle introuvable pour %s" % id)

	# Fond couleur-clé de l'agent (aplat) — l'éclairage du personnage reste neutre.
	_env.background_color = agent.color

	_settle_left = SETTLE_FRAMES
	_phase = "settle"
	return false


## UN SEUL matériau `<id>_tex` par agent (export Tripo riggé, docs/
## 3D_PIPELINE.md) : sa texture 2K déjà peinte est CONSERVÉE (jamais
## repeinte en aplat) — même convention que PlayerLook.gd::
## _textured_character_material / tools/character_shots.gd::
## _apply_cartoon_materials / tools/review/model_preview.gd::_restyle.
## Contour d'encre posé ensuite via Cartoon.apply_team_outline (allié, jamais
## la coque de surbrillance ennemie — un portrait de sélection n'a pas de
## camp).
func _apply_portrait_materials(model: Node3D) -> void:
	for mesh in _find_mesh_instances(model):
		if mesh.mesh == null:
			continue
		mesh.extra_cull_margin = 2.0
		for i in mesh.mesh.get_surface_count():
			var src: Material = mesh.mesh.surface_get_material(i)
			var m := Cartoon.character_surface(&"outfit", Color.WHITE)
			var base := src as BaseMaterial3D
			if base:
				m.set_shader_parameter("albedo_color", base.albedo_color)
				if base.albedo_texture != null:
					m.set_shader_parameter("use_albedo_texture", true)
					m.set_shader_parameter("use_triplanar", false)
					m.set_shader_parameter("albedo_texture", base.albedo_texture)
			mesh.set_surface_override_material(i, m)
		Cartoon.apply_team_outline(mesh, false)


## `Animation.has_animation(name)` ne couvre que la bibliothèque "" (globale) ;
## le glTF importe parfois les clips dans une bibliothèque nommée — on essaie
## le nom nu puis un suffixe qui correspond dans toutes les bibliothèques
## (même repli que tools/character_shots.gd::_play).
func _play_idle(anim: AnimationPlayer) -> bool:
	if anim.has_animation("Idle"):
		anim.play("Idle")
		return true
	for lib_name in anim.get_animation_library_list():
		var lib := anim.get_animation_library(lib_name)
		if lib and lib.has_animation("Idle"):
			anim.play("Idle" if lib_name == "" else "%s/Idle" % lib_name)
			return true
	return false


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var found := _find_anim_player(c)
		if found:
			return found
	return null


func _find_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_mesh_instances(c))
	return out


func _capture_current() -> void:
	var agent: AgentConfig = _agents[_index]
	var id: String = agent.agent_name.to_lower()
	var img := root.get_texture().get_image()
	var out_path := _globalize("%s/%s.png" % [_out_dir, id])
	var dir := out_path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(out_path)
	print("AGENT_PORTRAIT %s -> %s (err=%d)" % [id, out_path, err])


## Même idiome que tools/review/ui_shots.gd::_globalize : `--out=res://…`
## (défaut) doit résoudre vers un chemin OS réel pour DirAccess/save_png,
## un chemin OS déjà absolu (fourni par run_review.ps1) passe inchangé.
func _globalize(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") else path


func _fail(reason: String) -> bool:
	printerr("AGENT_PORTRAITS_FAIL %s" % reason)
	quit(1)
	return true
