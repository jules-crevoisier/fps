## hud_capture.gd
## Captures de vérification visuelle du HUD en jeu (contrat lead 2026-09-27,
## "HUD en jeu" puis "TAB SCOREBOARD"/"DEATH SCREEN") — même patron que
## tools/rigging/look_capture.gd : temps piloté par la physique, fenêtre sans
## focus (la souris de l'utilisateur ne change rien), joueur figé (mouvement/
## regard désactivés), bots activés en 4v4 (MatchConfig.team_size, tâche
## "TAB SCOREBOARD" : "4v4 bots if the mode allows it" -- un seul lot de
## remplissage synchrone, voir GameWorld._fill_bots_if_needed, donc déjà
## présents à `tick == 120` comme l'unique bot des états a-e).
##   "%GODOT%" --screen 1 --resolution 1920x1080 --path . -s res://tools/ui/hud_capture.gd
## Images : reports/checkpoints/2026-09-27_ui/hud_ingame_<état>.png — à
## comparer avec reports/ui/renders/{hud,scoreboard,death}.png.
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const OUT_DIR := "res://reports/checkpoints/2026-09-27_ui"


class Driver extends Node:
	var tree: SceneTree
	var tick := -1
	var player: PlayerController
	var bot: PlayerController
	var hud: Node

	func _physics_process(_delta: float) -> void:
		tick += 1
		if tick == 120:
			for p in _players(tree.get_root()):
				if p.is_local_human():
					player = p
				elif bot == null:
					bot = p
			if player:
				# La souris de l'utilisateur ne doit rien changer à la vue
				# (même précaution que tools/rigging/look_capture.gd) --
				# `Input.action_press` continue de fonctionner (lu par
				# PlayerInput._physics_process, pas par ces callbacks).
				player.set_process_unhandled_input(false)
				player.set_process_input(false)
			hud = tree.get_root().find_child("HUD", true, false)
		if tick == 130:
			Input.action_press("weapon_2")   # équipe le revolver (slot 2).
		if tick == 133:
			Input.action_release("weapon_2")
		if tick == 160 and player:
			# Après le délai de changement d'arme (Weapon.SWITCH_DELAY = 0.25 s,
			# soit ~15 ticks) -- un tir pressé trop tôt (avant cette tâche,
			# tick 145) n'était pas encore accepté (`_switch_cooldown > 0`).
			Input.action_press("fire")
		if tick == 163:
			Input.action_release("fire")
		if tick == 185:
			_save.call_deferred("a_revolver")
		if tick == 191 and hud and hud.has_method("debug_force_kill_feed_and_ko"):
			hud.debug_force_kill_feed_and_ko("Joueur", "Crapaud", 0, "RAVAGE", true, true)
			hud.debug_force_hit_marker("kill")
		if tick == 207:
			_save.call_deferred("b_killfeed_ko")
		if tick == 213 and player:
			var health := player.get_node_or_null("Health") as Health
			if health:
				health.apply_damage(75.0)   # 100 -> 25 PV (<= 30, seuil "bas").
		if tick == 230:
			_save.call_deferred("c_low_hp")
		if tick == 235:
			Input.action_press("weapon_3")   # équipe la frag (grenade 1).
		if tick == 238:
			Input.action_release("weapon_3")
		if tick == 255:
			_save.call_deferred("d_grenade")
		if tick == 261:
			DisplayServer.window_set_size(Vector2i(1280, 800))
		if tick == 273:
			_save.call_deferred("e_1280x800")
		# ---- Tâche "TAB SCOREBOARD"/"DEATH SCREEN" (2026-09-27) : retour à la
		# résolution pleine (les deux maquettes sont conçues en 1920x1080). ----
		if tick == 280:
			DisplayServer.window_set_size(Vector2i(1920, 1080))
		if tick == 290 and hud and hud.has_method("debug_show_scoreboard"):
			hud.debug_show_scoreboard(true)
		if tick == 305:
			_save.call_deferred("f_scoreboard")
		if tick == 310 and hud and hud.has_method("debug_show_scoreboard"):
			hud.debug_show_scoreboard(false)
		if tick == 315 and hud and hud.has_method("debug_force_death"):
			hud.debug_force_death("Crapaud", "REVOLVER", true)
		if tick == 335:
			_save.call_deferred("g_death")
		if tick == 345:
			tree.quit()

	func _save(view: String) -> void:
		await RenderingServer.frame_post_draw
		var img := tree.get_root().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join("hud_ingame_%s.png" % view)))
		print("HUD_CAPTURE_SAVED ", view)

	func _players(n: Node) -> Array:
		var out: Array = []
		if n is PlayerController:
			out.append(n)
		for c in n.get_children():
			out.append_array(_players(c))
		return out


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = true
	# 4v4 (tâche "TAB SCOREBOARD" : "4v4 bots if the mode allows it") -- les
	# états a-e n'utilisent que `player`/le PREMIER bot trouvé, inchangés par
	# la présence de bots supplémentaires.
	MatchConfig.team_size = 4
	# Différé : _initialize() tourne AVANT le _ready des autoloads (racine pas
	# encore dans l'arbre) -- ajoutée tout de suite, la carte échapperait à
	# Look/LevelLook (node_added) et à d'autres autoloads, même précaution que
	# tools/rigging/look_capture.gd.
	get_root().add_child.call_deferred((load(_SHIPMENT) as PackedScene).instantiate())
	var d := Driver.new()
	d.tree = self
	get_root().add_child(d)
