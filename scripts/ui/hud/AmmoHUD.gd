## AmmoHUD.gd
## Panneau de munitions (contrat lead 2026-09-27, HUD en jeu, point 2) —
## bas-droite : icône autocollante de l'arme, munitions du chargeur en
## display T_4XL + "/ réserve" T_L, pastilles (une par balle, chargeur <= 12
## seulement), état de rechargement ("RECHARGE"), chargeur vide -> chiffre
## ROUGE. Ligne d'indice sous les munitions (touches "Éventail"/"Recharger"),
## visible seulement les 5 premières secondes après l'équipement OU sous 1/3
## de chargeur (`show_hint`, fonction PURE). Une grenade équipée remplace
## l'icône/le chiffre par l'autocollant + le compte de CETTE grenade (le fil
## de munitions d'arme disparaît, `show_grenade`).
class_name AmmoHUD
extends Control

const _GUN_ICON_PX := 70.0
const _PIP_W := 14.0
const _PIP_H := 30.0
const _MAX_PIPS_SHOWN := 12
const _HINT_AFTER_EQUIP_S := 5.0
const _HINT_LOW_FRACTION := 1.0 / 3.0

## Hauteur totale du panneau (munitions + indice), épinglée en bas-droite : la colonne garde
## cette hauteur même quand une rangée disparaît (mode grenade), pour que le chiffre ne saute pas.
const TOTAL_HEIGHT := 262.0   # mesuré en jeu : pastilles 30 + chiffre Bangers 135 px (~165) + indice 40 + écarts

var _icon: TextureRect
var _ammo_label: Label
var _reserve_label: Label
var _pips_row: HBoxContainer
var _pips: Array = []
var _reload_label: Label
var _fan_hint: Control
var _reload_hint: Control
var _hint_row: HBoxContainer

var _mag_size: int = 0
var _time_since_equip: float = 0.0
var _last_ammo: int = 0
var _is_fan_weapon: bool = false
var _showing_grenade: bool = false


## Une pastille par balle : `true` = dépensée (assombrie), une par index >=
## `ammo` (les premières `ammo` restent pleines). Fonction PURE, testée
## directement.
static func pip_states(ammo: int, mag_size: int) -> Array:
	var out: Array = []
	for i in mag_size:
		out.append(i >= ammo)
	return out


## Les pastilles ne s'affichent QUE sous un petit chargeur (contrat point 2 :
## "when mag_size <= 12") — un chargeur de 30 ferait 30 pastilles illisibles.
static func show_pips(mag_size: int) -> bool:
	return mag_size > 0 and mag_size <= _MAX_PIPS_SHOWN


## L'indice (touches) reste visible les 5 premières secondes après
## l'équipement, OU tant que le chargeur est sous 1/3 (contrat point 2).
static func show_hint(time_since_equip: float, ammo: int, mag_size: int) -> bool:
	if time_since_equip < _HINT_AFTER_EQUIP_S:
		return true
	if mag_size <= 0:
		return false
	return float(ammo) / float(mag_size) <= _HINT_LOW_FRACTION


static func is_empty(ammo: int) -> bool:
	return ammo <= 0


func _ready() -> void:
	Comic.anchor(self, Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _process(delta: float) -> void:
	_time_since_equip += delta
	if not _showing_grenade:
		_hint_row.visible = show_hint(_time_since_equip, _last_ammo, _mag_size)


func _build() -> void:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTokens.S2)
	# Épingle le contenu au BAS de la colonne (hauteur fixe `TOTAL_HEIGHT`,
	# voir sa doc) même quand une rangée disparaît (`_hint_row`/pastilles
	# masqués en mode grenade, `show_grenade`) -- sinon le fil de munitions
	# remonterait vers la rangée d'inventaire au-dessus dès que ces rangées
	# ne comptent plus dans la disposition.
	col.alignment = BoxContainer.ALIGNMENT_END
	col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	col.offset_right = -UiTokens.EDGE_MARGIN
	col.offset_bottom = -UiTokens.EDGE_MARGIN
	col.offset_left = col.offset_right - 560.0
	col.offset_top = col.offset_bottom - TOTAL_HEIGHT
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(col)

	col.add_child(_build_ammo_row())
	col.add_child(_build_hint_row())


func _build_ammo_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", UiTokens.S3)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(0, _GUN_ICON_PX)
	_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# hauteur FIXE en bas de rangée : étirée sur toute la rangée (pastilles + gros chiffre), l'icône
	# grossissait jusqu'à chevaucher l'inventaire (revue lead des captures)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_icon)

	var numbers := VBoxContainer.new()
	numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# petit écart positif : à -26 les pastilles touchaient le chiffre et « RECHARGE » les
	# chevauchait (retour utilisateur 2026-09-27)
	numbers.add_theme_constant_override("separation", 2)
	numbers.alignment = BoxContainer.ALIGNMENT_END

	_reload_label = UiTokens.make_label("RECHARGE", UiTokens.label(UiTokens.T_M, UiTokens.YELLOW, 3, true), true)
	_reload_label.visible = false
	numbers.add_child(_reload_label)

	_pips_row = HBoxContainer.new()
	_pips_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips_row.add_theme_constant_override("separation", 5)
	numbers.add_child(_pips_row)

	var count_row := HBoxContainer.new()
	count_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_row.alignment = BoxContainer.ALIGNMENT_END
	count_row.add_theme_constant_override("separation", UiTokens.S2)
	_ammo_label = UiTokens.make_label("0", UiTokens.display(UiTokens.T_4XL, UiTokens.PAPER))
	count_row.add_child(_ammo_label)
	_reserve_label = UiTokens.make_label("/ 0", UiTokens.display(UiTokens.T_L, UiTokens.PAPER))
	_reserve_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count_row.add_child(_reserve_label)
	numbers.add_child(count_row)

	row.add_child(numbers)
	return row


func _build_pip(spent: bool) -> Control:
	var pip := PanelContainer.new()
	pip.custom_minimum_size = Vector2(_PIP_W, _PIP_H)
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color := UiTokens.INK_SOFT if spent else UiTokens.YELLOW
	pip.add_theme_stylebox_override("panel", UiTokens.plate(color, UiTokens.SKEW_DEG, UiTokens.DROP_SMALL, 3.0, Vector2.ZERO))
	return pip


func _build_hint_row() -> HBoxContainer:
	_hint_row = HBoxContainer.new()
	_hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_row.alignment = BoxContainer.ALIGNMENT_END
	_hint_row.add_theme_constant_override("separation", UiTokens.S2)

	_fan_hint = _build_hint_chip("Clic D", "Éventail")
	_fan_hint.visible = false
	_hint_row.add_child(_fan_hint)

	_reload_hint = _build_hint_chip(Settings.label_for_physical(KEY_R), "Recharger")
	_hint_row.add_child(_reload_hint)
	return _hint_row


func _build_hint_chip(key_text: String, label_text: String) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_constant_override("separation", UiTokens.S1)

	var key := PanelContainer.new()
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.PAPER, 0.0, UiTokens.DROP_SMALL, UiTokens.STROKE, Vector2(UiTokens.S1, 2)))
	key.add_child(UiTokens.make_label(key_text, UiTokens.label(UiTokens.T_XS, UiTokens.INK, 0, true)))
	chip.add_child(key)

	chip.add_child(UiTokens.make_label(label_text, UiTokens.label(UiTokens.T_S, UiTokens.PAPER, 3, true), true))
	return chip


## GameHUD.gd -> Weapon.ammo_changed(ammo, reserve) + Weapon.cfg().mag_size.
func update_ammo(ammo: int, reserve: int, mag_size: int) -> void:
	_showing_grenade = false
	_mag_size = mag_size
	_last_ammo = ammo
	_reserve_label.visible = true
	_ammo_label.text = str(ammo)
	_reserve_label.text = "/ %d" % reserve
	var empty := is_empty(ammo)
	_ammo_label.label_settings = UiTokens.display(UiTokens.T_4XL, UiTokens.RED if empty else UiTokens.PAPER)
	_rebuild_pips(ammo, mag_size)


func _rebuild_pips(ammo: int, mag_size: int) -> void:
	for p in _pips:
		(p as Control).queue_free()
	_pips.clear()
	_pips_row.visible = show_pips(mag_size)
	if not _pips_row.visible:
		return
	for spent in pip_states(ammo, mag_size):
		var pip := _build_pip(spent)
		_pips.append(pip)
		_pips_row.add_child(pip)


## GameHUD.gd -> Weapon.reload_started/ammo_changed (fin de rechargement).
## Pendant le rechargement, « RECHARGE » prend la place des pastilles (jamais les deux empilés).
func set_reloading(reloading: bool) -> void:
	_reload_label.visible = reloading
	_pips_row.visible = not reloading and show_pips(_mag_size)


## GameHUD.gd -> Weapon.weapon_changed(cfg) : icône + relance le minuteur
## d'indice (contrat : "the first 5 s after equip") + indice éventail
## seulement pour une arme FAN.
func set_weapon(cfg: WeaponConfig) -> void:
	_showing_grenade = false
	_reserve_label.visible = true
	_time_since_equip = 0.0
	if cfg == null:
		_icon.texture = null
		_is_fan_weapon = false
		_fan_hint.visible = false
		return
	_icon.texture = UiTokens.icon(WeaponIcon.sticker(cfg.weapon_name))
	_is_fan_weapon = cfg.has_fan_fire()
	_fan_hint.visible = _is_fan_weapon
	_mag_size = cfg.mag_size


## GameHUD.gd -> UtilityThrower.equipped_changed(kind) quand une grenade est
## en main : remplace l'icône/le chiffre par SON autocollant + compte, cache
## la réserve (une grenade n'en a pas) et l'indice de rechargement/éventail
## (aucun sens pour une grenade, `Weapon.gd` bloque déjà tir/rechargement).
func show_grenade(kind: int, count: int) -> void:
	_showing_grenade = true
	_icon.texture = UiTokens.icon(WeaponIcon.grenade_stem(kind) + "_sticker")
	_ammo_label.text = str(count)
	_ammo_label.label_settings = UiTokens.display(UiTokens.T_4XL, UiTokens.PAPER)
	_reserve_label.visible = false
	_pips_row.visible = false
	_reload_label.visible = false
	_hint_row.visible = false
