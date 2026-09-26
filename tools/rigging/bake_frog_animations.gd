## bake_frog_animations.gd
## Outil hors-ligne (one-shot, relancé seulement si frog_cowboy.glb est
## réexporté) : retargete les clips UAL nécessaires
## (HumanoidBoneMap.NEEDED_CLIPS, squelette Rigify "DEF-*" de
## assets/incoming/quaternius/ual.glb) vers le squelette Mixamo/humanoïde de
## Frog Cowboy (assets/models/characters/frog_cowboy.glb, déjà renommé en
## noms de profil humanoïde par scripts/import/FrogCowboyPostImport.gd — voir
## sa doc), et écrit le résultat dans une AnimationLibrary autonome
## (resources/agents/anim/frog_cowboy_humanoid.tres) chargée par
## scenes/characters/frog_cowboy.tscn.
##
## Ne touche NI ual.glb NI frog_cowboy.glb NI verrou.glb : lecture seule sur
## les trois, écriture UNIQUEMENT sur la nouvelle AnimationLibrary — donc
## aucun risque pour Verrou/les bras FP (contrat lead : "isolate it... rather
## than changing Verrou's pipeline").
##
## Retargeting rotation (par os, cf. docs/assets_pipeline/
## retargeting_3d_skeletons.html "Rest Fixer") : delta = repos_source⁻¹ · pose
## puis pose_cible = repos_cible · delta -- préserve la rotation OBSERVÉE
## relative au repos de chaque squelette plutôt que de recopier la valeur brute
## (qui suppose à tort deux repos identiques). Position (Hips uniquement) :
## même delta, mis à l'échelle par le ratio de longueur de jambe entre les
## deux squelettes (proportions Frog Cowboy != mannequin UAL).
##
## Lancer : godot --headless --path . --script res://tools/rigging/bake_frog_animations.gd
extends SceneTree

const HumanoidBoneMap = preload("res://scripts/import/HumanoidBoneMap.gd")

const UAL_PATH := "res://assets/incoming/quaternius/ual.glb"
const FROG_PATH := "res://assets/models/characters/frog_cowboy.glb"
const OUT_PATH := "res://resources/agents/anim/frog_cowboy_humanoid.tres"
const FROG_SKELETON_TRACK_PREFIX := "Armature/Skeleton3D:"

func _initialize() -> void:
	var ual := load(UAL_PATH) as PackedScene
	var frog := load(FROG_PATH) as PackedScene
	if ual == null or frog == null:
		push_error("bake_frog_animations: échec de chargement (ual=%s frog=%s)" % [ual, frog])
		quit(1)
		return

	var ual_root := ual.instantiate()
	var frog_root := frog.instantiate()
	get_root().add_child(ual_root)
	get_root().add_child(frog_root)

	var ual_skeleton := _find_skeleton(ual_root)
	var frog_skeleton := _find_skeleton(frog_root)
	var ual_player := _find_anim_player(ual_root)
	if ual_skeleton == null or frog_skeleton == null or ual_player == null:
		push_error("bake_frog_animations: squelette/AnimationPlayer introuvable (ual_skeleton=%s frog_skeleton=%s ual_player=%s)" %
			[ual_skeleton, frog_skeleton, ual_player])
		quit(1)
		return

	var scale := _leg_length_scale(ual_skeleton, frog_skeleton)
	print("bake_frog_animations: leg length scale (frog/ual) = ", scale)

	var lib := AnimationLibrary.new()
	var missing: Array = []
	for clip_name in HumanoidBoneMap.NEEDED_CLIPS:
		if not ual_player.has_animation(clip_name):
			missing.append(clip_name)
			continue
		var src_anim := ual_player.get_animation(clip_name)
		var new_anim := _retarget_animation(src_anim, ual_skeleton, frog_skeleton, scale)
		lib.add_animation(clip_name, new_anim)
	if not missing.is_empty():
		push_warning("bake_frog_animations: clips UAL introuvables, ignorés: %s" % [missing])

	var dir_err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH.get_base_dir()))
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_error("bake_frog_animations: impossible de créer %s (%s)" % [OUT_PATH.get_base_dir(), dir_err])
	var save_err := ResourceSaver.save(lib, OUT_PATH)
	if save_err != OK:
		push_error("bake_frog_animations: échec de sauvegarde %s (%s)" % [OUT_PATH, save_err])
		quit(1)
		return

	print("bake_frog_animations: OK -> ", OUT_PATH, " (", lib.get_animation_list().size(), " clips)")
	quit(0)

## Longueur de jambe (cuisse+tibia+pied, somme des translations de repos) de
## chaque squelette -- repère de mise à l'échelle stable pour les pistes de
## POSITION (Hips uniquement) : Frog Cowboy et le mannequin UAL n'ont pas les
## mêmes proportions.
func _leg_length_scale(ual_skeleton: Skeleton3D, frog_skeleton: Skeleton3D) -> float:
	var ual_len := _chain_length(ual_skeleton, ["DEF-thigh.L", "DEF-shin.L", "DEF-foot.L"])
	var frog_len := _chain_length(frog_skeleton, ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"])
	if is_zero_approx(ual_len):
		return 1.0
	return frog_len / ual_len

func _chain_length(skeleton: Skeleton3D, bone_names: Array) -> float:
	var total := 0.0
	for n in bone_names:
		var idx := skeleton.find_bone(n)
		if idx == -1:
			continue
		total += skeleton.get_bone_rest(idx).origin.length()
	return total

func _retarget_animation(src: Animation, ual_skeleton: Skeleton3D, frog_skeleton: Skeleton3D, scale: float) -> Animation:
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = src.loop_mode
	out.step = src.step

	for i in src.get_track_count():
		var track_type := src.track_get_type(i)
		if track_type != Animation.TYPE_POSITION_3D and track_type != Animation.TYPE_ROTATION_3D:
			continue  # pas de piste scale/value attendue sur ces clips (vérifié par sondage).
		var path := src.track_get_path(i)
		var bone_name := String(path.get_concatenated_subnames())
		if bone_name == "root":
			continue  # pas d'équivalent : Frog Cowboy n'a pas d'os au-dessus de Hips.
		var humanoid_name: String = HumanoidBoneMap.DEF_TO_HUMANOID.get(bone_name, "")
		if humanoid_name.is_empty():
			continue
		var source_idx := ual_skeleton.find_bone(bone_name)
		var target_idx := frog_skeleton.find_bone(humanoid_name)
		if source_idx == -1 or target_idx == -1:
			continue

		var source_rest := ual_skeleton.get_bone_rest(source_idx)
		var target_rest := frog_skeleton.get_bone_rest(target_idx)
		var new_track := out.add_track(track_type)
		out.track_set_path(new_track, NodePath(FROG_SKELETON_TRACK_PREFIX + humanoid_name))
		out.track_set_interpolation_type(new_track, src.track_get_interpolation_type(i))

		for k in src.track_get_key_count(i):
			var t := src.track_get_key_time(i, k)
			var value = src.track_get_key_value(i, k)
			var new_value
			if track_type == Animation.TYPE_ROTATION_3D:
				var source_rest_q := source_rest.basis.get_rotation_quaternion()
				var target_rest_q := target_rest.basis.get_rotation_quaternion()
				var pose_q: Quaternion = value
				var delta: Quaternion = source_rest_q.inverse() * pose_q
				new_value = target_rest_q * delta
			else:
				var pose_pos: Vector3 = value
				var delta_pos: Vector3 = pose_pos - source_rest.origin
				new_value = target_rest.origin + delta_pos * scale
			out.track_insert_key(new_track, t, new_value)
	return out

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r:
			return r
	return null
