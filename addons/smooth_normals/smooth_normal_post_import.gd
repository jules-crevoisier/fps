## smooth_normal_post_import.gd
## EditorScenePostImportPlugin (TECH-03, relance apres QA) : reinjecte en
## CUSTOM0 les normales lissees decodees par
## `smooth_normal_gltf_extension.gd._import_post_parse` (meme dossier), APRES
## que le pipeline d'import ait fini son post-traitement mesh (`meshes/
## generate_lods`, `meshes/create_shadow_meshes`, `array_mesh/
## deduplicate_surfaces` -- tous actifs par defaut sur nos props). Sondage
## verifie par capture avant/apres (voir l'en-tete de
## smooth_normal_gltf_extension.gd) : ecrire CUSTOM0 plus tot (dans
## `_import_post_parse`, avant ce post-traitement) ne survit PAS -- la
## reconstruction de surface de `generate_lods`/`create_shadow_meshes` ne
## connait que VERTEX/NORMAL/TANGENT/UV/COLOR/BONES/WEIGHTS et jette tout
## canal CUSTOM au passage (confirme par sondage : desactiver `generate_lods`
## seul suffit a faire reapparaitre CUSTOM0). `_internal_process` (categorie
## MESH_3D_NODE -- PAS categorie MESH, qui ne se declenche jamais sur nos
## scenes glb "plates" sans MeshLibrary, verifie par sondage), lui, s'execute
## APRES ce post-traitement -- reinjecter ici est donc le seul point
## d'accroche qui survit jusqu'au mesh importe final.
##
## Enregistre par `plugin.gd` via `EditorPlugin.add_scene_post_import_plugin`
## (portee globale tant que l'addon est actif dans project.godot
## [editor_plugins], comme `GLTFDocument.register_gltf_document_extension`
## pour l'autre moitie du mecanisme) -- aucune configuration par fichier
## `.import` requise, donc valable pour TOUT prop/perso stylekit du jeu, pas
## seulement ceux dont le `.import` a ete touche a la main.
@tool
extends EditorScenePostImportPlugin

const SmoothNormalGltfExtension := preload("res://addons/smooth_normals/smooth_normal_gltf_extension.gd")


func _internal_process(category: int, _base_node: Node, node: Node, _resource: Resource) -> void:
	# TECH-03 (sondage) : sur nos scenes glb "plates" (pas de MeshLibrary),
	# `_internal_process` n'est JAMAIS appele avec la categorie MESH -- la
	# categorie qui porte vraiment le mesh ici est MESH_3D_NODE, avec le mesh
	# accessible via `node.mesh` (l'objet Node est encore un
	# `ImporterMeshInstance3D`, pas un `MeshInstance3D` final, a ce stade).
	if category != EditorScenePostImportPlugin.INTERNAL_IMPORT_CATEGORY_MESH_3D_NODE:
		return
	var importer_mesh := node.get("mesh") as ImporterMesh
	if importer_mesh == null:
		return
	var by_surface: Dictionary = SmoothNormalGltfExtension._pending_smooth_normals.get(importer_mesh.get_instance_id(), {})
	if by_surface.is_empty():
		return

	# Snapshot complet AVANT `clear()` (surfaces, LODs, blend shapes) --
	# `ImporterMesh` ne permet de modifier une surface qu'en reconstruisant le
	# mesh en entier (voir sa doc de classe), jamais en assignant un seul
	# canal en place.
	var blend_shape_names: Array[String] = []
	for bs_idx in importer_mesh.get_blend_shape_count():
		blend_shape_names.append(importer_mesh.get_blend_shape_name(bs_idx))

	var surfaces: Array[Dictionary] = []
	var surface_count: int = importer_mesh.get_surface_count()
	for surf_idx in surface_count:
		var arrays: Array = importer_mesh.get_surface_arrays(surf_idx)
		var flags: int = importer_mesh.get_surface_format(surf_idx)
		if by_surface.has(surf_idx):
			var smooth: PackedFloat32Array = by_surface[surf_idx]
			var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if smooth.size() == vertex_count * 3:
				arrays[Mesh.ARRAY_CUSTOM0] = smooth
				flags |= Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT

		var blend_shapes: Array = []
		for bs_idx in blend_shape_names.size():
			blend_shapes.append(importer_mesh.get_surface_blend_shape_arrays(surf_idx, bs_idx))

		var lods: Dictionary = {}
		for lod_idx in importer_mesh.get_surface_lod_count(surf_idx):
			lods[importer_mesh.get_surface_lod_size(surf_idx, lod_idx)] = importer_mesh.get_surface_lod_indices(surf_idx, lod_idx)

		surfaces.append({
			"primitive": importer_mesh.get_surface_primitive_type(surf_idx),
			"arrays": arrays,
			"blend_shapes": blend_shapes,
			"lods": lods,
			"material": importer_mesh.get_surface_material(surf_idx),
			"name": importer_mesh.get_surface_name(surf_idx),
			"flags": flags,
		})

	importer_mesh.clear()
	for bs_name in blend_shape_names:
		importer_mesh.add_blend_shape(bs_name)
	for s in surfaces:
		importer_mesh.add_surface(s["primitive"], s["arrays"], s["blend_shapes"], s["lods"], s["material"], s["name"], s["flags"])
