## test_agent_portraits.gd
## Spec UX-20 — « Portraits et vitrine des agents avec les vrais modèles
## peints (cartes de sélection, menu principal) ».
##
## Capture du 2026-09-25 : les cartes de sélection montraient une grosse
## initiale (V, C, V, G, R, V) au lieu d'un portrait, et la vitrine du menu
## montrait trois silhouettes blanches unies. Cette suite verrouille :
##
## 1) Les 6 portraits (tools/review/agent_portraits.gd) existent, un PNG
##    512×512 par agent de AgentDatabase.all(), sous assets/ui/portraits/.
## 2) AgentSelectScreen affiche CE portrait sur chaque carte — plus
##    l'initiale géante — et réserve la couleur pleine à la carte
##    sélectionnée (design.md §9 : "l'agent sélectionné gagne SEUL sa couleur").
## 3) MainMenu (vitrine du menu) garde la texture peinte du modèle Tripo
##    (matériau "<id>_tex") au lieu de la repeindre en aplat blanc — cause
##    racine de la régression du 2026-09-25.
##
## Instances RÉELLES des deux écrans (comme tests/ui/test_main_menu.gd::_menu) :
## `_ready()` des deux scripts ne fait aucun appel réseau réel, donc sûr en
## headless — aucune capture d'écran n'est nécessaire pour ces assertions
## (matériaux et arbre de nœuds), voir tools/review/ui_shots.gd pour les
## captures avant/après en image.
extends GdUnitTestSuite

const AGENT_SELECT_SCRIPT := preload("res://scripts/ui/AgentSelectScreen.gd")
const MAIN_MENU_SCRIPT := preload("res://scripts/ui/MainMenu.gd")
const PORTRAIT_DIR := "res://assets/ui/portraits/"
const EXPECTED_PORTRAIT_SIZE := 512

## `AgentDatabase.selected_index` est une var STATIQUE (survit au changement
## de scène, voir son commentaire d'en-tête) : sauvegardée/restaurée pour ne
## jamais polluer une autre suite (même patron que tests/ui/test_main_menu.gd
## vis-à-vis de MatchConfig) — plusieurs tests ci-dessous appellent `_select`.
var _saved_selected_index: int


func before_test() -> void:
	_saved_selected_index = AgentDatabase.selected_index


func after_test() -> void:
	AgentDatabase.selected_index = _saved_selected_index


func _screen() -> CanvasLayer:
	var s: CanvasLayer = AGENT_SELECT_SCRIPT.new()
	add_child(s)
	auto_free(s)
	return s


func _menu() -> Node3D:
	var m: Node3D = MAIN_MENU_SCRIPT.new()
	add_child(m)
	auto_free(m)
	return m


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var found := _first_mesh(c)
		if found:
			return found
	return null


# ================================================================
#  1) Les 6 portraits générés (tools/review/agent_portraits.gd)
# ================================================================

func test_all_six_agents_have_a_generated_portrait_png() -> void:
	var agents := AgentDatabase.all()
	assert_int(agents.size()).append_failure_message(
		"ce test suppose le roster figé à 6 agents (docs/LORE.md §4.0)"
	).is_equal(6)
	for agent in agents:
		var id: String = agent.agent_name.to_lower()
		var path := "%s%s.png" % [PORTRAIT_DIR, id]
		assert_bool(ResourceLoader.exists(path)).append_failure_message(
			"portrait manquant pour %s (%s) -- lancer godot --path . -s res://tools/review/agent_portraits.gd" % [agent.agent_name, path]
		).is_true()


func test_generated_portraits_are_512_square_pngs() -> void:
	for agent in AgentDatabase.all():
		var id: String = agent.agent_name.to_lower()
		var path := "%s%s.png" % [PORTRAIT_DIR, id]
		if not ResourceLoader.exists(path):
			continue  # déjà signalé par test_all_six_agents_have_a_generated_portrait_png.
		var tex: Texture2D = load(path)
		assert_object(tex).append_failure_message(
			"le portrait de %s doit se charger comme une texture" % agent.agent_name
		).is_not_null()
		assert_int(tex.get_width()).append_failure_message(
			"portrait de %s : largeur attendue %d px" % [agent.agent_name, EXPECTED_PORTRAIT_SIZE]
		).is_equal(EXPECTED_PORTRAIT_SIZE)
		assert_int(tex.get_height()).append_failure_message(
			"portrait de %s : hauteur attendue %d px" % [agent.agent_name, EXPECTED_PORTRAIT_SIZE]
		).is_equal(EXPECTED_PORTRAIT_SIZE)


# ================================================================
#  2) Cartes de sélection (AgentSelectScreen)
# ================================================================

func test_agent_cards_show_the_generated_portrait_not_an_initial() -> void:
	var screen := _screen()
	var agents := AgentDatabase.all()

	assert_int(screen._cards.size()).is_equal(agents.size())
	for i in screen._cards.size():
		var c: Dictionary = screen._cards[i]
		var id: String = agents[i].agent_name.to_lower()
		assert_object(c.portrait).append_failure_message(
			"la carte de %s doit afficher le portrait généré, pas l'initiale de son nom" % agents[i].agent_name
		).is_not_null()
		var portrait: TextureRect = c.portrait
		assert_object(portrait.texture).append_failure_message(
			"la carte de %s a un nœud portrait mais sans texture chargée" % agents[i].agent_name
		).is_not_null()
		assert_str(portrait.texture.resource_path).append_failure_message(
			"la carte de %s doit charger assets/ui/portraits/%s.png" % [agents[i].agent_name, id]
		).is_equal("%s%s.png" % [PORTRAIT_DIR, id])
		assert_object(c.placeholder).append_failure_message(
			"aucun état de repli (glyphe géant) n'est nécessaire quand le portrait existe déjà"
		).is_null()


func test_agent_select_no_longer_builds_a_giant_initial_label() -> void:
	# Régression directe de la capture du 2026-09-25 ("grosse initiale V, C,
	# V, G, R, V") : le seul Label encore possible dans la plaque est le
	# glyphe de rôle de repli (placeholder, jamais construit ici puisque les
	# portraits existent) -- aucun Label ne doit porter la seule initiale du
	# nom de l'agent.
	var screen := _screen()
	var agents := AgentDatabase.all()
	for i in screen._cards.size():
		var c: Dictionary = screen._cards[i]
		var agent_initial: String = agents[i].agent_name.substr(0, 1)
		var plate: ComicPanel = c.plate
		for child in plate.body.get_children():
			if child is Label and child != c.placeholder:
				assert_str((child as Label).text).append_failure_message(
					"la plaque de %s ne doit plus afficher son initiale géante" % agents[i].agent_name
				).is_not_equal(agent_initial)


func test_selected_card_keeps_full_color_others_are_desaturated() -> void:
	var screen := _screen()

	screen._select(2)

	for i in screen._cards.size():
		var c: Dictionary = screen._cards[i]
		var portrait: TextureRect = c.portrait
		if i == 2:
			assert_that(portrait.modulate).append_failure_message(
				"la carte sélectionnée doit garder son portrait en couleur pleine (modulate blanc)"
			).is_equal(Color.WHITE)
		else:
			assert_that(portrait.modulate).append_failure_message(
				"une carte non sélectionnée doit désaturer son portrait vers le neutre (design.md §9), jamais rester en couleur pleine"
			).is_equal(Comic.TEXT_DIM)


func test_changing_selection_moves_the_full_color_to_the_new_card() -> void:
	var screen := _screen()
	screen._select(0)
	screen._select(3)

	var previous: TextureRect = screen._cards[0].portrait
	var current: TextureRect = screen._cards[3].portrait
	assert_that(previous.modulate).append_failure_message(
		"l'ancienne carte sélectionnée doit repasser désaturée dès qu'une autre est choisie"
	).is_equal(Comic.TEXT_DIM)
	assert_that(current.modulate).append_failure_message(
		"la nouvelle carte sélectionnée doit passer en couleur pleine"
	).is_equal(Color.WHITE)


# ================================================================
#  3) Vitrine du menu (MainMenu) — texture peinte conservée
# ================================================================

func test_menu_showcase_keeps_the_painted_texture_for_the_selected_character() -> void:
	var menu := _menu()
	var agent: AgentConfig = AgentDatabase.all()[0]

	var model: Node3D = menu._load_character_model(agent, true)
	assert_object(model).append_failure_message(
		"assets/models/characters/%s.glb doit s'instancier" % agent.agent_name.to_lower()
	).is_not_null()
	auto_free(model)

	var mesh := _first_mesh(model)
	assert_object(mesh).append_failure_message("aucun MeshInstance3D trouvé dans le modèle instancié").is_not_null()
	var mat := mesh.get_surface_override_material(0) as ShaderMaterial
	assert_object(mat).append_failure_message(
		"la surface doit porter un matériau de substitution (Cartoon.character_surface)"
	).is_not_null()
	assert_bool(bool(mat.get_shader_parameter("use_albedo_texture"))).append_failure_message(
		"la texture peinte du modèle Tripo (matériau \"<id>_tex\") doit être conservée -- " +
		"c'était la cause des silhouettes blanches unies constatées le 2026-09-25"
	).is_true()
	assert_object(mat.get_shader_parameter("albedo_texture")).append_failure_message(
		"albedo_texture ne doit jamais être vide quand use_albedo_texture est actif"
	).is_not_null()


func test_menu_showcase_desaturates_unselected_neighbours_without_losing_the_texture() -> void:
	var menu := _menu()
	var agent: AgentConfig = AgentDatabase.all()[0]

	var selected_model: Node3D = menu._load_character_model(agent, true)
	var neighbour_model: Node3D = menu._load_character_model(agent, false)
	auto_free(selected_model)
	auto_free(neighbour_model)

	var selected_mat := _first_mesh(selected_model).get_surface_override_material(0) as ShaderMaterial
	var neighbour_mat := _first_mesh(neighbour_model).get_surface_override_material(0) as ShaderMaterial

	assert_bool(bool(neighbour_mat.get_shader_parameter("use_albedo_texture"))).append_failure_message(
		"un voisin non sélectionné garde sa texture peinte -- seule la teinte change, jamais la texture"
	).is_true()

	var selected_tint: Color = selected_mat.get_shader_parameter("albedo_color")
	var neighbour_tint: Color = neighbour_mat.get_shader_parameter("albedo_color")
	assert_that(selected_tint).append_failure_message(
		"l'agent au centre du podium garde sa texture inchangée (teinte blanche)"
	).is_equal(Color.WHITE)
	assert_bool(neighbour_tint.is_equal_approx(Color.WHITE)).append_failure_message(
		"un agent voisin (non sélectionné) doit être désaturé vers text_dim, jamais laissé en pleine couleur"
	).is_false()
