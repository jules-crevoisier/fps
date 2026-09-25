## DeathPanel.gd
## Voile plein écran à la mort — v4 « Encre, jaune, italique » (UX-34,
## docs/UI_DIRECTION_BL3.md §6 « Mort », §7 tokens) : remplace le bandeau
## pinceau rouge v3 (`BrushHeader`) par le langage v4 — monde désaturé à 60 %
## derrière le voile (shader canvas_item CONSTRUIT EN LIGNE, `Shader.new()` +
## `.code`, jamais un fichier `.gdshader` séparé qui serait hors de ma liste
## de fichiers ; syntaxe confirmée Context7 Godot 4.7 "Screen-reading
## shaders" : `hint_screen_texture` + `SCREEN_UV`), titre « REMBALLÉ » géant
## encré (157 px, `vital`, contour 5 px = `STROKE_DISPLAY`, ombre dure (8, 8)
## « moments héros » §4.3, incliné −6° comme un titre de boss §2), carte du
## tueur à coins coupés (glyphe ▼ + nom, arme, PV restants) et barre à
## rayures de danger « Retour dans N s » (§4.5 « rayures : barres de
## chargement seulement »).
##
## Portrait : la maquette §6 montre un portrait rendu de l'agent tueur —
## `show_death()` ne reçoit que `killer_name`/`weapon_name` (+ PV restants,
## nouveau) de `GameHUD.gd` (hors de ma liste de fichiers, voir son appel
## `_death_panel.show_death(killer, weapon_or_ability)` : `killer_id` n'y est
## PAS résolu en `agent_index`). Plutôt qu'une image inventée (règle globale
## « pas de texte/visuel factice »), la carte affiche le glyphe ▼ en grand —
## déjà le langage visuel du camp ennemi partout ailleurs — à la place d'un
## portrait. Un vrai portrait 3D suivrait l'ajout d'un paramètre agent_index
## côté GameHUD.gd (blocked_on, voir le rendu de tâche UX-34).
class_name DeathPanel
extends Control

## Désaturation du monde derrière le voile (§6 « monde désaturé à 60 % »).
const WORLD_DESATURATION := 0.6
## Shader canvas_item inline (voir la note de tête de fichier) — ajuste
## saturation/contraste/luminosité par lecture de `screen_texture` (Context7
## Godot 4.7, "Adjust brightness, contrast, and saturation using screen
## texture"), réduit ici à la seule saturation (`WORLD_DESATURATION`).
const _DESATURATE_SHADER_CODE := "shader_type canvas_item;\n\nuniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;\nuniform float saturation : hint_range(0.0, 1.0) = 1.0;\n\nvoid fragment() {\n\tvec3 c = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;\n\tc = mix(vec3(dot(vec3(1.0), c) * 0.33333), c, saturation);\n\tCOLOR = vec4(c, 1.0);\n}\n"

## Délai visuel avant réapparition (§6 « Retour dans 3 s ») — mirroir du
## défaut serveur `GameWorld.respawn_delay` (3.0, hors de ma liste de
## fichiers) ; purement cosmétique, la réapparition RÉELLE reste décidée par
## le serveur (`GameHUD.hide_death()` referme ce voile quand elle survient,
## indépendamment de ce compte à rebours local). Raccourci en test (même
## convention que `world.rematch_countdown_s`, tests/networking/
## test_rematch.gd) pour ne jamais coûter de secondes réelles.
@export var respawn_delay_s: float = 3.0

var _world_dim: ColorRect
var _title_label: Label
var _killer_card: Control
var _killer_name_label: Label
var _weapon_label: Label
var _remaining_hp_label: Label
var _empty_label: Label
var _respawn_label: Label
var _respawn_seconds_left: float = 0.0
var _respawn_running: bool = false

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)

	_world_dim = _build_desaturation_layer()
	add_child(_world_dim)

	# Voile de lisibilité léger (§6 ne prescrit qu'une désaturation, pas un
	# noir plein — le monde reste visible, juste éteint) : encre à faible
	# opacité, jamais un fond plein derrière le titre (règle §5 étendue ici
	# par cohérence, même si §5 vise nommément le HUD en jeu).
	var tint := ColorRect.new()
	tint.color = Color(Comic.ink_color().r, Comic.ink_color().g, Comic.ink_color().b, 0.35)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)

	# `CenterContainer`, PAS `Comic.anchor(v, PRESET_CENTER)` sur un `Control`
	# nu (bug vérifié en capture, corrigé ici) : `set_anchors_preset()` seul ne
	# touche JAMAIS `grow_horizontal`/`grow_vertical` (Godot 4.7,
	# `Control.grow_horizontal` -- valeur par défaut `1` = `GROW_DIRECTION_END`,
	# jamais `BOTH`), donc des ancres à 0,5 + offsets à zéro posent seulement
	# le COIN HAUT-GAUCHE du contenu au centre de l'écran, qui grandit ensuite
	# vers le bas-droite -- tout le voile de mort se retrouvait dans le
	# quadrant bas-droit. `CenterContainer` calcule sa propre taille mini à
	# partir de son enfant ET le centre réellement (même correctif déjà
	# appliqué à la carte MVP d'EndPanel.gd, relance QA ART-36 2e passage).
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", Comic.SP_5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(v)

	_title_label = _build_title_label()
	v.add_child(_title_label)

	_killer_card = _build_killer_card()
	v.add_child(_killer_card)

	_empty_label = Comic.body_label_v4("Réapparition imminente…", Comic.SIZE_28, Comic.paper_dim_color())
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.visible = false
	v.add_child(_empty_label)

	v.add_child(_build_respawn_bar())

## `killer_name` : nom du tueur tel qu'affiché dans `player_info`/le killfeed
## (vide par défaut — état VIDE tant que l'appelant n'a pas encore résolu
## l'identité du tueur : le titre « REMBALLÉ » seul reste correct, jamais un
## nom inventé). `weapon_name` : arme ou capacité utilisée, également
## optionnelle. `killer_remaining_hp` (nouveau, UX-34) : PV qu'il restait au
## tueur au moment du kill (§6 « Il lui restait 34 PV ») — négatif par défaut
## (inconnu) : la ligne correspondante reste alors ABSENTE plutôt qu'un
## chiffre inventé, `GameHUD._on_died` (hors de ma liste de fichiers) ne le
## fournit pas encore aujourd'hui.
## Câblé côté appelant par `GameHUD._on_died` (relance QA ART-36, 2e
## passage) : `killer_id` (reçu du signal `Health.died`) résout le nom via
## `player_info`, l'arme via le kill le plus récent reçu par
## `GameWorld.kill_logged` dont la victime est le joueur local — voir
## `GameHUD._on_died`/`GameHUD._on_kill_logged`.
func show_death(killer_name: String = "", weapon_name: String = "", killer_remaining_hp: float = -1.0) -> void:
	visible = true
	if killer_name.is_empty():
		_killer_card.visible = false
		_empty_label.visible = true
	else:
		_killer_card.visible = true
		_empty_label.visible = false
		_killer_name_label.text = ("▼ %s" % killer_name).to_upper()
		var has_weapon := not weapon_name.is_empty()
		_weapon_label.visible = has_weapon
		if has_weapon:
			_weapon_label.text = weapon_name.to_upper()
		var has_hp := killer_remaining_hp >= 0.0
		_remaining_hp_label.visible = has_hp
		if has_hp:
			_remaining_hp_label.text = "Il lui restait %d PV" % int(round(killer_remaining_hp))
	_start_respawn_countdown()

func hide_death() -> void:
	visible = false
	_respawn_running = false
	set_process(false)

func _start_respawn_countdown() -> void:
	_respawn_seconds_left = respawn_delay_s
	_respawn_running = true
	set_process(true)
	_update_respawn_label()

func _process(delta: float) -> void:
	if not _respawn_running:
		set_process(false)
		return
	_respawn_seconds_left = maxf(0.0, _respawn_seconds_left - delta)
	_update_respawn_label()
	if _respawn_seconds_left <= 0.0:
		_respawn_running = false

func _update_respawn_label() -> void:
	_respawn_label.text = "Retour dans %d s" % int(ceil(_respawn_seconds_left))

## Titre « REMBALLÉ » (§6/§4.1) : 157 `vital`, contour 5 (`STROKE_DISPLAY`),
## ombre dure (8, 8) — même valeur que `SHADOW_HOVER_OFFSET` sur l'échelle
## partagée des ombres dures (§4.3 "(8, 8) moments héros"), pas une
## coïncidence : les deux usages partagent le même jeton de distance —
## incliné −6° (titre de boss, §2), pivot recentré à chaque redimensionnement
## pour tourner autour du CENTRE du texte plutôt que du coin haut-gauche.
func _build_title_label() -> Label:
	var l := Comic.ink_label("REMBALLÉ", Comic.SIZE_157, Comic.vital_color(), Comic.title_font_v4())
	l.add_theme_constant_override("outline_size", Comic.STROKE_DISPLAY)
	l.add_theme_constant_override("shadow_offset_x", int(Comic.SHADOW_HOVER_OFFSET.x))
	l.add_theme_constant_override("shadow_offset_y", int(Comic.SHADOW_HOVER_OFFSET.y))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.rotation_degrees = -6.0
	l.resized.connect(func() -> void: l.pivot_offset = l.size * 0.5)
	return l

## Carte du tueur (§6 « carte du tueur (portrait, ▼ nom, arme, ... PV ») —
## plaque à coins coupés (`Comic.plate_style()`) + ombre dure portée en
## enfant (`Comic.hard_shadow_style()`), voir `_build_plate` : ComicPanel.gd
## (v3, coins arrondis, hors de ma liste de fichiers) ne pose pas les coins
## coupés v4.
func _build_killer_card() -> Control:
	var plate := _build_plate(Vector2(420.0, 0.0))
	var host: Control = plate.host
	var body: PanelContainer = plate.body

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Comic.SP_1)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(box)

	_killer_name_label = Comic.title_label_v4("", Comic.SIZE_37, Comic.enemy_color())
	_killer_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_killer_name_label)

	_weapon_label = Comic.meta_label_v4("", Comic.SIZE_21, Comic.paper_dim_color())
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_label.visible = false
	box.add_child(_weapon_label)

	_remaining_hp_label = Comic.body_label_v4("", Comic.SIZE_21, Comic.paper_dim_color())
	_remaining_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_remaining_hp_label.visible = false
	box.add_child(_remaining_hp_label)

	host.visible = false
	return host

## Barre « Retour dans N s » (§6, §4.5 « rayures de danger : barres de
## chargement seulement ») : rayures diagonales jaune/encre en tuile
## (`Comic.hatch_texture`, v3 INCHANGÉ, réutilisé avec ses DEUX couleurs pour
## produire un motif à deux tons plutôt que la variante à fond transparent) ;
## le texte reste lisible sur les deux tons grâce au contour/ombre encre de
## `Comic.ink_label` (§5 règle 1, même mécanisme que le titre ci-dessus),
## jamais un fond plein supplémentaire derrière lui.
func _build_respawn_bar() -> Control:
	var host := Control.new()
	host.custom_minimum_size = Vector2(320.0, 48.0)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var stripes := TextureRect.new()
	stripes.texture = Comic.hatch_texture(16, 8, Comic.signal_color(), Comic.ink_color())
	stripes.stretch_mode = TextureRect.STRETCH_TILE
	stripes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Comic.anchor(stripes, Control.PRESET_FULL_RECT)
	host.add_child(stripes)

	_respawn_label = Comic.ink_label("", Comic.SIZE_28, Comic.paper_color(), Comic.button_font_v4())
	_respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Comic.anchor(_respawn_label, Control.PRESET_FULL_RECT)
	host.add_child(_respawn_label)

	return host

## Shader de désaturation plein écran (voir la constante `_DESATURATE_SHADER_
## CODE` et la note de tête de fichier) — posé en PREMIER enfant (sous le
## voile d'encre et le contenu) pour lire, via `screen_texture`, tout ce qui a
## été dessiné avant lui (le monde 3D).
func _build_desaturation_layer() -> ColorRect:
	var dim := ColorRect.new()
	dim.color = Color.WHITE
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Comic.anchor(dim, Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = _DESATURATE_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("saturation", 1.0 - WORLD_DESATURATION)
	dim.material = mat
	return dim

## Plaque v4 minimaliste (coins coupés + ombre dure portée en enfant, §4.3) —
## `Comic.plate_style()`/`hard_shadow_style()` existent déjà (v4, INCHANGÉS,
## voir Comic.gd) ; seul cet assemblage (hôte + ombre décalée + panneau) est
## propre à ce fichier. Retourne `{host, body}` : `host` porte la taille
## minimale et se place dans l'arbre, `body` (`PanelContainer`, insère ses
## enfants selon `content_margin_*` du style posé) reçoit le contenu.
func _build_plate(min_size: Vector2, bg: Color = Comic.plate_color()) -> Dictionary:
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.custom_minimum_size = min_size

	# UX-34, REVUE LEAD point 5 (capture 01 : « encoche parasite en haut à
	# droite » sur la carte du tueur) -- `Comic.hard_shadow_style(0)` posait un
	# rectangle DROIT (radius 0, aucun coin coupé) derrière un `body` chamfré
	# (`Comic.plate_style`, coin haut-droit à 45°) : décalée de
	# `SHADOW_HARD_OFFSET` (6, 6), l'ombre droite dépassait du triangle coupé
	# par le chamfer du plateau de façade, dessinant un petit coin carré
	# parasite pile à l'endroit du chamfer. `Comic.plate_style(Comic.ink_color())`
	# partage EXACTEMENT la même géométrie chamfrée que `body` ci-dessous --
	# l'ombre ne peut plus dépasser que sur les bords droits/bas (l'effet de
	# relief voulu), jamais sur le coin coupé.
	var shadow := PanelContainer.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.add_theme_stylebox_override("panel", Comic.plate_style(Comic.ink_color()))
	Comic.anchor(shadow, Control.PRESET_FULL_RECT)
	shadow.offset_left = Comic.SHADOW_HARD_OFFSET.x
	shadow.offset_top = Comic.SHADOW_HARD_OFFSET.y
	shadow.offset_right = Comic.SHADOW_HARD_OFFSET.x
	shadow.offset_bottom = Comic.SHADOW_HARD_OFFSET.y
	host.add_child(shadow)

	var body := PanelContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_stylebox_override("panel", Comic.plate_style(bg))
	Comic.anchor(body, Control.PRESET_FULL_RECT)
	host.add_child(body)

	# `host` (Control nu, ci-dessus) ne remonte JAMAIS sa taille mini tout
	# seul — ce n'est pas un Container, contrairement à `body`
	# (PanelContainer), qui LUI réémet `minimum_size_changed` à chaque
	# changement de taille mini d'un descendant, à n'importe quelle
	# profondeur (comportement standard des Container Godot, voir la note de
	# ComicPanel.gd) : sans cette resynchronisation, un parent Container de
	# `host` (ex. le VBoxContainer de `_ready()`) lui donnerait une hauteur de
	# ZÉRO, laissant tout le contenu de la carte invisible/tassé — même piège
	# que celui déjà documenté et corrigé dans EndPanel.gd (carte MVP,
	# `CenterContainer` plutôt qu'un `Control` nu).
	body.minimum_size_changed.connect(func() -> void:
		host.custom_minimum_size = body.get_combined_minimum_size()
	)

	return {"host": host, "body": body}
