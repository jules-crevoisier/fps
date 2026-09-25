## fp_shots.gd
## Capture EN FENÊTRÉ (swapchain requis, comme tools/blender/viewmodel_shots.gd
## et tools/char_ingame_shots.gd) la vue première personne (ViewModel : arme +
## gants) pour LES 10 ARMES de WeaponDatabase (ART-12, §5.3), plus un sprint et
## un ADS. Force le loadout local via Weapon.server_set_loadout (même pair =
## serveur ET propriétaire en solo, donc appel direct, pas de RPC — même
## stratagème que viewmodel_shots.gd).
##
##   godot --path . -s res://tools/fp_shots.gd -- --out=<dossier>
##
## Par arme (id 0..9 de WeaponDatabase.PATHS) :
##   "<out>/fp_<arme>.png"      — couleurs réelles, pose hanche.
##   "<out>/fp_<arme>_mask.png" — MASQUE (CHK-28/29/30, voir `_capture_mask`) :
##     silhouette blanche pleine de l'arme+gants sur fond noir uni, RIEN
##     d'autre au monde ne peut y apparaître (ViewModel.set_mask_mode +
##     Camera3D.cull_mask restreint au calque dédié + environnement fond noir
##     forcé) — un simple seuil "pixel non noir" donne un masque binaire fiable
##     même pour des matériaux d'arme presque noirs (ex. la crosse).
## Si le modèle .glb d'une arme est introuvable (arme pas encore livrée par
## ART-13), imprime `FP_SHOT_SKIP <arme> <raison>` et passe à la suivante SANS
## faire échouer le run.
## Plus "<out>/fp_sprint.png"/"_mask.png" et "<out>/fp_ads.png"/"_mask.png".
## "<out>/fp_shots.json" résume chaque capture : nom, id, catégorie, modèle
## trouvé ou non, et pour les poses hanche la position ÉCRAN normalisée
## (0..1, origine haut-gauche) du bout du canon (empty "Muzzle" projeté via
## `Camera3D.unproject_position` — CHK-30 "marqueur muzzle" : une coordonnée
## exacte plutôt qu'un pixel à chercher visuellement) et la taille de viewport.
## Le bloc "ads" porte en plus `ads_sight_top_y` (FP-01, §5.3 « bord haut de la
## hausse à y 0,50 ± 0,02 », `viewmodel.ads_sight_top_y` de tokens.json) : voir
## `_measure_ads_sight_top_y` — aucune des 7 armes peintes ne porte d'empty
## "Sight" dédié (seuls "Muzzle"/"Foregrip" existent, tools/blender/
## make_weapons.py), donc mesuré sur le MASQUE ADS déjà produit plutôt que sur
## un repère géométrique manquant.
## Imprime `FP_SHOT <nom> -> <chemin>` par capture puis `FP_SHOTS_DONE` (0) ou
## `FP_SHOTS_FAIL <raison>` (1).
extends SceneTree

const LEVEL := "res://scenes/levels/test_arena.tscn"
const SETTLE_FRAMES := 150
const POSE_SETTLE_FRAMES := 30
## Le nouveau matériau/calque de masque (ViewModel.set_mask_mode) doit avoir
## fini de RENDRE au moins une fois avant capture — quelques frames de marge
## (le changement lui-même est instantané, pas besoin de 150 comme pour la
## pose hanche/ADS/sprint qui elle anime réellement vers sa cible).
const MASK_SETTLE_FRAMES := 5
## Calque dédié à l'arme+gants — voir ViewModel._MASK_RENDER_LAYER (même
## valeur, dupliquée ici : fp_shots.gd n'a pas accès aux constantes privées
## d'un autre script, seul son effet — le calque posé par `set_mask_mode` —
## doit rester en phase avec cette valeur si l'une des deux change un jour).
const MASK_RENDER_LAYER := 20
## Bande centrale utilisée par `_measure_ads_sight_top_y` — même largeur que
## `viewmodel.center_clear_zone` de tokens.json (CHK-28, 20 % × 20 %), réutilisée
## ici faute d'empty "Sight" dédié : l'organe de visée est approximé par le
## pixel non noir le plus haut du masque ADS dans cette colonne centrale
## (l'endroit où le joueur regarde À TRAVERS l'arme en visée), pas par une
## mesure géométrique exacte comme le fait `_pose_result` pour le canon.
const ADS_SIGHT_CENTER_BAND := 0.20

var _out_dir: String = ""
var _started: bool = false
var _player: PlayerController = null
var _weapon: Weapon = null
var _camera: Camera3D = null
var _view_model: ViewModel = null
var _hud: CanvasLayer = null
var _mask_env: Environment = null
var _cull_mask_normal: int = 0
var _shot_index: int = 0
var _phase: String = "wait_spawn"
# wait_spawn -> equip -> settle -> capture -> mask_setup -> mask_settle ->
# mask_capture -> equip (arme suivante) -> ... -> pose_sprint_equip -> ... ->
# pose_ads_capture -> ads_mask_setup -> ads_mask_settle -> ads_mask_capture -> done
var _settle_frames: int = 0
var _results: Array = []
var _sprint_result: Dictionary = {}
var _ads_result: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		return _start()

	match _phase:
		"wait_spawn":
			return _wait_spawn()
		"equip":
			return _equip_next_weapon()
		"settle":
			return _tick_settle("capture")
		"capture":
			_capture_current_weapon()
			_phase = "mask_setup"
			return false
		"mask_setup":
			_enter_mask_mode()
			_phase = "mask_settle"
			_settle_frames = 0
			return false
		"mask_settle":
			return _tick_mask_settle("mask_capture")
		"mask_capture":
			_capture_mask(_weapon_shot_name(_current_weapon_id()))
			_exit_mask_mode()
			_shot_index += 1
			_phase = "equip"
			return false
		"pose_sprint_equip":
			_equip_pose_weapon()
			_phase = "pose_sprint_settle"
			return false
		"pose_sprint_settle":
			return _tick_settle("pose_sprint_transition")
		"pose_sprint_transition":
			_settle_frames = 0
			_phase = "pose_sprint_capture"
			return false
		"pose_sprint_capture":
			# `Sprint.physics_update` retombe en `Idle` DÈS que `player.
			# input_vector` est nul (scripts/player/states/Sprint.gd) —
			# lui-même réécrit CHAQUE tick physique depuis `input.move`, que
			# `PlayerInput._physics_process` efface à son tour si la souris
			# n'est pas capturée (`reads_devices`, voir sa doc) : il faut
			# donc réaffirmer l'entrée ET l'état À CHAQUE frame de ce settle,
			# pas une seule fois à la transition — même stratagème que
			# `aim_held` ci-dessous pour la pose ADS.
			var input_node = _player.get_node_or_null("Input")
			if input_node:
				input_node.move = Vector2(0.0, -1.0)
			var sm = _player.state_machine
			if sm and sm.current_name != "Sprint":
				sm.transition_to("Sprint")
			_settle_frames += 1
			if _settle_frames < POSE_SETTLE_FRAMES:
				return false
			_capture("fp_sprint")
			_sprint_result = _pose_result("fp_sprint")
			var input_node2 = _player.get_node_or_null("Input")
			if input_node2:
				input_node2.move = Vector2.ZERO
			var sm2 = _player.state_machine
			if sm2:
				sm2.transition_to("Idle")
			_phase = "sprint_mask_setup"
			return false
		"sprint_mask_setup":
			_enter_mask_mode()
			_phase = "sprint_mask_settle"
			_settle_frames = 0
			return false
		"sprint_mask_settle":
			return _tick_mask_settle("sprint_mask_capture")
		"sprint_mask_capture":
			_capture_mask("fp_sprint")
			_exit_mask_mode()
			_phase = "pose_ads_settle"
			_settle_frames = 0
			return false
		"pose_ads_settle":
			var input_node = _player.get_node_or_null("Input")
			if input_node:
				input_node.aim_held = true
			_settle_frames += 1
			if _settle_frames < SETTLE_FRAMES:
				return false
			_phase = "pose_ads_capture"
			return false
		"pose_ads_capture":
			_capture("fp_ads")
			_ads_result = _pose_result("fp_ads")
			_phase = "ads_mask_setup"
			return false
		"ads_mask_setup":
			_enter_mask_mode()
			_phase = "ads_mask_settle"
			_settle_frames = 0
			return false
		"ads_mask_settle":
			return _tick_mask_settle("ads_mask_capture")
		"ads_mask_capture":
			_capture_mask("fp_ads")
			_ads_result["ads_sight_top_y"] = _measure_ads_sight_top_y("fp_ads")
			_exit_mask_mode()
			_finish()
			return false
	return false


func _start() -> bool:
	if _out_dir.is_empty():
		print("FP_SHOTS_FAIL --out requis")
		quit(1)
		return true
	var look: Node = load("res://scripts/core/LevelLook.gd").new()
	root.add_child(look)
	if not ResourceLoader.exists(LEVEL):
		return _fail("carte introuvable : %s" % LEVEL)
	var packed := load(LEVEL) as PackedScene
	var inst := packed.instantiate()
	if inst.get("agent_select") != null:
		inst.set("agent_select", false)
	root.add_child(inst)
	current_scene = inst
	print("FP_SHOTS_START level=%s" % LEVEL)
	return false


func _wait_spawn() -> bool:
	_player = get_first_node_in_group("local_player") as PlayerController
	if _player == null:
		_settle_frames += 1
		if _settle_frames > 600:
			return _fail("timeout en attente du joueur local")
		return false
	_weapon = _player.get_node_or_null("Weapon") as Weapon
	if _weapon == null:
		return _fail("pas de node Weapon sur le joueur local")
	_camera = _player.get_node_or_null("Head/Camera3D") as Camera3D
	if _camera == null:
		return _fail("pas de Camera3D sur le joueur local (Head/Camera3D)")
	_view_model = _camera.get_node_or_null("ViewModel") as ViewModel
	if _view_model == null:
		return _fail("pas de ViewModel sous Head/Camera3D")
	# Le HUD (CanvasLayer "HUD", scripts/ui/GameHUD.gd — réticule, barre de vie,
	# barre de capacités, compteur de munitions) dessine par-dessus la 3D, donc
	# ni `Camera3D.cull_mask` ni son `environment` ne l'affectent : sans le
	# cacher, un simple seuil "pixel non noir" sur le masque compterait AUSSI
	# ses pixels (le réticule tombe justement dans le carré central que
	# CHK-28 doit pouvoir mesurer comme VIDE d'arme).
	_hud = current_scene.get_node_or_null("HUD") as CanvasLayer
	_cull_mask_normal = _camera.cull_mask
	# Fond noir uni forcé (voir doc de classe) : les valeurs par défaut
	# d'ambiance/tonemapping n'ont aucune prise sur le résultat, ni sur le
	# fond (BG_COLOR pur, jamais de ciel/ambiance) ni sur l'arme+gants
	# (`ViewModel.set_mask_mode` les passe en matériau NON ÉCLAIRÉ blanc).
	_mask_env = Environment.new()
	_mask_env.background_mode = Environment.BG_COLOR
	_mask_env.background_color = Color.BLACK
	_phase = "equip"
	return false


## Id courant dans WeaponDatabase.PATHS (0..9) pour `_shot_index`.
func _current_weapon_id() -> int:
	return _shot_index


func _weapon_shot_name(id: int) -> String:
	var stem: String = (WeaponDatabase.PATHS[id] as String).get_file().get_basename()
	return "fp_%s" % stem


func _equip_next_weapon() -> bool:
	if _shot_index >= WeaponDatabase.PATHS.size():
		_phase = "pose_sprint_equip"
		return false
	var id := _current_weapon_id()
	var path := Weapon.model_path_for(id)
	if path.is_empty() or not ResourceLoader.exists(path):
		print("FP_SHOT_SKIP %s modele introuvable (%s)" % [_weapon_shot_name(id), path])
		_results.append({
			"name": _weapon_shot_name(id), "weapon_id": id, "model_found": false,
		})
		_shot_index += 1
		return false
	var ids: Array[int] = [id, id]
	_weapon.server_set_loadout(ids)
	_settle_frames = 0
	_phase = "settle"
	return false


func _equip_pose_weapon() -> void:
	# N'importe laquelle des armes livrées convient pour sprint/ADS (juste
	# une pose représentative) ; Ravage (fusil d'assaut, id 4) si son modèle
	# existe, sinon la première arme dont le modèle est déjà livré.
	var id := 4
	if not ResourceLoader.exists(Weapon.model_path_for(id)):
		id = 0
		for i in WeaponDatabase.PATHS.size():
			if ResourceLoader.exists(Weapon.model_path_for(i)):
				id = i
				break
	var ids: Array[int] = [id, id]
	_weapon.server_set_loadout(ids)
	_settle_frames = 0


func _tick_settle(next_phase: String) -> bool:
	_settle_frames += 1
	if _settle_frames < SETTLE_FRAMES:
		return false
	_phase = next_phase
	return false


func _tick_mask_settle(next_phase: String) -> bool:
	_settle_frames += 1
	if _settle_frames < MASK_SETTLE_FRAMES:
		return false
	_phase = next_phase
	return false


func _capture_current_weapon() -> void:
	var id := _current_weapon_id()
	var name := _weapon_shot_name(id)
	_capture(name)
	_results.append(_pose_result(name, id))


## Position ÉCRAN normalisée (0..1, origine haut-gauche comme §5.3) du bout du
## canon (`ViewModel.muzzle_global_position`) — CHK-30. `weapon_id` optionnel
## (absent pour sprint/ADS, dont §5.3 ne contraint pas la position du canon).
func _pose_result(name: String, weapon_id: int = -1) -> Dictionary:
	var vp_size := root.get_visible_rect().size
	var screen := _camera.unproject_position(_view_model.muzzle_global_position())
	var entry := {
		"name": name,
		"muzzle_screen": [screen.x / vp_size.x, screen.y / vp_size.y],
		"viewport_size": [vp_size.x, vp_size.y],
	}
	if weapon_id >= 0:
		var cfg := WeaponDatabase.get_by_id(weapon_id)
		entry["weapon_id"] = weapon_id
		entry["model_found"] = true
		entry["category"] = cfg.category if cfg else -1
		entry["weapon_name"] = cfg.weapon_name if cfg else ""
	return entry


## Bascule caméra+ViewModel en mode masque (voir doc de classe et
## ViewModel.set_mask_mode) : rien d'autre que l'arme+gants ne peut apparaître
## dans la capture qui suit (`_capture_mask`).
func _enter_mask_mode() -> void:
	_view_model.set_mask_mode(true)
	_camera.cull_mask = 1 << (MASK_RENDER_LAYER - 1)
	_camera.environment = _mask_env
	if _hud:
		_hud.visible = false


func _exit_mask_mode() -> void:
	_view_model.set_mask_mode(false)
	_camera.cull_mask = _cull_mask_normal
	_camera.environment = null
	if _hud:
		_hud.visible = true


func _capture(name: String) -> void:
	var img := root.get_texture().get_image()
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var path := "%s/%s.png" % [_out_dir, name]
	var err := img.save_png(path)
	print("FP_SHOT %s -> %s (err=%d)" % [name, path, err])


func _capture_mask(name: String) -> void:
	_capture("%s_mask" % name)


## Position ÉCRAN normalisée (0..1, haut-gauche, même convention que
## `_pose_result`) du pixel non noir le plus haut du masque `<name>_mask.png`
## (déjà écrit sur disque par `_capture_mask` juste avant, relu ici plutôt que
## re-rendu) DANS la bande centrale `ADS_SIGHT_CENTER_BAND` — voir sa doc.
## -1.0 si le masque est introuvable ou entièrement noir dans cette bande
## (repli sûr, jamais un crash : `fp_shots.json` porte alors une valeur hors
## plage [0,1] facilement reconnaissable côté lecteur plutôt qu'un champ nul).
func _measure_ads_sight_top_y(name: String) -> float:
	var path := "%s/%s_mask.png" % [_out_dir, name]
	var img := Image.load_from_file(path)
	if img == null:
		return -1.0
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return -1.0
	var half := ADS_SIGHT_CENTER_BAND * 0.5
	var x0 := int((0.5 - half) * w)
	var x1 := int((0.5 + half) * w)
	for y in h:
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			if c.r > 0.5 or c.g > 0.5 or c.b > 0.5:
				return float(y) / float(h)
	return -1.0


func _write_result_json() -> void:
	var data := {
		"weapons": _results,
		"sprint": _sprint_result,
		"ads": _ads_result,
	}
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var path := "%s/fp_shots.json" % _out_dir
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


func _finish() -> void:
	_write_result_json()
	print("FP_SHOTS_DONE")
	quit(0)


func _fail(reason: String) -> bool:
	print("FP_SHOTS_FAIL ", reason)
	quit(1)
	return true
