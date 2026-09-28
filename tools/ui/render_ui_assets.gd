## render_ui_assets.gd
## Rend les images de base de l'interface (maquettes, puis icônes et visuels du salon) avec le VRAI
## rendu du jeu (toon_bd + contour) : la grenouille en pied, revolver en main, les armes et les
## grenades de profil. Chaque sujet est rendu sur fond NOIR puis BLANC : l'alpha se déduit de l'écart
## (tools/ui/alpha_from_pair.py), sans liseré de fond. Temps piloté par la physique ; la fenêtre ne
## prend pas le focus.
##   "%GODOT%" --screen 1 --resolution 1600x800 --path . -s res://tools/ui/render_ui_assets.gd -- --set=props
##   "%GODOT%" --screen 1 --resolution 1000x1400 --path . -s res://tools/ui/render_ui_assets.gd -- --set=hero
## Images : reports/ui/assets/<sujet>_{black,white}.png
extends SceneTree

const OUT_DIR := "res://reports/ui/assets"
const _ThirdPersonWeapon := preload("res://scripts/player/ThirdPersonWeapon.gd")

## Sujets par lot. `side` : vue de profil orthographique (canon vers la DROITE de l'image : les
## modèles ont le canon sur -Z, caméra sur +X). `hero` : vue 3/4 en perspective.
const SETS := {
	"props": [
		{"name": "revolver", "scene": "res://assets/models/weapons/revolver.glb", "view": "side"},
		{"name": "ravage", "scene": "res://assets/models/weapons/ravage.glb", "view": "side"},
		{"name": "frag", "scene": "res://assets/models/utilities/frag.glb", "view": "side"},
		{"name": "flash", "scene": "res://assets/models/utilities/flash.glb", "view": "side"},
		{"name": "smoke", "scene": "res://assets/models/utilities/smoke.glb", "view": "side"},
		# Tâche "quatre armes v2" (2026-09-28) : les 4 nouvelles armes peintes (couleurs de
		# sommet, tools/blender/lib/painted_weapon.py) n'ont pas encore d'icône. "vcolor" : voir
		# _build() -- une couleur de sommet n'a pas d'équivalent dans le matériau glTF/PBR
		# standard, ToonStyle.apply_to lirait un albédo blanc par défaut (StandardMaterial3D,
		# aucune texture) sans ce marqueur.
		{"name": "rafale", "scene": "res://assets/models/weapons/rafale.glb", "view": "side", "vcolor": true},
		{"name": "fracas", "scene": "res://assets/models/weapons/fracas.glb", "view": "side", "vcolor": true},
		{"name": "verdict", "scene": "res://assets/models/weapons/verdict.glb", "view": "side", "vcolor": true},
		{"name": "aiguille", "scene": "res://assets/models/weapons/aiguille.glb", "view": "side", "vcolor": true},
	],
	"hero": [
		{"name": "frog", "scene": "res://scenes/characters/frog_cowboy.tscn", "view": "hero",
			"clip": "Pistol_Idle", "t": 0.3, "gun": "res://assets/models/weapons/revolver.glb"},
		{"name": "frog_aim", "scene": "res://scenes/characters/frog_cowboy.tscn", "view": "hero",
			"clip": "Pistol_Aim_Neutral", "t": 0.3, "gun": "res://assets/models/weapons/revolver.glb"},
		{"name": "frog_rifle", "scene": "res://scenes/characters/frog_cowboy.tscn", "view": "hero",
			"clip": "Rifle_Idle", "t": 0.5},
	],
}


class Driver extends Node:
	var tree: SceneTree
	var subjects: Array = []
	var index := 0
	var step := 0
	var holder: Node3D
	var env: Environment
	var cam: Camera3D

	func _ready() -> void:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		env = ToonStyle.environment()
		env.background_mode = Environment.BG_COLOR
		env.fog_enabled = false
		env.glow_enabled = false
		env.ssil_enabled = false
		env.ssao_enabled = false
		var we := WorldEnvironment.new()
		add_child(we)
		we.environment = env   # APRÈS l'entrée dans l'arbre : Look (LevelLook.node_added) y pose le ciel du jeu
		var sun := DirectionalLight3D.new()
		add_child(sun)
		ToonStyle.apply_sun(sun)
		sun.directional_shadow_max_distance = 10.0
		# lumière de studio : face caméra, en haut à gauche (les deux vues regardent vers -X / -Z)
		sun.look_at_from_position(Vector3.ZERO, Vector3(-0.55, -0.6, -0.35), Vector3.UP)
		cam = Camera3D.new()
		add_child(cam)
		cam.make_current()
		ToonStyle.add_outline_pass(cam)

	func _physics_process(_delta: float) -> void:
		if index >= subjects.size():
			tree.quit()
			return
		var s: Dictionary = subjects[index]
		match step:
			0:
				_build(s)
			8:
				env.background_color = Color.BLACK
			12:
				_save.call_deferred("%s_black.png" % s["name"])
			16:
				env.background_color = Color.WHITE
			20:
				_save.call_deferred("%s_white.png" % s["name"])
			24:
				holder.queue_free()
				index += 1
				step = -1
		step += 1

	func _build(s: Dictionary) -> void:
		holder = Node3D.new()
		add_child(holder)
		var model := (load(s["scene"]) as PackedScene).instantiate() as Node3D
		holder.add_child(model)
		if s.get("vcolor", false):
			# Couleur de sommet (tools/blender/lib/painted_weapon.py::paint_vertex_colors) : même
			# raison que ViewModel.gd/ThirdPersonWeapon.gd -- ToonStyle.apply_to (ink_toon.gdshader)
			# lit une couleur de sommet comme un MASQUE (AO/arête/dégradé), pas comme l'albédo
			# complet, donc jamais utilisable ici pour la peinture PRINCIPALE de l'arme. On pose
			# `vertex_color_use_as_albedo` sur le StandardMaterial3D importé directement, sans passer
			# par ToonStyle.
			for mesh in model.find_children("*", "MeshInstance3D", true, false):
				var mi := mesh as MeshInstance3D
				if mi.mesh == null:
					continue
				for i in mi.mesh.get_surface_count():
					var std := mi.mesh.surface_get_material(i) as StandardMaterial3D
					if std:
						var dup := std.duplicate() as StandardMaterial3D
						dup.vertex_color_use_as_albedo = true
						mi.set_surface_override_material(i, dup)
		else:
			ToonStyle.apply_to(model)
		if s.has("clip"):
			var ap := model.find_children("*", "AnimationPlayer", true, false)
			if not ap.is_empty():
				var player := ap[0] as AnimationPlayer
				for a in player.get_animation_list():
					if a.ends_with(s["clip"]):
						player.play(a)
						player.seek(float(s["t"]), true)
						player.speed_scale = 0.0
						break
		if s.has("gun"):
			var skel := model.find_children("*", "Skeleton3D", true, false)
			if not skel.is_empty():
				var att := BoneAttachment3D.new()
				att.bone_name = "PistolGrip"
				(skel[0] as Skeleton3D).add_child(att)
				var gun := (load(s["gun"]) as PackedScene).instantiate() as Node3D
				att.add_child(gun)
				ToonStyle.apply_to(gun)
				gun.scale = _ThirdPersonWeapon.counter_scale_for(att.global_transform.basis.get_scale())
		_frame(s, _bounds(holder))

	func _frame(s: Dictionary, box: AABB) -> void:
		var c := box.get_center()
		var aspect := float(tree.get_root().size.x) / float(tree.get_root().size.y)
		if s["view"] == "side":
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = max(box.size.y, box.size.z / aspect) * 1.18
			cam.near = 0.01
			cam.far = 50.0
			cam.look_at_from_position(c + Vector3(3.0, 0.0, 0.0), c, Vector3.UP)
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 28.0
			var dist: float = box.size.y * 0.56 / tan(deg_to_rad(cam.fov * 0.5))
			cam.look_at_from_position(c + Vector3(0.42, 0.12, 1.0).normalized() * dist, c, Vector3.UP)

	func _bounds(n: Node) -> AABB:
		var box := AABB()
		var first := true
		for vi in n.find_children("*", "VisualInstance3D", true, false):
			var v := vi as VisualInstance3D
			if v is Light3D or not v.visible:
				continue
			var b := v.global_transform * v.get_aabb()
			box = b if first else box.merge(b)
			first = false
		return box

	func _save(file_name: String) -> void:
		await RenderingServer.frame_post_draw
		var img := tree.get_root().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT_DIR.path_join(file_name)))
		print("UI_ASSET ", file_name)


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var set_name := "props"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--set="):
			set_name = arg.trim_prefix("--set=")
	var d := Driver.new()
	d.tree = self
	d.subjects = SETS.get(set_name, [])
	get_root().add_child.call_deferred(d)
