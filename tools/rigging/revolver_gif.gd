## revolver_gif.gd
## Filme la vue FPS du revolver en jeu pour un GIF : rechargement, inspection, éventail.
## Temps piloté par la PHYSIQUE (60 Hz), une image tous les 2 tics (30 i/s), sans bot (pas
## d'interruption par une mort). Images : reports/checkpoints/2026-09-27_revolver/gif/<séquence>_NNN.png
## puis : python tools/rigging/make_gif.py (assemble les GIF).
##   "%GODOT%" --screen 1 --path . -s res://tools/rigging/revolver_gif.gd
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const OUT_DIR := "res://reports/checkpoints/2026-09-27_revolver/gif"
## (début en tics depuis l'installation, action, argument)
const TIMELINE := [
	[10, "press", "weapon_2"], [13, "release", "weapon_2"],
	# barillet plein : le jeu refuse de recharger -> trois coups d'abord
	[45, "press", "fire"], [47, "release", "fire"], [65, "press", "fire"], [67, "release", "fire"],
	[85, "press", "fire"], [87, "release", "fire"],
	[90, "rec_start", "reload"], [92, "press", "reload"], [95, "release", "reload"], [250, "rec_stop", ""],
	[280, "rec_start", "inspect"], [282, "press", "inspect"], [285, "release", "inspect"], [440, "rec_stop", ""],
	[470, "rec_start", "fan"], [472, "press", "aim"], [520, "release", "aim"], [540, "rec_stop", ""],
	[560, "quit", ""],
]


class Driver extends Node:
	var tree: SceneTree
	var tick := -1
	var player: Node
	var seq := ""
	var n := 0

	func _physics_process(_delta: float) -> void:
		tick += 1
		if tick == 120:
			player = _find_human(tree.get_root())
			if player:
				# la souris de l'utilisateur (curseur qui passe sur la fenêtre) ne tourne pas la vue
				player.set_process_unhandled_input(false)
				player.set_process_input(false)
		if tick < 120 or player == null:
			return
		var t := tick - 120
		for ev in TIMELINE:
			if ev[0] != t:
				continue
			match ev[1]:
				"press":
					Input.action_press(ev[2])
				"release":
					Input.action_release(ev[2])
				"rec_start":
					seq = ev[2]
					n = 0
				"rec_stop":
					seq = ""
				"quit":
					tree.quit()
		if seq != "" and t % 2 == 0:
			_save.call_deferred("%s_%03d.png" % [seq, n])
			n += 1

	func _save(file_name: String) -> void:
		await RenderingServer.frame_post_draw
		var img := tree.get_root().get_texture().get_image()
		img.resize(640, 400)
		img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join(file_name)))

	func _find_human(node: Node) -> Node:
		if node is PlayerController and (node as PlayerController).is_local_human():
			return node
		for c in node.get_children():
			var r := _find_human(c)
			if r:
				return r
		return null


func _initialize() -> void:
	# La fenêtre ne prend jamais le focus : la souris/le clavier de l'utilisateur (qui travaille
	# pendant la capture) ne pilotent pas la vue ni l'inventaire.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = false
	MatchConfig.team_size = 1
	get_root().add_child((load(_SHIPMENT) as PackedScene).instantiate())
	var d := Driver.new()
	d.tree = self
	get_root().add_child(d)
