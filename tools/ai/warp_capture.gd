## warp_capture.gd
## Outil de VÉRIFICATION VISUELLE (tâche "bots humains" passe 2, contrat
## obligatoire : "capture a short sequence of a bot STRAFING or backpedalling
## in combat") — héberge Shipment TDM avec 1 bot (même boot minimal que
## tools/style/capture_shipment.gd), puis IMPOSE au bot un déplacement latéral
## (ou arrière) CONTRÔLÉ pendant que son cap (`rotation.y`, "visée") reste
## figé -- démontre LocomotionWarp.gd sans dépendre du hasard d'un vrai combat
## IA (délai incertain, direction/durée non garanties). Le déplacement FORCÉ
## est une téléportation directe de `global_position`/`rotation.y` (jamais
## `move_and_slide()`) : LocomotionWarp ne lit que `Skeleton3D.global_transform`
## (voir sa docstring, "Vitesse RECALCULÉE par différence de position"), donc
## indifférent à la façon dont cette position a changé.
##
## 6 captures espacées de 0.15 s (CAPTURE_INTERVAL_S), caméra FIXE posée une
## seule fois au moment du verrouillage (jamais réorientée sur le cap du bot
## ensuite, contrat "NOT attached to its yaw") — 3/4 arrière-latéral (voir
## `_setup_camera`) : assez de face pour juger si le buste/l'arme restent
## alignés sur la visée d'origine, assez de côté pour voir les jambes/hanches
## suivre le déplacement.
##
## Usage :
##   "%GODOT%" --path . --screen 1 -s res://tools/ai/warp_capture.gd -- \
##       --mode=strafe [--out=res://reports/checkpoints/2026-09-27_bots]
##   --mode=backward pour le recul (résiduel de hanches + lecture inversée,
##   voir LocomotionWarp.backward_hip_yaw_deg/is_backward_locomotion).
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const _SETTLE_FRAMES := 120     ## ~2 s : bot spawné, modèle chargé, LocomotionWarp attaché.
const _CAPTURE_INTERVAL_S := 0.15
const _CAPTURE_COUNT := 6
const _DRIFT_SPEED_MPS := 1.8   ## Vitesse latérale/arrière imposée (walk typique) -- assez lent pour rester bien cadré sur les 6 captures (~1 m de dérive totale).

var _out_dir := "res://reports/checkpoints/2026-09-27_bots"
var _mode := "strafe"           ## "strafe" (latéral) ou "backward" (recul).
var _frame := 0
var _world: Node = null
var _bot: Node3D = null
var _base_pos := Vector3.ZERO
var _base_rot_y := 0.0
var _drift_dir := Vector3.ZERO  ## Direction MONDE (plan XZ, normalisée) du déplacement imposé.
var _elapsed_since_lock_s := 0.0
var _shot_index := 0
var _next_shot_t := 0.0
var _images: Array[Image] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)
		elif a.begins_with("--mode="):
			_mode = a.get_slice("=", 1)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)


func _process(delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_boot()
		return false
	if _world == null:
		return false
	if _frame < _SETTLE_FRAMES:
		return false
	if _frame == _SETTLE_FRAMES:
		_lock_on_bot()
		if _bot == null:
			printerr("WARP_CAPTURE_FAIL no_bot")
			call_deferred("quit", 1)
			return true
		return false

	_elapsed_since_lock_s += delta
	_drive_bot()

	if _elapsed_since_lock_s >= _next_shot_t:
		_capture_frame()
		_shot_index += 1
		_next_shot_t += _CAPTURE_INTERVAL_S
		if _shot_index >= _CAPTURE_COUNT:
			_build_contact_sheet()
			call_deferred("quit", 0)
			return true
	return false


func _boot() -> void:
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 1
	var packed := load(_SHIPMENT) as PackedScene
	_world = packed.instantiate()
	# DIFFÉRÉ (même contrat que capture_shipment.gd/bot_behaviour_probe.gd) :
	# un add_child synchrone ici fait rater l'entrée dans l'arbre à l'autoload
	# `Look` (scripts/core/LevelLook.gd).
	get_root().add_child.call_deferred(_world)


## Premier bot trouvé sous `players_root` -- un seul existe (team_size=1).
func _lock_on_bot() -> void:
	var players_root := _world.get_node_or_null(_world.get("players_root"))
	if players_root == null:
		return
	for child in players_root.get_children():
		if bool(child.get("is_bot")):
			_bot = child as Node3D
			break
	if _bot == null:
		return
	_base_pos = _bot.global_position
	_base_rot_y = _bot.rotation.y
	var forward := BotLook.yaw_forward_dir(rad_to_deg(_base_rot_y))
	var right := Vector3(forward.z, 0.0, -forward.x)  # perpendiculaire (plan XZ) à la visée.
	_drift_dir = right if _mode == "strafe" else -forward
	_setup_camera(forward, right)


## Caméra FIXE, posée UNE SEULE FOIS (voir la docstring de tête) -- décalée
## PRINCIPALEMENT dans l'axe de la VISÉE d'origine (`forward`, jamais l'axe du
## déplacement imposé, `right`/`_drift_dir` : sinon le bot MARCHE VERS la
## caméra au lieu de glisser LATÉRALEMENT devant elle -- piège rencontré en
## plaçant la caméra sur `right`), avec un léger décalage latéral pour un 3/4
## plutôt qu'une face pure. Regarde un point FIXE (`eye_pos` du verrouillage) :
## le déplacement imposé (perpendiculaire à l'axe de vue) fait donc glisser le
## bot LATÉRALEMENT dans le cadre, à distance quasi constante de la caméra --
## assez de face pour juger de l'alignement buste/arme sur la visée
## d'origine, assez de côté pour voir les jambes suivre le déplacement.
func _setup_camera(forward: Vector3, right: Vector3) -> void:
	var eye_pos: Vector3 = _bot.get("head").global_position if _bot.get("head") != null else _base_pos + Vector3(0, 1.6, 0)
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.position = eye_pos + forward * 2.0 + right * 2.6 + Vector3(0, 0.2, 0)
	cam.look_at(eye_pos, Vector3.UP)
	cam.current = true


## Téléportation directe (JAMAIS move_and_slide, voir la docstring de tête) :
## `global_position` dérive de `_base_pos` le long de `_drift_dir` à
## `_DRIFT_SPEED_MPS`, `rotation.y` reste figé sur le cap de verrouillage --
## simule un strafe/recul à vitesse et cap CONSTANTS, sans dépendre du combat
## IA réel.
func _drive_bot() -> void:
	if _bot == null or not is_instance_valid(_bot):
		return
	_bot.global_position = _base_pos + _drift_dir * (_DRIFT_SPEED_MPS * _elapsed_since_lock_s)
	_bot.rotation.y = _base_rot_y


func _capture_frame() -> void:
	var img := get_root().get_texture().get_image()
	if img == null:
		push_error("warp_capture: pas d'image (lancé --headless ? voir l'en-tête)")
		return
	_images.append(img)
	_save(img, "warp_%d.png" % _shot_index)


func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name)
	var abs_dir := ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var err := img.save_png(path)
	print("warp_capture: ", name, " -> ", path, " (err=", err, ")")


## Planche-contact 3x2 (mosaïque des 6 captures, réduites au tiers) --
## vérification rapide sans ouvrir 6 fichiers séparés.
func _build_contact_sheet() -> void:
	if _images.is_empty():
		return
	var w := _images[0].get_width()
	var h := _images[0].get_height()
	var cols := 3
	var rows := 2
	var thumb_w := w / cols
	var thumb_h := h / rows
	var sheet := Image.create(thumb_w * cols, thumb_h * rows, false, Image.FORMAT_RGBA8)
	for i in _images.size():
		var thumb := (_images[i] as Image).duplicate() as Image
		thumb.convert(Image.FORMAT_RGBA8)
		thumb.resize(thumb_w, thumb_h)
		var col := i % cols
		var row := int(i / cols)
		sheet.blit_rect(thumb, Rect2i(0, 0, thumb_w, thumb_h), Vector2i(col * thumb_w, row * thumb_h))
	_save(sheet, "warp_sheet.png")
