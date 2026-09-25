## CrosshairEditor.gd
## Éditeur de viseur (UX-03, docs/research/04_ui_ux.md §2.2 « Réglages de
## viseur Valorant : couleur ; contour (on/off, opacité, épaisseur) ; point
## central (taille, opacité) ; lignes intérieures et extérieures (longueur,
## épaisseur, écart, opacité) ; codes de viseur en import/export »). Ouvert en
## overlay par OptionsMenu.gd (page "Viseur", `_open_crosshair_editor`), même
## patron que PauseMenu._open_options : `signal closed`, fond opaque plein
## écran, "Retour" ferme.
##
## Édite un brouillon (`_draft`, un dictionnaire Crosshair.normalize_settings)
## qui s'écrit IMMÉDIATEMENT dans `Settings.crosshair_settings` + `save_all()`
## à chaque changement (même convention que chaque contrôle d'OptionsMenu.gd —
## jamais de bouton "Enregistrer" séparé) et se reflète EN TEMPS RÉEL sur DEUX
## aperçus (`_sky_crosshair`/`_sand_crosshair`, deux nœuds Crosshair distincts
## posés sur un fond ciel et un fond sable — StyleTokens.MAP_PALETTES,
## "wasteland", la carte par défaut de la tranche verticale, voir
## `_sky_texture`) : chaque curseur/case/préréglage/import appelle
## `_persist_and_refresh_preview()`, qui réapplique `_draft` aux deux nœuds
## via `Crosshair.apply_settings` (redessine, `_draw()` — UX-03).
##
## Le CODE (`_code_field`) est le MÊME mécanisme que la persistance
## (Crosshair.encode/decode, voir Settings.gd) : "Copier" le pose dans le
## presse-papiers, "Importer" décode le texte du champ (jamais le
## presse-papiers OS directement — un simple copier-coller marche déjà via le
## LineEdit natif, et ça reste utilisable en tête headless/sandbox où le
## presse-papiers OS peut être indisponible).
##
## UX-38 (2026-09-25, retour lead §4 « bandeau pinceau rouge à supprimer,
## titre en encre 66 comme OPTIONS ») : `BrushHeader.gd` (bandeau rouge
## « pinceau », hors de la liste de fichiers de cette tâche — LU, jamais
## modifié) est remplacé ici par un simple `Label` v4 (même patron que
## OptionsMenu.gd::_title_label, `Comic.title_label_v4`, capitales italiques
## papier, 66 px) — plus aucun fond pinceau rouge sur cet écran.
extends Control

signal closed

const _PREVIEW_SIZE := Vector2(340, 200)
## Libellés FR des 4 préréglages requis, dans l'ORDRE de `Crosshair.PRESET_IDS`
## (séparation logique/présentation — même patron que Settings.LAYOUT_OPTIONS
## / OptionsMenu._LAYOUT_LABELS).
const _PRESET_LABELS := ["Défaut", "Point", "Croix fine", "Croix épaisse"]

var _draft: Dictionary = {}
var _content: VBoxContainer
var _sky_crosshair: Crosshair
var _sand_crosshair: Crosshair
var _code_field: LineEdit

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_draft = Crosshair.normalize_settings(Settings.crosshair_settings)
	_build()

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

	# UX-38 : titre v4 SANS bandeau pinceau (remplace `BrushHeader`, rouge) —
	# capitales italiques papier, 66 px, zéro fond (voir la docstring de tête).
	var title_label := Comic.title_label_v4("Éditeur de viseur", Comic.SIZE_66, Comic.paper_color())
	root.add_child(title_label)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("margin_top", Comic.SP_2)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := Button.new()
	back.text = "Retour"
	back.custom_minimum_size = Vector2(120, 38)
	back.pressed.connect(func(): closed.emit())
	UiFx.press(back)
	header_row.add_child(spacer)
	header_row.add_child(back)
	root.add_child(header_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", Comic.SP_3)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	_rebuild_content()

## Reconstruit TOUT le contenu défilable depuis `_draft` — appelé au premier
## affichage et après tout changement qui touche PLUSIEURS champs à la fois
## (préréglage, import de code) : un simple curseur déplacé n'appelle JAMAIS
## ceci (voir `_slider_row`/`_check_row`), pour ne pas faire sauter le focus
## clavier/manette ni la position de défilement pendant un réglage fin.
func _rebuild_content() -> void:
	for c in _content.get_children():
		c.queue_free()

	_content.add_child(_build_previews())
	_content.add_child(_build_presets())

	_content.add_child(Comic.bullet_row("Couleur"))
	var picker := ColorPickerButton.new()
	picker.edit_alpha = false  # UX-03 : l'alpha de base est toujours 1, voir Crosshair.normalize_settings
	picker.color = _draft.color
	picker.custom_minimum_size = Vector2(80, 40)
	picker.color_changed.connect(func(c: Color):
		_draft.color = c
		_persist_and_refresh_preview())
	_content.add_child(picker)

	_content.add_child(HSeparator.new())
	_content.add_child(Comic.bullet_row("Contour"))
	_content.add_child(_check_row("Activé", "outline_enabled"))
	_content.add_child(_slider_row("Opacité", "outline_opacity", 0.0, 1.0, 0.05, _fmt_pct))
	_content.add_child(_slider_row("Épaisseur", "outline_thickness", 0.5, 4.0, 0.5, _fmt_px))

	_content.add_child(HSeparator.new())
	_content.add_child(Comic.bullet_row("Point central"))
	_content.add_child(_check_row("Activé", "dot_enabled"))
	_content.add_child(_slider_row("Taille", "dot_size", 1.0, 16.0, 0.5, _fmt_px))
	_content.add_child(_slider_row("Opacité", "dot_opacity", 0.0, 1.0, 0.05, _fmt_pct))

	_content.add_child(HSeparator.new())
	_content.add_child(Comic.bullet_row("Lignes intérieures"))
	_content.add_child(_check_row("Activées", "inner_enabled"))
	_content.add_child(_slider_row("Longueur", "inner_length", 1.0, 24.0, 0.5, _fmt_px))
	_content.add_child(_slider_row("Épaisseur", "inner_thickness", 0.5, 8.0, 0.5, _fmt_px))
	_content.add_child(_slider_row("Écart", "inner_gap", 0.0, 24.0, 0.5, _fmt_px))
	_content.add_child(_slider_row("Opacité", "inner_opacity", 0.0, 1.0, 0.05, _fmt_pct))

	_content.add_child(HSeparator.new())
	_content.add_child(Comic.bullet_row("Lignes extérieures"))
	_content.add_child(_check_row("Activées", "outer_enabled"))
	_content.add_child(_slider_row("Longueur", "outer_length", 1.0, 24.0, 0.5, _fmt_px))
	_content.add_child(_slider_row("Épaisseur", "outer_thickness", 0.5, 8.0, 0.5, _fmt_px))
	_content.add_child(_slider_row("Écart", "outer_gap", 0.0, 32.0, 0.5, _fmt_px))
	_content.add_child(_slider_row("Opacité", "outer_opacity", 0.0, 1.0, 0.05, _fmt_pct))

	_content.add_child(HSeparator.new())
	var static_check := CheckButton.new()
	static_check.text = "Réticule statique (ignore la dispersion réelle de l'arme, purement cosmétique)"
	static_check.button_pressed = Settings.static_crosshair
	static_check.toggled.connect(func(on: bool):
		Settings.static_crosshair = on
		Settings.save_all()
		if _sky_crosshair: _sky_crosshair.static_mode = on
		if _sand_crosshair: _sand_crosshair.static_mode = on)
	_content.add_child(static_check)

	_content.add_child(HSeparator.new())
	_content.add_child(Comic.bullet_row("Code du viseur (import/export)"))
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", Comic.SP_2)
	_code_field = LineEdit.new()
	_code_field.editable = true
	_code_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_field.custom_minimum_size = Vector2(320, 40)
	code_row.add_child(_code_field)
	code_row.add_child(_btn("Copier", func(): DisplayServer.clipboard_set(_code_field.text)))
	code_row.add_child(_btn("Importer", _import_code))
	_content.add_child(code_row)
	_content.add_child(Comic.label("« Importer » lit le code tapé/collé ci-dessus.", Comic.SIZE_FLOOR, Comic.DISABLED, Comic.FONT_BODY))

	_persist_and_refresh_preview()

# ----------------------------------------------------------- APERÇU (ciel + sable, temps réel)
## Deux aperçus côte à côte (docs/research/04_ui_ux.md tâche UX-03 : "l'aperçu
## change en temps réel sur un fond ciel + un fond sable") — palette
## `StyleTokens.MAP_PALETTES["wasteland"]` (carte par défaut de la tranche
## verticale, mémoire "vertical slice priority"), jamais une couleur inventée.
func _build_previews() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Comic.SP_3)

	var palette: Dictionary = StyleTokens.MAP_PALETTES[StyleTokens.DEFAULT_MAP_ID]

	var sky_bg := TextureRect.new()
	sky_bg.texture = _sky_texture(palette["sky_zenith"], palette["sky_horizon"])
	sky_bg.stretch_mode = TextureRect.STRETCH_SCALE
	sky_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var sky := _build_preview("Fond ciel", sky_bg)
	_sky_crosshair = sky.crosshair

	var sand_bg := ColorRect.new()
	sand_bg.color = palette["ground"]
	var sand := _build_preview("Fond sable", sand_bg)
	_sand_crosshair = sand.crosshair

	row.add_child(sky.wrap)
	row.add_child(sand.wrap)
	return row

## Une colonne d'aperçu : titre à puce, boîte qui rogne (`clip_contents`) avec
## le fond fourni en plein cadre et un nœud Crosshair centré par-dessus, prêt
## à recevoir `apply_settings()` (voir `_persist_and_refresh_preview`).
func _build_preview(title: String, background: Control) -> Dictionary:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", Comic.SP_1)
	wrap.add_child(Comic.bullet_row(title))
	var box := Control.new()
	box.custom_minimum_size = _PREVIEW_SIZE
	box.clip_contents = true
	Comic.anchor(background, Control.PRESET_FULL_RECT)
	box.add_child(background)
	var cross := Crosshair.new()
	Comic.anchor(cross, Control.PRESET_CENTER)
	box.add_child(cross)
	wrap.add_child(box)
	return {"wrap": wrap, "crosshair": cross}

## Dégradé ciel (zénith en haut -> horizon en bas) — même patron que
## GameHUD._build_scope (Image.create + set_pixel + ImageTexture.
## create_from_image, jamais Gradient/GradientTexture2D, pour rester cohérent
## avec l'unique autre texture procédurale déjà posée par ce module).
func _sky_texture(zenith: Color, horizon: Color) -> ImageTexture:
	var w := 4
	var h := 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(h - 1)
		var c := zenith.lerp(horizon, t)
		for x in w:
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

# ----------------------------------------------------------- PRÉRÉGLAGES (UX-03)
func _build_presets() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_1)
	v.add_child(Comic.bullet_row("Préréglages"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Comic.SP_2)
	for i in Crosshair.PRESET_IDS.size():
		var id: String = Crosshair.PRESET_IDS[i]
		row.add_child(_btn(_PRESET_LABELS[i], _apply_preset.bind(id)))
	v.add_child(row)
	return v

func _apply_preset(id: String) -> void:
	_draft = Crosshair.normalize_settings(Crosshair.PRESETS.get(id, Crosshair.DEFAULT_SETTINGS))
	Settings.crosshair_settings = _draft
	Settings.save_all()
	_rebuild_content()

## Décode `_code_field.text` (Crosshair.decode — jamais un plantage, un code
## invalide retombe sur `DEFAULT_SETTINGS`, voir sa doc) et l'applique comme
## nouveau brouillon.
func _import_code() -> void:
	_draft = Crosshair.decode(_code_field.text)
	Settings.crosshair_settings = _draft
	Settings.save_all()
	_rebuild_content()

# ----------------------------------------------------------- PERSISTANCE + APERÇU TEMPS RÉEL
## Écrit `_draft` (normalisé) dans `Settings.crosshair_settings` + sauvegarde,
## puis réapplique aux DEUX aperçus (`Crosshair.apply_settings`, redessine via
## `_draw()`) et rafraîchit le champ code — appelé par CHAQUE contrôle
## (curseur glissé, case cochée, préréglage, import), jamais différé : c'est
## ce qui rend l'aperçu "temps réel" (acceptance UX-03).
func _persist_and_refresh_preview() -> void:
	_draft = Crosshair.normalize_settings(_draft)
	Settings.crosshair_settings = _draft
	Settings.save_all()
	if _sky_crosshair and is_instance_valid(_sky_crosshair):
		_sky_crosshair.apply_settings(_draft)
	if _sand_crosshair and is_instance_valid(_sand_crosshair):
		_sand_crosshair.apply_settings(_draft)
	if _code_field:
		_code_field.text = Crosshair.encode(_draft)

# ----------------------------------------------------------- CONTRÔLES GÉNÉRIQUES
## Ligne étiquette + curseur + valeur formatée, liée à `_draft[key]` (float) —
## `fmt` formate la valeur affichée (`_fmt_px`/`_fmt_pct`). Ne touche JAMAIS
## `_rebuild_content()` (voir sa doc) : seul `_persist_and_refresh_preview`
## tourne à chaque glissement, le curseur garde le focus pendant le réglage.
func _slider_row(label_text: String, key: String, min_v: float, max_v: float, step: float, fmt: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Comic.SP_3)
	var name_lbl := Comic.label(label_text, Comic.SIZE_BODY, Comic.TEXT, Comic.FONT_BODY)
	name_lbl.custom_minimum_size = Vector2(140, 0)
	row.add_child(name_lbl)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step
	sl.value = float(_draft.get(key, min_v))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sl)
	var val_lbl: String = fmt.call(sl.value)
	var lbl := Comic.number_label(val_lbl, Comic.SIZE_FLOOR, Comic.TEXT)
	lbl.custom_minimum_size = Vector2(64, 0)
	row.add_child(lbl)
	sl.value_changed.connect(func(x: float):
		_draft[key] = x
		lbl.text = fmt.call(x)
		_persist_and_refresh_preview())
	return row

## Case à cocher liée à `_draft[key]` (bool).
func _check_row(label_text: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = label_text
	c.button_pressed = bool(_draft.get(key, false))
	c.toggled.connect(func(on: bool):
		_draft[key] = on
		_persist_and_refresh_preview())
	return c

func _fmt_px(v: float) -> String:
	return "%.1f px" % v

func _fmt_pct(v: float) -> String:
	return "%d %%" % int(round(v * 100.0))

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(cb)
	UiFx.press(b)
	return b
