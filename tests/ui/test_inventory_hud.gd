## test_inventory_hud.gd
## Spec (contrat lead 2026-09-27, "inventaire CS-style", point 10) : panneau
## bas-droite de 5 rangées (armes 1/2 + grenades 3/4/5), hors de la zone
## centrale 40 %×40 %, rangée équipée surlignée en jaune signal, rangées
## vides/épuisées assombries à 35 % — voir scripts/ui/hud/InventoryHUD.gd.
## Remplace tests/combat/utility/test_utility_hud.gd (3 emplacements bas-centre,
## touches Q/C/X) : structure et contrat visuel entièrement différents,
## l'ancien fichier est supprimé plutôt que réutilisé.
extends GdUnitTestSuite


func _hud() -> InventoryHUD:
	var hud: InventoryHUD = auto_free(InventoryHUD.new())
	add_child(hud)
	return hud


func test_builds_exactly_five_rows() -> void:
	var hud := _hud()
	assert_int(hud._rows.size()).is_equal(5)


func test_row_numbers_are_digits_one_to_five_not_keyboard_labels() -> void:
	var hud := _hud()
	for i in 5:
		var row: Dictionary = hud._rows[i]
		var label: Label = row["number_label"]
		assert_str(label.text).append_failure_message(
			"la colonne numéro doit toujours afficher un CHIFFRE (1..5), jamais une touche clavier"
		).is_equal(str(i + 1))


func test_each_row_meets_the_44px_physical_minimum_height_at_1280x800() -> void:
	var hud := _hud()
	var factor := 1280.0 / 1920.0
	for row in hud._rows:
		var root: Control = row["root"]
		var physical_h: float = root.custom_minimum_size.y * factor
		assert_float(physical_h).append_failure_message(
			"une rangée doit faire au moins 44 px physiques de haut à 1280x800"
		).is_greater_equal(44.0)


# ---- placement hors de la zone centrale (contrat : bas-droite) ----

func test_panel_rect_never_overlaps_the_center_zone() -> void:
	var viewport := Vector2(1920.0, 1080.0)
	var overlaps := HudFormat.overlaps_center_zone(InventoryHUD.panel_rect(), viewport)
	assert_bool(overlaps).append_failure_message(
		"le panneau d'inventaire ne doit jamais chevaucher la zone centrale 40%%x40%%"
	).is_false()


## Choix utilisateur 2026-09-27 : barre d'inventaire centrée en bas (plus au-dessus des munitions).
func test_panel_rect_sits_centered_at_the_bottom() -> void:
	var viewport := Vector2(1920.0, 1080.0)
	var r := InventoryHUD.panel_rect()
	assert_float(r.get_center().x).append_failure_message("le panneau doit être CENTRÉ").is_equal_approx(viewport.x * 0.5, 1.0)
	assert_float(r.position.y).append_failure_message("le panneau doit être ancré en BAS").is_greater(viewport.y * 0.5)


# ---- update_weapon_slots (rangées 1/2) ----

## CHANGÉ (restyle "HUD en jeu" point 3, 2026-09-27) : le contrat visuel
## remplace le NOM textuel de l'arme par sa silhouette d'icône
## (WeaponIcon.sil, comme le fil des éliminations) — le nom en toutes lettres
## disparaît des rangées d'armes, `text_label` ne sert plus qu'au "—" grisé
## d'un slot VIDE (voir les deux tests suivants).
func test_update_weapon_slots_shows_the_weapon_icon() -> void:
	var hud := _hud()
	hud.update_weapon_slots(["RAVAGE", ""])
	var row0: Dictionary = hud._rows[0]
	var icon: TextureRect = row0["icon"]
	assert_bool(icon.visible).is_true()
	assert_str(icon.texture.resource_path.get_file().get_basename()).is_equal("ravage_sil")


## Tâche "revolver" (2026-09-27) : row 2 affiche désormais l'icône de l'arme
## secondaire réelle du loadout (WeaponDatabase.default_loadout_ids, slot 2)
## au lieu du "—" grisé historique (aucune arme secondaire n'existait avant
## cette tâche).
func test_update_weapon_slots_shows_revolver_icon_in_row_2() -> void:
	var hud := _hud()
	hud.update_weapon_slots(["RAVAGE", "REVOLVER"])
	var row1: Dictionary = hud._rows[1]
	var icon: TextureRect = row1["icon"]
	assert_str(icon.texture.resource_path.get_file().get_basename()).is_equal("revolver_sil")
	var root: Control = row1["root"]
	assert_float(root.modulate.a).append_failure_message(
		"un slot d'arme REMPLI ne doit jamais être assombri"
	).is_equal_approx(1.0, 0.001)


func test_update_weapon_slots_shows_em_dash_for_empty_slot() -> void:
	var hud := _hud()
	hud.update_weapon_slots(["RAVAGE", ""])
	var row1: Dictionary = hud._rows[1]
	var label: Label = row1["text_label"]
	assert_str(label.text).is_equal("—")
	assert_bool(label.visible).is_true()
	var icon: TextureRect = row1["icon"]
	assert_bool(icon.visible).append_failure_message(
		"un slot d'arme vide ne doit montrer aucune icône"
	).is_false()
	var root: Control = row1["root"]
	assert_float(root.modulate.a).append_failure_message(
		"un slot d'arme vide doit être assombri à 35%"
	).is_equal_approx(0.35, 0.001)


func test_update_weapon_slots_full_opacity_when_filled() -> void:
	var hud := _hud()
	hud.update_weapon_slots(["RAVAGE", "PETIT GUN"])
	for i in 2:
		var row: Dictionary = hud._rows[i]
		var root: Control = row["root"]
		assert_float(root.modulate.a).is_equal_approx(1.0, 0.001)


# ---- update_charges (rangées 3/4/5) ----

func test_update_charges_dims_an_empty_grenade_row() -> void:
	var hud := _hud()
	hud.update_charges([1, 1, 0])  # frag/flash pleins, smoke à 0
	var smoke_row: Dictionary = hud._rows[4]
	var root: Control = smoke_row["root"]
	assert_float(root.modulate.a).is_equal_approx(0.35, 0.001)
	var count_label: Label = smoke_row["count_label"]
	assert_str(count_label.text).is_equal("×0")


func test_update_charges_restores_full_opacity_when_refilled() -> void:
	var hud := _hud()
	hud.update_charges([0, 1, 1])
	hud.update_charges([1, 1, 1])
	var frag_row: Dictionary = hud._rows[2]
	var root: Control = frag_row["root"]
	assert_float(root.modulate.a).is_equal_approx(1.0, 0.001)
	var count_label: Label = frag_row["count_label"]
	assert_str(count_label.text).is_equal("×1")


# ---- set_equipped (rangée surlignée, contrat : "signal yellow #FFCE1F fill or border, ink text") ----

# CHANGÉ (restyle "HUD en jeu" point 3) : les rangées sont désormais des
# plaques BD INCLINÉES (StyleBoxComic, contrat "5 skewed slots"), plus des
# StyleBoxFlat sans pente — `bg_color` devient `fill`, mêmes seuils de
# couleur/contraste attendus.
func test_set_equipped_highlights_the_row_in_signal_yellow() -> void:
	var hud := _hud()
	hud.set_equipped(0)
	var row0: Dictionary = hud._rows[0]
	var sb: StyleBoxComic = row0["style"]
	assert_bool(sb.fill.is_equal_approx(Color("FFCE1F"))).append_failure_message(
		"la rangée équipée doit être surlignée en jaune signal #FFCE1F"
	).is_true()


func test_set_equipped_unhighlights_the_previous_row() -> void:
	var hud := _hud()
	hud.set_equipped(0)
	hud.set_equipped(2)
	var row0: Dictionary = hud._rows[0]
	var sb0: StyleBoxComic = row0["style"]
	assert_bool(sb0.fill.is_equal_approx(Color("FFCE1F"))).append_failure_message(
		"seule la rangée COURANTE doit rester surlignée"
	).is_false()
	var row2: Dictionary = hud._rows[2]
	var sb2: StyleBoxComic = row2["style"]
	assert_bool(sb2.fill.is_equal_approx(Color("FFCE1F"))).is_true()


func test_set_equipped_forces_full_opacity_even_if_just_emptied() -> void:
	# Contrat : juste après un lancer, la grenade reste équipée (retour en
	# cours, UtilityEquip.return_left) alors que sa charge est déjà à 0 --
	# les deux états (assombri / équipé) sont indépendants et peuvent coexister,
	# mais la rangée équipée reste TOUJOURS pleinement visible.
	var hud := _hud()
	hud.update_charges([0, 1, 1])  # frag à 0 -> rangée 2 assombrie
	hud.set_equipped(2)
	var frag_row: Dictionary = hud._rows[2]
	var root: Control = frag_row["root"]
	assert_float(root.modulate.a).is_equal_approx(1.0, 0.001)


# ---- glyphes (repris d'UtilityHUD, même contrat) ----

func test_glyph_textures_are_generated_without_crashing() -> void:
	for kind in [UtilityDatabase.FRAG, UtilityDatabase.FLASH, UtilityDatabase.SMOKE]:
		var tex := InventoryHUD._glyph_texture(kind, Color("0E0A12"))
		assert_object(tex).is_not_null()
		var img := tex.get_image()
		assert_bool(img.is_invisible()).append_failure_message(
			"un glyphe de type ne doit jamais être une image entièrement transparente"
		).is_false()


## CHANGÉ (restyle "HUD en jeu" point 3) : le chiffre n'est plus une COLONNE
## à gauche de la rangée mais une étiquette FLOTTANTE posée sur le coin
## haut-gauche du slot (contrat : "number tag", voir la maquette `.inv .s b`
## en position absolue au-dessus du coin) — elle peut donc chevaucher
## l'icône, mais reste toujours dans la MOITIÉ gauche du slot et au-dessus (ou
## au niveau) du haut de l'icône.
func test_slot_number_badge_floats_over_the_top_left_corner() -> void:
	var hud := _hud()
	await get_tree().process_frame
	for row in hud._rows:
		var root: Control = row["root"]
		var number_label: Control = row["number_label"]
		var num_rect := number_label.get_global_rect()
		var root_rect := root.get_global_rect()
		assert_float(num_rect.position.x - root_rect.position.x).append_failure_message(
			"le chiffre doit rester dans la moitié GAUCHE du slot"
		).is_less(root_rect.size.x * 0.5)
		var icon: Control = row["icon"]
		assert_float(num_rect.position.y).append_failure_message(
			"le chiffre doit flotter AU-DESSUS (ou au niveau) du haut de l'icône"
		).is_less_equal(icon.get_global_rect().position.y + 1.0)
