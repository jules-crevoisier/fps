## test_minimap.gd
## Spec UX-04 (docs/research/04_ui_ux.md §4 #4, tâche UX-04 — "Minimap (240 px
## à 1080p) dessinée depuis Layouts + nom de la zone courante sous la
## minimap") : la minimap rend les empreintes des pièces Layouts (sol, murs,
## couverts) en top-down, oriente le joueur, montre les alliés (●) et les
## ennemis révélés (▼) SEULEMENT — un ennemi non révélé n'a structurellement
## aucun moyen d'apparaître (Minimap.revealed_enemy_positions ne lit jamais un
## PlayerController directement, voir Minimap.gd doc de classe) ; le nom de
## zone (LocationLabel) reflète toujours la dernière image lue (< 250 ms).
extends GdUnitTestSuite

## Pièces au format `Layouts.gd` (Dictionary pures — voir doc de classe de
## Layouts.gd "PURES... aucun nœud, aucun moteur nécessaire") : un sol, un mur,
## un couvert (container), un élément décoratif (accent, hors contrat) et un
## mur invisible (jamais de color_key, hors contrat) — mêmes clés EXACTES que
## les 6 maps réelles.
const _SAMPLE_PIECES: Array = [
	{"type": "box", "name": "Ground", "pos": Vector3(0, -1, 0), "size": Vector3(10, 2, 6), "color_key": "floor"},
	{"type": "box", "name": "Wall1", "pos": Vector3(5, 1, 0), "size": Vector3(1, 3, 6), "color_key": "wall"},
	{"type": "container", "name": "Cover1", "pos": Vector3(-3, 1, 2), "size": Vector3(2, 2, 2), "color_key": "cover"},
	{"type": "box", "name": "Deco", "pos": Vector3(0, 5, 0), "size": Vector3(2, 2, 2), "color_key": "accent"},
	{"type": "invisible_wall", "name": "Edge", "start": Vector3(-10, 0, -10), "end": Vector3(10, 0, -10), "height": 8.0},
	{"type": "fence", "name": "RailN", "start": Vector3(-5, 0, -3), "end": Vector3(5, 0, -3), "height": 1.0, "color_key": "wall"},
]


func _minimap() -> Minimap:
	var mm := Minimap.new()
	add_child(mm)
	auto_free(mm)
	return mm


func _location_label() -> LocationLabel:
	var lbl := LocationLabel.new()
	add_child(lbl)
	auto_free(lbl)
	return lbl


# ================================================ footprints_from_pieces (pure, LD-04 Layouts)

func test_footprints_from_pieces_keeps_only_floor_wall_cover() -> void:
	var fps := Minimap.footprints_from_pieces(_SAMPLE_PIECES)
	assert_int(fps.size()).append_failure_message(
		"attendu 4 (Ground/Wall1/Cover1/RailN) -- Deco (accent) et Edge (invisible_wall, sans color_key) ne sont jamais des empreintes minimap"
	).is_equal(4)


func test_footprints_from_pieces_box_rect_matches_kit_piece_footprint() -> void:
	var fps := Minimap.footprints_from_pieces(_SAMPLE_PIECES)
	var ground: Dictionary = fps[0]
	assert_str(String(ground["kind"])).is_equal("floor")
	var rect: Rect2 = ground["rect"]
	assert_vector(rect.position).is_equal_approx(Vector2(-5, -3), Vector2.ONE * 0.001)
	assert_vector(rect.size).is_equal_approx(Vector2(10, 6), Vector2.ONE * 0.001)


func test_footprints_from_pieces_fence_gets_a_thin_but_nonzero_rect() -> void:
	var fps := Minimap.footprints_from_pieces(_SAMPLE_PIECES)
	var rail: Dictionary = fps[3]
	assert_str(String(rail["kind"])).is_equal("wall")
	var rect: Rect2 = rail["rect"]
	assert_bool(rect.size.x > 0.0).is_true()
	assert_bool(rect.size.y > 0.0).is_true()


func test_footprints_from_pieces_of_empty_array_is_empty() -> void:
	assert_array(Minimap.footprints_from_pieces([])).is_empty()


func test_footprints_from_pieces_ignores_a_piece_with_no_pos_and_no_start() -> void:
	# Pièce mal formée (ni pos/size ni start/end) : Kit.piece_footprint replie
	# sur un rectangle nul -- jamais dessinée (contrat : pas de crash non plus).
	var broken := [{"type": "box", "name": "Broken", "color_key": "wall"}]
	assert_array(Minimap.footprints_from_pieces(broken)).is_empty()


# ================================================ footprints_in_range (culling par rayon)

func test_footprints_in_range_keeps_footprint_the_player_stands_in() -> void:
	var fps := Minimap.footprints_from_pieces(_SAMPLE_PIECES)
	var near := Minimap.footprints_in_range(fps, Vector2(0, 0), 4.0)
	var kinds: Array = []
	for fp in near:
		kinds.append(String((fp as Dictionary)["kind"]))
	assert_array(kinds).append_failure_message(str(kinds)).contains(["floor"])


func test_footprints_in_range_excludes_a_footprint_entirely_outside_the_radius() -> void:
	# Rect isolé (min(4.5,-3) max(5.5,3), même géométrie que "Wall1" ci-dessus)
	# -- point le plus proche de l'origine est (4.5,0), à 4.5 m : exclu à un
	# rayon de 4 m. Isolé plutôt que mélangé à _SAMPLE_PIECES : un autre mur
	# (RailN) est légitimement à moins de 4 m de l'origine et fausserait un
	# test qui se contenterait de vérifier "aucun mur ne survit".
	var far_wall := [{"rect": Rect2(Vector2(4.5, -3.0), Vector2(1.0, 6.0)), "kind": "wall"}]
	assert_array(Minimap.footprints_in_range(far_wall, Vector2(0, 0), 4.0)).is_empty()


func test_footprints_in_range_of_empty_array_is_empty() -> void:
	assert_array(Minimap.footprints_in_range([], Vector2.ZERO, 100.0)).is_empty()


# ================================================ clip_rect_to_view / footprint_screen_rect / positions_in_range
# REVUE LEAD 2026-09-25T20:37 (capture 01_hud_wasteland_1080p.jpg, « la
# minimap Wasteland déborde de son cadre ... plan dessiné en bas à droite,
# hors du carré noir ») : `footprints_in_range` (culling par rayon, ci-dessus)
# garde une empreinte dès que son point le plus proche du joueur est dans le
# rayon -- mais un LONG mur qui longe le joueur peut quand même s'étendre bien
# au-delà de ce rayon sur son autre axe, et donc déborder du cadre 240 px une
# fois projeté SANS rognage. Ces tests verrouillent le rognage géométrique
# (jamais un test de rendu -- voir la doc de classe "Fonctions PURES...
# testables sans nœud").

func test_clip_rect_to_view_shrinks_a_rect_that_extends_past_the_radius_on_one_axis() -> void:
	# Même géométrie qu'un long mur Wasteland (des dizaines de mètres) qui
	# longe le joueur de près sur Z (-1..1) : rogné à la fenêtre carrée de
	# rayon 28 m sur X, inchangé sur Z (déjà dans la fenêtre).
	var world_wall := Rect2(Vector2(-1000.0, -1.0), Vector2(2000.0, 2.0))
	var clipped := Minimap.clip_rect_to_view(world_wall, Vector2.ZERO, Minimap.VIEW_RADIUS_M)

	assert_vector(clipped.position).is_equal_approx(Vector2(-Minimap.VIEW_RADIUS_M, -1.0), Vector2.ONE * 0.001)
	assert_vector(clipped.end).is_equal_approx(Vector2(Minimap.VIEW_RADIUS_M, 1.0), Vector2.ONE * 0.001)


func test_clip_rect_to_view_leaves_a_rect_already_inside_the_window_untouched() -> void:
	var room := Rect2(Vector2(-2.0, -3.0), Vector2(4.0, 6.0))
	var clipped := Minimap.clip_rect_to_view(room, Vector2.ZERO, Minimap.VIEW_RADIUS_M)

	assert_vector(clipped.position).is_equal_approx(room.position, Vector2.ONE * 0.001)
	assert_vector(clipped.size).is_equal_approx(room.size, Vector2.ONE * 0.001)


func test_clip_rect_to_view_is_empty_when_entirely_outside_the_window() -> void:
	var far_away := Rect2(Vector2(500.0, 500.0), Vector2(10.0, 10.0))
	var clipped := Minimap.clip_rect_to_view(far_away, Vector2.ZERO, Minimap.VIEW_RADIUS_M)

	assert_bool(clipped.has_area()).append_failure_message(
		"un rectangle entièrement hors fenêtre doit rogner à une aire nulle -- jamais dessiné"
	).is_false()


func test_footprint_screen_rect_of_an_oversized_footprint_never_exceeds_the_panel() -> void:
	# Régression EXACTE de la REVUE LEAD : une empreinte bien plus grande que
	# la fenêtre visible (mur long) ne doit jamais produire un rectangle écran
	# qui déborde du panneau [0, SIZE_PX] x [0, SIZE_PX], quel que soit le
	# joueur ou la carte.
	var px_per_m := Minimap.px_per_meter(Minimap.SIZE_PX, Minimap.VIEW_RADIUS_M)
	var center := Vector2(Minimap.SIZE_PX, Minimap.SIZE_PX) * 0.5
	var world_wall := Rect2(Vector2(-1000.0, -1.0), Vector2(2000.0, 2.0))

	var screen := Minimap.footprint_screen_rect(world_wall, Vector2.ZERO, Minimap.VIEW_RADIUS_M, px_per_m, center)

	assert_bool(screen.has_area()).is_true()
	assert_float(screen.position.x).append_failure_message(
		"critère UX-40/minimap : aucun point dessiné hors du rect de la minimap (bord gauche)"
	).is_greater_equal(-0.01)
	assert_float(screen.position.y).is_greater_equal(-0.01)
	assert_float(screen.end.x).append_failure_message(
		"critère UX-40/minimap : aucun point dessiné hors du rect de la minimap (bord droit)"
	).is_less_equal(Minimap.SIZE_PX + 0.01)
	assert_float(screen.end.y).is_less_equal(Minimap.SIZE_PX + 0.01)


func test_footprint_screen_rect_is_empty_for_a_footprint_entirely_outside_the_view() -> void:
	var px_per_m := Minimap.px_per_meter(Minimap.SIZE_PX, Minimap.VIEW_RADIUS_M)
	var center := Vector2(Minimap.SIZE_PX, Minimap.SIZE_PX) * 0.5
	var far_away := Rect2(Vector2(500.0, 500.0), Vector2(10.0, 10.0))

	var screen := Minimap.footprint_screen_rect(far_away, Vector2.ZERO, Minimap.VIEW_RADIUS_M, px_per_m, center)

	assert_bool(screen.has_area()).is_false()


func test_positions_in_range_excludes_a_position_beyond_the_radius() -> void:
	var positions: Array = [Vector3(1.0, 0.0, 1.0), Vector3(500.0, 0.0, 500.0)]
	var near := Minimap.positions_in_range(positions, Vector2.ZERO, Minimap.VIEW_RADIUS_M)

	assert_int(near.size()).append_failure_message(
		"un allié/ennemi au-delà du rayon affiché ne doit jamais être dessiné -- même défaut que les empreintes non rognées"
	).is_equal(1)
	assert_vector(near[0] as Vector3).is_equal_approx(Vector3(1.0, 0.0, 1.0), Vector3.ONE * 0.001)


func test_positions_in_range_of_empty_array_is_empty() -> void:
	assert_array(Minimap.positions_in_range([], Vector2.ZERO, Minimap.VIEW_RADIUS_M)).is_empty()


# ================================================ to_map_point / px_per_meter (pures)

func test_to_map_point_translates_and_scales_from_player_origin() -> void:
	var pt := Minimap.to_map_point(Vector3(5, 0, 3), Vector3(2, 0, 3), 10.0)
	assert_vector(pt).is_equal_approx(Vector2(30, 0), Vector2.ONE * 0.001)


func test_to_map_point_is_the_zero_vector_at_the_player_position() -> void:
	var origin := Vector3(7, 1, -4)
	assert_vector(Minimap.to_map_point(origin, origin, 12.0)).is_equal_approx(Vector2.ZERO, Vector2.ONE * 0.001)


func test_px_per_meter_is_half_the_panel_size_over_the_view_radius() -> void:
	assert_float(Minimap.px_per_meter(240.0, 30.0)).is_equal_approx(4.0, 0.001)


func test_px_per_meter_is_zero_for_a_zero_radius_rather_than_dividing_by_zero() -> void:
	assert_float(Minimap.px_per_meter(240.0, 0.0)).is_equal_approx(0.0, 0.001)


# ================================================ player_heading_rad (oriente le joueur, carte fixe)

func test_player_heading_is_zero_when_facing_minus_z() -> void:
	# Convention du fichier (voir Minimap.gd doc de classe) : forward=-Z ->
	# flèche non tournée (pointe "vers le haut" du panneau, cap 0).
	assert_float(Minimap.player_heading_rad(Vector3(0, 0, -1))).is_equal_approx(0.0, 0.001)


func test_player_heading_defaults_to_zero_for_a_degenerate_forward() -> void:
	assert_float(Minimap.player_heading_rad(Vector3.ZERO)).is_equal_approx(0.0, 0.001)


func test_player_heading_rotates_the_arrow_to_match_an_arbitrary_facing() -> void:
	var forward := Vector3(1, 0, 0)
	var heading := Minimap.player_heading_rad(forward)
	# La flèche "vers le haut" (0,-1), tournée de `heading`, doit pointer dans
	# la MÊME direction écran que `forward` projeté (x,z) -- même convention
	# que to_map_point (aucun flip caché entre les deux fonctions).
	assert_vector(Vector2(0, -1).rotated(heading)).is_equal_approx(Vector2(forward.x, forward.z), Vector2.ONE * 0.001)


# ================================================ ally_positions (● toujours, relatif à l'équipe locale)

func test_ally_positions_keeps_only_candidates_on_the_local_team() -> void:
	var candidates: Array = [
		{"team": 0, "pos": Vector3(1, 0, 1)},
		{"team": 1, "pos": Vector3(2, 0, 2)},
		{"team": 0, "pos": Vector3(3, 0, 3)},
	]
	var allies := Minimap.ally_positions(candidates, 0)
	assert_int(allies.size()).is_equal(2)
	assert_vector(allies[0] as Vector3).is_equal(Vector3(1, 0, 1))
	assert_vector(allies[1] as Vector3).is_equal(Vector3(3, 0, 3))


func test_ally_positions_is_relative_never_hardcoded_on_team_zero() -> void:
	# Même règle que Comic.is_ally (UX-01) : un local en équipe 1 voit
	# l'équipe 1 comme alliée, jamais l'équipe 0 en dur.
	var candidates: Array = [{"team": 1, "pos": Vector3(9, 0, 9)}]
	assert_int(Minimap.ally_positions(candidates, 1).size()).is_equal(1)
	assert_array(Minimap.ally_positions(candidates, 0)).is_empty()


func test_ally_positions_shows_nobody_when_local_team_is_unknown() -> void:
	var candidates: Array = [{"team": 0, "pos": Vector3.ZERO}, {"team": 1, "pos": Vector3.ONE}]
	assert_array(Minimap.ally_positions(candidates, -1)).is_empty()


# ================================================ revealed_enemy_positions (▼ SEULEMENT si révélé)

func test_revealed_enemy_positions_reads_only_reveal_marker_label3d() -> void:
	# `global_position` exige le nœud DANS l'arbre (sinon Godot renvoie une
	# Transform3D vide, "!is_inside_tree()") -- même parti que
	# test_team_relative.gd (`add_child(...)` avant `auto_free(...)`).
	var marker := Label3D.new()
	add_child(marker)
	marker.text = Minimap.REVEAL_MARKER_TEXT
	marker.global_position = Vector3(6, 0, -2)
	var other_label := Label3D.new()
	add_child(other_label)
	other_label.text = "PAS UN MARQUEUR DE REVEAL"
	var smoke_wall := Node3D.new()
	add_child(smoke_wall)

	var enemies := Minimap.revealed_enemy_positions([marker, other_label, smoke_wall])

	assert_int(enemies.size()).is_equal(1)
	assert_vector(enemies[0] as Vector3).is_equal_approx(Vector3(6, 0, -2), Vector3.ONE * 0.001)

	auto_free(marker)
	auto_free(other_label)
	auto_free(smoke_wall)


func test_revealed_enemy_positions_of_empty_array_is_empty() -> void:
	assert_array(Minimap.revealed_enemy_positions([])).is_empty()


func test_minimap_never_shows_an_enemy_that_has_no_reveal_marker() -> void:
	# Contrat UX-04, "ennemis non révélés jamais affichés (le serveur n'envoie
	# rien de plus)" : un `Node` quelconque qui existerait pour un ennemi non
	# révélé (round_props peut contenir bien d'autres choses -- fumées,
	# tremplins, pièges) ne produit JAMAIS de position ennemie.
	var unrelated_prop := Node3D.new()
	var enemies := Minimap.revealed_enemy_positions([unrelated_prop])
	var mm := _minimap()
	mm.set_enemies(enemies)
	assert_int(mm.enemy_count()).is_equal(0)
	auto_free(unrelated_prop)


# ================================================ Minimap (nœud) -- état sans dépendre de _draw()

func test_minimap_default_size_is_240px_at_1080p() -> void:
	var mm := _minimap()
	assert_float(mm.custom_minimum_size.x).is_equal_approx(Minimap.SIZE_PX, 0.001)
	assert_float(mm.custom_minimum_size.y).is_equal_approx(Minimap.SIZE_PX, 0.001)


# ================================================ v4 -- plaque à coins coupés, flèche signal, "N" (UX-31)

func test_minimap_uses_a_chamfered_plate_matching_the_v4_minimap_chamfer() -> void:
	# UI_DIRECTION_BL3.md §5 « minimap à coins coupés » / §7 `shape.chamfer_px`
	# minimap = 22 px -- même fabrique que `Comic.plate_style()` (UX-30),
	# jamais le radius carré de l'ancienne classe de base `ComicPanel`.
	var mm := _minimap()
	var style: StyleBoxFlat = mm.get("_plate_style")
	assert_object(style).is_not_null()
	assert_int(style.corner_radius_top_right).is_equal(Comic.CHAMFER_PX_MINIMAP)
	assert_int(style.corner_radius_bottom_left).is_equal(Comic.CHAMFER_PX_MINIMAP)
	assert_int(style.corner_radius_top_left).is_equal(0)
	assert_int(style.corner_radius_bottom_right).is_equal(0)


func test_minimap_clips_its_contents_to_its_own_rect() -> void:
	# REVUE LEAD 2026-09-25T20:37 -- filet de sécurité VISUEL en plus du
	# rognage géométrique testé ci-dessus (`footprint_screen_rect`/
	# `positions_in_range`) : même fabrique que AgentSelectScreen.gd/
	# CrosshairEditor.gd (`clip_contents = true`).
	var mm := _minimap()
	assert_bool(mm.clip_contents).is_true()


func test_minimap_shows_a_fixed_north_label() -> void:
	# §5 « ... « N » » -- repère fixe, la carte elle-même ne pivote jamais
	# (voir doc de classe de Minimap.gd).
	var mm := _minimap()
	var north: Label = mm.get("_north_label")
	assert_object(north).is_not_null()
	assert_str(north.text).is_equal("N")


func test_minimap_set_layout_populates_footprint_count_from_layouts_pieces() -> void:
	var mm := _minimap()
	mm.set_layout(_SAMPLE_PIECES)
	assert_int(mm.footprint_count()).is_equal(4)


func test_minimap_set_allies_and_enemies_counts_are_independent() -> void:
	var mm := _minimap()
	mm.set_allies([Vector3(1, 0, 1), Vector3(2, 0, 2)])
	mm.set_enemies([Vector3(3, 0, 3)])
	assert_int(mm.ally_count()).is_equal(2)
	assert_int(mm.enemy_count()).is_equal(1)


func test_minimap_set_layout_can_be_called_again_on_map_change() -> void:
	var mm := _minimap()
	mm.set_layout(_SAMPLE_PIECES)
	assert_int(mm.footprint_count()).is_equal(4)
	mm.set_layout([])
	assert_int(mm.footprint_count()).is_equal(0)


# ================================================ Wasteland v4 (UX-39, retour lead 2026-09-25)
# Revue de reports/checkpoints/2026-09-25_UX-36/01_hud_wasteland_1080p.jpg :
# la minimap n'affichait que la flèche du joueur sur un carré noir -- la
# vraie cause était `tools/review/ui_shots.gd` qui chargeait
# `scenes/levels/tdm_map.tscn` (Map = CompMapBuilder, une arène placeholder
# qui ignore MatchConfig.map_id et ne pose donc jamais de nœud
# "nav_region"/MapSetup) au lieu de `scenes/levels/maps/wasteland.tscn` (la
# VRAIE scène, MapSetup.map_id="wasteland" -- voir le correctif dans ce
# fichier) : `GameHUD._acquire_map_setup` ne trouvait donc jamais de
# MapSetup et `Minimap.set_layout` n'était jamais appelée. Ce test verrouille
# le critère d'acceptation côté données (Minimap.gd est une fonction PURE,
# testable sans charger la scène 3D) : `WastelandLayout.data()["pieces"]`
# (LD-40, scripts/levels/maps/layouts/wasteland.gd) produit bien >= 20
# empreintes sol/mur/couvert une fois passées par `footprints_from_pieces` --
# indépendamment du bug de sélection de scène, réel mais hors de cette
# fonction pure (corrigé dans tools/review/ui_shots.gd).
func test_minimap_set_layout_wasteland_v4_has_at_least_20_footprints() -> void:
	var mm := _minimap()
	mm.set_layout(WastelandLayout.data().get("pieces", []))
	assert_int(mm.footprint_count()).append_failure_message(
		"%d empreintes -- attendu >= 20 (bâtiments/murs/couverts de Wasteland v4, deux moitiés + centre)" % mm.footprint_count()
	).is_greater_equal(20)


# ================================================ LocationLabel (état vide, mise à jour de zone)

func test_location_label_starts_hidden_as_the_empty_state() -> void:
	var lbl := _location_label()
	assert_bool(lbl.visible).append_failure_message(
		"aucune zone connue avant la 1re image : le bandeau doit rester caché (état vide), pas une case charcoal vide"
	).is_false()


func test_location_label_shows_and_uppercases_the_zone_name() -> void:
	var lbl := _location_label()
	lbl.set_zone_name("Quai Ouest")
	assert_bool(lbl.visible).is_true()
	assert_str(lbl.current_text()).is_equal("QUAI OUEST")


func test_location_label_hides_again_once_the_zone_becomes_empty() -> void:
	var lbl := _location_label()
	lbl.set_zone_name("Cour Est")
	lbl.set_zone_name("")
	assert_bool(lbl.visible).append_failure_message(
		"sorti de toute zone déclarée (bord de carte) : redevient l'état vide, ne garde pas le dernier nom affiché"
	).is_false()


func test_location_label_width_matches_the_minimap_width() -> void:
	# "nom de la zone courante SOUS la minimap" (contrat) : même largeur, pour
	# rester aligné sous le panneau plutôt que de déborder ou de le sous-remplir.
	var lbl := _location_label()
	assert_float(lbl.custom_minimum_size.x).is_equal_approx(Minimap.SIZE_PX, 0.001)


func test_location_label_updates_reflect_the_latest_position_every_frame() -> void:
	# Contrat : "nom de zone mis à jour <= 250 ms après le changement". GameHUD
	# appelle `set_zone_name` CHAQUE image (`_process`, `_update_minimap`) --
	# aucun sondage intermédiaire : une image à ~16 ms (60 fps) est donc déjà
	# ~15x sous le budget. Ce test verrouille l'API idempotente qui rend cela
	# possible sans travail inutile (pas de redessin quand la zone n'a pas
	# changé, voir LocationLabel.set_zone_name).
	var lbl := _location_label()
	lbl.set_zone_name("Ruelle Ouest")
	assert_str(lbl.current_text()).is_equal("RUELLE OUEST")
	lbl.set_zone_name("Ruelle Ouest")  # même zone, image suivante -- pas de régression.
	assert_str(lbl.current_text()).is_equal("RUELLE OUEST")
	lbl.set_zone_name("Rue du Saloon")  # changement de zone, image d'après.
	assert_str(lbl.current_text()).is_equal("RUE DU SALOON")


# ================================================ Budget CPU (<= 0,3 ms/image, voir Minimap.gd doc de classe)

func test_minimap_per_frame_path_does_not_recompute_layout_footprints() -> void:
	# La partie chère (parcours de TOUTES les pièces Layouts + Kit.piece_footprint)
	# ne doit tourner QU'À `set_layout()` (chargement de carte), jamais au fil
	# des images (`set_player_state`/`set_allies`/`set_enemies`) -- verrouille
	# la propriété d'ARCHITECTURE derrière le budget 0,3 ms/image, plutôt qu'une
	# mesure d'horloge murale bruitée en CI headless.
	var mm := _minimap()
	mm.set_layout(_SAMPLE_PIECES)
	var before := mm.footprint_count()
	for i in 120:  # ~2 s à 60 fps -- simule le travail par image seul.
		mm.set_player_state(Vector3(i, 0, 0), Vector3(0, 0, -1))
		mm.set_allies([Vector3(1, 0, 1)])
		mm.set_enemies([])
	assert_int(mm.footprint_count()).append_failure_message(
		"footprint_count() a changé après des updates PAR IMAGE seules -- set_player_state/set_allies/set_enemies ne doivent jamais retoucher aux empreintes"
	).is_equal(before)


func test_minimap_per_frame_transform_is_cheap_enough_for_the_frame_budget() -> void:
	# Garde-fou de régression (PAS la mesure officielle du budget 0,3 ms/image,
	# qui se fait au vrai profilage moteur, docs/REVIEW.md -- une horloge murale
	# en CI headless est bruitée) : le chemin par image (culling + transform,
	# sans la construction des empreintes) reste des ordres de grandeur sous
	# 0,3 ms même avec une marge très généreuse, pour attraper une régression
	# grossière (ex. quelqu'un qui réintroduit un O(taille de la carte) ici).
	var fps := Minimap.footprints_from_pieces(_SAMPLE_PIECES)
	var origin := Vector2.ZERO
	var px_per_m := Minimap.px_per_meter(Minimap.SIZE_PX, Minimap.VIEW_RADIUS_M)
	var iterations := 2000
	var start_usec := Time.get_ticks_usec()
	for i in iterations:
		var near := Minimap.footprints_in_range(fps, origin, Minimap.VIEW_RADIUS_M)
		for fp in near:
			var rect: Rect2 = (fp as Dictionary)["rect"]
			Minimap.to_map_point(Vector3(rect.position.x, 0.0, rect.position.y), Vector3.ZERO, px_per_m)
	var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	var per_frame_ms := elapsed_ms / float(iterations)
	assert_float(per_frame_ms).append_failure_message(
		"%.4f ms/appel (%d itérations, %.2f ms au total) -- marge très généreuse (10x le budget 0,3 ms), une vraie régression O(carte) la dépasserait largement" % [per_frame_ms, iterations, elapsed_ms]
	).is_less(3.0)
