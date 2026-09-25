## Crosshair.gd
## Réticule dynamique (GF-09, docs/research/01_game_feel.md #8 : « le réticule
## est statique alors que la dispersion varie de 0,25° à 5° ») : l'écart entre
## les traits reflète la dispersion RÉELLE de l'arme, recalculé CHAQUE FRAME
## par GameHUD._update_crosshair depuis la MÊME pipeline que le tir
## (Weapon._fire_local : spread_hip/aim + WeaponFeel.move_spread_deg +
## air_spread_add, ou pellet_spread pour un fusil à pompe) projetée à l'écran
## par WeaponFeel.crosshair_gap_px (formule tan(spread)/tan(fov_v/2) ×
## hauteur_écran/2, testée dans tests/ui/test_crosshair.gd). Un "bloom" (flash
## rouge translucide, WeaponFeel.crosshair_bloom_alpha) rend le spray visible
## SANS changer l'écart réel affiché. Masqué en ADS/lunette par GameHUD
## (`_crosshair.visible = not scoping`, inchangé — GF-09 ne touche pas à ce
## comportement).
##
## Éditeur de viseur (UX-03, docs/research/04_ui_ux.md §2.2 « couleur ;
## contour ; point central ; lignes intérieures et extérieures (longueur,
## épaisseur, écart, opacité) ; codes de viseur en import/export ») : `_draw()`
## lit désormais un dictionnaire `settings` (voir `DEFAULT_SETTINGS`) au lieu
## de constantes figées. `normalize_settings()` complète/borne tout dictionnaire
## partiel (jamais de clé manquante -> valeur par défaut, jamais de plantage
## sur un dictionnaire corrompu) ; `encode()`/`decode()` sérialisent ce
## dictionnaire en un CODE texte (Base64 de JSON pleine précision) — le MÊME
## mécanisme sert à la fois le partage (scripts/ui/CrosshairEditor.gd,
## "Copier"/"Importer") et la persistance (Settings.crosshair_settings, un
## dictionnaire déjà normalisé, écrit tel quel sous forme de code dans
## user://settings.cfg). `PRESETS` fournit les 4 préréglages requis (Défaut,
## Point, Croix fine, Croix épaisse — voir CrosshairEditor._PRESET_LABELS pour
## leurs libellés FR).
##
## La dispersion réelle (`current_gap_px()`, INCHANGÉE par cette tâche — API
## et constantes publiques de GF-09 encore verrouillées par
## tests/ui/test_crosshair.gd) continue de piloter l'écart affiché : `_draw()`
## calcule l'écart de chaque groupe de traits (intérieur/extérieur) comme
## `current_gap_px() - DEFAULT_GAP_PX + settings.xxx_gap` (voir `line_gap_px`,
## pure et testée) — le DELTA dynamique (spray/ADS) reste visible PAR-DESSUS
## l'écart choisi par le joueur, jamais remplacé par lui.
##
## Option "réticule statique" (`static_mode`) : gèle l'écart à `DEFAULT_GAP_PX`
## (delta dynamique nul) et coupe le bloom, pour les joueurs qui préfèrent un
## réticule purement cosmétique. Câblée bout en bout par cette tâche —
## `Settings.static_crosshair` (persistant) -> `GameHUD._build_crosshair`
## (`_crosshair.static_mode = Settings.static_crosshair`) -> case à cocher de
## CrosshairEditor.gd — la note historique de GF-09 qui bloquait ce câblage
## (Settings.gd/OptionsMenu.gd étaient hors de son périmètre) est résolue.
class_name Crosshair
extends Control

## Écart (px) affiché en mode statique, ou tant qu'aucune dispersion n'a
## encore été fournie — identique à l'ancien réticule fixe de GameHUD, et
## origine du delta dynamique consommé par `line_gap_px` (voir doc de classe).
const DEFAULT_GAP_PX := 5.0
const LINE_LENGTH_PX := 7.0
const LINE_THICKNESS_PX := 2.0
const CENTER_DOT_PX := 2.0

## Durée du fondu de bloom (s, "reduced motion: fades only" — un simple fondu,
## jamais désactivé par Settings.reduced_motion, voir WeaponFeel.crosshair_bloom_alpha).
const BLOOM_DURATION_S := 0.15
## Épaisseur (px) de l'anneau de bloom au pic (alpha = 1).
const BLOOM_RING_WIDTH_PX := 3.0
## Décalage (px) de l'anneau de bloom au-delà des traits.
const BLOOM_RING_OFFSET_PX := 4.0

# ------------------------------------------------------------ Réglages d'apparence (UX-03)
## Bornes de clamp (px/ratio) des champs numériques de `settings` — un même
## couple par famille de champs (intérieur/extérieur partagent leurs bornes),
## utilisées par `normalize_settings()`. Larges plutôt que strictement collées
## aux plages proposées par CrosshairEditor (filet de sécurité pour un code
## importé à la main, même principe que Settings.clamp_fov).
const _OPACITY_MIN := 0.0
const _OPACITY_MAX := 1.0
const _THICKNESS_MIN := 0.5
const _THICKNESS_MAX := 10.0
const _LENGTH_MIN := 1.0
const _LENGTH_MAX := 40.0
const _GAP_MIN := 0.0
const _GAP_MAX := 40.0
const _DOT_SIZE_MIN := 1.0
const _DOT_SIZE_MAX := 24.0

## Dictionnaire de réglages par défaut ("Défaut", voir `PRESETS`) — reproduit
## EXACTEMENT l'ancien réticule fixe de GF-09 (croix intérieure seule, écart
## `DEFAULT_GAP_PX`, longueur `LINE_LENGTH_PX`, épaisseur `LINE_THICKNESS_PX`,
## point central `CENTER_DOT_PX`, blanc, contour d'encre 1 px) — toute clé
## absente d'un dictionnaire fourni à `normalize_settings()` retombe ici.
## `color` n'a JAMAIS de canal alpha propre (toujours forcé à 1 par
## `normalize_settings` — seules les opacités PAR ÉLÉMENT ci-dessous
## contrôlent la transparence, pour éviter une double multiplication confuse).
const DEFAULT_SETTINGS := {
	"color": Color(1.0, 1.0, 1.0, 1.0),
	"outline_enabled": true,
	"outline_opacity": 1.0,
	"outline_thickness": 1.0,
	"dot_enabled": true,
	"dot_size": CENTER_DOT_PX,
	"dot_opacity": 1.0,
	"inner_enabled": true,
	"inner_length": LINE_LENGTH_PX,
	"inner_thickness": LINE_THICKNESS_PX,
	"inner_gap": DEFAULT_GAP_PX,
	"inner_opacity": 1.0,
	"outer_enabled": false,
	"outer_length": 3.0,
	"outer_thickness": 2.0,
	"outer_gap": 16.0,
	"outer_opacity": 0.7,
}

## 4 préréglages requis (UX-03, docs/research/04_ui_ux.md tâche UX-03 :
## "Défaut, Point, Croix fine, Croix épaisse") — dictionnaires COMPLETS
## (jamais construits par fusion à l'exécution : un `const Dictionary` ne peut
## pas appeler `.duplicate()`, même convention que Settings.GRAPHICS_PRESETS).
## `PRESET_IDS` fixe l'ORDRE d'affichage ; CrosshairEditor._PRESET_LABELS porte
## les libellés FR (séparation logique/présentation, même patron que
## Settings.LAYOUT_OPTIONS / OptionsMenu._LAYOUT_LABELS).
const PRESET_IDS := ["default", "dot", "thin_cross", "thick_cross"]
const PRESETS := {
	"default": {
		"color": Color(1.0, 1.0, 1.0, 1.0),
		"outline_enabled": true, "outline_opacity": 1.0, "outline_thickness": 1.0,
		"dot_enabled": true, "dot_size": 2.0, "dot_opacity": 1.0,
		"inner_enabled": true, "inner_length": 7.0, "inner_thickness": 2.0, "inner_gap": 5.0, "inner_opacity": 1.0,
		"outer_enabled": false, "outer_length": 3.0, "outer_thickness": 2.0, "outer_gap": 16.0, "outer_opacity": 0.7,
	},
	"dot": {
		"color": Color(1.0, 1.0, 1.0, 1.0),
		"outline_enabled": true, "outline_opacity": 1.0, "outline_thickness": 1.0,
		"dot_enabled": true, "dot_size": 4.0, "dot_opacity": 1.0,
		"inner_enabled": false, "inner_length": 7.0, "inner_thickness": 2.0, "inner_gap": 5.0, "inner_opacity": 1.0,
		"outer_enabled": false, "outer_length": 3.0, "outer_thickness": 2.0, "outer_gap": 16.0, "outer_opacity": 0.7,
	},
	"thin_cross": {
		"color": Color(1.0, 1.0, 1.0, 1.0),
		"outline_enabled": true, "outline_opacity": 1.0, "outline_thickness": 1.0,
		"dot_enabled": false, "dot_size": 2.0, "dot_opacity": 1.0,
		"inner_enabled": true, "inner_length": 6.0, "inner_thickness": 1.0, "inner_gap": 2.0, "inner_opacity": 1.0,
		"outer_enabled": false, "outer_length": 3.0, "outer_thickness": 2.0, "outer_gap": 16.0, "outer_opacity": 0.7,
	},
	"thick_cross": {
		"color": Color(1.0, 1.0, 1.0, 1.0),
		"outline_enabled": true, "outline_opacity": 1.0, "outline_thickness": 1.0,
		"dot_enabled": true, "dot_size": 3.0, "dot_opacity": 1.0,
		"inner_enabled": true, "inner_length": 10.0, "inner_thickness": 4.0, "inner_gap": 6.0, "inner_opacity": 1.0,
		"outer_enabled": false, "outer_length": 3.0, "outer_thickness": 2.0, "outer_gap": 16.0, "outer_opacity": 0.7,
	},
}

## Réglages d'apparence COURANTS, TOUJOURS normalisés (voir `apply_settings`) —
## jamais lus/écrits directement par un appelant, seulement via
## `apply_settings()`. `_draw()` s'y appuie à chaque frame.
var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)

## Option "réticule statique" (voir doc de classe) : false par défaut
## (réticule dynamique).
var static_mode: bool = false

var _gap_px: float = DEFAULT_GAP_PX
## INF tant qu'aucun tir n'a eu lieu depuis la création (pas de bloom à afficher).
var _time_since_shot: float = INF

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if _time_since_shot < BLOOM_DURATION_S:
		_time_since_shot += delta
		queue_redraw()

## Recalcule l'écart RÉEL depuis la dispersion courante (`spread_rad`, rad —
## MÊME valeur que celle utilisée pour le tir, voir doc de classe), la FOV
## verticale de la caméra (deg, `Camera3D.fov`) et la hauteur d'écran (px).
## Appelé CHAQUE FRAME par GameHUD._update_crosshair.
func update_spread(spread_rad: float, fov_v_deg: float, screen_height: float) -> void:
	_gap_px = WeaponFeel.crosshair_gap_px(spread_rad, deg_to_rad(fov_v_deg), screen_height)
	queue_redraw()

## Déclenche le bloom (GF-09, "bloom visible au spray") — appelé par GameHUD
## sur `Weapon.fired` (tir prédit localement, propriétaire uniquement).
func notify_shot() -> void:
	_time_since_shot = 0.0
	queue_redraw()

## Écart (px) réellement dessiné CE frame — `DEFAULT_GAP_PX` figé en mode
## statique, sinon la dernière dispersion fournie par `update_spread`. Exposé
## (pas seulement interne) pour rester testable sans dépendre de `_draw()`
## (tests/ui/test_crosshair.gd). INCHANGÉ par UX-03 : c'est le delta entre
## cette valeur et `DEFAULT_GAP_PX` que `line_gap_px()` ajoute à l'écart choisi
## par le joueur (voir doc de classe) — jamais l'inverse.
func current_gap_px() -> float:
	return DEFAULT_GAP_PX if static_mode else _gap_px

## Alpha (0..1) du bloom CE frame — 0 en mode statique (coupé), sinon suit
## `WeaponFeel.crosshair_bloom_alpha` depuis le dernier `notify_shot()`.
## Exposé pour les mêmes raisons que `current_gap_px`.
func current_bloom_alpha() -> float:
	if static_mode:
		return 0.0
	return WeaponFeel.crosshair_bloom_alpha(_time_since_shot, BLOOM_DURATION_S)

## Applique un dictionnaire de réglages (UX-03) — toujours NORMALISÉ
## (`normalize_settings`, jamais le dictionnaire brut fourni : un appelant qui
## passe un dictionnaire partiel ou corrompu — code importé à la main — ne
## fait jamais planter le tracé, voir doc de classe) puis redessine.
func apply_settings(s: Dictionary) -> void:
	settings = normalize_settings(s)
	queue_redraw()

## Complète TOUTE clé absente de `raw` par sa valeur de `DEFAULT_SETTINGS` et
## borne chaque champ numérique/couleur — jamais une mutation de `raw` (rend
## toujours un NOUVEAU dictionnaire), jamais un plantage sur un type/valeur
## inattendu (un champ invalide retombe silencieusement sur le défaut). Pure,
## testable sans nœud (tests/ui/test_crosshair_code.gd).
static func normalize_settings(raw: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULT_SETTINGS.duplicate(true)
	if raw.has("color") and raw.color is Color:
		var c: Color = raw.color
		# Alpha TOUJOURS à 1 (voir doc de `DEFAULT_SETTINGS`) : seules les
		# opacités par élément ci-dessous contrôlent la transparence.
		out.color = Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0), 1.0)
	for key in ["outline_enabled", "dot_enabled", "inner_enabled", "outer_enabled"]:
		if raw.has(key):
			out[key] = bool(raw[key])
	for key in ["outline_opacity", "dot_opacity", "inner_opacity", "outer_opacity"]:
		if raw.has(key) and (raw[key] is float or raw[key] is int):
			out[key] = clampf(float(raw[key]), _OPACITY_MIN, _OPACITY_MAX)
	for key in ["outline_thickness", "inner_thickness", "outer_thickness"]:
		if raw.has(key) and (raw[key] is float or raw[key] is int):
			out[key] = clampf(float(raw[key]), _THICKNESS_MIN, _THICKNESS_MAX)
	for key in ["inner_length", "outer_length"]:
		if raw.has(key) and (raw[key] is float or raw[key] is int):
			out[key] = clampf(float(raw[key]), _LENGTH_MIN, _LENGTH_MAX)
	for key in ["inner_gap", "outer_gap"]:
		if raw.has(key) and (raw[key] is float or raw[key] is int):
			out[key] = clampf(float(raw[key]), _GAP_MIN, _GAP_MAX)
	if raw.has("dot_size") and (raw.dot_size is float or raw.dot_size is int):
		out.dot_size = clampf(float(raw.dot_size), _DOT_SIZE_MIN, _DOT_SIZE_MAX)
	return out

## Sérialise un dictionnaire de réglages en un CODE texte partageable
## (docs/research/04_ui_ux.md §2.2 "codes de viseur en import/export") —
## Base64 (Marshalls, doc Godot "Marshalls" "utf8_to_base64") d'un JSON en
## PLEINE PRÉCISION (`JSON.stringify(.., full_precision=true)`, doc Godot
## "JSON" "stringify" : "stringifies unreliable float digits for exact
## decoding") pour un aller-retour `decode(encode(s)) == normalize_settings(s)`
## SANS PERTE (test) — jamais les 8 bits d'un hex couleur, qui tronqueraient
## silencieusement les valeurs choisies au curseur. Normalise d'abord `s`
## (jamais le dictionnaire brut encodé tel quel). Pure.
static func encode(s: Dictionary) -> String:
	var n := normalize_settings(s)
	var payload := {
		"v": 1,
		"color": [n.color.r, n.color.g, n.color.b],
		"outline_enabled": n.outline_enabled,
		"outline_opacity": n.outline_opacity,
		"outline_thickness": n.outline_thickness,
		"dot_enabled": n.dot_enabled,
		"dot_size": n.dot_size,
		"dot_opacity": n.dot_opacity,
		"inner_enabled": n.inner_enabled,
		"inner_length": n.inner_length,
		"inner_thickness": n.inner_thickness,
		"inner_gap": n.inner_gap,
		"inner_opacity": n.inner_opacity,
		"outer_enabled": n.outer_enabled,
		"outer_length": n.outer_length,
		"outer_thickness": n.outer_thickness,
		"outer_gap": n.outer_gap,
		"outer_opacity": n.outer_opacity,
	}
	return Marshalls.utf8_to_base64(JSON.stringify(payload, "", true, true))

## Lit un CODE produit par `encode()` (ou tapé/collé à la main dans
## CrosshairEditor) et rend le dictionnaire de réglages correspondant,
## NORMALISÉ. Un code vide, mal formé (Base64 invalide, JSON invalide, racine
## qui n'est pas un dictionnaire) ou dont `color` n'a pas 3 composantes retombe
## silencieusement sur `DEFAULT_SETTINGS` PUIS relit les autres clés présentes
## et valides plutôt que d'abandonner tout le dictionnaire — jamais de
## plantage sur une entrée utilisateur (même philosophie défensive que
## Settings.gd, ex. `clamp_fov`/`migrate_fov`). Pure.
static func decode(code: String) -> Dictionary:
	if code.is_empty():
		return DEFAULT_SETTINGS.duplicate(true)
	var json_text := Marshalls.base64_to_utf8(code)
	if json_text.is_empty():
		return DEFAULT_SETTINGS.duplicate(true)
	var parsed = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return DEFAULT_SETTINGS.duplicate(true)
	var parsed_dict: Dictionary = parsed
	var raw: Dictionary = DEFAULT_SETTINGS.duplicate(true)
	if parsed_dict.has("color") and parsed_dict["color"] is Array and (parsed_dict["color"] as Array).size() == 3:
		var pc: Array = parsed_dict["color"]
		raw.color = Color(float(pc[0]), float(pc[1]), float(pc[2]))
	for key in DEFAULT_SETTINGS:
		if key == "color":
			continue
		if parsed_dict.has(key):
			raw[key] = parsed_dict[key]
	return normalize_settings(raw)

# ------------------------------------------------------------ Paramètres de tracé (purs, UX-03)
## Écart RÉEL (px) d'un groupe de traits (intérieur OU extérieur) : le DELTA
## dynamique entre `dynamic_gap_px` (`current_gap_px()`, spray/ADS — GF-09,
## INCHANGÉ) et `DEFAULT_GAP_PX` s'ADDITIONNE à l'écart choisi par le joueur
## (`setting_gap_px`, `settings.inner_gap`/`outer_gap`) — jamais l'un ou
## l'autre seul : un joueur qui agrandit son écart de base voit quand même le
## spray s'ouvrir PAR-DESSUS sa préférence, et le mode statique (delta nul,
## `current_gap_px()` fige à `DEFAULT_GAP_PX`) rend exactement `setting_gap_px`.
## Pure, testable sans nœud (tests/ui/test_crosshair_code.gd).
static func line_gap_px(dynamic_gap_px: float, setting_gap_px: float) -> float:
	return dynamic_gap_px - DEFAULT_GAP_PX + setting_gap_px

## Couleur d'un élément (point central / traits intérieurs / traits
## extérieurs) : `base` (settings.color, alpha toujours 1, voir
## `normalize_settings`) multipliée par l'opacité PROPRE de l'élément
## (`settings.xxx_opacity`, bornée [0,1] avant l'appel par
## `normalize_settings` — reclampée ici en filet de sécurité). Pure.
static func element_color(base: Color, opacity: float) -> Color:
	return Color(base.r, base.g, base.b, base.a * clampf(opacity, 0.0, 1.0))

# ------------------------------------------------------------ Tracé (UX-03 : depuis `settings`)
func _draw() -> void:
	var dyn_gap := current_gap_px()
	var col: Color = settings.color
	var outline_on: bool = settings.outline_enabled
	var outline_a: float = settings.outline_opacity
	var outline_w: float = settings.outline_thickness

	if settings.inner_enabled:
		_draw_axis_lines(
			line_gap_px(dyn_gap, settings.inner_gap), settings.inner_length, settings.inner_thickness,
			element_color(col, settings.inner_opacity), outline_on, outline_a, outline_w)
	if settings.outer_enabled:
		_draw_axis_lines(
			line_gap_px(dyn_gap, settings.outer_gap), settings.outer_length, settings.outer_thickness,
			element_color(col, settings.outer_opacity), outline_on, outline_a, outline_w)
	if settings.dot_enabled:
		_draw_center_dot(settings.dot_size, element_color(col, settings.dot_opacity), outline_on, outline_a)

	var bloom := current_bloom_alpha()
	if bloom > 0.0:
		_draw_bloom_ring(dyn_gap, bloom)

## Trace UN groupe de 4 traits (haut/bas/gauche/droite), du bord intérieur
## (`gap` px du centre) vers l'extérieur (`gap + length`) — liseré sombre
## (contour, si activé) + trait plein, comme l'ancien réticule fixe
## (GameHUD._cross_line, retiré par GF-09). Un `gap` négatif (dictionnaire
## importé à la main avec un écart extrême et une forte dispersion dynamique
## négative — ne devrait pas arriver, `line_gap_px` reste néanmoins non bornée
## par construction) donne simplement des traits qui traversent le centre :
## jamais un crash, `draw_line` accepte des points de part et d'autre de l'origine.
func _draw_axis_lines(gap: float, length: float, thickness: float, col: Color, outline_on: bool, outline_a: float, outline_w: float) -> void:
	var axes: Array[Vector2] = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
	for axis in axes:
		var a: Vector2 = axis * gap
		var b: Vector2 = axis * (gap + length)
		if outline_on:
			draw_line(a, b, Color(Comic.BG.r, Comic.BG.g, Comic.BG.b, outline_a), thickness + outline_w * 2.0)
		draw_line(a, b, col, thickness)

## Point central carré, liseré sombre (contour, si activé) en dessous.
func _draw_center_dot(size: float, col: Color, outline_on: bool, outline_a: float) -> void:
	if outline_on:
		var pad := 1.0
		draw_rect(Rect2(-(size * 0.5 + pad), -(size * 0.5 + pad), size + pad * 2.0, size + pad * 2.0),
			Color(Comic.BG.r, Comic.BG.g, Comic.BG.b, outline_a))
	draw_rect(Rect2(-size * 0.5, -size * 0.5, size, size), col)

## Anneau translucide (bloom) autour de l'écart RÉEL (`gap`, avant l'ajout de
## l'écart choisi par le joueur — le bloom signale la dispersion, pas
## l'apparence, voir doc de classe) — SEUL le fondu (`alpha`) anime, le rayon
## reste fixe : conforme à "reduced motion: fades only".
func _draw_bloom_ring(gap: float, alpha: float) -> void:
	var r := gap + LINE_LENGTH_PX + BLOOM_RING_OFFSET_PX
	var c := Comic.BULLET
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(c.r, c.g, c.b, alpha * 0.6), BLOOM_RING_WIDTH_PX, true)
