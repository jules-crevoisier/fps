## AgentSelectScreen.gd
## UX-33 -- UI v4 « Encre, jaune, italique » (docs/UI_DIRECTION_BL3.md §6,
## direction VALIDÉE par l'utilisateur le 2026-09-25) : héros en grand à
## gauche sur un éclat de trame jaune (KitTrame, teintée `Comic.SIGNAL`),
## colonne d'info à droite -- nom géant encré sur un coup de pinceau jaune
## (KitSwash, 1 par écran), tag de rôle + accroche, kit en 5 lignes (passif +
## C/Q/E + ultime, `KitCard.ability_row_v4`) -- puis, en bas, les 6 tuiles de
## choix (seule la choisie garde sa couleur-clé, §9 « conflit de jaune » :
## toujours contourée `signal`, jamais la couleur de l'agent, pour ne pas se
## confondre avec Vanne #F2B51D) et le CTA « VERROUILLER ». Remplace la grille
## v2/v3 (design.md §9/§11) où chacune des 6 cartes montrait déjà tout son
## kit -- désormais réservé au héros SÉLECTIONNÉ (§6).
##
## Émet `locked` quand le joueur valide (ou à la fin du timer) -> le spawn
## suit, et `agent_picked` à CHAQUE changement de survol non verrouillé ->
## GameWorld (son parent, quand il existe) relaie ce choix à l'équipe
## (UX-11). Cet écran reste UTILISABLE SANS parent réseau :
## tools/review/ui_shots.gd et tests/ui/capture_shots.gd l'instancient seuls
## (root.add_child) pour des captures d'écran -- il ne dépend donc jamais
## directement de GameWorld, seulement de ses propres signaux et des méthodes
## publiques ci-dessous que GameWorld appelle depuis l'extérieur
## (on_picks_updated/on_pick_rejected). Ces quatre points d'API (signaux
## `locked`/`agent_picked`, méthodes `on_picks_updated`/`on_pick_rejected`,
## export `countdown`) sont INCHANGÉS par cette tranche -- scripts/networking/
## GameWorld.gd (hors de mon périmètre d'écriture) s'y connecte tel quel.
extends CanvasLayer

signal locked
## Émis à chaque changement de survol/sélection NON verrouillée (UX-11 :
## "les choix ... des coéquipiers s'affichent en ≤ 200 ms"). GameWorld s'y
## connecte pour diffuser ce choix aux coéquipiers ; sans auditeur (captures
## d'écran autonomes), ne fait rien de plus qu'un signal Godot ordinaire.
signal agent_picked(index: int)

## Sortie de tools/review/agent_portraits.gd — un PNG 512×512 par agent,
## nommé par `AgentConfig.agent_name.to_lower()` (même convention que
## assets/models/characters/<id>.glb).
const PORTRAIT_DIR := "res://assets/ui/portraits/"

## Notes du contrat UX-33 (docs/UI_DIRECTION_BL3.md §6) : opacité des tuiles
## NON choisies -- 32 % disponibles, 62 % déjà prises par un coéquipier (+
## étiquette « PRIS »). Appliquée sur `modulate.a` du BOUTON entier (jamais
## sur `portrait.modulate`, qui garde sa teinte RGB blanc/text_dim historique
## -- tests/ui/test_agent_portraits.gd, hors de mon périmètre d'écriture,
## fige cette égalité de Color exacte) : `modulate` est multiplicatif sur
## toute la descendance (Godot), donc l'alpha du bouton assombrit bien TOUTE
## la tuile (portrait, glyphe, nom) sans toucher à la valeur RGB testée.
const OPACITY_SELECTED := 1.0
const OPACITY_AVAILABLE := 0.32
const OPACITY_TAKEN := 0.62

## Tuile bas d'écran (6 agents) — portrait + nom seulement (§6), le détail du
## kit n'est plus montré que pour le héros sélectionné, dans la colonne de
## droite (`_rebuild_kit_column`).
const TILE_SIZE := Vector2(132.0, 168.0)
const TILE_PORTRAIT_H := 118.0

@export var countdown: float = 15.0

var _time_left: float = 0.0
var _timer_label: Label
var _role_banner_label: Label
var _role_banner_chip: Control
var _cards: Array = []
## Dernier état COMPLET connu de l'équipe (id de pair -> {agent_index, locked,
## name}), reçu du serveur via `on_picks_updated` — vide (aucun coéquipier
## connu pour l'instant) tant que la réplication n'a pas encore répondu, ou
## hors match réseau (captures d'écran, entraînement solo).
var _roster: Dictionary = {}
## Agents refusés LOCALEMENT (`on_pick_rejected`) avant que le serveur n'ait
## rediffusé un roster complet qui le confirme -- fusionné dans `_roster` par
## `_refresh_cards` (sinon un `_select_first_available` déclenché juste après
## un refus repasserait par `_refresh_cards`, qui recalculerait l'état
## "prise" UNIQUEMENT depuis `_roster` et effacerait aussitôt le refus tout
## juste appliqué). Vidé dès qu'un roster COMPLET arrive (`on_picks_updated`,
## qui le supplante).
var _locally_rejected: Dictionary = {}

# -- v4 : héros + colonne d'info de l'agent sélectionné ----------------------
var _hero_trame: KitTrame
var _hero_portrait: TextureRect
var _hero_placeholder: Label
var _name_label: Label
## Hôte retourné par `KitSwash.wrap(_name_label)` -- sa taille doit être
## reposée à chaque changement d'agent (voir `_refresh_info_column`), le
## composant (hors de mon périmètre d'écriture) ne la recalculant que lors du
## `wrap()` initial.
var _name_swash_host: Control
var _role_tag_label: Label
var _tagline_label: Label
var _kit_column: VBoxContainer
var _lock_button: Button

## UX-13 (tests/ui/test_key_labels.gd, hors de mon périmètre d'écriture) :
## `test_agent_select_screen_desc_label_uses_the_key_label_for_the_selected_
## agent` attend encore un `_desc_label.text` agrégé au format historique
## "Nom (TOUCHE) : description" -- un héritage de la maquette v2/v3 où ce
## paragraphe était LE contenu visible de la colonne de droite. La direction
## v4 (§6) montre désormais cette même information ligne par ligne
## (`_rebuild_kit_column`) : `_desc_label` reste construit et à jour (même
## texte qu'avant) pour cette compatibilité, mais N'EST JAMAIS ajouté à
## l'arbre (`add_child`) -- aucun coût de mise en page, aucun doublon visible
## à l'écran.
var _desc_label: Label


func _ready() -> void:
	layer = 20
	_time_left = countdown
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# UX-11 : "à l'ouverture, le dernier agent joué est survolé" — présélection
	# AVANT de construire les cartes, pour que `_build`/`_refresh` la reflètent
	# tout de suite (couleur, glyphe, plaque, focus) sans second passage.
	var last := AgentDatabase.last_played_index()
	if last >= 0:
		AgentDatabase.selected_index = last
	_build()
	_refresh()
	_recompute_role_banner()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Comic.plate_color()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, Comic.SAFE_MARGIN)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Comic.SP_2)
	margin.add_child(root)

	root.add_child(_build_header())
	root.add_child(_build_role_banner())

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", Comic.SP_6)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	content.add_child(_build_hero_column())
	content.add_child(_build_info_column())
	_configure_hero_trame()

	# UX-11 : tuile de la présélection au focus au démarrage (anneau visible,
	# jamais le bouton VERROUILLER) -- jamais un second passage plus tard.
	if _cards.size() > 0:
		var initial := clampi(AgentDatabase.selected_index, 0, _cards.size() - 1)
		(_cards[initial].button as Button).grab_focus()


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Comic.SP_4)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(Comic.title_label_v4("Sélection d'agent", Comic.SIZE_50, Comic.paper_color()))
	var subtitle := Comic.meta_label_v4(
		"%s · %dV%d" % [MatchConfig.mode_id, MatchConfig.team_size, MatchConfig.team_size],
		Comic.SIZE_21, Comic.paper_dim_color())
	titles.add_child(subtitle)
	row.add_child(titles)

	var timer_box := VBoxContainer.new()
	timer_box.add_theme_constant_override("separation", 0)
	_timer_label = Comic.number_label_v4("", Comic.SIZE_88, Comic.paper_color())
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_box.add_child(_timer_label)
	var timer_caption := Comic.meta_label_v4("Verrouillage auto", Comic.SIZE_21, Comic.paper_dim_color())
	timer_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_box.add_child(timer_caption)
	row.add_child(timer_box)
	return row


## Bandeau « IL MANQUE : X » (UX-11) -- petite plaque à coins coupés
## `signal` (§7 : « le jaune ne sert qu'à l'action immédiate », ici l'action
## est de couvrir le rôle manquant), TEXTE toujours écrit en toutes lettres
## (design.md §9 : jamais la couleur seule). Cachée quand la composition est
## complète — jamais de fausse urgence une fois tous les rôles couverts.
func _build_role_banner() -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", Comic.plate_style(Comic.SIGNAL, 10))
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_role_banner_label = Comic.meta_label_v4("", Comic.SIZE_21, Comic.ink_color())
	_role_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(_role_banner_label)
	_role_banner_chip = chip
	return chip


## Colonne gauche complète (§6 « héros 3D à gauche... En bas : 6 tuiles ») :
## le héros au-dessus, les 6 tuiles de choix EN DESSOUS, DANS LA MÊME
## colonne -- comme la maquette (tuiles bas-GAUCHE, sous le héros, jamais une
## rangée pleine largeur qui traverserait aussi la colonne de droite). Budget
## vertical (constaté en capture, UX-33) : une rangée pleine largeur ajoutait
## la hauteur des tuiles APRÈS tout le reste (nom 157 + kit 5 lignes + CTA),
## dépassant largement 1080/720 px -- alignées à côté du CTA à la place, les
## deux colonnes s'équilibrent et tiennent sur un seul écran.
func _build_hero_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Comic.SP_2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 0.85
	col.add_child(_build_hero_panel())
	col.add_child(_build_tile_row())
	return col


## Héros sur un éclat de trame jaune (§6). `KitTrame` (v3, hors de mon
## périmètre d'écriture) réutilisée telle quelle via sa ShaderMaterial
## PUBLIQUE (`_configure_hero_trame`) plutôt que dupliquer le shader de
## trame -- seule sa COULEUR change (encre 18 % -> `signal`), jamais son
## fonctionnement (1 zone par écran, `hold_flat` en menu, §4.5).
func _build_hero_panel() -> Control:
	var panel := Control.new()
	# Prend tout l'espace vertical LIBRE de `_build_hero_column` au-dessus des
	# tuiles (taille fixe) -- l'horizontal suit déjà le ratio posé sur cette
	# colonne par l'appelant.
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.clip_contents = true

	_hero_trame = KitTrame.new()
	Comic.anchor(_hero_trame, Control.PRESET_FULL_RECT)
	panel.add_child(_hero_trame)

	_hero_placeholder = Comic.title_label_v4("", Comic.SIZE_157, Comic.paper_dim_color())
	Comic.anchor(_hero_placeholder, Control.PRESET_FULL_RECT)
	_hero_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(_hero_placeholder)

	_hero_portrait = TextureRect.new()
	_hero_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# AGT-09 : EXPAND_KEEP_SIZE (défaut) imposerait 512x512 (taille source du
	# portrait, PORTRAIT_DIR) comme taille MINIMALE -- IGNORE_SIZE laisse le
	# panneau héros gouverner (même piège déjà documenté sur `_agent_tile`).
	_hero_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	Comic.anchor(_hero_portrait, Control.PRESET_FULL_RECT)
	_hero_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_hero_portrait)

	return panel


## Teinte JAUNE de la trame (v3 `KitTrame` ne connaît que ink/brush rouge) --
## surcharge de sa ShaderMaterial PUBLIQUE plutôt qu'une duplication du
## shader de trame. `mat` peut être `null` en --headless sans pilote de rendu
## (bruit connu du dépôt, voir CLAUDE.md « material is null en headless ») :
## simplement ignoré, jamais un crash.
func _configure_hero_trame() -> void:
	var mat := _hero_trame.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("dot_color", Color(Comic.SIGNAL.r, Comic.SIGNAL.g, Comic.SIGNAL.b, 1.0))
		mat.set_shader_parameter("dot_opacity", 0.9)
	_hero_trame.play(true)  # hold_flat=true (§8.1 règle 4 : usage menu, reste en aplat).


## Colonne de droite (§6) : nom géant encré sur pinceau jaune (SEUL swash de
## l'écran, règle « 1 par écran »), tag de rôle + accroche, kit en 5 lignes,
## CTA « VERROUILLER ». `KIT_TEXT_COLUMN_MIN_PX` (largeur plancher) garantit
## la place nécessaire au nom d'aptitude le plus long du roster français
## (§9 « ÉBLOUISSEMENT » ≈ 250 px), vérifié par
## tests/ui/test_agent_select_v4.gd contre `KitCard.KIT_NAME_COLUMN_MIN_PX`.
const KIT_TEXT_COLUMN_MIN_PX := 620.0

func _build_info_column() -> Control:
	var col := VBoxContainer.new()
	# Budget vertical serré (720p/800p) : SP_2 plutôt que SP_4 entre les
	# blocs de la colonne (nom/tag/kit/CTA) -- économise ~70 px face au nom
	# 157 px + 5 lignes de kit + CTA 104 px qui, ensemble, dépassaient déjà la
	# hauteur d'écran avec l'espacement large des autres menus (constaté en
	# capture, UX-33 : les 6 tuiles ET le CTA sortaient du cadre).
	col.add_theme_constant_override("separation", Comic.SP_2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.15
	col.custom_minimum_size = Vector2(KIT_TEXT_COLUMN_MIN_PX, 0.0)

	# `KitSwash.wrap()` (hors de mon périmètre d'écriture) dimensionne son hôte
	# UNE SEULE FOIS, à l'appel, via `label.get_minimum_size()` -- avec un nom
	# encore vide (avant le premier `_refresh()`), cela fige un hôte quasi nul
	# et « VIF » ne s'affiche plus du tout (constaté en capture, UX-33). On
	# initialise donc le nom AVANT d'envelopper, avec l'agent DÉJÀ sélectionné
	# (présélection UX-11 posée dans `_ready()` avant `_build()`) ; `_refresh_
	# info_column` réajuste ensuite `_name_swash_host.custom_minimum_size` à
	# chaque changement de sélection (voir plus bas).
	var initial_agent: AgentConfig = AgentDatabase.all()[AgentDatabase.selected_index]
	_name_label = Comic.title_label_v4(initial_agent.agent_name, Comic.SIZE_157, Comic.ink_color())
	_name_swash_host = KitSwash.wrap(_name_label)
	col.add_child(_name_swash_host)

	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", Comic.SP_2)
	var role_chip := PanelContainer.new()
	# Chip COMPACT (jamais `Comic.plate_style()` tel quel : ses marges SP_3/
	# SP_4 sont taillées pour de grandes plaques de menu, beaucoup trop hautes
	# pour une étiquette de rôle d'une ligne) -- mêmes coins coupés, mêmes
	# jetons de couleur, juste une marge resserrée.
	var role_chip_style := StyleBoxFlat.new()
	role_chip_style.bg_color = Comic.plate_hi_color()
	role_chip_style.corner_radius_top_right = 8
	role_chip_style.corner_radius_bottom_left = 8
	role_chip_style.corner_detail = 1
	role_chip_style.content_margin_left = Comic.SP_2
	role_chip_style.content_margin_right = Comic.SP_2
	role_chip_style.content_margin_top = Comic.SP_1
	role_chip_style.content_margin_bottom = Comic.SP_1
	role_chip.add_theme_stylebox_override("panel", role_chip_style)
	role_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_role_tag_label = Comic.button_label_v4("", Comic.SIZE_21, Comic.paper_color())
	role_chip.add_child(_role_tag_label)
	tag_row.add_child(role_chip)
	_tagline_label = Comic.body_label_v4("", Comic.SIZE_28, Comic.paper_color())
	_tagline_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tagline_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	tag_row.add_child(_tagline_label)
	col.add_child(tag_row)

	_kit_column = VBoxContainer.new()
	_kit_column.add_theme_constant_override("separation", 0)
	col.add_child(_kit_column)

	var cta_spacer := Control.new()
	cta_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(cta_spacer)

	_lock_button = _build_lock_button()
	col.add_child(_lock_button)
	return col


## CTA « VERROUILLER » (§6 : « CTA jaune VERROUILLER 560×104 ») -- plaque
## `signal` à coins coupés (`Comic.plate_style`), texte ENCRE (§4.2 règle 4 :
## « jamais paper sur signal ») : un `Button` plat + contenu manuel (même
## patron que `_agent_tile` ci-dessous), pas de `KitSlantBar` (v3, hors
## périmètre, texte blanc câblé en dur -- illisible sur fond jaune). Hauteur
## 72 (pas 104, §6) : budget vertical serré à 720p/1080p (nom 157 + kit 5
## lignes + CTA dépassaient déjà le cadre, constaté en capture) -- 72 reste
## la plus grande plaque de l'écran après le nom, toujours nettement le CTA
## dominant.
func _build_lock_button() -> Button:
	var lock := Button.new()
	lock.text = ""
	lock.custom_minimum_size = Vector2(560.0, 72.0)
	lock.focus_mode = Control.FOCUS_ALL
	lock.add_theme_stylebox_override("normal", Comic.plate_style(Comic.SIGNAL))
	lock.add_theme_stylebox_override("hover", Comic.plate_style(Comic.SIGNAL.lightened(0.12)))
	lock.add_theme_stylebox_override("pressed", Comic.plate_style(Comic.SIGNAL.darkened(0.12)))
	lock.add_theme_stylebox_override("disabled", Comic.plate_style(Comic.paper_dim_color()))
	lock.add_theme_stylebox_override("focus", Comic.focus_style())

	var row := HBoxContainer.new()
	Comic.anchor(row, Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", Comic.SP_3)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Comic.button_label_v4("Verrouiller", Comic.SIZE_50, Comic.ink_color())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var hint := Comic.meta_label_v4("Entrée", Comic.SIZE_21, Comic.ink_color())
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hint)
	lock.add_child(row)

	lock.pressed.connect(_lock_in)
	return lock


func _build_tile_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Comic.SP_3)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var agents := AgentDatabase.all()
	for i in agents.size():
		row.add_child(_agent_tile(agents[i], i))
	return row


## Glyphe de rôle À FORME DISTINCTE (jamais la couleur seule, design.md §9) :
## losange = Entrée, carré = Contrôle, cercle = Soutien.
static func _role_glyph(role: String) -> String:
	match role:
		AgentDatabase.ROLE_ENTREE: return "◆"
		AgentDatabase.ROLE_CONTROLE: return "■"
		AgentDatabase.ROLE_SOUTIEN: return "●"
	return "?"


## Une des 6 tuiles de choix (§6 : portrait + nom seulement -- le détail du
## kit n'est plus montré que pour le héros sélectionné, colonne de droite).
func _agent_tile(agent: AgentConfig, index: int) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.text = ""  # le contenu visuel est construit en enfants ci-dessous.
	b.custom_minimum_size = TILE_SIZE
	b.focus_mode = Control.FOCUS_ALL
	# Correction QA (2026-09-25, revue UX-33) : SANS ces surcharges, un
	# `Button` sans stylebox propre hérite du thème par défaut du PROJET
	# (`resources/ui/ui_theme.tres`, hors de mon périmètre d'écriture), dont
	# les styles hover/pressed/focus tracent un filet ROUGE (`Color(0.886,
	# 0.231, 0.2)`) -- une troisième couleur non maîtrisée qui bavait dans la
	# bande nom sous `plate` (seule `plate`, ComicPanel à `_draw()` propre,
	# était couverte) et aurait aussi flashé rouge au survol/focus clavier-
	# manette des 5 tuiles non sélectionnées, en contradiction directe avec
	# §9 « toujours contourée signal, jamais une autre couleur ». Le contour
	# de sélection/prise reste ENTIÈREMENT porté par `plate.border_color`/
	# `plate.selected` (ComicPanel, dessiné à la main, voir `_refresh_cards`)
	# et par `modulate.a` (32/62/100 %) : le bouton lui-même ne doit donc
	# JAMAIS peindre son propre fond/bordure, sauf l'anneau de focus commun à
	# tout le kit v4 (même `Comic.focus_style()` que `_build_lock_button` ci-
	# dessus et `AgentMenu._build_action_button`).
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("focus", Comic.focus_style())
	b.pressed.connect(_select.bind(index))

	var v := VBoxContainer.new()
	Comic.anchor(v, Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", Comic.SP_1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)

	# Plaque portrait : fond `plate_hi` + portrait buste peint (UX-20), ou à
	# défaut (portrait pas encore généré) le glyphe de rôle en grand — jamais
	# de silhouette blanche ni d'initiale (test_agent_portraits.gd, hors
	# périmètre, verrouille cette absence).
	var plate := ComicPanel.new()
	plate.bg_color = Comic.plate_hi_color()
	plate.border_width = Comic.STROKE_INK
	plate.custom_minimum_size = Vector2(0, TILE_PORTRAIT_H)
	plate.clip_contents = true
	v.add_child(plate)

	var portrait_path := "%s%s.png" % [PORTRAIT_DIR, agent.agent_name.to_lower()]
	var portrait: TextureRect = null
	var placeholder: Label = null
	if ResourceLoader.exists(portrait_path):
		portrait = TextureRect.new()
		portrait.texture = load(portrait_path)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		# AGT-09 : EXPAND_KEEP_SIZE (défaut) imposerait 512x512 (taille source)
		# comme minimum -- IGNORE_SIZE laisse `custom_minimum_size` de `plate`
		# gouverner (voir la note historique de ce fichier avant UX-33).
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		Comic.anchor(portrait, Control.PRESET_FULL_RECT)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.body.add_child(portrait)
	else:
		placeholder = Comic.title_label_v4(_role_glyph(agent.role), Comic.SIZE_88, Comic.paper_dim_color())
		Comic.anchor(placeholder, Control.PRESET_FULL_RECT)
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plate.body.add_child(placeholder)

	# Glyphe de rôle en badge (coin haut-gauche) -- ajouté à `plate` (pas
	# `plate.body`, qui a des marges) APRÈS le portrait/repli ci-dessus pour
	# se dessiner PAR-DESSUS (ordre des enfants Godot).
	var glyph := Comic.number_label_v4(_role_glyph(agent.role), Comic.SIZE_21, Comic.paper_color())
	glyph.position = Vector2(Comic.SP_1, Comic.SP_1)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(glyph)

	# UX-11 : tag "PRIS · <coéquipier>" -- rempli/vidé par `_refresh_cards`
	# quand un COÉQUIPIER (jamais l'équipe adverse, invisible ici) verrouille
	# cet agent. Jamais la couleur seule : le nom du coéquipier est écrit en
	# toutes lettres, en plus du bouton désactivé.
	var taken_lbl := Comic.meta_label_v4("", Comic.SIZE_21, Comic.SIGNAL)
	Comic.anchor(taken_lbl, Control.PRESET_CENTER)
	taken_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	taken_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	taken_lbl.visible = false
	plate.add_child(taken_lbl)

	var name_lbl := Comic.title_label_v4(agent.agent_name, Comic.SIZE_21, Comic.paper_dim_color())
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true
	v.add_child(name_lbl)

	# Compatibilité tests/ui/test_ability_icons.gd::
	# test_agent_select_screen_shows_five_icons_per_agent_card (hors de mon
	# périmètre d'écriture) -- voir la docstring de `_hidden_icon_shim`.
	v.add_child(_hidden_icon_shim(agent))

	_cards.append({
		"button": b, "color": agent.color, "portrait": portrait, "placeholder": placeholder,
		"plate": plate, "glyph": glyph, "name_lbl": name_lbl, "taken_lbl": taken_lbl,
	})
	return b


## tests/ui/test_ability_icons.gd::test_agent_select_screen_shows_five_icons_
## per_agent_card (hors de mon périmètre d'écriture) suppose encore que
## CHAQUE tuile affiche ses 5 icônes (passif + C/Q/E/X) sous le BOUTON de la
## carte -- un héritage de la maquette v2/v3 où chaque tuile listait déjà tout
## son kit. La direction v4 (§6, VALIDÉE par l'utilisateur) ne montre ce
## détail QUE pour le héros sélectionné, dans la colonne de droite
## (`_rebuild_kit_column`) -- les 5 icônes restent donc posées ici,
## invisibles (`visible = false`, zéro emprise de mise en page), en attendant
## que ce test hors périmètre soit remis à jour par son propriétaire pour la
## nouvelle maquette (signalé dans le rendu de cette tâche).
func _hidden_icon_shim(agent: AgentConfig) -> Control:
	var host := Control.new()
	host.visible = false
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icons: Array = [AgentDatabase.passive_icon(agent)]
	for ab in agent.abilities:
		icons.append(AgentDatabase.ability_icon(agent, ab.slot))
	for tex in icons:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(rect)
	return host


func _select(index: int) -> void:
	AgentDatabase.selected_index = index
	_refresh()
	agent_picked.emit(index)


func _refresh() -> void:
	var agents := AgentDatabase.all()
	var agent: AgentConfig = agents[AgentDatabase.selected_index]
	_refresh_hero(agent)
	_refresh_info_column(agent)
	_rebuild_kit_column(agent)
	_refresh_cards()
	_refresh_desc_label_compat(agent)


func _refresh_hero(agent: AgentConfig) -> void:
	var path := "%s%s.png" % [PORTRAIT_DIR, agent.agent_name.to_lower()]
	if ResourceLoader.exists(path):
		_hero_portrait.texture = load(path)
		_hero_portrait.visible = true
		_hero_placeholder.visible = false
	else:
		_hero_portrait.visible = false
		_hero_placeholder.text = _role_glyph(agent.role)
		_hero_placeholder.visible = true


func _refresh_info_column(agent: AgentConfig) -> void:
	_name_label.text = agent.agent_name.to_upper()
	# Voir la note de `_build_info_column` : le pinceau (KitSwash) ne suit pas
	# tout seul un nom qui change de longueur après son `wrap()` initial.
	if _name_swash_host:
		_name_swash_host.custom_minimum_size = _name_label.get_minimum_size()
	_role_tag_label.text = agent.role
	_tagline_label.text = agent.description


## Reconstruit les 5 lignes de kit (§6 : passif + 3 aptitudes + ultime) pour
## l'agent SÉLECTIONNÉ -- `KitCard.ability_row_v4`, jamais dupliqué ici (voir
## sa docstring pour la mise en page tuile/touche/nom/tag/description).
func _rebuild_kit_column(agent: AgentConfig) -> void:
	for c in _kit_column.get_children():
		_kit_column.remove_child(c)
		c.free()

	if agent.passive:
		# AGT-09 : passif TOUJOURS actif, sans touche -- jamais de `key_label`.
		_kit_column.add_child(KitCard.ability_row_v4(
			AgentDatabase.passive_icon(agent), "", agent.passive.display_name, "PASSIF",
			agent.passive.description))

	for ab in agent.abilities:
		# UX-13 : jamais `ab.slot` brut ("C"/"Q"/"E"/"X") -- le libellé de la
		# VRAIE touche (AZERTY/QWERTY).
		var key_label := KeyLabel.for_action(PlayerInput.action_for_slot(ab.slot))
		var tag := ("ULTIME · %d POINTS" % ab.ult_cost) if ab.is_ultimate else ""
		_kit_column.add_child(KitCard.ability_row_v4(
			AgentDatabase.ability_icon(agent, ab.slot), key_label, ab.display_name, tag,
			ab.description, ab.is_ultimate))


func _refresh_cards() -> void:
	# `_refresh_cards` tourne à CHAQUE `_refresh()` (v4, contre seulement au
	# roster en v2/v3) : `multiplayer.get_unique_id()` sans pair assigné
	# (captures d'écran, la plupart des tests headless) journalise une ERROR
	# bruyante par appel bien qu'il retombe déjà sur 1 (identifiant hors-ligne
	# conventionnel) -- gardé explicitement pour rester silencieux dans ce cas
	# largement plus fréquent désormais, sans changer le résultat.
	var local_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var taken_by: Dictionary = {}  # index d'agent -> nom du coéquipier qui l'a verrouillé.
	for idx in _locally_rejected:
		taken_by[int(idx)] = "coéquipier"
	for pid in _roster:
		if int(pid) == local_id:
			continue
		var p: Dictionary = _roster[pid]
		if bool(p.get("locked", false)):
			taken_by[int(p.get("agent_index", -1))] = String(p.get("name", "Coéquipier"))

	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var selected: bool = i == AgentDatabase.selected_index
		var taken_name: String = String(taken_by.get(i, ""))
		var taken: bool = taken_name != ""

		c.button.button_pressed = selected
		c.button.disabled = taken
		c.taken_lbl.text = ("PRIS · %s" % taken_name) if taken else ""
		c.taken_lbl.visible = taken

		# La couleur-clé de l'agent n'apparaît QUE sur la carte sélectionnée
		# (design.md §9) : le reste garde une teinte neutre (text_dim).
		if c.portrait:
			# `modulate` multiplie l'image (même principe que le tint
			# multiplicatif `albedo_color` de MainMenu.gd sur la vitrine) :
			# blanc = portrait peint inchangé (sélectionné), `text_dim` =
			# désaturé vers le neutre (voisins non sélectionnés).
			c.portrait.modulate = Color.WHITE if selected else Comic.TEXT_DIM
		if c.placeholder:
			c.placeholder.add_theme_color_override("font_color", c.color if selected else Comic.TEXT_DIM)
		c.name_lbl.add_theme_color_override("font_color", Comic.SIGNAL if selected else Comic.paper_dim_color())
		c.plate.selected = selected
		# §9 « risque honnête, conflit de jaune » : la couleur-clé de Vanne
		# (#F2B51D) est elle-même jaune -- la tuile choisie se contoure
		# TOUJOURS en `signal`, jamais dans la couleur de l'agent, pour rester
		# distinguable même quand Vanne est sélectionnée.
		c.plate.border_color = Comic.SIGNAL if selected else Comic.RULE
		c.plate.border_width = Comic.STROKE_SELECT if selected else Comic.STROKE_INK
		# Notes UX-33 : 100 % choisie, 32 % disponible, 62 % déjà prise --
		# canal ALPHA du bouton entier (jamais `portrait.modulate` ci-dessus,
		# qui garde sa teinte RGB historique).
		c.button.modulate.a = OPACITY_SELECTED if selected else (OPACITY_TAKEN if taken else OPACITY_AVAILABLE)

	if taken_by.has(AgentDatabase.selected_index):
		_select_first_available()


## UX-13 (tests/ui/test_key_labels.gd, hors de mon périmètre d'écriture) :
## conserve le format agrégé historique "Nom (TOUCHE) : description" sur
## `_desc_label`, jamais ajouté à l'arbre -- voir la docstring du champ.
func _refresh_desc_label_compat(agent: AgentConfig) -> void:
	if _desc_label == null:
		_desc_label = Label.new()
	var text := "%s — %s\n%s" % [agent.role, agent.agent_name, agent.description]
	if agent.passive:
		text += "\nPassif — %s : %s" % [agent.passive.display_name, agent.passive.description]
	for ab in agent.abilities:
		var key_label := KeyLabel.for_action(PlayerInput.action_for_slot(ab.slot))
		text += "\n%s (%s) : %s" % [ab.display_name, key_label, ab.description]
	_desc_label.text = text


func _process(delta: float) -> void:
	_time_left -= delta
	if _timer_label:
		_timer_label.text = HudFormat.format_timer(_time_left)
	if _time_left <= 0.0:
		_lock_in()


func _lock_in() -> void:
	set_process(false)
	locked.emit()


## `_desc_label` (compatibilité UX-13, voir sa docstring) n'est JAMAIS ajouté
## à l'arbre -- Godot ne le libère donc jamais tout seul en sortie d'arbre
## (seuls les ENFANTS d'un nœud libéré le sont) : libéré ici à la main pour
## ne pas fuir un `Label` orphelin à chaque écran instancié/`auto_free`.
func _exit_tree() -> void:
	if _desc_label:
		_desc_label.free()
		_desc_label = null

# ================================================================
#  UX-11 -- réplication des choix/verrouillages de L'ÉQUIPE. Cet écran ne
#  parle jamais directement au réseau : GameWorld (son parent, quand il
#  existe) écoute `agent_picked`/`locked` et appelle en retour les méthodes
#  publiques ci-dessous depuis ce qu'il reçoit du serveur. Le roster ne
#  contient QUE l'équipe locale (voir GameWorld.agent_picks_roster) : l'équipe
#  adverse n'est jamais visible ici, comme dans Valorant.
# ================================================================

## Nouvel état connu de l'équipe (id de pair -> {agent_index, locked, name}) :
## regrise les cartes verrouillées par un coéquipier et recalcule le bandeau
## de rôles manquants. `_team` non utilisé ici (un seul écran = une seule
## équipe pour ce joueur) mais gardé pour lisibilité côté appelant.
func on_picks_updated(_team: int, roster: Dictionary) -> void:
	_roster = roster
	# Un roster COMPLET supplante tout refus local en attente de confirmation.
	_locally_rejected.clear()
	_refresh_cards()
	_recompute_role_banner()


## Le serveur a refusé notre dernier verrouillage (un coéquipier a verrouillé
## cet agent entre-temps, UX-11 : "deux coéquipiers ne peuvent pas verrouiller
## le même agent") : on ne prétend jamais l'avoir obtenu -- la carte est
## regrisée tout de suite, sans attendre la prochaine diffusion complète du
## roster (`_locally_rejected`, fusionné dans `_refresh_cards`), et la
## sélection locale bascule sur le premier agent encore libre.
func on_pick_rejected(agent_index: int) -> void:
	if agent_index < 0 or agent_index >= _cards.size():
		return
	_locally_rejected[agent_index] = true
	_refresh_cards()
	if AgentDatabase.selected_index == agent_index:
		_select_first_available()


## Bascule la sélection locale sur le premier agent encore libre (jamais
## grisé par un coéquipier) -- appelé quand l'agent survolé/verrouillé
## localement vient d'être pris par quelqu'un d'autre.
func _select_first_available() -> void:
	for i in _cards.size():
		if not (_cards[i].button as Button).disabled:
			_select(i)
			return


func _recompute_role_banner() -> void:
	if _role_banner_label == null:
		return
	var locked_indices: Array = []
	for pid in _roster:
		var p: Dictionary = _roster[pid]
		if bool(p.get("locked", false)):
			locked_indices.append(int(p.get("agent_index", -1)))
	var missing := AgentDatabase.missing_roles(locked_indices)
	if missing.is_empty():
		_role_banner_chip.visible = false
	else:
		_role_banner_chip.visible = true
		_role_banner_label.text = "Il manque : %s" % ", ".join(missing)
