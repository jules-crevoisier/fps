## PropKit.gd (dev-only, scripts/dev/ -- excluded from exports)
## Instances a prop GLB from assets/models/props/manifest.json and recolors
## it via Cartoon.painted_for_slot(). Verified empirically (headless probe
## of truck_wreck.glb/wooden_shack.glb/fuel_billboard.glb): each mesh
## surface's ORIGINAL glTF material name survives import as
## `Material.resource_name`, and matches the manifest's `slots` list
## 1:1 (e.g. truck_wreck's 5 surfaces are literally named "painted_metal",
## "rust", "accent", "glass", "rubber") -- so no manifest parsing is needed
## at paint time, just read each surface's own material name.
class_name PropKit
extends RefCounted

## Loads `path`, places it, and repaints every surface via
## `Cartoon.painted_for_slot(surface_material_name, tints.get(name, WHITE))`.
## `tints` keys are slot names ("accent", "sign", "rust", ...); a slot not
## present in `tints` keeps its painted texture at a neutral WHITE tint
## (i.e. the texture's own baked colour, untouched).
static func instance(path: String, pos: Vector3, rot_y_deg: float = 0.0, tints: Dictionary = {}) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("PropKit.instance: prop introuvable %s" % path)
		return null
	var inst := packed.instantiate() as Node3D
	inst.position = pos
	inst.rotation_degrees.y = rot_y_deg
	paint(inst, tints)
	return inst

## Repaints every MeshInstance3D surface under `node` (recursive) in place --
## useful to re-tint a prop already added to the tree.
static func paint(node: Node, tints: Dictionary) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		for i in range(mi.mesh.get_surface_count()):
			var src_mat := mi.mesh.surface_get_material(i)
			var slot := src_mat.resource_name if src_mat else ""
			if slot.is_empty():
				continue
			var tint: Color = tints.get(slot, Color.WHITE)
			mi.set_surface_override_material(i, Cartoon.painted_for_slot(slot, tint))
	for c in node.get_children():
		paint(c, tints)
