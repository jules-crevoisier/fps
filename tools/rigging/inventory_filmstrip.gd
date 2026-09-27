## inventory_filmstrip.gd
## Captures de vérification pour la tâche "inventaire CS-style" (2026-09-27) —
## même bootstrap que tools/rigging/utility_filmstrip.gd (partie TDM 1v1 réelle
## sur Shipment, joueur humain local + un bot figé), déroulé piloté par un
## nœud enfant en `_physics_process` (PAS `_process` : un `SceneTree._process`
## tourne à la cadence de RENDU, bien plus vite que la physique en fenêtré).
##   "%GODOT%" --screen 1 --path . -s res://tools/rigging/inventory_filmstrip.gd
## Produit dans OUT_DIR (contrat lead) : inv_a_rifle / inv_b_frag_equipped /
## inv_c_frag_aiming / inv_d_after_throw / inv_e_wheel.
##
## Étendu pour la tâche "utilitaires — 4 retours de playtest" (2026-09-27) :
## v3_a_long_line (LMB tenu, frag, ligne continue) / v3_b_short_line (RMB tenu,
## lob court + anneau proche) / v3_c_smoke_exit (caméra hors des puffs mais à
## <4 m du centre de détonation -- AUCUNE incrustation) / v3_d_bot_flashed
## (bot ébloui, étoiles visibles au-dessus de sa tête).
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const OUT_DIR := "res://reports/checkpoints/2026-09-27_inventory"

func _initialize() -> void:
	Engine.max_fps = 60
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 1
	get_root().add_child((load(_SHIPMENT) as PackedScene).instantiate())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_root().add_child(InventoryCaptureDriver.new())

func _process(_delta: float) -> bool:
	return false  # tout le déroulé vit dans InventoryCaptureDriver._physics_process.


## Nœud pilote — driven par `_physics_process` (60 Hz fixe), voir doc de fichier.
class InventoryCaptureDriver extends Node:
	const _SETTLE := 120
	var _player: PlayerController
	var _bot: PlayerController
	var _hud: Node  ## CanvasLayer (GameHUD.gd n'a pas de class_name) -- duck-typing, voir `_find_hud`.
	var _tick := 0
	var _phase_start := 0
	var _phase := 0
	## v3_c (fumigène) : le nuage est posé UNE SEULE FOIS, à cette distance
	## fixe devant le joueur (voir `_spawn_smoke_fixed`) — c'est la CAMÉRA
	## qu'on déplace ensuite autour du nuage RÉELLEMENT posé pour trouver un
	## azimut dégagé (voir `_apply_best_camera_placement`), jamais l'inverse
	## (un seul axe fixe pouvait tomber pile sur le plus gros puff du dôme,
	## observé lors d'un premier passage de cet outil).
	const _SMOKE_FIXED_DISTANCE_M := 3.0
	## Rayons candidats caméra<->centre, du plus GRAND au plus petit (contrat :
	## « même à moins de 4 m du centre » — on préfère démontrer le correctif
	## avec la plus grande marge possible). Chacun reste sous 3.66 m pour que
	## la distance 3D réelle (l'œil est ~1.6-1.8 m au-dessus du sol où le
	## nuage est posé) reste sous 4 m.
	const _CAM_SEARCH_RADII_M := [3.6, 3.2, 2.8, 2.4]
	const _CAM_SEARCH_AZIMUTH_STEPS := 24
	var _smoke_cloud: SmokeCloud

	func _physics_process(_delta: float) -> void:
		_tick += 1
		if _tick < _SETTLE:
			return
		if _player == null:
			_player = _find_human(get_tree().root)
			_bot = _find_bot(get_tree().root)
			_hud = _find_hud(get_tree().root)
			if _player == null or _bot == null:
				return
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			# Fige le bot pour TOUTE la séquence (capture uniquement, jamais en
			# jeu normal) — même précaution que utility_filmstrip.gd : sans ça,
			# BotBrain continue de combattre normalement et peut tuer le joueur
			# en plein milieu d'une prise (ce qui viderait charges/équipement
			# via GameWorld._on_player_died -> server_clear_charges, cassant
			# les captures suivantes).
			_bot.movement_locked = true
			var bot_hp := _bot.get_node_or_null("Health")
			if bot_hp and bot_hp.has_method("spawn_protection"):
				bot_hp.spawn_protection(9999.0)
			var player_hp := _player.get_node_or_null("Health")
			if player_hp and player_hp.has_method("spawn_protection"):
				player_hp.spawn_protection(9999.0)
			_phase_start = _tick
			_phase = 1
			return

		var t := _tick - _phase_start

		match _phase:
			1: _phase_rifle(t)
			2: _phase_equip_frag(t)
			3: _phase_aim_frag(t)
			4: _phase_after_throw(t)
			5: _phase_wheel_to_flash(t)
			6: _phase_v3_refill_and_equip_frag(t)
			7: _phase_v3_long_line(t)
			8: _phase_v3_short_line(t)
			9: _phase_v3_smoke_spawn(t)
			10: _phase_v3_bot_flash(t)
			_: get_tree().quit()

	# ---------------------------------------------------------- (a) état par défaut : rifle équipé
	func _phase_rifle(t: int) -> void:
		if t == 5:
			_shot("inv_a_rifle")
			_next_phase(2)

	# ---------------------------------------------------------- (b) touche 3 -> frag équipée
	## Attend le délai de déploiement complet (UtilityEquip.DEPLOY_DELAY_S,
	## 0,25 s = 15 tics à 60 Hz) + une marge confortable avant de capturer, pour
	## que la pose FP_Throw_Ready ait le temps de se stabiliser visuellement.
	func _phase_equip_frag(t: int) -> void:
		if t == 1:
			Input.action_press("weapon_3")
		if t == 2:
			Input.action_release("weapon_3")
		if t == 30:
			var utility := _utility()
			if utility == null or not utility.is_utility_equipped():
				push_warning("inventory_filmstrip: la frag n'est pas équipée au tick attendu")
			_shot("inv_b_frag_equipped")
			_next_phase(3)

	# ---------------------------------------------------------- (c) maintien du tir -> arc + anneau
	func _phase_aim_frag(t: int) -> void:
		if t == 1:
			# Visée quasi horizontale (même raison que utility_filmstrip.gd
			# _phase_hold_arc : un angle piqué fait converger les points de
			# l'arc trop près de la caméra, un lancer presque à plat les étale
			# lisiblement à l'écran).
			_player.head.rotation.x = deg_to_rad(-4.0)
			Input.action_press("fire")
		if t == 20:
			_shot("inv_c_frag_aiming")
			_next_phase(4)

	# ---------------------------------------------------------- (d) relâchement -> lancer -> retour à l'arme
	## Attend le retour automatique complet (UtilityEquip.RETURN_DELAY_S,
	## 0,4 s = 24 tics) + marge avant de capturer.
	func _phase_after_throw(t: int) -> void:
		if t == 1:
			Input.action_release("fire")
			_player.head.rotation.x = 0.0
		if t == 40:
			var utility := _utility()
			if utility == null or utility.is_utility_equipped():
				push_warning("inventory_filmstrip: le retour automatique à l'arme n'a pas eu lieu au tick attendu")
			_shot("inv_d_after_throw")
			_next_phase(5)

	# ---------------------------------------------------------- (e) molette -> flash (frag épuisée, sautée)
	func _phase_wheel_to_flash(t: int) -> void:
		if t == 1:
			Input.action_press("weapon_next")
		if t == 2:
			Input.action_release("weapon_next")
		if t == 15:
			_shot("inv_e_wheel")
			_next_phase(6)

	# ======================================================================
	#  Tâche "utilitaires — 4 retours de playtest" (2026-09-27) : v3_a..v3_d.
	# ======================================================================

	# ---------------------------------------------------------- (v3-a prep) recharge + frag en main
	## La frag/flash de la séquence (a)-(e) ci-dessus ont déjà consommé leur
	## charge -- `server_refill_charges()` est l'API SERVEUR déjà exposée pour
	## exactement ce cas (spawn/respawn), appelée directement ici (outil de
	## capture hors réseau réel, même schéma que tests/combat/
	## test_inventory_server_authority.gd qui appelle les méthodes serveur en direct).
	func _phase_v3_refill_and_equip_frag(t: int) -> void:
		if t == 1:
			var utility := _utility()
			if utility:
				utility.server_refill_charges()
			Input.action_press("weapon_3")
		if t == 2:
			Input.action_release("weapon_3")
		if t == 30:  # délai de déploiement (15 tics) + marge.
			_next_phase(7)

	# ---------------------------------------------------------- (v3-a) LMB tenu -> ligne continue
	## Le maintien est ANNULÉ après la capture (touche "1", reprend l'arme sans
	## lancer -- voir `_handle_equip_input`) plutôt que relâché : un lancer RÉEL
	## détonerait plus tard (dégâts de frag) pendant les phases suivantes, un
	## bruit inutile pour ces captures (le geste de lancer lui-même est déjà
	## couvert par inv_c_frag_aiming/inv_d_after_throw ci-dessus).
	func _phase_v3_long_line(t: int) -> void:
		if t == 1:
			# ~15° vers le haut (contrat de capture) -- même convention de signe
			# que _phase_aim_frag (`-4.0` = légèrement relevé).
			_player.head.rotation.x = deg_to_rad(-15.0)
			Input.action_press("fire")
		if t == 25:
			_shot("v3_a_long_line")
		if t == 26:
			Input.action_release("fire")
			Input.action_press("weapon_1")
		if t == 27:
			Input.action_release("weapon_1")
			_player.head.rotation.x = 0.0
			_next_phase(8)

	# ---------------------------------------------------------- (v3-b) RMB tenu -> lob court
	## Même annulation qu'en (v3-a) ci-dessus (touche "1"), pour la MÊME
	## raison -- une flash lancée pour de vrai détonerait pendant la phase
	## fumigène/bot suivante et s'auto-éblouirait le joueur (elle affecte aussi
	## le lanceur, contrat FlashMath.should_affect), polluant ces captures d'une
	## incrustation blanche plein écran sans rapport avec elles.
	func _phase_v3_short_line(t: int) -> void:
		if t == 1:
			Input.action_press("weapon_4")  # flash (la frag vient d'être annulée en (v3-a)).
		if t == 2:
			Input.action_release("weapon_4")
		if t == 17:  # délai de déploiement (15 tics) + marge.
			_player.head.rotation.x = deg_to_rad(-15.0)
			Input.action_press("aim")
		if t == 37:
			var utility := _utility()
			if utility == null or not utility.is_utility_equipped():
				push_warning("inventory_filmstrip: v3_b -- la flash n'est plus équipée au tick attendu")
			_shot("v3_b_short_line")
		if t == 38:
			Input.action_release("aim")
			Input.action_press("weapon_1")
		if t == 39:
			Input.action_release("weapon_1")
			_player.head.rotation.x = 0.0
			_next_phase(9)

	# ---------------------------------------------------------- (v3-c) fumigène : sortie du cache local
	## Pose UN SEUL SmokeCloud réel devant le joueur (position FIXE, jamais
	## rejouée -- seul le nuage RÉSULTANT importe ici, pas la trajectoire déjà
	## couverte par (v3-a)/(v3-b)), attend sa croissance complète, puis
	## cherche une position CAMÉRA (azimut × rayon autour du nuage RÉEL,
	## `_find_clear_camera_placement`) hors de TOUS les puffs réels avec la
	## MÊME fonction pure que `SmokeCloud._process` (`camera_inside_puff`) --
	## jamais une approximation géométrique séparée. Le joueur est ensuite
	## téléporté À CETTE position (même hauteur de sol, donc aucun risque de
	## chute) plutôt que de chercher un unique candidat le long d'un axe fixe
	## (une seule direction pouvait tomber pile sur le puff le plus large du
	## dôme, observé lors d'un premier passage de cet outil).
	func _phase_v3_smoke_spawn(t: int) -> void:
		if t == 1:
			_spawn_smoke_fixed()
			return
		if t == 90:  # >= smoke_grow_seconds (1.0 s) + gigue de départ max (0.3 s), marge incluse.
			_apply_best_camera_placement()
			return
		if t == 105:  # marge après téléportation (settle physique + interpolation caméra).
			_shoot_v3c()
			_next_phase(10)

	func _spawn_smoke_fixed() -> void:
		var cfg := UtilityDatabase.get_by_id(UtilityDatabase.SMOKE)
		var cam := _player.camera
		var forward_flat := Vector3(-cam.global_transform.basis.z.x, 0.0, -cam.global_transform.basis.z.z)
		if forward_flat.length() < 0.01:
			forward_flat = Vector3(0, 0, -1)
		var center := cam.global_position + forward_flat.normalized() * _SMOKE_FIXED_DISTANCE_M
		center.y = _player.global_position.y  # posé au sol, au niveau des pieds du joueur.
		var scene: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
		SmokeCloud.spawn_local(center, cfg, true, scene)
		_smoke_cloud = scene.get_child(scene.get_child_count() - 1) as SmokeCloud

	## Position/rayon des puffs RÉELS en coordonnées MONDE (post-croissance :
	## `scale.x` == rayon courant, `SphereMesh.radius` de base = 1.0).
	func _real_puff_world_spheres(cloud: SmokeCloud) -> Array:
		var out: Array = []
		for child in cloud.get_children():
			if child is MeshInstance3D:
				var radius: float = (child as MeshInstance3D).scale.x
				if radius <= 0.001:
					continue
				out.append({"pos": cloud.to_global((child as MeshInstance3D).position), "radius": radius})
		return out

	## Cherche, autour du nuage réellement posé, la plus GRANDE distance
	## candidate (contrat : « même à moins de 4 m du centre ») pour laquelle
	## au moins un azimut dégage TOUS les puffs réels — téléporte le joueur
	## (MÊME hauteur de sol que sa position actuelle, jamais de saut/chute) à
	## ce point et l'oriente vers le centre du nuage. `push_warning` (jamais
	## un blocage) si aucune combinaison ne dégage tout, capture alors depuis
	## la position d'origine.
	func _apply_best_camera_placement() -> void:
		if _smoke_cloud == null or not is_instance_valid(_smoke_cloud):
			push_warning("inventory_filmstrip: v3_c -- le nuage a disparu avant la recherche de position")
			return
		var center: Vector3 = _smoke_cloud.global_position
		var puffs := _real_puff_world_spheres(_smoke_cloud)
		var eye_height: float = (_player.current_height - 0.2) if "current_height" in _player else 1.6
		var chosen := Vector3.INF
		# Parmi les azimuts DÉGAGÉS d'un même rayon, garde celui qui maximise la
		# marge (distance à la surface du puff le plus proche) -- jamais le
		# premier qui « dégage tout juste » : ce dernier reste souvent collé au
		# bord d'un puff (marge de quelques cm), ce qui rend la capture peu
		# lisible (le dôme remplit quand même tout le cadre). Le rayon le plus
		# GRAND avec AU MOINS un azimut dégagé l'emporte (contrat : « même à
		# moins de 4 m du centre » — la plus grande marge possible).
		for radius in _CAM_SEARCH_RADII_M:
			var best_margin := -INF
			var best_pos := Vector3.INF
			for i in _CAM_SEARCH_AZIMUTH_STEPS:
				var az := TAU * float(i) / float(_CAM_SEARCH_AZIMUTH_STEPS)
				var eye_pos := center + Vector3(cos(az) * radius, eye_height, sin(az) * radius)
				var margin := INF
				for p in puffs:
					var surface_dist: float = eye_pos.distance_to(p["pos"]) - float(p["radius"]) * SmokeCloud.OVERLAY_SAFETY_MARGIN
					margin = minf(margin, surface_dist)
				if margin > best_margin:
					best_margin = margin
					best_pos = eye_pos
			if best_margin > 0.0:
				chosen = best_pos
				break
		if chosen == Vector3.INF:
			push_warning("inventory_filmstrip: v3_c -- aucune position caméra n'a dégagé tous les puffs, capture depuis la position d'origine")
			return
		var body_pos := chosen
		body_pos.y = _player.global_position.y  # remplace la hauteur "œil" par la hauteur de SOL déjà connue.
		_player.global_position = body_pos
		_player.velocity = Vector3.ZERO
		var to_center_flat := Vector3(center.x - body_pos.x, 0.0, center.z - body_pos.z)
		if to_center_flat.length() > 0.01:
			_player.rotation.y = Basis.looking_at(to_center_flat, Vector3.UP).get_euler().y
		_player.head.rotation.x = deg_to_rad(-5.0)

	func _shoot_v3c() -> void:
		if _smoke_cloud and is_instance_valid(_smoke_cloud) and bool(_smoke_cloud.get("_camera_inside")):
			push_warning("inventory_filmstrip: v3_c -- l'incrustation est active alors que la caméra ne devrait être dans AUCUN puff")
		_shot("v3_c_smoke_exit")

	# ---------------------------------------------------------- (v3-d) bot flashé -> tell visuel
	## Détonation FLASH simulée directement devant le visage du bot (bypass
	## volontaire du lancer, même raison qu'en (v3-c)) via `_server_detonate`
	## -- le MÊME chemin de code que le jeu réel (résout les effets ET diffuse
	## `_broadcast_blind_indicator`), jamais une logique dupliquée pour la capture.
	func _phase_v3_bot_flash(t: int) -> void:
		if t == 1:
			var utility := _utility()
			var flash_cfg := UtilityDatabase.get_by_id(UtilityDatabase.FLASH)
			if utility and flash_cfg and _bot:
				var bot_forward: Vector3 = -_bot.global_transform.basis.z
				var head_pos: Vector3 = _bot.head.global_position if _bot.head else _bot.global_position
				var pos := head_pos + bot_forward * 1.0  # devant le regard du bot -> "facing", durée max.
				var thrower_id := str(_player.name).to_int()
				var thrower_team := int(_player.team)
				utility._server_detonate(UtilityDatabase.FLASH, -1, pos, flash_cfg, thrower_id, thrower_team)
			var to_bot := (_bot.global_position - _player.global_position) if _bot else Vector3.FORWARD
			var to_bot_flat := Vector3(to_bot.x, 0.0, to_bot.z)
			if to_bot_flat.length() > 0.01:
				_player.rotation.y = Basis.looking_at(to_bot_flat, Vector3.UP).get_euler().y
			_player.head.rotation.x = deg_to_rad(-10.0)
		if t == 20:
			_shot("v3_d_bot_flashed")
			_next_phase(11)

	func _utility() -> UtilityThrower:
		return _player.get_node_or_null("UtilityThrower") as UtilityThrower

	func _next_phase(p: int) -> void:
		_phase_start = _tick
		_phase = p

	func _shot(name: String) -> void:
		var img := get_tree().root.get_texture().get_image()
		if img:
			img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join(name + ".png")))

	func _find_human(n: Node) -> PlayerController:
		var pc := n as PlayerController
		if pc and pc.is_local_human():
			return pc
		for c in n.get_children():
			var r := _find_human(c)
			if r:
				return r
		return null

	func _find_bot(n: Node) -> PlayerController:
		var pc := n as PlayerController
		if pc and bool(pc.get("is_bot")):
			return pc
		for c in n.get_children():
			var r := _find_bot(c)
			if r:
				return r
		return null

	func _find_hud(n: Node) -> Node:
		if n.has_method("debug_force_flash"):
			return n
		for c in n.get_children():
			var r := _find_hud(c)
			if r:
				return r
		return null
