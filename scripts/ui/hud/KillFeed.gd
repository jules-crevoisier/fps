## KillFeed.gd
## Fil des éliminations (contrat lead 2026-09-27, HUD en jeu, point 5) —
## haut-droite : 5 entrées MAX (`trim_to_cap`), chacune tenue 5 s puis fondue
## en 0.3 s (`fade_alpha`/`is_expired`, fonctions PURES), nouvelle entrée
## glissée depuis la droite (`UiTokens.SLIDE_S`). Plaque PAPIER inclinée
## (JAUNE si le joueur LOCAL est le tueur), nom du tueur en couleur d'équipe
## profonde (BLUE_DEEP/MAGENTA_DEEP), silhouette de l'arme
## (WeaponIcon.icon_for_kill_feed — inconnue -> pictogramme "kill"),
## pictogramme headshot si `headshot`, nom de la victime.
## Alimenté par GameHUD.gd depuis GameWorld.kill_logged(killer, victim,
## killer_team, weapon_or_ability, headshot).
class_name KillFeed
extends Control

const CAP := 5
const HOLD_S := 5.0
const FADE_S := 0.3

## Une entrée = {"root": PanelContainer, "headshot_icon": TextureRect,
## "weapon_icon": TextureRect, "age": float}. Index 0 = la plus RÉCENTE
## (les nouvelles entrées sont insérées en tête, contrat "new entries slide
## in from the right" -- elles apparaissent donc en HAUT de la pile).
var _entries: Array = []
var _column: VBoxContainer


## Opacité (0..1) d'une entrée âgée de `age` secondes : pleine pendant
## `hold`, fondue linéairement sur `fade` ensuite, 0 au-delà. Fonction PURE.
static func fade_alpha(age: float, hold: float = HOLD_S, fade: float = FADE_S) -> float:
	if age <= hold:
		return 1.0
	if fade <= 0.0:
		return 0.0
	return clampf(1.0 - (age - hold) / fade, 0.0, 1.0)


static func is_expired(age: float, hold: float = HOLD_S, fade: float = FADE_S) -> bool:
	return age >= hold + fade


## Garde les `cap` entrées les plus RÉCENTES (fin du tableau) — l'appelant
## pousse les nouvelles entrées en fin de liste, jamais l'inverse.
static func trim_to_cap(entries: Array, cap: int = CAP) -> Array:
	if entries.size() <= cap:
		return entries.duplicate()
	return entries.slice(entries.size() - cap, entries.size())


func _ready() -> void:
	Comic.anchor(self, Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override("separation", UiTokens.S2)
	_column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_column.offset_right = -UiTokens.EDGE_MARGIN
	_column.offset_top = UiTokens.EDGE_MARGIN * 0.7
	_column.offset_left = _column.offset_right - 520.0
	_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_column)


func _process(delta: float) -> void:
	for entry in _entries.duplicate():
		entry["age"] += delta
		var root: Control = entry["root"]
		root.modulate.a = fade_alpha(entry["age"])
		if is_expired(entry["age"]):
			_entries.erase(entry)
			root.queue_free()


## `killer_team`/`local_team` : couleur d'équipe PROFONDE du nom du tueur —
## relative au joueur local, jamais l'index brut (même convention que
## `Comic.is_ally`/ScoreHUD.map_scores). `is_local_killer` : le joueur LOCAL
## est-il le tueur -> plaque JAUNE plutôt que papier.
func add_kill(killer_name: String, victim_name: String, killer_team: int, local_team: int,
		weapon_or_ability: String, headshot: bool, is_local_killer: bool) -> void:
	var entry := _build_entry(killer_name, victim_name, killer_team, local_team, weapon_or_ability, headshot, is_local_killer)
	_entries.push_front(entry)
	_column.add_child(entry["root"])
	_column.move_child(entry["root"], 0)
	_trim_visible()

	var root: Control = entry["root"]
	root.modulate.a = 0.0
	root.pivot_offset = Vector2(root.size.x, root.size.y * 0.5)
	root.scale = Vector2(1.0, 1.0)
	root.position.x += 60.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, UiTokens.SLIDE_S)
	tw.tween_property(root, "position:x", root.position.x - 60.0, UiTokens.SLIDE_S)


func _trim_visible() -> void:
	while _entries.size() > CAP:
		var dropped = _entries.pop_back()
		(dropped["root"] as Control).queue_free()


func _build_entry(killer_name: String, victim_name: String, killer_team: int, local_team: int,
		weapon_or_ability: String, headshot: bool, is_local_killer: bool) -> Dictionary:
	var root := PanelContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size_flags_horizontal = Control.SIZE_SHRINK_END   # la plaque épouse son contenu, calée à droite
	var fill := UiTokens.YELLOW if is_local_killer else UiTokens.PAPER
	root.add_theme_stylebox_override("panel", UiTokens.plate(fill, UiTokens.SKEW_DEG, UiTokens.DROP_SMALL, UiTokens.STROKE, Vector2(UiTokens.S2, UiTokens.S1 * 0.5)))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTokens.S2)

	var killer_color := UiTokens.BLUE_DEEP if Comic.is_ally(killer_team, local_team) else UiTokens.MAGENTA_DEEP
	row.add_child(UiTokens.make_label(killer_name, UiTokens.label(UiTokens.T_S, killer_color, 0, true), true))

	var weapon_icon := TextureRect.new()
	weapon_icon.texture = UiTokens.icon(WeaponIcon.icon_for_kill_feed(weapon_or_ability))
	weapon_icon.custom_minimum_size = Vector2(0, 30)
	weapon_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(weapon_icon)

	var headshot_icon := TextureRect.new()
	headshot_icon.texture = UiTokens.icon("headshot")
	# EXPAND_IGNORE_SIZE : sans lui, `custom_minimum_size` ci-dessous perd
	# face à la taille NATIVE du picto (expand_mode par défaut =
	# EXPAND_KEEP_SIZE) -- voir InventoryHUD._build_icon, même bogue.
	headshot_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	headshot_icon.custom_minimum_size = Vector2(26, 26)
	headshot_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	headshot_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	headshot_icon.visible = headshot
	row.add_child(headshot_icon)

	var victim_color := UiTokens.MAGENTA_DEEP if Comic.is_ally(killer_team, local_team) else UiTokens.BLUE_DEEP
	row.add_child(UiTokens.make_label(victim_name, UiTokens.label(UiTokens.T_S, victim_color, 0, true), true))

	root.add_child(row)
	return {"root": root, "headshot_icon": headshot_icon, "weapon_icon": weapon_icon, "age": 0.0}
