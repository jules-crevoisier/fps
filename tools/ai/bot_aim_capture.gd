## bot_aim_capture.gd
## Bot 1v1 contre un joueur IMMOBILE et INVULNÉRABLE : le bot est téléporté à
## ~10 m devant le joueur, ~135° hors de son cône de vue (doit se retourner et
## engager -- scénario qui sollicite le plus le rattrapage du ressort de visée
## ET la contre-rotation de colonne, cf. diagnostic du lead). Journalise, à
## CHAQUE tir du bot, l'écart (deg, horizontal) entre la direction RÉELLE vers
## le joueur et :
##  - la façade du CORPS (yaw du CharacterBody, = la visée du bot -- BotBrain.
##    _aim_towards fait tourner `player.rotation.y` lui-même) ;
##  - la façade de la TÊTE (nœud gameplay `head`, convention Godot standard
##    -Z -- sert de témoin : ne reçoit AUCUNE contre-rotation de LocomotionWarp,
##    doit donc rester ~= body si le tir/la visée eux-mêmes sont sains) ;
##  - la façade de la POITRINE (os Chest/UpperChest du squelette 3P). AXE
##    calibré empiriquement (2026-09-27, en comparant systématiquement +X/-X/
##    +Z/-Z contre `body`/`head` connus corrects) : sur ce rig (Frog Cowboy,
##    Humanoid remappé), l'avant de la poitrine est l'axe LOCAL -X, PAS +Z
##    (convention glTF brute, fausse ici -- l'ancienne version de cet outil
##    lisait +Z et rapportait à tort ~85-90° d'écart en permanence, y compris
##    hanches quasi immobiles ET LocomotionWarp désactivé : un artefact de
##    mesure, pas un bug de jeu -- voir capture_notes ci-dessous) ;
##  - la direction du CANON (vecteur grip -> Muzzle de l'arme 3P, indépendant
##    de toute convention d'axe local -- mesure géométrique, jamais un axe
##    supposé) ;
##  - la direction de DÉPLACEMENT (bot.velocity).
## Sert à trancher ENTRE la contre-rotation de colonne (LocomotionWarp), le
## rattrapage du ressort de visée (BotAim/BotBrain._aim_towards) et l'attache
## de l'arme 3P (ThirdPersonWeapon._GRIP_OFFSETS) comme cause du symptôme
## rapporté : « le haut du corps ne se tourne pas vers là où il tire ».
##   "%GODOT%" --screen 1 --resolution 1280x720 --path . -s res://tools/ai/bot_aim_capture.gd
## Images : reports/checkpoints/2026-09-27_bots/aimfix_NN.png (+ side_NN.png)
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const OUT_DIR := "res://reports/checkpoints/2026-09-27_bots"
const TELEPORT_TICK := 40         ## Laisse le monde/les bots se stabiliser avant de téléporter.
const ENGAGE_TIMEOUT_TICKS := 900 ## 15 s après téléportation : sécurité si le bot ne voit jamais le joueur.
const FIGHT_DURATION_TICKS := 360 ## ~6 s (60 Hz) de journal/captures APRÈS le premier tir.
const SAVE_EVERY_TICKS := 6       ## ~0.1 s (60 Hz), cf. contrat lead.


class Driver extends Node:
	var tree: SceneTree
	var tick := -1
	var player: PlayerController
	var bot: PlayerController
	var resolved := false
	var teleported := false
	var first_shot_tick := -1
	var shots := 0
	var n := 0
	var side_n := 0
	var _side_ticks: Array = []

	func _physics_process(_delta: float) -> void:
		tick += 1
		if not resolved and tick >= 20:
			_resolve_players()
		if player == null:
			return
		var h := player.get_node_or_null("Health")
		if h and "current_health" in h:
			h.set("current_health", 100.0)  # invulnérable : on veut voir le bot tirer longtemps.

		if not teleported and tick == TELEPORT_TICK:
			_teleport_bot_in_front()
			teleported = true

		if teleported and first_shot_tick == -1 and (tick - TELEPORT_TICK) >= ENGAGE_TIMEOUT_TICKS:
			print("BOT_AIM_NO_ENGAGE ticks=", tick - TELEPORT_TICK)
			tree.quit()
			return

		if first_shot_tick != -1:
			var elapsed := tick - first_shot_tick
			if elapsed >= 0 and elapsed <= FIGHT_DURATION_TICKS and elapsed % SAVE_EVERY_TICKS == 0:
				_save.call_deferred("aimfix_%02d.png" % n)
				n += 1
			if elapsed in _side_ticks:
				_save_side.call_deferred("side_%02d.png" % side_n)
				side_n += 1
			if elapsed >= FIGHT_DURATION_TICKS:
				print("BOT_AIM_DONE shots=", shots)
				tree.quit()

	func _resolve_players() -> void:
		resolved = true
		for p in tree.get_root().find_children("*", "PlayerController", true, false):
			var pc := p as PlayerController
			if pc.is_local_human():
				player = pc
			elif bot == null:
				bot = pc
		if player == null or bot == null:
			return
		player.set_process_unhandled_input(false)
		player.set_process_input(false)
		var w := bot.get_node_or_null("Weapon") as Weapon
		if w:
			w.remote_fired.connect(func(_c, _o, _d): _log_shot())
			w.fired.connect(func(_c, _f = false): _log_shot())
		# 3 prises depuis une caméra de CÔTÉ (pas attachée au bot), réparties sur
		# le combat -- montre le bot strafer en tirant (contrat lead).
		_side_ticks = [30, FIGHT_DURATION_TICKS / 2, FIGHT_DURATION_TICKS - 30]

	## Téléporte le bot à ~10 m DEVANT le joueur (dans le prolongement de son
	## regard courant), DOS tourné (doit se retourner pour engager -- sollicite
	## le rattrapage du ressort ET la contre-rotation de colonne, contrat lead).
	func _teleport_bot_in_front() -> void:
		var player_fwd := -player.global_transform.basis.z
		player_fwd.y = 0.0
		player_fwd = player_fwd.normalized() if player_fwd.length() > 0.01 else Vector3(0, 0, -1)
		var bot_pos := player.global_position + player_fwd * 10.0
		bot.global_position = bot_pos
		bot.velocity = Vector3.ZERO
		# Le bot regarde ~135° à l'écart du joueur (hors du cône de vue de
		# BotBrain.SIGHT_FOV=100° : doit bien se retourner pour engager) --
		# pas un 180° pile, pour que le balayage hors-combat (BotLook) le
		# ramène dans le cône en un temps raisonnable et déterministe.
		var yaw_deg := rad_to_deg(atan2(-player_fwd.x, -player_fwd.z)) + 135.0
		bot.rotation.y = deg_to_rad(yaw_deg)
		bot.head.rotation.x = 0.0

	func _log_shot() -> void:
		shots += 1
		if first_shot_tick == -1:
			first_shot_tick = tick
		if bot == null or player == null:
			return
		var to_target := player.global_position - bot.global_position
		to_target.y = 0.0
		var body_fwd := -bot.global_transform.basis.z
		body_fwd.y = 0.0
		var chest_fwd := body_fwd
		var skel := bot.find_children("*", "Skeleton3D", true, false)
		if not skel.is_empty():
			var sk := skel[0] as Skeleton3D
			var ci := sk.find_bone("Chest")
			if ci < 0:
				ci = sk.find_bone("UpperChest")
			if ci < 0:
				ci = sk.find_bone("Spine2")
			if ci >= 0:
				var g := sk.global_transform * sk.get_bone_global_pose(ci)
				# Axe -X local, calibré empiriquement (voir docstring d'en-tête) --
				# PAS +Z (convention glTF brute, invalide sur ce rig remappé).
				var fwd := -g.basis.x
				fwd.y = 0.0
				if fwd.length() > 0.01:
					chest_fwd = fwd
		var head_fwd := body_fwd
		if bot.head:
			var hd := -bot.head.global_transform.basis.z  # convention Godot standard (Node3D), PAS glTF.
			hd.y = 0.0
			if hd.length() > 0.01:
				head_fwd = hd
		var muzzle_fwd := body_fwd
		var tpw := bot.find_children("*", "ThirdPersonWeapon", true, false)
		if not tpw.is_empty():
			var w3p: Node3D = tpw[0]
			var muzzle: Node3D = w3p.get("_muzzle")
			var model: Node3D = w3p.get("_model")
			if muzzle and model:
				var d := muzzle.global_position - model.global_position
				d.y = 0.0
				if d.length() > 0.01:
					muzzle_fwd = d
		var vel := bot.velocity
		vel.y = 0.0
		print("BOT_AIM shot=%d body_vs_target=%.1f° head_vs_target=%.1f° chest_vs_target=%.1f° muzzle_vs_target=%.1f° move_vs_target=%.1f° speed=%.1f" % [
			shots,
			rad_to_deg(body_fwd.angle_to(to_target)),
			rad_to_deg(head_fwd.angle_to(to_target)),
			rad_to_deg(chest_fwd.angle_to(to_target)),
			rad_to_deg(muzzle_fwd.angle_to(to_target)),
			rad_to_deg(vel.angle_to(to_target)) if vel.length() > 0.3 else 0.0,
			vel.length(),
		])

	func _save(file_name: String) -> void:
		await RenderingServer.frame_post_draw
		tree.get_root().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR.path_join(file_name)))

	## Caméra de CÔTÉ temporaire (pas attachée au bot) : regarde le duo
	## joueur/bot de profil, prend une image, puis rend la main à la caméra du
	## joueur (celle utilisée par `_save`) pour ne pas perturber la suite.
	func _save_side(file_name: String) -> void:
		if player == null or bot == null:
			return
		var mid := (player.global_position + bot.global_position) * 0.5
		var to_bot := bot.global_position - player.global_position
		to_bot.y = 0.0
		var side := to_bot.normalized().rotated(Vector3.UP, PI * 0.5) if to_bot.length() > 0.01 else Vector3(1, 0, 0)
		var cam := Camera3D.new()
		tree.get_root().add_child(cam)
		cam.global_position = mid + side * 8.0 + Vector3(0, 1.6, 0)
		cam.look_at(mid + Vector3(0, 1.2, 0), Vector3.UP)
		cam.current = true
		await RenderingServer.frame_post_draw
		tree.get_root().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR.path_join(file_name)))
		if player.camera:
			player.camera.current = true
		cam.queue_free()


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 1
	get_root().add_child.call_deferred((load(_SHIPMENT) as PackedScene).instantiate())
	var d := Driver.new()
	d.tree = self
	get_root().add_child(d)
