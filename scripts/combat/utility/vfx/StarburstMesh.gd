## StarburstMesh.gd
## Constructeur PUR d'un maillage d'étoile plate à N pointes (éclats de
## détonation frag/flash, ThrownUtility.gd) — un éventail de triangles depuis
## le centre (0,0,0), dans le plan XY LOCAL. Ne s'occupe QUE de la géométrie :
## l'appelant pose `billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED` sur son
## matériau pour que l'étoile fasse toujours face à la caméra, ce fichier ne
## touche jamais au matériau/au nœud.
class_name StarburstMesh
extends RefCounted

## `spikes` pointes (mini 3), alternant rayon `outer_radius` (pointe) /
## `inner_radius` (creux) autour du centre.
static func build(spikes: int, outer_radius: float, inner_radius: float) -> ArrayMesh:
	var point_count := maxi(spikes, 3) * 2
	var verts := PackedVector3Array()
	verts.append(Vector3.ZERO)
	for i in point_count:
		var angle := TAU * float(i) / float(point_count)
		var r := outer_radius if i % 2 == 0 else inner_radius
		verts.append(Vector3(cos(angle) * r, sin(angle) * r, 0.0))

	var indices := PackedInt32Array()
	for i in point_count:
		var a := 1 + i
		var b := 1 + ((i + 1) % point_count)
		indices.append(0)
		indices.append(a)
		indices.append(b)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
