## action_weapons_capture.gd
## Captures + MESURE de cadrage première-personne (tâche "cadrage FP quatre armes", 2026-09-28) --
## remplace la version "quatre armes" (2026-09-28, ids 2-5 seulement, pas de mesure) : couvre
## maintenant LES SIX armes du catalogue (Ravage/Revolver ids 0/1 en RÉFÉRENCE, HORS PÉRIMÈTRE de
## réglage -- voir FPArmsRig._GRIP_POS_BY_ID -- + Rafale/Fracas/Verdict/Aiguille ids 2-5), hanche ET
## visée (ADS) pour chacune, plus un masque (silhouette blanche sur fond noir, même recette que
## l'historique tools/fp_shots.gd -- ViewModel.set_mask_mode + Camera3D.cull_mask restreint au calque
## dédié) qui sert à calculer bbox/centroïde/couverture d'écran, et la position écran du canon
## (empty "Muzzle" projeté via Camera3D.unproject_position). Un frame MI-CYCLE (pompe/levier/verrou
## à mi-course, chargeur en plein dip de rechargement pour la Rafale) par arme À PIÈCE MOBILE
## (ViewModel.action_node_name_for) -- rien pour Ravage/Revolver (aucune pièce dédiée).
##
## Force le loadout du joueur local ARME PAR ARME via `Weapon.server_set_loadout` (appel direct
## serveur -- le solo/hôte EST le serveur) plutôt que par un item de boutique/une sélection de
## loadout (hors du périmètre de cette tâche) : c'est un outil de VÉRIFICATION visuelle, pas un flux
## de jeu. Déclenche un tir/rechargement RÉEL via les actions d'entrée ("fire"/"reload",
## Input.action_press -- même mécanisme que "aim" ci-dessous, déjà validé par le passage précédent)
## plutôt que de trafiquer les champs privés de ViewModel : simule un vrai joueur, pas un raccourci.
##
##   "%GODOT%" --screen 1 --path . -s res://tools/rigging/action_weapons_capture.gd
##
## Images : reports/checkpoints/2026-09-28_weapons_v3/<nom>_{hip,hip_mask,ads,ads_mask,cycle}.png.
## Mesures : reports/checkpoints/2026-09-28_weapons_v3/fp_framing.json (+ imprimées en console,
## FP_FRAMING <nom> <pose> ...).
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const OUT_DIR := "res://reports/checkpoints/2026-09-28_weapons_v3"

## Ids WeaponDatabase.PATHS -> nom de fichier. 0/1 = référence (Ravage/Revolver, jamais retouchés
## par cette tâche -- voir FPArmsRig._GRIP_POS_BY_ID) ; 2-5 = armes réglées par cette tâche.
const _WEAPONS := [
	{"id": 0, "name": "ravage"},
	{"id": 1, "name": "revolver"},
	{"id": 2, "name": "rafale"},
	{"id": 3, "name": "fracas"},
	{"id": 4, "name": "verdict"},
	{"id": 5, "name": "aiguille"},
]

## Délai (frames physiques, 60 Hz) après un changement d'arme avant capture -- laisse le viewmodel
## finir sa montée d'équipement (AnimState.start_equip) et le modèle 3D se recharger (`_refresh_model`).
const _SETTLE_FRAMES := 40
## Délai (frames) tenu en visée avant la capture ADS -- au-delà du plus lent `ads_time` du catalogue
## (0.28 s ≈ 17 frames à 60 Hz, Aiguille), marge pour la transition ADS ET l'apparition de ScopeOverlay.
const _ADS_SETTLE_FRAMES := 60
## Le nouveau matériau/calque de masque (ViewModel.set_mask_mode) doit avoir fini de RENDRE au moins
## une fois avant capture -- le changement lui-même est instantané, pas besoin d'un long settle.
const _MASK_SETTLE_FRAMES := 5
## Même calque que ViewModel._MASK_RENDER_LAYER (dupliqué ici, cet outil n'a pas accès aux constantes
## privées d'un autre script -- voir sa doc).
const _MASK_RENDER_LAYER := 20
## Résolution d'analyse du masque (sous-échantillonnée depuis le viewport 1920x1080 -- bbox/couverture/
## centroïde n'ont pas besoin de la pleine résolution, et une boucle par pixel en GDScript sur 1080p
## est lente ; le PNG sauvegardé, lui, reste plein cadre pour l'inspection visuelle).
const _ANALYSIS_SIZE := Vector2i(384, 216)
## Seuil "pixel non noir" (0-255, comme l'historique tools/review/style_check.py::load_mask_bool).
const _MASK_THRESHOLD := 127


class Driver extends Node:
	var tree: SceneTree
	var out_dir := OUT_DIR
	var player: PlayerController
	var weapon: Weapon
	var camera: Camera3D
	var view_model: ViewModel
	var hud: CanvasLayer
	var _cull_mask_normal: int = 0
	var _mask_env: Environment
	var _step := 0
	var _wait_left := 0
	var _weapon_index := 0
	var _results: Array = []
	var _current_entry: Dictionary = {}
	var _current_pose: Dictionary = {}

	func _physics_process(_delta: float) -> void:
		match _step:
			0:  # attente spawn/stabilisation initiale.
				_wait_left -= 1
				if _wait_left <= 0:
					_find_player()
					if player:
						player.set_process_unhandled_input(false)
						player.set_process_input(false)
						weapon = player.get_node_or_null("Weapon") as Weapon
						camera = player.get_node_or_null("Head/Camera3D") as Camera3D
						view_model = camera.get_node_or_null("ViewModel") as ViewModel if camera else null
						hud = tree.get_root().find_child("HUD", true, false) as CanvasLayer
						if camera:
							_cull_mask_normal = camera.cull_mask
						_mask_env = Environment.new()
						_mask_env.background_mode = Environment.BG_COLOR
						_mask_env.background_color = Color.BLACK
					_step = 1
			1:  # équipe l'arme courante.
				_equip_next()
			2:  # settle post-équipement.
				_wait_left -= 1
				if _wait_left <= 0:
					_step = 3
			3:  # capture hanche (couleur).
				_current_pose = {}
				_save_color("%s_hip" % _current_entry["name"])
				_step = 4
			4:  # masque hanche.
				_enter_mask_mode()
				_wait_left = _MASK_SETTLE_FRAMES
				_step = 5
			5:
				_wait_left -= 1
				if _wait_left <= 0:
					_measure_and_save_mask("hip")
					_exit_mask_mode()
					_step = 6
			6:  # entre en visée.
				Input.action_press("aim")
				_wait_left = _ADS_SETTLE_FRAMES
				_step = 7
			7:
				_wait_left -= 1
				if _wait_left <= 0:
					_save_color("%s_ads" % _current_entry["name"])
					_step = 8
			8:  # masque ADS.
				_enter_mask_mode()
				_wait_left = _MASK_SETTLE_FRAMES
				_step = 9
			9:
				_wait_left -= 1
				if _wait_left <= 0:
					_measure_and_save_mask("ads")
					_exit_mask_mode()
					Input.action_release("aim")
					_step = 10
			10:  # déclenche le geste mi-cycle (tir ou rechargement selon la pièce mobile de l'arme).
				_wait_left = 3  # laisse le relâchement de visée se stabiliser avant de tirer/recharger.
				_step = 11
			11:
				_wait_left -= 1
				if _wait_left <= 0:
					_step = _begin_cycle_capture()
			12:  # attente mi-cycle.
				_wait_left -= 1
				if _wait_left <= 0:
					_save_color("%s_cycle" % _current_entry["name"])
					_step = 13
			13:
				_results.append(_current_entry)
				_weapon_index += 1
				_step = 1

	func _equip_next() -> void:
		if _weapon_index >= _WEAPONS.size():
			_finish()
			return
		var entry: Dictionary = _WEAPONS[_weapon_index]
		_current_entry = {"id": entry["id"], "name": entry["name"]}
		if weapon:
			var ids: Array[int] = [int(entry["id"])]
			weapon.server_set_loadout(ids)
		_wait_left = _SETTLE_FRAMES
		_step = 2

	## Déclenche un tir (armes à pièce mobile PumpGrip/Lever/Bolt, cycle sur le TIR) ou un
	## rechargement (Rafale, "Magazine" -- animée par le dip de rechargement générique, PAS un
	## cycle de tir) selon `ViewModel.action_node_name_for` -- "" (Ravage/Revolver, aucune pièce
	## dédiée) saute directement l'étape sans capture "_cycle". Renvoie le PROCHAIN `_step`.
	func _begin_cycle_capture() -> int:
		var cfg := WeaponDatabase.get_by_id(int(_current_entry["id"]))
		var kind := ViewModel.action_node_name_for(cfg)
		if kind == "":
			return 13
		if kind == "Magazine":
			Input.action_press("reload")
			# Relâché dès la fin de cette frame -- un `reload` n'a besoin que du front montant
			# (`reload_pressed`, voir PlayerInput.gd), le tenir plus longtemps ne changerait rien.
			call_deferred("_release_action", "reload")
			_wait_left = maxi(int(cfg.reload_time * 0.4 * 60.0), 3)
			return 12
		Input.action_press("fire")
		call_deferred("_release_action", "fire")
		_wait_left = maxi(int(cfg.cycle_time * 0.5 * 60.0), 3)
		return 12

	func _release_action(action: String) -> void:
		Input.action_release(action)

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

	func _save_color(name: String) -> void:
		var img := _grab()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		img.save_png(ProjectSettings.globalize_path(out_dir.path_join("%s.png" % name)))
		print("ACTION_WEAPONS_SAVED ", name)

	func _grab() -> Image:
		return tree.get_root().get_texture().get_image()

	func _enter_mask_mode() -> void:
		if view_model:
			view_model.set_mask_mode(true)
		if camera:
			camera.cull_mask = 1 << (_MASK_RENDER_LAYER - 1)
			camera.environment = _mask_env
		if hud:
			hud.visible = false

	func _exit_mask_mode() -> void:
		if view_model:
			view_model.set_mask_mode(false)
		if camera:
			camera.cull_mask = _cull_mask_normal
			camera.environment = null
		if hud:
			hud.visible = true

	## Sauvegarde le masque plein cadre (inspection visuelle) PUIS mesure bbox/centroïde/couverture
	## sur une copie sous-échantillonnée (voir `_ANALYSIS_SIZE`) -- et la position écran du canon
	## (Camera3D.unproject_position, PAS lue sur le masque : une coordonnée exacte plutôt qu'un pixel
	## à chercher visuellement, même choix que l'historique tools/fp_shots.gd).
	func _measure_and_save_mask(pose: String) -> void:
		var name: String = "%s_%s_mask" % [_current_entry["name"], pose]
		var img := _grab()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		img.save_png(ProjectSettings.globalize_path(out_dir.path_join("%s.png" % name)))
		print("ACTION_WEAPONS_SAVED ", name)

		var small := img.duplicate() as Image
		small.resize(_ANALYSIS_SIZE.x, _ANALYSIS_SIZE.y, Image.INTERPOLATE_NEAREST)
		small.convert(Image.FORMAT_RGBA8)
		var stats := _analyze(small)

		var muzzle_screen := Vector2(-1.0, -1.0)
		var grip_screen := Vector2(-1.0, -1.0)
		var axis_angle_deg := 0.0
		if camera and view_model:
			var vp := tree.get_root().get_visible_rect().size
			var screen := camera.unproject_position(view_model.muzzle_global_position())
			muzzle_screen = Vector2(screen.x / vp.x, screen.y / vp.y)
			# "Grip" = origine du modèle d'arme courant (poignée -- voir la doc de tête de chaque
			# build_<id>.py, "origine = poignée") : le PARENT direct de l'empty "Muzzle" (voir chaque
			# build_<id>.py, `for o in (body, ..., muzzle, foregrip): o.parent = root`) EST ce nœud
			# racine, sur les 6 armes -- pas besoin d'un accès privé à ViewModel._model.
			var muzzle_node := view_model.find_child("Muzzle", true, false) as Node3D
			var grip_node := muzzle_node.get_parent() as Node3D if muzzle_node else null
			if grip_node:
				var gscreen := camera.unproject_position(grip_node.global_position)
				grip_screen = Vector2(gscreen.x / vp.x, gscreen.y / vp.y)
				var d := muzzle_screen - grip_screen
				# atan2 en repère ÉCRAN (x droite, y BAS -- origine haut-gauche, comme bbox/centroïde
				# ci-dessus) : un angle négatif signifie donc "le canon MONTE à l'écran depuis la
				# poignée" (y diminue vers le haut), positif = "le canon PLONGE vers le bas".
				axis_angle_deg = rad_to_deg(atan2(d.y, d.x))

		_current_entry[pose] = {
			"coverage_pct": stats["coverage_pct"],
			"bbox": stats["bbox"],
			"centroid": stats["centroid"],
			"muzzle_screen": [muzzle_screen.x, muzzle_screen.y],
			"grip_screen": [grip_screen.x, grip_screen.y],
			"axis_angle_deg": axis_angle_deg,
		}
		print("FP_FRAMING ", _current_entry["name"], " ", pose, " ", _current_entry[pose])

	## Bbox (normalisée 0..1, origine haut-gauche)/centroïde/couverture % d'un masque déjà réduit à
	## `_ANALYSIS_SIZE` -- seuil "pixel non noir" identique à l'historique
	## tools/review/style_check.py::load_mask_bool (`> 127` sur au moins un canal).
	func _analyze(img: Image) -> Dictionary:
		var w := img.get_width()
		var h := img.get_height()
		var data := img.get_data()
		var min_x := w
		var max_x := -1
		var min_y := h
		var max_y := -1
		var sum_x := 0.0
		var sum_y := 0.0
		var count := 0
		var idx := 0
		for y in h:
			for x in w:
				var r: int = data[idx]
				var g: int = data[idx + 1]
				var b: int = data[idx + 2]
				idx += 4
				if r > _MASK_THRESHOLD or g > _MASK_THRESHOLD or b > _MASK_THRESHOLD:
					count += 1
					sum_x += x
					sum_y += y
					if x < min_x:
						min_x = x
					if x > max_x:
						max_x = x
					if y < min_y:
						min_y = y
					if y > max_y:
						max_y = y
		if count == 0:
			return {"coverage_pct": 0.0, "bbox": [0.0, 0.0, 0.0, 0.0], "centroid": [0.0, 0.0]}
		return {
			"coverage_pct": float(count) / float(w * h) * 100.0,
			"bbox": [float(min_x) / w, float(min_y) / h, float(max_x + 1) / w, float(max_y + 1) / h],
			"centroid": [(sum_x / count) / w, (sum_y / count) / h],
		}

	## Verrou de cadrage (consigne du lead, 2026-09-28, après le 1er passage de cette tâche) : l'angle
	## d'axe écran (poignée -> canon, `axis_angle_deg` de `_measure_and_save_mask`) de chaque arme, en
	## pose HANCHE, doit rester à ±8° de celui de Ravage (référence jamais retouchée) -- sinon l'arme
	## lit comme "pointant vers le sol" (Rafale) ou "en bazooka" (Fracas) au lieu de suivre la même
	## diagonale que Ravage. Le point de canon écran doit aussi rester à ≤ 0,06 (distance euclidienne,
	## coordonnées normalisées 0..1) de celui de Ravage -- SAUF l'Aiguille, dont la lunette abaisse
	## légèrement le point de canon mesuré sans que ce soit un défaut de cadrage (toléré explicitement).
	const _ANGLE_TOLERANCE_DEG := 8.0
	const _MUZZLE_TOLERANCE := 0.06

	func _compute_gate() -> Dictionary:
		var ref: Dictionary = {}
		for w in _results:
			if int(w.get("id", -1)) == 0 and w.has("hip"):
				ref = w["hip"]
				break
		if ref.is_empty():
			return {"error": "référence Ravage (hip) introuvable -- capture Ravage manquante/échouée"}
		var ref_angle: float = ref["axis_angle_deg"]
		var ref_muzzle := Vector2(ref["muzzle_screen"][0], ref["muzzle_screen"][1])
		var entries: Array = []
		var all_pass := true
		for w in _results:
			if not w.has("hip"):
				continue
			var hip: Dictionary = w["hip"]
			var angle_delta := _angle_diff(float(hip["axis_angle_deg"]), ref_angle)
			var muzzle := Vector2(hip["muzzle_screen"][0], hip["muzzle_screen"][1])
			var muzzle_delta := muzzle.distance_to(ref_muzzle)
			var is_aiguille: bool = w["name"] == "aiguille"
			var angle_ok := absf(angle_delta) <= _ANGLE_TOLERANCE_DEG
			var muzzle_ok := muzzle_delta <= _MUZZLE_TOLERANCE or is_aiguille
			var ok := angle_ok and muzzle_ok
			all_pass = all_pass and ok
			var entry := {
				"name": w["name"], "id": w["id"],
				"axis_angle_deg": hip["axis_angle_deg"], "angle_delta_deg": angle_delta, "angle_ok": angle_ok,
				"muzzle_screen": hip["muzzle_screen"], "muzzle_delta": muzzle_delta,
				"muzzle_ok": muzzle_ok, "muzzle_tolerance_waived": is_aiguille, "pass": ok,
			}
			entries.append(entry)
			print("FP_GATE ", w["name"], " angle=", hip["axis_angle_deg"], " angle_delta=", angle_delta,
				" muzzle_delta=", muzzle_delta, " pass=", ok)
		return {
			"reference": {"name": "ravage", "axis_angle_deg": ref_angle, "muzzle_screen": ref["muzzle_screen"]},
			"tolerance_angle_deg": _ANGLE_TOLERANCE_DEG, "tolerance_muzzle": _MUZZLE_TOLERANCE,
			"results": entries, "all_pass": all_pass,
		}

	## Différence angulaire signée dans (-180, 180] -- `a - b` normalisée pour ne jamais rapporter
	## ~350° au lieu de ~-10° au passage 180°/-180° d'atan2.
	func _angle_diff(a: float, b: float) -> float:
		var d := fmod(a - b + 180.0, 360.0)
		if d < 0.0:
			d += 360.0
		return d - 180.0

	func _finish() -> void:
		var gate := _compute_gate()
		var data := {"weapons": _results, "gate": gate}
		var path := ProjectSettings.globalize_path(out_dir.path_join("fp_framing.json"))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(data, "\t"))
			f.close()
		print("FP_GATE_ALL_PASS ", gate.get("all_pass", false))
		print("ACTION_WEAPONS_CAPTURE_DONE")
		tree.quit()


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

	# Différé : _initialize() tourne AVANT le _ready des autoloads (racine pas encore dans l'arbre)
	# -- même raison que look_capture.gd.
	get_root().add_child.call_deferred((load(_SHIPMENT) as PackedScene).instantiate())
	var d := Driver.new()
	d.tree = self
	d.out_dir = out_dir
	d._wait_left = 120  # laisse Look/ToonStyle styler l'Environment + la physique se stabiliser.
	get_root().add_child(d)
