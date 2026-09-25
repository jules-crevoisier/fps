## test_fp_gloves.gd
## Spec (FP-02, 2e passage) : fp_gloves.glb vient maintenant de
## tools/blender/fit_gloves_painted.py (mains Tripo Studio PEINTES, ART-84) —
## plus un seul bloc beige/manchette bleue plate dans la vue FPS. Ce fichier
## couvre, SANS dépendre d'un rendu texturé (indisponible en headless dans
## cet environnement de session, voir ViewModel.gd::_RIGHT_GLOVE_ANCHOR_BY_ID
## pour la même limite documentée) :
##   1. la géométrie exportée elle-même (nœuds "GloveR"/"GloveL" attendus par
##      ViewModel.gd, matériau peint reconnaissable par
##      `_PAINTED_MATERIAL_MARKER`, plus AUCUN slot "_glove"/"_cuff" à plat) ;
##   2. les tables PAR ARME de ViewModel.gd (ancrage/échelle, fonctions PURES,
##      même style de pin que tests/player/test_viewmodel_pose_math.gd) ;
##   3. un critère géométrique de non-régression pour « plus aucun bloc
##      détaché » : l'AABB monde du gant transformé (ancrage + échelle de
##      ViewModel.gd, transform IDENTITÉ sinon) chevauche l'AABB de l'arme
##      elle-même, pour les 7 armes peintes — un gant qui flotterait loin de
##      l'arme (régression du défaut que cette tâche corrige) ferait échouer
##      ce chevauchement, contrairement à un simple test de valeurs figées.
extends GdUnitTestSuite

const GLOVES_PATH := "res://assets/models/characters/fp_gloves.glb"
const _PAINTED_MARKER := "_painted"
## FP-03 : marqueur du matériau SÉPARÉ de la manche (tools/blender/
## fit_gloves_painted.py::_add_sleeve_material -- "tissu de veste sombre",
## JAMAIS la texture peinte du gant) -- voir ViewModel.gd::
## _apply_glove_materials pour la reteinte au runtime (couleur-clé de l'agent
## sélectionné, assombrie).
const _SLEEVE_MARKER := "_sleeve"


func _load_glove_node(name: String) -> Node3D:
	var packed := load(GLOVES_PATH) as PackedScene
	assert_object(packed).is_not_null()
	var gloves := packed.instantiate() as Node3D
	var node := gloves.find_child(name, true, false) as Node3D
	auto_free(gloves)
	return node


func _find_mesh_instances(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_find_mesh_instances(c))
	return out


# ---------------------------------------------------------------- géométrie exportée
func test_gloves_glb_exposes_glove_r_and_glove_l_nodes() -> void:
	var r := _load_glove_node("GloveR")
	var l := _load_glove_node("GloveL")
	assert_object(r).is_not_null()
	assert_object(l).is_not_null()


func test_glove_r_and_glove_l_each_carry_exactly_one_painted_material() -> void:
	# FP-03 (verdict lead fp_shots 2026-09-25 12h40, tools/blender/
	# fit_gloves_painted.py::_add_sleeve_material) : la manche est désormais un
	# matériau SÉPARÉ ("<gant>_sleeve", tissu plat -- JAMAIS la texture peinte
	# du gant, l'exact défaut que ce passage corrige, voir l'en-tête "FP-03" du
	# script Blender) -- chaque gant porte donc DEUX matériaux : le gant peint
	# ("_painted") ET la manche ("_sleeve"). Le critère ORIGINAL de ce test
	# (« un seul matériau PEINT par gant ») reste intact et toujours vérifié
	# ci-dessous -- il n'exige plus que TOUTE surface soit peinte, ce qui
	# excluait la manche par construction depuis qu'elle a son propre slot.
	for glove_name in ["GloveR", "GloveL"]:
		var glove := _load_glove_node(glove_name)
		var meshes := _find_mesh_instances(glove)
		assert_int(meshes.size()).is_greater(0)
		var painted_count := 0
		var sleeve_count := 0
		for mesh in meshes:
			assert_object(mesh.mesh).is_not_null()
			for i in mesh.mesh.get_surface_count():
				var mat: Material = mesh.mesh.surface_get_material(i)
				assert_object(mat).is_not_null()
				var mat_name: String = mat.resource_name
				# Plus AUCUN slot à plat "_glove"/"_cuff" (ancien corps bpy en
				# blocs de make_gloves.py) : la texture peinte couvre TOUT le
				# gant HORMIS la manche, qui a son propre matériau séparé
				# ci-dessous (notes de tâche FP-02 : « manchette laissée à sa
				# couleur peinte » -- portait sur l'ancienne manchette fondue
				# dans le maillage de la main, pas sur la manche FP-03).
				assert_bool(mat_name.ends_with("_glove")).is_false()
				assert_bool(mat_name.ends_with("_cuff")).is_false()
				if mat_name.contains(_PAINTED_MARKER):
					painted_count += 1
				elif mat_name.ends_with(_SLEEVE_MARKER):
					sleeve_count += 1
				else:
					fail("matériau inattendu sur %s : %s" % [glove_name, mat_name])
		assert_int(painted_count).is_equal(1)
		assert_int(sleeve_count).is_equal(1)


func test_glove_sleeve_material_is_a_flat_colour_without_the_glove_texture() -> void:
	# FP-03 (acceptance) : « manche = matériau SÉPARÉ... jamais la texture du
	# gant » -- la manche NE DOIT PORTER AUCUNE image (contrairement au gant,
	# voir test_glove_r_material_carries_an_albedo_texture juste au-dessus) :
	# la texture peau/cuir du gant étirée sur tout le tronc de cône était
	# EXACTEMENT le défaut rapporté par le lead sur fp_shots (« elle reprend
	# la texture du gant étirée »).
	for glove_name in ["GloveR", "GloveL"]:
		var glove := _load_glove_node(glove_name)
		var meshes := _find_mesh_instances(glove)
		var found := false
		for mesh in meshes:
			for i in mesh.mesh.get_surface_count():
				var mat: Material = mesh.mesh.surface_get_material(i)
				if mat and mat.resource_name.ends_with(_SLEEVE_MARKER):
					found = true
					var std := mat as StandardMaterial3D
					assert_object(std).is_not_null()
					assert_object(std.albedo_texture).is_null()
		assert_bool(found).is_true()


func test_glove_r_material_carries_an_albedo_texture() -> void:
	# Politique "peinture conservée" (ai_import_painted.py/fit_weapon_painted.py/
	# fit_gloves_painted.py) : le matériau importé doit rester un
	# StandardMaterial3D avec une texture d'albédo, jamais une couleur plate
	# résiduelle — c'est ce que `Cartoon.texture_from_imported_material` lit
	# côté ViewModel.gd::_apply_glove_materials.
	var r := _load_glove_node("GloveR")
	var meshes := _find_mesh_instances(r)
	assert_int(meshes.size()).is_greater(0)
	var mat := meshes[0].mesh.surface_get_material(0) as StandardMaterial3D
	assert_object(mat).is_not_null()
	assert_object(mat.albedo_texture).is_not_null()


func test_glove_meshes_stay_within_a_sane_hand_sized_bounding_box() -> void:
	# Main adulte réelle (tools/blender/fit_gloves_painted.py::ADULT_HAND_LENGTH_M
	# = 0,19 m) : plus AUCUNE dimension ne doit dépasser tres largement cette
	# longueur (garde-fou anti-régression -- un ré-export malformé qui
	# regonflerait l'échelle romprait ce test avant d'atteindre le jeu).
	#
	# FP-02 (3e passage) : seuil RELEVÉ de 0,30 à 0,60 -- la main porte
	# maintenant une MANCHE (tools/blender/fit_gloves_painted.py::_add_sleeve,
	# acceptance : « chaque gant se prolonge par une manche... qui sort du bord
	# bas/droit de l'écran »), longue par construction (_SLEEVE_LENGTH = 0,34 m)
	# pour sortir du cadre -- ce n'est plus une régression mais la géométrie
	# voulue.
	#
	# FP-03 : seuil RESSERRÉ de 0,60 à 0,50 -- le rayon du collier est
	# maintenant ABSOLU et petit (6 cm au poignet, 8 cm à la sortie, contre un
	# facteur relatif 2,2x qui gonflait démesurément la manche, voir l'en-tête
	# "FP-03" du script Blender), donc les tailles mesurées ont RÉTRÉCI d'autant
	# -- resserrer le seuil restaure une vraie garde-fou anti-régression
	# (0,60 ne détectait plus grand-chose face à ces nouvelles dimensions).
	# Sondage de cette tâche sur le .glb final (repère Godot, x=droite/
	# y=haut/z=profondeur) : GloveR size=(0,275;0,381;0,419), GloveL
	# size=(0,275;0,363;0,375).
	for glove_name in ["GloveR", "GloveL"]:
		var glove := _load_glove_node(glove_name)
		for mesh in _find_mesh_instances(glove):
			var size: Vector3 = mesh.mesh.get_aabb().size
			assert_float(size.x).is_less(0.50)
			assert_float(size.y).is_less(0.50)
			assert_float(size.z).is_less(0.50)


func test_glove_extends_past_hand_length_via_sleeve() -> void:
	# Non-régression positive (l'inverse du test ci-dessus) : la plus grande
	# dimension de l'AABB doit dépasser nettement ADULT_HAND_LENGTH_M (0,19 m)
	# -- une régression qui supprimerait la manche (retour à une main "nue",
	# _SLEEVE_LENGTH non appliquée) romprait CE test avant d'atteindre le jeu,
	# symétrique du garde-fou ci-dessus. FP-03 : seuil inchangé (0,32) -- la
	# manche rétrécie (voir le test ci-dessus) dépasse encore nettement cette
	# borne (GloveL, la plus courte des deux, mesure 0,375 -- marge réelle
	# contre une régression qui supprimerait la manche).
	for glove_name in ["GloveR", "GloveL"]:
		var glove := _load_glove_node(glove_name)
		var max_extent := 0.0
		for mesh in _find_mesh_instances(glove):
			var size: Vector3 = mesh.mesh.get_aabb().size
			max_extent = maxf(max_extent, maxf(size.x, maxf(size.y, size.z)))
		assert_float(max_extent).is_greater(0.32)


# ---------------------------------------------------------------- tables PAR ARME (ViewModel.gd)
# Pins de non-régression (même style que test_viewmodel_pose_math.gd) : une
# valeur ne change qu'après une nouvelle mesure (rendu ou, ici, dump AABB
# géométrique documenté sur chaque constante de ViewModel.gd), jamais pour
# faire "passer" ce test.
func test_right_glove_anchor_for_matches_tuned_constant_for_each_painted_weapon() -> void:
	assert_vector(ViewModel.right_glove_anchor_for(0)).is_equal_approx(Vector3(0.0, 0.011, 0.0), Vector3.ONE * 0.001)
	assert_vector(ViewModel.right_glove_anchor_for(1)).is_equal_approx(Vector3(0.0, 0.011, 0.0), Vector3.ONE * 0.001)
	assert_vector(ViewModel.right_glove_anchor_for(2)).is_equal_approx(Vector3(0.0, 0.016, 0.0), Vector3.ONE * 0.001)
	assert_vector(ViewModel.right_glove_anchor_for(3)).is_equal_approx(Vector3(0.0, 0.018, 0.0), Vector3.ONE * 0.001)
	assert_vector(ViewModel.right_glove_anchor_for(4)).is_equal_approx(Vector3(0.0, 0.018, 0.0), Vector3.ONE * 0.001)
	assert_vector(ViewModel.right_glove_anchor_for(5)).is_equal_approx(Vector3(0.0, 0.018, 0.0), Vector3.ONE * 0.001)
	assert_vector(ViewModel.right_glove_anchor_for(6)).is_equal_approx(Vector3(0.0, 0.018, 0.0), Vector3.ONE * 0.001)


func test_right_glove_anchor_defaults_to_zero_for_an_unknown_id() -> void:
	assert_vector(ViewModel.right_glove_anchor_for(-1)).is_equal(Vector3.ZERO)


# FP-02 (3e passage) : « la main droite lit comme une capsule sur Pistolet/
# Magnum/Marqueur » (acceptance) -- lacet PAR ARME (voir la doc de
# `_RIGHT_GLOVE_ROTATION_BY_ID` côté ViewModel.gd), SEULEMENT ces 3 armes,
# jamais un lacet partagé (qui casserait la lecture déjà bonne du Fracas --
# voir la doc). Même style de pin que `right_glove_anchor_for` ci-dessus.
func test_right_glove_rotation_for_matches_tuned_constant_for_capsule_weapons() -> void:
	assert_vector(ViewModel.right_glove_rotation_for(0)).is_equal_approx(Vector3(0.0, deg_to_rad(38.0), 0.0), Vector3.ONE * 0.001)
	assert_vector(ViewModel.right_glove_rotation_for(1)).is_equal_approx(Vector3(0.0, deg_to_rad(25.0), 0.0), Vector3.ONE * 0.001)
	assert_vector(ViewModel.right_glove_rotation_for(3)).is_equal_approx(Vector3(0.0, deg_to_rad(25.0), 0.0), Vector3.ONE * 0.001)


func test_right_glove_rotation_defaults_to_zero_for_already_readable_weapons() -> void:
	# Rafale/Ravage/Fracas/Faucheur (id 2/4/5/6) : déjà lisibles (jointures/
	# pouce visibles, voir la doc de `_RIGHT_GLOVE_ANCHOR_BY_ID`) -- repli
	# neutre, AUCUNE régression possible sur elles.
	for wid in [2, 4, 5, 6, -1]:
		assert_vector(ViewModel.right_glove_rotation_for(wid)).is_equal(Vector3.ZERO)


func test_glove_scale_defaults_to_one_for_every_weapon() -> void:
	# FP-02 : le nouveau gant est déjà à l'échelle adulte réelle, aucune
	# réduction par arme n'est présumée nécessaire (voir la doc de
	# `_RIGHT_GLOVE_SCALE_BY_ID`) — contrairement à l'ancien gabarit bloc
	# (0,40-0,55 selon l'arme, valeurs disparues avec lui.
	for wid in range(7):
		assert_float(ViewModel.right_glove_scale_for(wid)).is_equal_approx(1.0, 0.001)
		assert_float(ViewModel.left_glove_scale_for(wid)).is_equal_approx(1.0, 0.001)


# ---------------------------------------------------------------- non-régression géométrique
# Reproduit le calcul de `ViewModel._attach_gloves` (ancrage + échelle +
# rotation -- FP-02 3e passage : `right_glove_rotation_for`, plus
# systématiquement ZERO depuis le lacet par arme anti-"capsule") SANS
# instancier ViewModel/PlayerController (garde le test indépendant de l'arbre
# de scène joueur, même esprit que test_viewmodel_pose_math.gd) : l'AABB monde
# du gant ainsi transformé doit chevaucher l'AABB de l'arme -- un gant qui
# flotterait loin de l'arme (le défaut "bloc détaché" que cette tâche corrige)
# romprait ce chevauchement.
func _mesh_aabb(root: Node) -> AABB:
	var combined := AABB()
	var first := true
	for mesh in _find_mesh_instances(root):
		var world_aabb: AABB = mesh.transform * mesh.mesh.get_aabb()
		if first:
			combined = world_aabb
			first = false
		else:
			combined = combined.merge(world_aabb)
	return combined


func test_right_glove_overlaps_each_painted_weapon_once_anchored() -> void:
	var glove_r := _load_glove_node("GloveR")
	var glove_aabb := _mesh_aabb(glove_r)
	for wid in range(7):
		var path := Weapon.model_path_for(wid)
		if path.is_empty() or not ResourceLoader.exists(path):
			continue  # arme pas encore livrée (voir WeaponDatabase) -- rien à vérifier.
		var packed := load(path) as PackedScene
		var model := packed.instantiate() as Node3D
		var weapon_aabb := _mesh_aabb(model)
		var anchor := ViewModel.right_glove_anchor_for(wid)
		var scale := ViewModel.right_glove_scale_for(wid)
		var rotation := ViewModel.right_glove_rotation_for(wid)
		var basis := Basis.from_euler(rotation).scaled(Vector3.ONE * scale)
		var placed_transform := Transform3D(basis, anchor)
		var placed: AABB = placed_transform * glove_aabb
		assert_bool(weapon_aabb.intersects(placed)).is_true()
		model.free()


func test_left_glove_overlaps_each_painted_weapon_once_anchored_near_foregrip() -> void:
	var glove_l := _load_glove_node("GloveL")
	var glove_aabb := _mesh_aabb(glove_l)
	# Même calcul que ViewModel._left_glove_anchor (foregrip -> muzzle, t=0.4,
	# + _LEFT_GLOVE_DOWN_NUDGE) -- dupliqué ici plutôt qu'appelé : la fonction
	# réelle a besoin d'un `_model` déjà posé en enfant de ViewModel, ce test
	# reste volontairement indépendant de cet arbre de scène.
	const FOREGRIP_FORWARD_T := 0.4
	const LEFT_GLOVE_DOWN_NUDGE := Vector3(0.06, 0.03, 0.0)
	for wid in range(7):
		var path := Weapon.model_path_for(wid)
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		var model := packed.instantiate() as Node3D
		var weapon_aabb := _mesh_aabb(model)
		var foregrip := model.find_child("Foregrip", true, false) as Node3D
		var muzzle := model.find_child("Muzzle", true, false) as Node3D
		assert_object(foregrip).is_not_null()
		var anchor: Vector3 = foregrip.position
		if muzzle:
			anchor = anchor.lerp(muzzle.position, FOREGRIP_FORWARD_T)
		anchor += LEFT_GLOVE_DOWN_NUDGE
		var scale := ViewModel.left_glove_scale_for(wid)
		var placed := AABB(glove_aabb.position * scale + anchor, glove_aabb.size * scale)
		assert_bool(weapon_aabb.intersects(placed)).is_true()
		model.free()
