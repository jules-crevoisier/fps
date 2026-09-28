## DeathScreen.gd
## Écran de mort (contrat lead 2026-09-27, "DEATH SCREEN") : affiché quand le
## joueur LOCAL meurt (Health.died), masqué à son respawn (Health.respawned).
## Habillage plein écran désaturé + teinté de rouge + trame de points en
## vignette (assets/shaders/ui/death_tint.gdshader, lit la scène 3D/le HUD déjà
## dessinés en dessous). Éclat BD "K.O. !" (étoile encrée, texte display jaune
## contour encre), carte du tueur (portrait, nom, arme + tir à la tête,
## PV restants SI fiable côté client -- voir GameHUD._resolve_killer_hp),
## anneau de compte à rebours (respawn_delay) et astuce tournante parmi
## `TIPS` (6 astuces réellement vraies, vérifiées contre le code -- voir leurs
## commentaires). Suicide/environnement (killer_id <= 0, même convention que
## Health.apply_damage "0 = environnement") : "ÉLIMINÉ PAR L'ENVIRONNEMENT",
## sans ligne d'arme.
class_name DeathScreen
extends Control

## Astuces round-robin (GameHUD.gd avance l'index à chaque mort locale) --
## chacune vérifiée contre le code au moment d'écrire cette tâche :
##  0. FlashMath/UtilityThrower._apply_blind_to_target : `has_los and not
##     smoke_between(...)` -- une fumée entre la flash et la cible ANNULE
##     l'aveuglement, jamais un simple atténuateur.
##  1. UtilityThrower._throw_speed_for/en-tête section « RMB = lob COURT,
##     sous-main » : le clic droit lance la grenade en main d'un lob court.
##  2. Weapon.gd (tâche "revolver") : `fan_trigger = player.input.alt_fire_held`
##     UNIQUEMENT pour une arme `has_fan_fire()` (le Revolver) -- clic droit
##     maintenu = tir en rafale (fan the hammer).
##  3. PlayerInput.resolve_sprint_toggle + project.godot ("sprint" = Maj
##     gauche/droite, physical_keycode 4194325) : bascule, pas un maintien.
##  4. WeaponConfig.headshot_mult : Ravage ×1,4, Revolver ×2,0 (Weapon.gd
##     `dmg *= c.headshot_mult`) -- jamais un ×2 universel.
##  5. GameHUD._spot_enemy/MinimapHUD.heard : un ennemi apparaît sur la
##     minicarte s'il vient de tirer, court à proximité, OU est dans le champ
##     de vision à portée avec une ligne de vue libre.
const TIPS := [
	"Une flash lancée derrière une fumée n'aveugle personne : vise par-dessus le mur.",
	"Clic droit avec une grenade en main = lancer court, pratique dans un angle serré.",
	"Maintiens le clic droit au revolver pour tirer en rafale (fan the hammer).",
	"Le sprint est une bascule : un appui sur Maj suffit, pas besoin de la maintenir.",
	"Un tir à la tête multiplie les dégâts -- jusqu'à ×2 au revolver.",
	"Un ennemi apparaît sur la minicarte dès qu'il tire, court près de toi, ou que tu le vois.",
]

## Étoile BD de l'éclat "K.O. !" -- points de la maquette
## reports/ui/mockups/death.html (`<polygon points="...">`, viewBox 760x380),
## repris tels quels pour un rendu identique.
const _BURST_SIZE := Vector2(760.0, 380.0)

## `PackedVector2Array([Vector2(...), ...])` n'est pas une expression CONSTANTE
## en GDScript (Godot 4.7) -- fabriquée à l'appel plutôt qu'en `const`.
static func _burst_points() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(380, 6), Vector2(440, 96), Vector2(560, 40), Vector2(540, 140),
		Vector2(700, 120), Vector2(610, 200), Vector2(752, 270), Vector2(590, 270),
		Vector2(620, 370), Vector2(490, 300), Vector2(380, 374), Vector2(300, 290),
		Vector2(150, 360), Vector2(180, 262), Vector2(10, 250), Vector2(150, 180),
		Vector2(40, 100), Vector2(210, 120), Vector2(200, 20), Vector2(310, 96),
	])

const _RING_DIAMETER := 124.0
const _POP_S := UiTokens.POP_S
const _POP_OVERSHOOT := 1.08

var _veil: ColorRect
var _burst_root: Control
var _ko_label: Label
var _killer_portrait: TextureRect
var _killer_name_label: Label
var _weapon_icon: TextureRect
var _weapon_label: Label
var _hp_label: Label
var _ring: _RespawnRing
var _countdown_label: Label
var _tip_label: Label
var _pop_tween: Tween

## LOADOUT SELECTION (contrat lead 2026-09-28, point 4 "DEATH SCREEN") —
## rangée compacte pour changer la primaire du PROCHAIN respawn : une entrée
## par `Loadout.PRIMARY_NAMES` = {"name":String, "button":Button}.
var _picker_buttons: Array = []
## Vrai si CET écran a libéré la souris (capturée en jeu) pour rendre « Prochaine arme »
## cliquable : il la recapture au respawn, jamais s'il ne l'a pas libérée lui-même.
var _released_mouse: bool = false

var _tip_index: int = -1
var _elapsed: float = 0.0
var _respawn_delay: float = 3.0
var _counting: bool = false


## `killer_id <= 0` = environnement (même convention que
## Health.apply_damage "attacker_id = 0 = environnement"). Fonction PURE.
## Retour de test 2026-09-28 (« on ne peut pas changer d'arme, il n'y a pas la souris ») :
## pendant la mort, une souris capturée devient visible pour cliquer sur « Prochaine arme ».
## Tout autre mode (déjà visible : menu pause ouvert…) reste tel quel.
static func mouse_mode_for_picker(current_mode: int) -> int:
	return Input.MOUSE_MODE_VISIBLE if current_mode == Input.MOUSE_MODE_CAPTURED else current_mode


static func is_environment_death(killer_id: int) -> bool:
	return killer_id <= 0


## Nom affiché "ÉLIMINÉ PAR" -- "L'ENVIRONNEMENT" pour un suicide/environnement,
## sinon le nom réel du tueur.
static func killer_display_name(killer_id: int, killer_name: String) -> String:
	return "L'ENVIRONNEMENT" if is_environment_death(killer_id) else killer_name


## "ARME" ou "ARME · TIR À LA TÊTE" -- `weapon_or_ability` déjà en capitales
## (GameWorld.kill_logged, ex. "RAVAGE").
static func killer_line(weapon_or_ability: String, headshot: bool) -> String:
	return weapon_or_ability + " · TIR À LA TÊTE" if headshot else weapon_or_ability


## "Il lui restait N PV" -- PV du tueur arrondis à l'entier.
static func killer_hp_line(remaining_hp: float) -> String:
	return "Il lui restait %d PV" % int(round(remaining_hp))


## Secondes restantes avant le respawn (arrondi SUPÉRIEUR, jamais négatif) --
## `3.0`/`elapsed=0` -> 3, `elapsed=2.5` -> 1, `elapsed>=delay` -> 0.
static func countdown_seconds(elapsed: float, delay: float) -> int:
	return maxi(int(ceil(maxf(delay - elapsed, 0.0))), 0)


## Portion encore JAUNE de l'anneau (1.0 = plein au moment de la mort, se
## VIDE jusqu'à 0.0 au respawn) -- `delay <= 0` : anneau déjà vide (repli
## défensif, jamais de division par zéro).
static func ring_fill_ratio(elapsed: float, delay: float) -> float:
	if delay <= 0.0:
		return 0.0
	return clampf((delay - elapsed) / delay, 0.0, 1.0)


## Astuce n° `index` (round-robin, GameHUD.gd avance l'index à chaque mort).
static func tip_for(index: int) -> String:
	return TIPS[index % TIPS.size()]


func _ready() -> void:
	Comic.anchor(self, Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	_refresh_primary_picker_highlight()


func _build() -> void:
	_build_veil()
	_build_burst()
	_build_killer_card()
	_build_primary_picker()
	_build_respawn_ring()
	_build_tip()


func _build_veil() -> void:
	_veil = ColorRect.new()
	Comic.anchor(_veil, Control.PRESET_FULL_RECT)
	_veil.color = Color.BLACK
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/ui/death_tint.gdshader")
	_veil.material = mat
	add_child(_veil)


func _build_burst() -> void:
	_burst_root = Control.new()
	_burst_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_burst_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_burst_root.custom_minimum_size = _BURST_SIZE
	_burst_root.size = _BURST_SIZE
	_burst_root.offset_left = -_BURST_SIZE.x * 0.5
	_burst_root.offset_right = _BURST_SIZE.x * 0.5
	_burst_root.offset_top = 90.0
	_burst_root.offset_bottom = 90.0 + _BURST_SIZE.y
	_burst_root.pivot_offset = _BURST_SIZE * 0.5
	_burst_root.rotation_degrees = -6.0
	add_child(_burst_root)

	var star := Polygon2D.new()
	star.polygon = _burst_points()
	star.color = UiTokens.RED
	_burst_root.add_child(star)

	var stroke := Line2D.new()
	stroke.points = _burst_points()
	stroke.closed = true
	stroke.width = UiTokens.STROKE * 2.5
	stroke.default_color = UiTokens.INK
	stroke.joint_mode = Line2D.LINE_JOINT_ROUND
	_burst_root.add_child(stroke)

	_ko_label = UiTokens.make_label("K.O. !", UiTokens.display(UiTokens.T_4XL, UiTokens.YELLOW))
	# Le texte hérite du tilt -6° de `_burst_root` (maquette : `.txt` est un
	# enfant de `.ko`, donc tourné AVEC l'étoile, jamais contre-incliné).
	_ko_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ko_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Comic.anchor(_ko_label, Control.PRESET_FULL_RECT)
	_burst_root.add_child(_ko_label)


func _build_killer_card() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	row.offset_top = 520.0
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH   # centrée : grandit des deux côtés
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	_killer_portrait = TextureRect.new()
	_killer_portrait.texture = UiTokens.icon("portrait_verrou")
	_killer_portrait.custom_minimum_size = Vector2(180, 180)
	_killer_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_killer_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_killer_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait_bg := PanelContainer.new()
	portrait_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = UiTokens.enemy_color()
	bg_style.set_border_width_all(int(UiTokens.STROKE))
	bg_style.border_color = UiTokens.INK
	bg_style.shadow_size = 0
	portrait_bg.add_theme_stylebox_override("panel", bg_style)
	portrait_bg.add_child(_killer_portrait)
	row.add_child(portrait_bg)

	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size = Vector2(520, 0)
	card.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.PAPER, 0.0, UiTokens.DROP, UiTokens.STROKE, Vector2(UiTokens.S4, UiTokens.S3)))
	var card_col := VBoxContainer.new()
	card_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_col.add_theme_constant_override("separation", UiTokens.S1)

	card_col.add_child(UiTokens.make_label("Éliminé par", UiTokens.label(UiTokens.T_S, UiTokens.INK_SOFT, 0, true), true))
	_killer_name_label = UiTokens.make_label("", UiTokens.display(UiTokens.T_2XL, UiTokens.MAGENTA_DEEP, 6))
	card_col.add_child(_killer_name_label)

	var weapon_row := HBoxContainer.new()
	weapon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_theme_constant_override("separation", UiTokens.S2)
	_weapon_icon = TextureRect.new()
	_weapon_icon.custom_minimum_size = Vector2(0, 52)
	_weapon_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_child(_weapon_icon)
	_weapon_label = UiTokens.make_label("", UiTokens.label(UiTokens.T_M, UiTokens.INK, 0, true), true)
	weapon_row.add_child(_weapon_label)
	card_col.add_child(weapon_row)

	_hp_label = UiTokens.make_label("", UiTokens.body(UiTokens.T_S, UiTokens.INK))
	card_col.add_child(_hp_label)

	card.add_child(card_col)
	row.add_child(card)


## LOADOUT SELECTION (contrat lead 2026-09-28, "DEATH SCREEN" point 4 : "a
## compact row to change the primary for the NEXT respawn ... current one
## highlighted") — colonne compacte de 5 boutons (silhouette + numéro),
## posée dans la zone GAUCHE de l'écran, totalement LIBRE quelle que soit la
## variante affichée (voir capture reports/checkpoints/2026-09-28_loadout/
## hud_ingame_g_death.png) : une première version alignée sous la carte du
## tueur (`_build_killer_card`, hauteur ÉLASTIQUE selon la ligne PV/arme
## affichées) chevauchait l'anneau de compte à rebours dès que le contenu de
## la carte grandissait un peu — cette colonne, à gauche de la carte/de
## l'étoile "K.O. !" (tous deux CENTRÉS horizontalement), ne peut plus jamais
## les toucher, quel que soit leur contenu. Choisir un bouton : persiste
## IMMÉDIATEMENT (Settings.selected_primary, MÊME règle qu'ArmoryScreen) ET
## avertit le serveur (GameWorld.request_primary_weapon, lu via le groupe
## "match" — MÊME technique que Weapon._round_locked, aucune dépendance
## directe à GameHUD.gd) : le serveur applique ce choix au PROCHAIN respawn
## SEULEMENT (jamais mi-vie, voir GameWorld._on_player_died).
const _PICKER_ORIGIN := Vector2(64.0, 340.0)
const _PICKER_BTN_SIZE := Vector2(72.0, 72.0)  # >= 44 px de tap target (contrat).
const _PICKER_GAP := 10.0

func _build_primary_picker() -> void:
	var col := VBoxContainer.new()
	col.position = _PICKER_ORIGIN
	col.add_theme_constant_override("separation", int(_PICKER_GAP))
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(col)

	col.add_child(UiTokens.make_label("Prochaine arme", UiTokens.label(UiTokens.T_XS, UiTokens.PAPER, int(UiTokens.STROKE * 0.5), true), true))

	_picker_buttons = []
	for i in Loadout.PRIMARY_NAMES.size():
		var wname: String = Loadout.PRIMARY_NAMES[i]
		var btn := _build_picker_button(wname, i + 1)
		col.add_child(btn)
		_picker_buttons.append({"name": wname, "button": btn})


func _build_picker_button(wname: String, number: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = _PICKER_BTN_SIZE
	btn.focus_mode = Control.FOCUS_ALL
	btn.tooltip_text = wname
	MenuWidgets.apply_plate_states(btn, UiTokens.PAPER, 0.0)

	var icon := TextureRect.new()
	icon.texture = UiTokens.icon(WeaponIcon.sil(wname))
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 6.0
	icon.offset_right = -6.0
	icon.offset_top = 6.0
	icon.offset_bottom = -6.0
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)

	# Numéro discret dans le coin, DANS les bornes du bouton (contrairement à
	# la badge flottante d'InventoryHUD — ici la colonne est déjà serrée
	# contre le bord gauche de l'écran, une badge qui déborde à gauche sortirait
	# du viewport).
	var num := UiTokens.make_label(str(number), UiTokens.label(UiTokens.T_XS, UiTokens.INK_SOFT, 0, true))
	num.set_anchors_preset(Control.PRESET_TOP_LEFT)
	num.position = Vector2(4.0, 2.0)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(num)

	btn.pressed.connect(_on_primary_picked.bind(wname))
	return btn


## Choisit `wname` pour le PROCHAIN respawn — persiste (Settings) ET avertit
## le serveur (contrat : "choice also becomes the persisted default").
func _on_primary_picked(wname: String) -> void:
	Settings.selected_primary = wname
	Settings.save_all()
	var match_node := get_tree().get_first_node_in_group("match")
	if match_node and match_node.has_method("request_primary_weapon"):
		match_node.request_primary_weapon(Loadout.primary_id_for_name(wname))
	_refresh_primary_picker_highlight()


## Surligne (jaune) le bouton de la primaire ACTUELLEMENT retenue pour le
## prochain respawn (Settings.selected_primary) — appelée à la construction
## ET à chaque `show_death` (contrat : "current one highlighted").
func _refresh_primary_picker_highlight() -> void:
	for entry in _picker_buttons:
		var selected: bool = String(entry["name"]) == Settings.selected_primary
		MenuWidgets.apply_plate_states(entry["button"], UiTokens.YELLOW if selected else UiTokens.PAPER)


func _build_respawn_ring() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_top = -(80.0 + _RING_DIAMETER)
	row.offset_bottom = -80.0
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.add_theme_constant_override("separation", UiTokens.S3)
	add_child(row)

	_ring = _RespawnRing.new()
	_ring.custom_minimum_size = Vector2(_RING_DIAMETER, _RING_DIAMETER)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_ring)
	_countdown_label = UiTokens.make_label("3", UiTokens.display(UiTokens.T_L, UiTokens.INK, 0))
	_countdown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.add_child(_countdown_label)

	var label := UiTokens.make_label("Retour au combat…", UiTokens.label(UiTokens.T_M, UiTokens.PAPER, int(UiTokens.STROKE), true), true)
	row.add_child(label)


func _build_tip() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(460, 0)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -(460.0 + 64.0)
	panel.offset_right = -64.0
	panel.offset_top = -(160.0 + 80.0)
	panel.offset_bottom = -80.0
	panel.add_theme_stylebox_override("panel", UiTokens.plate(UiTokens.PAPER, 0.0, UiTokens.DROP_SMALL, UiTokens.STROKE, Vector2(UiTokens.S3, UiTokens.S2)))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTokens.S1)
	col.add_child(UiTokens.make_label("Astuce", UiTokens.label(UiTokens.T_S, UiTokens.INK, 0, true), true))
	_tip_label = UiTokens.make_label("", UiTokens.body(UiTokens.T_S, UiTokens.INK))
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_tip_label)
	panel.add_child(col)
	add_child(panel)


## Affiche l'écran (Health.died du joueur LOCAL, ou mise à jour dès qu'un
## `kill_logged` en retard fournit l'arme -- voir GameHUD._show_death_screen).
## `has_killer_hp`/`killer_hp` : PV du tueur, SEULEMENT si résolus de façon
## fiable côté client (voir GameHUD._resolve_killer_hp) -- sinon la ligne est
## masquée plutôt que d'afficher une valeur inventée.
func show_death(killer_name: String, is_environment: bool, weapon_or_ability: String, headshot: bool,
		killer_hp: float, has_killer_hp: bool, respawn_delay: float) -> void:
	_killer_name_label.text = killer_name
	_weapon_label.visible = not is_environment
	_weapon_icon.visible = not is_environment
	if not is_environment:
		_weapon_label.text = killer_line(weapon_or_ability, headshot)
		_weapon_icon.texture = UiTokens.icon(WeaponIcon.sticker(weapon_or_ability))
	_hp_label.visible = has_killer_hp and not is_environment
	if _hp_label.visible:
		_hp_label.text = killer_hp_line(killer_hp)

	_respawn_delay = maxf(respawn_delay, 0.0)
	_elapsed = 0.0
	_counting = true
	_update_countdown()
	_refresh_primary_picker_highlight()

	if not visible:
		_tip_index += 1
		_tip_label.text = tip_for(_tip_index)
		_pop_in()
	visible = true
	var wanted := mouse_mode_for_picker(Input.mouse_mode)
	if wanted != Input.mouse_mode:
		Input.mouse_mode = wanted
		_released_mouse = true


## Masque l'écran (Health.respawned du joueur LOCAL) -- GameHUD.gd.
func hide_death() -> void:
	_counting = false
	visible = false
	_recapture_mouse()


## Rend la souris au jeu au respawn -- seulement si cet écran l'avait libérée. Menu pause
## ouvert à ce moment : c'est lui qui recapturera à sa fermeture (il restaure le mode noté à
## son ouverture, qu'on remplace ici par « capturé »).
func _recapture_mouse() -> void:
	if not _released_mouse:
		return
	_released_mouse = false
	var pause := get_tree().get_first_node_in_group("pause_menu") if is_inside_tree() else null
	if pause != null and pause.has_method("is_open") and pause.is_open():
		pause.set("_mouse_mode_before_open", Input.MOUSE_MODE_CAPTURED)
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Touches 1 à 5 pendant la mort = choisir la primaire du prochain respawn (même ordre que
## les boutons ; les touches d'arme du joueur sont muettes tant que la souris est libérée).
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var index := key.keycode - KEY_1
	if index < 0 or index >= _picker_buttons.size():
		return
	_on_primary_picked(String(_picker_buttons[index]["name"]))
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _pop_in() -> void:
	_burst_root.pivot_offset = _BURST_SIZE * 0.5
	_burst_root.scale = Vector2.ONE * _POP_OVERSHOOT
	if _pop_tween and is_instance_valid(_pop_tween):
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.tween_property(_burst_root, "scale", Vector2.ONE, _POP_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if not _counting:
		return
	_elapsed += delta
	_update_countdown()


func _update_countdown() -> void:
	_countdown_label.text = str(countdown_seconds(_elapsed, _respawn_delay))
	_ring.ratio = ring_fill_ratio(_elapsed, _respawn_delay)
	_ring.queue_redraw()


## Anneau de compte à rebours -- fond papier + portion JAUNE qui se VIDE
## (éventail depuis midi, sens horaire) + trait d'encre, dessinés directement
## (aucune texture de progression radiale native ne correspond au visuel BD).
class _RespawnRing extends Control:
	var ratio: float = 1.0

	func _draw() -> void:
		var r := size.x * 0.5
		var center := size * 0.5
		draw_circle(center, r, UiTokens.PAPER_2)
		if ratio > 0.0:
			var points := PackedVector2Array([center])
			var segments := 48
			for i in segments + 1:
				var t: float = minf(float(i) / float(segments), ratio)
				var a := -PI * 0.5 + TAU * t
				points.append(center + Vector2(cos(a), sin(a)) * r)
				if t >= ratio:
					break
			draw_colored_polygon(points, UiTokens.YELLOW)
		draw_arc(center, r - UiTokens.STROKE * 0.5, 0.0, TAU, 48, UiTokens.INK, UiTokens.STROKE, true)
