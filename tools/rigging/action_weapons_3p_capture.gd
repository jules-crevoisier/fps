## action_weapons_3p_capture.gd
## Capture EN FENÊTRÉ (swapchain requis, comme tools/rigging/action_weapons_capture.gd) la vue
## TROISIÈME personne d'un BOT tenant chacune des armes réglées par la tâche "cadrage FP quatre
## armes" (2026-09-28) -- Ravage (id 0, référence) + Rafale/Fracas/Verdict/Aiguille (ids 2-5) -- sur
## Canyon Express (`scenes/levels/maps/canyon_express.tscn`), terrain dégagé du rebord nord
## (~(10,0,-28), près des marqueurs de spawn N7/N8).
##
## Héberge un TDM avec bots (comme l'historique tools/char_ingame_shots.gd) : l'hôte spawne comme
## joueur local (agent_select désactivé), un bot rempli par `allow_bot_fill` sert de mannequin --
## téléporté à la position cible et gelé (BotBrain.set_physics_process(false) + entrée à zéro,
## sinon l'IA continue de le faire marcher/regarder pendant la capture). Loadout forcé ARME PAR ARME
## via `Weapon.server_set_loadout` sur le NŒUD DU BOT (même mécanisme serveur direct que le solo,
## le bot est simulé côté hôte).
##
##   "%GODOT%" --screen 1 --path . -s res://tools/rigging/action_weapons_3p_capture.gd
##
## Images : reports/checkpoints/2026-09-28_weapons_v3/<nom>_3p.png.
## Imprime `ACTION_WEAPONS_3P_SAVED <nom>` par capture puis `ACTION_WEAPONS_3P_DONE`.
extends SceneTree

const _CANYON := "res://scenes/levels/maps/canyon_express.tscn"
const OUT_DIR := "res://reports/checkpoints/2026-09-28_weapons_v3"

## Position cible (rebord nord, terrain dégagé -- voir la doc de tête) et distance/hauteur de la
## caméra externe (3 m, hauteur poitrine ≈1.4 m -- consigne de tâche).
const _TARGET_POS := Vector3(10.0, 0.0, -28.0)
const _CAMERA_DISTANCE := 3.0
const _CAMERA_HEIGHT := 1.4
## Le bot regarde vers -Z (nord, vers le fond de carte) -- la caméra se place donc sur +Z (devant
## lui, légèrement de profil) pour voir l'arme tenue en main plutôt que de dos.
const _BOT_YAW := 0.0

const _WEAPONS := [
	{"id": 0, "name": "ravage"},
	{"id": 2, "name": "rafale"},
	{"id": 3, "name": "fracas"},
	{"id": 4, "name": "verdict"},
	{"id": 5, "name": "aiguille"},
]

const _SETTLE_FRAMES := 30


class Driver extends Node:
	var tree: SceneTree
	var out_dir := OUT_DIR
	var world: Node
	var bot: PlayerController
	var bot_weapon: Weapon
	var bot_brain: Node
	var spectator_cam: Camera3D
	var _step := 0
	var _wait_left := 0
	var _weapon_index := 0

	func _physics_process(_delta: float) -> void:
		# Le bot continue d'être simulé (BotBrain gelé, voir `_freeze_bot`) -- réaffirme la position/
		# l'entrée à zéro CHAQUE frame tant qu'on n'a pas fini : `move_and_slide` (CharacterBody3D)
		# peut sinon faire lentement glisser le mannequin (gravité résiduelle, friction) pendant les
		# settle de plusieurs armes d'affilée.
		if bot:
			_pin_bot()
		match _step:
			0:
				_wait_left -= 1
				if _wait_left <= 0:
					_find_bot()
					if bot:
						_freeze_bot()
						bot_weapon = bot.get_node_or_null("Weapon") as Weapon
						spectator_cam = Camera3D.new()
						tree.get_root().add_child(spectator_cam)
						_frame_camera()
					_step = 1
			1:
				_equip_next()
			2:
				_wait_left -= 1
				if _wait_left <= 0:
					_save("%s_3p" % _WEAPONS[_weapon_index]["name"])
					_weapon_index += 1
					_step = 1

	func _equip_next() -> void:
		if _weapon_index >= _WEAPONS.size() or bot == null:
			_finish()
			return
		var entry: Dictionary = _WEAPONS[_weapon_index]
		if bot_weapon:
			var ids: Array[int] = [int(entry["id"])]
			bot_weapon.server_set_loadout(ids)
		_wait_left = _SETTLE_FRAMES
		_step = 2

	func _find_bot() -> void:
		for p in _players(tree.get_root()):
			if bool(p.get("is_bot")):
				bot = p
				return

	func _players(n: Node) -> Array:
		var out: Array = []
		if n is PlayerController:
			out.append(n)
		for c in n.get_children():
			out.append_array(_players(c))
		return out

	## Fige le mannequin : coupe l'IA (BotBrain, qui réécrit `input.move`/`input.look_delta` à
	## chaque tick, voir sa docstring de classe) ET son entrée déjà posée (sinon le DERNIER ordre
	## de BotBrain avant la coupure -- ex. "avance" -- continuerait de s'appliquer indéfiniment,
	## `PlayerController._physics_process` consommant `input.move` quel que soit qui l'a écrit).
	func _freeze_bot() -> void:
		bot_brain = bot.get_node_or_null("BotBrain")
		if bot_brain:
			bot_brain.set_physics_process(false)
		bot.set_process_unhandled_input(false)
		bot.set_process_input(false)
		_pin_bot()

	func _pin_bot() -> void:
		var inp = bot.get("input")
		if inp:
			inp.move = Vector2.ZERO
			inp.look_delta = Vector2.ZERO
			inp.jump_held = false
			inp.fire_held = false
			inp.fire_pressed = false
			inp.aim_held = false
			inp.alt_fire_held = false
		bot.velocity = Vector3.ZERO
		bot.global_position = _target_pos()
		bot.rotation = Vector3(0.0, _BOT_YAW, 0.0)

	func _target_pos() -> Vector3:
		return Vector3(10.0, 0.0, -28.0)

	## Cadrage 3/4 -- caméra sur +Z devant le mannequin (il regarde -Z, voir `_BOT_YAW`), légèrement
	## décalée sur le côté pour révéler l'arme tenue en main droite plutôt qu'un silhouette plate de
	## face. Hauteur poitrine (consigne de tâche).
	func _frame_camera() -> void:
		var target := _target_pos()
		var look_pos := target + Vector3(0.0, 1.1, 0.0)
		var cam_pos := target + Vector3(0.0, _CAMERA_HEIGHT, 0.0) \
			+ Vector3(-0.9, 0.0, 1.0).normalized() * _CAMERA_DISTANCE
		spectator_cam.global_position = cam_pos
		spectator_cam.look_at(look_pos, Vector3.UP)
		spectator_cam.current = true

	func _save(name: String) -> void:
		var img := tree.get_root().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		img.save_png(ProjectSettings.globalize_path(out_dir.path_join("%s.png" % name)))
		print("ACTION_WEAPONS_3P_SAVED ", name)

	func _finish() -> void:
		print("ACTION_WEAPONS_3P_DONE")
		tree.quit()


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "canyon_express"
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 2
	MatchConfig.bot_difficulty = MatchConfig.Difficulty.VETERAN

	var out_dir := OUT_DIR
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")

	var packed := load(_CANYON) as PackedScene
	var inst := packed.instantiate()
	if inst.get("agent_select") != null:
		inst.set("agent_select", false)
	if inst.get("allow_bot_fill") != null:
		inst.set("allow_bot_fill", true)
	get_root().add_child.call_deferred(inst)
	var d := Driver.new()
	d.tree = self
	d.out_dir = out_dir
	# Attente initiale plus longue que la carte Shipment (canyon_express : navmesh plus grand à
	# bake, spawn du bot ET de l'hôte) -- avant le premier `_find_bot`.
	d._wait_left = 240
	get_root().add_child(d)
