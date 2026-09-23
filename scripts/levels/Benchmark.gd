## Benchmark.gd
## Scène de benchmark autonome (pas de GameWorld / réseau / menus) : la comp map
## (CompMapBuilder + WorldEnvironment/DirectionalLight, voir benchmark.tscn) est
## peuplée de 8 mannequins d'entraînement et parcourue par une caméra suivant un
## chemin fermé fixe. 3 s d'échauffement puis 20 s de mesure ; à la fin, imprime
## UNE ligne "BENCH ..." et écrit le même relevé en JSON dans user://, puis
## quitte. Fonctionne en fenêtré (Camera3D active) et en --headless (chiffres
## sans valeur en headless, mais aucune erreur).
extends Node3D

enum Phase { WARMUP, MEASURE, DONE }

const WARMUP_SEC := 3.0
const MEASURE_SEC := 20.0
const CAMERA_SPEED := 6.0     ## m/s le long du chemin
const HISTORY_CAPACITY := 200000 ## large marge : headless peut dépasser 60 fps

## Chemin fermé traversant les lanes, le mid et les deux sites de la comp map.
const PATH_POINTS: Array[Vector3] = [
	Vector3(-27.0, 2.5, 0.0),
	Vector3(-10.0, 2.0, 14.0),
	Vector3(0.0, 3.5, 0.0),
	Vector3(22.0, 2.0, 14.0),
	Vector3(27.0, 2.5, 0.0),
	Vector3(22.0, 2.0, -14.0),
	Vector3(0.0, 3.5, 0.0),
	Vector3(-10.0, 2.0, -14.0),
]

## 8 mannequins répartis sur la carte, hors des murs et du bâtiment central.
const DUMMY_POSITIONS: Array[Vector3] = [
	Vector3(-24.0, 0.0, 16.0),
	Vector3(-24.0, 0.0, -16.0),
	Vector3(-12.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 10.0),
	Vector3(0.0, 0.0, -10.0),
	Vector3(12.0, 0.0, 0.0),
	Vector3(24.0, 0.0, 16.0),
	Vector3(24.0, 0.0, -16.0),
]

var _stats: FrameStats
var _phase: Phase = Phase.WARMUP
var _elapsed: float = 0.0
var _path_t: float = 0.0
var _path_len: float = 0.0
var _camera: Camera3D
var _draw_calls_sum: int = 0
var _objects_sum: int = 0
var _measured_frames: int = 0

func _ready() -> void:
	_stats = FrameStats.new(HISTORY_CAPACITY)
	_spawn_dummies()
	_build_camera()
	_path_len = _path_length()

func _spawn_dummies() -> void:
	var dummies := Node3D.new()
	dummies.name = "Dummies"
	add_child(dummies)
	var dummy_script := preload("res://scripts/world/TrainingDummy.gd")
	for i in range(DUMMY_POSITIONS.size()):
		var d := StaticBody3D.new()
		d.name = "Dummy%d" % i
		d.set_script(dummy_script)
		d.position = DUMMY_POSITIONS[i]
		dummies.add_child(d)

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "BenchCamera"
	add_child(_camera)
	_camera.global_position = PATH_POINTS[0]
	_camera.current = true

func _path_length() -> float:
	var total := 0.0
	var n := PATH_POINTS.size()
	for i in range(n):
		total += PATH_POINTS[i].distance_to(PATH_POINTS[(i + 1) % n])
	return total

func _point_on_path(dist: float) -> Vector3:
	var n := PATH_POINTS.size()
	var remaining := dist
	for i in range(n):
		var a := PATH_POINTS[i]
		var b := PATH_POINTS[(i + 1) % n]
		var seg := a.distance_to(b)
		if remaining <= seg:
			return a if seg <= 0.0001 else a.lerp(b, remaining / seg)
		remaining -= seg
	return PATH_POINTS[0]

func _advance_camera(delta: float) -> void:
	if _path_len <= 0.0:
		return
	_path_t = fmod(_path_t + CAMERA_SPEED * delta, _path_len)
	var pos := _point_on_path(_path_t)
	_camera.global_position = pos
	var ahead := _point_on_path(fmod(_path_t + 2.0, _path_len))
	if ahead.distance_to(pos) > 0.001:
		_camera.look_at(ahead, Vector3.UP)

func _process(delta: float) -> void:
	_advance_camera(delta)
	match _phase:
		Phase.WARMUP:
			_elapsed += delta
			if _elapsed >= WARMUP_SEC:
				_phase = Phase.MEASURE
				_elapsed = 0.0
		Phase.MEASURE:
			_elapsed += delta
			_record_frame(delta)
			if _elapsed >= MEASURE_SEC:
				_phase = Phase.DONE
				_finish()
		Phase.DONE:
			pass

func _record_frame(delta: float) -> void:
	_stats.add(delta * 1000.0)
	_draw_calls_sum += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_objects_sum += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	_measured_frames += 1

func _finish() -> void:
	var avg_fps := _stats.avg_fps()
	var low1 := _stats.low_1pct_fps()
	var p99 := _stats.p99_ms()
	var draw_calls_avg := 0
	var objects_avg := 0
	if _measured_frames > 0:
		draw_calls_avg = int(round(float(_draw_calls_sum) / _measured_frames))
		objects_avg = int(round(float(_objects_sum) / _measured_frames))
	print("BENCH avg_fps=%.2f low1=%.2f p99_ms=%.2f draw_calls=%d objects=%d frames=%d" % [
		avg_fps, low1, p99, draw_calls_avg, objects_avg, _measured_frames,
	])
	_write_json(avg_fps, low1, p99, draw_calls_avg, objects_avg, _measured_frames)
	get_tree().quit()

func _write_json(avg_fps: float, low1: float, p99: float, draw_calls_avg: int, objects_avg: int, frames: int) -> void:
	var data := {
		"avg_fps": avg_fps,
		"low1": low1,
		"p99_ms": p99,
		"draw_calls": draw_calls_avg,
		"objects": objects_avg,
		"frames": frames,
	}
	var path := "user://benchmark_%d.json" % int(Time.get_unix_time_from_system())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
