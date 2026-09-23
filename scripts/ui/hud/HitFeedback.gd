## HitFeedback.gd
## Fonctions PURES (aucun état, aucun nœud) des retours de combat (design.md
## §8/§10, contract-r4a.md "R4-FX") : variante de hitmarker, fenêtre de
## correspondance kill <-> hit_confirmed, angle de la flèche de dégâts,
## courbes de fondu/chronologie, choix du mot-bruit, position du burst hors
## zone centrale et intensité de la vignette de vie basse. Isolées ici pour
## rester testables sans scène (voir tests/ui/test_hit_feedback.gd).
class_name HitFeedback
extends RefCounted

# ------------------------------------------------------------ Hitmarker (#1)
const MARKER_NORMAL := "normal"
const MARKER_HEADSHOT := "headshot"
const MARKER_KILL := "kill"

## Durée du hitmarker (design.md/contract : 120-200 ms).
const MARKER_DURATION := 0.16

## `is_kill` a priorité sur `headshot` (une balle de kill headshot reste la
## variante kill = croix, pas le tick alourdi).
static func marker_variant(headshot: bool, is_kill: bool) -> String:
	if is_kill:
		return MARKER_KILL
	if headshot:
		return MARKER_HEADSHOT
	return MARKER_NORMAL

# ------------------------------------------------------------ Fenêtre kill (#4)
## `Weapon.hit_confirmed` (tir) et `kill_logged` (mort confirmée) sont deux
## signaux distincts poussés par le serveur à des instants très proches pour
## le MÊME tir mortel (voir Health._die -> GameWorld._record_kill, toutes
## deux synchrones dans la résolution du coup). Cette fenêtre relie les deux
## côté HUD SANS toucher GameWorld.gd (hors périmètre R4-FX) : le dernier kill
## LOCAL connu (horodatage) "réclame" le hit_confirmed qui le suit de près.
const KILL_MATCH_WINDOW := 0.35

static func is_kill_hit(hit_time: float, last_kill_time: float, window: float = KILL_MATCH_WINDOW) -> bool:
	if last_kill_time < 0.0:
		return false
	var dt := hit_time - last_kill_time
	return dt >= 0.0 and dt <= window

# ------------------------------------------------------------ Flèche de dégâts (#2)
## Durée du fondu de la flèche (design.md : "fading over 1 s").
const WEDGE_DURATION := 1.0

## Angle (degrés, 0 = devant, 90 = droite, ±180 = derrière) entre l'avant du
## joueur et la source des dégâts, projeté sur le plan horizontal (ignore le
## tangage de la caméra : `forward`/`right` doivent venir du corps, pas de la
## tête). Source confondue avec l'origine => 0° (dégénéré, sans direction).
static func wedge_angle_deg(origin: Vector3, forward: Vector3, right: Vector3, source: Vector3) -> float:
	var to_source := source - origin
	to_source.y = 0.0
	if to_source.length_squared() < 0.0001:
		return 0.0
	var f := forward
	f.y = 0.0
	var r := right
	r.y = 0.0
	return rad_to_deg(atan2(to_source.dot(r), to_source.dot(f)))

## Opacité de la flèche (1 au début, 0 après `duration`).
static func wedge_alpha(elapsed: float, duration: float = WEDGE_DURATION) -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(1.0 - elapsed / duration, 0.0, 1.0)

# ------------------------------------------------------------ Mot-bruit (#4)
## "CRAC!" est RÉSERVÉ au headshot ; les autres tournent pour les kills au
## corps (design.md : « PAF!, BLAM!, CRAC! (headshot), VLAN! »).
const HEADSHOT_WORD := "CRAC!"
const KILL_WORDS := ["PAF!", "BLAM!", "VLAN!"]

static func sound_word(headshot: bool, pick: int) -> String:
	if headshot:
		return HEADSHOT_WORD
	return KILL_WORDS[posmod(pick, KILL_WORDS.size())]

## Chronologie du burst : 60 in / 180 hold / 60 out (design.md §10), ≤ 300 ms.
const BURST_IN := 0.06
const BURST_HOLD := 0.18
const BURST_OUT := 0.06
const BURST_DURATION := BURST_IN + BURST_HOLD + BURST_OUT

static func burst_alpha(elapsed: float) -> float:
	if elapsed < 0.0 or elapsed > BURST_DURATION:
		return 0.0
	if elapsed < BURST_IN:
		return clampf(elapsed / BURST_IN, 0.0, 1.0) if BURST_IN > 0.0 else 1.0
	if elapsed < BURST_IN + BURST_HOLD:
		return 1.0
	var out_t := elapsed - BURST_IN - BURST_HOLD
	return clampf(1.0 - out_t / BURST_OUT, 0.0, 1.0) if BURST_OUT > 0.0 else 0.0

## Petit "pop" d'entrée (0.6 -> 1.0 pendant BURST_IN), stable ensuite.
## `HitFeedback.burst_scale_reduced` (mouvement réduit) saute directement à 1.0.
static func burst_scale(elapsed: float) -> float:
	if elapsed < BURST_IN and BURST_IN > 0.0:
		return lerpf(0.6, 1.0, clampf(elapsed / BURST_IN, 0.0, 1.0))
	return 1.0

## Taille du burst (design.md : size 76 authored ~ marge confortable pour le
## halo + le mot) et sa position hors zone centrale (design.md §4/§8 : « placed
## OUTSIDE the centre 40 %×40 % zone »), à gauche ou à droite du viseur,
## centrée verticalement (croquis HUD : « ONO ... ONO » de part et d'autre).
const BURST_SIZE := Vector2(340.0, 170.0)
const BURST_MARGIN := 48.0  # Comic.SP_6

static func burst_rect(right_side: bool, viewport_size: Vector2) -> Rect2:
	var zone := HudFormat.center_zone_rect(viewport_size)
	var y := (viewport_size.y - BURST_SIZE.y) * 0.5
	var x: float
	if right_side:
		x = zone.position.x + zone.size.x + BURST_MARGIN
	else:
		x = zone.position.x - BURST_MARGIN - BURST_SIZE.x
	return Rect2(Vector2(x, y), BURST_SIZE)

# ------------------------------------------------------------ Vignette de vie basse (#3)
## Sous ce ratio de vie (35 %, design.md), les hachures commencent à ramper
## depuis les bords ; intensité maximale à 0 PV.
const VIGNETTE_HP_THRESHOLD := 0.35
const VIGNETTE_MAX_THICKNESS := 220.0
## Pulsation ≤ 1 Hz (design.md/contract).
const VIGNETTE_PULSE_HZ := 1.0

static func vignette_thickness(ratio: float, max_thickness: float = VIGNETTE_MAX_THICKNESS) -> float:
	var r := clampf(ratio, 0.0, 1.0)
	if r >= VIGNETTE_HP_THRESHOLD:
		return 0.0
	return (VIGNETTE_HP_THRESHOLD - r) / VIGNETTE_HP_THRESHOLD * max_thickness

## Multiplicateur d'alpha oscillant dans [0.6, 1.0] à `hz` Hz. Le mouvement
## réduit fige l'appel côté HUD (n'appelle jamais cette fonction) plutôt que
## de la modifier ici (elle reste pure et indépendante des réglages).
static func vignette_pulse(time: float, hz: float = VIGNETTE_PULSE_HZ) -> float:
	return 0.8 + 0.2 * sin(TAU * maxf(hz, 0.0) * time)
