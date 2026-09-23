## MainMenu.gd — Lobby v2 « Peint au soleil, encré gras » (design.md §11).
## Scène 3D en fond (podiums + vrais modèles d'agent qui posent en Idle,
## caméra qui balance) avec une UI charcoal/pinceau par-dessus : barre
## d'onglets (JOUER / AGENTS / ARSENAL / OPTIONS, cyclables au LB/RB) + carte
## de partie. La carte de partie écrit MatchConfig (mode, carte MapCatalog,
## bots, difficulté) puis change de scène vers la carte choisie.
extends Node3D

## Repli tant que R3-MAPS n'a pas livré MapCatalog.gd (chargement dynamique :
## voir `_map_catalog()` — pas de dépendance statique pour ne jamais casser
## le boot si le fichier n'existe pas encore).
const MAP_CATALOG_PATH := "res://scripts/levels/maps/MapCatalog.gd"
const FALLBACK_SCENES := {
	"tdm": "res://scenes/levels/tdm_map.tscn",
	"hardpoint": "res://scenes/levels/comp_map.tscn",
	"snd": "res://scenes/levels/snd_map.tscn",
	"duel": "res://scenes/levels/duel_arena.tscn",
	"duo": "res://scenes/levels/duel_arena.tscn",
}
const MODE_LABELS := {
	"tdm": "Arène — Match à mort",
	"hardpoint": "Arène — Hardpoint",
	"snd": "Tactique — Recherche & Destruction",
	"duel": "Duel (1v1)",
	"duo": "Duo (2v2)",
}
## Étiquettes courtes pour le sélecteur segmenté (compact, 1 ligne par mode —
## retour lead R3 : la liste verticale à description faisait déborder la carte).
const SHORT_MODE_LABELS := {
	"tdm": "Arène",
	"hardpoint": "Hardpoint",
	"snd": "Tactique",
	"duel": "Duel",
	"duo": "Duo",
}
const MODE_DESCRIPTIONS := {
	"tdm": "4v4 sans économie, capacités actives. Premier à 40 éliminations.",
	"hardpoint": "4v4, capture un point qui se déplace toutes les 60 s.",
	"snd": "4v4 par manches, achat d'armes, pose/désamorçage de bombe.",
	"duel": "1 contre 1, sans capacités, équipement imposé.",
	"duo": "2 contre 2, sans capacités, équipement imposé.",
}
const DIFFICULTY_LABELS := ["Recrue", "Vétéran", "Élite"]

## Numérotation des cartes (design.md v2 §7, ordre du catalogue "flagship
## d'abord") — affichage "07. WASTELAND" (voir les feuilles de référence).
## Indépendant de l'ORDRE de MapCatalog.all() (lu, jamais modifié ici) :
## reste correct même si une carte listée ici n'existe pas encore côté
## MapCatalog (Wasteland/Cargo Ship, en cours d'ajout par la tranche cartes).
const MAP_NUMBERS := {
	"port_ferraille": 1, "val_poussiere": 2, "saint_ombre": 3,
	"col_du_vautour": 4, "la_fosse": 5, "le_belvedere": 6,
	"wasteland": 7, "cargo_ship": 8,
}

const OPTIONS_SCRIPT := preload("res://scripts/ui/OptionsMenu.gd")
const ARSENAL_SCRIPT := preload("res://scripts/ui/ArsenalMenu.gd")
const AGENT_SCRIPT := preload("res://scripts/ui/AgentMenu.gd")

const TAB_PLAY := 0
const TAB_AGENTS := 1
const TAB_ARSENAL := 2
const TAB_OPTIONS := 3
const TAB_LABELS := ["JOUER", "AGENTS", "ARSENAL", "OPTIONS"]

const CHAR_MODEL_DIR := "res://assets/models/characters/"

var _mode_id: String = MatchConfig.mode_id
var _map_choice: Dictionary = {}
var _mode_cards: Array = []
var _map_cards: Array = []
var _map_list: GridContainer
var _diff_buttons: Array = []
var _bots_check: CheckButton
var _host_btn: Button
var _ip_field: LineEdit
var _status: ComicPanel
var _status_label: Label
var _retry_btn: Button
var _retry_action: Callable = Callable()
var _net: NetworkManager
var _loading_t: float = -1.0

# UI
var _tab_index: int = TAB_PLAY
var _tabs: Array = []
var _content: Control
var _play_panel: Control
var _embedded: Control

# Décor 3D
var _cam: Camera3D
var _podium_root: Node3D
var _chars: Array = []
var _last_agent_shown: int = -1
var _t: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Settings.load_all()
	_net = NetworkManager.get_net(get_tree())
	_net.disconnect_from_game()
	_net.connection_succeeded.connect(_on_connected)
	_net.connection_failed.connect(_on_failed)
	_build_world()
	_build_ui()
	_show_tab(TAB_PLAY)
	call_deferred("_focus_play")

func _process(delta: float) -> void:
	_t += delta
	if _cam:
		var sway := sin(_t * 0.22) * 1.5
		_cam.position = Vector3(sway, 2.35, 7.6)
		_cam.look_at(Vector3(sway * 0.25, 1.35, 0))
	for i in _chars.size():
		var c: Node3D = _chars[i]
		if not is_instance_valid(c):
			continue
		c.position.y = 0.06 + sin(_t * 1.8 + float(i) * 1.3) * 0.05
		c.rotation.y = sin(_t * 0.5 + float(i)) * 0.14
	if _tab_index == TAB_PLAY and AgentDatabase.selected_index != _last_agent_shown:
		_refresh_lobby_characters()
	if _loading_t >= 0.0:
		_loading_t += delta
		if _loading_t > 1.0:
			_status_label.text = "Connexion au serveur… %d s" % int(_loading_t)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_tab_next"):
		_show_tab((_tab_index + 1) % TAB_LABELS.size())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_tab_prev"):
		_show_tab((_tab_index - 1 + TAB_LABELS.size()) % TAB_LABELS.size())
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- Décor 3D
func _build_world() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -35, 0)
	key.light_energy = 1.1
	key.light_color = Color(0.98, 0.94, 0.86)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, 150, 0)
	rim.light_energy = 1.3
	rim.light_color = Color(0.7, 0.76, 0.9)
	add_child(rim)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skymat := ProceduralSkyMaterial.new()
	skymat.sky_top_color = Comic.PANEL_HI
	skymat.sky_horizon_color = Comic.PANEL
	skymat.ground_horizon_color = Comic.PANEL
	skymat.ground_bottom_color = Comic.BG
	sky.sky_material = skymat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	# Mur de fond charcoal + estrade (grammaire v2 : plus de papier/graphite).
	_box(Vector3(0, -3.4, -3.6), Vector3(32, 9, 1), Comic.PANEL)
	_box(Vector3(0, -0.3, 0), Vector3(11, 0.6, 5.5), Comic.BG)
	_box(Vector3(0, -0.02, 0.2), Vector3(10.4, 0.16, 4.6), Comic.PANEL_HI)

	_podium_root = Node3D.new()
	add_child(_podium_root)
	var xs := [-2.5, 0.0, 2.5]
	for i in 3:
		# Seul le podium central (agent sélectionné mis en avant) porte
		# l'accent pinceau (design.md §9 : « l'agent sélectionné gagne SEUL
		# sa couleur »).
		var accent := Comic.BRUSH if i == 1 else Comic.RULE
		_podium(Vector3(xs[i], 0.0, 0.2), accent)

	_cam = Camera3D.new()
	_cam.fov = 50
	_cam.position = Vector3(0, 2.4, 7.8)
	add_child(_cam)
	_cam.current = true

	_refresh_lobby_characters()

func _podium(pos: Vector3, accent: Color) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.15
	cyl.height = 0.22
	mi.mesh = cyl
	mi.position = pos + Vector3(0, 0.05, 0)
	mi.material_override = Cartoon.mat(Comic.PANEL_HI)
	add_child(mi)
	var ring := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 1.06
	rc.bottom_radius = 1.06
	rc.height = 0.06
	ring.mesh = rc
	ring.position = pos + Vector3(0, 0.18, 0)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = accent
	rm.emission_enabled = true
	rm.emission = accent
	rm.emission_energy_multiplier = 1.6
	ring.material_override = rm
	add_child(ring)

func _box(center: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = center
	mi.material_override = Cartoon.mat(color)
	add_child(mi)

## Reconstruit les 3 modèles d'agent du podium (design.md deliverable #4 :
## « replace the blob mannequins with the real agent models »). Centre =
## l'agent SÉLECTIONNÉ (AgentDatabase.selected_index), voisins immédiats de
## part et d'autre (ordre du catalogue, circulaire) — recalculé au retour sur
## l'onglet JOUER si la sélection a changé dans l'onglet Agents.
func _refresh_lobby_characters() -> void:
	for c in _chars:
		if is_instance_valid(c):
			c.queue_free()
	_chars.clear()
	_last_agent_shown = AgentDatabase.selected_index
	var agents := AgentDatabase.all()
	var n := agents.size()
	if n == 0 or _podium_root == null:
		return
	var xs := [-2.5, 0.0, 2.5]
	var center := AgentDatabase.selected_index
	var order := [center - 1, center, center + 1]
	for i in 3:
		var idx := posmod(order[i], n)
		var agent: AgentConfig = agents[idx]
		var node := _load_character_model(agent, i == 1)
		if node == null:
			continue
		node.position = Vector3(xs[i], 0.06, 0.2)
		_podium_root.add_child(node)
		_chars.append(node)

## Instancie assets/models/characters/<id>.glb, joue "Idle", recolore chaque
## slot matériau via `Cartoon.character_surface(kind, color)` (même
## convention de suffixe que tools/character_shots.gd : "<id>_<slot>").
## `is_selected` : SEUL l'agent au centre garde sa couleur exportée pleine
## (design.md §9) ; les voisins passent en neutre `text_dim` (silhouette
## désaturée, sans jamais disparaître).
func _load_character_model(agent: AgentConfig, is_selected: bool) -> Node3D:
	var id := agent.agent_name.to_lower()
	var path := "%s%s.glb" % [CHAR_MODEL_DIR, id]
	if not ResourceLoader.exists(path):
		push_warning("MainMenu: modèle agent introuvable (%s)" % path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate() as Node3D
	if root == null:
		return null
	var anim := _find_typed(root, "AnimationPlayer") as AnimationPlayer
	if anim:
		_play_idle(anim)
	_apply_character_materials(root, id, agent.color, is_selected)
	return root

## `Animation.has_animation("Idle")` ne couvre que la bibliothèque "" (globale) ;
## le glTF importe parfois les clips dans une bibliothèque nommée — on essaie
## le nom nu puis un suffixe qui correspond dans toutes les bibliothèques
## (même repli que tools/character_shots.gd::_play).
func _play_idle(anim: AnimationPlayer) -> void:
	if anim.has_animation("Idle"):
		anim.play("Idle")
		return
	for lib_name in anim.get_animation_library_list():
		var lib := anim.get_animation_library(lib_name)
		if lib and lib.has_animation("Idle"):
			anim.play("Idle" if lib_name == "" else "%s/Idle" % lib_name)
			return

func _apply_character_materials(model: Node3D, id: String, accent_color: Color, is_selected: bool) -> void:
	for mesh in _find_mesh_instances(model):
		if mesh.mesh == null:
			continue
		mesh.extra_cull_margin = 2.0
		for i in mesh.mesh.get_surface_count():
			var mat: Material = mesh.mesh.surface_get_material(i)
			var mat_name: String = mat.resource_name if mat else ""
			if not mat_name.begins_with(id + "_"):
				continue
			var slot := mat_name.substr(id.length() + 1)
			var base: BaseMaterial3D = mat as BaseMaterial3D
			var exported_color: Color = base.albedo_color if base else Color.WHITE
			var tint := accent_color if slot == "cloth" else exported_color
			if not is_selected:
				tint = tint.lerp(Comic.TEXT_DIM, 0.7)
			mesh.set_surface_override_material(i, Cartoon.character_surface(StringName(slot), tint))

func _find_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_mesh_instances(c))
	return out

func _find_typed(n: Node, class_name_str: String) -> Node:
	if n.get_class() == class_name_str:
		return n
	for c in n.get_children():
		var r := _find_typed(c, class_name_str)
		if r:
			return r
	return null

# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_content = Control.new()
	Comic.anchor(_content, Control.PRESET_FULL_RECT)
	_content.offset_top = 84
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_content)

	_build_play_panel()
	_build_top_bar(root)

func _build_top_bar(root: Control) -> void:
	var bar := ComicPanel.new()
	bar.bg_color = Comic.PANEL
	bar.border_width = 0
	bar.radius = 0
	bar.content_margin = 0
	Comic.anchor(bar, Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 78
	root.add_child(bar)

	var line := ColorRect.new()
	Comic.anchor(line, Control.PRESET_BOTTOM_WIDE)
	line.offset_top = -Comic.RULE_W
	line.color = Comic.RULE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(line)

	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = Comic.SAFE_MARGIN
	hb.offset_right = -Comic.SAFE_MARGIN
	hb.add_theme_constant_override("separation", Comic.SP_2)
	hb.alignment = BoxContainer.ALIGNMENT_BEGIN
	bar.add_child(hb)

	var brand := Comic.title_label("Fps", Comic.SIZE_LABEL, Comic.BULLET)
	brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(brand)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(Comic.SP_6, 0)
	hb.add_child(gap)

	var group := ButtonGroup.new()
	for i in TAB_LABELS.size():
		var tb := Button.new()
		tb.text = TAB_LABELS[i]
		tb.toggle_mode = true
		tb.button_group = group
		tb.focus_mode = Control.FOCUS_ALL
		tb.custom_minimum_size = Vector2(0, 48)
		tb.pressed.connect(_on_tab.bind(i))
		hb.add_child(tb)
		_tabs.append(tb)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	var quit := Button.new()
	quit.text = "Quitter"
	quit.custom_minimum_size = Vector2(0, 48)
	quit.pressed.connect(func(): get_tree().quit())
	hb.add_child(quit)

func _build_play_panel() -> void:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	Comic.anchor(wrap, Control.PRESET_BOTTOM_LEFT)
	wrap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	wrap.grow_horizontal = Control.GROW_DIRECTION_END
	wrap.offset_left = Comic.SAFE_MARGIN
	wrap.offset_bottom = -Comic.SAFE_MARGIN
	wrap.custom_minimum_size = Vector2(460, 0)
	_content.add_child(wrap)
	_play_panel = wrap

	var header := BrushHeader.new()
	header.title = "Partie"
	wrap.add_child(header)

	var panel := ComicPanel.new()
	panel.bg_color = Comic.PANEL
	wrap.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Comic.SP_2)
	panel.body.add_child(box)

	box.add_child(Comic.bullet_row("Mode"))
	# Sélecteur segmenté (1 ligne, 5 modes) — tient toujours à l'écran, la
	# description complète reste disponible en info-bulle.
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", Comic.SP_1)
	box.add_child(mode_row)
	var mgroup := ButtonGroup.new()
	for id in MatchConfig.MODES:
		var btn := _mode_card(id, mgroup)
		mode_row.add_child(btn)
		_mode_cards.append({"button": btn, "id": id})

	box.add_child(HSeparator.new())
	box.add_child(Comic.bullet_row("Carte"))
	# Grille de cartes titrées (2 colonnes) — retour lead R3 : la liste verticale
	# faisait déborder le sélecteur de mode hors écran.
	_map_list = GridContainer.new()
	_map_list.columns = 2
	_map_list.add_theme_constant_override("h_separation", Comic.SP_1)
	_map_list.add_theme_constant_override("v_separation", Comic.SP_1)
	box.add_child(_map_list)

	box.add_child(HSeparator.new())
	var bots_row := HBoxContainer.new()
	bots_row.add_theme_constant_override("separation", Comic.SP_3)
	box.add_child(bots_row)
	_bots_check = CheckButton.new()
	_bots_check.text = "Bots"
	_bots_check.button_pressed = MatchConfig.bots_enabled
	_bots_check.toggled.connect(_on_bots_toggled)
	bots_row.add_child(_bots_check)
	for i in DIFFICULTY_LABELS.size():
		var db := Button.new()
		db.text = DIFFICULTY_LABELS[i]
		db.toggle_mode = true
		db.custom_minimum_size = Vector2(0, 38)
		db.pressed.connect(_on_difficulty.bind(i))
		bots_row.add_child(db)
		_diff_buttons.append(db)
	_refresh_difficulty_ui()

	_host_btn = Button.new()
	_host_btn.text = "▶  JOUER (héberger)"
	_host_btn.custom_minimum_size = Vector2(0, 60)
	_host_btn.add_theme_font_size_override("font_size", Comic.SIZE_SUBTITLE)
	_host_btn.pressed.connect(_on_host)
	box.add_child(_host_btn)

	box.add_child(HSeparator.new())

	var mp := Comic.label("Multijoueur — rejoindre une IP", Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL)
	box.add_child(mp)

	_ip_field = LineEdit.new()
	_ip_field.text = "127.0.0.1"
	_ip_field.placeholder_text = "IP du serveur"
	box.add_child(_ip_field)

	var join_btn := Button.new()
	join_btn.text = "Rejoindre"
	join_btn.custom_minimum_size = Vector2(0, 46)
	join_btn.pressed.connect(_on_join)
	box.add_child(join_btn)

	box.add_child(HSeparator.new())

	var train_btn := Button.new()
	train_btn.text = "Terrain d'entraînement (solo)"
	train_btn.custom_minimum_size = Vector2(0, 46)
	train_btn.pressed.connect(_on_training)
	box.add_child(train_btn)

	_status = ComicPanel.new()
	_status.bg_color = Comic.PANEL_HI
	_status.border_width = Comic.RULE_W
	_status.content_margin = Comic.SP_2
	_status.visible = false
	box.add_child(_status)
	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", Comic.SP_1)
	_status.body.add_child(status_box)
	_status_label = Comic.label("", Comic.SIZE_BODY, Comic.TEXT, Comic.FONT_LABEL)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_box.add_child(_status_label)
	_retry_btn = Button.new()
	_retry_btn.text = "Réessayer"
	_retry_btn.custom_minimum_size = Vector2(0, 40)
	_retry_btn.visible = false
	_retry_btn.pressed.connect(func():
		if _retry_action.is_valid():
			_retry_action.call())
	status_box.add_child(_retry_btn)
	if _net.last_disconnect_reason != "":
		_show_error(_net.last_disconnect_reason)
		_net.last_disconnect_reason = ""

	_select_mode(_mode_id)

func _mode_card(id: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 48)
	b.text = SHORT_MODE_LABELS.get(id, id)
	b.tooltip_text = "%s\n%s" % [MODE_LABELS.get(id, id), MODE_DESCRIPTIONS.get(id, "")]
	b.pressed.connect(_select_mode.bind(id))
	return b

# ---------------------------------------------------------------- Sélection mode/carte
func _select_mode(id: String) -> void:
	_mode_id = id
	for c in _mode_cards:
		c.button.button_pressed = c.id == id
	_refresh_maps()

func _map_catalog() -> Object:
	if ResourceLoader.exists(MAP_CATALOG_PATH):
		return load(MAP_CATALOG_PATH)
	return null

## Cartes disponibles pour `_mode_id`. Repli sur la scène historique tant que
## MapCatalog (R3-MAPS) n'existe pas ou ne couvre pas encore ce mode.
func _maps_for_mode() -> Array:
	var cat := _map_catalog()
	var out: Array = []
	if cat:
		for m in cat.all():
			if _mode_id in m.modes:
				out.append(m)
	if out.is_empty():
		out.append({
			"id": "default", "name": "Terrain standard", "description": "",
			"scene": FALLBACK_SCENES.get(_mode_id, FALLBACK_SCENES["tdm"]),
		})
	return out

## "07. WASTELAND" (design.md v2 §7/§11 — même grammaire que les feuilles de
## référence). Une carte sans numéro connu (nouvelle carte pas encore dans
## MAP_NUMBERS) garde juste son nom, jamais un numéro inventé.
func _map_display_name(m: Dictionary) -> String:
	var id := str(m.get("id", ""))
	var name := str(m.get("name", id))
	if MAP_NUMBERS.has(id):
		return "%02d. %s" % [MAP_NUMBERS[id], name.to_upper()]
	return name.to_upper()

func _refresh_maps() -> void:
	for c in _map_list.get_children():
		c.queue_free()
	_map_cards.clear()
	var maps := _maps_for_mode()
	var group := ButtonGroup.new()
	for m in maps:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 44)
		b.text = _map_display_name(m)
		var size_tag: String = str(m.get("size", ""))
		var desc: String = str(m.get("description", ""))
		b.tooltip_text = ("%s — %s" % [size_tag, desc]) if size_tag != "" else desc
		b.pressed.connect(_select_map.bind(m))
		_map_list.add_child(b)
		_map_cards.append(b)
	if not maps.is_empty():
		_map_cards[0].button_pressed = true
		_select_map(maps[0])

func _select_map(m: Dictionary) -> void:
	_map_choice = m

func _on_bots_toggled(on: bool) -> void:
	MatchConfig.bots_enabled = on
	_refresh_difficulty_ui()

func _on_difficulty(i: int) -> void:
	MatchConfig.bot_difficulty = i
	_refresh_difficulty_ui()

func _refresh_difficulty_ui() -> void:
	for i in _diff_buttons.size():
		_diff_buttons[i].button_pressed = i == MatchConfig.bot_difficulty
		_diff_buttons[i].disabled = not MatchConfig.bots_enabled

# ---------------------------------------------------------------- Onglets
func _on_tab(idx: int) -> void:
	_show_tab(idx)

func _show_tab(idx: int) -> void:
	_tab_index = idx
	if _tabs.size() > idx and is_instance_valid(_tabs[idx]):
		_tabs[idx].button_pressed = true
	if _embedded and is_instance_valid(_embedded):
		_embedded.queue_free()
	_embedded = null

	if idx == TAB_PLAY:
		_play_panel.visible = true
		if AgentDatabase.selected_index != _last_agent_shown:
			_refresh_lobby_characters()
		call_deferred("_focus_play")
		return

	_play_panel.visible = false
	var script: Script = null
	match idx:
		TAB_AGENTS: script = AGENT_SCRIPT
		TAB_ARSENAL: script = ARSENAL_SCRIPT
		TAB_OPTIONS: script = OPTIONS_SCRIPT
	if script == null:
		return
	_embedded = script.new()
	_embedded.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _embedded.has_signal("closed"):
		_embedded.closed.connect(func(): _show_tab(TAB_PLAY))
	_content.add_child(_embedded)

func _focus_play() -> void:
	if _host_btn and is_instance_valid(_host_btn) and _play_panel.visible:
		_host_btn.grab_focus()

# ---------------------------------------------------------------- Réseau / jeu
func _on_host() -> void:
	_apply_match_config()
	if _net.host() == OK:
		_loading_t = -1.0
		_status.visible = false
		_start_game()
	else:
		_show_error("Échec de l'hébergement.", _on_host)

func _on_join() -> void:
	if _ip_field.text.strip_edges() == "":
		_show_empty("Aucune adresse — saisis une IP de serveur.")
		_ip_field.grab_focus()
		return
	_apply_match_config()
	_loading_t = 0.0
	_status.visible = true
	_status.bg_color = Comic.PANEL_HI
	_retry_btn.visible = false
	_status_label.add_theme_color_override("font_color", Comic.TEXT)
	_status_label.text = "Connexion à %s…" % _ip_field.text
	_net.join(_ip_field.text)

func _on_connected() -> void:
	_loading_t = -1.0
	_status.visible = false
	_start_game()

func _on_failed() -> void:
	_loading_t = -1.0
	_show_error("Connexion échouée.", _on_join)

## `code` : contexte pour le joueur (design.md v2 §11 "Error: ⚠ ÉCHEC, code,
## Réessayer"). `retry` : action rejouée par le bouton Réessayer.
func _show_error(msg: String, retry: Callable = Callable()) -> void:
	_status.visible = true
	_status.bg_color = Comic.PANEL_HI
	_status.border_color = Comic.BRUSH
	_status_label.add_theme_color_override("font_color", Comic.BRUSH)
	_status_label.text = "⚠ ÉCHEC — %s" % msg
	_retry_action = retry
	_retry_btn.visible = retry.is_valid()

func _show_empty(msg: String) -> void:
	_status.visible = true
	_status.bg_color = Comic.PANEL_HI
	_status.border_color = Comic.RULE
	_status_label.add_theme_color_override("font_color", Comic.TEXT_DIM)
	_status_label.text = msg
	_retry_btn.visible = false

func _on_training() -> void:
	get_tree().change_scene_to_file("res://scenes/levels/training/training_ground.tscn")

func _apply_match_config() -> void:
	MatchConfig.set_mode(_mode_id)
	MatchConfig.map_id = str(_map_choice.get("id", ""))

func _start_game() -> void:
	var scene: String = str(_map_choice.get("scene", FALLBACK_SCENES.get(_mode_id, FALLBACK_SCENES["tdm"])))
	get_tree().change_scene_to_file(scene)
