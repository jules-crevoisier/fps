## smooth_normal_gltf_extension.gd
## GLTFDocumentExtension qui recopie l'attribut glTF personnalise
## `_SMOOTH_NORMAL` (ecrit par tools/blender/lib/toonkit.py
## `smooth_normal_attrs`, A3D-02) dans le canal `Mesh.ARRAY_CUSTOM0` (format
## RGB_FLOAT) de chaque surface importee -- le mecanisme officiel de Godot
## pour exposer un attribut de mesh non standard (aucun canal CUSTOM n'est
## peuple par defaut par GLTFDocument ; un attribut prefixe "_" non reconnu
## par une extension enregistree est simplement ignore au parsing, voir
## tests/rendering/test_stylekit_assets.gd).
##
## Enregistree par plugin.gd (EditorPlugin) tant que l'addon est actif dans
## project.godot [editor_plugins] : c'est ce qui rend l'attribut REELLEMENT
## disponible a l'import du jeu (TECH-03, relance apres QA), au lieu de
## seulement dans les tests (tests/rendering/test_outline_normals.gd et
## test_stylekit_assets.gd), qui reproduisent volontairement cette meme
## logique en propre, self-contained, pour prouver le mecanisme -- jamais
## comme source reelle pour le jeu.
##
## Ne concerne QUE les meshes STATIQUES : un mesh SKINNE (Skeleton3D) est
## skinne par Godot sur NORMAL/TANGENT selon la pose, mais jamais sur les
## attributs CUSTOM (recopies tels quels, en pose de repos) -- CUSTOM0 y
## fendrait le contour comme NORMAL brut. Pour ce cas, la normale lissee est
## plutot ecrite dans TANGENT et `Cartoon._mesh_is_skinned()` bascule
## `ink_outline.gdshader` dessus (voir l'en-tete du shader) ; cette extension
## d'import n'a rien a y faire.
##
## IMPORTANT (relance apres QA, sondage confirme par capture avant/apres) :
## `_import_post_parse` s'execute AVANT le post-traitement mesh du pipeline
## d'import (`meshes/generate_lods`, `meshes/create_shadow_meshes`,
## `array_mesh/deduplicate_surfaces` -- tous actifs par defaut sur nos props,
## voir docs/research/07_godot_tech.md C3). Ce post-traitement RECONSTRUIT
## chaque surface via son propre outillage de simplification/deduplication,
## qui ne connait que VERTEX/NORMAL/TANGENT/UV/COLOR/BONES/WEIGHTS -- un canal
## CUSTOM y est silencieusement perdu, meme peuple ici. Ecrire CUSTOM0 dans
## `_import_post_parse` seul ne survit donc PAS jusqu'au mesh importe final
## (verifie par sondage : desactiver generate_lods seul suffit a faire
## reapparaitre CUSTOM0 -- donc bien LUI le responsable, pas dedup/shadow).
## On garde ce hook pour DECODER l'accesseur `_SMOOTH_NORMAL` une seule fois
## (lecture brute du buffer glTF, disponible seulement ici via `GLTFState`),
## mais on met le resultat de cote (`_pending_smooth_normals`, cle = identite
## d'objet de l'ImporterMesh reconstruit) au lieu de compter dessus comme
## resultat final -- `SmoothNormalPostImportPlugin._internal_process`
## (meme dossier) le reinjecte APRES ce post-traitement, quand Godot appelle
## les plugins de post-import enregistres par `plugin.gd`.
@tool
extends GLTFDocumentExtension

## Doit correspondre a tools/blender/lib/toonkit.py `SMOOTH_NORMAL_ATTR` : les
## attributs applicatifs glTF prefixes "_" sont mis en MAJUSCULES par
## Blender a l'export.
const SMOOTH_NORMAL_GLTF_ATTR := "_SMOOTH_NORMAL"

## instance_id (int, `Object.get_instance_id()`) de l'ImporterMesh d'origine
## (`gltf_mesh.mesh`, celui que GLTFDocument continue d'utiliser jusqu'a la
## generation finale de la scene -- verifie par sondage : c'est le MEME objet
## que `node.mesh` recoit dans `SmoothNormalPostImportPlugin._internal_process`)
## -> Dictionary {surf_idx: PackedFloat32Array} des normales lissees decodees
## pour ses surfaces. `static` : ce hook et le plugin de post-import qui
## consomme ce cache sont deux objets d'extension DIFFERENTS (l'un enregistre
## aupres de `GLTFDocument`, l'autre aupres d'`EditorPlugin`), sans reference
## l'un vers l'autre -- seule une donnee de CLASSE partagee les relie. Vide a
## chaque `_import_post_parse` (un import a la fois, jamais deux fichiers en
## parallele dans le meme process d'import) pour ne jamais faire fuiter le
## cache d'un import au suivant si un mesh conserve la meme instance_id d'un
## fichier a l'autre (improbable mais gratuit a exclure).
static var _pending_smooth_normals: Dictionary = {}


## Appele par GLTFDocument apres le parsing des meshes mais avant la
## generation de la scene : decode l'accesseur `_SMOOTH_NORMAL` de chaque
## primitive qui le porte et le met de cote dans `_pending_smooth_normals`
## (voir la note ci-dessus -- l'ecriture directe en CUSTOM0 ici ne survivrait
## pas au post-traitement mesh du pipeline d'import).
func _import_post_parse(state: GLTFState) -> Error:
	_pending_smooth_normals.clear()
	var json: Dictionary = state.get_json()
	var gltf_meshes_json: Array = json.get("meshes", [])
	var accessors: Array = state.get_accessors()
	var buffer_views: Array = state.get_buffer_views()
	var state_meshes: Array = state.get_meshes()
	for mesh_idx in state_meshes.size():
		if mesh_idx >= gltf_meshes_json.size():
			continue
		var prims: Array = (gltf_meshes_json[mesh_idx] as Dictionary).get("primitives", [])
		var gltf_mesh: GLTFMesh = state_meshes[mesh_idx]
		var importer_mesh: ImporterMesh = gltf_mesh.mesh
		if importer_mesh == null:
			continue
		var by_surface: Dictionary = {}
		for surf_idx in range(min(importer_mesh.get_surface_count(), prims.size())):
			var attrs: Dictionary = (prims[surf_idx] as Dictionary).get("attributes", {})
			if not attrs.has(SMOOTH_NORMAL_GLTF_ATTR):
				continue
			var accessor: GLTFAccessor = accessors[int(attrs[SMOOTH_NORMAL_GLTF_ATTR])]
			by_surface[surf_idx] = _decode_vec3_float_accessor(state, accessor, buffer_views)
		if not by_surface.is_empty():
			_pending_smooth_normals[importer_mesh.get_instance_id()] = by_surface
	return OK


## Decode un accesseur glTF VEC3/FLOAT brut (aucune extension standard ne le
## comprend, d'ou la lecture manuelle du buffer plutot qu'un getter GLTFState
## dedie) en un tableau plat pret pour `Mesh.ARRAY_CUSTOM0` (RGB_FLOAT : 3
## floats par sommet).
static func _decode_vec3_float_accessor(state: GLTFState, accessor: GLTFAccessor, buffer_views: Array) -> PackedFloat32Array:
	var view: GLTFBufferView = buffer_views[accessor.get_buffer_view()]
	var raw: PackedByteArray = view.load_buffer_view_data(state)
	var count: int = accessor.get_count()
	var elem_size := 12  # VEC3 * float32
	var stride: int = view.get_byte_stride()
	var effective_stride := stride if stride > 0 else elem_size
	var byte_offset: int = accessor.get_byte_offset()
	var out := PackedFloat32Array()
	out.resize(count * 3)
	for i in count:
		var base: int = byte_offset + i * effective_stride
		var vals := raw.slice(base, base + elem_size).to_float32_array()
		out[i * 3 + 0] = vals[0]
		out[i * 3 + 1] = vals[1]
		out[i * 3 + 2] = vals[2]
	return out
