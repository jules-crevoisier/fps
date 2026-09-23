## char_ingame_shots.gd
## Capture EN FENÊTRÉ (pas headless : il faut un vrai swapchain pour lire le
## rendu — même contrainte que tools/screenshot.gd/character_shots.gd/
## map_shots.gd) des corps agents animés EN PARTIE (R3-CHAR) : héberge un TDM
## avec bots sur scenes/levels/maps/port_ferraille.tscn (MatchConfig, comme
## tools/bot_smoke.gd), l'hôte spawne comme joueur local (agent_select
## désactivé, comme tools/map_shots.gd), puis :
##  - N vues 3e personne (caméra EXTERNE, jamais le joueur) sur des bots
##    DIFFÉRENTS, espacées dans le temps pour augmenter les chances de capter
##    de la course ET du tir (aucun hook direct "ce bot tire maintenant" —
##    hors de portée de cette tranche, Weapon.gd est en lecture seule) ;
##  - 1 vue 1re personne (la caméra du joueur local lui-même) montrant
##    fp_arms + l'arme tenue.
##
##   godot --path . -s res://tools/char_ingame_shots.gd -- [--out=C:/dossier/]
##
## Écrit "<out>/bot_<n>_tp.png" (n = 1..BOT_SHOTS) et "<out>/local_fp.png",
## imprime `CHAR_SHOT <nom> -> <chemin>` par capture puis
## `CHAR_INGAME_SHOTS_DONE` (0) ou `CHAR_INGAME_SHOTS_FAIL <raison>` (1).
extends SceneTree

const DEFAULT_OUT := "C:/Users/srko/AppData/Local/Temp/claude/C--Users-srko-Desktop-fps/02e156fb-5e66-4722-9835-071a024d62a9/scratchpad/shots/chars_ingame"
const LEVEL := "res://scenes/levels/maps/port_ferraille.tscn"

## Nombre de bots capturés en 3e personne, et l'écart (s) entre chaque
## capture (espacé pour augmenter la chance de voir du tir en plus de la
## course, un match TDM veteran prend quelques secondes à s'engager).
const BOT_SHOTS := 3
const BOT_SHOT_INTERVAL := 8.0
## Attente initiale (s) avant la première capture : laisse le navmesh se
## bake, les bots spawner et commencer à se déplacer.
const INITIAL_SETTLE := 6.0
## Frames d'attente après un repositionnement de caméra externe avant de
## capturer — le rendu suit la transform avec un cran de retard (constaté
## dans tools/character_shots.gd).
const CAMERA_SETTLE_FRAMES := 4

var _out_dir: String = DEFAULT_OUT
var _started: bool = false
var _world: Node = null
var _spectator_cam: Camera3D

var _t: float = 0.0
var _phase: String = "settle"   # settle -> bot_shot(n) -> local_fp -> done
var _bot_shot_index: int = 0
var _next_bot_shot_t: float = INITIAL_SETTLE
var _cam_wait_left: int = 0
var _after_cam_wait: Callable = Callable()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)


func _process(delta: float) -> bool:
	if not _started:
		_started = true
		return _start()
	_t += delta

	match _phase:
		"settle":
			if _t >= INITIAL_SETTLE:
				_phase = "bot_wait"
			return false
		"bot_wait":
			if _t >= _next_bot_shot_t:
				_begin_bot_shot()
			return false
		"cam_wait":
			_cam_wait_left -= 1
			if _cam_wait_left > 0:
				return false
			return _after_cam_wait.call()
	return false


func _start() -> bool:
	MatchConfig.mode_id = "tdm"
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 3
	MatchConfig.bot_difficulty = MatchConfig.Difficulty.VETERAN

	var net := NetworkManager.get_net(self)
	net.host()

	if not ResourceLoader.exists(LEVEL):
		return _fail("carte introuvable : %s" % LEVEL)
	var scene: PackedScene = load(LEVEL)
	_world = scene.instantiate()
	# Skip l'écran de sélection d'agent (plein écran, couvrirait la capture) —
	# spawn immédiat de l'hôte comme joueur local, même stratagème que
	# tools/map_shots.gd.
	if _world.get("agent_select") != null:
		_world.set("agent_select", false)
	_world.set("allow_bot_fill", true)
	root.add_child(_world)
	current_scene = _world

	_spectator_cam = Camera3D.new()
	root.add_child(_spectator_cam)

	print("CHAR_INGAME_SHOTS_START level=%s" % LEVEL)
	return false


# ------------------------------------------------------------ 3e personne (bots)
func _begin_bot_shot() -> void:
	_bot_shot_index += 1
	_next_bot_shot_t = _t + BOT_SHOT_INTERVAL
	var bot := _pick_bot(_bot_shot_index)
	if bot == null:
		push_warning("char_ingame_shots : aucun bot trouvé pour la capture %d" % _bot_shot_index)
		_advance_after_bot_shots()
		return
	_frame_camera_on(bot)
	_begin_cam_wait(Callable(self, "_shoot_bot"))


func _shoot_bot() -> bool:
	_capture("bot_%d_tp" % _bot_shot_index)
	if _bot_shot_index >= BOT_SHOTS:
		_advance_after_bot_shots()
	else:
		_phase = "bot_wait"
	return false


func _advance_after_bot_shots() -> void:
	_begin_local_fp_shot()  # transitionne vers "cam_wait" (ou termine directement).


## Corps de joueur de l'équipe/bot n° `index` (1-based, cycle si moins de bots
## que `BOT_SHOTS` sont vivants) parmi les joueurs `is_bot`.
func _pick_bot(index: int) -> Node3D:
	var players := _world.get_node_or_null(_world.players_root) if _world else null
	if players == null:
		return null
	var bots: Array = []
	for p in players.get_children():
		if bool(p.get("is_bot")):
			bots.append(p)
	if bots.is_empty():
		return null
	return bots[(index - 1) % bots.size()] as Node3D


## Cadrage 3/4 arrière — essaie plusieurs distances (la plus grande d'abord)
## et garde la première dont la ligne de vue body -> caméra n'est pas
## obstruée (un port est plein de conteneurs/murs proches, la caméra finit
## souvent DANS le décor sans ce filet de sécurité).
const _FRAME_DISTANCES := [3.0, 2.0, 1.2, 0.7]

func _frame_camera_on(body: Node3D) -> void:
	var back := body.global_transform.basis.z    # avant = -Z, donc +Z = derrière.
	var side := body.global_transform.basis.x
	var look_pos := body.global_position + Vector3(0, 1.1, 0)
	var space := root.get_world_3d().direct_space_state
	var chosen := body.global_position + back * _FRAME_DISTANCES[-1] + side * 0.5 + Vector3(0, 1.7, 0)
	for dist in _FRAME_DISTANCES:
		var d: float = dist
		var candidate: Vector3 = body.global_position + back * d + side * (d * 0.45) + Vector3(0, 1.6, 0)
		var query := PhysicsRayQueryParameters3D.create(look_pos, candidate)
		query.exclude = [body]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			chosen = candidate
			break
	_spectator_cam.global_position = chosen
	_spectator_cam.look_at(look_pos, Vector3.UP)
	_spectator_cam.current = true


# ------------------------------------------------------------ 1re personne (local)
func _begin_local_fp_shot() -> void:
	var local_player := get_first_node_in_group("local_player")
	if local_player == null:
		push_warning("char_ingame_shots : aucun joueur local (spawn pas encore résolu ?)")
		_finish()
		return
	var cam: Camera3D = local_player.get("camera")
	if cam == null:
		_finish()
		return
	cam.current = true
	_begin_cam_wait(Callable(self, "_shoot_local_fp"))


func _shoot_local_fp() -> bool:
	_capture("local_fp")
	_finish()
	return false


# ------------------------------------------------------------ utilitaires
func _begin_cam_wait(after: Callable) -> void:
	_cam_wait_left = CAMERA_SETTLE_FRAMES
	_after_cam_wait = after
	_phase = "cam_wait"


func _capture(name: String) -> void:
	var img := root.get_texture().get_image()
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var path := "%s/%s.png" % [_out_dir, name]
	var err := img.save_png(path)
	print("CHAR_SHOT %s -> %s (err=%d)" % [name, path, err])


func _finish() -> void:
	print("CHAR_INGAME_SHOTS_DONE")
	quit(0)


func _fail(reason: String) -> bool:
	print("CHAR_INGAME_SHOTS_FAIL ", reason)
	quit(1)
	return true
