## Minimap.gd
## Minimap HUD (UX-04, .orchestrator/design.md §12 "minimap 240 px" ;
## docs/research/04_ui_ux.md §2.1 "Valorant : minimap en haut à gauche... notre
## maquette suit ce schéma" — carte fixe, jamais un parti "carte qui pivote").
## Dessine en top-down les empreintes des pièces `Layouts.gd`/`layouts/*.gd`
## (LD-04 : sol/mur/couvert UNIQUEMENT, `color_key` in {floor,wall,cover}) via
## `Kit.piece_footprint()` — LA MÊME fonction pure que `Kit.build_piece` utilise
## pour poser la géométrie réelle (aucune re-dérivation de la géométrie d'une
## rampe/clôture/bâtiment ici, jamais une seconde source de vérité qui pourrait
## diverger). Le joueur reste au CENTRE, la carte est recentrée (translation
## pure, jamais de rotation) et une flèche tourne pour montrer son cap
## (`player_heading_rad`) — « oriente le joueur » sans faire pivoter le décor.
##
## Alliés (●) : toujours affichés (positions répliquées des coéquipiers,
## `GameHUD._update_minimap`). Ennemis (▼) : SEULEMENT ceux révélés par
## `RevealAbility`/`RenewalAbility` — `AbilityController.net_show_markers` pose
## un `Label3D` texte "!" visible à travers les murs UNIQUEMENT chez les
## coéquipiers du lanceur (RPC ciblée, jamais un broadcast). Cette classe ne
## lit JAMAIS la position d'un `PlayerController` ennemi directement : la
## SEULE source honnête d'une position ennemie est ce marqueur déjà poussé par
## le serveur à CE client (`revealed_enemy_positions`) — un ennemi non révélé
## n'a donc structurellement AUCUN moyen d'apparaître ici, le serveur
## n'envoyant rien de plus à ce client (contrat UX-04).
##
## Budget CPU (≤ 0,3 ms/image) : `footprints_from_pieces` (parcours de TOUTES
## les pièces Layouts + `Kit.piece_footprint`) tourne UNE SEULE FOIS par
## `set_layout()` (appelé au chargement de la carte — voir GameHUD), jamais
## par image. Le travail PAR IMAGE se limite à `footprints_in_range` (culling
## borne-à-rayon sur un Rect2 déjà calculé, pas de trigonométrie) puis
## `to_map_point` (une soustraction + une mise à l'échelle, linéaire) sur les
## formes retenues (~10-20 par carte, mesuré sur les 6 layouts) plus les
## quelques alliés/ennemis révélés — jamais O(taille de la carte) par image.
class_name Minimap
extends Control

## design.md §12 : "1920x1080: minimap 240" (1280x800 : 160, géré par le
## stretch canvas_items+expand du projet — voir Comic.SIZE_FLOOR, même parti).
const SIZE_PX := 240.0

## Rayon (m) de la fenêtre affichée autour du joueur — design.md/maps-spec ne
## fixe pas de zoom : CHOIX PROPRE À CETTE TÂCHE, assez large pour montrer 2-3
## pièces Layouts autour du joueur sans réduire leurs empreintes à des points
## (mesuré à la main sur les 6 maps : largeur de pièce type 8-15 m).
const VIEW_RADIUS_M := 28.0

const PLAYER_ARROW_PX := 7.0
const _GLYPH_FONT_SIZE := 20
## "N" (nord) : fourni au-dessus de la carte fixe (§5, ligne « haut-gauche »)
## — la carte ne pivote jamais (voir doc de classe), seule la flèche joueur
## tourne ; ce repère fixe confirme visuellement que le nord est "vers le
## haut" du panneau, même convention que `player_heading_rad`.
const _NORTH_GLYPH := "N"

## `color_key` (Layouts.gd) -> teinte minimap. `platform`/`accent` (rampes
## d'accès, décor) n'ont PAS d'empreinte minimap (hors du contrat UX-04, qui
## ne cite que sol/mur/couvert) — filtrées par `_VISIBLE_KINDS` ci-dessous.
const _KIND_COLOR := {
	"floor": Comic.PANEL_HI,
	"wall": Comic.RULE,
	"cover": Comic.DISABLED,
}
const _VISIBLE_KINDS := {"floor": true, "wall": true, "cover": true}

## Seule source honnête d'une position ennemie côté client (voir doc de
## classe) — texte EXACT posé par `AbilityController.net_show_markers`.
const REVEAL_MARKER_TEXT := "!"

var _footprints: Array = []
var _allies: Array = []
var _enemies: Array = []
var _player_pos: Vector3 = Vector3.ZERO
var _forward: Vector3 = Vector3(0.0, 0.0, -1.0)
## Plaque à coins coupés (UI_DIRECTION_BL3.md §5 « minimap à coins coupés »,
## §7 `shape.chamfer_px` minimap = 22 px) — la minimap est le SEUL conteneur
## boxed de ce coin du HUD (« Six ancres fixes », §5 #2 : c'est l'ancre
## elle-même, pas « du texte en boîte »). `Comic.plate_style()` (UX-30,
## hors de ce fichier mais déjà chargé par Comic.gd) remplace le
## `ComicPanel`/`Comic.panel_style()` v3 (coins carrés) que cette classe
## utilisait via son ancienne classe de base.
var _plate_style: StyleBoxFlat
var _north_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	Comic.anchor(self, Control.PRESET_TOP_LEFT)
	offset_left = Comic.SAFE_MARGIN
	offset_top = Comic.SAFE_MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# REVUE LEAD 2026-09-25T20:37 (« la minimap Wasteland déborde de son
	# cadre ») -- filet de sécurité VISUEL en plus du rognage géométrique de
	# `_draw()` (`footprint_screen_rect`/`positions_in_range` ci-dessus, qui
	# fait le vrai travail testable) : même patron que AgentSelectScreen.gd/
	# CrosshairEditor.gd (`clip_contents = true`, la fabrique déjà en place
	# dans ce dépôt pour "jamais dessiner hors du rect d'un Control").
	clip_contents = true
	_plate_style = Comic.plate_style(Comic.plate_color(), Comic.CHAMFER_PX_MINIMAP)
	resized.connect(queue_redraw)

	_north_label = Comic.label(_NORTH_GLYPH, Comic.SIZE_21, Comic.paper_dim_color(), Comic.FONT_LABEL)
	_north_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_north_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Comic.anchor(_north_label, Control.PRESET_TOP_WIDE)
	_north_label.offset_top = Comic.SP_1
	_north_label.offset_bottom = float(Comic.SIZE_21) + Comic.SP_1
	add_child(_north_label)

# ======================================================================
#  Fonctions PURES (testables sans nœud — tests/ui/test_minimap.gd)
# ======================================================================

## Empreintes (sol/mur/couvert) des pièces `Layouts.gd`/`layouts/*.gd` — voir
## doc de classe. `pieces` : `data["pieces"]` telle quelle (MÊME tableau que
## `MapSetup._build_geometry` consomme via `Kit.build_piece`).
static func footprints_from_pieces(pieces: Array) -> Array:
	var out: Array = []
	for entry in pieces:
		var p: Dictionary = entry
		var kind := String(p.get("color_key", ""))
		if not _VISIBLE_KINDS.has(kind):
			continue
		var fp: Dictionary = Kit.piece_footprint(p)
		var mn: Vector2 = fp["min"]
		var mx: Vector2 = fp["max"]
		if mx.x <= mn.x or mx.y <= mn.y:
			continue  # empreinte nulle (pièce mal formée, ex. ni pos ni start) : jamais dessinée.
		out.append({"rect": Rect2(mn, mx - mn), "kind": kind})
	return out

## Culling par rayon (m) autour du joueur — PLUS PROCHE POINT du rectangle
## (pas juste ses coins) : un long mur qui longe le joueur reste visible même
## si ses deux extrémités sont hors rayon.
static func footprints_in_range(footprints: Array, origin_xz: Vector2, radius_m: float) -> Array:
	var out: Array = []
	for entry in footprints:
		var fp: Dictionary = entry
		var rect: Rect2 = fp["rect"]
		var closest := Vector2(
			clampf(origin_xz.x, rect.position.x, rect.end.x),
			clampf(origin_xz.y, rect.position.y, rect.end.y)
		)
		if closest.distance_to(origin_xz) <= radius_m:
			out.append(fp)
	return out

## REVUE LEAD 2026-09-25T20:37 (capture 01_hud_wasteland_1080p.jpg, « la
## minimap Wasteland déborde de son cadre ... plan dessiné en bas à droite,
## hors du carré noir ») : `footprints_in_range` ci-dessus ne garde QUE les
## empreintes dont le point le plus proche est dans le rayon -- une empreinte
## RETENUE (un long mur qui longe le joueur, cf. sa docstring) peut quand même
## s'étendre BIEN AU-DELÀ du rayon sur son autre axe, et donc déborder du
## cadre carré une fois projetée. Cette fonction ROGNE le rectangle MONDE à la
## fenêtre carrée `[origin_xz - radius_m, origin_xz + radius_m]` (même rayon
## que `footprints_in_range`, même fenêtre que `px_per_meter`/`to_map_point`
## projettent exactement sur `[0, panel_size]`) AVANT toute projection --
## jamais après (roder après projection perdrait l'échelle mètres/px). Un
## `Rect2` sans aire (`has_area()` faux, empreinte entièrement hors fenêtre
## malgré `footprints_in_range` — ne peut arriver qu'à la marge flottante
## près) doit être ignoré par l'appelant, jamais dessiné.
static func clip_rect_to_view(rect: Rect2, origin_xz: Vector2, radius_m: float) -> Rect2:
	var view := Rect2(origin_xz - Vector2(radius_m, radius_m), Vector2(radius_m, radius_m) * 2.0)
	return rect.intersection(view)

## Rectangle ÉCRAN (px, prêt pour `draw_rect`) d'une empreinte -- ROGNE
## d'abord le rectangle MONDE à la fenêtre visible (`clip_rect_to_view`) PUIS
## le projette (`to_map_point`) : le rectangle rendu ne dépasse donc jamais
## `[0, panel_size]` des deux côtés, quelle que soit la taille réelle de
## l'empreinte (REVUE LEAD ci-dessus). `Rect2()` (aire nulle) si l'empreinte
## rognée est vide -- l'appelant (`_draw()`) doit ignorer ce cas via
## `has_area()`.
static func footprint_screen_rect(world_rect: Rect2, origin_xz: Vector2, radius_m: float, px_per_m: float, center: Vector2) -> Rect2:
	var clipped := clip_rect_to_view(world_rect, origin_xz, radius_m)
	if not clipped.has_area():
		return Rect2()
	var origin := Vector3(origin_xz.x, 0.0, origin_xz.y)
	var p0 := center + to_map_point(Vector3(clipped.position.x, 0.0, clipped.position.y), origin, px_per_m)
	var p1 := center + to_map_point(Vector3(clipped.end.x, 0.0, clipped.end.y), origin, px_per_m)
	return Rect2(p0, p1 - p0).abs()

## Filtre alliés/ennemis (`Vector3`, XZ) à la MÊME fenêtre carrée que les
## empreintes (`footprints_in_range`/`clip_rect_to_view`) — REVUE LEAD
## 2026-09-25T20:37 : sans ce filtre, un allié/ennemi au-delà du rayon affiché
## se dessinait quand même (`_draw()` parcourait `_allies`/`_enemies` SANS
## aucun culling), potentiellement hors du cadre 240 px — même défaut que les
## empreintes, corrigé de la même façon (un point hors fenêtre ne se dessine
## simplement plus, plutôt que d'être re-projeté/clampé sur le bord).
static func positions_in_range(positions: Array, origin_xz: Vector2, radius_m: float) -> Array:
	var out: Array = []
	for entry in positions:
		var v: Vector3 = entry
		if Vector2(v.x, v.z).distance_to(origin_xz) <= radius_m:
			out.append(v)
	return out

## Point MONDE (XZ) -> point minimap (px), recentré sur `origin` (le joueur),
## SANS rotation (carte fixe, voir doc de classe) — juste une translation et
## une mise à l'échelle, linéaire (budget CPU).
static func to_map_point(world_pos: Vector3, origin: Vector3, px_per_m: float) -> Vector2:
	return Vector2(world_pos.x - origin.x, world_pos.z - origin.z) * px_per_m

## Rayon minimap (px) -> échelle (px par mètre) pour `to_map_point`.
static func px_per_meter(panel_size_px: float, view_radius_m: float) -> float:
	if view_radius_m <= 0.0:
		return 0.0
	return (panel_size_px * 0.5) / view_radius_m

## Cap (rad) de la flèche joueur : 0 = pointe "vers le haut" du panneau
## (repli par défaut, `forward` nul) ; tourne pour suivre `forward` (XZ monde,
## basis.z inversé côté appelant — même convention que
## `HitFeedback.wedge_angle_deg`/`GameHUD._on_damage_from_direction`), la
## carte elle-même restant fixe.
static func player_heading_rad(forward: Vector3) -> float:
	var d := Vector2(forward.x, forward.z)
	if d.length_squared() < 0.0001:
		return 0.0
	return d.angle() + PI * 0.5

## Alliés à afficher (●, toujours) — `candidates`: Array[Dictionary{team:int,
## pos:Vector3}], sans le joueur local (l'APPELANT l'exclut déjà : jamais un
## point sur soi-même). Relatif à l'équipe locale, jamais l'équipe 0 en dur
## (`Comic.is_ally`, même règle que UX-01/KillfeedPanel).
static func ally_positions(candidates: Array, local_team: int) -> Array:
	var out: Array = []
	for entry in candidates:
		var c: Dictionary = entry
		if Comic.is_ally(int(c.get("team", -1)), local_team):
			out.append(c["pos"] as Vector3)
	return out

## Ennemis à afficher (▼) — UNIQUEMENT ceux révélés, voir doc de classe.
## `nodes` : n'importe quel tableau de `Node` (typiquement
## `get_tree().get_nodes_in_group("round_props")`, GameHUD._update_minimap) —
## seuls les `Label3D` au texte EXACT `REVEAL_MARKER_TEXT` comptent ; tout le
## reste (murs de fumée, tremplins, pièges...) est ignoré silencieusement.
static func revealed_enemy_positions(nodes: Array) -> Array:
	var out: Array = []
	for n in nodes:
		if n is Label3D and (n as Label3D).text == REVEAL_MARKER_TEXT:
			out.append((n as Label3D).global_position)
	return out

# ======================================================================
#  État (mis à jour par GameHUD, une fois par image — voir doc de classe)
# ======================================================================

## Charge les empreintes d'UNE carte — appelé au chargement (GameHUD
## `_acquire_map_setup`), JAMAIS par image (voir doc de classe, budget CPU).
func set_layout(pieces: Array) -> void:
	_footprints = footprints_from_pieces(pieces)
	queue_redraw()

func set_player_state(pos: Vector3, forward: Vector3) -> void:
	_player_pos = pos
	_forward = forward
	queue_redraw()

func set_allies(positions: Array) -> void:
	_allies = positions
	queue_redraw()

func set_enemies(positions: Array) -> void:
	_enemies = positions
	queue_redraw()

## Exposés pour rester testables SANS dépendre de `_draw()` (même parti que
## `Crosshair.current_gap_px()`/`current_bloom_alpha()`).
func footprint_count() -> int:
	return _footprints.size()

func ally_count() -> int:
	return _allies.size()

func enemy_count() -> int:
	return _enemies.size()

# ======================================================================
#  Rendu
# ======================================================================
func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	draw_style_box(_plate_style, Rect2(Vector2.ZERO, size))
	var center := size * 0.5
	var px_per_m := px_per_meter(minf(size.x, size.y), VIEW_RADIUS_M)
	var origin_xz := Vector2(_player_pos.x, _player_pos.z)
	for entry in footprints_in_range(_footprints, origin_xz, VIEW_RADIUS_M):
		var fp: Dictionary = entry
		# REVUE LEAD 2026-09-25T20:37 -- `footprint_screen_rect` ROGNE le
		# rectangle monde à la fenêtre visible AVANT projection (voir sa
		# docstring) : jamais le rectangle brut de `fp["rect"]` projeté tel
		# quel, qui pouvait déborder du cadre 240 px pour une empreinte longue.
		var screen_rect := footprint_screen_rect(fp["rect"], origin_xz, VIEW_RADIUS_M, px_per_m, center)
		if screen_rect.has_area():
			draw_rect(screen_rect, _KIND_COLOR.get(String(fp["kind"]), Comic.RULE))
	# Même rognage pour les glyphes alliés/ennemis (REVUE LEAD ci-dessus) --
	# `positions_in_range` : un point hors de la fenêtre visible ne se dessine
	# simplement plus, jamais projeté hors cadre.
	for a in positions_in_range(_allies, origin_xz, VIEW_RADIUS_M):
		_draw_glyph(center + to_map_point(a as Vector3, _player_pos, px_per_m), Comic.ALLY, "●")
	for e in positions_in_range(_enemies, origin_xz, VIEW_RADIUS_M):
		_draw_glyph(center + to_map_point(e as Vector3, _player_pos, px_per_m), Comic.enemy_color(), "▼")
	_draw_player_arrow(center)

func _draw_glyph(pos: Vector2, color: Color, glyph: String) -> void:
	var f := Comic.FONT_LABEL
	var sz := f.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, _GLYPH_FONT_SIZE)
	draw_string(f, pos - Vector2(sz.x * 0.5, -sz.y * 0.3), glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, _GLYPH_FONT_SIZE, color)

## Flèche `signal` (§5 « flèche signal ») — SEUL glyphe du HUD à porter le
## jaune ici ; un des ≤ 3 accents `signal` simultanés tolérés (§5 #5, voir
## AmmoPanel._reserve_color pour l'autre accent en jeu).
func _draw_player_arrow(center: Vector2) -> void:
	var heading := player_heading_rad(_forward)
	var pts := PackedVector2Array([
		Vector2(0.0, -PLAYER_ARROW_PX),
		Vector2(-PLAYER_ARROW_PX * 0.7, PLAYER_ARROW_PX * 0.6),
		Vector2(PLAYER_ARROW_PX * 0.7, PLAYER_ARROW_PX * 0.6),
	])
	var screen := PackedVector2Array()
	for p in pts:
		screen.append(center + p.rotated(heading))
	draw_colored_polygon(screen, Comic.signal_color())
