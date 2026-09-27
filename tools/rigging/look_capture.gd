## look_capture.gd
## Captures de comparaison du rendu (avant/après un réglage de style) : vue FPS, portrait du bot
## en 3e personne, vue d'ensemble de la carte. Temps piloté par la physique ; le bot est figé ;
## la fenêtre ne prend pas le focus (la souris de l'utilisateur ne change rien).
##   "%GODOT%" --screen 1 --path . -s res://tools/rigging/look_capture.gd -- --tag=avant
## Images : reports/checkpoints/look/<tag>_{fps,portrait,overview}.png
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const OUT_DIR := "res://reports/checkpoints/look"


class Driver extends Node:
	var tree: SceneTree
	var tag := "look"
	var tick := -1
	var player: PlayerController
	var bot: PlayerController
	var cam: Camera3D

	func _physics_process(_delta: float) -> void:
		tick += 1
		if tick == 120:
			for p in _players(tree.get_root()):
				if p.is_local_human():
					player = p
				elif bot == null:
					bot = p
			if player:
				player.set_process_unhandled_input(false)
				player.set_process_input(false)
			for n in tree.get_root().find_children("*", "DirectionalLight3D", true, false):
				var sun := n as DirectionalLight3D
				print("LOOK_SUN dir=", -sun.global_transform.basis.z, " energy=", sun.light_energy,
					" shadows=", sun.shadow_enabled, " color=", sun.light_color)
				if "--noshadow" in OS.get_cmdline_user_args():
					sun.shadow_enabled = false
		if tick == 125 and player:
			Input.action_press("weapon_2")
		if tick == 128:
			Input.action_release("weapon_2")
		if tick == 200 and bot:
			bot.process_mode = Node.PROCESS_MODE_DISABLED   # figé pour des vues comparables
			# le bot face au joueur, à 6 m devant lui
			var fwd := -player.global_transform.basis.z
			fwd.y = 0.0
			bot.global_position = player.global_position + fwd.normalized() * 6.0
			bot.look_at(player.global_position, Vector3.UP)
			bot.rotate_y(PI)
		if tick == 230:
			_save.call_deferred("fps")
		if tick == 250 and bot:
			cam = Camera3D.new()
			cam.fov = 40.0
			tree.get_root().add_child(cam)
			var head: Vector3 = bot.global_position + Vector3(0, 1.45, 0)
			var front := bot.global_transform.basis.z  # le bot regarde -Z ; on se place devant
			front.y = 0.0
			cam.global_position = head + front.normalized() * 2.4 + bot.global_transform.basis.x * 0.9 + Vector3(0, 0.1, 0)
			cam.look_at(head - Vector3(0, 0.35, 0), Vector3.UP)
			cam.make_current()
		if tick == 262:
			_save.call_deferred("portrait")
		if tick == 270 and cam:
			cam.fov = 60.0
			cam.global_position = Vector3(18.0, 14.0, 18.0)
			cam.look_at(Vector3.ZERO, Vector3.UP)
		if tick == 282:
			_save.call_deferred("overview")
		if tick == 290 and cam:   # vue du dessus orthographique (minimap des maquettes)
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 46.0
			cam.look_at_from_position(Vector3(0.0, 40.0, 0.0), Vector3.ZERO, Vector3.FORWARD)
		if tick == 298:
			_save.call_deferred("top")
		if tick == 310:
			tree.quit()

	func _save(view: String) -> void:
		if "--nohud" in OS.get_cmdline_user_args():   # fond propre pour les maquettes d'interface
			for layer in tree.get_root().find_children("*", "CanvasLayer", true, false):
				(layer as CanvasLayer).visible = false
		await RenderingServer.frame_post_draw
		var img := tree.get_root().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join("%s_%s.png" % [tag, view])))
		print("LOOK_SAVED ", tag, "_", view)

	func _players(n: Node) -> Array:
		var out: Array = []
		if n is PlayerController:
			out.append(n)
		for c in n.get_children():
			out.append_array(_players(c))
		return out


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 1
	# Différé : _initialize() tourne AVANT le _ready des autoloads (racine pas encore dans l'arbre)
	# -- ajoutée tout de suite, la carte échapperait à Look (LevelLook.node_added) et garderait
	# un soleil horizontal non stylé, sans rapport avec le jeu réel.
	get_root().add_child.call_deferred((load(_SHIPMENT) as PackedScene).instantiate())
	var d := Driver.new()
	d.tree = self
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):
			d.tag = arg.trim_prefix("--tag=")
	get_root().add_child(d)
