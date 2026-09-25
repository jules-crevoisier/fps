## capture_shots.gd
## Capture d'écran EN FENÊTRÉ (comme tools/screenshot.gd, lu mais non modifié)
## pour les états UI qui n'ont pas de scène dédiée ou nécessitent d'être
## forcés (menu d'achat ouvert, page de fin) — voir contract-r3.md "R3-UI —
## acceptance" #6. Écrit `SCREENSHOT_OK <out>` puis quitte (0), ou
## `SCREENSHOT_FAIL <raison>` et quitte (1).
##
##   godot --resolution 1920x1080 --path . -s res://tests/ui/capture_shots.gd -- \
##       --target=agent_select|buy|end|hud|options|hitmarker_normal|hitmarker_headshot| \
##                hitmarker_kill|damage_direction|vignette|kill_word|kill_word_headshot| \
##                killfeed_local \
##       --out=C:/tmp/shot.png [--wait=90] [--settle=20] [--team=0|1]
##
## `--team=` (relance QA UX-01, cibles `end`/`killfeed_local` UNIQUEMENT) :
## force l'équipe locale affichée (voir GameHUD.debug_force_end/
## debug_force_killfeed_local, `local_team_override`) — capture les DEUX
## perspectives (allié/ennemi RELATIF au joueur local) sans devoir spawner un
## second joueur sur l'autre équipe. Omis (défaut -1) : équipe RÉELLE du
## joueur local, comportement historique inchangé.
##
## `--resolution WxH` est un flag MOTEUR natif de Godot (avant `-s`, hors des
## arguments utilisateur après `--`) : la fenêtre s'ouvre déjà à cette taille
## (stretch canvas_items+expand du projet). Deux passes (1920x1080, 1280x800)
## couvrent design.md v2 §12 "1920×1080 ... 1280×800".
extends SceneTree

const TEST_ARENA := "res://scenes/levels/test_arena.tscn"
const AGENT_SELECT_SCRIPT := preload("res://scripts/ui/AgentSelectScreen.gd")
const OPTIONS_SCRIPT := preload("res://scripts/ui/OptionsMenu.gd")
const LEVEL_LOOK_SCRIPT := preload("res://scripts/core/LevelLook.gd")

var _target: String = ""
var _out: String = ""
var _wait_frames: int = 90
var _settle_frames: int = 20
## Voir la docstring d'en-tête `--team=` : -1 = équipe réelle du joueur local.
var _local_team: int = -1

var _inst: Node
var _frame: int = 0
var _phase: int = 0
var _phase_frame: int = 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--target="):
			_target = a.get_slice("=", 1)
		elif a.begins_with("--out="):
			_out = a.get_slice("=", 1)
		elif a.begins_with("--wait="):
			_wait_frames = int(a.get_slice("=", 1))
		elif a.begins_with("--settle="):
			_settle_frames = int(a.get_slice("=", 1))
		elif a.begins_with("--team="):
			_local_team = int(a.get_slice("=", 1))

func _process(_delta: float) -> bool:
	if _out.is_empty() or _target.is_empty():
		return _fail("--target et --out sont requis")
	_frame += 1
	match _target:
		"agent_select":
			return _run_agent_select()
		"options":
			return _run_standalone(OPTIONS_SCRIPT)
		"buy":
			return _run_in_match("BuyMenu", "debug_force_open", [])
		"end":
			return _run_in_match("HUD", "debug_force_end", [0, 40, 27, _local_team])
		"hud":
			return _run_in_match_idle()
		"hitmarker_normal":
			return _run_in_match("HUD", "debug_force_hit_marker", [HitFeedback.MARKER_NORMAL])
		"hitmarker_headshot":
			return _run_in_match("HUD", "debug_force_hit_marker", [HitFeedback.MARKER_HEADSHOT])
		"hitmarker_kill":
			return _run_in_match("HUD", "debug_force_hit_marker", [HitFeedback.MARKER_KILL])
		"damage_direction":
			return _run_in_match("HUD", "debug_force_damage_direction", [55.0])
		"vignette":
			return _run_in_match("HUD", "debug_force_vignette", [0.1])
		"kill_word":
			return _run_in_match("HUD", "debug_force_kill_word", [false])
		"kill_word_headshot":
			return _run_in_match("HUD", "debug_force_kill_word", [true])
		"killfeed_local":
			return _run_in_match("HUD", "debug_force_killfeed_local", [_local_team])
	return _fail("cible inconnue : %s" % _target)

func _run_agent_select() -> bool:
	if _inst == null:
		_inst = AGENT_SELECT_SCRIPT.new()
		_inst.countdown = 45.0  # assez long pour ne jamais verrouiller pendant la capture
		root.add_child(_inst)
		return false
	if _frame < _wait_frames:
		return false
	_capture()
	return true

## Instancie un `Control`/`CanvasLayer` autonome (pas de scène 3D derrière) —
## utilisé pour "options" (OptionsMenu.gd, pas de flux de match nécessaire).
func _run_standalone(script: Script) -> bool:
	if _inst == null:
		_inst = script.new()
		if _inst is Control:
			_inst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(_inst)
		return false
	if _frame < _wait_frames:
		return false
	_capture()
	return true

## HUD en jeu SANS état forcé (design.md v2 §12 : capture "HUD en match" de
## référence — vitalité/munitions/capacités/score au repos, comme un joueur
## qui vient de spawn en entraînement/arène).
func _run_in_match_idle() -> bool:
	if _inst == null:
		var look: Node = LEVEL_LOOK_SCRIPT.new()
		root.add_child(look)
		var packed := load(TEST_ARENA) as PackedScene
		if packed == null:
			return _fail("scène introuvable : %s" % TEST_ARENA)
		_inst = packed.instantiate()
		if _inst.get("agent_select") != null:
			_inst.set("agent_select", false)
		root.add_child(_inst)
		current_scene = _inst
		return false
	if _frame < _wait_frames:
		return false
	_capture()
	return true

func _run_in_match(node_name: String, method: String, args: Array) -> bool:
	if _inst == null:
		var look: Node = LEVEL_LOOK_SCRIPT.new()
		root.add_child(look)
		var packed := load(TEST_ARENA) as PackedScene
		if packed == null:
			return _fail("scène introuvable : %s" % TEST_ARENA)
		_inst = packed.instantiate()
		if _inst.get("agent_select") != null:
			_inst.set("agent_select", false)
		root.add_child(_inst)
		current_scene = _inst
		return false
	if _frame < _wait_frames:
		return false
	if _phase == 0:
		var target_node := _inst.get_node_or_null(node_name)
		if target_node == null or not target_node.has_method(method):
			return _fail("nœud/méthode introuvable : %s.%s" % [node_name, method])
		target_node.callv(method, args)
		_phase = 1
		_phase_frame = 0
		return false
	_phase_frame += 1
	if _phase_frame < _settle_frames:
		return false
	_capture()
	return true

func _capture() -> void:
	var img := root.get_texture().get_image()
	var dir := _out.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var save_err := img.save_png(_out)
	if save_err != OK:
		print("SCREENSHOT_FAIL échec de l'écriture PNG (%d)" % save_err)
		quit(1)
		return
	print("SCREENSHOT_OK ", _out)
	quit(0)

func _fail(reason: String) -> bool:
	print("SCREENSHOT_FAIL ", reason)
	quit(1)
	return true
