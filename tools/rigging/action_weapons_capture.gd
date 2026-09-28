## action_weapons_capture.gd
## Captures de vérification des quatre nouvelles armes (tâche "quatre armes",
## 2026-09-28 : Rafale/Fracas/Verdict/Aiguille) — vue première personne de
## chacune (viewmodel + HUD réels, comme `look_capture.gd::Driver` "fps"), et
## la lunette de l'Aiguille pleinement visée (ScopeOverlay).
##
## Force le loadout du joueur local ARME PAR ARME via `Weapon.server_set_loadout`
## (appel direct serveur — le solo/hôte EST le serveur) plutôt que par un item
## de boutique/une sélection de loadout (hors du périmètre de cette tâche,
## Builder B) : c'est un outil de VÉRIFICATION visuelle, pas un flux de jeu.
##
##   "%GODOT%" --screen 1 --path . -s res://tools/rigging/action_weapons_capture.gd
##
## Images : reports/checkpoints/2026-09-28_weapons/<nom>_fps.png (x4) +
## aiguille_scope.png.
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const OUT_DIR := "res://reports/checkpoints/2026-09-28_weapons"

## Ids WeaponDatabase.PATHS (append-only, tâche "quatre armes") -> nom de
## fichier de capture.
const _WEAPONS := [
	{"id": 2, "name": "rafale"},
	{"id": 3, "name": "fracas"},
	{"id": 4, "name": "verdict"},
	{"id": 5, "name": "aiguille"},
]

## Délai (frames physiques, 60 Hz) après un changement d'arme avant capture --
## laisse le viewmodel finir sa montée d'équipement (AnimState.start_equip) et
## le modèle 3D se recharger (`_refresh_model`).
const _SETTLE_FRAMES := 40
## Délai (frames) tenu en visée avant la capture de la lunette -- largement
## au-delà de `ads_time` (0.28 s ≈ 17 frames à 60 Hz) de l'Aiguille, marge pour
## la transition ADS ET l'apparition de ScopeOverlay.
const _SCOPE_SETTLE_FRAMES := 60


class Driver extends Node:
	var tree: SceneTree
	var out_dir := OUT_DIR
	var player: PlayerController
	var weapon: Weapon
	var _step := 0
	var _wait_left := 0
	var _pending_save := ""
	var _weapon_index := 0

	func _physics_process(_delta: float) -> void:
		match _step:
			0:
				_wait_left -= 1
				if _wait_left <= 0:
					_find_player()
					if player:
						player.set_process_unhandled_input(false)
						player.set_process_input(false)
						weapon = player.get_node_or_null("Weapon") as Weapon
					_step = 1
			1:
				_equip_next()
			2:
				_wait_left -= 1
				if _wait_left <= 0:
					_save.call_deferred(_pending_save)
					_step = 3
			3:
				_step = 4  # laisse une frame à _save (call_deferred) avant d'enchaîner.
			4:
				if _current_weapon_is_aiguille():
					Input.action_press("aim")
					_wait_left = _SCOPE_SETTLE_FRAMES
					_step = 5
				else:
					_weapon_index += 1
					_step = 1
			5:
				_wait_left -= 1
				if _wait_left <= 0:
					_save.call_deferred("aiguille_scope")
					_step = 6
			6:
				Input.action_release("aim")
				_weapon_index += 1
				_step = 1

	func _equip_next() -> void:
		if _weapon_index >= _WEAPONS.size():
			print("ACTION_WEAPONS_CAPTURE_DONE")
			tree.quit()
			return
		var entry: Dictionary = _WEAPONS[_weapon_index]
		if weapon:
			var ids: Array[int] = [int(entry["id"])]
			weapon.server_set_loadout(ids)
		_pending_save = "%s_fps" % String(entry["name"])
		_wait_left = _SETTLE_FRAMES
		_step = 2

	func _current_weapon_is_aiguille() -> bool:
		return weapon != null and weapon.cfg() != null and weapon.cfg().weapon_name == "Aiguille"

	func _find_player() -> void:
		for p in _players(tree.get_root()):
			if p.is_local_human():
				player = p
				return

	func _players(n: Node) -> Array:
		var out: Array = []
		if n is PlayerController:
			out.append(n)
		for c in n.get_children():
			out.append_array(_players(c))
		return out

	func _save(name: String) -> void:
		await RenderingServer.frame_post_draw
		var img := tree.get_root().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		img.save_png(ProjectSettings.globalize_path(out_dir.path_join("%s.png" % name)))
		print("ACTION_WEAPONS_SAVED ", name)


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = false
	MatchConfig.team_size = 1

	var out_dir := OUT_DIR
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")

	# Différé : _initialize() tourne AVANT le _ready des autoloads (racine pas
	# encore dans l'arbre) — même raison que look_capture.gd.
	get_root().add_child.call_deferred((load(_SHIPMENT) as PackedScene).instantiate())
	var d := Driver.new()
	d.tree = self
	d.out_dir = out_dir
	d._wait_left = 120  # laisse Look/ToonStyle styler l'Environment + la physique se stabiliser.
	get_root().add_child(d)
