## BotReaction.gd
## Modèle PUR de réaction humain-like — v2 (BOT-26, docs/research/08_bots_
## humanlike.md §3.2 règle A6, valeurs §3.8). Remplace le délai FIXE de BOT-02
## (Recrue 0.45 s, Vétéran 0.3 s, Élite 0.2 s, sans aucune variance) par une
## loi EX-GAUSSIENNE (Normale + Exponentielle), la même famille de
## distribution que le temps de réaction humain mesuré en laboratoire
## ([S16]) : la partie normale (μ, σ) modélise le socle perceptivo-moteur, la
## partie exponentielle (τ) la queue étalée des réactions lentes — ce que ne
## peut PAS produire une constante.
## Un délai supplémentaire s'ajoute si la cible est loin du centre de l'écran
## à l'acquisition, et un « délai d'ouverture du feu » (comme l'AttackDelay
## de CS) s'ajoute au tout premier tir d'un engagement (jamais aux
## réacquisitions internes pendant un combat déjà entamé). Plancher à 150 ms
## dans tous les cas — aucune réaction, même dans la queue basse de la loi,
## ne descend sous ce plancher humain.
## Aucun accès à l'arbre de scène — consommé par scripts/ai/BotBrain.gd, testé
## isolément dans tests/ai/test_bot_reaction.gd.
class_name BotReaction
extends RefCounted

## Plancher (s) : aucune réaction, quels que soient les tirages, ne descend
## sous cette valeur (A6, dernière puce).
const REACTION_FLOOR_S := 0.15

## Au-delà de cet angle (deg) entre le regard courant et la direction de la
## cible à l'acquisition, +OFF_CENTER_PENALTY_S s'ajoute (A6, 2e puce) — une
## cible en périphérie demande un temps de recentrage en plus du socle
## perceptif.
const OFF_CENTER_ANGLE_DEG := 35.0
const OFF_CENTER_PENALTY_S := 0.12  # 120 ms.

## Paramètres μ/σ/τ (s) de la loi ex-gaussienne par difficulté (§3.8) — les
## médianes approximatives qui en résultent (μ + τ·ln 2, l'approximation
## usuelle pour une ex-gaussienne) sont ~475/330/230 ms, cohérentes avec les
## anciennes constantes BOT-02 (0.45/0.3/0.2 s) qu'elles remplacent : le socle
## reste au même ordre de grandeur, seule une vraie VARIANCE (absente avant)
## s'y ajoute désormais.
static func _ex_gaussian_params(difficulty: int) -> Dictionary:
	match difficulty:
		MatchConfig.Difficulty.RECRUE:
			return {"mu": 0.400, "sigma": 0.040, "tau": 0.110}
		MatchConfig.Difficulty.ELITE:
			return {"mu": 0.200, "sigma": 0.025, "tau": 0.045}
		_:
			return {"mu": 0.280, "sigma": 0.035, "tau": 0.070}  # VETERAN

## Médiane APPROXIMATIVE (s) de la loi ex-gaussienne de `difficulty`, sans les
## puces additionnelles (hors-centre / délai d'ouverture du feu / plancher) —
## utilisée pour documenter/vérifier §3.8, pas pour tirer une valeur (voir
## `sample_base_reaction_s`).
static func expected_median_s(difficulty: int) -> float:
	var p := _ex_gaussian_params(difficulty)
	return float(p.mu) + float(p.tau) * log(2.0)

## Délai d'ouverture du feu (s, A6 3e puce, comme l'AttackDelay de CS) —
## s'ajoute UNIQUEMENT au tout premier tir d'un engagement (le bot entre en
## combat depuis le repos), jamais à une réacquisition de cible PENDANT un
## combat déjà en cours (voir `reaction_time`, paramètre `is_first_shot`).
static func fire_delay_s(difficulty: int) -> float:
	match difficulty:
		MatchConfig.Difficulty.RECRUE:
			return 0.250
		MatchConfig.Difficulty.ELITE:
			return 0.0
		_:
			return 0.080  # VETERAN

## Tire une exponentielle de paramètre d'échelle `scale` (s) par inversion de
## la fonction de répartition : `-scale * ln(1 - U)`, U ~ Uniforme(0,1) — U
## est borné loin de 1 pour éviter un `log(0)` (tirage extrême, 1 chance sur
## 10 millions).
static func _sample_exponential(scale: float, rng: RandomNumberGenerator) -> float:
	var u := clampf(rng.randf(), 0.0000001, 0.9999999)
	return -scale * log(1.0 - u)

## Tirage BRUT (s) de la loi ex-gaussienne μ/σ/τ de `difficulty` — SOMME d'une
## Normale(μ, σ) et d'une Exponentielle(τ), SANS aucun des ajustements
## contextuels de `reaction_time` (hors-centre, premier tir, plancher) :
## isolé pour les tests statistiques (médiane, coefficient de variation) qui
## doivent vérifier la distribution de BASE, telle que documentée en §3.8.
static func sample_base_reaction_s(difficulty: int, rng: RandomNumberGenerator) -> float:
	var p := _ex_gaussian_params(difficulty)
	return rng.randfn(float(p.mu), float(p.sigma)) + _sample_exponential(float(p.tau), rng)

## Délai de réaction COMPLET (s) avant que le bot puisse engager une cible
## qui vient d'apparaître (A6) : tirage ex-gaussien de base
## (`sample_base_reaction_s`), + OFF_CENTER_PENALTY_S si `target_offset_deg`
## dépasse OFF_CENTER_ANGLE_DEG, + `fire_delay_s` si `is_first_shot` (premier
## tir d'un engagement, jamais une réacquisition interne), puis plancher à
## REACTION_FLOOR_S sur le TOTAL.
static func reaction_time(difficulty: int, rng: RandomNumberGenerator, target_offset_deg: float = 0.0, is_first_shot: bool = true) -> float:
	var t := sample_base_reaction_s(difficulty, rng)
	if absf(target_offset_deg) > OFF_CENTER_ANGLE_DEG:
		t += OFF_CENTER_PENALTY_S
	if is_first_shot:
		t += fire_delay_s(difficulty)
	return maxf(t, REACTION_FLOOR_S)
