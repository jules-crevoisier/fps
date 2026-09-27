## BlindIndicator.gd
## Tell visuel comique au-dessus de la tête d'un joueur FLASHÉ (contrat lead
## 2026-09-27, point 4 : "so you can see whether you flashed the enemy") — 3
## petites étoiles à 4 pointes (StarburstMesh, réutilisé depuis ThrownUtility.gd)
## signal_yellow avec un liseré encre, billboardées, qui orbitent au-dessus de
## la tête avec un léger bob, popent en entrée/sortie. Diffusé à TOUS les
## pairs SAUF la victime locale elle-même (voir UtilityThrower._broadcast_blind_indicator,
## seul appelant) — celle-ci voit déjà son incrustation plein écran
## (UtilityThrower.local_blinded), un système entièrement séparé de CE fichier.
##
## Purement COSMÉTIQUE (aucune autorité réseau) : CHAQUE pair fait tourner sa
## propre instance indépendamment (comme SmokeCloud/ThrownUtility VFX) — un
## léger désaccord de timing d'un pair à l'autre (latence RPC) n'a aucune
## conséquence de jeu, contrairement au vol d'un ThrownUtility.
##
## Toute la logique de durée de vie (extension du minuteur, expiration, courbe
## d'échelle pop-in/tenue/pop-out) est en fonctions STATIQUES PURES, testées
## directement sans nœud (tests/combat/utility/test_blind_indicator.gd) — le
## nœud lui-même (`_physics_process`) ne fait que les appeler et piloter les
## meshes, jamais testé directement (même séparation que SmokeCloud.gd).
class_name BlindIndicator
extends Node3D

const _StarburstMesh := preload("res://scripts/combat/utility/vfx/StarburstMesh.gd")

const STAR_COUNT := 3
const STAR_OUTER_M := 0.18
const STAR_INNER_M := 0.075
## L'étoile d'encre est légèrement PLUS GRANDE que l'étoile de remplissage
## (même convention que ThrownUtility._spawn_starburst) pour lire comme un
## liseré tout autour, jamais un second contour identique superposé.
const _INK_SCALE := 1.15
const _FILL_COLOR := Color("FFCE1F")  # signal_yellow (tokens de style du projet).
const _INK_COLOR := Color("0E0A12")   # ink (tokens de style du projet).
## Dessinée AVANT l'étoile de remplissage (contrat : "an ink star behind
## each") — un `render_priority` plus bas garantit cet ordre sous N'IMPORTE
## QUEL angle de vue (contrat : "visible from any angle"), contrairement à un
## simple décalage de profondeur local qui ne serait fiable que de face.
const _INK_RENDER_PRIORITY := -1

const ORBIT_RADIUS_M := 0.35
const HEIGHT_ABOVE_HEAD_TOP_M := 0.35
const ORBIT_TURNS_PER_SEC := 1.2
const BOB_AMOUNT_M := 0.05
const BOB_PERIOD_S := 0.6

const POP_IN_S := 0.1
## Lisibilité de loin (revue lead 2026-09-27 : à 15 m, les étoiles n'étaient que
## deux points) : taille réelle jusqu'à DIST_SCALE_REF_M de la caméra, puis
## grossies avec la distance (taille à l'écran ~constante), plafonnées.
const DIST_SCALE_REF_M := 6.0
const DIST_SCALE_MAX := 4.0
const POP_OUT_S := 0.2

var _target: Node3D
var _remaining: float = 0.0
var _elapsed: float = 0.0
var _stars: Array = []  # [{"ink": MeshInstance3D, "fill": MeshInstance3D}, ...]

# ======================================================================
#  Logique PURE (durée de vie, courbe d'échelle, orbite) — testée directement.
# ======================================================================

## Un nouveau blind sur une cible déjà indiquée ÉTEND le minuteur (contrat :
## "extends the timer and does not stack a second indicator") — jamais un
## simple remplacement ni une addition : le plus LONG des deux l'emporte,
## qu'il s'agisse du blind déjà en cours ou du nouveau.
static func extended_remaining(current_remaining: float, new_duration: float) -> float:
	return maxf(current_remaining, new_duration)

static func is_expired(remaining: float) -> bool:
	return remaining <= 0.0

static func _smoothstep01(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## Progression 0 -> 1 du POP-IN (contrat : "pop in over 0.1s"), fonction du
## temps écoulé depuis la CRÉATION de l'indicateur — jamais réinitialisée par
## une extension du minuteur (contrat : ne "stack" jamais un second pop-in).
static func pop_in_progress(elapsed_since_start: float, pop_in_s: float = POP_IN_S) -> float:
	if pop_in_s <= 0.0:
		return 1.0
	return _smoothstep01(elapsed_since_start / pop_in_s)

## Progression 0 -> 1 du POP-OUT (contrat : "shrink out over the last 0.2s"),
## fonction du temps RESTANT avant expiration — vaut 1 tant qu'il reste plus de
## `pop_out_s`, redescend vers 0 uniquement dans la toute dernière fenêtre.
## Une EXTENSION repousse `remaining` vers le haut, donc ramène naturellement
## cette progression à 1 sans qu'aucun code dédié ne soit nécessaire.
static func pop_out_progress(remaining: float, pop_out_s: float = POP_OUT_S) -> float:
	if pop_out_s <= 0.0:
		return 1.0 if remaining > 0.0 else 0.0
	return _smoothstep01(remaining / pop_out_s)

## Échelle finale (0-1) des étoiles à cet instant — le plus restrictif des deux
## pop (jamais une somme/moyenne) : au tout début ET juste avant expiration,
## c'est bien le pop-in/pop-out qui doit dominer, pas l'autre.
## Facteur de taille selon la distance caméra -> indicateur (1 au plus près).
static func distance_scale(dist_m: float) -> float:
	return clampf(dist_m / DIST_SCALE_REF_M, 1.0, DIST_SCALE_MAX)

static func scale_factor(elapsed_since_start: float, remaining: float,
		pop_in_s: float = POP_IN_S, pop_out_s: float = POP_OUT_S) -> float:
	return minf(pop_in_progress(elapsed_since_start, pop_in_s), pop_out_progress(remaining, pop_out_s))

## Décalage LOCAL (par rapport au centre de l'orbite, lui-même déjà positionné
## au-dessus de la tête) de l'étoile `star_index`/`star_count` à l'instant
## `elapsed` — cercle de rayon `radius` dans le plan XZ (tourne à
## `turns_per_sec`), plus un léger bob vertical sinusoïdal. Fonction PURE,
## indépendante de `scale_factor` (l'appelant les combine).
static func orbit_offset(elapsed: float, star_index: int, star_count: int, radius: float,
		turns_per_sec: float, bob_amount: float, bob_period_s: float) -> Vector3:
	var count := maxi(star_count, 1)
	var angle := TAU * elapsed * turns_per_sec + TAU * float(star_index) / float(count)
	var bob := sin(TAU * elapsed / maxf(bob_period_s, 0.001)) * bob_amount
	return Vector3(cos(angle) * radius, bob, sin(angle) * radius)

# ======================================================================
#  Nœud — un SEUL indicateur par joueur (contrat : "does not stack a second
#  indicator"), créé/étendu par `apply_to`.
# ======================================================================

## `preload` de SOI-MÊME par CHEMIN (jamais le nom de classe global
## `BlindIndicator`, même dans SON PROPRE fichier) — même raison que
## `ThrownUtility._StarburstMesh`/`UtilityThrower._BlindIndicator` : le cache
## des classes globales de Godot n'est pas garanti à jour pour un fichier tout
## juste ajouté lors d'un run gdUnit4/outil `-s` en ligne de commande, y
## compris pour l'auto-référence d'un script à son PROPRE `class_name`.
const _Self := preload("res://scripts/combat/utility/vfx/BlindIndicator.gd")

## Crée (ou étend) l'indicateur du joueur `target` — cherche d'abord un
## indicateur déjà attaché sous `target` (nom de nœud fixe "BlindIndicator")
## avant d'en créer un nouveau, pour ne JAMAIS en empiler un second. Duck-typé
## (`.get`/`.set`, jamais `as BlindIndicator`) pour la même raison que `_Self`
## ci-dessus.
static func apply_to(target: Node3D, duration: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var existing := target.get_node_or_null("BlindIndicator")
	if existing:
		existing.set("_remaining", extended_remaining(float(existing.get("_remaining")), duration))
		return
	var indicator = _Self.new()
	indicator.name = "BlindIndicator"
	indicator.set("_target", target)
	indicator.set("_remaining", duration)
	target.add_child(indicator)

func _ready() -> void:
	_build_stars()

func _build_stars() -> void:
	for i in STAR_COUNT:
		var ink := _make_star_mesh(STAR_OUTER_M * _INK_SCALE, STAR_INNER_M * _INK_SCALE, _INK_COLOR)
		ink.material_override.render_priority = _INK_RENDER_PRIORITY
		add_child(ink)
		var fill := _make_star_mesh(STAR_OUTER_M, STAR_INNER_M, _FILL_COLOR)
		add_child(fill)
		_stars.append({"ink": ink, "fill": fill})

static func _make_star_mesh(outer: float, inner: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _StarburstMesh.build(4, outer, inner)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi

## Disparition immédiate si le joueur meurt/respawn (contrat) : sondé chaque
## tick physique via `Health.is_dead` — un poll à 60 Hz plutôt qu'une
## connexion de signal, pour ne dépendre d'aucun ordre d'initialisation entre
## ce nœud (ajouté APRÈS coup, à la première flash) et le Health de `target`
## (déjà prêt de toute façon, mais jamais une hypothèse à vérifier ici).
func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		queue_free()
		return
	var hp := _target.get_node_or_null("Health")
	if hp and bool(hp.get("is_dead")):
		queue_free()
		return
	_elapsed += delta
	_remaining -= delta
	if is_expired(_remaining):
		queue_free()
		return

	var top_y: float = float(_target.get("current_height")) if "current_height" in _target else 1.8
	position = Vector3(0.0, top_y + HEIGHT_ABOVE_HEAD_TOP_M, 0.0)

	var k := 1.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		k = distance_scale(cam.global_position.distance_to(global_position))
	var s := scale_factor(_elapsed, _remaining) * k
	for i in _stars.size():
		var offset := orbit_offset(_elapsed, i, _stars.size(), ORBIT_RADIUS_M * k, ORBIT_TURNS_PER_SEC, BOB_AMOUNT_M * k, BOB_PERIOD_S)
		var pair: Dictionary = _stars[i]
		var ink: MeshInstance3D = pair["ink"]
		var fill: MeshInstance3D = pair["fill"]
		ink.position = offset
		fill.position = offset
		ink.scale = Vector3.ONE * s
		fill.scale = Vector3.ONE * s
