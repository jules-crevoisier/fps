## OptionsMenu.gd
## Menu d'options à cinq pages : "Clavier / Souris", "Manette",
## "Affichage & Son", "Accessibilité" et "Viseur" (UX-03).
## - Navigable au clavier ET à la manette (focus + ui_*).
## - Page clavier : sensibilité souris, FOV (horizontal, UX-02) + effets de FOV
##   dynamique, mode d'affichage clavier Auto/AZERTY/QWERTY (UX-14 — un
##   LIBELLÉ seulement, voir Settings.LAYOUT_OPTIONS), remap touches,
##   sensibilité ADS et maintien/bascule accroupi-ADS-marche (UX-06).
## - Page manette : sensibilité, inversion Y, remap des boutons.
## - Page affichage & son (UX-06) : mode fenêtre, échelle de rendu, vsync,
##   limite d'images, préréglage graphique (dont Steam Deck), contours d'arête
##   (ink edges), overlay FPS/réseau, volumes maître/effets/musique/interface/
##   voix/ambiance, audio mono.
## - Page accessibilité : couleur ennemi (Magenta/Citron, design.md §9 —
##   recommandation daltonisme), échelle d'interface (Steam Deck), mouvement
##   réduit, secousses de caméra et head-bob (UX-06). Voir Settings.gd /
##   Cartoon.gd (R-A).
## - Page viseur (UX-03) : ouvre CrosshairEditor.gd (couleur, contour, point
##   central, lignes intérieures/extérieures, écart, opacité, 4 préréglages,
##   code importable/exportable, aperçu temps réel ciel + sable) en overlay
##   par-dessus cette page — même patron d'imbrication que PauseMenu._open_options
##   (l'overlay porte son propre fond opaque, rien à masquer ici).
## Chaque page a son bouton "Réinitialiser cette page" (UX-06, `_reset_button`/
## `_rebuild_page`) qui ne remet à zéro QUE les réglages de cette page.
## Émet `closed` quand on revient en arrière.
##
## UX-35 (2026-09-25) — « UI v4 BL3 » (docs/UI_DIRECTION_BL3.md §6 « Options »,
## direction VALIDÉE) : reskin complet du CHROME (onglets, lignes, curseurs,
## bascules), la logique Settings (get/set/save_all) reste identique champ par
## champ — seul l'HABILLAGE change :
##   - Onglets penchés (`KitSlantBar`, kit ART-31/UX-30 partagé — remplace les
##     5 `Button.toggle_mode` v2) : onglet ACTIF en fond `signal` (jaune,
##     §4.6 « choisi : fond signal »), les autres en `plate_hi`.
##   - Chaque réglage devient une LIGNE v4 (`_row_v4`) : hauteur FIXE
##     `ROW_HEIGHT_V4` (60 px), largeur bornée à `ROW_MAX_WIDTH_V4` (1 100 px
##     max — `_scroll` capé, colonne alignée à gauche, §4.4 « rien n'est
##     centré par défaut »), libellé `Comic.SIZE_28` sur une colonne fixe de
##     `ROW_LABEL_WIDTH_V4` (480 px), contrôle ensuite avec une marge droite
##     `ROW_RIGHT_MARGIN_V4` (« pas au bord »).
##   - Curseurs numériques : `_V4Slider` (classe interne, piste PENCHÉE à 12°
##     remplie en `signal` — §6 « curseur à piste penchée signal ») remplace
##     `HSlider`. Aucun composant kit équivalent au moment de cette tranche
##     (scripts/ui/kit/ hors de la liste de fichiers UX-35) : classe privée à
##     CE fichier plutôt qu'un fichier de kit hors périmètre — même choix que
##     `WeaponSilhouette`/`WeaponTurntable` en classes internes de BuyMenu.gd.
##   - Réglages booléens : bascule OUI / NON (`_toggle_row_v4`, réutilise
##     `KitSlantBar` — fond `signal` si OUI, `plate_hi` si NON) remplace
##     `CheckButton`.
##   - Aide de la ligne focalisée à droite (comme BL3, §6) : panneau fixe
##     (`_build_help_panel`, coins coupés `Comic.plate_style()`) à droite de la
##     colonne de réglages, mis à jour par `_set_help()` au survol/focus de
##     CHAQUE ligne (`_wire_help`) — état "vide" par défaut
##     (`_HELP_DEFAULT_TEXT`, aucune ligne survolée/focalisée).
## UX-37 (retour lead 2026-09-25, §4 « bandeau pinceau rouge à supprimer,
## titre OPTIONS en encre 66 ») : `BrushHeader.gd` (bandeau rouge « pinceau »,
## hors de la liste de fichiers de cette tâche — LU, jamais modifié) est
## remplacé ici par un simple `Label` v4 (`Comic.title_label_v4`, capitales
## italiques papier, 66 px) — plus aucun fond pinceau rouge sur cet écran
## (§4.5 « bandeau rouge supprimé », `_title_label` ci-dessous). `Comic.
## bullet_row()` (petite puce ROUGE devant chaque sous-titre de section, ex.
## « Touches — … ») reste v3 : ni Comic.gd (le jeton `BULLET`) ni l'acceptance
## de cette tâche (« bandeau », pas « puce ») ne le couvrent — un simple point
## de 21 px, sans commune mesure avec la barre pleine largeur qui posait
## problème (retour utilisateur 2026-09-25 : « titre OPTIONS en encre 66 »
## visait le bandeau, pas cette puce).
## Limite restante (à arbitrer par le lead, `blocked_on`) : ArsenalMenu.gd/
## BuyMenu.gd/CrosshairEditor.gd gardent leur propre `BrushHeader` (hors de la
## liste de fichiers de cette tâche) — seul l'écran OPTIONS perd son bandeau
## rouge par ce lot.
extends Control

signal closed

## Overlay CrosshairEditor.gd (UX-03) — preload plutôt qu'un chemin en dur
## dans `_open_crosshair_editor`, même patron que PauseMenu.OPTIONS_SCRIPT.
const CROSSHAIR_EDITOR_SCRIPT := preload("res://scripts/ui/CrosshairEditor.gd")

## UX-35, UI_DIRECTION_BL3.md §6 « lignes de 60 px sur 1 100 px max (libellé
## 28, contrôle à 480 px, pas au bord) ».
const ROW_HEIGHT_V4 := 60.0
const ROW_MAX_WIDTH_V4 := 1100.0
const ROW_LABEL_WIDTH_V4 := 480.0
const ROW_RIGHT_MARGIN_V4 := 24.0  # Comic.SP_4 (§4.4 grille de 6) — « pas au bord ».
const HELP_PANEL_MIN_W := 340.0
const _HELP_DEFAULT_TEXT := "Survolez ou sélectionnez un réglage pour voir son aide, comme dans Borderlands 3."

var _pages: VBoxContainer  ## conteneur direct des 5 pages (UX-06 : reconstruit une page au clic "Réinitialiser", voir `_rebuild_page`).
var _kb_page: VBoxContainer
var _pad_page: VBoxContainer
var _render_page: VBoxContainer
var _access_page: VBoxContainer
var _crosshair_page: VBoxContainer
var _kb_buttons: Dictionary = {}
var _pad_buttons: Dictionary = {}
var _tab_kb: KitSlantBar
var _tab_pad: KitSlantBar
var _tab_render: KitSlantBar
var _tab_access: KitSlantBar
var _tab_crosshair: KitSlantBar
## Overlay ouvert par la page "Viseur" (UX-03) — voir `_open_crosshair_editor`.
var _crosshair_editor: Control
var _layout_option: OptionButton
var _enemy_color_label: Label
var _enemy_color_buttons: Array = []
var _ui_scale_label: Label
## UX-35 : aide à droite (§6 « aide de la ligne focalisée à droite, comme BL3 »).
var _help_label: Label
## UX-37 : titre "OPTIONS" v4 (remplace `BrushHeader`, voir la docstring de tête) —
## référencé par tests/ui/test_options_v4.gd pour vérifier le retrait du bandeau rouge.
var _title_label: Label

var _listening_action: String = ""
var _listening_kind: String = ""  # "kb" ou "pad"
var _scroll: ScrollContainer
var _hold_time: float = 0.0       # durée de maintien d'une direction
var _repeat_cd: float = 0.0       # cooldown de répétition de navigation

## Ordre 0 Magenta / 1 Citron (design.md v2 §9 : Settings.enemy_color).
const _ENEMY_COLOR_NAMES := ["Magenta", "Citron"]
const _ENEMY_COLOR_SWATCH := [Comic.ENEMY_MAGENTA, Comic.ENEMY_CITRON]

## Mode d'affichage clavier — index de l'OptionButton vers Settings.layout
## (UX-12 : contrôle natif OptionButton, stylé par ui_theme.tres ; UX-14 :
## "Auto" détecte la disposition RÉELLE de l'OS à l'affichage — les LIAISONS
## ne changent plus jamais, voir Settings.LAYOUT_OPTIONS). Le libellé "Auto"
## gagne un suffixe " (AZERTY détecté)" quand `Settings.detected_fr_keyboard()`
## le signale (docs/research/10_ammo_kits_input.md §4.2 point 8), pour
## rassurer un joueur FR que "Auto" a déjà compris son clavier.
const _LAYOUT_IDS := ["auto", "azerty", "qwerty"]
const _LAYOUT_LABELS := ["Auto", "AZERTY", "QWERTY"]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_show_page("kb")

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Comic.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, Comic.SAFE_MARGIN)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	margin.add_child(root)

	# UX-37 §4 : titre v4 SANS bandeau pinceau (remplace `BrushHeader`, rouge)
	# — capitales italiques papier, 66 px, zéro fond (voir la docstring de tête).
	_title_label = Comic.title_label_v4("Options", Comic.SIZE_66, Comic.paper_color())
	root.add_child(_title_label)

	# En-tête : onglets penchés v4 (UX-35, §6 « onglets penchés ») + retour.
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", Comic.SP_2)
	header_row.add_theme_constant_override("margin_top", Comic.SP_2)
	_tab_kb = _tab_v4("Clavier / Souris", func(): _show_page("kb"))
	_tab_pad = _tab_v4("Manette", func(): _show_page("pad"))
	_tab_render = _tab_v4("Affichage & Son", func(): _show_page("render"))
	_tab_access = _tab_v4("Accessibilité", func(): _show_page("access"))
	_tab_crosshair = _tab_v4("Viseur", func(): _show_page("crosshair"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := Button.new()
	back.text = "Retour"
	back.custom_minimum_size = Vector2(120, 38)
	back.pressed.connect(func(): closed.emit())
	UiFx.press(back)
	header_row.add_child(_tab_kb)
	header_row.add_child(_tab_pad)
	header_row.add_child(_tab_render)
	header_row.add_child(_tab_access)
	header_row.add_child(_tab_crosshair)
	header_row.add_child(spacer)
	header_row.add_child(back)
	root.add_child(header_row)

	# Filet d'accent sous les onglets, déployé de gauche à droite à l'ouverture
	# (UX-12 : UiFx.wipe — `scale`, jamais géré par les conteneurs, sûr ici
	# même enfant direct de `root`, un VBoxContainer). UX-35 : `signal` (jaune)
	# plutôt que `BULLET` (rouge v3) — seule la couleur qui désigne (§4.2).
	var accent_rule := ColorRect.new()
	accent_rule.color = Comic.signal_color()
	accent_rule.custom_minimum_size = Vector2(0, Comic.RULE_W_STRONG)
	accent_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(accent_rule)
	UiFx.wipe(accent_rule)

	# Corps : colonne de réglages (bornée à 1 100 px, alignée à gauche) + aide
	# de la ligne focalisée à droite (UX-35, §6 « comme BL3 »).
	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", Comic.SP_3)
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body_row)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(ROW_MAX_WIDTH_V4, 0.0)
	_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	body_row.add_child(_scroll)
	_pages = VBoxContainer.new()
	_pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_pages)

	body_row.add_child(_build_help_panel())

	_kb_page = _build_kb()
	_pad_page = _build_pad()
	_render_page = _build_render()
	_access_page = _build_access()
	_crosshair_page = _build_crosshair_page()
	_pages.add_child(_kb_page)
	_pages.add_child(_pad_page)
	_pages.add_child(_render_page)
	_pages.add_child(_access_page)
	_pages.add_child(_crosshair_page)

## Onglet penché v4 (UX-35, §6 « onglets penchés » ; §4.6 « choisi : fond
## signal ») — `KitSlantBar` (kit ART-31/UX-30 partagé, réutilisé tel quel,
## même composant que BuyMenu.gd/ArsenalMenu.gd pour que TOUS les onglets du
## jeu se lisent comme un seul système). `selected`/`accent_color` sont mis à
## jour par `_show_page` ci-dessous, jamais ici (construction initiale seule).
func _tab_v4(text: String, cb: Callable) -> KitSlantBar:
	var b := KitSlantBar.new()
	b.bar_text = text
	b.custom_minimum_size = Vector2(220.0, 48.0)
	b.accent_color = Comic.plate_hi_color()
	b.pressed.connect(cb)
	return b

func _show_page(page: String) -> void:
	_kb_page.visible = page == "kb"
	_pad_page.visible = page == "pad"
	_render_page.visible = page == "render"
	_access_page.visible = page == "access"
	_crosshair_page.visible = page == "crosshair"
	for entry in [["kb", _tab_kb], ["pad", _tab_pad], ["render", _tab_render], ["access", _tab_access], ["crosshair", _tab_crosshair]]:
		var tab: KitSlantBar = entry[1]
		var active: bool = entry[0] == page
		tab.selected = active
		tab.accent_color = Comic.signal_color() if active else Comic.plate_hi_color()
	var target := _tab_kb
	var shown := _kb_page
	match page:
		"pad": target = _tab_pad; shown = _pad_page
		"render": target = _tab_render; shown = _render_page
		"access": target = _tab_access; shown = _access_page
		"crosshair": target = _tab_crosshair; shown = _crosshair_page
	target.grab_focus()
	_set_help(_HELP_DEFAULT_TEXT)
	# Les 5 pages sont des enfants directs de `pages` (VBoxContainer dans
	# `_scroll`) : la même bascule de visibilité que ci-dessus vient de mettre
	# en file un nouveau tri du conteneur — `call_deferred` laisse ce tri
	# s'exécuter avant que `UiFx.reveal` ne capture les offsets d'origine de
	# la page montrée (même précaution que PauseMenu._reveal_panel).
	call_deferred("_reveal_page", shown)

func _reveal_page(page: Control) -> void:
	if is_instance_valid(page) and page.visible:
		UiFx.reveal(page)

# ----------------------------------------------------------- AIDE (UX-35, §6)
## Panneau fixe à droite du corps — « aide de la ligne focalisée à droite,
## comme BL3 » : coins coupés (`Comic.plate_style()`, §4.3), état "vide" par
## défaut (`_HELP_DEFAULT_TEXT`) tant qu'aucune ligne n'a été survolée/
## focalisée sur la page courante (voir `_wire_help`/`_set_help`).
func _build_help_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Comic.plate_style(Comic.plate_color()))
	panel.custom_minimum_size = Vector2(HELP_PANEL_MIN_W, 0.0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Comic.SP_2)
	panel.add_child(col)

	col.add_child(Comic.meta_label_v4("Aide", Comic.SIZE_21, Comic.paper_dim_color()))
	_help_label = Comic.body_label_v4(_HELP_DEFAULT_TEXT, Comic.SIZE_28, Comic.paper_color())
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_help_label)
	return panel

func _set_help(text: String) -> void:
	if _help_label:
		_help_label.text = text

## Branche `target` (survol souris + focus clavier/manette) sur l'aide à
## droite — appelé pour la ligne ENTIÈRE (`_row_v4`) ET pour le contrôle
## interactif précis qu'elle porte (`_wire_help` de nouveau, au cas par cas :
## un contrôle composite — ex. la paire couleur ennemi — n'a pas de focus
## propre, seuls ses boutons enfants en ont un).
func _wire_help(target: Control, help_text: String) -> void:
	if target == null or help_text == "":
		return
	var show_help := func(): _set_help(help_text)
	target.mouse_entered.connect(show_help)
	target.focus_entered.connect(show_help)

# ----------------------------------------------------------- LIGNE v4 (UX-35, §6)
## Ligne de réglage v4 : hauteur FIXE `ROW_HEIGHT_V4`, libellé sur une colonne
## fixe `ROW_LABEL_WIDTH_V4` (« libellé 28 »), `control` ensuite (« contrôle à
## 480 px »), marge droite `ROW_RIGHT_MARGIN_V4` (« pas au bord »). La largeur
## TOTALE de la ligne est bornée par `_scroll` (capé à `ROW_MAX_WIDTH_V4` dans
## `_build`), jamais fixée ici. Branche l'aide au survol de la ligne entière ET
## du contrôle (voir `_wire_help`) — un contrôle composite peut avoir besoin
## d'un câblage supplémentaire sur ses propres enfants, à la charge de
## l'appelant (voir `_build_access`, sélecteur de couleur ennemi).
func _row_v4(label_text: String, control: Control, help_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT_V4)
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var lbl := Comic.body_label_v4(label_text, Comic.SIZE_28, Comic.paper_color())
	lbl.custom_minimum_size = Vector2(ROW_LABEL_WIDTH_V4, ROW_HEIGHT_V4)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(lbl)

	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)

	var right_pad := Control.new()
	right_pad.custom_minimum_size = Vector2(ROW_RIGHT_MARGIN_V4, 0.0)
	right_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right_pad)

	_wire_help(row, help_text)
	_wire_help(control, help_text)
	return row

## Ligne curseur v4 (piste penchée `signal`, §6) — combine `_V4Slider` avec son
## étiquette de valeur formatée (`fmt`) ; `on_change` persiste IMMÉDIATEMENT
## (même convention que chaque contrôle du menu — jamais de bouton
## "Enregistrer" séparé).
func _slider_row_v4(label_text: String, help_text: String, min_v: float, max_v: float, step: float, initial: float, fmt: Callable, on_change: Callable) -> HBoxContainer:
	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", Comic.SP_3)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var slider := _V4Slider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(slider)

	var val_lbl := Comic.number_label_v4(fmt.call(initial), Comic.SIZE_21, Comic.paper_color())
	val_lbl.custom_minimum_size = Vector2(96.0, 0.0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wrap.add_child(val_lbl)

	slider.value_changed.connect(func(v: float):
		val_lbl.text = fmt.call(v)
		on_change.call(v))

	var row := _row_v4(label_text, wrap, help_text)
	_wire_help(slider, help_text)
	return row

## Ligne bascule OUI / NON v4 (§6) — réutilise `KitSlantBar` (kit partagé) en
## petit bouton à deux états : fond `signal` + « OUI » quand actif, fond
## `plate_hi` + « NON » sinon (§4.6 « choisi : fond signal »). `get_fn`/
## `set_fn` lisent/écrivent le réglage `Settings` ; `save_all()` est appelé à
## chaque bascule comme tout le reste du menu ; `extra` (optionnel) couvre les
## rappels supplémentaires déjà nécessaires ailleurs (overlay FPS, audio mono).
func _toggle_row_v4(label_text: String, help_text: String, get_fn: Callable, set_fn: Callable, extra: Callable = Callable()) -> HBoxContainer:
	var toggle := KitSlantBar.new()
	toggle.custom_minimum_size = Vector2(128.0, 48.0)
	var sync := func():
		var on: bool = bool(get_fn.call())
		toggle.bar_text = "Oui" if on else "Non"
		toggle.accent_color = Comic.signal_color() if on else Comic.plate_hi_color()
	sync.call()
	toggle.pressed.connect(func():
		set_fn.call(not bool(get_fn.call()))
		Settings.save_all()
		if extra.is_valid():
			extra.call()
		sync.call())
	return _row_v4(label_text, toggle, help_text)

# ----------------------------------------------------- PAGE CLAVIER / SOURIS
func _build_kb() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_1)

	# UX-37 (retour lead 2026-09-25, §4 : « la sensibilité de base est beaucoup
	# trop haute », afficher en valeur LISIBLE, jamais « 0.0025 ») — échelle
	# 0,1x-5,0x où 1,0x = Settings.MOUSE_SENSITIVITY_DEFAULT (posé par SET-01,
	# scripts/core/Settings.gd, LU jamais modifié ici) : piste et libellé
	# suivent cette échelle (min/max/step DÉRIVÉS du défaut, jamais figés en
	# dur, pour rester corrects si SET-01 le retouche), mais la valeur
	# PERSISTÉE dans Settings.mouse_sensitivity reste le PASSAGE DIRECT de la
	# valeur du curseur — jamais reconvertie ici — pour rester compatible avec
	# tests/ui/test_options_v4.gd::test_slider_row_drives_a_slanted_signal_track_and_persists_the_setting
	# (verrouillé : assigne min/max/value BRUTS au curseur puis vérifie que
	# Settings.mouse_sensitivity reçoit EXACTEMENT cette même valeur).
	v.add_child(_slider_row_v4(
		"Sensibilité souris", "Vitesse de rotation de la caméra par mouvement de souris. 1.00× = valeur par défaut. Plus haut, plus vif.",
		Settings.MOUSE_SENSITIVITY_DEFAULT * 0.1, Settings.MOUSE_SENSITIVITY_DEFAULT * 5.0, Settings.MOUSE_SENSITIVITY_DEFAULT * 0.01, Settings.mouse_sensitivity,
		func(x): return "%.2f×" % (x / Settings.MOUSE_SENSITIVITY_DEFAULT),
		func(x): Settings.mouse_sensitivity = x; Settings.save_all()))

	# UX-02 : curseur 80-120° HORIZONTAL (défaut 103°, cf. Valorant/Overwatch 2,
	# docs/research/04_ui_ux.md §3.1) — Settings.clamp_fov garde une borne plus
	# large (70-120) comme filet de sécurité pour un fichier déjà existant.
	v.add_child(_slider_row_v4(
		"Champ de vision (FOV)", "Champ de vision horizontal (16:9). Plus large montre davantage de scène mais déforme les bords.",
		80.0, 120.0, 1.0, Settings.fov,
		func(x): return "%d°" % int(x),
		func(x): Settings.fov = x; Settings.save_all()))

	v.add_child(_toggle_row_v4(
		"Effets de FOV", "Élargit temporairement le champ de vision en sprint, glissade et survitesse.",
		func(): return Settings.fov_effects_enabled,
		func(on): Settings.fov_effects_enabled = on))

	# UX-06, docs/research/04_ui_ux.md §2.7 : "il faut un multiplicateur ADS
	# séparé ... pour garder la mémoire musculaire" (Aimlabs/Ubisoft R6).
	v.add_child(_slider_row_v4(
		"Sensibilité en visée (ADS)", "Multiplicateur de sensibilité appliqué UNIQUEMENT en visée, pour garder la mémoire musculaire au tir à la hanche.",
		0.3, 2.0, 0.05, Settings.ads_sensitivity_multiplier,
		func(x): return "×%.2f" % x,
		func(x): Settings.ads_sensitivity_multiplier = x; Settings.save_all()))

	# UX-06, docs/research/04_ui_ux.md §2.7 : "maintien ou bascule (accroupi,
	# ADS, marche)" — défaut maintien (comportement actuel inchangé).
	v.add_child(_toggle_row_v4(
		"Maintenir pour viser", "OUI : la visée reste active tant que la touche est maintenue. NON : un appui bascule la visée.",
		func(): return Settings.hold_to_aim,
		func(on): Settings.hold_to_aim = on))
	v.add_child(_toggle_row_v4(
		"Maintenir pour s'accroupir", "OUI : reste accroupi tant que la touche est maintenue. NON : un appui bascule accroupi/debout.",
		func(): return Settings.hold_to_crouch,
		func(on): Settings.hold_to_crouch = on))
	v.add_child(_toggle_row_v4(
		"Maintenir pour marcher", "OUI : la marche reste active tant que la touche est maintenue. NON : un appui bascule marche/course.",
		func(): return Settings.hold_to_walk,
		func(on): Settings.hold_to_walk = on))

	# Contrôle natif OptionButton (UX-12 : style v2 centralisé dans
	# ui_theme.tres) — remplace la paire de boutons + libellé "Actuel : …" de
	# la v1 par un seul sélecteur, la sélection AFFICHÉE fait déjà office
	# d'indicateur "actuel". UX-14 : ce sélecteur ne change plus jamais une
	# touche, seulement l'AFFICHAGE des touches (voir Settings.apply_layout).
	_layout_option = OptionButton.new()
	_layout_option.custom_minimum_size = Vector2(260, 40)
	for i in _LAYOUT_LABELS.size():
		var label: String = _LAYOUT_LABELS[i]
		if _LAYOUT_IDS[i] == "auto" and Settings.detected_fr_keyboard():
			label += " (AZERTY détecté)"
		_layout_option.add_item(label, i)
	_layout_option.selected = maxi(_LAYOUT_IDS.find(Settings.layout), 0)
	_layout_option.item_selected.connect(func(idx): _set_layout(_LAYOUT_IDS[idx]))
	v.add_child(_row_v4("Disposition clavier", _layout_option, "Change l'AFFICHAGE des touches (AZERTY/QWERTY) — les liaisons elles-mêmes ne changent jamais."))

	v.add_child(Comic.bullet_row("Touches — clique puis appuie sur la nouvelle touche"))
	for action in Settings.ACTIONS:
		var btn := _btn(Settings.binding_text(action), _rebind.bind(action, "kb"))
		_kb_buttons[action] = btn
		v.add_child(_row_v4(Settings.ACTIONS[action], btn, "Touche assignée pour « %s ». Cliquez puis appuyez sur la nouvelle touche." % Settings.ACTIONS[action]))

	v.add_child(HSeparator.new())
	v.add_child(_reset_button("kb", Settings.reset_kb_page))
	return v

# ----------------------------------------------------------- PAGE MANETTE
func _build_pad() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_1)

	v.add_child(_slider_row_v4(
		"Sensibilité manette", "Vitesse de rotation de la caméra au stick droit.",
		0.5, 8.0, 0.1, Settings.gamepad_sensitivity,
		func(x): return "%.1f" % x,
		func(x): Settings.gamepad_sensitivity = x; Settings.save_all()))

	v.add_child(_toggle_row_v4(
		"Inverser l'axe vertical (Y)", "OUI : pousser le stick vers le haut baisse la visée (inversé). NON : comportement standard.",
		func(): return Settings.invert_y,
		func(on): Settings.invert_y = on))

	v.add_child(Comic.bullet_row("Boutons — clique puis appuie sur un bouton manette"))
	for action in Settings.ACTIONS:
		var btn := _btn(Settings.gamepad_text(action), _rebind.bind(action, "pad"))
		_pad_buttons[action] = btn
		v.add_child(_row_v4(Settings.ACTIONS[action], btn, "Bouton manette assigné pour « %s ». Cliquez puis appuyez sur un bouton." % Settings.ACTIONS[action]))

	var note := Comic.body_label_v4("Sticks (déplacement/visée) et gâchettes (tir/visée) sont fixes.", Comic.SIZE_21, Comic.paper_dim_color())
	v.add_child(note)

	v.add_child(HSeparator.new())
	v.add_child(_reset_button("pad", Settings.reset_pad_page))
	return v

# ------------------------------------------------------------ PAGE AFFICHAGE & SON
const _WINDOW_MODE_LABELS := ["Fenêtré", "Plein écran (bordures)", "Plein écran (exclusif)"]
const _FPS_LIMIT_LABELS := ["Illimitée", "60", "144", "240"]
const _GRAPHICS_PRESET_IDS := ["quality", "balanced", "performance", "steam_deck"]
const _GRAPHICS_PRESET_LABELS := ["Qualité", "Équilibré", "Performance", "Steam Deck"]

func _build_render() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_1)

	# ------------------------------------------------------- AFFICHAGE (UX-06)
	v.add_child(Comic.bullet_row("Affichage"))

	var window_opt := OptionButton.new()
	window_opt.custom_minimum_size = Vector2(260, 40)
	for i in Settings.WINDOW_MODES.size():
		window_opt.add_item(_WINDOW_MODE_LABELS[i], i)
	window_opt.selected = maxi(Settings.WINDOW_MODES.find(Settings.window_mode), 0)
	window_opt.item_selected.connect(func(idx):
		Settings.window_mode = Settings.WINDOW_MODES[idx]
		Settings.apply_window_mode(); Settings.save_all())
	v.add_child(_row_v4("Mode fenêtre", window_opt, "Fenêtré, plein écran avec bordures, ou plein écran exclusif."))

	v.add_child(_slider_row_v4(
		"Échelle de rendu 3D", "Résolution de rendu interne, en pourcentage de la fenêtre. Baisser améliore les images par seconde.",
		0.5, 1.0, 0.05, Settings.render_scale,
		func(x): return "%d %%" % int(round(x * 100.0)),
		func(x): Settings.render_scale = x; Settings.apply_render_scale(); Settings.save_all()))

	v.add_child(_toggle_row_v4(
		"Synchronisation verticale (vsync)", "Synchronise l'affichage avec le taux de rafraîchissement de l'écran — supprime le déchirement d'image, peut ajouter un peu de latence.",
		func(): return Settings.vsync_enabled,
		func(on): Settings.vsync_enabled = on,
		func(): Settings.apply_vsync()))

	var fps_opt := OptionButton.new()
	fps_opt.custom_minimum_size = Vector2(260, 40)
	for i in Settings.FPS_LIMIT_OPTIONS.size():
		fps_opt.add_item(_FPS_LIMIT_LABELS[i], i)
	fps_opt.selected = maxi(Settings.FPS_LIMIT_OPTIONS.find(Settings.fps_limit), 0)
	fps_opt.item_selected.connect(func(idx):
		Settings.fps_limit = Settings.FPS_LIMIT_OPTIONS[idx]
		Settings.apply_fps_limit(); Settings.save_all())
	v.add_child(_row_v4("Limite d'images", fps_opt, "Plafonne le nombre d'images par seconde."))

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", Comic.SP_2)
	var preset_opt := OptionButton.new()
	preset_opt.custom_minimum_size = Vector2(220, 40)
	for i in _GRAPHICS_PRESET_IDS.size():
		preset_opt.add_item(_GRAPHICS_PRESET_LABELS[i], i)
	preset_opt.selected = maxi(_GRAPHICS_PRESET_IDS.find(Settings.graphics_preset), 0)
	preset_row.add_child(preset_opt)
	preset_row.add_child(_btn("Appliquer", func():
		Settings.apply_graphics_preset(_GRAPHICS_PRESET_IDS[preset_opt.selected])
		_rebuild_page("render")))
	v.add_child(_row_v4("Préréglage graphique", preset_row, "Applique un ensemble de réglages graphiques prêt à l'emploi, y compris un préréglage Steam Deck."))

	v.add_child(HSeparator.new())
	v.add_child(_toggle_row_v4(
		"Contours d'arête (ink edges)", "Contours d'encre supplémentaires sur les arêtes des objets.",
		func(): return Settings.ink_edges,
		func(on): Settings.ink_edges = on))

	v.add_child(_toggle_row_v4(
		"Afficher FPS / réseau", "Affiche en permanence les images par seconde et la latence réseau. F3 bascule aussi manuellement.",
		func(): return Settings.show_perf_overlay,
		func(on): Settings.show_perf_overlay = on,
		func():
			# UX-06, relance QA n°3 : appliquer sans redémarrage (même principe
			# que "Audio mono" ci-dessous) — le réglage était mort, seul F3
			# basculait l'affichage sans ce rappel.
			var perf := get_tree().root.get_node_or_null("Perf") if get_tree() else null
			if perf and perf.has_method("apply_show_perf_overlay"):
				perf.apply_show_perf_overlay()))

	# --------------------------------------------------------------- SON
	v.add_child(HSeparator.new())
	v.add_child(_slider_row_v4("Volume général", "Volume général (musique, effets, voix, ambiance), de 0 à 100 %.",
		0.0, 1.0, 0.01, Settings.volume_master,
		func(x): return "%d %%" % int(round(x * 100.0)),
		func(x): Settings.volume_master = x; Settings.save_all()))
	v.add_child(_slider_row_v4("Volume effets (SFX)", "Volume des effets sonores (tirs, impacts, pas), de 0 à 100 %.",
		0.0, 1.0, 0.01, Settings.volume_sfx,
		func(x): return "%d %%" % int(round(x * 100.0)),
		func(x): Settings.volume_sfx = x; Settings.save_all()))
	v.add_child(_slider_row_v4("Volume musique", "Volume de la musique, de 0 à 100 %.",
		0.0, 1.0, 0.01, Settings.volume_music,
		func(x): return "%d %%" % int(round(x * 100.0)),
		func(x): Settings.volume_music = x; Settings.save_all()))
	v.add_child(_slider_row_v4("Volume interface (UI)", "Volume des sons d'interface (clics, achats, alertes), de 0 à 100 %.",
		0.0, 1.0, 0.01, Settings.volume_ui,
		func(x): return "%d %%" % int(round(x * 100.0)),
		func(x): Settings.volume_ui = x; Settings.save_all()))
	v.add_child(_slider_row_v4("Volume voix (chat vocal)", "Volume du chat vocal des autres joueurs, de 0 à 100 %.",
		0.0, 1.0, 0.01, Settings.volume_voice,
		func(x): return "%d %%" % int(round(x * 100.0)),
		func(x): Settings.volume_voice = x; Settings.save_all()))
	v.add_child(_slider_row_v4("Volume ambiance de carte", "Volume des sons d'ambiance de la carte (vent, foule), de 0 à 100 %.",
		0.0, 1.0, 0.01, Settings.volume_ambience,
		func(x): return "%d %%" % int(round(x * 100.0)),
		func(x): Settings.volume_ambience = x; Settings.save_all()))

	v.add_child(_toggle_row_v4(
		"Audio mono", "OUI : un seul canal audio (gauche = droit) — utile en écoutant avec une seule oreille.",
		func(): return Settings.audio_mono,
		func(on): Settings.audio_mono = on,
		func():
			var sfx := get_tree().root.get_node_or_null("Sfx") if get_tree() else null
			if sfx and sfx.has_method("apply_audio_mono"):
				sfx.apply_audio_mono()))

	v.add_child(HSeparator.new())
	v.add_child(_reset_button("render", func():
		Settings.reset_render_page()
		# UX-06 : "Réinitialiser" doit s'appliquer sans redémarrage — même
		# rappel que les bascules audio mono / overlay FPS ci-dessus, sinon
		# l'overlay resterait affiché (ou l'audio mono actif) après la remise
		# à zéro tant que le joueur ne re-bascule pas la case lui-même.
		var perf := get_tree().root.get_node_or_null("Perf") if get_tree() else null
		if perf and perf.has_method("apply_show_perf_overlay"):
			perf.apply_show_perf_overlay()
		var sfx := get_tree().root.get_node_or_null("Sfx") if get_tree() else null
		if sfx and sfx.has_method("apply_audio_mono"):
			sfx.apply_audio_mono()))
	return v

# ------------------------------------------------------------ PAGE ACCESSIBILITÉ
func _build_access() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_1)

	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", Comic.SP_3)
	_enemy_color_buttons.clear()
	for i in _ENEMY_COLOR_NAMES.size():
		var b := _btn(_ENEMY_COLOR_NAMES[i], _set_enemy_color.bind(i))
		var swatch := ColorRect.new()
		swatch.color = _ENEMY_COLOR_SWATCH[i]
		swatch.custom_minimum_size = Vector2(18, 18)
		var bh := HBoxContainer.new()
		bh.add_theme_constant_override("separation", Comic.SP_1)
		bh.add_child(swatch)
		bh.add_child(b)
		_enemy_color_buttons.append(b)
		crow.add_child(bh)
	var enemy_help := "Couleur d'affichage des ennemis. Citron est recommandé pour les joueurs protanopes/deutéranopes."
	for b2 in _enemy_color_buttons:
		_wire_help(b2, enemy_help)
	v.add_child(_row_v4("Couleur ennemi", crow, enemy_help))
	_enemy_color_label = Comic.body_label_v4("", Comic.SIZE_21, Comic.paper_dim_color())
	_enemy_color_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_enemy_color_label)
	_refresh_enemy_color_ui()

	v.add_child(HSeparator.new())
	v.add_child(_slider_row_v4(
		"Échelle d'interface", "Agrandit toute l'interface — utile sur petit écran ou Steam Deck (1.15× recommandé).",
		0.8, 1.5, 0.05, Settings.ui_scale,
		func(x): return "%.2f×" % x,
		func(x):
			Settings.ui_scale = Settings.clamp_ui_scale(x)
			Settings.apply_ui_scale()  # BUG-13 : appliquer en direct, pas seulement au prochain démarrage
			Settings.save_all()))

	v.add_child(HSeparator.new())
	v.add_child(_toggle_row_v4(
		"Mouvement réduit", "OUI : remplace les glissements et zooms de l'interface par de simples fondus.",
		func(): return Settings.reduced_motion,
		func(on): Settings.reduced_motion = on))

	# UX-06, docs/research/04_ui_ux.md §2.7 : "secousses de caméra, balancement
	# de tête" — désactivables pour le confort (mal des transports), même
	# principe que Mouvement réduit ci-dessus.
	v.add_child(_toggle_row_v4(
		"Secousses de caméra", "OUI : la caméra tremble sous l'effet des tirs et des dégâts.",
		func(): return Settings.camera_shake_enabled,
		func(on): Settings.camera_shake_enabled = on))

	# UX-37 (retour lead 2026-09-25, §4, GF-08) : intensité de la secousse à
	# trauma, séparée du maître ON/OFF ci-dessus — même patron que le curseur
	# "Intensité du balancement" juste en dessous (Settings.camera_shake_intensity,
	# combiné par CameraShake.effective_intensity, scripts/player/CameraShake.gd,
	# LU jamais modifié ici — cette page ne fait qu'écrire le réglage Settings).
	v.add_child(_slider_row_v4(
		"Intensité du tremblement", "Force de la secousse de caméra à l'impact (tir, dégât, explosion), de 0 (aucune) à 100 % (pleine intensité).",
		0.0, 1.0, 0.01, Settings.camera_shake_intensity,
		func(x): return "%d %%" % int(round(x * 100.0)),
		func(x): Settings.camera_shake_intensity = x; Settings.save_all()))

	v.add_child(_toggle_row_v4(
		"Balancement de tête (head-bob)", "OUI : la caméra suit le pas du personnage.",
		func(): return Settings.head_bob_enabled,
		func(on): Settings.head_bob_enabled = on))

	v.add_child(_slider_row_v4(
		"Intensité du balancement", "Force du balancement de tête, de 0 (immobile) à 2× (prononcé).",
		0.0, 2.0, 0.1, Settings.head_bob_intensity,
		func(x): return "%.1f×" % x,
		func(x): Settings.head_bob_intensity = x; Settings.save_all()))

	v.add_child(HSeparator.new())
	v.add_child(_reset_button("access", Settings.reset_access_page))
	return v

# ------------------------------------------------------------ PAGE VISEUR (UX-03)
## Page la plus légère des cinq : la personnalisation elle-même vit dans
## CrosshairEditor.gd (couleur, contour, point central, lignes intérieures/
## extérieures, écart, opacité, préréglages, code, aperçu ciel + sable) — cette
## page se contente d'expliquer ce qui s'y trouve et d'ouvrir l'éditeur en
## overlay (`_open_crosshair_editor`). Pas de bouton "Réinitialiser" ici :
## rien de propre à CETTE page à remettre à zéro (le préréglage "Défaut" de
## l'éditeur joue ce rôle pour le réticule lui-même).
func _build_crosshair_page() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_3)

	v.add_child(Comic.bullet_row("Viseur"))
	var desc := Comic.body_label_v4(
		"Couleur, contour, point central, lignes intérieures et extérieures, écart et opacité — avec aperçu en temps réel sur un fond ciel et un fond sable, 4 préréglages, et un code de viseur importable/exportable.",
		Comic.SIZE_28, Comic.paper_dim_color())
	desc.custom_minimum_size = Vector2(ROW_MAX_WIDTH_V4 - ROW_RIGHT_MARGIN_V4, 0.0)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(desc)

	v.add_child(_btn("Ouvrir l'éditeur de viseur", _open_crosshair_editor))
	return v

## Ouvre CrosshairEditor.gd en overlay par-dessus cette page — même patron que
## PauseMenu._open_options (preload -> .new() -> connecte `closed` ->
## add_child -> UiFx.reveal) : l'overlay porte son propre fond opaque plein
## écran, rien à masquer ici en dessous (voir doc de tête de fichier).
func _open_crosshair_editor() -> void:
	_crosshair_editor = CROSSHAIR_EDITOR_SCRIPT.new()
	_crosshair_editor.closed.connect(_close_crosshair_editor)
	add_child(_crosshair_editor)
	UiFx.reveal(_crosshair_editor)

func _close_crosshair_editor() -> void:
	if _crosshair_editor and is_instance_valid(_crosshair_editor):
		_crosshair_editor.queue_free()
	_crosshair_editor = null

func _set_enemy_color(i: int) -> void:
	Settings.enemy_color = Settings.clamp_enemy_color(i)
	Settings.save_all()
	_refresh_enemy_color_ui()

func _refresh_enemy_color_ui() -> void:
	if _enemy_color_label:
		_enemy_color_label.text = "Actuel : %s" % _ENEMY_COLOR_NAMES[Settings.enemy_color]
	for i in _enemy_color_buttons.size():
		_enemy_color_buttons[i].disabled = i == Settings.enemy_color

# ----------------------------------------------------------- REBIND
func _rebind(action: String, kind: String) -> void:
	_listening_action = action
	_listening_kind = kind
	var dict: Dictionary = _kb_buttons if kind == "kb" else _pad_buttons
	dict[action].text = "Appuyez…"

## Maintenir haut/bas (stick ou D-pad) fait défiler en continu : le 1er pas est
## géré par le système, puis on répète après un court délai (le scroll suit grâce
## à follow_focus).
func _process(delta: float) -> void:
	if _listening_action != "":
		return
	var dir := 0
	if Input.is_action_pressed("ui_down"):
		dir = 1
	elif Input.is_action_pressed("ui_up"):
		dir = -1
	if dir == 0:
		_hold_time = 0.0
		_repeat_cd = 0.0
		return
	_hold_time += delta
	if _hold_time < 0.4:
		return  # laisse le premier déplacement au système
	_repeat_cd -= delta
	if _repeat_cd <= 0.0:
		_move_focus(dir)
		_repeat_cd = 0.12

func _move_focus(dir: int) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null:
		return
	var nxt := focused.find_next_valid_focus() if dir > 0 else focused.find_prev_valid_focus()
	if nxt:
		nxt.grab_focus()

func _input(event: InputEvent) -> void:
	if _listening_action == "":
		return
	var ok := false
	if _listening_kind == "kb":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
				_end_listen()
				accept_event()
				return
			Settings.set_binding(_listening_action, event); ok = true
		elif event is InputEventMouseButton and event.pressed:
			Settings.set_binding(_listening_action, event); ok = true
	else:  # manette
		if event is InputEventJoypadButton and event.pressed:
			Settings.set_binding(_listening_action, event); ok = true
	if ok:
		_end_listen()
		accept_event()

func _end_listen() -> void:
	var a := _listening_action
	var kind := _listening_kind
	_listening_action = ""
	_listening_kind = ""
	if a == "":
		return
	if kind == "kb" and _kb_buttons.has(a):
		_kb_buttons[a].text = Settings.binding_text(a)
	elif kind == "pad" and _pad_buttons.has(a):
		_pad_buttons[a].text = Settings.gamepad_text(a)

func _set_layout(name: String) -> void:
	Settings.apply_layout(name)
	# `OptionButton.selected` ne réémet pas `item_selected` quand on l'assigne
	# par code : sûr à rappeler ici même si `name` vient déjà de ce signal.
	var idx := _LAYOUT_IDS.find(name)
	if idx >= 0 and _layout_option:
		_layout_option.selected = idx
	for action in _kb_buttons:
		_kb_buttons[action].text = Settings.binding_text(action)

# ----------------------------------------------------------- UI HELPERS
func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 34)
	b.pressed.connect(cb)
	UiFx.press(b)
	return b

## Bouton "Réinitialiser cette page" (UX-06 : "« Réinitialiser » remet les
## valeurs par défaut de la page seulement") — `reset_fn` est l'un des
## `Settings.reset_*_page` ; reconstruit ENSUITE la page (`_rebuild_page`) pour
## que les curseurs/cases affichés reflètent les valeurs remises à zéro, sans
## exiger de garder une référence membre pour chaque contrôle de chaque page.
func _reset_button(page: String, reset_fn: Callable) -> Button:
	var b := _btn("Réinitialiser cette page", func():
		reset_fn.call()
		_rebuild_page(page))
	return b

## Reconstruit la page `page` (après un "Réinitialiser") : la page affichée
## retient son état (visible), et le focus retombe sur le bouton Réinitialiser
## de la page fraîchement reconstruite (toujours son DERNIER enfant, voir
## chaque `_build_*`) pour que la navigation clavier/manette continue sans
## sauter ailleurs.
func _rebuild_page(page: String) -> void:
	var old: VBoxContainer
	var new_page: VBoxContainer
	var was_visible := false
	var idx := 0
	match page:
		"kb":
			old = _kb_page; was_visible = old.visible; idx = old.get_index()
			new_page = _build_kb(); _kb_page = new_page
		"pad":
			old = _pad_page; was_visible = old.visible; idx = old.get_index()
			new_page = _build_pad(); _pad_page = new_page
		"render":
			old = _render_page; was_visible = old.visible; idx = old.get_index()
			new_page = _build_render(); _render_page = new_page
		"access":
			old = _access_page; was_visible = old.visible; idx = old.get_index()
			new_page = _build_access(); _access_page = new_page
	_pages.add_child(new_page)
	_pages.move_child(new_page, idx)
	new_page.visible = was_visible
	old.visible = false
	old.queue_free()
	if was_visible and new_page.get_child_count() > 0:
		(new_page.get_child(new_page.get_child_count() - 1) as Control).grab_focus()


## ==============================================================================
##  Curseur v4 « piste penchée » (UX-35, UI_DIRECTION_BL3.md §6 « Options :
##  curseur à piste penchée signal ») — remplace `HSlider` pour les pages
##  d'options v4. Piste = parallélogramme cisaillé à 12° (même géométrie que
##  KitSlantBar/KitSlantTile, `Comic.SLANT_DEG`), remplissage `signal` jusqu'à
##  la valeur courante sur fond `plate_hi`, contour encre `Comic.STROKE_INK`.
##  Aucun composant kit équivalent au moment de cette tranche (scripts/ui/kit/
##  hors de la liste de fichiers UX-35) : classe interne privée à ce fichier,
##  même choix que `WeaponSilhouette`/`WeaponTurntable` (BuyMenu.gd).
##  Entrée : glisser-déposer souris (clic n'importe où sur la piste = saut à
##  cette position, comme un HSlider natif) + `ui_left`/`ui_right` au clavier/
##  manette quand le curseur a le focus (mêmes actions que la navigation de
##  menu — jamais un code clavier en dur, cohérent avec le reste du dépôt).
## ==============================================================================
class _V4Slider extends Control:
	signal value_changed(v: float)

	var min_value: float = 0.0
	var max_value: float = 1.0
	var step: float = 0.0
	var value: float = 0.0:
		set(v):
			var clamped := clampf(v, min_value, max_value)
			if step > 0.0:
				clamped = min_value + round((clamped - min_value) / step) * step
				clamped = clampf(clamped, min_value, max_value)
			value = clamped
			queue_redraw()

	var _dragging := false

	func _ready() -> void:
		custom_minimum_size = Vector2(0.0, 28.0)
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		resized.connect(queue_redraw)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	## Parallélogramme cisaillé de `tan(Comic.SLANT_DEG)` sur X — même
	## géométrie que KitSlantBar/KitSlantTile (une seule inclinaison, CHK-38).
	func _slant_points(w: float) -> PackedVector2Array:
		var shear := size.y * tan(deg_to_rad(Comic.SLANT_DEG))
		return PackedVector2Array([
			Vector2(shear, 0.0), Vector2(w + shear, 0.0),
			Vector2(w, size.y), Vector2(0.0, size.y),
		])

	func _ratio() -> float:
		if max_value <= min_value:
			return 0.0
		return clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var track := _slant_points(size.x)
		draw_colored_polygon(track, Comic.plate_hi_color())
		var r := _ratio()
		if r > 0.0:
			draw_colored_polygon(_slant_points(size.x * r), Comic.signal_color())
		var closed := track.duplicate()
		closed.append(track[0])
		draw_polyline(closed, Comic.ink_color(), Comic.STROKE_INK)
		if has_focus():
			var m := Comic.FOCUS_RING_OFFSET_PX
			draw_rect(Rect2(Vector2(-m, -m), size + Vector2(m, m) * 2.0), Comic.paper_color(), false, Comic.STROKE_FOCUS)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				grab_focus()
				_set_from_x(event.position.x)
			accept_event()
		elif event is InputEventMouseMotion and _dragging:
			_set_from_x(event.position.x)
			accept_event()
		elif event.is_action_pressed("ui_left"):
			_apply(value - _nudge())
			accept_event()
		elif event.is_action_pressed("ui_right"):
			_apply(value + _nudge())
			accept_event()

	func _nudge() -> float:
		return step if step > 0.0 else (max_value - min_value) * 0.01

	func _set_from_x(x: float) -> void:
		if size.x <= 0.0:
			return
		var r := clampf(x / size.x, 0.0, 1.0)
		_apply(min_value + r * (max_value - min_value))

	func _apply(v: float) -> void:
		value = v
		value_changed.emit(value)
