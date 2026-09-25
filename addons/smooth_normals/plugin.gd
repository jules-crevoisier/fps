## plugin.gd
## Active `smooth_normal_gltf_extension.gd` + `smooth_normal_post_import.gd` a
## l'import REEL du jeu (TECH-03, relance apres QA : le mecanisme n'existait
## jusque-la que reproduit dans les tests, voir
## tests/rendering/test_outline_normals.gd et test_stylekit_assets.gd). Tant
## que cet addon est active dans project.godot [editor_plugins], CHAQUE import
## .glb/.gltf recopie l'attribut glTF `_SMOOTH_NORMAL` dans
## `Mesh.ARRAY_CUSTOM0` -- `ink_outline.gdshader` le lit ensuite comme normale
## d'extrusion lissee sur les meshes statiques stylekit (`Cartoon.
## _mesh_is_skinned` gere le cas skinne, canal TANGENT, sans rapport avec cet
## addon).
##
## DEUX extensions cooperent (voir l'en-tete de chaque fichier pour le
## detail) car aucune des deux seule ne suffit :
##  - `GLTFDocumentExtension` (`_import_post_parse`) est le SEUL point du
##    pipeline qui a acces au buffer glTF brut pour decoder l'accesseur
##    `_SMOOTH_NORMAL` -- mais il s'execute AVANT le post-traitement mesh
##    (`meshes/generate_lods` etc.) qui jette ensuite tout canal CUSTOM.
##  - `EditorScenePostImportPlugin` (`_internal_process`) s'execute APRES ce
##    post-traitement (donc y survit) mais n'a plus acces au glTF brut -- il
##    reinjecte les valeurs deja decodees par le premier, mises de cote dans
##    `SmoothNormalGltfExtension._pending_smooth_normals`.
##
## Activation dans project.godot [editor_plugins] : fichier partage entre
## plusieurs taches en parallele, hors du perimetre de cette tache (voir
## rapport de tache, blocked_on).
@tool
extends EditorPlugin

var _smooth_normal_extension: GLTFDocumentExtension
var _smooth_normal_post_import: EditorScenePostImportPlugin


func _enter_tree() -> void:
	_smooth_normal_extension = preload("res://addons/smooth_normals/smooth_normal_gltf_extension.gd").new()
	GLTFDocument.register_gltf_document_extension(_smooth_normal_extension)
	_smooth_normal_post_import = preload("res://addons/smooth_normals/smooth_normal_post_import.gd").new()
	add_scene_post_import_plugin(_smooth_normal_post_import)


func _exit_tree() -> void:
	if _smooth_normal_extension != null:
		GLTFDocument.unregister_gltf_document_extension(_smooth_normal_extension)
		_smooth_normal_extension = null
	if _smooth_normal_post_import != null:
		remove_scene_post_import_plugin(_smooth_normal_post_import)
		_smooth_normal_post_import = null
