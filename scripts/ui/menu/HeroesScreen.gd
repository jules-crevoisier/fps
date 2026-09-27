## HeroesScreen.gd
## Écran PERSOS du salon (reports/ui/mockups/heroes.html, rendu
## reports/ui/renders/heroes.png). Roster réel (AgentDatabase.all(), un seul
## agent aujourd'hui) complété par des cartes verrouillées « Bientôt »
## (RosterPadding) jusqu'à 4 — grille 2×2 fixe, comme la maquette. « Choisir »
## fixe AgentDatabase.selected_index sur l'agent affiché.
class_name HeroesScreen
extends Control

const _CARD_SIZE := Vector2(176, 190)
const _CARD_GAP := 22.0
const _HERO_IMG := "res://assets/ui/renders/frog_aim.png"

## Bio de la maquette (heroes.html ".bio") — pas de champ dédié sur AgentConfig
## (prototype à un seul personnage) : copie réelle de la direction, gardée ici
## le temps qu'AgentConfig porte un champ `bio` (à demander au lead si un 2e
## agent arrive).
const _BIO_BY_NAME := {
	"Verrou": "Shérif d'un marécage où personne ne tire plus vite que lui. Verrou dégaine au premier bruit d'eau et ne rate jamais deux fois la même cible.",
}
const _SUBTITLE_BY_NAME := {
	"Verrou": "Duelliste · Cow-boy du marais",
}
const _KIT_ICONS := ["ravage_sticker", "revolver_sticker", "frag_sticker", "flash_sticker", "smoke_sticker"]

var _cards: Array[Dictionary] = []
var _shown_index: int = 0
var _name_label: Label
var _role_label: Label
var _bio_label: Label
var _pick_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_shown_index = AgentDatabase.selected_index
	_build()


func _build() -> void:
	add_child(MenuWidgets.sunburst_background(
		Color("FF5A3C"), Color("E8392E"), Color("E8392E"),
		true, Vector2(1040, 560), 520.0, UiTokens.YELLOW, Color("FFB21F")))

	var section_label := UiTokens.make_label("Personnages · %d disponible" % AgentDatabase.all().size(),
		UiTokens.display(UiTokens.T_L, UiTokens.PAPER, 4))
	section_label.position = Vector2(64, 118)
	add_child(section_label)

	_build_hero_image()
	_build_roster()
	_build_info_panel()


func _build_hero_image() -> void:
	var img := TextureRect.new()
	if ResourceLoader.exists(_HERO_IMG):
		img.texture = load(_HERO_IMG)
	img.position = Vector2(640, 120)
	img.size = Vector2(700, 1000)
	img.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(img)


func _build_roster() -> void:
	var names: Array = []
	for a in AgentDatabase.all():
		names.append(a.agent_name)
	var padded := RosterPadding.pad(names, 4)

	var root := Control.new()
	root.position = Vector2(64, 186)
	add_child(root)

	for i in padded.size():
		var col := i % 2
		var row := i / 2
		var card := _build_card(padded[i], i)
		card.position = Vector2(col * (_CARD_SIZE.x + _CARD_GAP), row * (_CARD_SIZE.x + _CARD_GAP))
		root.add_child(card)
		_cards.append({"index": i, "locked": padded[i]["locked"], "button": card})
	_refresh_cards()


func _build_card(entry: Dictionary, index: int) -> Control:
	var btn := Button.new()
	btn.size = _CARD_SIZE
	btn.custom_minimum_size = _CARD_SIZE
	btn.focus_mode = Control.FOCUS_ALL
	btn.clip_contents = true
	MenuWidgets.apply_plate_states(btn, UiTokens.PAPER, 0.0)

	if entry["locked"]:
		btn.disabled = true
		btn.tooltip_text = "Bientôt"
		var lock := TextureRect.new()
		lock.texture = UiTokens.icon("lock")
		lock.custom_minimum_size = Vector2(56, 64)
		lock.set_anchors_preset(Control.PRESET_CENTER)
		lock.position = Vector2(-28, -32)
		lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(lock)
	else:
		var portrait := TextureRect.new()
		portrait.texture = UiTokens.icon("portrait_verrou")
		portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(portrait)
		btn.pressed.connect(_on_card_pressed.bind(index))

	var tag := PanelContainer.new()
	tag.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tag.add_theme_stylebox_override("panel", UiTokens.plate(Color(UiTokens.INK.r, UiTokens.INK.g, UiTokens.INK.b, 0.85 if entry["locked"] else 1.0), 0.0, Vector2.ZERO, 0.0, Vector2(UiTokens.S2, UiTokens.S1 * 0.5)))
	tag.add_child(UiTokens.make_label(RosterPadding.LOCKED_TAG if entry["locked"] else entry["name"], UiTokens.label(UiTokens.T_S, UiTokens.PAPER), true))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(tag)
	return btn


func _on_card_pressed(index: int) -> void:
	_shown_index = index
	_refresh_cards()
	_refresh_info_panel()


func _refresh_cards() -> void:
	for c in _cards:
		var btn: Button = c["button"]
		var selected: bool = c["index"] == _shown_index
		if selected and not c["locked"]:
			MenuWidgets.apply_plate_states(btn, UiTokens.YELLOW, 0.0)
			var sb := btn.get_theme_stylebox("normal") as StyleBoxComic
			sb.drop = Vector2(12, 12)
			btn.position -= Vector2(4, 4) if not btn.has_meta("shifted") else Vector2.ZERO
			btn.set_meta("shifted", true)
		elif btn.has_meta("shifted"):
			btn.position += Vector2(4, 4)
			btn.remove_meta("shifted")


func _build_info_panel() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(1920 - 64 - 560, 170)
	col.custom_minimum_size = Vector2(560, 0)
	col.add_theme_constant_override("separation", UiTokens.S2)

	_name_label = UiTokens.make_label("", UiTokens.display(UiTokens.T_4XL, UiTokens.YELLOW, 10))
	col.add_child(_name_label)

	var role_wrap := PanelContainer.new()
	role_wrap.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.INK, UiTokens.SKEW_DEG, Vector2.ZERO, 0.0, Vector2(UiTokens.S2, UiTokens.S1 * 0.75)))
	_role_label = UiTokens.make_label("", UiTokens.label(UiTokens.T_S, UiTokens.PAPER), true)
	role_wrap.add_child(_role_label)
	col.add_child(role_wrap)

	var bio_panel := PanelContainer.new()
	bio_panel.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.PAPER, 0.0, UiTokens.DROP))
	_bio_label = UiTokens.make_label("", UiTokens.body(23))
	_bio_label.custom_minimum_size = Vector2(500, 0)
	_bio_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	bio_panel.add_child(_bio_label)
	col.add_child(bio_panel)

	var kit_panel := PanelContainer.new()
	kit_panel.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.PAPER, 0.0, UiTokens.DROP))
	var kit_row := HBoxContainer.new()
	kit_row.add_theme_constant_override("separation", UiTokens.S2)
	kit_row.add_child(UiTokens.make_label("Équipement", UiTokens.label(UiTokens.T_XS, UiTokens.INK_SOFT)))
	for icon_name in _KIT_ICONS:
		var tex := TextureRect.new()
		tex.texture = UiTokens.icon(icon_name)
		tex.custom_minimum_size = Vector2(0, 54)
		tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		kit_row.add_child(tex)
	kit_panel.add_child(kit_row)
	col.add_child(kit_panel)

	add_child(col)

	_pick_button = MenuWidgets.comic_button("Choisir", UiTokens.YELLOW, UiTokens.T_3XL)
	_pick_button.add_theme_font_override("font", UiTokens.FONT_DISPLAY)
	_pick_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_pick_button.position = Vector2(-64 - 280, -64 - 100)
	_pick_button.custom_minimum_size = Vector2(280, 100)
	_pick_button.pressed.connect(_on_pick_pressed)
	add_child(_pick_button)

	_refresh_info_panel()


func _refresh_info_panel() -> void:
	var agents := AgentDatabase.all()
	if _shown_index < 0 or _shown_index >= agents.size():
		_name_label.text = ""
		_role_label.text = RosterPadding.LOCKED_TAG
		_bio_label.text = "Bientôt disponible."
		_pick_button.disabled = true
		return
	var a: AgentConfig = agents[_shown_index]
	_name_label.text = a.agent_name.to_upper()
	_role_label.text = _SUBTITLE_BY_NAME.get(a.agent_name, a.role).to_upper()
	_bio_label.text = _BIO_BY_NAME.get(a.agent_name, a.description)
	_pick_button.disabled = false


func _on_pick_pressed() -> void:
	if _shown_index >= 0 and _shown_index < AgentDatabase.all().size():
		AgentDatabase.selected_index = _shown_index
