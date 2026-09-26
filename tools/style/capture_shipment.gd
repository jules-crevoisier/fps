## capture_shipment.gd
## Captures in-game du style BD (2026-09-26) : héberge Shipment avec 1 bot,
## laisse le style/l'IA se stabiliser, écrit deux PNG (vue FPS locale +
## survol) -- même famille que tools/review/gameplay_probe.gd (SceneTree,
## `_process` pour laisser le moteur tourner avant d'agir, jamais dans
## `_initialize`, voir sa docstring). FENÊTRÉ (pas headless : il faut un vrai
## swapchain pour une capture -- voir tools/style/render_parity_godot.gd).
##
## Usage :
##   "%GODOT%" --path . -s res://tools/style/capture_shipment.gd -- --out=reports/checkpoints/2026-09-26_toon_bd
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const _SETTLE_FRAMES := 90  ## ~1.5s à 60 fps : laisse les bots spawn/bouger un peu.

var _out_dir: String = "res://reports/checkpoints/2026-09-26_toon_bd"
var _frame: int = 0
var _world: Node = null
var _shots_done: bool = false

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)

func _process(_delta: float) -> bool:
	if _frame == 0:
		_boot()
	_frame += 1
	if _shots_done:
		return false
	if _frame == _SETTLE_FRAMES:
		_capture_player_view()
	elif _frame == _SETTLE_FRAMES + 2:
		_switch_to_overview_camera()
	elif _frame == _SETTLE_FRAMES + 6:
		# Le swapchain a besoin de quelques frames après le changement de
		# caméra pour présenter une image qui reflète VRAIMENT le nouveau
		# point de vue (get_root().get_texture() renvoie la dernière frame
		# PRÉSENTÉE, jamais celle en cours de construction) -- capturer trop
		# tôt renverrait encore la vue joueur.
		_capture_overview()
		_shots_done = true
		call_deferred("quit", 0)
	return false

func _boot() -> void:
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 1
	var packed := load(_SHIPMENT) as PackedScene
	_world = packed.instantiate()
	get_root().add_child(_world)

func _local_player() -> Node:
	var players := get_root().get_tree().get_nodes_in_group("local_player")
	return players[0] if not players.is_empty() else null

func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name)
	var abs_dir := ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var err := img.save_png(path)
	print("capture_shipment: ", name, " -> ", path, " (err=", err, ")")

func _capture_player_view() -> void:
	var img := get_root().get_texture().get_image()
	if img:
		_save(img, "ingame_player_view.png")
	else:
		push_error("capture_shipment: pas d'image (lancé --headless ? voir l'en-tête)")

func _switch_to_overview_camera() -> void:
	# Caméra libre de survol : nouvelle Camera3D au-dessus de la carte,
	# `current = true` la bascule sans toucher à la caméra du joueur.
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.position = Vector3(0.0, 14.0, 14.0)
	cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	cam.current = true

func _capture_overview() -> void:
	var img := get_root().get_texture().get_image()
	if img:
		_save(img, "ingame_overview.png")
