## BuyMenu.gd
## Menu d'achat rapide (touche "buy_menu", B par défaut) — UX-05,
## docs/research/04_ui_ux.md §2.5/§3.3 : grille catégories × armes façon CS2,
## achat en 2 touches (1re = catégorie 1–5, 2e = arme 1–5 dans cette
## catégorie), « R » (action "reload" — réutilisée : le rechargement en jeu
## n'a aucun sens boutique ouverte, et project.godot est hors de la liste de
## fichiers de cette tâche) rachète le loadout de la manche précédente.
## Navigation manette : grille RÉELLE de boutons (focus_mode ALL), le focus
## D-pad/stick suit la résolution géométrique standard de Godot — aucun
## voisin codé en dur.
## - Sans mode de jeu (entraînement) ou mode sans économie (TDM/Hardpoint,
##   Duel/Duo — équipement imposé) : achat libre et gratuit, comme avant, et
##   « R » n'a pas de sens (pas de crédits, pas de manche) : indisponible.
## - Mode à manches avec économie (SnD, voir SnDMode.my_credits/buy_phase) :
##   affiche le solde de crédits et le prix de chaque arme ; une arme trop
##   chère est verrouillée (cadenas + « N cr requis »), une arme déjà
##   possédée porte un tampon « ✓ », une arme juste achetée un « ● »
##   transitoire (achat prédit, en attente de confirmation serveur).
## Revente (titre de la tâche ART-34 précédente) : PAS implémentée ici. Elle
## demanderait une requête réseau de remboursement (nouvelle RPC côté
## Weapon.gd, ex. `request_sell`) : Weapon.gd n'est PAS dans la liste de
## fichiers de cette tâche (scripts/ui/BuyMenu.gd, scripts/ui/ArsenalMenu.gd)
## — voir le rendu de fin de tâche, `blocked_on`.
##
## ART-34 (2026-09-25) — « Achat et Arsenal v3 » : reskin complet contre la
## maquette du §8.6 « Achat / équipement » (docs/STYLE_BIBLE.md) avec le kit
## d'autocollants ART-31 (KitCard/KitSlantBar, scripts/ui/kit/) : colonne
## d'onglets inclinés (catégorie), grille de cartes-armes (silhouette + prix,
## verrouillée avec « N cr requis »), panneau de détail (barres de stats +
## aperçu 3D tournant du modèle réel de l'arme). TOUTE la logique testée
## (grouping/digits/achat/rachat/crédits, tests/ui/test_buy_menu.gd, hors
## périmètre de cette tâche) reste un calque intact sous ce nouvel habillage :
## `_grouped_categories()`, `_resolve_digit()`/`_handle_digit()`,
## `_afford_check()`, `_rebuy_previous_loadout()`, `_owned_ids()`, `_process()`,
## `_try_open()` gardent exactement leur signature/comportement — seule la
## construction visuelle (`_build`) et l'affichage (`_refresh_labels`) sont
## réécrits.
##
## Écart connu avec la maquette (à arbitrer par le lead, `blocked_on`) : le
## §8.6 dessine SIX onglets (1 POING, 2 SMG, 3 FUSILS, 4 POMPE, 5 LOURDE,
## 6 SNIPER — un onglet par WeaponConfig.Category non vide). Le test verrouillé
## `test_grouped_categories_has_five_groups_covering_the_whole_database`
## (tests/ui/test_buy_menu.gd, POSSÉDÉ par UX-35 mais dont l'assertion n'est
## PAS remise en cause par le §6 de UI_DIRECTION_BL3.md — « onglets 1–5 »)
## exige exactement CINQ groupes (Pompe+Lourde fusionnés, Sniper+Mêlée
## fusionnés — `CATEGORY_GROUPS` ci-dessous, hérité de la tâche UX-05). Cette
## tranche garde donc CINQ onglets inclinés (numérotés 1 à 5, même grammaire
## visuelle KitSlantBar que la maquette) plutôt que de casser un test
## verrouillé — voir le rendu de fin de tâche.
##
## UX-35 (2026-09-25) — « UI v4 BL3 » (docs/UI_DIRECTION_BL3.md §6 « Achat /
## arsenal », direction VALIDÉE) : cartes-armes portées à 240×150 (`CARD_SIZE`,
## était 220×140 par défaut de KitCard.DEFAULT_SIZE), onglet ACTIF en fond
## `signal` (jaune, §4.6 « choisi : fond signal ») au lieu du gris `PANEL_HI`
## fixe de la v3 — `_tab_bars`/`_category_grids` gardent leur rôle, seule la
## couleur suit maintenant `_active_category` (voir `_tab_accent`) ; CTA
## « ACHETER » repeint en `signal` (était `BRUSH` rouge, rôle repris par
## `color.ui.signal` pour tout code NEUF v4, tokens.json §7) ; le prix
## « Gratuit » du Pistolet (le seul à coût nul, resources/weapons/pistolet.tres)
## n'apparaît plus QUE sur sa carte (`entry.price_label`) — le panneau de
## détail (`_detail_price`) le laisse vide plutôt que de répéter le mot pour
## la même arme sélectionnée (§6 « "Gratuit" une seule fois »).
##
## GF-23 (2026-09-25) — HUD munitions §2.6 : un achat en arène (TDM/Hardpoint,
## `Inventory.RULE_ARENA`, voir `_is_arena_ammo_rule`) affiche désormais le
## message « Loadout appliqué à la prochaine réapparition » (`_flash_message`,
## réutilisé tel quel) — la boutique en arène choisit le loadout du PROCHAIN
## respawn, jamais l'inventaire courant hors de la fenêtre d'achat gratuite
## (`Weapon.ARENA_BUY_WINDOW`/`arena_buy_allowed`, hors de ce lot de fichiers :
## ce panneau ne lit que `GameMode.ammo_rule`, jamais l'horodatage serveur du
## spawn).
##
## UX-38 (2026-09-25, retour lead §4 « bandeau pinceau rouge à supprimer,
## titre en encre 66 comme OPTIONS ») : `BrushHeader.gd` (bandeau rouge
## « pinceau », hors de la liste de fichiers de cette tâche — LU, jamais
## modifié) est remplacé ici par un simple `Label` v4 (`_title_label`, même
## patron que OptionsMenu.gd::_title_label — `Comic.title_label_v4`,
## capitales italiques papier, 66 px) — plus aucun fond pinceau rouge sur cet
## écran. `_replay_title()` (fondu d'opacité seul, comme MainMenu._fade_in —
## jamais une translation d'offsets : `_title_label` vit dans `wrap`, un
## `VBoxContainer`, voir sa docstring) remplace `BrushHeader.replay()`
## (balayage de gauche à droite, supprimé avec le bandeau lui-même).
extends CanvasLayer

## Pile partagée des overlays modaux (Pause/Achat/fin de match, BUG-U01) :
## voir PauseMenu.gd — mêmes noms de groupe, `Input.mouse_mode` n'est
## recapturé que quand la pile est vide.
const MODAL_GROUP := "ui_modal_stack"
## Groupe où PauseMenu s'enregistre pendant qu'il est affiché : geler la
## touche "buy_menu" tant que Pause est ouvert par-dessus (BUG-U01).
const PAUSE_GROUP := "ui_pause_open"

## Regroupe les 7 valeurs de WeaponConfig.Category en 5 groupes adressables au
## clavier (touches 1–5, façon CS2 : catégorie puis arme). « Lourde » combine
## fusils à pompe et armes lourdes dans UNE catégorie boutique — même choix
## que le "Heavy" de CS2 — pour tenir sur 5 touches ; Mêlée (actuellement
## vide) rejoint Sniper plutôt que de réclamer une 6e touche. NE PAS étendre
## à 6 groupes sans mettre à jour tests/ui/test_buy_menu.gd EN MÊME TEMPS
## (hors périmètre de ce fichier — voir la note d'écart ci-dessus).
const CATEGORY_GROUPS := [
	{"label": "Armes de poing", "cats": [WeaponConfig.Category.SIDEARM]},
	{"label": "SMG", "cats": [WeaponConfig.Category.SMG]},
	{"label": "Fusils", "cats": [WeaponConfig.Category.RIFLE]},
	{"label": "Lourde", "cats": [WeaponConfig.Category.SHOTGUN, WeaponConfig.Category.HEAVY]},
	{"label": "Sniper", "cats": [WeaponConfig.Category.SNIPER, WeaponConfig.Category.MELEE]},
]
## Délai (s) avant qu'une catégorie en attente (1re touche pressée, 2e jamais
## venue) ne s'annule silencieusement — évite un état bloqué en mémoire.
const PENDING_TIMEOUT := 2.5
## Nombre de colonnes de la grille de cartes-armes (§8.6 : 3 cartes par
## rangée sur l'exemple « Achat / équipement »).
const GRID_COLUMNS := 3
## Largeur fixe de la colonne d'onglets et du panneau de détail (design en
## 1920×1080, mis à l'échelle par le stretch canvas_items+expand du projet —
## voir Comic.gd).
const TABS_COLUMN_W := 260.0
const DETAIL_COLUMN_W := 440.0
## UX-35, UI_DIRECTION_BL3.md §6 : « cartes d'armes à coins coupés 240×150 »
## (KitCard.DEFAULT_SIZE reste 220×140, INCHANGÉ — kit partagé hors périmètre).
const CARD_SIZE := Vector2(240.0, 150.0)
## §8.7 : au-delà de ce ratio hauteur/largeur (aspect plus étroit que 16:9,
## ex. 1280×800 Deck), le panneau de détail passe SOUS la grille plutôt qu'à
## côté. 1080p et 720p partagent la même aspect (16:9 ≈ 0.5625) : ce seuil ne
## change donc jamais l'agencement gradé par CHK-32 à CHK-37 (uniquement
## 1080p/720p), juste un confort supplémentaire pour les autres résolutions.
const STACK_ASPECT_THRESHOLD := 0.62

var _panel: Control
var _title_label: Label
var _open: bool = false
var _first_button: Control
## Array[Dictionary] {entries: Array[Dictionary]{button, weapon, digit,
## price_label, pending_dot}} — un élément par catégorie de CATEGORY_GROUPS,
## dans l'ordre de `_grouped_categories()`.
var _categories: Array = []
## Un KitSlantBar par catégorie (colonne de gauche, §8.6 "onglets inclinés").
var _tab_bars: Array = []
## Une GridContainer par catégorie (grille de cartes-armes) — TOUTES existent
## dès `_build()` (boutons focusables réels, test_every_weapon_button_is_
## focusable_for_gamepad_navigation), seule celle de `_active_category` est
## visible (jamais un reparent : une GridContainer masquée reste un enfant
## normal, ni fuite de nœud orphelin ni recalcul de taille erroné — les
## Container de Godot ignorent les enfants invisibles pour leur taille mini).
var _category_grids: Array = []
## Catégorie actuellement affichée dans la grille centrale (indépendant de
## `_pending_category` ci-dessous, qui ne concerne QUE le raccourci clavier
## à 2 touches).
var _active_category: int = 0
var _locked_label: Label
var _mode: Node
var _requested: Dictionary = {}  # weapon_id -> horodatage de la demande (état "●")
## Catégorie choisie (1re touche 1–5), en attente de la 2e (l'arme) ; -1 =
## aucune attente, la prochaine touche 1–5 choisit une catégorie.
var _pending_category: int = -1
var _pending_timeout_left: float = 0.0
## Loadout (ids d'armes, ordre des slots) possédé à la fermeture de la
## DERNIÈRE phase d'achat — « la manche précédente » que « R » rachète. Vide
## tant qu'aucune manche n'a encore été jouée.
var _previous_loadout: Array = []
var _last_buy_phase: bool = false
var _bg: ColorRect

## ---------------------------------------------------------------- Panneau de détail
var _detail_panel: ComicPanel
var _detail_name: Label
var _detail_price: Label
var _detail_bars: Dictionary = {}  # "damage"/"rate"/"range" -> ComicBar
var _detail_mag_label: Label
var _detail_cta: KitSlantBar
var _detail_turntable: WeaponTurntable
var _detail_weapon: WeaponConfig = null
## Agencement réactif (§8.7) : une seule BoxContainer dont on bascule
## `vertical` selon l'aspect courant — jamais un reparent.
var _body_row: BoxContainer

func _ready() -> void:
	layer = 9
	_build()
	_panel.visible = false
	_title_label.visible = false
	var vp := get_viewport()
	if vp:
		vp.size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(Comic.BG.r, Comic.BG.g, Comic.BG.b, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.visible = false
	add_child(bg)
	_bg = bg

	# Overlay large (§8.6 : onglets + grille + détail côte à côte), centré :
	# titre v4 au-dessus du corps (jamais imbriqué dedans, "never nested" —
	# docs/STYLE_BIBLE.md §8.1 règle 3).
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", Comic.SP_2)
	wrap.anchor_left = 0.06; wrap.anchor_right = 0.94
	wrap.anchor_top = 0.08; wrap.anchor_bottom = 0.92
	wrap.offset_left = 0; wrap.offset_right = 0; wrap.offset_top = 0; wrap.offset_bottom = 0
	add_child(wrap)
	_panel = wrap

	# UX-38 : titre v4 SANS bandeau pinceau (remplace `BrushHeader`, rouge) —
	# capitales italiques papier, 66 px, zéro fond (voir la docstring de tête).
	_title_label = Comic.title_label_v4("Achat — Training (gratuit)", Comic.SIZE_66, Comic.paper_color())
	wrap.add_child(_title_label)

	var body_row := BoxContainer.new()
	body_row.vertical = false
	body_row.add_theme_constant_override("separation", Comic.SP_3)
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_child(body_row)
	_body_row = body_row

	_build_tabs_column(body_row)
	_build_grid_column(body_row)
	_build_detail_panel(body_row)

	var groups := _grouped_categories()
	if not groups.is_empty() and not (groups[_active_category].weapons as Array).is_empty():
		_show_detail((groups[_active_category].weapons as Array)[0])

	_locked_label = Comic.label("Achat verrouillé — manche en cours", Comic.SIZE_BODY, Comic.TEXT, Comic.FONT_LABEL)
	Comic.anchor(_locked_label, Control.PRESET_CENTER_BOTTOM)
	_locked_label.offset_top = -90
	_locked_label.offset_bottom = -60
	_locked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_locked_label.visible = false
	add_child(_locked_label)

## Colonne de gauche : un KitSlantBar par catégorie (§8.2 : les onglets
## portent l'inclinaison à 12°, jamais un radius — famille "autocollant").
func _build_tabs_column(parent: Container) -> void:
	var tabs_col := VBoxContainer.new()
	tabs_col.add_theme_constant_override("separation", Comic.SP_2)
	tabs_col.custom_minimum_size = Vector2(TABS_COLUMN_W, 0)
	parent.add_child(tabs_col)

	var groups := _grouped_categories()
	for i in groups.size():
		var g: Dictionary = groups[i]
		var tab := KitSlantBar.new()
		tabs_col.add_child(tab)
		tab.bar_text = "%d — %s" % [i + 1, g.label]
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.accent_color = _tab_accent(i == _active_category)
		tab.selected = i == _active_category
		tab.pressed.connect(_on_tab_pressed.bind(i))
		_tab_bars.append(tab)

## Colonne centrale : une grille de cartes-armes par catégorie (§8.6 : cartes-
## autocollants avec silhouette et prix), plus le pied de page (Racheter/
## Fermer). Construit les entrées de TOUTES les catégories dès l'ouverture —
## voir la doc de `_category_grids`.
func _build_grid_column(parent: Container) -> void:
	var grid_col := VBoxContainer.new()
	grid_col.add_theme_constant_override("separation", Comic.SP_3)
	grid_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid_col)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	grid_col.add_child(scroll)

	var grid_stack := VBoxContainer.new()
	grid_stack.add_theme_constant_override("separation", 0)
	grid_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_stack)

	var groups := _grouped_categories()
	for i in groups.size():
		var g: Dictionary = groups[i]
		var grid := GridContainer.new()
		grid_stack.add_child(grid)
		grid.columns = GRID_COLUMNS
		grid.add_theme_constant_override("h_separation", Comic.SP_3)
		grid.add_theme_constant_override("v_separation", Comic.SP_3)
		grid.visible = i == _active_category
		_category_grids.append(grid)

		var entries: Array = []
		var weapons: Array = g.weapons
		for wi in weapons.size():
			var entry := _weapon_card(wi, weapons[wi])
			grid.add_child(entry.button)
			# UX-35 : `KitCard._ready()` réassigne `custom_minimum_size` à
			# `DEFAULT_SIZE` (220×140) à l'entrée dans l'arbre — la taille
			# 240×150 (§6) doit donc être reposée APRÈS `add_child` (`_ready`
			# tourne SYNCHRONE dedans), jamais avant, sous peine d'être écrasée.
			entry.button.custom_minimum_size = CARD_SIZE
			entries.append(entry)
		_categories.append({"entries": entries})
		if _first_button == null and not entries.is_empty():
			_first_button = entries[0].button

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", Comic.SP_3)
	grid_col.add_child(footer)

	var rebuy := Button.new()
	footer.add_child(rebuy)
	rebuy.text = "Racheter (R)"
	rebuy.custom_minimum_size = Vector2(0, Comic.MIN_TAP_TARGET_PX)
	rebuy.focus_mode = Control.FOCUS_ALL
	rebuy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rebuy.pressed.connect(_rebuy_previous_loadout)

	var close := Button.new()
	footer.add_child(close)
	close.text = "Fermer (B)"
	close.custom_minimum_size = Vector2(0, Comic.MIN_TAP_TARGET_PX)
	close.focus_mode = Control.FOCUS_ALL
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(_close)

## Carte-arme (§8.6 : « silhouette », prix, cadenas + « N cr requis » quand
## hors de prix, tampon « ✓ » quand possédée) — un KitCard réel (BaseButton),
## `entry.button` reste le nom attendu par tests/ui/test_buy_menu.gd même si
## ce n'est plus un `Button` natif mais un composant du kit ART-31.
func _weapon_card(digit_index: int, w: WeaponConfig) -> Dictionary:
	var card := KitCard.new()
	# UX-35 : la taille 240×150 (§6) est reposée par l'appelant APRÈS
	# `add_child` (`_build_grid_column`) — `KitCard._ready()` réassigne
	# `custom_minimum_size` à `DEFAULT_SIZE` à l'entrée dans l'arbre, ce qui
	# écraserait une valeur posée ICI, avant l'ajout.
	card.card_title = w.weapon_name
	card.accent_color = Comic.PANEL_HI
	card.pressed.connect(_buy.bind(w))
	card.mouse_entered.connect(_show_detail.bind(w))
	card.focus_entered.connect(_show_detail.bind(w))

	var silhouette := WeaponSilhouette.new()
	card.add_child(silhouette)
	silhouette.category = w.category
	silhouette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	silhouette.offset_bottom = -(Comic.SIZE_SUBTITLE + Comic.SP_2)

	var digit_badge := Comic.label(str(digit_index + 1), Comic.SIZE_FLOOR, Comic.TEXT_DIM, Comic.FONT_NUMBER)
	card.add_child(digit_badge)
	Comic.anchor(digit_badge, Control.PRESET_TOP_LEFT)
	digit_badge.offset_left = Comic.SP_1
	digit_badge.offset_top = Comic.SP_1
	digit_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var price := Comic.number_label("", Comic.SIZE_BODY, Comic.TEXT)
	card.add_child(price)
	Comic.anchor(price, Control.PRESET_TOP_RIGHT)
	price.offset_left = -140
	price.offset_top = Comic.SP_1
	price.offset_right = -Comic.SP_1
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# « ● » transitoire (achat prédit, en attente de confirmation serveur) —
	# distinct du tampon « ✓ » natif de KitCard (`selected`, qui marque
	# « possédée »), voir `_refresh_labels`.
	var pending_dot := Comic.label("●", Comic.SIZE_SUBTITLE, Comic.BULLET, Comic.FONT_NUMBER)
	card.add_child(pending_dot)
	Comic.anchor(pending_dot, Control.PRESET_TOP_RIGHT)
	pending_dot.offset_left = -34
	pending_dot.offset_top = Comic.SP_1
	pending_dot.visible = false
	pending_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return {"button": card, "weapon": w, "digit": digit_index + 1, "price_label": price, "pending_dot": pending_dot}

## Panneau de détail (§8.6 : « détail avec barres de stats et rotation de
## l'arme ») : nom + prix, aperçu 3D tournant du modèle réel, barres Dégâts/
## Cadence/Portée, chargeur, CTA ACHETER (miroir de l'état de la carte
## survolée/focus, voir `_show_detail`/`_refresh_detail_panel`).
func _build_detail_panel(parent: Container) -> void:
	var detail := ComicPanel.new()
	parent.add_child(detail)
	detail.bg_color = Comic.PANEL
	detail.border_width = Comic.RULE_W
	detail.content_margin = Comic.SP_3
	detail.custom_minimum_size = Vector2(DETAIL_COLUMN_W, 0)
	_detail_panel = detail

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Comic.SP_2)
	detail.body.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	_detail_name = Comic.title_label("", Comic.SIZE_LABEL, Comic.TEXT)
	_detail_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_name.clip_text = true
	head.add_child(_detail_name)
	_detail_price = Comic.number_label("", Comic.SIZE_SUBTITLE, Comic.ALLY)
	head.add_child(_detail_price)

	var preview_wrap := Control.new()
	preview_wrap.custom_minimum_size = Vector2(0, 260)
	col.add_child(preview_wrap)
	_detail_turntable = WeaponTurntable.new()
	preview_wrap.add_child(_detail_turntable)
	_detail_turntable.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_detail_bars = {
		"damage": _detail_stat_row(col, "Dégâts"),
		"rate": _detail_stat_row(col, "Cadence"),
		"range": _detail_stat_row(col, "Portée"),
	}
	_detail_mag_label = Comic.label("", Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL)
	col.add_child(_detail_mag_label)

	_detail_cta = KitSlantBar.new()
	col.add_child(_detail_cta)
	_detail_cta.bar_text = "Acheter (Entrée/A)"
	_detail_cta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# UX-35, §6 « CTA "ACHETER" jaune » : `color.ui.signal` remplace le rôle
	# « marque » de `BRUSH` (rouge, v3) pour tout code NEUF v4 (tokens.json §7).
	_detail_cta.accent_color = Comic.signal_color()
	_detail_cta.pressed.connect(_buy_detail)

func _detail_stat_row(col: VBoxContainer, label_text: String) -> ComicBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Comic.SP_2)
	col.add_child(row)
	var lbl := Comic.label(label_text, Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL)
	lbl.custom_minimum_size = Vector2(110, 0)
	row.add_child(lbl)
	var bar := ComicBar.new()
	row.add_child(bar)
	# UX-35, §6 « 3 barres de stats ... paper, plus de bleu » — `fill_color`
	# est un `@export` PUBLIC de ComicBar.gd (hors de la liste de fichiers de
	# cette tâche, non modifié) : posé ici plutôt que d'y toucher.
	bar.fill_color = Comic.paper_color()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.ticks = 4
	return bar

## §8.7 : bascule le panneau de détail sous la grille plutôt qu'à côté sur
## une aspect plus étroite que 16:9 (voir `STACK_ASPECT_THRESHOLD`) — un
## simple flip de `BoxContainer.vertical`, jamais un reparent (aucun nœud ne
## change de parent, aucun risque de perdre le focus courant).
func _apply_responsive_layout() -> void:
	if _body_row == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vsize := vp.get_visible_rect().size
	if vsize.x <= 0.0:
		return
	_body_row.vertical = (vsize.y / vsize.x) > STACK_ASPECT_THRESHOLD

## Regroupe WeaponDatabase.all() selon CATEGORY_GROUPS, dans l'ordre du
## catalogue ; une catégorie sans arme n'apparaît pas (jamais le cas
## aujourd'hui, mais robuste si le catalogue change). Pur — aucun état
## d'instance, aucun nœud requis : testable directement.
static func _grouped_categories() -> Array:
	var groups: Array = []
	for g in CATEGORY_GROUPS:
		var weapons: Array = []
		for w in WeaponDatabase.all():
			if (g.cats as Array).has(w.category):
				weapons.append(w)
		if not weapons.is_empty():
			groups.append({"label": g.label, "weapons": weapons})
	return groups

func _process(delta: float) -> void:
	if _mode == null or not is_instance_valid(_mode):
		_mode = get_tree().get_first_node_in_group("game_mode")
	_track_previous_loadout()
	if not _open:
		return
	if _mode and "buy_phase" in _mode and not bool(_mode.buy_phase):
		_close()
		return
	if _pending_category != -1:
		_pending_timeout_left -= delta
		if _pending_timeout_left <= 0.0:
			_pending_category = -1
	_refresh_labels()

## Repère la fermeture de la phase d'achat (buy_phase vrai -> faux, la manche
## commence) pour mémoriser le loadout ALORS possédé : c'est lui que « R »
## rachètera à la PROCHAINE ouverture de la boutique, y compris si le joueur
## meurt entre-temps et se retrouve réduit au pistolet (SnDMode.
## _after_round_respawn) — sans cette mémorisation l'info serait déjà perdue.
## Tourne en continu (avant le `if not _open: return` de `_process`) : la
## phase d'achat change que la boutique soit ouverte ou non à cet instant.
func _track_previous_loadout() -> void:
	if _mode == null or not ("buy_phase" in _mode):
		return
	var phase := bool(_mode.buy_phase)
	if _last_buy_phase and not phase:
		_previous_loadout = _owned_ids()
	_last_buy_phase = phase

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("buy_menu"):
		# BUG-U01 : Pause affiché par-dessus gèle l'Achat, B ne doit ni
		# l'ouvrir ni le fermer tant que Pause n'a pas été refermé.
		if not get_tree().get_nodes_in_group(PAUSE_GROUP).is_empty():
			return
		if _open:
			_close()
		else:
			_try_open()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		# BUG-U01 : "pause" et "ui_cancel" partagent la même touche (Échap,
		# project.godot). BuyMenu est ajouté après PauseMenu dans la scène et
		# reçoit donc l'_unhandled_input en premier ; sans ce garde, Échap
		# fermait Achat au lieu de laisser l'événement remonter à Pause
		# (résultat : Achat se ferme à l'insu du joueur, Pause reste affiché).
		if not get_tree().get_nodes_in_group(PAUSE_GROUP).is_empty():
			return
		_close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("reload"):
		# « R » : racheter le loadout de la manche précédente (action
		# "reload" réutilisée — inerte de toute façon boutique ouverte,
		# PlayerInput.gd coupe les entrées de jeu tant que la souris est
		# visible ; voir le commentaire d'en-tête). Gamepad : même action,
		# donc même bouton que la touche de rechargement en jeu.
		_rebuy_previous_loadout()
		get_viewport().set_input_as_handled()
		return
	# Achat en 2 touches façon CS2 (1–5 catégorie, puis 1–5 arme) — lues en
	# PHYSICAL_KEYCODE brut (aucune action dédiée dans project.godot, hors
	# périmètre de cette tâche) ; jamais un echo (répétition auto au maintien).
	if event is InputEventKey and event.pressed and not event.echo:
		var digit := _digit_from_keycode(event.physical_keycode)
		if digit != -1:
			_handle_digit(digit)
			get_viewport().set_input_as_handled()

## Touches 1–5 (rangée du haut) -> chiffre 1–5, -1 sinon. Statique, pur.
static func _digit_from_keycode(code: int) -> int:
	if code >= KEY_1 and code <= KEY_5:
		return code - KEY_1 + 1
	return -1

## Résout un chiffre (1–5) selon l'attente courante — pur à l'état
## `_pending_category` près, sans effet de bord, directement testable. CS2 :
## 1re touche = catégorie, 2e = arme dans cette catégorie ; un chiffre hors
## plage relance comme un choix de catégorie plutôt que de bloquer
## silencieusement l'attente en cours.
func _resolve_digit(digit: int) -> Dictionary:
	var groups := _grouped_categories()
	var idx := digit - 1
	if _pending_category == -1 or _pending_category >= groups.size():
		if idx >= groups.size():
			return {"action": "none"}
		return {"action": "select_category", "category": idx}
	var weapons: Array = groups[_pending_category].weapons
	if idx < weapons.size():
		return {"action": "buy", "weapon": weapons[idx]}
	if idx >= groups.size():
		return {"action": "cancel"}
	return {"action": "select_category", "category": idx}

func _handle_digit(digit: int) -> void:
	var res := _resolve_digit(digit)
	match res.get("action", "none"):
		"select_category":
			_pending_category = res.category
			_pending_timeout_left = PENDING_TIMEOUT
			# La grille affichée suit le raccourci clavier (WYSIWYG) : appuyer
			# sur « 3 » montre la 3e catégorie AVANT le chiffre d'arme suivant.
			_select_category(res.category)
		"buy":
			_buy(res.weapon)
		"cancel":
			_pending_category = -1
	_refresh_labels()

## Onglet cliqué (souris/manette) : bascule la grille affichée et efface
## toute attente de raccourci clavier en cours (la souris n'utilise jamais le
## mécanisme "2e chiffre").
func _on_tab_pressed(i: int) -> void:
	_pending_category = -1
	_select_category(i)

## UX-35, §4.6 « choisi : fond signal » — jaune pour l'onglet ACTIF, `plate_hi`
## (gris chaud, repos/survol) pour les autres. Utilisé par la construction
## initiale (`_build_tabs_column`) ET chaque changement d'onglet ci-dessous.
static func _tab_accent(active: bool) -> Color:
	return Comic.signal_color() if active else Comic.plate_hi_color()

func _select_category(i: int) -> void:
	if i < 0 or i >= _category_grids.size():
		return
	_active_category = i
	for gi in _category_grids.size():
		(_category_grids[gi] as GridContainer).visible = gi == i
	for ti in _tab_bars.size():
		var tab: KitSlantBar = _tab_bars[ti]
		tab.selected = ti == i
		tab.accent_color = _tab_accent(ti == i)
	var entries: Array = (_categories[i] as Dictionary).entries
	if not entries.is_empty():
		_show_detail((entries[0] as Dictionary).weapon)

## Ouverture forcée pour les captures d'écran (tests/ui/capture_shots.gd) —
## contourne la vérification de phase d'achat, jamais appelé en jeu normal.
func debug_force_open() -> void:
	_open = true
	_panel.visible = true
	_title_label.visible = true
	_replay_title()
	_bg.visible = true
	add_to_group(MODAL_GROUP)
	_refresh_labels()

func _try_open() -> void:
	if _mode and "buy_phase" in _mode and not bool(_mode.buy_phase):
		_flash_locked()
		return
	_open = true
	_pending_category = -1
	_panel.visible = true
	_title_label.visible = true
	_replay_title()
	_bg.visible = true
	add_to_group(MODAL_GROUP)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_labels()
	if _first_button:
		_first_button.grab_focus()

## Réapparition du titre (UX-38, remplace `BrushHeader.replay()`, un balayage
## de gauche à droite maintenant supprimé avec le bandeau lui-même) — fondu
## d'opacité seul, comme `MainMenu._fade_in` : `_title_label` vit dans `wrap`
## (un `VBoxContainer`, voir sa docstring de construction), qui réattribue la
## position/taille de ses enfants à chaque re-tri de mise en page (déclenché
## par `visible = true` juste avant) — un `Tween` qui animerait `offset_top`/
## `offset_bottom` partirait donc de valeurs déjà PÉRIMÉES. `modulate:a` seul
## ne touche ni position ni taille : sûr sur un enfant de `Container`.
func _replay_title() -> void:
	_title_label.modulate.a = 0.0
	var tw := _title_label.create_tween()
	tw.tween_property(_title_label, "modulate:a", 1.0, Comic.DUR_REDUCED_FADE if Comic.reduced_motion() else Comic.DUR_REVEAL)

func _flash_message(text: String, color: Color = Comic.TEXT) -> void:
	_locked_label.text = text
	_locked_label.add_theme_color_override("font_color", color)
	_locked_label.visible = true
	var tw := _locked_label.create_tween()
	tw.tween_interval(1.5)
	tw.tween_callback(_locked_label.hide)

func _flash_locked() -> void:
	_flash_message("Achat verrouillé — manche en cours", Comic.TEXT)

func _close() -> void:
	_open = false
	_pending_category = -1
	_panel.visible = false
	_title_label.visible = false
	_bg.visible = false
	remove_from_group(MODAL_GROUP)
	if get_tree().get_nodes_in_group(MODAL_GROUP).is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _buy(w: WeaponConfig) -> void:
	_pending_category = -1
	var weapon := _local_weapon()
	if weapon:
		var id := WeaponDatabase.id_of(w)
		weapon.buy(id)
		_requested[id] = Time.get_ticks_msec() / 1000.0
		_play_ui_sfx("ui_buy")
		if _is_arena_ammo_rule():
			# §2.6 : « Boutique en arène : elle choisit le loadout du
			# prochain respawn. » — persiste un instant après `_close()`
			# ci-dessous (`_locked_label` n'est pas un enfant de `_panel`).
			_flash_message("Loadout appliqué à la prochaine réapparition", Comic.TEXT_DIM)
	_close()

## Vrai en arène (TDM/Hardpoint, `Inventory.RULE_ARENA`) — sert UNIQUEMENT au
## message « s'applique à la prochaine réapparition » ci-dessus (§2.6). En
## round (SnD, sa propre `buy_phase`) l'achat s'applique tout de suite pour
## la manche ; en mode sans économie (entraînement, aucun nœud "game_mode")
## il n'y a ni respawn scénarisé ni message à afficher. Même lecture que
## `Weapon._ammo_rule()` (hors de ce lot de fichiers) sur le même groupe
## "game_mode" — aucune source de vérité dupliquée, juste la même valeur lue
## depuis l'UI.
func _is_arena_ammo_rule() -> bool:
	if _mode == null or not is_instance_valid(_mode) or not ("ammo_rule" in _mode):
		return false
	return String(_mode.ammo_rule) == Inventory.RULE_ARENA

## CTA « ACHETER » du panneau de détail — achète l'arme actuellement détaillée.
func _buy_detail() -> void:
	if _detail_weapon:
		_buy(_detail_weapon)

## « R » : rachète en un coup les armes MANQUANTES du loadout de la manche
## précédente (CS2 "autobuy", docs/research/04_ui_ux.md §2.5/§3.3) — jamais
## celles déjà possédées (idempotent, et surtout évite qu'un rachat à 2 armes
## sur un inventaire à 2 emplacements pleins n'en remplace une déjà bonne,
## Inventory.give()/replace_current ne visant que l'emplacement COURANT).
## Les crédits ne sont vérifiés QUE pour ce qui reste réellement à acheter :
## un joueur qui a déjà tout ne doit jamais se voir refuser faute de crédits
## pour un total qu'il ne paie plus.
func _rebuy_previous_loadout() -> void:
	if not _open:
		return
	if _previous_loadout.is_empty():
		_flash_message("⚠ Aucun loadout de manche précédente")
		return
	var owned := _owned_ids()
	var missing: Array = []
	for id in _previous_loadout:
		if not owned.has(id):
			missing.append(id)
	if missing.is_empty():
		_flash_message("Loadout déjà possédé", Comic.TEXT_DIM)
		return
	var economy := _has_economy()
	var check := _afford_check(missing, economy, int(_mode.my_credits) if economy else -1)
	if not check.ok:
		_flash_message("⚠ Crédits insuffisants — manque %s" % HudFormat.format_credits(check.missing))
		return
	for id in missing:
		var w := WeaponDatabase.get_by_id(id)
		if w:
			_buy(w)

## Le loadout `ids` (ids d'armes) est-il abordable avec `credits` crédits ?
## Pur (aucun état d'instance) : testable seul. Sans économie (entraînement /
## mode imposé), toujours abordable — il n'y a pas de crédits à vérifier.
static func _afford_check(ids: Array, economy: bool, credits: int) -> Dictionary:
	if not economy:
		return {"ok": true, "missing": 0, "total": 0}
	var total := 0
	for id in ids:
		var w := WeaponDatabase.get_by_id(id)
		if w:
			total += w.cost
	var missing := maxi(0, total - credits)
	return {"ok": missing == 0, "missing": missing, "total": total}

func _play_ui_sfx(name: String) -> void:
	var sfx := get_tree().root.get_node_or_null("Sfx") if get_tree() else null
	if sfx and sfx.has_method("play_ui"):
		sfx.play_ui(name)

func _local_weapon() -> Weapon:
	var arr := get_tree().get_nodes_in_group("local_player")
	if arr.is_empty():
		return null
	return arr[0].get_node_or_null("Weapon")

func _has_economy() -> bool:
	return _mode != null and is_instance_valid(_mode) and "my_credits" in _mode

func _owned_ids() -> Array:
	var weapon := _local_weapon()
	if weapon == null:
		return []
	var ids: Array = []
	for w in weapon.weapons:
		if w:
			ids.append(WeaponDatabase.id_of(w))
	return ids

func _refresh_labels() -> void:
	var economy := _has_economy()
	var credits: int = int(_mode.my_credits) if economy else -1
	# `.to_upper()` : `Comic.title_label_v4()` uppercase à la construction (voir
	# `_build()`), mais un `Label` nu ne le refait pas de lui-même à chaque
	# `.text =` — répété ici pour ne jamais retomber en casse mixte après un
	# rafraîchissement (même comportement que `BrushHeader.title`, dont le
	# setter uppercase à CHAQUE affectation, jamais seulement à la construction).
	_title_label.text = (("Achat — %s" % HudFormat.format_credits(credits)) if economy else "Achat — Training (gratuit)").to_upper()
	var owned := _owned_ids()
	var now := Time.get_ticks_msec() / 1000.0
	for cat_index in _categories.size():
		var cat: Dictionary = _categories[cat_index]
		var tab: KitSlantBar = _tab_bars[cat_index]
		tab.selected = cat_index == _active_category
		tab.accent_color = _tab_accent(cat_index == _active_category)
		for entry in (cat.entries as Array):
			var card: KitCard = entry.button
			var w: WeaponConfig = entry.weapon
			var id: int = WeaponDatabase.id_of(w)
			var affordable := not economy or w.cost <= credits
			var is_owned := owned.has(id)
			var requested := _requested.has(id) and (now - float(_requested[id])) < 0.6

			(entry.price_label as Label).text = "Gratuit" if w.cost <= 0 else "%d cr" % w.cost
			(entry.pending_dot as Label).visible = requested
			card.selected = is_owned and not requested
			if affordable:
				if card.disabled:
					card.disabled = false
					card.disabled_reason = ""
					card._refresh()
			else:
				card.set_disabled_with_reason("%d cr requis" % (w.cost - credits))
	_refresh_detail_panel()

## Change l'arme affichée dans le panneau de détail (survol/focus d'une carte,
## clic d'onglet) : stats, aperçu 3D tournant, état du CTA.
func _show_detail(w: WeaponConfig) -> void:
	if w == null or _detail_name == null:
		return
	_detail_weapon = w
	_detail_name.text = w.weapon_name
	# UX-35, §6 « "Gratuit" une seule fois » : la carte (`entry.price_label`)
	# porte déjà « Gratuit » pour l'unique arme à coût nul (Pistolet) — le
	# panneau de détail ne répète plus le mot pour la même arme sélectionnée.
	_detail_price.text = "" if w.cost <= 0 else "%d cr" % w.cost

	var max_dmg := 1.0
	var max_rate := 1.0
	var max_range := 1.0
	for c in WeaponDatabase.all():
		max_dmg = maxf(max_dmg, c.damage)
		max_rate = maxf(max_rate, c.fire_rate)
		max_range = maxf(max_range, c.max_range)
	(_detail_bars.damage as ComicBar).value = w.damage / max_dmg
	(_detail_bars.rate as ComicBar).value = w.fire_rate / max_rate
	(_detail_bars.range as ComicBar).value = w.max_range / max_range
	_detail_mag_label.text = "Chargeur %d / %d" % [w.mag_size, w.reserve_ammo]

	_detail_turntable.show_weapon(WeaponDatabase.id_of(w), w.category)
	_refresh_detail_panel()

## Miroir de l'état d'achat (possédée / abordable / verrouillée) sur le CTA
## du panneau de détail — appelé après chaque `_show_detail` ET à chaque
## `_refresh_labels` (les crédits/l'inventaire changent pendant que le
## panneau reste ouvert sur la même arme).
func _refresh_detail_panel() -> void:
	if _detail_weapon == null or _detail_cta == null:
		return
	var economy := _has_economy()
	var credits: int = int(_mode.my_credits) if economy else -1
	var owned := _owned_ids().has(WeaponDatabase.id_of(_detail_weapon))
	var affordable := not economy or _detail_weapon.cost <= credits
	if owned:
		_detail_cta.selected = true
		if _detail_cta.disabled:
			_detail_cta.disabled = false
			_detail_cta.disabled_reason = ""
			_detail_cta._refresh()
	elif not affordable:
		_detail_cta.selected = false
		_detail_cta.set_disabled_with_reason("%d cr requis" % (_detail_weapon.cost - credits))
	else:
		_detail_cta.selected = false
		if _detail_cta.disabled:
			_detail_cta.disabled = false
			_detail_cta.disabled_reason = ""
			_detail_cta._refresh()


## ==========================================================================
##  Silhouette d'arme procédurale (§8.6 « silhouette » des cartes) — même
##  esprit que MainMenu.MapVignette (STYLE_BIBLE v3 : un aplat déterministe
##  tant qu'aucun rendu dédié n'existe, JAMAIS un chiffre/texte inventé) :
##  une forme d'archétype par catégorie (poing/SMG/fusil/pompe-lourde/
##  sniper), en encre plate, partagée par toutes les armes de cette
##  catégorie — exactement ce que montre la maquette (3 cartes « FUSILS »
##  affichant la même silhouette générique). Réutilisée telle quelle par
##  ArsenalMenu.gd via `preload("res://scripts/ui/BuyMenu.gd").WeaponSilhouette`.
## ==========================================================================
class WeaponSilhouette extends Control:
	var category: int = WeaponConfig.Category.RIFLE:
		set(v):
			category = v
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var col := Comic.HARD_SHADOW_COLOR
		var s: float = minf(size.x, size.y)
		var ox := size.x * 0.5
		var oy := size.y * 0.52
		match category:
			WeaponConfig.Category.SIDEARM:
				draw_rect(Rect2(ox - s * 0.22, oy - s * 0.06, s * 0.34, s * 0.14), col)
				draw_rect(Rect2(ox - s * 0.05, oy + s * 0.02, s * 0.12, s * 0.24), col)
			WeaponConfig.Category.SMG:
				draw_rect(Rect2(ox - s * 0.30, oy - s * 0.06, s * 0.50, s * 0.12), col)
				draw_rect(Rect2(ox + s * 0.16, oy - s * 0.03, s * 0.14, s * 0.06), col)
				draw_rect(Rect2(ox - s * 0.10, oy + s * 0.02, s * 0.08, s * 0.20), col)
				draw_rect(Rect2(ox - s * 0.02, oy + s * 0.06, s * 0.07, s * 0.22), col)
			WeaponConfig.Category.SHOTGUN:
				draw_rect(Rect2(ox - s * 0.34, oy - s * 0.05, s * 0.60, s * 0.11), col)
				draw_rect(Rect2(ox + s * 0.24, oy - s * 0.045, s * 0.18, s * 0.09), col)
				draw_rect(Rect2(ox - s * 0.44, oy - s * 0.03, s * 0.12, s * 0.09), col)
			WeaponConfig.Category.HEAVY:
				draw_rect(Rect2(ox - s * 0.36, oy - s * 0.08, s * 0.62, s * 0.16), col)
				draw_rect(Rect2(ox + s * 0.24, oy - s * 0.05, s * 0.16, s * 0.10), col)
				draw_circle(Vector2(ox - s * 0.05, oy + s * 0.18), s * 0.12, col)
			WeaponConfig.Category.SNIPER:
				draw_rect(Rect2(ox - s * 0.46, oy - s * 0.04, s * 0.86, s * 0.08), col)
				draw_rect(Rect2(ox - s * 0.06, oy - s * 0.16, s * 0.20, s * 0.08), col)
				draw_rect(Rect2(ox - s * 0.48, oy - s * 0.02, s * 0.10, s * 0.12), col)
			_:  # RIFLE et MELEE (catégorie sans arme aujourd'hui) : archétype fusil.
				draw_rect(Rect2(ox - s * 0.36, oy - s * 0.05, s * 0.58, s * 0.10), col)
				draw_rect(Rect2(ox + s * 0.20, oy - s * 0.03, s * 0.18, s * 0.06), col)
				draw_rect(Rect2(ox - s * 0.46, oy - s * 0.03, s * 0.12, s * 0.10), col)
				draw_rect(Rect2(ox - s * 0.06, oy + s * 0.02, s * 0.07, s * 0.22), col)


## ==========================================================================
##  Aperçu 3D tournant du modèle RÉEL de l'arme (§8.6 panneau de détail :
##  « vue de profil 3D, tourne ») — un SubViewport avec son propre World3D
##  (`own_world_3d`, jamais le monde de la partie en cours), le modèle chargé
##  via `Weapon.model_path_for()` (même convention que ViewModel.gd/
##  ThirdPersonWeapon.gd) et repeint avec `Cartoon.painted_texture_prop()`
##  (même matériau encré que le reste du jeu, texture albédo importée
##  extraite via `Cartoon.texture_from_imported_material()`). Cadrage
##  automatique par AABB (les armes n'ont pas toutes le même pivot/gabarit —
##  voir WeaponConfig, aucune donnée de cadrage FP ici). Repli honnête (jamais
##  un vide silencieux) : sans modèle chargeable, affiche la silhouette
##  procédurale de la catégorie à la place. Mouvement réduit
##  (`Comic.reduced_motion()`) : la rotation s'arrête, jamais interdite par
##  défaut (le jeton "reduced_motion.forbid" vise l'échelle/la position/la
##  rotation DES CONTRÔLES D'INTERFACE ; ce tour lent d'objet 3D est la
##  fonction même de l'aperçu, comme l'arme au sol qui tourne à 30°/s en jeu,
##  §5.4 — mais on la fige quand même par cohérence stricte avec la règle
##  "aucune rotation" du jeton, plutôt que d'ouvrir une exception non écrite).
## ==========================================================================
class WeaponTurntable extends Control:
	## Vitesse de rotation (rad/s) — un tour complet toutes les ~12 s, assez
	## lent pour lire chaque face sans donner le tournis dans un menu.
	const ROTATE_SPEED := 0.52

	var _svc: SubViewportContainer
	var _viewport: SubViewport
	var _pivot: Node3D
	var _cam: Camera3D
	var _fallback: WeaponSilhouette
	var _loaded: Node3D = null
	var _current_path := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

		_svc = SubViewportContainer.new()
		add_child(_svc)
		_svc.stretch = true
		_svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE

		_viewport = SubViewport.new()
		_svc.add_child(_viewport)
		_viewport.own_world_3d = true
		# Taille pilotée par `_svc.stretch` (ci-dessus) — poser `size` ici
		# déclenche un avertissement moteur inutile (« Can't change the size
		# of a SubViewport with a SubViewportContainer parent that has
		# stretch enabled ») et serait de toute façon écrasé au premier tri.
		_viewport.transparent_bg = false
		# Ne rend que quand ce contrôle est réellement visible à l'écran
		# (menu ouvert, onglet actif) — jamais en tâche de fond une fois la
		# boutique fermée (`_panel.visible = false` en cascade jusqu'ici).
		_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE

		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Comic.PANEL_HI
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Comic.TEXT_DIM
		env.ambient_light_energy = 0.7
		var world_env := WorldEnvironment.new()
		world_env.environment = env
		_viewport.add_child(world_env)

		var key := DirectionalLight3D.new()
		_viewport.add_child(key)
		key.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
		var fill := DirectionalLight3D.new()
		_viewport.add_child(fill)
		fill.rotation_degrees = Vector3(-15.0, -150.0, 0.0)
		fill.light_energy = 0.35

		_pivot = Node3D.new()
		_viewport.add_child(_pivot)
		_cam = Camera3D.new()
		_viewport.add_child(_cam)
		_cam.current = true

		_fallback = WeaponSilhouette.new()
		add_child(_fallback)
		_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_fallback.visible = false

		set_process(true)

	## Charge (ou recharge, si `id` change) le modèle réel de l'arme dans le
	## tourniquet ; `category` alimente le repli procédural si le modèle est
	## introuvable. No-op si `id` est déjà celui affiché (évite de recharger
	## le .glb à chaque frame pendant que la souris survole la même carte).
	func show_weapon(id: int, category: int) -> void:
		_fallback.category = category
		var path := Weapon.model_path_for(id)
		if path == _current_path:
			return
		_current_path = path
		if _loaded:
			_loaded.queue_free()
			_loaded = null
		if path == "" or not ResourceLoader.exists(path):
			_show_fallback()
			return
		var scene := load(path) as PackedScene
		var inst: Node = scene.instantiate() if scene else null
		if inst == null or not (inst is Node3D):
			_show_fallback()
			return
		_svc.visible = true
		_fallback.visible = false
		_loaded = inst as Node3D
		_pivot.add_child(_loaded)
		_pivot.rotation = Vector3.ZERO
		_paint(_loaded)
		_frame_camera()

	func _show_fallback() -> void:
		_svc.visible = false
		_fallback.visible = true
		_fallback.queue_redraw()

	## Repeint chaque surface avec le matériau encré du jeu (même fabrique que
	## ViewModel.gd/ThirdPersonWeapon.gd) à partir de la texture albédo déjà
	## importée — jamais le gris PBR par défaut de l'import glTF.
	func _paint(model: Node3D) -> void:
		for mesh in _mesh_instances(model):
			if mesh.mesh == null:
				continue
			for i in mesh.mesh.get_surface_count():
				var mat: Material = mesh.mesh.surface_get_material(i)
				var tex := Cartoon.texture_from_imported_material(mat)
				mesh.set_surface_override_material(i, Cartoon.painted_texture_prop(tex))

	static func _mesh_instances(n: Node) -> Array:
		var out: Array = []
		if n is MeshInstance3D:
			out.append(n)
		for c in n.get_children():
			out.append_array(_mesh_instances(c))
		return out

	## Cadre la caméra sur l'AABB réelle du modèle chargé (jamais les nudges/
	## échelles FP de ViewModel.gd, calibrés pour une caméra fixe à la
	## hanche — ce tourniquet a besoin d'un cadrage générique, indépendant du
	## pivot d'auteur de chaque arme) : recentre le modèle sur l'origine du
	## pivot, recule la caméra d'une distance proportionnelle au rayon.
	func _frame_camera() -> void:
		var res := _local_aabb(_loaded, Transform3D.IDENTITY)
		if not res.has_any:
			return
		var aabb: AABB = res.aabb
		_loaded.position -= aabb.get_center()
		var radius: float = maxf(aabb.size.length() * 0.5, 0.05)
		var fov_rad := deg_to_rad(_cam.fov * 0.5)
		var dist: float = radius / maxf(tan(fov_rad), 0.1) * 1.6
		_cam.position = Vector3(radius * 0.12, radius * 0.12, dist)
		_cam.look_at(Vector3.ZERO, Vector3.UP)

	## AABB de `n` (et ses descendants) dans l'espace LOCAL de `n` — accumule
	## le transform en descendant plutôt que de dépendre de `global_transform`
	## (valide même avant le premier `_process`/rendu). `has_any` distingue
	## "aucun maillage trouvé" d'une AABB légitimement nulle (position/taille
	## à zéro), jamais confondus.
	static func _local_aabb(n: Node, parent_xform: Transform3D) -> Dictionary:
		var xform := parent_xform
		if n is Node3D:
			xform = parent_xform * (n as Node3D).transform
		var result := AABB()
		var has_any := false
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			result = xform * (n as MeshInstance3D).mesh.get_aabb()
			has_any = true
		for c in n.get_children():
			var child_res: Dictionary = _local_aabb(c, xform)
			if child_res.has_any:
				result = (child_res.aabb as AABB) if not has_any else result.merge(child_res.aabb)
				has_any = true
		return {"aabb": result, "has_any": has_any}

	func _process(delta: float) -> void:
		if _loaded == null or not is_visible_in_tree() or Comic.reduced_motion():
			return
		_pivot.rotation.y = wrapf(_pivot.rotation.y + delta * ROTATE_SPEED, 0.0, TAU)
