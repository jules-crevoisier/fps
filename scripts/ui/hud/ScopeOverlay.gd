## ScopeOverlay.gd
## Habillage plein écran d'une VRAIE lunette (tâche "quatre armes", 2026-09-28
## — `WeaponConfig.scoped == true`, seule l'Aiguille pour l'instant) : cercle
## clair au centre, vignette sombre puis noir plein au-delà (voir
## `assets/shaders/ui/scope_vignette.gdshader`, `_mask` ci-dessous — AUCUNE
## lecture de la scène, seul l'alpha varie), anneau d'encre épais + croix
## simple dessinés PAR-DESSUS par `_marks` (`_draw()` classique, direction
## « Planche » — `scripts/ui/theme/UiTokens.gd` : INK #1B1030, PAPER #FFF4E0,
## YELLOW #FFCE1F).
##
## N'apparaît QUE tant que le joueur est RÉELLEMENT en train de regarder dans
## la lunette (`is_fully_scoped`, fonction PURE testée directement dans
## tests/ui/test_scope_overlay.gd) : arme `scoped`, gâchette de visée tenue,
## ET transition ADS (`WeaponFeel.ads_progress`, même convention que le reste
## du projet) arrivée à son terme — jamais pendant la transition elle-même
## (un cercle qui saute en plein écran AVANT que la caméra n'ait fini de
## zoomer serait un artefact visuel, pas un effet voulu). `GameHUD.gd` pilote
## cette progression (`_scope_ads_t`) et appelle `update_scope`/`set_scoped_visible`
## chaque frame — CE fichier ne lit lui-même aucun état de jeu (mêmes
## garanties de pureté que Crosshair.gd pour son propre calcul de dispersion).
class_name ScopeOverlay
extends Control

const _SHADER := preload("res://assets/shaders/ui/scope_vignette.gdshader")

## Rayon du cercle de visée, fraction du PLUS PETIT côté de l'écran (§ style
## "Planche" — jamais un pixel fixe, pour rester cohérent à toute résolution).
const RADIUS_RATIO := 0.42
const VIGNETTE_WIDTH_RATIO := 0.11
const RING_WIDTH_PX := 10.0
const CROSS_LEN_PX := 30.0
const CROSS_GAP_PX := 7.0
const CROSS_THICKNESS_PX := 3.0

## Anneau d'encre + croix (contrat : "thick ink ring, simple cross") — nœud
## DÉDIÉ avec son PROPRE `_draw()` (jamais une méthode du parent connectée au
## signal `draw` d'un `Control` générique : `draw_arc`/`draw_line` exigent
## d'être appelés depuis le `_draw()` DE L'OBJET qui les reçoit, sinon le
## moteur refuse le tracé — "Drawing is only allowed inside this node's
## `_draw()`..."). Ajouté APRÈS `_mask` (voir `_ready`) : dessiné par-dessus,
## jamais mangé par le noir plein du masque.
class _Marks extends Control:
	var radius_px: float = 0.0

	func _draw() -> void:
		if radius_px <= 0.0:
			return
		var c := size * 0.5
		# Anneau d'encre épais -- liseré PAPIER en dessous pour rester lisible
		# même sur un fond très sombre. Constantes qualifiées `ScopeOverlay.` :
		# une classe imbriquée GDScript n'hérite pas implicitement des constantes
		# de la classe englobante par nom nu.
		draw_arc(c, radius_px, 0.0, TAU, 96, UiTokens.PAPER, ScopeOverlay.RING_WIDTH_PX + 4.0, true)
		draw_arc(c, radius_px, 0.0, TAU, 96, UiTokens.INK, ScopeOverlay.RING_WIDTH_PX, true)
		# Croix simple -- même gap central que Crosshair.gd (traits qui ne se
		# touchent jamais au centre).
		var axes: Array[Vector2] = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
		for axis in axes:
			var a: Vector2 = c + axis * ScopeOverlay.CROSS_GAP_PX
			var b: Vector2 = c + axis * (ScopeOverlay.CROSS_GAP_PX + ScopeOverlay.CROSS_LEN_PX)
			draw_line(a, b, UiTokens.INK, ScopeOverlay.CROSS_THICKNESS_PX + 2.0)
			draw_line(a, b, UiTokens.PAPER, ScopeOverlay.CROSS_THICKNESS_PX)

var _mask: ColorRect
var _marks: _Marks
var _mask_material: ShaderMaterial
var _radius_px: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_mask = ColorRect.new()
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask.color = Color.WHITE  # remplacé entièrement par le shader (COLOR), voir sa doc.
	Comic.anchor(_mask, Control.PRESET_FULL_RECT)
	_mask_material = ShaderMaterial.new()
	_mask_material.shader = _SHADER
	_mask.material = _mask_material
	add_child(_mask)

	_marks = _Marks.new()
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Comic.anchor(_marks, Control.PRESET_FULL_RECT)
	add_child(_marks)  # ajouté APRÈS `_mask` : dessiné par-dessus (jamais mangé par le noir plein).

## Arme/masque au rayon COURANT de l'écran — à rappeler si la fenêtre change
## de taille (voir `GameHUD._update_scope`), jamais mis en cache indéfiniment.
func refresh_layout() -> void:
	var s := size
	_radius_px = minf(s.x, s.y) * RADIUS_RATIO
	if _mask_material:
		_mask_material.set_shader_parameter("radius_px", _radius_px)
		_mask_material.set_shader_parameter("vignette_width_px", minf(s.x, s.y) * VIGNETTE_WIDTH_RATIO)
		_mask_material.set_shader_parameter("ink_color", UiTokens.INK)
	if _marks:
		_marks.radius_px = _radius_px
		_marks.queue_redraw()

## Affiche/masque l'ensemble (contrat : "shown only while fully scoped").
func set_scoped_visible(v: bool) -> void:
	if v == visible:
		return
	visible = v
	if v:
		refresh_layout()

## Le joueur regarde-t-il RÉELLEMENT dans une lunette CE frame ? Fonction PURE
## (aucun accès scène), seule source de vérité pour `GameHUD._update_scope` —
## `ads_t` = progression ADS courante (0 = hanche, 1 = visée pleine,
## `WeaponFeel.ads_progress`, même convention partout dans le projet).
static func is_fully_scoped(scoped: bool, aiming: bool, ads_t: float, threshold: float = 0.999) -> bool:
	return scoped and aiming and ads_t >= threshold
