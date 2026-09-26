## test_weapon_models.gd
## A3D-20 — critères d'acceptation sur le modèle .glb peint du Ravage
## (assets/models/weapons/ravage.glb) : texture peinte conservée, canon vers
## le viseur (-Z, ex-tools/blender/make_weapons.py), ancres "Grip"
## (origine)/"Foregrip"/"Muzzle" présentes et cohérentes (gants + flash au
## canon, ViewModel.gd), budget <= 8000 tris.
##
## Nettoyage du prototype 2026-09-26 ("clean absolument tout") : les 6 autres
## modèles (pistolet, magnum, rafale, marqueur, fracas, faucheur) et leurs
## assets sont supprimés -- Ravage est désormais la SEULE arme du jeu
## (WeaponDatabase.PATHS id 0), ce fichier ne teste plus qu'elle.
extends GdUnitTestSuite

const MAX_TRIS := 8000
const PAINTED_MARKER := "_painted"
const WEAPON_IDS := [0]
const _STEMS_BY_ID := ["ravage"]


## Instancie assets/models/weapons/<stem>.glb pour l'id donné — échoue fort
## (jamais un skip silencieux) si le modèle ou son fichier sont introuvables :
## les 7 armes sont censées être TOUTES livrées par cette tâche. Construit le
## chemin depuis `_STEMS_BY_ID` (jamais `Weapon.model_path_for`, qui ne
## résout plus que l'id 0 du catalogue réduit au Ravage seul — voir sa
## docstring) : ce fichier vérifie les ASSETS livrés, indépendamment du
## catalogue de jeu courant.
func _load_model(id: int) -> Node3D:
	var path := "res://assets/models/weapons/%s.glb" % _STEMS_BY_ID[id]
	assert_bool(ResourceLoader.exists(path)).append_failure_message(
		"id %d : modèle introuvable (%s)" % [id, path]).is_true()
	var scene: PackedScene = load(path)
	assert_object(scene).append_failure_message("id %d : échec de chargement (%s)" % [id, path]).is_not_null()
	var inst := scene.instantiate() as Node3D
	assert_object(inst).is_not_null()
	return inst


func _find_mesh_instances(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_mesh_instances(c))
	return out


func _tri_count(root: Node3D) -> int:
	var total := 0
	for mesh in _find_mesh_instances(root):
		if mesh.mesh:
			total += mesh.mesh.get_faces().size() / 3
	return total


func _weapon_label(id: int) -> String:
	return "%d (%s)" % [id, _STEMS_BY_ID[id]]


# ======================================================================
#  Budget de tris (critère d'acceptation : <= 8000 par arme)
# ======================================================================
func test_every_weapon_model_stays_within_the_8000_tris_budget() -> void:
	for id in WEAPON_IDS:
		var inst := _load_model(id)
		var tris := _tri_count(inst)
		assert_int(tris).append_failure_message(
			"%s : %d tris (budget A3D-20 <= %d)" % [_weapon_label(id), tris, MAX_TRIS]).is_less_equal(MAX_TRIS)
		assert_int(tris).append_failure_message(
			"%s : mesh vide (0 tri)" % _weapon_label(id)).is_greater(0)
		inst.free()


# ======================================================================
#  Texture peinte conservée (critère d'acceptation : "texture peinte")
# ======================================================================
func test_every_weapon_model_keeps_its_painted_texture() -> void:
	for id in WEAPON_IDS:
		var inst := _load_model(id)
		var found_painted := false
		for mesh in _find_mesh_instances(inst):
			if mesh.mesh == null:
				continue
			for i in mesh.mesh.get_surface_count():
				var mat: Material = mesh.mesh.surface_get_material(i)
				var name: String = mat.resource_name if mat else ""
				if name.contains(PAINTED_MARKER):
					found_painted = true
					var tex := Cartoon.texture_from_imported_material(mat)
					assert_object(tex).append_failure_message(
						"%s : matériau \"%s\" sans texture d'albédo" % [_weapon_label(id), name]).is_not_null()
		assert_bool(found_painted).append_failure_message(
			"%s : aucun matériau \"*%s*\" trouvé (bpy en blocs non remplacé ?)" %
			[_weapon_label(id), PAINTED_MARKER]).is_true()
		inst.free()


# ======================================================================
#  Ancres Muzzle/Foregrip (critère d'acceptation : "canon vers le viseur",
#  "gants sur Grip/Foregrip", "flash au Muzzle" — voir ViewModel.gd
#  _attach_gloves/_spawn_muzzle_flash/muzzle_global_position)
# ======================================================================
func test_every_weapon_model_has_a_muzzle_anchor_pointing_forward() -> void:
	for id in WEAPON_IDS:
		var inst := _load_model(id)
		var muzzle := inst.find_child("Muzzle", true, false) as Node3D
		assert_object(muzzle).append_failure_message(
			"%s : empty \"Muzzle\" introuvable" % _weapon_label(id)).is_not_null()
		# Canon le long de -Z (tools/blender/make_weapons.py, convention
		# partagée par les 7 modèles bpy ET peints, voir l'en-tête de
		# fit_weapon_painted.py) : le canon "vers le viseur" du critère
		# d'acceptation, contrôlé sans dépendre d'une caméra/scène de jeu.
		assert_float(muzzle.position.z).append_failure_message(
			"%s : Muzzle.z = %.4f (attendu < 0, canon vers -Z)" %
			[_weapon_label(id), muzzle.position.z]).is_less(0.0)
		inst.free()


func test_every_weapon_model_has_a_foregrip_anchor_distinct_from_muzzle_and_origin() -> void:
	for id in WEAPON_IDS:
		var inst := _load_model(id)
		var muzzle := inst.find_child("Muzzle", true, false) as Node3D
		var foregrip := inst.find_child("Foregrip", true, false) as Node3D
		assert_object(foregrip).append_failure_message(
			"%s : empty \"Foregrip\" introuvable" % _weapon_label(id)).is_not_null()
		# L'origine de l'arme EST le point d'ancrage du gant droit ("Grip" —
		# ViewModel._attach_gloves : transform IDENTITÉ, aucun empty dédié à
		# chercher) : Foregrip doit s'en écarter d'une marge non négligeable
		# pour que le gant gauche ne s'y superpose pas.
		assert_float(foregrip.position.length()).append_failure_message(
			"%s : Foregrip trop proche de l'origine (%.4f m)" %
			[_weapon_label(id), foregrip.position.length()]).is_greater(0.02)
		assert_float(foregrip.position.distance_to(muzzle.position)).append_failure_message(
			"%s : Foregrip confondu avec Muzzle" % _weapon_label(id)).is_greater(0.02)
		inst.free()


func test_muzzle_and_foregrip_anchors_match_the_backed_up_bpy_reference() -> void:
	# "reprendre ses ancres Grip/Foregrip/Muzzle" (contrat A3D-20) : les
	# positions locales doivent être EXACTEMENT celles de l'arme bpy d'origine
	# (assets/models/weapons/_bpy/<id>.glb, jamais recalculées), pas seulement
	# "présentes quelque part" — voir fit_weapon_painted.py::add_anchor_empty.
	for id in WEAPON_IDS:
		var stem: String = _STEMS_BY_ID[id]
		var backup_path := "res://assets/models/weapons/_bpy/%s.glb" % stem
		assert_bool(ResourceLoader.exists(backup_path)).append_failure_message(
			"%s : sauvegarde bpy introuvable (%s) — impossible de vérifier les ancres" %
			[_weapon_label(id), backup_path]).is_true()
		var backup_scene: PackedScene = load(backup_path)
		var backup_inst := backup_scene.instantiate() as Node3D

		var inst := _load_model(id)
		var muzzle := inst.find_child("Muzzle", true, false) as Node3D
		var foregrip := inst.find_child("Foregrip", true, false) as Node3D
		var backup_muzzle := backup_inst.find_child("Muzzle", true, false) as Node3D
		var backup_foregrip := backup_inst.find_child("Foregrip", true, false) as Node3D

		assert_float(muzzle.position.distance_to(backup_muzzle.position)).append_failure_message(
			"%s : Muzzle peint %s != Muzzle bpy %s" %
			[_weapon_label(id), muzzle.position, backup_muzzle.position]).is_less(0.001)
		assert_float(foregrip.position.distance_to(backup_foregrip.position)).append_failure_message(
			"%s : Foregrip peint %s != Foregrip bpy %s" %
			[_weapon_label(id), foregrip.position, backup_foregrip.position]).is_less(0.001)
		inst.free()
		backup_inst.free()


# ======================================================================
#  Chemin ViewModel — le matériau peint reçoit bien ink_toon (jamais laissé
#  tel quel), voir ViewModel._apply_cartoon_materials/_PAINTED_MATERIAL_MARKER.
# ======================================================================
func test_viewmodel_applies_painted_ink_toon_material_to_every_weapon() -> void:
	var vm := ViewModel.new()
	for id in WEAPON_IDS:
		var inst := _load_model(id)
		vm._apply_cartoon_materials(inst)
		var checked := false
		for mesh in _find_mesh_instances(inst):
			for i in mesh.mesh.get_surface_count():
				var original: Material = mesh.mesh.surface_get_material(i)
				if not (original and (original.resource_name as String).contains(PAINTED_MARKER)):
					continue
				var applied: Material = mesh.get_surface_override_material(i)
				assert_object(applied).append_failure_message(
					"%s : surface peinte sans override" % _weapon_label(id)).is_not_null()
				assert_bool(applied is ShaderMaterial).append_failure_message(
					"%s : le matériau appliqué n'est pas un ShaderMaterial ink_toon" %
					_weapon_label(id)).is_true()
				checked = true
		assert_bool(checked).append_failure_message(
			"%s : aucune surface peinte vérifiée (matériau \"*%s*\" absent ?)" %
			[_weapon_label(id), PAINTED_MARKER]).is_true()
		inst.free()
	vm.free()
