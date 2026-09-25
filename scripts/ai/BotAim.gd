## BotAim.gd
## Modèle PUR de visée humain-like — v2 (BOT-26, docs/research/08_bots_
## humanlike.md §3.2 règles A1-A6/A9, valeurs §3.8). Remplace le modèle v1
## (BOT-02) : offset qui SAUTAIT sur un anneau toutes les 0.35-0.7 s puis
## ressort qui « flickait » avec un dépassement fixe de 10 %. Désormais :
## - un OBJECTIF d'offset (magnitude + axe, gaussienne 2D ANISOTROPE, ratio de
##   flick aléatoire) est tiré périodiquement, par intervalle propre à chaque
##   difficulté (A2) ;
## - l'offset courant COURT après cet objectif via un filtre du 1er ordre
##   τ = 0.16 s (comme CS) — jamais un saut, quelle que soit la fréquence de
##   tirage (`offset_filter_step`) ;
## - la magnitude de base décroît en suivi avec un τ propre à la difficulté
##   (A3), remonte si la cible bouge vite (inchangé, BOT-02) OU si la vue
##   PROPRE du bot tourne trop vite ou s'il se déplace vite (A9) ;
## - la visée en SUIVI poursuit une position RETARDÉE de la cible (file de
##   perception, A5) plutôt que sa position vraie du tick courant ;
## - le ressort-amortisseur est désormais CRITIQUE (aucun dépassement
##   intrinsèque, A4 : « plus de dépassement fixe ») et son accélération est
##   PLAFONNÉE par difficulté (A1) — le dépassement humain vient maintenant du
##   ratio de flick appliqué à l'OFFSET (A4), pas du ressort lui-même.
## Aucun accès à l'arbre de scène — consommé par scripts/ai/BotBrain.gd, testé
## isolément dans tests/ai/test_bot_aim.gd.
##
## Compatibilité : `spring_natural_freq(peak_speed_deg, zeta)` garde SA
## signature à 2 arguments — scripts/ai/BotLook.gd (BOT-25, hors de ma liste
## de fichiers) l'appelle directement avec son propre zeta (0.9, quasi
## critique mais pas critique) pour SON ressort de regard hors combat.
##
## Référence : docs/research/08_bots_humanlike.md §3.2 (A1-A6, A9) et §3.8
## (table des paliers). Les valeurs sont écrites ICI ; BOT-11 les déplacera
## dans resources/bots/*.tres.
class_name BotAim
extends RefCounted

# ======================================================================
#  ERREUR D'ANGLE — magnitude (deg), régénérée périodiquement par
#  l'appelant (jamais recalculée par frame), décroissante en suivi (A3),
#  remontée par la vitesse angulaire propre du bot ou son déplacement (A9).
# ======================================================================

## Multiplicateur d'erreur appliqué quand la cible a une vitesse angulaire
## apparente (deg/s, vue depuis le bot) supérieure à ce seuil — un flick sur
## une cible qui strafe est moins précis qu'un suivi sur une cible immobile.
## Inchangé depuis BOT-02 (A1-A6/A9 ne modifient pas ce seuil).
const FAST_TARGET_ANGULAR_SPEED_DEG := 60.0
const FAST_TARGET_ERROR_MULT := 1.5

## A9 (règle 1) : si la vue PROPRE du bot (son propre ressort de visée)
## tourne à plus de ce seuil (deg/s), l'erreur courante remonte à AU MOINS
## cette fraction de son maximum (`max_error_deg`) — « comme CS » : un flick
## qui vient de se produire dégrade la précision qui suit, jamais l'inverse.
const OWN_VIEW_SPEED_THRESHOLD_DEG := 100.0
const OWN_VIEW_ERROR_FLOOR_RATIO := 0.5

## A9 (règle 2, comme UT^2) : au-delà de cette fraction de la vitesse de
## sprint, l'erreur est multipliée par ce facteur — tirer en pleine course
## est moins précis que tirer à l'arrêt ou en marche.
const OWN_MOVEMENT_SPEED_THRESHOLD_RATIO := 0.5
const OWN_MOVEMENT_ERROR_MULT := 1.3

## Erreur MAX (deg) à l'acquisition d'une cible (tracking_time = 0), par
## difficulté (MatchConfig.Difficulty) — inchangé depuis BOT-02, décroît
## ensuite avec `current_error_deg`.
static func max_error_deg(difficulty: int) -> float:
	match difficulty:
		MatchConfig.Difficulty.RECRUE:
			return 5.0
		MatchConfig.Difficulty.ELITE:
			return 1.0
		_:
			return 2.5  # VETERAN

## A3 : constante de décroissance (s) de l'erreur pendant le suivi CONTINU
## d'une même cible — propre à chaque difficulté depuis BOT-26 (v1 utilisait
## 0.8 s pour toutes : ça reste la valeur Vétéran, inchangée).
static func tracking_shrink_tau(difficulty: int) -> float:
	match difficulty:
		MatchConfig.Difficulty.RECRUE:
			return 1.5
		MatchConfig.Difficulty.ELITE:
			return 0.45
		_:
			return 0.8  # VETERAN

## Magnitude (deg) du prochain offset d'erreur à appliquer : décroissance
## exponentielle (`tracking_shrink_tau`) depuis `max_error_deg` en fonction du
## temps de suivi CONTINU (`tracking_time`, s, depuis l'acquisition de la
## cible — PAS depuis la dernière régénération), majorée si la cible bouge
## vite en angle apparent (`target_angular_speed_deg`), si la vue PROPRE du
## bot tourne vite (`own_view_speed_deg`, A9 règle 1) ou s'il se déplace vite
## (`own_speed_ratio`, part de la vitesse de sprint, A9 règle 2).
## Ne JAMAIS appeler ce calcul à chaque frame : seulement à l'acquisition et
## à chaque régénération périodique (voir `next_regen_interval`).
static func current_error_deg(
	difficulty: int,
	tracking_time: float,
	target_angular_speed_deg: float = 0.0,
	own_view_speed_deg: float = 0.0,
	own_speed_ratio: float = 0.0
) -> float:
	var base := max_error_deg(difficulty)
	var tau := tracking_shrink_tau(difficulty)
	var t := maxf(tracking_time, 0.0)
	var err := base * exp(-t / tau)
	if target_angular_speed_deg > FAST_TARGET_ANGULAR_SPEED_DEG:
		err *= FAST_TARGET_ERROR_MULT
	if own_view_speed_deg > OWN_VIEW_SPEED_THRESHOLD_DEG:
		err = maxf(err, base * OWN_VIEW_ERROR_FLOOR_RATIO)
	if own_speed_ratio > OWN_MOVEMENT_SPEED_THRESHOLD_RATIO:
		err *= OWN_MOVEMENT_ERROR_MULT
	return err

# ======================================================================
#  A2 — OFFSET QUI DÉRIVE : un objectif d'offset est tiré périodiquement (par
#  intervalle propre à la difficulté), l'offset COURANT le rejoint par un
#  filtre du 1er ordre τ = 0.16 s — jamais un saut, quel que soit
#  l'intervalle de tirage.
# ======================================================================

## Bornes (s) de l'intervalle entre deux tirages d'un NOUVEL objectif
## d'offset, par difficulté (§3.8 « Intervalle de l'offset ») —
## remplace REGEN_INTERVAL_MIN/MAX (BOT-02, uniforme 0.35-0.7 s pour toutes
## les difficultés) : plus la difficulté est haute, plus l'objectif change
## vite (et donc plus l'offset dérive souvent vers une nouvelle zone).
const OFFSET_INTERVAL_RECRUE := Vector2(0.6, 1.0)
const OFFSET_INTERVAL_VETERAN := Vector2(0.3, 0.6)
const OFFSET_INTERVAL_ELITE := Vector2(0.15, 0.35)

static func offset_regen_interval_range(difficulty: int) -> Vector2:
	match difficulty:
		MatchConfig.Difficulty.RECRUE:
			return OFFSET_INTERVAL_RECRUE
		MatchConfig.Difficulty.ELITE:
			return OFFSET_INTERVAL_ELITE
		_:
			return OFFSET_INTERVAL_VETERAN

## Intervalle (s) avant le prochain tirage d'un nouvel objectif d'offset —
## tiré uniformément dans la fourchette de `difficulty` (jamais un intervalle
## fixe : la périodicité elle-même doit varier pour ne pas être
## détectable/mécanique, comme en BOT-02).
static func next_regen_interval(rng: RandomNumberGenerator, difficulty: int) -> float:
	var r := offset_regen_interval_range(difficulty)
	return rng.randf_range(r.x, r.y)

## Filtre du 1er ordre (τ = OFFSET_FILTER_TAU, comme CS) : fait avancer
## `current` vers `target` d'une fraction Δt/τ de l'écart restant, jamais un
## saut — à 60 Hz et τ = 0.16 s, ça fait ~10 % de l'écart par tick (voir
## docs/research/08_bots_humanlike.md, table §1 ligne 2 : « Dérive : 10 % de
## l'écart par mise à jour »). Appelé CHAQUE tick, jamais seulement à la
## régénération — c'est ce qui remplace le saut de BOT-02.
const OFFSET_FILTER_TAU := 0.16

static func offset_filter_step(current: float, target: float, delta: float) -> float:
	var alpha := 1.0 - exp(-delta / OFFSET_FILTER_TAU)
	return current + (target - current) * alpha

# ======================================================================
#  A3 — FORME DE L'ERREUR : gaussienne 2D ANISOTROPE, σ dans l'axe du
#  dernier flick = AXIS_SIGMA_RATIO × σ perpendiculaire, même amplitude
#  quadratique moyenne (RMS) que la magnitude scalaire `current_error_deg`
#  d'avant (BOT-02 plaçait toute l'erreur sur un anneau de rayon exact —
#  RMS = rayon ; ici RMS = sqrt(σ_axe² + σ_perp²) doit rester égal à
#  `error_rms_deg` pour ne pas changer la précision globale, seulement sa
#  RÉPARTITION directionnelle).
# ======================================================================

const AXIS_SIGMA_RATIO := 2.2

## σ perpendiculaire à l'axe du dernier flick (deg) pour une erreur RMS
## totale de `error_rms_deg` — résolu de RMS² = σ_axe² + σ_perp² avec
## σ_axe = AXIS_SIGMA_RATIO × σ_perp.
static func perp_sigma_deg(error_rms_deg: float) -> float:
	return error_rms_deg / sqrt(AXIS_SIGMA_RATIO * AXIS_SIGMA_RATIO + 1.0)

## σ dans l'axe du dernier flick (deg) — AXIS_SIGMA_RATIO × `perp_sigma_deg`.
static func axis_sigma_deg(error_rms_deg: float) -> float:
	return AXIS_SIGMA_RATIO * perp_sigma_deg(error_rms_deg)

## Tire un offset 2D (deg, {x: composante YAW, y: composante PITCH}) suivant
## une gaussienne anisotrope centrée, étirée d'un facteur AXIS_SIGMA_RATIO
## dans la direction `axis_angle_deg` (l'axe du dernier flick, mesuré comme
## `desired_yaw`/`desired_pitch`) — puis fait pivoter le repère (σ_axe, σ_perp)
## vers (yaw, pitch) de cet angle. `error_rms_deg` est la magnitude RMS totale
## voulue (`current_error_deg`), AVANT le ratio de flick (A4, appliqué par
## l'appelant sur le résultat).
static func sample_anisotropic_offset(error_rms_deg: float, axis_angle_deg: float, rng: RandomNumberGenerator) -> Vector2:
	var sigma_axis := axis_sigma_deg(error_rms_deg)
	var sigma_perp := perp_sigma_deg(error_rms_deg)
	var along := rng.randfn(0.0, sigma_axis)
	var perp := rng.randfn(0.0, sigma_perp)
	var axis_rad := deg_to_rad(axis_angle_deg)
	var cos_a := cos(axis_rad)
	var sin_a := sin(axis_rad)
	var yaw := along * cos_a - perp * sin_a
	var pitch := along * sin_a + perp * cos_a
	return Vector2(yaw, pitch)

# ======================================================================
#  A4 — FLICK : le ratio d'amplitude de l'offset est tiré à CHAQUE flick
#  (chaque nouvel objectif d'offset, voir `next_regen_interval`) suivant
#  N(0.97 ; 0.05), borné à [0.85 ; 1.08] — remplace le dépassement FIXE de
#  10 % de BOT-02 (désormais porté par le ressort, voir `spring_params` :
#  critique, aucun dépassement intrinsèque). L'appelant multiplie le vecteur
#  de `sample_anisotropic_offset` par ce ratio ; le ressort « corrige »
#  ensuite en suivant l'offset FILTRÉ (`offset_filter_step`) vers le nouvel
#  objectif, jamais instantanément.
# ======================================================================

const FLICK_RATIO_MEAN := 0.97
const FLICK_RATIO_STDDEV := 0.05
const FLICK_RATIO_MIN := 0.85
const FLICK_RATIO_MAX := 1.08

static func flick_ratio(rng: RandomNumberGenerator) -> float:
	return clampf(rng.randfn(FLICK_RATIO_MEAN, FLICK_RATIO_STDDEV), FLICK_RATIO_MIN, FLICK_RATIO_MAX)

# ======================================================================
#  A5 — RETARD DE PERCEPTION EN SUIVI : la visée poursuit la position de la
#  cible telle qu'elle était il y a `perception_delay_s` (file, comme CS) —
#  pas sa position vraie du tick courant. Le +60 ms « en ligne » (BOT-03)
#  n'est pas géré ici, hors de mon périmètre (réseau).
# ======================================================================

static func perception_delay_s(difficulty: int) -> float:
	match difficulty:
		MatchConfig.Difficulty.RECRUE:
			return 0.25
		MatchConfig.Difficulty.ELITE:
			return 0.15
		_:
			return 0.20  # VETERAN

## `history` : Array de {"time": float, "pos": Vector3}, trié du plus ANCIEN
## (index 0) au plus RÉCENT — l'appelant y ajoute un échantillon chaque tick
## et l'élague (voir BotBrain._aim_towards). Renvoie la position interpolée à
## l'instant `now - delay_s` : le plus ancien échantillon si l'historique ne
## remonte pas assez loin (mieux qu'aucune valeur, jamais la position
## COURANTE — romprait le retard voulu), le plus récent si `delay_s` est nul
## ou l'historique tient en un seul point, `fallback` si l'historique est vide
## (cible tout juste acquise, aucun échantillon encore accumulé).
static func delayed_position(history: Array, now: float, delay_s: float, fallback: Vector3) -> Vector3:
	if history.is_empty():
		return fallback
	var target_time := now - delay_s
	var first: Dictionary = history[0]
	if target_time <= float(first.time):
		return first.pos
	for i in range(1, history.size()):
		var sample: Dictionary = history[i]
		if float(sample.time) >= target_time:
			var prev: Dictionary = history[i - 1]
			var t0 := float(prev.time)
			var t1 := float(sample.time)
			var span := t1 - t0
			var frac := 0.0 if span <= 0.0001 else clampf((target_time - t0) / span, 0.0, 1.0)
			return (prev.pos as Vector3).lerp(sample.pos, frac)
	var last: Dictionary = history[history.size() - 1]
	return last.pos

# ======================================================================
#  POINT VISÉ — torse au-delà de TORSO_AIM_DISTANCE, sauf Élite (assez
#  précis pour continuer à viser fin à toute distance). Inchangé (BOT-02).
# ======================================================================

## Distance (m) au-delà de laquelle le bot vise le torse plutôt que le point
## précis (tête) de la cible — sauf Élite.
const TORSO_AIM_DISTANCE := 20.0

## Demi-largeur (m) des deux points de visée possibles — utilisée pour
## convertir en largeur ANGULAIRE de hitbox via `hitbox_half_width_deg`.
const HEAD_HALF_WIDTH_M := 0.11
const TORSO_HALF_WIDTH_M := 0.30

static func aims_torso_beyond_range(difficulty: int, distance: float) -> bool:
	return difficulty != MatchConfig.Difficulty.ELITE and distance > TORSO_AIM_DISTANCE

## Demi-largeur (m) du point actuellement visé par la difficulté donnée à
## `distance` (m) — torse si `aims_torso_beyond_range`, sinon tête.
static func targeted_half_width_m(difficulty: int, distance: float) -> float:
	return TORSO_HALF_WIDTH_M if aims_torso_beyond_range(difficulty, distance) else HEAD_HALF_WIDTH_M

## Demi-largeur ANGULAIRE (deg) d'une cible de demi-largeur `half_width_m`
## (m, mesurée au centre) vue depuis `distance` (m).
static func hitbox_half_width_deg(half_width_m: float, distance: float) -> float:
	if distance <= 0.001:
		return 90.0
	return rad_to_deg(atan(half_width_m / distance))

# ======================================================================
#  CONDITION DE TIR — l'erreur courante doit être sous la demi-largeur
#  angulaire de la hitbox visée, plus la dispersion de l'arme équipée.
#  Inchangé (BOT-02).
# ======================================================================

## `true` si `error_deg` (l'erreur de visée courante, deg) autorise le tir :
## strictement sous la demi-largeur angulaire de la hitbox visée
## (`hitbox_half_width_deg`) plus la dispersion (deg) de l'arme équipée.
static func can_fire(error_deg: float, hitbox_half_width_deg_: float, weapon_spread_deg: float) -> bool:
	return error_deg < hitbox_half_width_deg_ + weapon_spread_deg

# ======================================================================
#  ROTATION — ressort-amortisseur `ω' += clamp(k·α − d·ω, ±accel_cap)·Δt`,
#  calibré CRITIQUE (A4 : plus de dépassement intrinsèque, le sur/sous-
#  virage humain vient désormais du ratio de flick sur l'OFFSET) pour
#  atteindre le pic de vitesse angulaire par difficulté (300/500/800°/s) sur
#  le flick de référence (90°), plafonné en ACCÉLÉRATION par difficulté
#  (A1 : 2000/3000/4500°/s² — un 180° ne dépasse alors plus ~1000°/s, contre
#  une croissance linéaire non plafonnée avant BOT-26).
# ======================================================================

## Amplitude (deg) du flick de référence utilisé pour calibrer k/d : un
## système ressort-amortisseur étant LINÉAIRE, le pic de vitesse
## (proportionnel à l'amplitude) est calibré sur CE saut d'angle ; le plafond
## d'accélération (`angular_accel_cap_deg`) borne ensuite les sauts plus
## grands indépendamment de cette calibration.
const FLICK_REFERENCE_DEG := 90.0

## Amortissement CRITIQUE (ζ = 1) du ressort de combat depuis BOT-26 — aucun
## dépassement intrinsèque (A4). `BotLook.gd` (BOT-25, regard hors combat)
## garde SON propre ζ = 0.9 (quasi critique) et appelle `spring_natural_freq`
## directement avec cette valeur : la signature à 2 arguments reste
## nécessaire pour lui, voir `_peak_speed_factor`.
const SPRING_ZETA_CRITICAL := 1.0

## Pic de vitesse angulaire (deg/s) visé par le ressort-amortisseur sur le
## flick de référence, par difficulté. Inchangé (BOT-02) : A1 ne plafonne que
## l'ACCÉLÉRATION, pas ce pic (« Les pics de 300/500/800°/s restent valables
## sur 90° »).
static func spring_peak_speed_deg(difficulty: int) -> float:
	match difficulty:
		MatchConfig.Difficulty.RECRUE:
			return 300.0
		MatchConfig.Difficulty.ELITE:
			return 800.0
		_:
			return 500.0  # VETERAN

## A1 : accélération angulaire MAX (deg/s²) du ressort de combat, par
## difficulté — passée à `spring_step` par l'appelant (BotBrain).
static func angular_accel_cap_deg(difficulty: int) -> float:
	match difficulty:
		MatchConfig.Difficulty.RECRUE:
			return 2000.0
		MatchConfig.Difficulty.ELITE:
			return 4500.0
		_:
			return 3000.0  # VETERAN

## Facteur Q(ζ) reliant le pic de vitesse angulaire de la réponse indicielle
## à sa pulsation naturelle ωn et à l'amplitude du saut A : v_max = A·ωn·Q(ζ).
## Sous-amorti (0 < ζ < 1) : obtenu en annulant dv/dt sur
## v(t) = (A·ωn/√(1-ζ²))·e^(-ζωn t)·sin(ωd t) — la formule se divise par
## √(1-ζ²), non définie à ζ = 1 (critique) : branche séparée, dérivée de
## v(t) = A·ωn²·t·e^(-ωn t) (réponse critique), dont le maximum en t = 1/ωn
## donne v_max = A·ωn·e⁻¹, soit Q(1) = e⁻¹. Utilisée par `spring_params`
## (ζ = SPRING_ZETA_CRITICAL) ET par `BotLook.gd` via `spring_natural_freq`
## (son propre ζ = 0.9, sous-amorti, branche générale).
static func _peak_speed_factor(zeta: float) -> float:
	var z := clampf(zeta, 0.0001, 1.0)
	if z > 0.9999:
		return exp(-1.0)
	return exp(-z * acos(z) / sqrt(1.0 - z * z))

## Pulsation naturelle ωn (même unité que les vitesses ici : deg/s) qui
## produit `peak_speed_deg` au sommet de la réponse à un flick de
## FLICK_REFERENCE_DEG, avec l'amortissement `zeta`. Signature à 2 arguments
## CONSERVÉE (BotLook.gd, BOT-25, l'appelle avec son propre ζ = 0.9).
static func spring_natural_freq(peak_speed_deg: float, zeta: float) -> float:
	return peak_speed_deg / (FLICK_REFERENCE_DEG * _peak_speed_factor(zeta))

## Raideur k et amortissement d du ressort-amortisseur de COMBAT pour la
## difficulté donnée — amortissement CRITIQUE (A4, `SPRING_ZETA_CRITICAL`),
## calibré pour atteindre son pic de vitesse angulaire (`spring_peak_speed_deg`)
## sur le flick de référence. `{"k": float, "d": float}`.
static func spring_params(difficulty: int) -> Dictionary:
	var wn := spring_natural_freq(spring_peak_speed_deg(difficulty), SPRING_ZETA_CRITICAL)
	return {"k": wn * wn, "d": 2.0 * SPRING_ZETA_CRITICAL * wn}

## Un pas d'intégration (Euler) du ressort-amortisseur
## `ω' += clamp(k·α − d·ω, ±max_accel_deg)·Δt` puis `angle += ω·Δt`, où
## α = target_angle - current_angle (deg), ω = current_speed (deg/s).
## `max_accel_deg` (A1, `angular_accel_cap_deg`) plafonne l'accélération
## INSTANTANÉE — INF par défaut (pas de plafond), pour les appelants qui ne
## veulent pas de cap (aucun en production : BotBrain passe toujours
## `angular_accel_cap_deg(_difficulty)`, mais garder INF par défaut documente
## explicitement que « pas de cap » est le comportement neutre, jamais un
## oubli silencieux). `{"angle": float, "speed": float}`.
static func spring_step(current_angle: float, current_speed: float, target_angle: float, k: float, d: float, delta: float, max_accel_deg: float = INF) -> Dictionary:
	var alpha := target_angle - current_angle
	var accel := clampf(k * alpha - d * current_speed, -max_accel_deg, max_accel_deg)
	var new_speed := current_speed + accel * delta
	var new_angle := current_angle + new_speed * delta
	return {"angle": new_angle, "speed": new_speed}
