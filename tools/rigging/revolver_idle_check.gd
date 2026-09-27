## revolver_idle_check.gd
## Contrôle de la vue FPS du revolver en jeu, temps piloté par la PHYSIQUE (60 Hz) :
## revolver sorti depuis 2 s (repos, animation de sortie finie), puis juste après un tir au
## clic gauche, puis en plein éventail (clic droit tenu).
##   "%GODOT%" --screen 1 --path . -s res://tools/rigging/revolver_idle_check.gd
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const OUT_DIR := "res://reports/checkpoints/2026-09-27_revolver"
## tics de physique (60/s) depuis la fin de l'installation -> action
const TIMELINE := [
	[10, "press", "weapon_2"], [13, "release", "weapon_2"],
	[130, "shot", "rv_check_idle.png"],
	[140, "press", "fire"], [150, "shot", "rv_check_fire.png"], [152, "release", "fire"],
	[200, "press", "aim"], [230, "shot", "rv_check_fan.png"], [236, "release", "aim"],
	[260, "quit", ""],
]

var _driver: Node


class Driver extends Node:
	var tree: SceneTree
	var tick := -1
	var player: Node

	func _physics_process(_delta: float) -> void:
		tick += 1
		if tick == 120:
			player = _find_human(tree.get_root())
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
				"shot":
					_save.call_deferred(ev[2])
				"quit":
					tree.quit()

	func _save(file_name: String) -> void:
		await RenderingServer.frame_post_draw
		var img := tree.get_root().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join(file_name)))
		print("CHECK_SAVED ", file_name)

	func _find_human(n: Node) -> Node:
		if n is PlayerController and (n as PlayerController).is_local_human():
			return n
		for c in n.get_children():
			var r := _find_human(c)
			if r:
				return r
		return null


func _initialize() -> void:
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 1
	get_root().add_child((load(_SHIPMENT) as PackedScene).instantiate())
	_driver = Driver.new()
	_driver.tree = self
	get_root().add_child(_driver)
