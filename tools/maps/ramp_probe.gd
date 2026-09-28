## ramp_probe.gd
## Sonde « on s'enfonce sur les rampes » (retour de test 2026-09-28, Canyon Express) : charge la
## carte, fige tous les bots, en pilote un seul le long des corniches (montée et descente) et
## mesure à chaque tick physique l'écart pieds du corps <-> sol de collision (rayon vertical,
## calque WORLD) et pieds <-> pente théorique du layout.
##   "%GODOT%" --headless --path . -s res://tools/maps/ramp_probe.gd
## Sortie : lignes RAMP_PROBE (min/max/moyenne des écarts par passage + pires points).
extends SceneTree

const MAP := "res://scenes/levels/maps/canyon_express.tscn"
## Passages : départ, direction (x), longueur (m), z de la corniche, pente théorique.
const RUNS := [
	{"name": "NE descente", "from": Vector3(9.0, 0.3, -6.5), "dir": 1.0, "len": 23.0, "xt": 11.0, "xb": 31.0},
	{"name": "NE montée", "from": Vector3(31.5, -4.7, -6.5), "dir": -1.0, "len": 21.0, "xt": 11.0, "xb": 31.0},
	{"name": "SO descente", "from": Vector3(-33.0, 0.3, 6.5), "dir": 1.0, "len": 23.0, "xt": -31.0, "xb": -11.0},
	{"name": "SO montée", "from": Vector3(-10.5, -4.7, 6.5), "dir": -1.0, "len": 23.0, "xt": -31.0, "xb": -11.0},
]

var _world: Node
var _pilot: Node3D
var _run := -1
var _t := 0.0
var _samples: Array = []


func _initialize() -> void:
	var packed: PackedScene = load(MAP)
	_world = packed.instantiate()
	get_root().add_child.call_deferred(_world)


func _physics_process(delta: float) -> bool:
	if _pilot == null:
		_t += delta
		_try_take_pilot()
		if _t > 15.0:
			print("RAMP_PROBE_FAIL no_player")
			quit(1)
		return false
	if _run < 0 or _t >= RUNS[_run]["len"] / 4.0 + 0.6:
		if _run >= 0:
			_report(RUNS[_run])
		_run += 1
		if _run >= RUNS.size():
			quit(0)
			return true
		_start(RUNS[_run])
		return false
	_t += delta
	if _t > 0.6:
		_sample(RUNS[_run])
	return false


func _try_take_pilot() -> void:
	var world := get_root().get_tree().get_first_node_in_group("match")
	if world == null:
		return
	var root := world.get_node_or_null(world.get("players_root"))
	if root == null or root.get_child_count() < 2:
		return
	for child in root.get_children():
		var brain := child.get_node_or_null("BotBrain")
		if brain != null:
			brain.process_mode = Node.PROCESS_MODE_DISABLED
		if _pilot == null and bool(child.get("is_bot")):
			_pilot = child
	for child in root.get_children():
		if child != _pilot:
			child.process_mode = Node.PROCESS_MODE_DISABLED


func _start(run: Dictionary) -> void:
	_t = 0.0
	_samples.clear()
	_pilot.global_position = run["from"]
	_pilot.velocity = Vector3.ZERO
	_pilot.rotation.y = -PI / 2.0 if float(run["dir"]) > 0.0 else PI / 2.0
	_pilot.get("input").set("move", Vector2(0.0, -1.0))


func _sample(run: Dictionary) -> void:
	var feet := _pilot.global_position
	var space := _pilot.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 1.0, feet + Vector3.DOWN * 3.0, PhysicsLayers.WORLD)
	q.exclude = [(_pilot as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var xt: float = run["xt"]
	var xb: float = run["xb"]
	var t := clampf((feet.x - xt) / (xb - xt), 0.0, 1.0)
	var theory := -5.0 * t
	_samples.append({"x": feet.x, "d_col": feet.y - (hit["position"] as Vector3).y, "d_th": feet.y - theory,
			"floor": (_pilot as CharacterBody3D).is_on_floor(), "col": str((hit["collider"] as Node).name),
			"head": float(_pilot.get("_head_step_offset"))})


func _report(run: Dictionary) -> void:
	if _samples.is_empty():
		print("RAMP_PROBE %s aucun échantillon" % run["name"])
		return
	var lo := 99.0
	var hi := -99.0
	var air := 0
	var h_lo := 99.0
	var h_hi := -99.0
	var worst: Array = []
	for s in _samples:
		lo = minf(lo, s["d_col"])
		hi = maxf(hi, s["d_col"])
		if not s["floor"]:
			air += 1
		h_lo = minf(h_lo, s["head"])
		h_hi = maxf(h_hi, s["head"])
		if absf(s["d_col"]) > 0.03 or absf(s["d_th"]) > 0.05:
			worst.append("x=%.1f col=%.3f th=%.3f %s" % [s["x"], s["d_col"], s["d_th"], s["col"]])
	print("RAMP_PROBE %s n=%d pieds-sol min=%.3f max=%.3f en_l'air=%d tête(lissage marche) min=%.3f max=%.3f" % [run["name"], _samples.size(), lo, hi, air, h_lo, h_hi])
	for w in worst.slice(0, 6):
		print("RAMP_PROBE   ", w)
	var k := 0
	var trace := ""
	for s in _samples:
		if k % 25 == 0:
			trace += " x=%.1f:%.2f" % [s["x"], s["head"]]
		k += 1
	print("RAMP_PROBE   tête le long du passage :", trace)
