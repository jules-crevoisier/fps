## FrogCowboyPostImport.gd
## Script de post-import (import_script/path dans
## assets/models/characters/frog_cowboy.glb.import) — retargeting Godot
## "BoneMap -> SkeletonProfileHumanoid" (docs/assets_pipeline/
## retargeting_3d_skeletons.html) appliqué au squelette Mixamo de Frog Cowboy :
## chaque os "mixamorig_*" est RENOMMÉ vers son nom de profil humanoïde
## (HumanoidBoneMap.MIXAMO_TO_HUMANOID) — Godot expose alors directement
## Skeleton3D.get_bone_name() == "Hips"/"RightHand"/... (contrat requirement
## 8 : "skeleton exposes humanoid names"). L'os NOUVEAU `WeaponGrip` (enfant de
## "RightHand", contrat GLB "native anim frog cowboy" 2026-09-26) n'a pas
## d'entrée dans la table -- il traverse ce script INCHANGÉ (voir
## `renamed_track_path`, repli sur le nom d'origine si la table ne le connaît
## pas), exactement ce que veut le contrat ("keep WeaponGrip as is").
## Renomme aussi le matériau du maillage peint ("tripo_mat_<uuid>", nom
## instable d'un export à l'autre) vers "frog_cowboy_tex" : PlayerLook.gd
## route déjà tout matériau `*_tex` reconnu vers ToonStyle.toon_material
## (voir `_BD_AGENT_MATERIAL_NAMES`), même mécanisme que "verrou_tex".
## Depuis la décision "frog gets NATIVE animations" (2026-09-26, abandon du
## retargeting UAL pour Frog Cowboy -- tools/rigging/bake_frog_animations.gd
## et resources/agents/anim/frog_cowboy_humanoid.tres restent en l'état, dossier
## de nettoyage ultérieur), les clips sont EMBARQUÉS dans le glb lui-même, avec
## des pistes qui ciblent encore les noms d'os Mixamo d'ORIGINE (le fichier
## source n'est jamais réécrit) : ce script renomme donc aussi CES pistes
## (`_rename_animation_tracks`, même table que les os) et force le mode de
## boucle des clips qui bouclent réellement en jeu (`_apply_loop_modes`,
## HumanoidBoneMap.FROG_LOOPING_CLIPS) -- indépendant de ce que l'export
## Blender a effectivement écrit dans le clip.
## N'écrit JAMAIS sur assets/models/characters/frog_cowboy.glb lui-même (règle
## "do not modify") : ce script ne modifie que la SCÈNE IMPORTÉE en mémoire
## (le résultat mis en cache sous .godot/imported/), le fichier .glb source
## reste intact sur le disque.
@tool
extends EditorScenePostImport

const HumanoidBoneMap = preload("res://scripts/import/HumanoidBoneMap.gd")
const TEX_MATERIAL_NAME := "frog_cowboy_tex"

func _post_import(scene: Node) -> Object:
	var skeleton := _find_skeleton(scene)
	var mesh := _find_mesh(scene)
	var anim_player := _find_animation_player(scene)
	if mesh:
		# AVANT le renommage des os : Skin.bind_name (posé par l'import glTF,
		# lookup PAR NOM au moment où Godot associe le MeshInstance3D à son
		# Skeleton3D) doit être retraduit en même temps, sinon le maillage perd
		# son squelettage ("Skin bind ... but Skeleton3D has no bone by that
		# name", constaté ici par un run réel -- pas une supposition).
		_rename_skin_binds(mesh)
	if skeleton:
		_rename_bones(skeleton)
	if mesh:
		_rename_material(mesh)
	if anim_player:
		_rename_animation_tracks(anim_player)
		_apply_loop_modes(anim_player)
	return scene

func _rename_bones(skeleton: Skeleton3D) -> void:
	for i in skeleton.get_bone_count():
		var mixamo_name := skeleton.get_bone_name(i)
		var humanoid_name: String = HumanoidBoneMap.MIXAMO_TO_HUMANOID.get(mixamo_name, "")
		if humanoid_name != "":
			skeleton.set_bone_name(i, humanoid_name)

func _rename_skin_binds(mesh: MeshInstance3D) -> void:
	var skin := mesh.skin
	if skin == null:
		return
	for i in skin.get_bind_count():
		var mixamo_name := skin.get_bind_name(i)
		var humanoid_name: String = HumanoidBoneMap.MIXAMO_TO_HUMANOID.get(mixamo_name, "")
		if humanoid_name != "":
			skin.set_bind_name(i, humanoid_name)

func _rename_material(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null:
		return
	for i in mesh.mesh.get_surface_count():
		var mat: Material = mesh.mesh.surface_get_material(i)
		if mat:
			mat.resource_name = TEX_MATERIAL_NAME

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_animation_player(c)
		if r:
			return r
	return null

## Renomme, dans CHAQUE clip de CHAQUE bibliothèque de `player`, la piste de
## squelette correspondant à un os Mixamo renommé par `_rename_bones` (même
## table `HumanoidBoneMap.MIXAMO_TO_HUMANOID`) — sinon les pistes viseraient un
## nom d'os (mixamorig_X) qui n'existe plus sur le Skeleton3D une fois ses os
## renommés, et la piste serait silencieusement ignorée à la lecture. STATIQUE
## (comme `renamed_track_path`) : `EditorScenePostImport` ne peut être
## instancié que par l'éditeur ("can only be instantiated by editor"), une
## méthode static reste appelable directement depuis les tests
## (tests/import/test_frog_cowboy_post_import.gd) sans `.new()`.
static func _rename_animation_tracks(player: AnimationPlayer) -> void:
	for lib_name in player.get_animation_library_list():
		var lib := player.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			var anim := lib.get_animation(anim_name)
			for i in anim.get_track_count():
				anim.track_set_path(i, renamed_track_path(anim.track_get_path(i), HumanoidBoneMap.MIXAMO_TO_HUMANOID))

## Fonction PURE (aucun Node requis, `NodePath` est un type valeur) — testée
## directement (tests/import/test_frog_cowboy_post_import.gd) : renomme
## UNIQUEMENT le nom d'os (sous-nom après ":") d'une piste de squelette via
## `bone_rename_map`, laisse le chemin de nœud (avant ":") et tout chemin sans
## sous-nom (":" absent, ex. une piste qui ne cible pas le squelette)
## INCHANGÉS. Repli sur le chemin d'origine si `bone_rename_map` ne connaît pas
## ce nom d'os (ex. `WeaponGrip`, os nouveau sans équivalent Mixamo -- contrat
## "keep WeaponGrip as is").
static func renamed_track_path(path: NodePath, bone_rename_map: Dictionary) -> NodePath:
	var bone_name := path.get_concatenated_subnames()
	if bone_name == "":
		return path
	var humanoid_name: String = bone_rename_map.get(bone_name, "")
	if humanoid_name == "":
		return path
	var node_part := path.get_concatenated_names()
	return NodePath("%s:%s" % [node_part, humanoid_name])

## Force le mode de boucle des clips « qui bouclent réellement en jeu »
## (`HumanoidBoneMap.FROG_LOOPING_CLIPS`, contrat livré par le lead) —
## indépendant du `loop_mode` que l'export Blender a effectivement écrit dans
## le clip (jamais garanti). Tout autre clip (Jump_Start/Roll/Rifle_Shoot/...)
## n'est pas touché : il joue une seule fois, tel qu'exporté. STATIQUE (voir
## `_rename_animation_tracks`) : appelable depuis les tests sans instancier
## `EditorScenePostImport`.
static func _apply_loop_modes(player: AnimationPlayer) -> void:
	for lib_name in player.get_animation_library_list():
		var lib := player.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			if HumanoidBoneMap.FROG_LOOPING_CLIPS.has(String(anim_name)):
				lib.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
