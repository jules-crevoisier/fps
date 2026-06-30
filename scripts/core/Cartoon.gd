## Cartoon.gd
## Direction artistique cartoon : matériaux TOON (cel-shading) + contour noir
## (technique "inverted hull" : une coque arrière agrandie en noir via next_pass).
## Utilisé par les builders de map et les joueurs pour un look BD cohérent.
class_name Cartoon
extends RefCounted

## Matériau de contour : coque arrière (cull front) agrandie, noir, non éclairé.
static func outline_mat(width: float = 0.04) -> StandardMaterial3D:
	var o := StandardMaterial3D.new()
	o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	o.albedo_color = Color(0.05, 0.05, 0.08)
	o.cull_mode = BaseMaterial3D.CULL_FRONT
	o.grow = true
	o.grow_amount = width
	return o

## Matériau cartoon : diffus TOON (lumière en paliers) + contour.
static func mat(color: Color, outline: float = 0.04) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.metallic = 0.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if outline > 0.0:
		m.next_pass = outline_mat(outline)
	return m
