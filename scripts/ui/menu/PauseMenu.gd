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


func _ready() -> void:
	layer = 50
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
	return col


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
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
