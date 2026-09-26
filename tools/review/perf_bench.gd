## perf_bench.gd
## Benchmark de performance EN FENÊTRÉ (swapchain requis, comme
## tools/map_shots.gd) pour la REVIEW PIPELINE (docs/REVIEW.md) : pour
## chaque map de MapCatalog.all() (filtrée par --maps=), charge la scène
## exactement comme tools/map_shots.gd (agent_select + allow_bot_fill
## désactivés — vue "salle vide" déterministe), puis fait voler une caméra
## externe le long d'un chemin déterministe (orbite aérienne 60 % du temps,
## puis une passe à hauteur de joueur à travers le centre de la carte 40 %
## du temps) pendant --seconds secondes (défaut 8) de MESURE après une
## courte chauffe non comptabilisée.
##
## Métriques par map (moyennées sur les frames de mesure, via FrameStats —
## scripts/core/FrameStats.gd, la même classe pure que l'overlay F3) : fps
## moyen, "1 % low", p99 du temps de frame, draw calls / primitives / objets
## (RenderingServer, mêmes appels que scripts/core/PerfOverlay.gd), le temps
## de rendu GPU mesuré (`RenderingServer.viewport_get_measured_render_time_gpu`,
## activé une fois pour toutes via `viewport_set_measure_render_time` — doc
## Godot 4.7 "RenderingServer" : reflète l'utilisation GPU même si le
## framerate est plafonné, contrairement au delta de frame CPU ci-dessus),
## et la mémoire vidéo si le moniteur `Performance` correspondant existe dans
## cette build de Godot (lookup dynamique par ClassDB — voir
## `_video_mem_monitor_id` — pour ne jamais dépendre à la compilation d'une
## constante qui pourrait ne pas exister sur toutes les versions 4.x).
##
##   godot --path . -s res://tools/review/perf_bench.gd -- \
##       --out=C:/dossier/ [--seconds=8] [--maps=cargo_ship,wasteland]
##
## Écrit "<out>/perf.json" :
##   {"seconds_per_map": 8.0,
##    "maps": [{"id", "avg_fps", "low_1pct_fps", "p99_frame_ms",
##              "draw_calls_avg", "primitives_avg", "objects_avg",
##              "gpu_ms_avg", "video_mem_mb", "frames_sampled"}, ...],
##    "errors": [{"id", "reason"}, ...]}
## Imprime `PERF_BENCH_MAP <id> avg_fps=.. low1=.. p99_ms=.. draw_calls=..`
## par map puis `PERF_BENCH_DONE` et quitte (0) — une map qui échoue à
## charger est journalisée dans "errors" et sautée, jamais fatale (contrat :
## ce script quitte toujours 0, le gate se juge dans report.py).
##
## -- Mode A/B `--toggle-uniform=<shader>:<param>` (tâche OPS-11, comble le
## trou signalé par ART-07 : « rien ne mesure le coût GPU d'un shader ») --
##   godot --path . -s res://tools/review/perf_bench.gd -- \
##       --out=C:/dossier/ --toggle-uniform=ink_edges:crease_enabled
## `<shader>` est un nom court résolu par `_SHADER_NAME_TO_PATH` (les shaders
## que Cartoon.gd/InkPost.gd utilisent réellement en jeu) ; `<param>` est le
## nom EXACT de l'uniform dans le fichier .gdshader. Pour CHAQUE map, la
## scène est rejouée deux fois de suite, sur EXACTEMENT le même vol de
## caméra déterministe que le mode normal (directement comparable) :
##   1. « avec » (`measure_a`) : tel quel, la valeur actuellement portée par
##      chaque ShaderMaterial trouvé utilisant ce shader (celle que le
##      matériau porte déjà — jamais réécrite avant cette passe) ;
##   2. « sans » (`measure_b`) : CE paramètre forcé à sa valeur neutre
##      (`false` pour un bool, `0`/`0.0` pour un entier/flottant — la
##      convention de "désactivé" de tous les shaders du dépôt, voir
##      ink_toon.gdshader/ink_edges.gdshader : `*_strength`/`*_enabled` à 0
##      = totalement inactif), sur CHAQUE matériau trouvé, puis restauré à
##      l'identique après la mesure.
## `gpu_ms_delta = avec.gpu_ms_avg - sans.gpu_ms_avg` (ms, positif si le
## réglage actuellement en jeu coûte plus cher que désactivé). Résolution
## RÉELLEMENT 1920×1080 (`_TOGGLE_WINDOW_SIZE`, imposée par
## `DisplayServer.window_set_size` UNIQUEMENT dans ce mode — jamais en mode
## normal, dont le project.godot le configure à 1280×800 réels
## (`window_width/height_override`) : changer cette résolution changerait
## aussi le fps/draw_calls du mode normal, comparés par `docs/REVIEW.md` à
## des seuils/régressions existants hors de mon périmètre). Le paramètre du
## matériau original (avant toute bascule) sert de référence "avec" ; s'il
## n'a jamais été explicitement posé sur l'instance, `RenderingServer.
## shader_get_parameter_default` (doc Godot 4.7) donne la valeur par défaut
## du SHADER lui-même — la restauration finale réapplique explicitement
## cette valeur (équivalent au non-réglage initial, jamais un état différent
## laissé après coup).
## Écrit en plus, dans "<out>/perf.json" : `"toggle_uniform": {"shader",
## "param"}` et, par map, `"shader"/"param"/"with_gpu_ms_avg"/
## "without_gpu_ms_avg"/"gpu_ms_delta"/"with_avg_fps"/"without_avg_fps"/
## "materials_toggled"` À LA PLACE des champs `avg_fps`/... habituels (mode
## normal ET mode A/B ne se mélangent jamais dans un seul run). Imprime
## `PERF_BENCH_TOGGLE <id> avec_gpu_ms=.. sans_gpu_ms=.. delta_ms=..` par map.
## `_fail()` (aucun matériau trouvé pour <shader>, paramètre introuvable ou
## d'un type non bool/numérique) garde le même contrat que le reste du
## fichier : quitte TOUJOURS 0 après avoir journalisé `PERF_BENCH_FAIL`.
extends SceneTree

const _LEVEL_LOOK_SCRIPT := preload("res://scripts/core/LevelLook.gd")
const _INK_POST_SCRIPT := preload("res://scripts/core/InkPost.gd")
const DEFAULT_SECONDS := 8.0
const WARMUP_SECONDS := 1.5

## Fraction de --seconds passée en orbite aérienne avant la passe centrale.
const ORBIT_FRACTION := 0.6
const EYE_HEIGHT := 1.6

## -- Mode A/B (--toggle-uniform=<shader>:<param>) ---------------------------
## Noms courts -> chemin réel, limité aux shaders que le jeu utilise
## effectivement via Cartoon.gd/InkPost.gd (assets/shaders/*.gdshader).
const _SHADER_NAME_TO_PATH: Dictionary = {
	"ink_toon": "res://assets/shaders/ink_toon.gdshader",
	"ink_edges": "res://assets/shaders/ink_edges.gdshader",
	"ink_outline": "res://assets/shaders/ink_outline.gdshader",
	"ink_sky": "res://assets/shaders/ink_sky.gdshader",
}
## Résolution imposée UNIQUEMENT en mode A/B — voir l'en-tête de fichier
## ("Résolution RÉELLEMENT 1920×1080").
const _TOGGLE_WINDOW_SIZE := Vector2i(1920, 1080)

var _out_dir: String = ""
var _seconds: float = DEFAULT_SECONDS
var _map_filter: PackedStringArray = []

var _toggle_active: bool = false
var _toggle_shader_name: String = ""
var _toggle_param_name: String = ""
var _toggle_materials: Array = []  # [{"material": ShaderMaterial, "original_value", "off_value"}]
var _pass_a_result: Dictionary = {}
var _pass_b_result: Dictionary = {}

var _maps: Array = []
var _map_index: int = 0
var _cam: Camera3D
var _current_scene_inst: Node
var _started: bool = false
var _failed: bool = false

# État de la map en cours.
var _phase: String = "warmup"  # warmup -> measure[_a] -> (warmup_b -> measure_b ->) map suivante
var _phase_t: float = 0.0
var _bounds_center: Vector3 = Vector3.ZERO
var _bounds_span: float = 20.0
var _stats: FrameStats
var _draw_calls_sum: float = 0.0
var _objects_sum: float = 0.0
var _primitives_sum: float = 0.0
var _video_mem_sum: float = 0.0
var _gpu_ms_sum: float = 0.0
var _sample_count: int = 0
var _video_mem_monitor_id: int = -1
var _gpu_viewport_rid: RID

var _results: Array = []
var _errors: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)
		elif a.begins_with("--seconds="):
			_seconds = float(a.get_slice("=", 1))
		elif a.begins_with("--maps="):
			_map_filter = a.get_slice("=", 1).split(",")
		elif a.begins_with("--toggle-uniform="):
			var spec := a.get_slice("=", 1)
			var parts := spec.split(":")
			if parts.size() == 2 and not parts[0].is_empty() and not parts[1].is_empty():
				_toggle_active = true
				_toggle_shader_name = parts[0]
				_toggle_param_name = parts[1]


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		return _start()
	if _failed:
		return true
	if _cam:
		_cam.current = true
	_ensure_ink_post()

	match _phase:
		"warmup", "warmup_b":
			_phase_t += delta
			_fly_camera(_phase_t)
			if _phase_t >= WARMUP_SECONDS:
				if _phase == "warmup":
					# Recensé une seule fois par map, juste avant sa toute
					# première mesure ("avec") — voir `_prepare_toggle_
					# materials`. `warmup_b` réutilise la MÊME liste (déjà
					# forcée "sans" par `_apply_toggle_state(true)` avant d'y
					# entrer, voir le bloc "measure_a" plus bas).
					if _toggle_active:
						_prepare_toggle_materials()
						if _failed:
							return true
					_phase = "measure_a" if _toggle_active else "measure"
				else:
					_phase = "measure_b"
				_phase_t = 0.0
				_stats = FrameStats.new(4096)
				_reset_accumulators()
			return false
		"measure", "measure_a", "measure_b":
			_phase_t += delta
			_stats.add(delta * 1000.0)
			_sample_render_info()
			_fly_camera(WARMUP_SECONDS + _phase_t)
			if _phase_t < _seconds:
				return false
			if _phase == "measure_a":
				_pass_a_result = _snapshot_pass()
				_apply_toggle_state(true)  # force l'état "sans" pour la 2e passe
				_phase = "warmup_b"
				_phase_t = 0.0
				_fly_camera(0.0)
				return false
			if _phase == "measure_b":
				_pass_b_result = _snapshot_pass()
				_apply_toggle_state(false)  # restaure l'état "avec" d'origine
			_finish_current_map()
			return _advance()
	return false


func _start() -> bool:
	if _toggle_active and not _SHADER_NAME_TO_PATH.has(_toggle_shader_name):
		return _fail("--toggle-uniform : shader inconnu '%s' (attendu l'un de %s)" % [_toggle_shader_name, _SHADER_NAME_TO_PATH.keys()])
	if _toggle_active:
		# Voir l'en-tête de fichier : imposé SEULEMENT en mode A/B, jamais en
		# mode normal (dont le fps/draw_calls est comparé par docs/REVIEW.md
		# à des seuils/régressions établis à la résolution de project.godot).
		DisplayServer.window_set_size(_TOGGLE_WINDOW_SIZE)
	# Doc Godot 4.7 "RenderingServer" : le temps GPU n'est mesurable qu'après
	# activation explicite sur le viewport -- inconditionnel (coût négligeable
	# quand rien ne le lit) pour que `gpu_ms_avg` soit toujours disponible,
	# mode normal comme mode A/B.
	_gpu_viewport_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_gpu_viewport_rid, true)

	var look: Node = _LEVEL_LOOK_SCRIPT.new()
	root.add_child(look)
	_maps = MapCatalog.all()
	if not _map_filter.is_empty():
		_maps = _maps.filter(func(m): return _map_filter.has(String(m["id"])))
	if _maps.is_empty():
		return _fail("MapCatalog.all() est vide (ou --maps= ne correspond à rien)")
	if _out_dir.is_empty():
		return _fail("--out requis")
	_video_mem_monitor_id = _find_video_mem_monitor_id()
	_cam = Camera3D.new()
	root.add_child(_cam)
	_cam.current = true
	return _load_map(0)


func _load_map(index: int) -> bool:
	if index >= _maps.size():
		_write_report()
		print("PERF_BENCH_DONE")
		quit(0)
		return true
	_map_index = index
	var entry: Dictionary = _maps[index]
	var map_id := String(entry["id"])
	MatchConfig.map_id = map_id
	var packed := load(String(entry["scene"])) as PackedScene
	if packed == null:
		_errors.append({"id": map_id, "reason": "scène introuvable : %s" % entry["scene"]})
		return _load_map(index + 1)
	if _current_scene_inst and is_instance_valid(_current_scene_inst):
		_current_scene_inst.queue_free()
	var inst := packed.instantiate()
	# Même convention que tools/map_shots.gd : vue "salle vide" déterministe,
	# sans écran de sélection d'agent ni bot errant dans le cadre.
	if inst.get("agent_select") != null:
		inst.set("agent_select", false)
	if inst.get("allow_bot_fill") != null:
		inst.set("allow_bot_fill", false)
	root.add_child(inst)
	_current_scene_inst = inst
	current_scene = inst
	var b := _bounds_for(map_id)
	_bounds_center = Vector3(b["center"].x, 0.0, b["center"].y)
	_bounds_span = b["span"]
	_phase = "warmup"
	_phase_t = 0.0
	_reset_accumulators()
	_fly_camera(0.0)
	return false


func _reset_accumulators() -> void:
	_draw_calls_sum = 0.0
	_objects_sum = 0.0
	_primitives_sum = 0.0
	_video_mem_sum = 0.0
	_gpu_ms_sum = 0.0
	_sample_count = 0


## Bounds (centre + envergure) de la map. Nettoyage du prototype 2026-09-26 :
## les six cartes "dessinées à la main" (`Layouts.gd`) et Cargo Ship ont été
## supprimées avec leurs scènes — Wasteland est désormais la seule carte.
func _bounds_for(map_id: String) -> Dictionary:
	var data: Dictionary = WastelandLayout.data() if map_id == "wasteland" else {}
	if data.is_empty() or not data.has("bounds"):
		return {"center": Vector2.ZERO, "span": 30.0}
	var bounds: Dictionary = data["bounds"]
	var mn: Vector2 = bounds["min"]
	var mx: Vector2 = bounds["max"]
	return {
		"center": Vector2((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5),
		"span": maxf(mx.x - mn.x, mx.y - mn.y),
	}


## Chemin déterministe : orbite aérienne (ORBIT_FRACTION du temps total),
## puis une passe rectiligne à hauteur de joueur à travers le centre de la
## carte (aller-retour sur ce qu'il reste de la fenêtre de mesure).
func _fly_camera(t: float) -> void:
	var total := WARMUP_SECONDS + _seconds
	var orbit_end := total * ORBIT_FRACTION
	if t < orbit_end:
		var frac: float = t / maxf(orbit_end, 0.001)
		var angle := frac * TAU
		var radius := _bounds_span * 0.55
		var height := _bounds_span * 0.4
		var pos := _bounds_center + Vector3(cos(angle) * radius, height, sin(angle) * radius)
		_cam.global_position = pos
		_cam.look_at(_bounds_center, Vector3.UP)
	else:
		var pass_t: float = (t - orbit_end) / maxf(total - orbit_end, 0.001)
		# Va-et-vient (0 -> 1 -> 0) le long de l'axe le plus long, à hauteur d'œil.
		var ping := 1.0 - absf(fmod(pass_t * 2.0, 2.0) - 1.0)
		var half := _bounds_span * 0.5
		var x := lerpf(-half, half, ping)
		var pos := _bounds_center + Vector3(x, EYE_HEIGHT, 0.0)
		var look_pos := _bounds_center + Vector3(0.0, EYE_HEIGHT, 0.0)
		_cam.global_position = pos
		_cam.look_at(look_pos if pos.distance_to(look_pos) > 0.05 else look_pos + Vector3(0.01, 0, 0), Vector3.UP)


func _sample_render_info() -> void:
	_draw_calls_sum += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_objects_sum += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	_primitives_sum += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_gpu_ms_sum += RenderingServer.viewport_get_measured_render_time_gpu(_gpu_viewport_rid)
	if _video_mem_monitor_id >= 0:
		_video_mem_sum += Performance.get_monitor(_video_mem_monitor_id as Performance.Monitor)
	_sample_count += 1


## Recherche dynamique (par nom, via ClassDB) du moniteur `Performance`
## "RENDER_VIDEO_MEM_USED" — évite de figer à la compilation une constante
## qui n'existe pas forcément à l'identique sur toutes les versions 4.x.
## Renvoie -1 si absent (le rapport affiche alors "n/a" pour ce champ).
func _find_video_mem_monitor_id() -> int:
	var names := ClassDB.class_get_integer_constant_list("Performance", true)
	if names.has("RENDER_VIDEO_MEM_USED"):
		return ClassDB.class_get_integer_constant("Performance", "RENDER_VIDEO_MEM_USED")
	return -1


func _snapshot_pass() -> Dictionary:
	var n := maxf(1.0, float(_sample_count))
	return {
		"avg_fps": _stats.avg_fps(),
		"low_1pct_fps": _stats.low_1pct_fps(),
		"p99_frame_ms": _stats.p99_ms(),
		"draw_calls_avg": _draw_calls_sum / n,
		"gpu_ms_avg": _gpu_ms_sum / n,
		"frames_sampled": _sample_count,
	}


func _finish_current_map() -> void:
	var entry: Dictionary = _maps[_map_index]
	var map_id := String(entry["id"])
	if _toggle_active:
		var row := {
			"id": map_id,
			"shader": _toggle_shader_name,
			"param": _toggle_param_name,
			"with_gpu_ms_avg": _pass_a_result["gpu_ms_avg"],
			"without_gpu_ms_avg": _pass_b_result["gpu_ms_avg"],
			"gpu_ms_delta": _pass_a_result["gpu_ms_avg"] - _pass_b_result["gpu_ms_avg"],
			"with_avg_fps": _pass_a_result["avg_fps"],
			"without_avg_fps": _pass_b_result["avg_fps"],
			"materials_toggled": _toggle_materials.size(),
		}
		_results.append(row)
		print("PERF_BENCH_TOGGLE %s avec_gpu_ms=%.3f sans_gpu_ms=%.3f delta_ms=%.3f (%d matériau(x))" % [
			map_id, row["with_gpu_ms_avg"], row["without_gpu_ms_avg"], row["gpu_ms_delta"], row["materials_toggled"],
		])
		return
	var n := maxf(1.0, float(_sample_count))
	var video_mb: float = (_video_mem_sum / n) / (1024.0 * 1024.0) if _video_mem_monitor_id >= 0 else -1.0
	var row := {
		"id": map_id,
		"avg_fps": _stats.avg_fps(),
		"low_1pct_fps": _stats.low_1pct_fps(),
		"p99_frame_ms": _stats.p99_ms(),
		"draw_calls_avg": _draw_calls_sum / n,
		"primitives_avg": _primitives_sum / n,
		"objects_avg": _objects_sum / n,
		"gpu_ms_avg": _gpu_ms_sum / n,
		"video_mem_mb": video_mb,
		"frames_sampled": _sample_count,
	}
	_results.append(row)
	print("PERF_BENCH_MAP %s avg_fps=%.1f low1=%.1f p99_ms=%.2f draw_calls=%.0f" % [
		map_id, row["avg_fps"], row["low_1pct_fps"], row["p99_frame_ms"], row["draw_calls_avg"]])


func _advance() -> bool:
	return _load_map(_map_index + 1)


func _ensure_ink_post() -> void:
	if _cam and _cam.get_node_or_null("InkPost") == null:
		var post := _INK_POST_SCRIPT.new()
		post.name = "InkPost"
		_cam.add_child(post)


## -- Mode A/B : bascule d'un paramètre de shader sur tous les matériaux ----

## Parcourt `node` récursivement et ajoute à `out` chaque `ShaderMaterial`
## (matériau de surface OU `material_override`) dont `.shader == target`,
## trouvé sur un `GeometryInstance3D` (MeshInstance3D compris) — couvre aussi
## bien les matériaux du décor/personnages (Cartoon.gd) que celui de
## `InkPost` (`material_override`, voir scripts/core/InkPost.gd).
func _collect_shader_materials(node: Node, target: Shader, out: Array) -> void:
	if node is GeometryInstance3D:
		var override := (node as GeometryInstance3D).material_override
		if override is ShaderMaterial and override.shader == target and not out.has(override):
			out.append(override)
		if node is MeshInstance3D and node.mesh:
			for i in range(node.mesh.get_surface_count()):
				var mat: Material = node.get_surface_override_material(i)
				if mat == null:
					mat = node.mesh.surface_get_material(i)
				if mat is ShaderMaterial and mat.shader == target and not out.has(mat):
					out.append(mat)
	for child in node.get_children():
		_collect_shader_materials(child, target, out)


## Valeur "désactivée" générique pour un uniform bool/int/float — la
## convention `*_enabled`/`*_strength` = 0 de tous les shaders du dépôt (voir
## l'en-tête de fichier). `null` (type non pris en charge) signale à
## l'appelant d'abandonner (voir `_prepare_toggle_materials`).
func _off_value_for(original: Variant) -> Variant:
	match typeof(original):
		TYPE_BOOL:
			return false
		TYPE_FLOAT:
			return 0.0
		TYPE_INT:
			return 0
		_:
			return null


## Recense les matériaux à basculer pour la map EN COURS (la scène est
## rejouée à chaque map, donc ses matériaux le sont aussi — jamais réutilisé
## d'une map à l'autre). Échoue clairement (`_fail`, toujours code 0 — voir
## le contrat du fichier) si aucun matériau n'utilise ce shader, ou si le
## paramètre n'est ni bool ni numérique.
## Ne renvoie rien : les échecs passent par `_fail()` (qui pose `_failed`),
## l'appelant (`_process()`) teste ce drapeau juste après — jamais un bool de
## retour à double sens (`_fail()` renvoie `true` aussi bien que le succès
## renverrait `true`, ce qui serait ambigu pour l'appelant).
func _prepare_toggle_materials() -> void:
	_toggle_materials = []
	var shader_path: String = _SHADER_NAME_TO_PATH[_toggle_shader_name]
	var target_shader := load(shader_path) as Shader
	if target_shader == null:
		_fail("--toggle-uniform : impossible de charger %s" % shader_path)
		return
	var mats: Array = []
	_collect_shader_materials(root, target_shader, mats)
	if mats.is_empty():
		_fail("--toggle-uniform : aucun ShaderMaterial utilisant '%s' trouvé dans la scène de %s" % [_toggle_shader_name, String((_maps[_map_index] as Dictionary)["id"])])
		return
	for mat in mats:
		var mat_shader_material: ShaderMaterial = mat
		var original: Variant = mat_shader_material.get_shader_parameter(_toggle_param_name)
		if original == null:
			original = RenderingServer.shader_get_parameter_default(target_shader.get_rid(), _toggle_param_name)
		if original == null:
			_fail("--toggle-uniform : le shader '%s' n'a pas d'uniform '%s'" % [_toggle_shader_name, _toggle_param_name])
			return
		var off_value: Variant = _off_value_for(original)
		if off_value == null:
			_fail("--toggle-uniform : '%s' du shader '%s' n'est ni bool ni numérique (valeur %s), impossible à désactiver" % [_toggle_param_name, _toggle_shader_name, original])
			return
		_toggle_materials.append({"material": mat_shader_material, "original_value": original, "off_value": off_value})


## `off = true` force l'état "sans" (mesure_b) ; `off = false` restaure
## l'état "avec" d'origine, après mesure_b, pour laisser la scène exactement
## comme trouvée.
func _apply_toggle_state(off: bool) -> void:
	for entry in _toggle_materials:
		var mat: ShaderMaterial = entry["material"]
		mat.set_shader_parameter(_toggle_param_name, entry["off_value"] if off else entry["original_value"])


func _write_report() -> void:
	var data := {
		"seconds_per_map": _seconds,
		"maps": _results,
		"errors": _errors,
	}
	if _toggle_active:
		data["toggle_uniform"] = {"shader": _toggle_shader_name, "param": _toggle_param_name}
	var path := "%s/perf.json" % _out_dir
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("PERF_BENCH_FAIL impossible d'écrire %s" % path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()


func _fail(reason: String) -> bool:
	print("PERF_BENCH_FAIL ", reason)
	_write_report()
	_failed = true
	quit(0)  # contrat : perf_bench.gd quitte toujours 0, le gate se juge dans report.py.
	return true
