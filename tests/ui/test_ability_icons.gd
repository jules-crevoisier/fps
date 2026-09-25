## test_ability_icons.gd
## Spec UX-21 — « Icônes peintes des capacités et passifs (30) — découpe des
## planches Tripo, fond transparent, branchées dans le HUD et les écrans
## d'agents ».
##
## Le pixel (découpe des planches, détourage du fond en alpha, encre jamais
## touchée) est verrouillé côté Python : tools/ui/tests/test_slice_icon_sheets.py
## (rapide, itéré en boucle serrée). Cette suite verrouille la partie que SEUL
## Godot peut vérifier :
##
## 1) Les 30 PNG livrés (assets/ui/icons/abilities/) existent, se chargent en
##    128x128 avec un canal alpha réellement utilisé (fond détouré, pas une
##    case pleine ni un carré vide).
## 2) AgentDatabase.ability_icon/passive_icon résout la bonne icône pour les
##    6 agents x [passif, C, Q, E signature, X ultime], et reste sûr (`null`,
##    jamais un crash) hors roster.
## 3) AbilityBar (HUD) superpose l'icône de CHAQUE capacité sur sa tuile
##    penchée (UX-36), pour un agent réel -- jamais le seul losange abstrait
##    de ComicChip.
## 4) AgentSelectScreen et AgentMenu affichent l'icône de CHAQUE passif/
##    capacité dans leurs listes, pour les 6 agents.
extends GdUnitTestSuite

const ABILITY_BAR_SCRIPT := preload("res://scripts/ui/hud/AbilityBar.gd")
const AGENT_SELECT_SCREEN_SCRIPT := preload("res://scripts/ui/AgentSelectScreen.gd")
const AGENT_MENU_SCRIPT := preload("res://scripts/ui/AgentMenu.gd")

const EXPECTED_SIZE := 128
const SLOTS := ["C", "Q", "E", "X"]
const AGENT_KEYS := {
	"Vif": "vif", "Choc": "choc", "Vanne": "vanne",
	"Guet": "guet", "Roseau": "roseau", "Verrou": "verrou",
}

## `AgentDatabase.selected_index` est une var STATIQUE (même patron que
## tests/ui/test_agent_portraits.gd) -- sauvegardée/restaurée pour ne jamais
## polluer une autre suite.
var _saved_selected_index: int


func before_test() -> void:
	_saved_selected_index = AgentDatabase.selected_index


func after_test() -> void:
	AgentDatabase.selected_index = _saved_selected_index


func _ability_bar() -> AbilityBar:
	var bar: AbilityBar = ABILITY_BAR_SCRIPT.new()
	add_child(bar)
	auto_free(bar)
	return bar


func _agent_select_screen() -> CanvasLayer:
	var screen: CanvasLayer = AGENT_SELECT_SCREEN_SCRIPT.new()
	add_child(screen)
	auto_free(screen)
	return screen


func _agent_menu() -> Control:
	var menu: Control = AGENT_MENU_SCRIPT.new()
	add_child(menu)
	auto_free(menu)
	return menu


## Rectangles-icône SOUS `res://assets/ui/icons/abilities/` uniquement --
## écarte les autres TextureRect de ces écrans (ex. le portrait buste peint
## d'AgentSelectScreen, UX-20, assets/ui/portraits/), sans dépendre de la
## structure interne de `_cards`.
func _icon_rects_under(root: Node) -> Array:
	var found: Array = []
	for rect in root.find_children("*", "TextureRect", true, false):
		var tex: Texture2D = (rect as TextureRect).texture
		if tex and String(tex.resource_path).begins_with(AgentDatabase.ICON_DIR):
			found.append(rect)
	return found


# ================================================================
#  1) Les 30 PNG livrés (tools/ui/slice_icon_sheets.py)
# ================================================================

func test_thirty_icon_files_exist_for_the_six_agents() -> void:
	var expected: Array = []
	for agent_key in ["vif", "choc", "vanne", "guet", "roseau", "verrou"]:
		for slot_key in ["passive", "c", "q", "e", "x"]:
			expected.append("%s_%s" % [agent_key, slot_key])
	assert_int(expected.size()).is_equal(30)
	for name in expected:
		var path := "%s%s.png" % [AgentDatabase.ICON_DIR, name]
		assert_bool(ResourceLoader.exists(path)).append_failure_message(
			"icône manquante : %s -- lancer python tools/ui/slice_icon_sheets.py" % path
		).is_true()


func test_icons_are_128_square_with_a_used_alpha_channel() -> void:
	for agent_key in ["vif", "choc", "vanne", "guet", "roseau", "verrou"]:
		for slot_key in ["passive", "c", "q", "e", "x"]:
			var path := "%s%s_%s.png" % [AgentDatabase.ICON_DIR, agent_key, slot_key]
			if not ResourceLoader.exists(path):
				continue  # déjà signalé par test_thirty_icon_files_exist_for_the_six_agents.
			var tex: Texture2D = load(path)
			assert_object(tex).append_failure_message("%s doit se charger comme une texture" % path).is_not_null()
			assert_int(tex.get_width()).append_failure_message("%s : largeur attendue %d px" % [path, EXPECTED_SIZE]).is_equal(EXPECTED_SIZE)
			assert_int(tex.get_height()).append_failure_message("%s : hauteur attendue %d px" % [path, EXPECTED_SIZE]).is_equal(EXPECTED_SIZE)

			var img := tex.get_image()
			img.decompress()
			assert_bool(img.detect_alpha() != Image.ALPHA_NONE).append_failure_message(
				"%s : fond attendu détouré en alpha, canal alpha inutilisé (case pleine ?)" % path
			).is_true()


## La quasi-totalité des 30 icônes a une bonne marge de fond autour du picto
## (les 4 coins transparents) -- exactement DEUX planches Tripo vont jusqu'au
## bord de leur case par construction (fumée de Rideau/Guet, rideau de Voile/
## Roseau) : `tools/ui/tests/test_slice_icon_sheets.py::TestRealSheetCorners`
## le prouve pixel par pixel (les coins opaques y sont loin de la couleur de
## fond -- du vrai picto, jamais du fond oublié). Même seuil ici (>= 28/30),
## côté Godot, sur les fichiers réellement livrés.
func test_at_least_twenty_eight_of_thirty_icons_have_fully_transparent_corners() -> void:
	var fully_transparent := 0
	for agent_key in ["vif", "choc", "vanne", "guet", "roseau", "verrou"]:
		for slot_key in ["passive", "c", "q", "e", "x"]:
			var path := "%s%s_%s.png" % [AgentDatabase.ICON_DIR, agent_key, slot_key]
			if not ResourceLoader.exists(path):
				continue
			var img: Image = (load(path) as Texture2D).get_image()
			img.decompress()
			var all_transparent := true
			for c in [Vector2i(0, 0), Vector2i(EXPECTED_SIZE - 1, 0), Vector2i(0, EXPECTED_SIZE - 1), Vector2i(EXPECTED_SIZE - 1, EXPECTED_SIZE - 1)]:
				if img.get_pixelv(c).a > 0.01:
					all_transparent = false
					break
			if all_transparent:
				fully_transparent += 1
	assert_int(fully_transparent).append_failure_message(
		"seulement %d/30 icônes ont leurs 4 coins transparents" % fully_transparent
	).is_greater_equal(28)


# ================================================================
#  2) AgentDatabase.ability_icon / passive_icon
# ================================================================

func test_ability_icon_resolves_for_the_four_slots_of_all_six_agents() -> void:
	for agent in AgentDatabase.all():
		for slot in SLOTS:
			var tex := AgentDatabase.ability_icon(agent, slot)
			assert_object(tex).append_failure_message(
				"AgentDatabase.ability_icon(%s, \"%s\") doit résoudre une icône" % [agent.agent_name, slot]
			).is_not_null()
			var expected_path := "%s%s_%s.png" % [AgentDatabase.ICON_DIR, AGENT_KEYS[agent.agent_name], slot.to_lower()]
			assert_str(tex.resource_path).is_equal(expected_path)


func test_passive_icon_resolves_for_all_six_agents() -> void:
	for agent in AgentDatabase.all():
		var tex := AgentDatabase.passive_icon(agent)
		assert_object(tex).append_failure_message(
			"AgentDatabase.passive_icon(%s) doit résoudre une icône" % agent.agent_name
		).is_not_null()
		var expected_path := "%s%s_passive.png" % [AgentDatabase.ICON_DIR, AGENT_KEYS[agent.agent_name]]
		assert_str(tex.resource_path).is_equal(expected_path)


func test_icon_lookup_is_a_safe_null_off_roster_never_a_crash() -> void:
	assert_object(AgentDatabase.ability_icon(null, "C")).is_null()
	assert_object(AgentDatabase.passive_icon(null)).is_null()
	var unknown := AgentConfig.new()
	unknown.agent_name = "Inconnu"
	assert_object(AgentDatabase.ability_icon(unknown, "C")).is_null()
	assert_object(AgentDatabase.passive_icon(unknown)).is_null()


# ================================================================
#  3) AbilityBar (HUD) -- icône superposée sur CHAQUE tuile penchée
# ================================================================

func test_ability_bar_shows_the_agent_icon_on_every_chip() -> void:
	var agent: AgentConfig = AgentDatabase.all()[1]  # Choc -- 4 capacités C/Q/E/X.
	var bar := _ability_bar()
	var infos: Array = []
	for ab in agent.abilities:
		infos.append({"slot": ab.slot, "name": ab.display_name, "ult": ab.is_ultimate, "ratio": 1.0, "charges": 1})
	bar.refresh(infos, agent)

	assert_int(bar._chips.size()).is_equal(agent.abilities.size())
	assert_int(bar._chip_icons.size()).is_equal(agent.abilities.size())
	for i in agent.abilities.size():
		var icon: TextureRect = bar._chip_icons[i]
		assert_object(icon).append_failure_message(
			"chip %d (%s) : aucune icône superposée sur la tuile" % [i, agent.abilities[i].display_name]
		).is_not_null()
		assert_object(icon.get_parent()).append_failure_message(
			"l'icône doit être un enfant DU chip (composition externe sur ComicChip, jamais une modification de son script)"
		).is_equal(bar._chips[i])
		var expected := AgentDatabase.ability_icon(agent, agent.abilities[i].slot)
		assert_that(icon.texture).is_equal(expected)


func test_ability_bar_dims_the_icon_while_on_cooldown_full_opacity_when_ready() -> void:
	var agent: AgentConfig = AgentDatabase.all()[1]  # Choc.
	var bar := _ability_bar()
	var slot0: String = agent.abilities[0].slot
	bar.refresh([{"slot": slot0, "name": agent.abilities[0].display_name, "ult": false, "ratio": 0.0, "charges": 1}], agent)
	var icon: TextureRect = bar._chip_icons[0]

	bar.refresh([{"slot": slot0, "name": agent.abilities[0].display_name, "ult": false, "ratio": 0.5, "charges": 0}], agent)
	assert_float(icon.modulate.a).append_failure_message(
		"en recharge (aucune charge, cooldown en cours), l'icône doit être assourdie"
	).is_less(1.0)

	bar.refresh([{"slot": slot0, "name": agent.abilities[0].display_name, "ult": false, "ratio": 1.0, "charges": 1}], agent)
	assert_float(icon.modulate.a).append_failure_message(
		"prête (charge disponible), l'icône doit revenir en pleine opacité"
	).is_equal(1.0)


func test_ability_bar_without_an_agent_still_builds_chips_with_no_icon() -> void:
	# Repli historique (tests/ui/test_key_labels.gd) : `agent` reste optionnel.
	# Sans lui, impossible de résoudre une icône -- aucun crash, juste rien.
	var bar := _ability_bar()
	bar.refresh([{"slot": "Q", "name": "Fumée", "ult": false, "ratio": 1.0, "charges": 0}])
	assert_int(bar._chip_icons.size()).is_equal(1)
	assert_object(bar._chip_icons[0]).is_null()


# ================================================================
#  4) Écrans d'agents -- icône par ligne de capacité, pour les 6 agents
# ================================================================

func test_agent_select_screen_shows_five_icons_per_agent_card() -> void:
	var screen := _agent_select_screen()
	var agents := AgentDatabase.all()
	assert_int(screen._cards.size()).is_equal(agents.size())
	for i in agents.size():
		var agent: AgentConfig = agents[i]
		var card_button: Button = screen._cards[i].button
		var rects := _icon_rects_under(card_button)
		assert_int(rects.size()).append_failure_message(
			"la carte de %s doit montrer 5 icônes (passif + 4 capacités), %d trouvée(s)" % [agent.agent_name, rects.size()]
		).is_equal(5)

		var expected: Array = [AgentDatabase.passive_icon(agent)]
		for ab in agent.abilities:
			expected.append(AgentDatabase.ability_icon(agent, ab.slot))
		for j in rects.size():
			assert_that((rects[j] as TextureRect).texture).append_failure_message(
				"carte de %s, icône %d : ne correspond pas à l'icône attendue" % [agent.agent_name, j]
			).is_equal(expected[j])


func test_agent_menu_shows_five_icons_per_agent_card() -> void:
	var menu := _agent_menu()
	var agents := AgentDatabase.all()
	for agent in agents:
		var rects := _icon_rects_under(menu)
		# Cherché sur tout l'écran (AgentMenu ne garde pas de référence par
		# carte dans `_cards`, contrairement à AgentSelectScreen) -- filtré par
		# icône attendue plutôt que par position, en comptant les occurrences.
		var expected: Array = [AgentDatabase.passive_icon(agent)]
		for ab in agent.abilities:
			expected.append(AgentDatabase.ability_icon(agent, ab.slot))
		for exp_tex in expected:
			var matches := 0
			for r in rects:
				if (r as TextureRect).texture == exp_tex:
					matches += 1
			assert_int(matches).append_failure_message(
				"le menu Agents doit montrer l'icône %s au moins une fois pour %s" % [exp_tex.resource_path, agent.agent_name]
			).is_greater_equal(1)


func test_agent_menu_total_icon_count_matches_six_agents_times_five() -> void:
	var menu := _agent_menu()
	var rects := _icon_rects_under(menu)
	assert_int(rects.size()).append_failure_message(
		"6 agents x 5 icônes (passif + C/Q/E/X) attendues dans le menu Agents"
	).is_equal(30)
