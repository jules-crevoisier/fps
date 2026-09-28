## inspect_weapon_geometry.gd
## Outil de MESURE jetable (tâche "cadrage FP quatre armes", 2026-09-28) : charge chaque .glb
## d'arme (assets/models/weapons/*.glb) HORS scène de jeu (aucun rig, aucune caméra) et imprime,
## pour chaque arme, la position LOCALE (repère objet racine, celui que FPArmsRig.attach_weapon
## place tel quel sous "WeaponGrip", transform identité) de "Muzzle"/"Foregrip" et l'AABB globale
## du maillage -- sert à comparer les 4 nouvelles armes (Rafale/Fracas/Verdict/Aiguille) contre
## Ravage (référence qui cadre bien) SANS avoir à démarrer une partie complète.
##
##   "%GODOT%" --headless --path . -s res://tools/rigging/inspect_weapon_geometry.gd
extends SceneTree

const WEAPONS := ["ravage", "revolver", "rafale", "fracas", "verdict", "aiguille"]


func _initialize() -> void:
	for name in WEAPONS:
		var path := "res://assets/models/weapons/%s.glb" % name
		if not ResourceLoader.exists(path):
			print("SKIP ", name, " (introuvable)")
			continue
		var scene := load(path) as PackedScene
		var inst := scene.instantiate() as Node3D
		var muzzle := inst.find_child("Muzzle", true, false) as Node3D
		var foregrip := inst.find_child("Foregrip", true, false) as Node3D
		var aabb := _combined_aabb(inst)
		print("WEAPON ", name)
		print("  muzzle_local   = ", muzzle.position if muzzle else "N/A")
		print("  foregrip_local = ", foregrip.position if foregrip else "N/A")
		print("  aabb_min       = ", aabb.position)
		print("  aabb_max       = ", aabb.position + aabb.size)
		print("  aabb_size      = ", aabb.size)
		inst.queue_free()
	quit(0)


func _combined_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in _meshes(root):
		var a: AABB = m.get_aabb()
		# Repère LOCAL de root -- m peut être un enfant profond avec sa propre transform, donc on
		# passe par `m.transform` composé jusqu'à root (les meshes de ces armes sont des enfants
		# directs de root ou de root/Body, transforms simples -- pas de squelette ici).
		var t := _relative_transform(root, m)
		a = t * a
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t


func _meshes(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_meshes(c))
	return out
