## smoke_drop_capture.gd
## Vérifie le fumigène « qui descend par gravité et se pose au premier contact avec le sol » :
## lancer long vers le haut, une image tous les 0,25 s pendant 4 s, planche finale.
## Temps piloté par la physique ; fenêtre sans focus ; entrées du joueur coupées.
##   "%GODOT%" --screen 1 --resolution 960x540 --path . -s res://tools/rigging/smoke_drop_capture.gd
## Images : reports/checkpoints/2026-09-27_ui/smoke_drop/NN.png
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const OUT_DIR := "res://reports/checkpoints/2026-09-27_ui/smoke_drop"


class Driver extends Node:
	var tree: SceneTree
	var tick := -1
	var player: PlayerController
	var n := 0

	func _physics_process(_delta: float) -> void:
		tick += 1
		if tick == 100:
			for p in tree.get_root().find_children("*", "PlayerController", true, false):
				if (p as PlayerController).is_local_human():
					player = p
			if player:
				player.set_process_unhandled_input(false)
				player.set_process_input(false)
				player.camera.rotation.x = deg_to_rad(18.0)   # vers le haut : long vol plané
		if player == null:
			return
		if tick == 105:
			Input.action_press("weapon_5")
		if tick == 108:
			Input.action_release("weapon_5")
		if tick == 150:
			Input.action_press("fire")
		if tick == 156:
			Input.action_release("fire")
		if tick >= 160 and tick <= 400 and (tick - 160) % 15 == 0:
			_save.call_deferred("%02d.png" % n)
			n += 1
		if tick == 420:
			tree.quit()

	func _save(file_name: String) -> void:
		await RenderingServer.frame_post_draw
		var img := tree.get_root().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join(file_name)))


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = false
	MatchConfig.team_size = 1
	get_root().add_child.call_deferred((load(_SHIPMENT) as PackedScene).instantiate())
	var d := Driver.new()
	d.tree = self
	get_root().add_child(d)
