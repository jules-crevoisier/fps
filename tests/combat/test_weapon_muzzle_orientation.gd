## test_weapon_muzzle_orientation.gd
## Verrou de calibration (urgence "Rafale à l'envers", 2026-09-28 -- playtest utilisateur : « le
## Rafale est complètement à l'envers, le canon vers la caméra et la crosse vers l'écran »)) : pour
## CHAQUE arme du catalogue (WeaponDatabase.PATHS/assets/models/weapons/<stem>.glb), l'empty
## "Muzzle" doit tomber du côté -Z (« vers l'écran », canon en avant) de la silhouette, jamais du
## côté +Z (« vers la caméra ») -- même convention que Ravage (assets/models/weapons/ravage.glb,
## arme de référence jamais retouchée par cette tâche) : "-Z = canon vers l'avant" (voir la doc de
## tête de FPArmsRig.gd).
##
## Cause du bug Rafale (voir art/weapons/rafale/build_rafale.py) : FRONT_SIGN mesuré à +1.0 (avant
## SOURCE = +X) alors que le vrai avant était -X -- toute la silhouette (canon ET crosse) rendait
## donc EXACTEMENT inversée en jeu (constaté par capture ET confirmé par playtest). Ce test lit
## l'ASSET EXPORTÉ final (pas la logique Blender qui a produit le bug -- Blender n'est pas dans la
## boucle de test Godot) : il ne peut donc pas empêcher une PROCHAINE erreur de mesure de FRONT_SIGN
## côté script Blender, mais il VERROUILLE l'état correct actuel et détecte toute régression sur
## l'asset livré (ex. un ré-export malencontreux avec le mauvais signe).
extends GdUnitTestSuite

## Même ordre que WeaponDatabase.PATHS (id = index) -- dupliqué ici plutôt qu'importé : ce fichier
## vérifie les ASSETS livrés indépendamment du catalogue de jeu courant (même choix que
## tests/combat/test_weapon_models.gd::_STEMS_BY_ID).
const _STEMS_BY_ID := ["ravage", "revolver", "rafale", "fracas", "verdict", "aiguille"]


func _load(id: int) -> Node3D:
	var path := "res://assets/models/weapons/%s.glb" % _STEMS_BY_ID[id]
	assert_bool(ResourceLoader.exists(path)).append_failure_message(
		"id %d (%s) : modèle introuvable (%s)" % [id, _STEMS_BY_ID[id], path]).is_true()
	var scene: PackedScene = load(path)
	assert_object(scene).append_failure_message(
		"id %d (%s) : échec de chargement (%s)" % [id, _STEMS_BY_ID[id], path]).is_not_null()
	var inst: Node3D = auto_free(scene.instantiate() as Node3D)
	assert_object(inst).is_not_null()
	return inst


func _find_mesh_instances(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_mesh_instances(c))
	return out


## Transform LOCALE de `node` par rapport à `root`, accumulée nœud par nœud -- mêmes hypothèses que
## tools/rigging/inspect_weapon_geometry.gd (aucun squelette sur ces modèles d'arme, juste des
## enfants directs/petits-enfants à transform simple).
func _relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t


## (min_z, max_z) de l'AABB combinée de TOUS les MeshInstance3D du modèle, repère LOCAL de `root`
## (celui que FPArmsRig.attach_weapon place tel quel sous "WeaponGrip", transform identité).
func _combined_aabb_z(root: Node3D) -> Vector2:
	var min_z := INF
	var max_z := -INF
	for m in _find_mesh_instances(root):
		var t := _relative_transform(root, m)
		var a: AABB = t * (m as MeshInstance3D).get_aabb()
		min_z = minf(min_z, a.position.z)
		max_z = maxf(max_z, a.position.z + a.size.z)
	return Vector2(min_z, max_z)


func test_muzzle_sits_closer_to_the_forward_negative_z_end_than_the_rear_end() -> void:
	for id in _STEMS_BY_ID.size():
		var inst := _load(id)
		var muzzle := inst.find_child("Muzzle", true, false) as Node3D
		assert_object(muzzle).append_failure_message(
			"id %d (%s) : empty \"Muzzle\" introuvable" % [id, _STEMS_BY_ID[id]]).is_not_null()
		var z_range := _combined_aabb_z(inst)
		var dist_to_front: float = absf(muzzle.position.z - z_range.x)   # côté -Z, canon attendu.
		var dist_to_rear: float = absf(muzzle.position.z - z_range.y)    # côté +Z, crosse attendue.
		assert_float(dist_to_front).append_failure_message(
			("id %d (%s) : Muzzle (z=%.3f) plus proche de l'extrémité +Z (z=%.3f, côté caméra/crosse) que de -Z "
				+ "(z=%.3f, côté écran/canon) -- canon probablement à l'envers") % [
				id, _STEMS_BY_ID[id], muzzle.position.z, z_range.y, z_range.x]
		).is_less(dist_to_rear)


## La silhouette doit aussi s'étendre du côté +Z (crosse/récepteur, vers la caméra/la main) -- une
## arme réduite à un seul canon isolé sans masse arrière ne se lirait pas en FP (silhouette "juste un
## tube"). Seuil relatif à la longueur totale (pas un cm en dur) : le Revolver (le plus compact,
## z_max mesuré ≈ 0,049 pour un empan total ≈ 0,32, soit ~15 %) reste la plus petite arme du
## catalogue -- 2 % de marge suffit à distinguer "il y a une crosse" de "rien du tout".
func test_silhouette_extends_behind_the_muzzle_toward_the_camera() -> void:
	for id in _STEMS_BY_ID.size():
		var inst := _load(id)
		var z_range := _combined_aabb_z(inst)
		var span: float = z_range.y - z_range.x
		assert_float(z_range.y).append_failure_message(
			"id %d (%s) : rien du côté +Z (caméra) -- silhouette z=[%.3f, %.3f], span=%.3f" % [
				id, _STEMS_BY_ID[id], z_range.x, z_range.y, span]
		).is_greater(span * 0.02)
