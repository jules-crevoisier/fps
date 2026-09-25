## KitCharbonRow.gd
## Kit de composants autocollant (ART-31, docs/STYLE_BIBLE.md §8.2/§8.4) —
## famille « Charbon » (Couche 1, §8.1 : *informer* — lire, régler, comparer) :
## une ligne de liste ou de réglage. Ses 9 états (§8.4, colonne « Charbon
## (liste, réglage) ») :
##   Défaut       — `panel`, trait `rule` 1 px.
##   Survol       — `panel_hi` + puce pinceau à gauche.
##   Focus visible— trait papier 2 px, décalage 4 px (manette/clavier).
##   Pressé       — `panel` assombri de 4 %.
##   Sélectionné  — soulignement pinceau 4 px.
##   Désactivé    — `papier.off` + hachures 45° encre 25 % + RAISON (jamais
##                  vide, CHK-37 : tooltip ET libellé visible).
##   Chargement   — barre pinceau qui se remplit ; après 1 s, « Connexion au
##                  serveur… N s ».
##   Vide         — phrase d'invite + action (« Aucun ami en ligne — INVITER »).
##   Erreur       — ⚠ + « ÉCHEC » + code + RÉESSAYER.
##
## `extends BaseButton` (pas `Button`) : BaseButton ne dessine rien par
## défaut, tout le rendu vient de `_draw()` (mêmes fabriques `Comic.*` que
## ComicPanel/ComicChip) — on garde gratuitement le survol/focus/pression/
## désactivé/l'infobulle NATIFS du moteur (CHK-37) plutôt que de réinventer
## la détection d'entrée à la main.
##
## `state_override` (KitStates.State, -1 = auto) force l'état affiché pour la
## galerie statique (`scenes/dev/ui_kit_gallery.tscn`, capturée par
## `ui_shots` sans souris ni focus manette réels) ; en jeu normal, laisser à
## -1 et piloter `selected`/`loading`/`empty`/`error_text`/`disabled` — le
## survol/focus/pressé viennent alors de l'entrée réelle.
class_name KitCharbonRow
extends BaseButton

const ROW_HEIGHT := 64.0
## Chargement (§8.4) : cycle de remplissage de la barre pinceau, message de
## connexion après 1 s, compte à rebours depuis 3 s (STYLE_BIBLE v3 §8.4 :
## « après 1 s, "Connexion au serveur… 3 s" »).
const LOADING_FILL_DURATION := 1.2
const LOADING_MESSAGE_DELAY := 1.0
const LOADING_COUNTDOWN_FROM := 3
## Largeur réservée, à droite de la barre, pour le message « Connexion au
## serveur… N s » — mesuré (FONT_LABEL, SIZE_FLOOR=21) à 203×26 px pour la
## phrase la plus longue ("…3 s"/"…0 s"), + marge : 116 px (l'ancien 140 px
## moins le pad) tronquait visiblement le texte au milieu d'un mot.
const LOADING_STATUS_W := 250.0

## Émis par l'action « Vide » (INVITER) et l'action « Erreur » (RÉESSAYER) —
## l'appelant décide de ce qu'elles font ; la galerie ne les câble pas.
signal invite_pressed
signal retry_pressed

@export var label_text: String = "":
	set(v):
		label_text = v
		_refresh()
@export var value_text: String = "":
	set(v):
		value_text = v
		_refresh()
## Raison du désactivé — CHK-37 : jamais vide sur un contrôle désactivé.
## Utiliser `set_disabled_with_reason()` plutôt que `disabled` seul pour
## garantir que la raison suit le passage à désactivé.
@export var disabled_reason: String = "":
	set(v):
		disabled_reason = v
		_refresh()
@export var selected: bool = false:
	set(v):
		selected = v
		_refresh()
@export var loading: bool = false:
	set(v):
		loading = v
		_loading_t = 0.0
		_refresh()
@export var empty_prompt: String = "Aucun ami en ligne"
@export var empty_action: String = "INVITER"
@export var empty: bool = false:
	set(v):
		empty = v
		_refresh()
## Non vide => état Erreur ; sert aussi de texte de message.
@export var error_text: String = "":
	set(v):
		error_text = v
		_refresh()
@export var error_code: String = "ERR_500"
## Force un état (KitStates.State) pour la galerie — voir note de classe.
@export var state_override: int = -1:
	set(v):
		state_override = v
		_refresh()

var _held := false
var _loading_t := 0.0

var _main_label: Label
var _value_label: Label
var _reason_label: Label
var _hatch: TextureRect
var _hover_tab: ColorRect
var _loading_track: ColorRect
var _loading_fill: ColorRect
var _loading_label: Label
var _empty_label: Label
var _empty_btn: Button
var _error_label: Label
var _error_retry: Button


func _ready() -> void:
	custom_minimum_size = Vector2(0, ROW_HEIGHT)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_refresh)
	mouse_exited.connect(_refresh)
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	resized.connect(_refresh)

	_main_label = Comic.label("", Comic.SIZE_SUBTITLE, Comic.TEXT)
	add_child(_main_label)

	_value_label = Comic.number_label("", Comic.SIZE_SUBTITLE, Comic.TEXT_DIM)
	add_child(_value_label)

	_reason_label = Comic.label("", Comic.SIZE_FLOOR, Comic.DISABLED)
	add_child(_reason_label)

	_hatch = Comic.hatch_rect(Comic.SP_2, Comic.HARD_SHADOW_COLOR, 0.25)
	add_child(_hatch)

	_hover_tab = ColorRect.new()
	_hover_tab.color = Comic.BRUSH
	_hover_tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hover_tab)

	_loading_track = ColorRect.new()
	_loading_track.color = Comic.PANEL_HI
	_loading_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_loading_track)
	_loading_fill = ColorRect.new()
	_loading_fill.color = Comic.BRUSH
	_loading_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_loading_fill)
	_loading_label = Comic.label("", Comic.SIZE_FLOOR, Comic.TEXT_DIM)
	add_child(_loading_label)

	_empty_label = Comic.label("", Comic.SIZE_BODY, Comic.TEXT_DIM)
	add_child(_empty_label)
	_empty_btn = Button.new()
	_empty_btn.focus_mode = Control.FOCUS_ALL
	_empty_btn.pressed.connect(func() -> void: invite_pressed.emit())
	add_child(_empty_btn)
	UiFx.press(_empty_btn)

	_error_label = Comic.label("", Comic.SIZE_BODY, Comic.OBJECTIVE)
	add_child(_error_label)
	_error_retry = Button.new()
	_error_retry.text = "RÉESSAYER"
	_error_retry.focus_mode = Control.FOCUS_ALL
	_error_retry.pressed.connect(func() -> void: retry_pressed.emit())
	add_child(_error_retry)
	UiFx.press(_error_retry)

	var all_labels: Array[Label] = [_main_label, _value_label, _reason_label, _loading_label, _empty_label, _error_label]
	for lbl in all_labels:
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_refresh()


func _on_button_down() -> void:
	_held = true
	_refresh()


func _on_button_up() -> void:
	_held = false
	_refresh()


## API sûre pour désactiver (CHK-37 : la raison suit toujours le passage à
## désactivé — jamais un `disabled = true` isolé qui laisserait une raison
## vide ou périmée).
func set_disabled_with_reason(reason: String) -> void:
	disabled_reason = reason
	disabled = true
	_refresh()


func enable() -> void:
	disabled = false
	_refresh()


func current_state() -> int:
	if state_override >= 0:
		return state_override
	if error_text != "":
		return KitStates.State.ERROR
	if empty:
		return KitStates.State.EMPTY
	if loading:
		return KitStates.State.LOADING
	if disabled:
		return KitStates.State.DISABLED
	if selected:
		return KitStates.State.SELECTED
	if _held:
		return KitStates.State.PRESSED
	if has_focus():
		return KitStates.State.FOCUS
	if is_hovered():
		return KitStates.State.HOVER
	return KitStates.State.DEFAULT


func _process(delta: float) -> void:
	if current_state() != KitStates.State.LOADING:
		set_process(false)
		return
	_loading_t += delta
	var fill_ratio := clampf(fmod(_loading_t, LOADING_FILL_DURATION) / LOADING_FILL_DURATION, 0.0, 1.0)
	_loading_fill.size = Vector2(_loading_track.size.x * fill_ratio, _loading_track.size.y)
	if _loading_t >= LOADING_MESSAGE_DELAY:
		var remaining := int(ceil(LOADING_COUNTDOWN_FROM - (_loading_t - LOADING_MESSAGE_DELAY)))
		_loading_label.text = "Connexion au serveur… %d s" % maxi(remaining, 0)
	else:
		_loading_label.text = ""


func _refresh() -> void:
	if _main_label == null or not is_inside_tree():
		return
	var s := current_state()
	tooltip_text = disabled_reason if (s == KitStates.State.DISABLED and disabled_reason != "") else ""

	var all_aux: Array = [_value_label, _reason_label, _hatch, _hover_tab, _loading_track, _loading_fill, _loading_label, _empty_label, _empty_btn, _error_label, _error_retry]
	for n: Control in all_aux:
		n.visible = false
	_main_label.visible = true
	_main_label.add_theme_color_override("font_color", Comic.DISABLED if s == KitStates.State.DISABLED else Comic.TEXT)

	var pad: float = Comic.SP_4
	var w := size.x

	match s:
		KitStates.State.EMPTY:
			_main_label.visible = false
			_empty_label.visible = true
			_empty_label.text = empty_prompt
			_layout_left(_empty_label, pad, w - 180.0)
			_empty_btn.visible = true
			_empty_btn.text = empty_action
			_layout_right(_empty_btn, w - 160.0, pad)
		KitStates.State.ERROR:
			_main_label.visible = false
			_error_label.visible = true
			_error_label.text = "⚠ ÉCHEC — %s" % error_code
			_layout_left(_error_label, pad, w - 180.0)
			_error_retry.visible = true
			_layout_right(_error_retry, w - 160.0, pad)
		KitStates.State.LOADING:
			_main_label.text = label_text.to_upper()
			_layout_top(_main_label, pad, w - pad, Comic.SP_1, ROW_HEIGHT * 0.5)
			_loading_track.visible = true
			_loading_fill.visible = true
			_loading_label.visible = true
			var track_top := ROW_HEIGHT - 22.0
			_loading_track.position = Vector2(pad, track_top)
			_loading_track.size = Vector2(maxf(w - pad * 2.0 - LOADING_STATUS_W, 20.0), 8.0)
			_loading_fill.position = _loading_track.position
			_loading_fill.size = Vector2(0.0, _loading_track.size.y)
			# Logé dans la moitié BASSE de la ligne (comme la barre), jamais avec une
			# hauteur héritée de `size.y` (ligne entière) : `_layout_right` donnait une
			# boîte de 64 px repositionnée à `track_top - 6`, qui débordait de 36 px
			# SOUS la ligne -- texte tronqué par le `ScrollContainer` et chevauchant la
			# ligne suivante (bug capturé par `ui_shots` sur la galerie, ART-31 relance
			# QA).
			_loading_label.position = Vector2(w - LOADING_STATUS_W, ROW_HEIGHT * 0.5)
			_loading_label.size = Vector2(LOADING_STATUS_W - pad, ROW_HEIGHT * 0.5)
			set_process(true)
		KitStates.State.DISABLED:
			_main_label.text = label_text.to_upper()
			_layout_left(_main_label, pad, w - 220.0)
			_hatch.visible = true
			_reason_label.visible = true
			_reason_label.text = disabled_reason if disabled_reason != "" else KitStates.DEFAULT_DISABLED_REASON
			_layout_right(_reason_label, w - 200.0, pad)
		_:
			_main_label.text = label_text.to_upper()
			_layout_left(_main_label, pad + (Comic.SP_1 if s == KitStates.State.HOVER else 0.0), w - 220.0)
			_value_label.visible = value_text != ""
			_value_label.text = value_text
			_layout_right(_value_label, w - 200.0, pad)
			_hover_tab.visible = s == KitStates.State.HOVER
			if _hover_tab.visible:
				_hover_tab.position = Vector2.ZERO
				_hover_tab.size = Vector2(4.0, size.y)

	queue_redraw()


func _layout_left(n: Control, left: float, right: float) -> void:
	n.position = Vector2(left, 0.0)
	n.size = Vector2(maxf(right - left, 0.0), size.y)


func _layout_right(n: Control, left: float, pad_right: float) -> void:
	n.position = Vector2(left, 0.0)
	n.size = Vector2(maxf(size.x - pad_right - left, 0.0), size.y)


func _layout_top(n: Control, left: float, right: float, top: float, height: float) -> void:
	n.position = Vector2(left, top)
	n.size = Vector2(maxf(right - left, 0.0), height)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var s := current_state()
	var bg := Comic.PANEL
	var border := Comic.RULE
	match s:
		KitStates.State.HOVER, KitStates.State.FOCUS:
			bg = Comic.PANEL_HI
		KitStates.State.PRESSED:
			bg = Comic.PANEL.darkened(0.04)
		KitStates.State.DISABLED:
			border = Comic.DISABLED
	draw_style_box(Comic.panel_style(bg, border, Comic.PANEL_RADIUS, Comic.RULE_W), Rect2(Vector2.ZERO, size))
	if s == KitStates.State.SELECTED:
		var t := 4.0
		draw_rect(Rect2(Vector2(0.0, size.y - t), Vector2(size.x, t)), Comic.BRUSH, true)
	if s == KitStates.State.FOCUS:
		var m := Comic.FOCUS_RING_OFFSET_PX
		draw_rect(Rect2(Vector2(-m, -m), size + Vector2(m, m) * 2.0), Comic.TEXT, false, 2.0)
