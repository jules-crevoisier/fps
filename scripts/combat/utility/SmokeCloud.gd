## SmokeCloud.gd
## Nuage de fumigène PERSISTANT (survit à ThrownUtility, qui se libère à la
## détonation) — posé identiquement sur CHAQUE pair pour le rendu, avec en
## PLUS, côté SERVEUR SEULEMENT, un collider réel sur le calque
## PhysicsLayers.VISION qui bloque la ligne de vue des bots
## (BotPerception.has_los_to_any_point utilise déjà le masque PAR DÉFAUT —
## TOUS les calques, VISION compris — aucune modification de BotBrain.gd/
## BotPerception.gd n'est donc nécessaire, voir tests/ai/
## test_smoke_blocks_bot_los.gd). Minuterie PURE déléguée à SmokeMath.gd —
## ce fichier lit `SmokeMath.cloud_radius` chaque frame pour piloter à la fois
## le collider bloque-vue (inchangé) ET la présentation (contrat lead
## 2026-09-27, "smoke must BLOCK VISION") : un DÔME de 16-22 puffs OPAQUES
## (jamais de transparence — la fumée précédente, sphères translucides,
## laissait l'ennemi visible au travers) qui poussent en éventail depuis le
## point de détonation, respirent lentement, puis rétrécissent à zéro pour
## disparaître (jamais un fondu alpha, voir la docstring de `_process`).
##
## Filet de sécurité caméra : même à pleine densité, un dôme de sphères a des
## interstices géométriques ; un joueur dont la caméra est LITTÉRALEMENT DANS
## un puff (ou proche du centre) verrait alors au travers d'un interstice —
## `_update_camera_overlay` couvre ce cas d'un cache plein écran LOCAL (jamais
## répliqué aux autres pairs, voir sa docstring).
class_name SmokeCloud
extends Node3D

## Revue lead 2026-09-27 : 16-22 grosses sphères de 1,5-2,2 m lisaient comme
## des ballons ; plus de puffs, plus petits, donnent une silhouette de nuage BD.
const MIN_PUFFS := 24
const MAX_PUFFS := 30
const PUFF_RADIUS_MIN := 1.2
const PUFF_RADIUS_MAX := 1.8
## Centres des puffs : dôme POSÉ au sol (la grenade repose au sol), jamais
## dessous -- sous le sol, un puff n'apparaissait que comme une ellipse plate.
const PUFF_HEIGHT_MIN := 0.3
const PUFF_HEIGHT_MAX := 2.8
## Gris fumée chaud (vers le papier #FFF4E0) : le gris froid, éclairé par
## l'ambiance bleue, virait au bleu ciel.
const _COLOR_LO := Color("D6D0C6")
const _COLOR_HI := Color("EEE9DF")
## Ombre de chaque bouffée : même teinte, assombrie (aplat deux tons, voir le shader).
const _SHADE_FACTOR := 0.78
const _PUFF_SHADER := preload("res://assets/shaders/smoke_puff.gdshader")

const STAGGER_GROW_MAX_S := 0.3
const STAGGER_FADE_MAX_S := 0.3
const BOIL_AMOUNT := 0.05
const BOIL_PERIOD_MIN_S := 2.0
const BOIL_PERIOD_MAX_S := 3.0

## Marge de sécurité (fraction du rayon COURANT, déjà mis à l'échelle) sous
## laquelle la caméra locale est considérée "dans" un puff donné (contrat
## corrigé 2026-09-27 : le critère de distance au CENTRE du nuage, supprimé
## ci-dessous, laissait le cache actif ~4 m après avoir quitté les bouffées
## visibles — le centre est au SOL, sous le dôme, donc "loin" de toute
## bouffée réelle une fois qu'on s'en est éloigné). Voir `camera_inside_puff`.
const OVERLAY_SAFETY_MARGIN := 0.95
const OVERLAY_COLOR := Color("E2DDD3")
const OVERLAY_ALPHA := 0.92
const OVERLAY_FADE_S := 0.15
## Fondu de SORTIE plus rapide que l'entrée (retour utilisateur 2026-09-27) —
## `OVERLAY_FADE_S` reste la durée d'ENTRÉE (cache qui apparaît).
const OVERLAY_FADE_OUT_S := 0.1

var cfg: UtilityConfig
var _t: float = 0.0
## Un puff = {"node":MeshInstance3D, "slot":Vector3 (position locale à pleine
## croissance), "radius":float (rayon monde visé), "grow_delay":float,
## "fade_delay":float, "boil_phase":float, "boil_period":float}.
var _puffs: Array = []
var _has_collider: bool = false
var _collision_shape: SphereShape3D
var _rng := RandomNumberGenerator.new()

var _overlay: CanvasLayer
var _overlay_rect: ColorRect
## Correctif 2026-09-27 (même bug que le critère de distance au centre, voir
## le contrat "smoke overlay lingers") : la vignette des BORDS ne suivait PAS
## le fondu du cache central -- une fois affichée (`_ensure_overlay`,
## `_build_vignette`, ci-dessous), elle restait visible en PERMANENCE pour le
## reste de la vie du nuage même après que `_set_overlay_visible(false)` ait
## correctement fait disparaître le voile central. Référence gardée pour
## l'inclure dans le MÊME tween que `_overlay_rect` (voir `_set_overlay_visible`).
var _overlay_vignette: TextureRect
var _overlay_tween: Tween
var _camera_inside: bool = false

## Instancie et positionne le nuage à `pos` — appelé sur CHAQUE pair par
## ThrownUtility._spawn_detonation_vfx (`is_authority` réservé au SERVEUR :
## seul lui pose le collider bloque-vue réel, les clients n'ont pas de bots à
## faire raisonner).
static func spawn_local(pos: Vector3, cfg: UtilityConfig, is_authority: bool, scene: Node) -> void:
	if scene == null or cfg == null:
		return
	var cloud := SmokeCloud.new()
	cloud.cfg = cfg
	cloud._has_collider = is_authority
	scene.add_child(cloud)
	cloud.global_position = pos

func _ready() -> void:
	# Seed DÉTERMINISTE depuis la position de détonation (même valeur sur
	# CHAQUE pair, qui reçoivent tous la même `pos` via _broadcast_detonate) —
	# le dôme a donc la MÊME forme partout, pas seulement le même rayon.
	_rng.seed = int(global_position.x * 1000.0) ^ int(global_position.z * 1000.0) ^ int(global_position.y * 1000.0) ^ 7
	_build_puffs()
	if _has_collider:
		_build_collider()

func _build_puffs() -> void:
	var n := _rng.randi_range(MIN_PUFFS, MAX_PUFFS)
	for i in n:
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 16
		mesh.rings = 8
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var puff_color: Color = _COLOR_LO.lerp(_COLOR_HI, _rng.randf())
		mi.material_override = _puff_material(puff_color)
		mi.scale = Vector3.ZERO
		add_child(mi)
		_puffs.append({
			"node": mi,
			"slot": _dome_slot(i, n),
			"radius": _rng.randf_range(PUFF_RADIUS_MIN, PUFF_RADIUS_MAX),
			"grow_delay": _rng.randf_range(0.0, STAGGER_GROW_MAX_S),
			"fade_delay": _rng.randf_range(0.0, STAGGER_FADE_MAX_S),
			"boil_phase": _rng.randf_range(0.0, TAU),
			"boil_period": _rng.randf_range(BOIL_PERIOD_MIN_S, BOIL_PERIOD_MAX_S),
		})

## Position locale (à pleine croissance) du puff `i`/`n` — dôme posé au sol :
## azimut stratifié (une tranche de cercle par puff, gigue à l'intérieur,
## "seeded random") pour éviter les paquets qui laisseraient un couloir
## visible ; hauteur dans [PUFF_HEIGHT_MIN, PUFF_HEIGHT_MAX], biaisée vers le bas
## (`pow(u, 1.5)`) ; rayon horizontal borné par le profil du dôme (plus étroit
## en haut), en `[0.15, 0.95]` de ce profil pour couvrir aussi le bord.
func _dome_slot(i: int, n: int) -> Vector3:
	var slice := TAU / float(n)
	var azimuth := slice * float(i) + _rng.randf_range(0.0, slice)
	var h := lerpf(PUFF_HEIGHT_MIN, PUFF_HEIGHT_MAX, pow(_rng.randf(), 1.5))
	var dome_h := PUFF_HEIGHT_MAX * 1.2
	var profile := sqrt(maxf(0.0, 1.0 - (h / dome_h) * (h / dome_h)))
	var horiz := lerpf(0.15, 0.95, sqrt(_rng.randf())) * cfg.smoke_radius * profile
	return Vector3(cos(azimuth) * horiz, h, sin(azimuth) * horiz)

## Aplat BD deux tons (assets/shaders/smoke_puff.gdshader), opaque, indépendant
## de l'éclairage : avec toon_bd la face à l'ombre virait au bleu ciel.
static func _puff_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _PUFF_SHADER
	mat.set_shader_parameter("lit_color", color)
	mat.set_shader_parameter("shade_color", color.darkened(1.0 - _SHADE_FACTOR))
	return mat

func _build_collider() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.VISION
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	_collision_shape = SphereShape3D.new()
	_collision_shape.radius = 0.01
	col.shape = _collision_shape
	body.add_child(col)
	add_child(body)

## Ease-out "back" standard (easings.net) : dépasse légèrement 1 avant de s'y
## poser -- le "pop" comique de croissance (contrat : "ease-out (TRANS_BACK
## or QUAD)"). Fonction PURE.
static func _ease_out_back(x: float) -> float:
	const C1 := 1.70158
	const C3 := C1 + 1.0
	var t := x - 1.0
	return 1.0 + C3 * t * t * t + C1 * t * t

## Vrai si `cam_local_pos` (position LOCALE au nuage) est à l'intérieur de la
## sphère COURANTE (déjà mise à l'échelle : `puff_current_radius` = rayon de
## base × facteur d'échelle courant) d'UN SEUL puff — jamais un critère de
## distance au centre du nuage (voir le correctif de `_process`). Fonction
## PURE, testée directement sans nœud/scène (tests/combat/utility/test_smoke_cloud.gd) :
## `_process` l'appelle une fois par puff, par pair, chaque frame.
static func camera_inside_puff(cam_local_pos: Vector3, puff_local_pos: Vector3, puff_current_radius: float) -> bool:
	return cam_local_pos.distance_to(puff_local_pos) < puff_current_radius * OVERLAY_SAFETY_MARGIN

func _process(delta: float) -> void:
	_t += delta
	var envelope_radius := SmokeMath.cloud_radius(_t, cfg)
	var hold_end := cfg.smoke_grow_seconds + cfg.smoke_hold_seconds

	var local_cam := _local_camera()
	var cam_local_pos := Vector3.ZERO
	var have_cam := false
	if local_cam:
		cam_local_pos = to_local(local_cam.global_position)
		have_cam = true
	# Fix 2026-09-27 : PLUS de critère de distance au centre (le centre est au
	# sol, sous le dôme — il restait "proche" bien après avoir quitté les
	# puffs visibles). Le cache n'est actif QUE dans la sphère COURANTE d'au
	# moins un puff réel (voir `camera_inside_puff`, mis à jour dans la boucle
	# ci-dessous dès que chaque puff connaît son rayon mis à l'échelle).
	var camera_inside := false

	for entry in _puffs:
		var mi: MeshInstance3D = entry["node"]
		var grow_u: float = 1.0
		if cfg.smoke_grow_seconds > 0.0:
			grow_u = clampf((_t - entry["grow_delay"]) / cfg.smoke_grow_seconds, 0.0, 1.0)
		var eased := maxf(_ease_out_back(grow_u), 0.0)

		var fade_u := 1.0
		var fade_start: float = hold_end + entry["fade_delay"]
		if cfg.smoke_fade_seconds > 0.0:
			fade_u = 1.0 - clampf((_t - fade_start) / cfg.smoke_fade_seconds, 0.0, 1.0)
		elif _t >= fade_start:
			fade_u = 0.0

		var boil := 1.0 + sin(_t * TAU / float(entry["boil_period"]) + float(entry["boil_phase"])) * BOIL_AMOUNT
		var scale_factor := maxf(eased * fade_u * boil, 0.0)
		var slot: Vector3 = entry["slot"]
		var pos := slot * clampf(eased, 0.0, 1.0)
		mi.position = pos
		mi.scale = Vector3.ONE * maxf(float(entry["radius"]) * scale_factor, 0.0)

		if have_cam and not camera_inside:
			if camera_inside_puff(cam_local_pos, pos, float(entry["radius"]) * scale_factor):
				camera_inside = true

	_set_overlay_visible(camera_inside)

	if _collision_shape:
		_collision_shape.radius = maxf(envelope_radius, 0.01)
	if _t >= SmokeMath.total_lifetime(cfg) + STAGGER_FADE_MAX_S:
		_teardown_overlay()
		queue_free()

## Caméra du joueur HUMAIN LOCAL de CE pair (groupe "local_player", posé
## seulement sur soi-même par PlayerController._ready) — `null` sur un
## serveur dédié/un bot, jamais une exception.
func _local_camera() -> Camera3D:
	if not is_inside_tree():
		return null
	var locals := get_tree().get_nodes_in_group("local_player")
	if locals.is_empty():
		return null
	var me := locals[0] as PlayerController
	return me.camera if me else null

## Cache plein écran LOCAL (contrat : "This must be local-only (each peer
## checks its own camera)") — jamais diffusé, jamais posé par le serveur pour
## un bot : chaque `SmokeCloud` (une instance PAR PAIR, voir `spawn_local`)
## ne lit QUE `local_camera()`, qui ne résout jamais un bot ni un joueur
## distant.
func _set_overlay_visible(visible_now: bool) -> void:
	if visible_now == _camera_inside:
		return
	_camera_inside = visible_now
	_ensure_overlay()
	if _overlay_tween:
		_overlay_tween.kill()
	_overlay_tween = create_tween()
	var target_a := OVERLAY_ALPHA if visible_now else 0.0
	var duration := OVERLAY_FADE_S if visible_now else OVERLAY_FADE_OUT_S
	_overlay_tween.tween_property(_overlay_rect, "color:a", target_a, duration)
	# Même fondu que le voile central, sur le MÊME tween (voir le correctif
	# documenté par `_overlay_vignette`) -- la vignette n'a pas de teinte
	# propre à cibler (juste un dégradé noir baked dans sa texture), on anime
	# donc son `modulate:a` (0 = invisible, 1 = pleine intensité du dégradé).
	_overlay_tween.parallel().tween_property(_overlay_vignette, "modulate:a", 1.0 if visible_now else 0.0, duration)

func _ensure_overlay() -> void:
	if _overlay:
		return
	_overlay = CanvasLayer.new()
	_overlay.layer = 80
	add_child(_overlay)
	_overlay_rect = ColorRect.new()
	_overlay_rect.color = Color(OVERLAY_COLOR.r, OVERLAY_COLOR.g, OVERLAY_COLOR.b, 0.0)
	_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_overlay_rect)
	_overlay_vignette = _build_vignette()
	_overlay_vignette.modulate.a = 0.0
	_overlay.add_child(_overlay_vignette)

## Vignette radiale (assombrissement doux aux bords) — `GradientTexture2D` en
## remplissage radial, jamais un shader dédié (effet ponctuel, pas besoin
## d'un pipeline de post-traitement supplémentaire).
func _build_vignette() -> TextureRect:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	grad.add_point(1.0, Color(0.0, 0.0, 0.0, 0.4))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _teardown_overlay() -> void:
	if _overlay_tween:
		_overlay_tween.kill()
	if _overlay:
		_overlay.queue_free()
		_overlay = null
