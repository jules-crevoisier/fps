## BotCombatStyle.gd
## Discipline de combat PURE (contract-r3.md, BOT-04 ; BOT-21) : armes de
## précision qui exigent d'être quasi à l'arrêt pour tirer, distance préférée
## par catégorie d'arme (WeaponConfig.Category), rafales des armes automatiques
## à distance (3-5 tirs puis pause), intervalle de strafe réactif (rapide si le
## bot est pris pour cible, plus calme sinon), rythme de tir semi-auto (un
## appui = un front montant, espacé par `semi_auto_interval`), hystérésis de
## l'ADS (`ads_hold`) et marche (walk_held) en enquête/fin de round. Aucun
## accès à l'arbre de scène — consommée par scripts/ai/BotBrain.gd, testée
## isolément dans tests/ai/test_bot_combat_style.gd.
##
## Référence : docs/research/02_bots_ai.md §2.5 ("Halo Infinite modélise le
## strafe et le saut en réaction aux tirs reçus, pas au hasard"), §2.1 ("un
## fusil à distance rafale plutôt que de vider le chargeur") et §4 écarts #5
## ("sauts, plongeons et accroupis aléatoires en plein combat") / #11 ("aucune
## distance préférée par arme... un pompe tente d'engager un sniper à 40 m").
## docs/research/08_bots_humanlike.md §3.2 A7/A8 (BOT-21) : "Semi-auto : un
## appui = un front montant... jamais plus vite que la cadence de l'arme" et
## "ADS avec hystérésis... au plus 1 bascule par 1,5 s".
##
## NOTE (BOT-21, 3e passage, statut vérifié au 2026-09-25 par QA indépendant,
## 2 runs réels hp_veteran+tdm_veteran/Wasteland — reports/bot_bench/
## qa_verify_BOT21.json et qa_verify_BOT21_ts1.json) : `semi_auto_interval` et
## `ads_hold` implémentent les règles B7 (≤ 1 bascule ADS / 1,5 s) et B8 (CV de
## l'intervalle de tir ≥ 0,15, ≤ 30 % à cadence max) documentées par
## 08_bots_humanlike.md §3, et sont couvertes par des tests purs (tests/ai/
## test_bot_combat_style.gd) — ces deux fonctions elles-mêmes n'ont pas changé
## depuis le 1er passage, elles restent correctes en isolation.
## - B7 : confirmé propre sur les 2 runs (p99 bascules ADS/engagement 1.0 puis
##   2.0, seuil > 2.0 — aucun avertissement B7). Le fix vivait dans
##   BotBrain._tick_combat (`_ads_state` ne se réinitialise plus à chaque
##   changement de cible interne, voir son commentaire "BOT-21 (B7 fix)"), pas
##   dans `ads_hold` elle-même.
## - B8 : aucun avertissement sur les 2 runs, MAIS `b8_semi_auto_interval_cv`
##   et `b8_semi_auto_max_rate_ratio` valent -1.0 (sentinelle "pas assez
##   d'échantillons de tir semi-auto") sur les deux — absence d'avertissement,
##   PAS confirmation positive que le rythme semi-auto est humain en vif. À ne
##   pas sur-interpréter comme "B8 vérifié propre".
## - B14 : reste EN AVERTISSEMENT sur les 2 runs (`b14_random_jumps` = 50 puis
##   222, jamais 0). Diagnostic (voir le bloc correspondant dans BotBrain.gd) :
##   le banc lit `stuck.get("_phase")` DÉJÀ transité vers REQUEST_REPATH au
##   tick où BotStuck produit `jump_pressed` (tools/bot_bench.gd, BotStuck.gd),
##   donc chaque saut légitime de déblocage est compté comme "aléatoire" — la
##   correction vit dans tools/bot_bench.gd et/ou scripts/ai/BotStuck.gd,
##   AUCUN des deux dans la liste de fichiers de BOT-21. Blocage réel, voir
##   `blocked_on` du rendu de BOT-21.
## - B3 (écart-type du tangage) : mesuré 2,56° puis 2,82° au banc (seuil ≥ 3,0°).
##   Décision du lead du 2026-09-25 : B3 relève de BOT-25 (BotLook.gd, points de
##   regard variés en hauteur), pas de ce fichier ; le retour ±5°/90°/s vers
##   l'horizon (contrat L3 de BOT-21) ne vise qu'à ne plus figer le tangage.
class_name BotCombatStyle
extends RefCounted

# ======================================================================
#  ARMES DE PRÉCISION — s'arrêter avant de tirer.
# ======================================================================

## Armes qui exigent d'être quasi à l'arrêt pour tirer (semi-auto précises,
## nommées explicitement par le contrat BOT-04) — jamais déduites de
## `WeaponConfig.automatic` seul : Magnum/Pistolet/Fracas sont AUSSI semi-auto
## (`automatic = false`) sans exiger l'arrêt.
const PRECISION_WEAPON_NAMES := ["Marqueur", "Percuteur", "Faucheur"]

## Vitesse (fraction de `MovementConfig.sprint_speed`, [0, ~1]) sous laquelle
## une arme de précision peut tirer.
const PRECISION_MAX_SPEED_RATIO := 0.30

static func is_precision_weapon(weapon_name: String) -> bool:
	return PRECISION_WEAPON_NAMES.has(weapon_name)

## `true` si `speed_ratio` (vitesse horizontale courante / vitesse de sprint)
## autorise le tir de `weapon_name` — toujours vrai pour une arme qui n'est
## pas dans `PRECISION_WEAPON_NAMES` (aucune contrainte de vitesse).
static func can_fire_at_speed(weapon_name: String, speed_ratio: float) -> bool:
	if not is_precision_weapon(weapon_name):
		return true
	return speed_ratio < PRECISION_MAX_SPEED_RATIO

# ======================================================================
#  DISTANCE PRÉFÉRÉE PAR CATÉGORIE — WeaponConfig.Category.
# ======================================================================

## Bande de distance (m) préférée par catégorie — `{"min": float, "max": float}`
## (`max` = INF si sans borne haute). Catégories non listées ici (poing,
## lourde, mêlée) : aucune préférence documentée par le contrat -> bande
## [0, INF], jamais de recul/avance forcés pour elles.
static func preferred_distance_band(category: int) -> Dictionary:
	match category:
		WeaponConfig.Category.SHOTGUN:
			return {"min": 0.0, "max": 6.0}
		WeaponConfig.Category.SMG:
			return {"min": 5.0, "max": 15.0}
		WeaponConfig.Category.RIFLE:
			return {"min": 10.0, "max": 35.0}
		WeaponConfig.Category.SNIPER:
			return {"min": 25.0, "max": INF}
		_:
			return {"min": 0.0, "max": INF}

## Faut-il reculer (cible trop proche pour la catégorie d'arme équipée) ?
static func should_retreat(category: int, distance: float) -> bool:
	return distance < float(preferred_distance_band(category).min)

## Faut-il avancer (cible trop loin pour la catégorie d'arme équipée) ?
static func should_advance(category: int, distance: float) -> bool:
	var band := preferred_distance_band(category)
	return float(band.max) < INF and distance > float(band.max)

## `true` si `distance` est déjà dans la bande préférée de `category` — ni
## recul ni avance nécessaires : le bot peut se planter pour tirer.
static func in_preferred_band(category: int, distance: float) -> bool:
	return not should_retreat(category, distance) and not should_advance(category, distance)

# ======================================================================
#  RAFALES À DISTANCE — armes automatiques au-delà de BURST_RANGE_M.
# ======================================================================

const BURST_RANGE_M := 25.0
const BURST_MIN_SHOTS := 3
const BURST_MAX_SHOTS := 5
const BURST_PAUSE_MIN := 0.15
const BURST_PAUSE_MAX := 0.25

## Une arme automatique doit-elle rafaler (au lieu de maintenir la gâchette en
## continu) à `distance` (m) ? Toujours faux pour une arme semi-auto
## (`automatic = false`, ex. Marqueur/Percuteur/Faucheur) : le rythme y est
## déjà borné par un tir par appui (`fire_pressed`), jamais `fire_held`.
static func should_burst(automatic: bool, distance: float) -> bool:
	return automatic and distance > BURST_RANGE_M

static func roll_burst_shots(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(BURST_MIN_SHOTS, BURST_MAX_SHOTS)

static func roll_burst_pause(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(BURST_PAUSE_MIN, BURST_PAUSE_MAX)

## Un pas de la machine de rafale (état PUR, tenu par l'appelant — voir
## BotBrain._burst_state) : `state` = `{"shots_target": int, "shots_fired":
## float, "pause_left": float}` (`{}` = première invocation, "aucune rafale en
## cours"). Le nombre de tirs "tenus" est mesuré en TEMPS écoulé × `fire_rate`
## (balles/s) plutôt qu'un compte d'évènements réseau — indépendant de tout
## signal de tir, seulement `delta` et la cadence de l'arme. Renvoie le
## nouvel état, plus `"can_fire": bool` (faux pendant la pause post-rafale).
static func burst_step(state: Dictionary, delta: float, fire_rate: float, rng: RandomNumberGenerator) -> Dictionary:
	var shots_target: int = int(state.get("shots_target", 0))
	var shots_fired: float = float(state.get("shots_fired", 0.0))
	var pause_left: float = float(state.get("pause_left", 0.0))

	if pause_left > 0.0:
		pause_left = maxf(pause_left - delta, 0.0)
		return {"shots_target": shots_target, "shots_fired": shots_fired, "pause_left": pause_left, "can_fire": false}

	if shots_target <= 0:
		shots_target = roll_burst_shots(rng)
		shots_fired = 0.0

	shots_fired += fire_rate * delta
	if shots_fired >= float(shots_target):
		return {"shots_target": 0, "shots_fired": 0.0, "pause_left": roll_burst_pause(rng), "can_fire": false}
	return {"shots_target": shots_target, "shots_fired": shots_fired, "pause_left": 0.0, "can_fire": true}

# ======================================================================
#  STRAFE RÉACTIF — intervalle 0.25-0.6 s si le bot est pris pour cible
#  (coup reçu récemment), sinon un rythme plus lent (0.8-1.8 s, comportement
#  antérieur) en dehors de toute pression directe.
# ======================================================================

const STRAFE_REACTIVE_MIN := 0.25
const STRAFE_REACTIVE_MAX := 0.6
const STRAFE_IDLE_MIN := 0.8
const STRAFE_IDLE_MAX := 1.8

## Fenêtre (s) après un coup reçu pendant laquelle le bot se considère
## "pris pour cible" (déclenche le strafe réactif rapide, ci-dessus).
const TARGETED_MEMORY_SECONDS := 1.5

## Prochain intervalle (s) avant de changer de sens de strafe (ADAD) — tiré
## uniformément dans la fourchette rapide si `is_targeted`, sinon la lente.
static func strafe_interval(rng: RandomNumberGenerator, is_targeted: bool) -> float:
	if is_targeted:
		return rng.randf_range(STRAFE_REACTIVE_MIN, STRAFE_REACTIVE_MAX)
	return rng.randf_range(STRAFE_IDLE_MIN, STRAFE_IDLE_MAX)

# ======================================================================
#  RYTHME DE TIR SEMI-AUTO (BOT-21, A7) — un appui (front montant) toutes les
#  U(0,15 ; 0,40) s sous 20 m, U(0,30 ; 0,70) s au-delà, jamais plus vite que
#  la cadence de l'arme équipée. Remplace l'ancien `fire_pressed` vrai à
#  chaque tick (métronome à cadence max, écart #7 de 08_bots_humanlike.md).
# ======================================================================

const SEMI_AUTO_CLOSE_RANGE_M := 20.0  ## "sous 20 m" : distance < ce seuil.
const SEMI_AUTO_CLOSE_MIN := 0.15
const SEMI_AUTO_CLOSE_MAX := 0.40
const SEMI_AUTO_FAR_MIN := 0.30
const SEMI_AUTO_FAR_MAX := 0.70

## Prochain intervalle (s) avant le prochain appui semi-auto (front montant,
## voir BotBrain._tick_combat) — tiré selon `distance` (m), puis plafonné par
## `1 / fire_rate` (cadence de l'arme équipée, tirs/s, BotCombatStyle.burst_step
## utilise la même unité) si `fire_rate > 0.0` : jamais plus vite que l'arme
## elle-même, même à bout portant. `fire_rate <= 0.0` (arme inconnue) : aucun
## plafond, seul le tirage compte.
static func semi_auto_interval(distance: float, rng: RandomNumberGenerator, fire_rate: float = 0.0) -> float:
	var draw: float = rng.randf_range(SEMI_AUTO_CLOSE_MIN, SEMI_AUTO_CLOSE_MAX) if distance < SEMI_AUTO_CLOSE_RANGE_M \
			else rng.randf_range(SEMI_AUTO_FAR_MIN, SEMI_AUTO_FAR_MAX)
	if fire_rate > 0.0:
		return maxf(draw, 1.0 / fire_rate)
	return draw

# ======================================================================
#  ADS AVEC HYSTÉRÉSIS (BOT-21, A8) — maintenu jusqu'à U(0,5 ; 0,9) s après la
#  dernière vue de la cible, au plus 1 bascule par 1,5 s. Remplace l'ancien
#  `aim_held = base_can_shoot` (l'ADS clignotait au moindre franchissement du
#  seuil de visée, écart #7 de 08_bots_humanlike.md).
# ======================================================================

const ADS_MIN_TOGGLE_INTERVAL := 1.5
const ADS_HOLD_MIN := 0.5
const ADS_HOLD_MAX := 0.9

## Un pas de la machine d'hystérésis ADS (état PUR, tenu par l'appelant — voir
## BotBrain._ads_state) : `state` = `{"held": bool, "since_toggle": float,
## "hold_left": float}` (`{}` = première invocation sur une NOUVELLE cible,
## voir la remise à zéro dans BotBrain._tick_combat au changement de cible).
## `wants_ads` reflète le signal BRUT du tick courant (prêt à tirer + distance
## suffisante pour l'ADS) — ce n'est PAS un état, c'est cette fonction qui
## lisse ses changements en `"held"`. Tant que `wants_ads` est vrai, `hold_left`
## est reconduit à un nouveau tirage U(0,5 ; 0,9) s : la fenêtre de maintien
## recule donc à chaque tick où la cible est encore visée/prête, et ne se met
## à décompter qu'à partir de la dernière fois où elle l'était. Une bascule
## (ON ou OFF) n'est appliquée que si `since_toggle` a atteint
## `ADS_MIN_TOGGLE_INTERVAL` depuis la précédente — sur un engagement normal
## (bien plus long que 1,5 s), ce délai est déjà écoulé au moment où `hold_left`
## expire, donc l'extinction a bien lieu 0,5 à 0,9 s après la dernière vue.
static func ads_hold(state: Dictionary, delta: float, wants_ads: bool, rng: RandomNumberGenerator) -> Dictionary:
	var held: bool = bool(state.get("held", false))
	var since_toggle: float = float(state.get("since_toggle", ADS_MIN_TOGGLE_INTERVAL)) + delta
	var hold_left: float = rng.randf_range(ADS_HOLD_MIN, ADS_HOLD_MAX) if wants_ads \
			else maxf(float(state.get("hold_left", 0.0)) - delta, 0.0)

	var desired := wants_ads or hold_left > 0.0
	if desired != held and since_toggle >= ADS_MIN_TOGGLE_INTERVAL:
		held = desired
		since_toggle = 0.0

	return {"held": held, "since_toggle": since_toggle, "hold_left": hold_left}

# ======================================================================
#  MARCHE (walk_held) — enquête sur un bruit ou fin de round.
# ======================================================================

## `true` si le bot doit marcher (walk_held) plutôt que sprinter : en train
## d'enquêter sur un bruit (aucune cible visible, un bruit récent en mémoire)
## ou en fin de round (approche furtive — Booth, docs/research/02_bots_ai.md :
## "sneaking" en fin de manche).
static func should_walk(investigating: bool, round_ending: bool) -> bool:
	return investigating or round_ending

# ======================================================================
#  MUNITIONS (GF-24, docs/research/10_ammo_kits_input.md §2.7) — « Hors
#  combat, un bot recharge de lui-même dès que son chargeur descend sous
#  40 %. À sec, il passe au pistolet. Quand il lui reste moins d'un chargeur
#  en réserve et qu'aucun ennemi n'est en vue, il fait un détour vers une
#  cartouchière ou une caisse à <= 12 m. Tout passe par l'écriture de
#  player.input.reload_pressed et weapon_slot_pressed, comme pour un humain. »
#  Consommée par BotBrain._tick_ammo, aucun état de scène ici — chaque
#  fonction ne dépend que de ses arguments.
# ======================================================================

## Seuil (fraction du chargeur, §2.7 "sous 40 %") sous lequel un bot hors
## combat recharge de lui-même.
const RELOAD_SELF_THRESHOLD_RATIO := 0.4

## Rayon (m, §2.7 "cartouchière ou une caisse à <= 12 m") sous lequel un
## détour vers un point de munitions est retenu.
const AMMO_DETOUR_RADIUS_M := 12.0

## Nom (WeaponConfig.weapon_name) de l'arme de repli quand l'arme en main est
## à sec (§2.7 "il passe au pistolet") — jamais déduit d'une catégorie/d'un id,
## nommé explicitement comme PRECISION_WEAPON_NAMES ci-dessus.
const PISTOL_WEAPON_NAME := "Pistolet"

## Le bot doit-il recharger DE LUI-MÊME l'arme en main (§2.7) ? Seulement
## HORS combat (jamais sous le feu), avec une réserve à consommer, un chargeur
## qui n'est pas déjà plein, et une charge sous le seuil de 40 % —
## `mag`/`reserve` viennent de Weapon.mag[slot]/Weapon.reserve_a[slot],
## `mag_size` de WeaponConfig.mag_size pour l'arme en main.
static func should_self_reload(in_combat: bool, mag: int, mag_size: int, reserve: int) -> bool:
	if in_combat or mag_size <= 0 or reserve <= 0:
		return false
	if mag >= mag_size:
		return false
	return float(mag) / float(mag_size) < RELOAD_SELF_THRESHOLD_RATIO

## L'arme en main est-elle à sec (chargeur ET réserve à zéro) au point qu'il
## faille passer au pistolet (§2.7) ? Faux si l'arme en main EST déjà le
## pistolet (rien à changer), ou si aucun pistolet n'est présent dans un
## autre emplacement (`has_pistol_elsewhere`, résolu par l'appelant via
## Weapon.weapons — jamais déduit ici d'un index de slot fixe : le pistolet
## peut avoir été remplacé en boutique).
static func should_switch_to_pistol(current_weapon_name: String, mag: int, reserve: int, has_pistol_elsewhere: bool) -> bool:
	if current_weapon_name == PISTOL_WEAPON_NAME:
		return false
	if mag > 0 or reserve > 0:
		return false
	return has_pistol_elsewhere

## Faut-il faire un détour vers un point de munitions (§2.7 "il lui reste
## moins d'un chargeur en réserve et qu'aucun ennemi n'est en vue") ? Le
## combat (`in_combat`, cible engagée) couvre déjà "aucun ennemi en vue" —
## `_target_id != -1` dans BotBrain n'est vrai QUE quand un ennemi est
## RÉELLEMENT visible ce tick (voir BotBrain._tick_combat). `reserve < mag_size`
## = strictement moins d'un chargeur plein en réserve.
static func wants_ammo_detour(in_combat: bool, reserve: int, mag_size: int) -> bool:
	if in_combat or mag_size <= 0:
		return false
	return reserve < mag_size

## Point de munitions le plus proche de `bot_pos` parmi `points` (Array de
## Vector3, positions de cartouchières/caisses vivantes), à `radius` m au
## plus (§2.7 "<= 12 m") — Vector3.INF si aucun n'est assez près (sentinelle
## déjà utilisée par BotBrain pour "aucune cible", voir `_target_pos`/
## `_last_seen_enemy_pos`).
static func nearest_ammo_point(bot_pos: Vector3, points: Array, radius: float = AMMO_DETOUR_RADIUS_M) -> Vector3:
	var best := Vector3.INF
	var best_d := radius
	for p in points:
		var candidate: Vector3 = p
		var d := bot_pos.distance_to(candidate)
		if d <= best_d:
			best_d = d
			best = candidate
	return best
