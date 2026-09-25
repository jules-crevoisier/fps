## AmmoPanel.gd
## Case « munitions » (bas-droite, UI_DIRECTION_BL3.md §5) : nom d'arme
## (21, meta caps), chargeur (88) / réserve (37, `paper_dim` — « ∞ » quand la
## réserve est infinie, §5 #4 « pas de valeur de debug », voir
## `Inventory.INFINITE_RESERVE`, le 999999 diagnostiqué en §3.6), pips
## d'inventaire. v4 « Encre, jaune, italique » (UX-31) : remplace le chip
## ComicPanel v3 (fond charbon.bg à 80 %) par des `Label` encrés directement
## sur la 3D (§5 #1 « zéro fond derrière le texte du HUD ») — API PUBLIQUE
## (`update_ammo`/`update_weapon`/`update_inventory`/`show_pickup_toast`)
## INCHANGÉE : `tools/review/ui_shots.gd` (hors de ma liste de fichiers)
## pilote cette classe par réflexion (`hud.get("_ammo_panel")`) avec ces
## quatre signatures exactes — aucun risque de casser cette sonde.
## GF-23 (docs/research/10_ammo_kits_input.md §2.6) : états de la réserve
## (crème/ocre/« VIDE »), invite « [touche] RECHARGER » (chargeur ≤ 25 %, de
## la réserve, 1,5 s après la dernière rafale), invite « [touche] CHANGER
## D'ARME » (chargeur ET réserve à 0), toast de ramassage « +N ARME » (1,2 s,
## `show_pickup_toast`). Toute la logique de seuil/texte est PURE dans
## HudFormat.gd (hors de ma liste de fichiers, testée par
## tests/ui/test_hud_format.gd) ; ce fichier ne fait que lire l'état de ses
## propres appels et peindre le résultat.
class_name AmmoPanel
extends Control

## Réserve infinie (entraînement, `Inventory.RULE_INFINITE`) : sentinelle
## partagée avec Inventory.gd (hors de ma liste de fichiers) — jamais un
## second nombre magique dupliqué ici.
const INFINITE_RESERVE := Inventory.INFINITE_RESERVE
const INFINITE_GLYPH := "∞"
## Durée d'affichage du toast de ramassage (§2.6 : « +N ARME » pendant 1,2 s).
const PICKUP_TOAST_DURATION := 1.2
const _WIDTH := 300.0

var _weapon_label: Label
var _ammo_label: Label
var _reserve_label: Label
var _inv_row: HBoxContainer
## Invite RECHARGER/CHANGER D'ARME (§2.6) — les deux sont mutuellement
## exclusives (CHANGER D'ARME exige chargeur ET réserve à 0, donc rien à
## recharger), un seul label suffit.
var _prompt_label: Label
## Toast « +N ARME » (§2.6), flottant AU-DESSUS du reste (jamais dans le
## VBox : il ne doit pas pousser le reste du contenu quand il apparaît).
var _toast_label: Label

## Taille de chargeur de l'arme active (`WeaponConfig.mag_size`, fournie par
## `update_weapon` — voir GameHUD._on_weapon_changed) : seule donnée qui
## manquait ici pour calculer le ratio de munitions basses. 0 tant qu'aucune
## arme n'a encore été annoncée (jamais de chiffre pinceau avant la première
## arme, faute d'un dénominateur connu).
var _mag_size: int = 0
## Nom de la DERNIÈRE arme annoncée par `update_weapon` — "" tant qu'aucun
## appel n'a encore eu lieu. Sert UNIQUEMENT à détecter un VRAI changement
## d'arme (voir `update_weapon`) : `Weapon._emit_local` (hors de ce lot de
## fichiers) émet le signal `weapon_changed` — donc appelle `update_weapon` —
## à CHAQUE tir et pas seulement au changement d'arme ; sans cette
## déduplication, `_mag_prev`/`_reserve_prev` ci-dessous seraient remis à -1 à
## CHAQUE tir (weapon_changed suit toujours ammo_changed dans `_emit_local`)
## et ni la détection de rafale (RECHARGER « jamais pendant le tir ») ni celle
## d'un ramassage (`show_pickup_toast`) ne fonctionneraient jamais en jeu réel.
var _weapon_name: String = ""
var _current_ammo: int = 0
var _current_reserve: int = 0
## Chargeur du DERNIER appel à `update_ammo` — -1 tant qu'aucun appel n'a
## encore eu lieu, et remis à -1 par `update_weapon` UNIQUEMENT lors d'un VRAI
## changement d'arme (voir la doc de `_weapon_name` — jamais à chaque
## réannonce de la MÊME arme). Sert à détecter une rafale (le chargeur qui
## baisse) pour `_time_since_shot` ci-dessous.
var _mag_prev: int = -1
## Réserve du DERNIER appel à `update_ammo` — même rôle que `_mag_prev` mais
## pour détecter un RAMASSAGE (la réserve qui monte SANS que le chargeur ne
## change, voir `HudFormat.reserve_pickup_magazines`) plutôt qu'une rafale.
var _reserve_prev: int = -1
## Secondes écoulées depuis la dernière rafale détectée (§2.6, voir
## HudFormat.should_show_reload_prompt) — grand au départ : aucune rafale n'a
## encore eu lieu, l'invite RECHARGER peut apparaître dès que l'état le
## justifie autrement.
var _time_since_shot: float = 999.0
var _current_index: int = 0
var _weapon_count: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# `self` couvre tout l'écran (comme RoundPanel.gd) : la case elle-même
	# vit sur le VBox ci-dessous, un vrai `Container` dont `get_minimum_size()`
	# reflète TOUJOURS la hauteur réelle du contenu (contrairement à ce
	# `Control` nu, qui n'a pas de contenu propre à mesurer -- un `Control`
	# ancré sur un simple POINT bas-droite avec une hauteur minimale à 0
	# collapse à une hauteur nulle et pousse tout son contenu hors écran, bug
	# constaté à la capture v4).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Comic.SP_1)
	v.alignment = BoxContainer.ALIGNMENT_END
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.custom_minimum_size = Vector2(_WIDTH, 0.0)
	Comic.anchor(v, Control.PRESET_BOTTOM_RIGHT)
	v.grow_vertical = Control.GROW_DIRECTION_BEGIN
	v.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	v.offset_right = -Comic.SAFE_MARGIN
	v.offset_bottom = -Comic.SAFE_MARGIN
	add_child(v)

	# Toast « +N ARME » (§2.6) -- rangée du VBox comme les autres (PAS un
	# flottant en overlay, voir le commentaire de `self.set_anchors_and_
	# offsets_preset` ci-dessus : un panneau bas-droite dimensionné à son
	# contenu n'a pas de rect propre stable pour ancrer un overlay par-dessus).
	# Un `Container` ignore un enfant `visible = false` pour son calcul de
	# taille -- le toast n'occupe donc aucune place tant qu'il n'est pas
	# affiché, et pousse le reste vers le haut le temps de `PICKUP_TOAST_
	# DURATION` seulement.
	_toast_label = Comic.ink_label("", Comic.SIZE_37, Comic.paper_color(), Comic.number_font_v4())
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast_label.visible = false
	v.add_child(_toast_label)
	v.move_child(_toast_label, 0)

	_weapon_label = Comic.meta_label_v4("", Comic.SIZE_21, Comic.paper_dim_color())
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_weapon_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", Comic.SP_1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	_ammo_label = Comic.ink_label("--", Comic.SIZE_88, Comic.paper_color(), Comic.number_font_v4())
	row.add_child(_ammo_label)
	_reserve_label = Comic.ink_label("/ --", Comic.SIZE_37, Comic.paper_dim_color(), Comic.number_font_v4())
	_reserve_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_reserve_label)

	_prompt_label = Comic.meta_label_v4("", Comic.SIZE_21, Comic.paper_dim_color())
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt_label.visible = false
	v.add_child(_prompt_label)

	_inv_row = HBoxContainer.new()
	_inv_row.alignment = BoxContainer.ALIGNMENT_END
	_inv_row.add_theme_constant_override("separation", Comic.SP_2)
	_inv_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_inv_row)

## Fait vieillir `_time_since_shot` en continu (une rafale en cours le remet
## à 0 à CHAQUE coup via `update_ammo`, voir sa doc) : c'est ce qui garantit
## que l'invite RECHARGER attend bien 1,5 s après le dernier tir plutôt que
## de dépendre d'un état "is_firing" séparé, inaccessible depuis ce panneau
## (GameHUD.gd — qui appelle `update_ammo` — est hors de ce lot de fichiers).
func _process(delta: float) -> void:
	_time_since_shot += delta
	_update_prompt()

func update_ammo(current: int, reserve: int) -> void:
	# Capturé AVANT d'écraser `_mag_prev`/`_reserve_prev` ci-dessous : les deux
	# détections (rafale ET ramassage) comparent contre l'état du DERNIER
	# appel, jamais celui qu'on est en train de peindre.
	var prev_mag := _mag_prev
	if _mag_prev != -1 and current < _mag_prev:
		_time_since_shot = 0.0
	_mag_prev = current
	# Ramassage (§2.6, GF-22) : la réserve qui monte depuis le dernier appel
	# SANS que le chargeur ne change. Toujours 0 tant que `_mag_size` est
	# inconnu ou juste après un VRAI changement d'arme, et toujours 0 pour une
	# réserve infinie (elle ne "monte" jamais au sens d'un ramassage).
	var pickup := 0
	if reserve < INFINITE_RESERVE:
		pickup = HudFormat.reserve_pickup_magazines(prev_mag, current, _reserve_prev, reserve, _mag_size)
	_reserve_prev = reserve
	_current_ammo = current
	_current_reserve = reserve
	if pickup > 0:
		show_pickup_toast(pickup)
	if _ammo_label:
		_ammo_label.text = HudFormat.format_ammo(current)
		var low := _mag_size > 0 and float(current) / float(_mag_size) <= HudFormat.LOW_AMMO_RATIO
		_ammo_label.add_theme_color_override("font_color", Comic.vital_color() if low else Comic.paper_color())
	if _reserve_label:
		_reserve_label.text = _reserve_text(reserve)
		_reserve_label.add_theme_color_override("font_color", _reserve_color(reserve))
	_update_prompt()

## Réserve infinie (entraînement) : « ∞ » plutôt que « / 999999 » (§5 #4,
## bug historique du §3.6 « on voit 999999 »).
func _reserve_text(reserve: int) -> String:
	if reserve >= INFINITE_RESERVE:
		return INFINITE_GLYPH
	return HudFormat.format_reserve_label(reserve)

func _reserve_color(reserve: int) -> Color:
	if reserve >= INFINITE_RESERVE:
		return Comic.paper_dim_color()
	match HudFormat.reserve_state(reserve, _mag_size):
		"empty":
			return Comic.vital_color()
		"low":
			return Comic.signal_color()
		_:
			return Comic.paper_dim_color()

## `mag_size` : `WeaponConfig.mag_size` de l'arme active (0 par défaut) — sert
## au ratio de munitions basses (§5 #4, voir `HudFormat.LOW_AMMO_RATIO`).
func update_weapon(name: String, mag_size: int = 0) -> void:
	if _weapon_label:
		_weapon_label.text = name.to_upper()
	# VRAI changement d'arme seulement si le nom OU la taille de chargeur
	# diffère de la DERNIÈRE annonce (voir la doc de `_weapon_name`) : sinon
	# `update_weapon` est juste une réannonce de la même arme (émise à chaque
	# tir/rechargement par `Weapon._emit_local`, hors de ce lot de fichiers)
	# et ne doit JAMAIS effacer l'état de détection de rafale/ramassage en
	# cours.
	var switched := name != _weapon_name or mag_size != _mag_size
	_weapon_name = name
	_mag_size = mag_size
	if switched:
		# Nouvelle arme : le chargeur/la réserve précédents appartenaient à
		# une autre échelle, jamais une rafale ni un ramassage (voir la doc de
		# `_mag_prev`/`_reserve_prev`).
		_mag_prev = -1
		_reserve_prev = -1
	_update_prompt()

## `weapons` : Array de WeaponConfig (ou null pour un slot vide) ; `current_index` :
## index de l'arme active. Un chiffre par slot (allié = arme active, `paper_dim`
## sinon — sans boîte, juste le chiffre).
func update_inventory(weapons: Array, current_index: int) -> void:
	_current_index = current_index
	_weapon_count = weapons.size()
	_update_prompt()
	if _inv_row == null:
		return
	if _inv_row.get_child_count() != weapons.size():
		for c in _inv_row.get_children():
			c.queue_free()
		for i in weapons.size():
			_inv_row.add_child(Comic.ink_label(str(i + 1), Comic.SIZE_21, Comic.paper_dim_color(), Comic.number_font_v4()))
	for i in weapons.size():
		var lbl: Label = _inv_row.get_child(i)
		var active := i == current_index
		lbl.text = str(i + 1)
		lbl.add_theme_color_override("font_color", Comic.ALLY if active else Comic.paper_dim_color())

## Toast de ramassage (§2.6 « +N ARME », 1,2 s) — `amount` est le nombre de
## chargeurs ajoutés à la réserve (cartouchière/caisse, GF-22 ; le son
## dédié reste sur Audio.gd, hors de ce lot de fichiers). Déclenché
## automatiquement par `update_ammo` (voir sa doc) ; reste une méthode
## publique pour un déclenchement manuel (captures d'écran, tests). Tween
## porté par le nœud lui-même (jamais un `create_timer` avec une lambda qui
## capture un nœud, voir les conventions du projet).
func show_pickup_toast(amount: int) -> void:
	if _toast_label == null or amount <= 0:
		return
	_toast_label.text = HudFormat.format_ammo_pickup_toast(amount)
	_toast_label.visible = true
	var tw := _toast_label.create_tween()
	tw.tween_interval(PICKUP_TOAST_DURATION)
	tw.tween_callback(_toast_label.hide)

## Invite RECHARGER/CHANGER D'ARME (§2.6) — CHANGER D'ARME prime toujours
## (chargeur ET réserve à 0 : il n'y a plus rien à recharger). Jamais
## affichée pour une réserve infinie (rien à changer/recharger, elle ne tombe
## jamais à 0).
func _update_prompt() -> void:
	if _prompt_label == null:
		return
	if _current_reserve >= INFINITE_RESERVE:
		_prompt_label.visible = false
		return
	if HudFormat.should_show_switch_weapon_prompt(_current_ammo, _current_reserve):
		var action := HudFormat.next_weapon_action(_current_index, _weapon_count)
		_prompt_label.text = HudFormat.format_switch_weapon_prompt(KeyLabel.for_action(action))
		_prompt_label.add_theme_color_override("font_color", Comic.vital_color())
		_prompt_label.visible = true
	elif HudFormat.should_show_reload_prompt(_current_ammo, _mag_size, _current_reserve, _time_since_shot):
		_prompt_label.text = HudFormat.format_reload_prompt(KeyLabel.for_action("reload"))
		_prompt_label.add_theme_color_override("font_color", Comic.paper_dim_color())
		_prompt_label.visible = true
	else:
		_prompt_label.visible = false
