## PauseMenu.gd
## Menu pause EN PARTIE — CanvasLayer autonome (voile sombre + plaques BD
## REPRENDRE / PARAMÈTRES (SettingsPanel embarqué) / QUITTER VERS LE SALON /
## QUITTER LE JEU). N'ouvre PAS tout seul sur Échap : c'est le lead qui câble
## la touche dans scripts/ui/GameHUD.gd (fichier hors du périmètre de cette
## tâche — voir le README du dossier lobby/menus). Ce fichier ne fait
## qu'écouter Échap pour SE FERMER (ou revenir de son sous-panneau Paramètres
## aux boutons) une fois DÉJÀ ouvert — jamais pour s'ouvrir tout seul.
##
## Instanciation (pour le lead) :
##   var pause := PauseMenu.new()
##   some_persistent_node.add_child(pause)   # ex. GameHUD ou GameWorld
##   # sur Échap, dans GameHUD._unhandled_input (ou équivalent) :
##   if pause.is_open():
##       pause.close()
##   else:
##       pause.open()
##
## Réseau autoritaire serveur (voir CLAUDE.md du projet) : ce menu ne met
## JAMAIS la simulation en pause (`get_tree().paused`) — un client qui gèlerait
## le jeu localement désynchroniserait immédiatement une partie hébergée par
## le serveur. Seule l'interface s'affiche et la souris se libère ; la partie
## continue en arrière-plan, comme dans la plupart des FPS multijoueur à
## serveur autoritaire.
class_name PauseMenu
extends CanvasLayer

var _open: bool = false
var _veil: ColorRect
var _buttons_panel: Control
var _settings_wrap: Control
var _settings_panel: SettingsPanel
var _mouse_mode_before_open: int = Input.MOUSE_MODE_VISIBLE
## Rangée « Prochaine arme » (retour de test 2026-09-28 : changer d'arme en pleine partie) —
## reconstruite à chaque ouverture et après chaque choix, pour surligner le choix en cours.
var _primary_slot: VBoxContainer
var _primary_row: HFlowContainer


func _ready() -> void:
	layer = 50
	add_to_group("pause_menu")   # lu par DeathScreen pour recapturer la souris au bon moment
	_build()
	visible = false


func _build() -> void:
	_veil = ColorRect.new()
	_veil.color = Color(UiTokens.INK.r, UiTokens.INK.g, UiTokens.INK.b, 0.65)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_veil)

	_buttons_panel = _build_buttons()
	add_child(_buttons_panel)

	_settings_wrap = Control.new()
	_settings_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_wrap.visible = false
	_settings_panel = SettingsPanel.new()
	_settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_wrap.add_child(_settings_panel)
	var back_btn := MenuWidgets.comic_button("Retour", UiTokens.PAPER)
	back_btn.position = Vector2(48, 48)
	back_btn.pressed.connect(_show_buttons)
	_settings_wrap.add_child(back_btn)
	add_child(_settings_wrap)


func _build_buttons() -> Control:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-260, -240)
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", UiTokens.S2)

	var title := UiTokens.make_label("Pause", UiTokens.display(UiTokens.T_2XL, UiTokens.PAPER, 8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(520, 0)
	col.add_child(title)

	var resume := MenuWidgets.comic_button("Reprendre", UiTokens.YELLOW, UiTokens.T_L)
	resume.pressed.connect(close)
	var settings_btn := MenuWidgets.comic_button("Paramètres", UiTokens.PAPER, UiTokens.T_L)
	settings_btn.pressed.connect(_show_settings)
	var lobby := MenuWidgets.comic_button("Quitter vers le salon", UiTokens.PAPER, UiTokens.T_L)
	lobby.pressed.connect(_on_quit_to_lobby)
	var quit := MenuWidgets.comic_button("Quitter le jeu", UiTokens.PAPER, UiTokens.T_L)
	quit.pressed.connect(func() -> void: get_tree().quit())

	for b in [resume, settings_btn, lobby, quit]:
		b.custom_minimum_size = Vector2(520, 80)
		col.add_child(b)

	# Prochaine arme, juste sous « Reprendre » : prise à la prochaine réapparition (jamais en vie).
	_primary_slot = VBoxContainer.new()
	_primary_slot.add_theme_constant_override("separation", UiTokens.S1)
	var caption := UiTokens.make_label("Prochaine arme · à la réapparition",
			UiTokens.label(UiTokens.T_XS, UiTokens.PAPER, int(UiTokens.STROKE * 0.5), true), true)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_primary_slot.add_child(caption)
	col.add_child(_primary_slot)
	col.move_child(_primary_slot, resume.get_index() + 1)
	_rebuild_primary_row()
	return col


func _rebuild_primary_row() -> void:
	var names: Array = []
	for id in Loadout.available_primary_ids():
		names.append(Loadout.name_for_primary_id(id))
	if _primary_row == null or not is_instance_valid(_primary_row) or _primary_row.get_meta("names", []) != names:
		if _primary_row != null and is_instance_valid(_primary_row):
			_primary_slot.remove_child(_primary_row)
			_primary_row.queue_free()
		_primary_row = MenuWidgets.segmented(names, names, Settings.selected_primary, _on_primary_chosen)
		_primary_row.custom_minimum_size = Vector2(520, 0)
		_primary_row.alignment = FlowContainer.ALIGNMENT_CENTER
		_primary_row.set_meta("names", names)
		_primary_slot.add_child(_primary_row)
		return
	# Même liste : on ne fait que déplacer le surlignage (aucun nœud recréé).
	var i := 0
	for b in _primary_row.get_children():
		if b is Button:
			MenuWidgets.apply_plate_states(b, UiTokens.YELLOW if names[i] == Settings.selected_primary else UiTokens.PAPER, 0.0)
			for st in ["normal", "hover", "pressed", "focus", "disabled"]:
				var sb := (b as Button).get_theme_stylebox(st) as StyleBoxComic
				if sb:
					sb.pad = Vector2(12, 5)
			i += 1


## Même effet que la colonne de l'écran de mort : persiste le choix ET prévient le serveur,
## qui l'applique à la prochaine réapparition.
func _on_primary_chosen(wname: String) -> void:
	Settings.selected_primary = wname
	Settings.save_all()
	var match_node := get_tree().get_first_node_in_group("match") if is_inside_tree() else null
	if match_node and match_node.has_method("request_primary_weapon"):
		match_node.request_primary_weapon(Loadout.primary_id_for_name(wname))
	_rebuild_primary_row()


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_rebuild_primary_row()
	_show_buttons()
	_mouse_mode_before_open = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	Input.mouse_mode = _mouse_mode_before_open


func is_open() -> bool:
	return _open


func _show_buttons() -> void:
	_buttons_panel.visible = true
	_settings_wrap.visible = false


func _show_settings() -> void:
	_buttons_panel.visible = false
	_settings_wrap.visible = true


func _on_quit_to_lobby() -> void:
	var net := NetworkManager.get_net(get_tree())
	net.disconnect_from_game()
	close()
	# close() rétablit le mode d'avant l'ouverture (capturé en partie) : pas pour aller au salon
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		if _settings_wrap.visible:
			_show_buttons()
		else:
			close()
		get_viewport().set_input_as_handled()
