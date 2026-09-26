## bot_bench.gd
## Banc de mesure automatique des bots, headless (BOT-13, docs/research/
## 02_bots_ai.md #18 : « Pas de banc de mesure. Aucune métrique automatique
## (temps bloqué, changements d'objectif par minute, précision par distance).
## Impact : les régressions de comportement ne sont visibles qu'en playtest »).
##
## Enchaîne, dans UN SEUL process (même connexion réseau locale tout du long,
## comme tools/bot_smoke.gd) :
##   1. TDM 4v4 à Recrue, Vétéran puis Élite (bots des DEUX équipes, un temps
##      chacune — `--tdm-duration`) ;
##   2. Hardpoint 4v4 à Vétéran (`hp_veteran`, BOT-20) — même durée que TDM ;
##   3. SnD à Vétéran jusqu'à `--snd-rounds` manches jouées (rounds_to_win
##      relevé à l'infini pour ne jamais couper la série avant N manches).
## Chaque phase recrée un monde (scène de niveau MatchConfig.resolve_scene,
## `allow_bot_fill = true`, même patron que bot_smoke.gd) puis le libère avant
## la suivante. Seuls les joueurs BOT (PlayerController.is_bot, jamais
## l'hôte — voir doc de `_hook_bot`) alimentent les métriques.
##
## Métriques BOT-13 (temps bloqué, changements de but, précision par bande/
## difficulté, TTK effectif, capacités/min, pose/désamorçage SnD) : voir
## `_collect_metrics` et `check_thresholds` — inchangées par BOT-20, toujours
## BLOQUANTES (échec = `quit(1)`).
##
## BOT-20 (docs/research/08_bots_humanlike.md, « spec mesurable ») ajoute,
## SUR WASTELAND (nouvelle carte par défaut de la revue bots) :
##   - la phase `hp_veteran` (Hardpoint, Vétéran) ;
##   - un échantillonnage PAR TICK et PAR BOT du lacet/tangage, de la vitesse,
##     des entrées (jump/crouch/aim/fire) et de l'état du cerveau (combat ou
##     non, phase BotStuck, état de la machine à états du joueur) — jamais
##     exporté BRUT (volume ingérable sur 180 s × plusieurs bots à 60 Hz),
##     seulement AGRÉGÉ dans les métriques B1-B20 ci-dessous (même convention
##     que `_blocked_ticks`/`_total_bot_ticks` déjà en place pour BOT-13) ;
##   - un changement de but compte dès 0,5 m (au lieu de 5 m, l'angle mort
##     documenté #12 : la navette de 2 m entre spawns TDM Wasteland était
##     invisible) ; la NAVETTE A→B→A bouclée en moins de 10 s est détectée et
##     comptée À PART (`_register_goal_change`) plutôt que comptée deux fois
##     comme deux « vrais » changements ;
##   - les métriques B1-B15, B17, B18, B20 (voir `_collect_metrics`, sous la
##     clé `humanity` de `empty_metrics()`), mesurées UNIQUEMENT sur les
##     phases Vétéran (`tdm_veteran`, `hp_veteran`, `snd_veteran` — le tableau
##     §4 du research donne ses seuils "pour le Vétéran"), sauf B4 (TTFS) qui
##     reste ventilée par difficulté comme l'était déjà la précision BOT-13 ;
##   - une grille de présence 2 m au FORMAT de tools/heatmap.gd (mêmes clés
##     JSON : map_id/cell_size/bounds/grid_w/grid_h/kills/deaths, pour rester
##     directement rendable par tools/heatmap_render.py SANS le modifier —
##     hors de mon périmètre de fichiers) : "kills" = présence équipe 0,
##     "morts" = présence équipe 1, leur "différence" devient une carte de
##     contrôle territorial. Limite ASSUMÉE : les légendes du rendu resteront
##     étiquetées "kills"/"morts" (elles viennent de heatmap_render.py) — voir
##     docs/TESTING.md ;
##   - des seuils « observés » (avertissement, JAMAIS bloquants — imprimés en
##     `BOT_BENCH_OBSERVED <libellé>`, jamais dans `failures`/le code de
##     sortie) pour B1-B20, le temps que BOT-21 à BOT-29 comblent les écarts
##     qu'ils révèlent ; `check_observed_thresholds` bascule en bloquant en
##     une ligne (voir sa docstring) une fois BOT-29 terminé.
##
## LD-27 (docs/research/09_wasteland_vertical_slice.md §e, « Banc bots
## Wasteland ») ajoute, sous `metrics.wasteland`, les seuils de régression
## PROPRES à Wasteland — BLOQUANTS comme BOT-13 (`check_wasteland_
## thresholds`, jamais un simple avertissement : ce sont les critères
## d'acceptation mêmes de cette tâche), calculés SEULEMENT quand `--map=
## wasteland` (sentinelle `NO_DATA` sinon, via `_lane_points`/
## `_strong_positions` vides) :
##   - `kills_per_min_tdm_veteran` : kills / minute, phase `tdm_veteran`
##     seule (`_deaths_log` filtré par `phase_index`, comme
##     `_compute_trade_ratio`) ;
##   - `first_contact_median_s` : médiane, par vie de bot (remise à zéro à
##     chaque spawn/respawn), du délai entre le spawn et la PREMIÈRE
##     acquisition de cible (`_sample_acquisition_and_hearing`, phase
##     `tdm_veteran` seule) ;
##   - `lane_share` : part des CHANGEMENTS DE BUT DE PATROUILLE réels (hors
##     navette, hors combat — le même événement que `goal_changes_per_min`)
##     affectés à chacune des 3 lanes (`WastelandBots._lanes()`), par
##     correspondance directe à un hotspot déclaré (`WastelandBots.
##     _hotspots()`, tolérance 1 m) sinon par plus proche polyligne
##     (`lane_for_goal`) — phase `tdm_veteran` seule ;
##   - `strong_position_max_domination_ratio` : sur les 5 `strong_positions`
##     (rayon `LD27_STRONG_POSITION_HOLD_RADIUS_M`, même convention que
##     `tests/maps/test_wasteland.gd::ACCESS_RADIUS`), le MAX sur (position,
##     équipe) du temps où CETTE équipe SEULE y a un bot vivant, rapporté au
##     temps total observé (phase `tdm_veteran` seule) ;
##   - `early_death_ratio` : part des morts de la phase `tdm_veteran`
##     survenues à `LD27_EARLY_DEATH_WINDOW_S` s ou moins du dernier spawn
##     (`_deaths_log[].victim_life_clock_s`) ;
##   - `hp_zone_occupancy_min_ratio` : MINIMUM, sur chaque fenêtre de
##     `LD27_HP_ZONE_WINDOW_S` s ENTIÈREMENT observée de la phase
##     `hp_veteran`, de la fraction de ticks où la zone active a au moins un
##     bot vivant dedans (n'importe quelle équipe — différent de B18, qui ne
##     regarde que les fenêtres tenues par une SEULE équipe).
## `check_wasteland_thresholds` reste séparée de `check_thresholds` (jamais
## fusionnée dans son corps, pour ne rien changer aux tests BOT-13 existants
## qui l'appellent directement) mais son résultat est bien concaténé aux
## `failures` par `_finish`. Le détail des seuils vit UNIQUEMENT ici (les
## constantes `LD27_*` ci-dessous et cette docstring) : `docs/TESTING.md`
## (hors de mon périmètre de fichiers) ne décrit pas encore `metrics.
## wasteland`, à mettre à jour séparément.
##
## Fonctions PURES ajoutées et testées isolément (tests/ai/
## test_bot_bench_thresholds.gd) : `percentile`/`p99`, `coefficient_of_
## variation`, `segment_durations`, `is_snap_then_fire`, `max_simultaneous_
## events` — aucune ne touche l'arbre de scène ni le réseau, même convention
## que `distance_band`/`ratio`/`median`/`per_minute`/`check_thresholds` (BOT-13).
##
## La partie réelle (démarrer une partie headless, l'exécuter, écrire le
## JSON) tourne via `godot --headless -s res://tools/bot_bench.gd -- ...`,
## documentée dans docs/TESTING.md — hors du périmètre gdUnit4 (durée d'une
## partie réelle incompatible avec la boucle rapide de la suite).
extends SceneTree

# ======================================================================
#  Configuration par défaut / CLI
# ======================================================================
const OUT_DEFAULT := "res://reports/bot_bench/latest.json"
const DEFAULT_TDM_DURATION := 180.0   ## s SIMULÉES par phase TDM/Hardpoint (voir --time-scale).
const DEFAULT_SND_ROUNDS := 10
## BOT-20 : Wasteland devient la carte par défaut de la revue bots (l'ancien
## défaut, cargo_ship, ne voyait pas les défauts diagnostiqués sur Wasteland —
## constat #12 du research). `--map=` reste disponible pour cargo_ship.
const DEFAULT_MAP := "wasteland"
const DEFAULT_TIME_SCALE := 1.0
## BOT-20 : `hp_veteran` (Hardpoint Vétéran) ajouté après `tdm_elite`, avant
## le SnD — même ordre TDM -> Hardpoint -> SnD que la progression de modes
## du jeu (docs/ROADMAP.md).
const ALL_PHASES: Array[String] = ["tdm_recrue", "tdm_veteran", "tdm_elite", "hp_veteran", "snd_veteran"]

const DIFFICULTY_BY_KEY := {
	"recrue": MatchConfig.Difficulty.RECRUE,
	"veteran": MatchConfig.Difficulty.VETERAN,
	"elite": MatchConfig.Difficulty.ELITE,
}

## BOT-20 : un but qui saute de plus de cette distance (m) d'un échantillon
## à l'autre est compté comme un CHANGEMENT — 0,5 m (au lieu de 5 m sous
## BOT-13) pour voir la navette à 2 m entre spawns TDM Wasteland (constat #12,
## « angle mort à 5 m »). Un aller-retour A→B→A qui boucle en moins de
## `SHUTTLE_WINDOW_S` est une NAVETTE, comptée à part par
## `_register_goal_change` (jamais deux « vrais » changements de but).
const GOAL_JUMP_THRESHOLD_M := 0.5
## Fenêtre (s) de détection de la navette A→B→A — cf. `_register_goal_change`.
const SHUTTLE_WINDOW_S := 10.0
## Le rounds_to_win réel de SnDMode (6 par défaut) couperait la série avant
## `--snd-rounds` manches sur un score déséquilibré (contrat : "SnD 10
## manches", jamais "jusqu'à la victoire") — relevé à cette valeur le temps
## de la phase, voir `_begin_phase`.
const SND_ROUNDS_TO_WIN_OVERRIDE := 999999

# ======================================================================
#  Bandes de distance et seuils de régression BLOQUANTS (docs/TESTING.md,
#  BOT-13). INCHANGÉS par BOT-20 : voir la section "seuils observés" plus
#  bas pour les métriques B1-B20.
# ======================================================================
const DISTANCE_BANDS: Array[String] = ["5m", "20m", "40m"]
const _BAND_NEAR_MAX := 12.5   ## m — sous ce seuil : "5m".
const _BAND_MID_MAX := 30.0    ## m — sous ce seuil (et au-dessus du précédent) : "20m", sinon "40m".

## Précision RÉELLE observée en match (tirs bot -> hit_confirmed), volontai-
## rement plus étroite/plus basse que le Monte-Carlo "visée pure"
## (tests/ai/test_bot_aim.gd::MC_EXPECTED_RANGES) : un match réel ajoute les
## pauses de rafale, les ruptures de ligne de vue, le mouvement et l'encaisse
## de dégâts pendant l'engagement — la MÊME visée idéale y touche donc moins
## souvent sa cible. La cellule veteran/20m EST l'exemple du contrat BOT-13
## ("précision Vétéran 20 m entre 25 et 45 %", tasks/backlog.yaml) — vérifiée
## littéralement par tests/ai/test_bot_bench_thresholds.gd, jamais à modifier
## sans revoir ce contrat.
const ACCURACY_RANGES := {
	"recrue": {"5m": [0.15, 0.45], "20m": [0.10, 0.35], "40m": [0.10, 0.35]},
	"veteran": {"5m": [0.30, 0.60], "20m": [0.25, 0.45], "40m": [0.20, 0.45]},
	"elite": {"5m": [0.45, 0.80], "20m": [0.35, 0.65], "40m": [0.30, 0.60]},
}

## "temps bloqué < 2 %" (exemple littéral du contrat BOT-13).
const STUCK_TIME_MAX_RATIO := 0.02
## Au-delà, un bot "hésite" (va-et-vient, écart #2 docs/research/02_bots_ai.md)
## plutôt que de patrouiller/engager posément.
const GOAL_CHANGES_PER_MIN_MAX := 8.0
## TTK effectif (s) : un engagement instantané (< 0.1 s, tir "avant même
## d'avoir vu" venant d'ailleurs qu'une visée réelle) ou interminable (> 8 s,
## un bot qui n'arrive jamais à conclure) est suspect.
const TTK_MEDIAN_MIN_S := 0.1
const TTK_MEDIAN_MAX_S := 8.0
## Capacité RARE (BotBrain._tick_ability : tirage à 0.2 %/tick) : un usage
## très fréquent trahirait un tirage dérégulé, jamais un usage réaliste.
const ABILITY_PER_MIN_MAX := 8.0
## Une manche SnD sur un attaquant qui n'essaie JAMAIS de poser serait un
## objectif cassé ; 100 % de poses est plausible (défenseurs jamais assez
## rapides) et n'est donc pas borné en dehors du taux max théorique (1.0).
const PLANT_RATE_MIN := 0.15
const PLANT_RATE_MAX := 1.0
## Le désamorçage suppose D'ABORD une pose : un taux élevé n'est pas
## anormal en soi (défenseurs qui arrivent souvent à temps), mais un
## désamorçage sur QUASIMENT toutes les manches (> 85 %) trahirait plutôt une
## pose jamais défendue (attaquants qui ne repoussent jamais l'approche).
const DEFUSE_RATE_MIN := 0.0
const DEFUSE_RATE_MAX := 0.85

## Sentinelle "pas assez de données pour juger" — jamais NAN (non sérialisable
## en JSON) : `check_thresholds` ignore silencieusement toute valeur < 0.0.
const NO_DATA := -1.0

# ======================================================================
#  Seuils LD-27 — BLOQUANTS (docs/research/09_wasteland_vertical_slice.md
#  §e « Banc bots Wasteland »), voir la docstring de tête pour le sens de
#  chaque métrique. Comme BOT-13 : jamais un avertissement, un dépassement
#  fait échouer `bot_bench` (`check_wasteland_thresholds`, concaténé dans
#  `failures` par `_finish`).
# ======================================================================
const LD27_KILLS_PER_MIN_MIN := 6.0
const LD27_FIRST_CONTACT_MEDIAN_RANGE := [5.0, 9.0]
const LD27_LANE_SHARE_RANGE := [0.20, 0.45]
const LD27_STRONG_POSITION_DOMINATION_MAX := 0.35
## Rayon (m) de "tenue" d'une position forte — même valeur que `ACCESS_
## RADIUS` de `tests/maps/test_wasteland.gd` (comptage des accès des
## positions fortes), repris ici pour la même notion de "sur la position".
const LD27_STRONG_POSITION_HOLD_RADIUS_M := 6.0
const LD27_EARLY_DEATH_WINDOW_S := 3.0
const LD27_EARLY_DEATH_RATIO_MAX := 0.05
const LD27_HP_ZONE_OCCUPANCY_MIN_RATIO := 0.70
const LD27_HP_ZONE_WINDOW_S := 60.0
## Une fenêtre de `LD27_HP_ZONE_WINDOW_S` n'est jugée "entièrement observée"
## (et donc retenue par `_compute_hp_zone_occupancy_min_ratio`) que si son
## empan RÉEL (dernier - premier horodatage échantillonné dedans) atteint ce
## seuil — écarte une fenêtre finale tronquée (durée de phase non multiple
## de 60 s) d'un échec fabriqué par un manque de données, pas par les bots.
const LD27_HP_ZONE_WINDOW_MIN_COVERAGE_S := 55.0

# ======================================================================
#  Seuils OBSERVÉS BOT-20 (B1-B20, docs/research/08_bots_humanlike.md §4).
#  « Observé » = AVERTISSEMENT seulement (voir `check_observed_thresholds`,
#  jamais dans `failures`/le code de sortie) jusqu'à la fin de BOT-29, où le
#  contrat demande de les rendre bloquants — à ce moment-là, fusionner le
#  retour de `check_observed_thresholds` dans celui de `check_thresholds`
#  (ou faire appeler l'un par l'autre) est le seul changement nécessaire.
#  Mesurés UNIQUEMENT sur les phases Vétéran (tdm_veteran/hp_veteran/
#  snd_veteran, voir doc de tête), sauf B4 qui reste par difficulté.
# ======================================================================
const OBS_YAW_SPEED_P99_MAX_DEG_S := 360.0            ## B1
const OBS_YAW_ACCEL_P99_MAX_DEG_S2 := 5000.0          ## B2 (Vétéran ; Élite tolère 7000, non mesuré ici)
const OBS_DIVERGENCE_RATIO_RANGE := [0.20, 0.60]       ## B3
const OBS_PITCH_STDDEV_MIN_DEG := 3.0                  ## B3
const OBS_TTFS_MEDIAN_RANGES := {                      ## B4
	"recrue": [0.8, 1.3], "veteran": [0.5, 0.8], "elite": [0.35, 0.55],
}
const OBS_TTFS_CV_MIN := 0.2                           ## B4
const OBS_TTFS_P5_MIN_S := 0.18                        ## B4
const OBS_SHOTS_MOVING_RATIO_RANGE := [0.40, 0.80]     ## B5
const OBS_MOVING_ACCURACY_MAX := 0.15                  ## B5
const OBS_FAST_MOVING_SHOTS_MAX := 0.05                ## B5
const OBS_DODGE_SEGMENT_MEDIAN_RANGE := [0.3, 0.8]     ## B6
const OBS_DODGE_SEGMENT_MAX_S := 1.5                   ## B6
const OBS_DODGE_LATERAL_MAX_M := 3.5                   ## B6
const OBS_DODGE_STOP_RATIO_RANGE := [0.15, 0.35]       ## B6
const OBS_ADS_TOGGLES_P99_MAX := 2.0                   ## B7
const OBS_ADS_RAPID_TOGGLE_RATIO_MAX := 0.0            ## B7 (jamais 1 bascule/1.5s)
const OBS_SEMI_AUTO_CV_MIN := 0.15                     ## B8
const OBS_SEMI_AUTO_MAX_RATE_SHARE_MAX := 0.30         ## B8
const OBS_AIM_POINT_JUMPS_MAX := 0                     ## B9
const OBS_SNAP_THEN_FIRE_RATIO_MAX := 0.05             ## B10
const OBS_ALLY_DISTANCE_MEDIAN_RANGE := [6.0, 15.0]    ## B11
const OBS_ALLY_CLOSE_RATIO_MAX := 0.10                 ## B11
const OBS_ALLY_FAR_RATIO_MAX := 0.25                   ## B11
const OBS_MAX_SIMULTANEOUS_GOAL_CHANGES_MAX := 2       ## B12 (jamais >= 3)
const OBS_SPAWN_PRESENCE_MAX := 0.05                   ## B13
const OBS_SUSPICIOUS_GESTURES_MAX := 0                 ## B14 (sauts/accroupis au hasard)
const OBS_STUCK_EPISODES_PER_5MIN_MAX := 1.0           ## B15
const OBS_WALL_CONTACT_RATIO_MAX := 0.03               ## B15
const OBS_TRADE_RATIO_MIN := 0.30                      ## B17 (Vétéran ; Élite 0.50, non mesuré ici)
const OBS_HP_ZONE_BOT_COUNT_RANGE := [1, 3]             ## B18
const OBS_HP_ZONE_SPACING_MIN_M := 2.5                 ## B18
const OBS_HP_WATCH_BOT_COUNT_MIN := 1                  ## B18
const OBS_HP_ROTATION_ARRIVAL_RATIO_MIN := 0.5         ## B18 (assoupli : "≥1 bot" par rotation agrégé en ratio)
const OBS_HEARING_ERROR_MEDIAN_RANGE := [2.0, 6.0]     ## B20 ("jamais 0" : voir check, violé tant que BOT-29 n'ajoute pas de bruit)

## Rayon (m) de la zone Hardpoint (`hp_size` de MapSetup._build_markers,
## Vector3(10,4,10)) au-delà duquel on considère un bot "en surveillance"
## plutôt que dans la zone (8-20 m, §3.6 T5/B18).
const HP_WATCH_MIN_M := 8.0
const HP_WATCH_MAX_M := 20.0
## Délai (s) pour rejoindre la nouvelle zone après une rotation (B18/T5).
const HP_ROTATION_ARRIVAL_WINDOW_S := 10.0
## Fenêtre VACnet (B10) : 0,5 s avant / 0,25 s après le tir (le "après"
## n'entre pas dans `is_snap_then_fire`, qui ne juge que l'avant, voir sa doc).
const SNAP_WINDOW_BEFORE_S := 0.5
const SNAP_WINDOW_RECENT_S := 0.05
## Ignore un tir quasi immobile (rotation totale négligeable sur la fenêtre) :
## ni un flick ni un tir posé, rien à classer.
const SNAP_MIN_ROTATION_DEG := 5.0
const SNAP_RATIO_THRESHOLD := 0.8
## Fenêtre (s) hors de laquelle une rotation n'est plus imputable à un tir
## qui vient d'être lâché (B9 : exclut le recul, pas le flick d'acquisition
## qui EST le phénomène mesuré par B9 lui-même).
const RECOIL_GRACE_S := 0.12
## Fenêtre de synchronisation d'équipe (B12, VACnet-like §3.6 T3).
const SYNC_WINDOW_S := 0.2
## "Hors spawn" (B11/B13) : ignore les 10 premières secondes de vie du bot.
const SPAWN_GRACE_S := 10.0
const SPAWN_PRESENCE_RADIUS_M := 10.0
## Fenêtre de trade (B17, §3.4 T4/C7 "Échange de kill").
const TRADE_WINDOW_S := 3.0
## Portée d'audition d'un tir (BotBrain.HEAR_RADIUS) — bornée pour la
## corrélation B20 (`_closest_recent_shot`) : au-delà, ce n'est pas LE tir
## que le bot vient d'entendre.
const HEARING_CORRELATION_RADIUS_M := 22.0
const HEARING_CORRELATION_WINDOW_S := 1.5

# ======================================================================
#  Fonctions PURES — testées isolément (tests/ai/test_bot_bench_thresholds.gd),
#  aucune ne touche l'arbre de scène ni le réseau.
# ======================================================================

## Bande de distance (m) — "5m"/"20m"/"40m", mêmes noms que MC_EXPECTED_RANGES
## de tests/ai/test_bot_aim.gd pour rester directement comparable à la visée
## théorique. Une distance négative (jamais censée arriver) retombe sur "5m"
## plutôt que de planter.
static func distance_band(distance_m: float) -> String:
	if distance_m < _BAND_NEAR_MAX:
		return "5m"
	if distance_m < _BAND_MID_MAX:
		return "20m"
	return "40m"

## `hits / total`, ou NO_DATA si `total <= 0` (jamais une division par zéro
## silencieuse ni un NaN exporté en JSON).
static func ratio(hits: int, total: int) -> float:
	if total <= 0:
		return NO_DATA
	return float(hits) / float(total)

## Médiane d'un tableau de float/int (copie triée, jamais l'entrée mutée),
## NO_DATA si vide.
static func median(values: Array) -> float:
	if values.is_empty():
		return NO_DATA
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	var mid := n / 2
	if n % 2 == 1:
		return float(sorted[mid])
	return (float(sorted[mid - 1]) + float(sorted[mid])) * 0.5

## `count` ramené à un rythme "par minute" sur `duration_s` secondes RÉELLEMENT
## observées, NO_DATA si `duration_s <= 0` (jamais une division par zéro).
## `count == 0` sur une durée positive vaut bien 0.0 (donnée réelle : "aucun
## événement observé"), jamais confondu avec la sentinelle.
static func per_minute(count: int, duration_s: float) -> float:
	if duration_s <= 0.0:
		return NO_DATA
	return float(count) / (duration_s / 60.0)

## BOT-20 — percentile générique (méthode "plus proche rang", 0 < p <= 1),
## NO_DATA si `values` est vide. `p99`/B1/B2 en sont l'usage principal, mais
## B4 a aussi besoin d'un p5 (`percentile(values, 0.05)`).
static func percentile(values: Array, p: float) -> float:
	if values.is_empty():
		return NO_DATA
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	var idx := clampi(int(ceil(p * n)) - 1, 0, n - 1)
	return float(sorted[idx])

## BOT-20 — p99, raccourci documenté par le contrat ("Fonctions pures
## testées : p99, ...").
static func p99(values: Array) -> float:
	return percentile(values, 0.99)

## BOT-20 — coefficient de variation (écart-type population / moyenne),
## NO_DATA si moins de 2 valeurs (une variation n'a pas de sens sur un seul
## échantillon) ou si la moyenne est nulle (division par zéro).
static func coefficient_of_variation(values: Array) -> float:
	if values.size() < 2:
		return NO_DATA
	var sum := 0.0
	for v in values:
		sum += float(v)
	var mean := sum / values.size()
	if is_zero_approx(mean):
		return NO_DATA
	var sq_sum := 0.0
	for v in values:
		sq_sum += (float(v) - mean) * (float(v) - mean)
	var stddev := sqrt(sq_sum / values.size())
	return stddev / mean

## BOT-20 — découpage en segments contigus. `samples` : tableau de paires
## `[state, dt]` (état comparable par `==` quelconque, `dt` la durée RÉELLE
## de cet échantillon en s — jamais un pas fixe supposé, pour rester robuste
## à une légère instabilité du delta headless). Renvoie un tableau de
## `{"state": ..., "duration": <s>}`, un par plage contiguë de même état ;
## `[]` si `samples` est vide. Sert à B6 (segments d'esquive gauche/droite).
static func segment_durations(samples: Array) -> Array:
	var segments: Array = []
	var current_state = null
	var current_duration := 0.0
	var started := false
	for s in samples:
		var state = s[0]
		var dt: float = float(s[1])
		if started and state == current_state:
			current_duration += dt
		else:
			if started:
				segments.append({"state": current_state, "duration": current_duration})
			current_state = state
			current_duration = dt
			started = true
	if started:
		segments.append({"state": current_state, "duration": current_duration})
	return segments

## BOT-20 — B10 « snap puis tir » (fenêtre VACnet, §3.4/§4) : `rotation_
## last_50ms_deg`/`rotation_last_500ms_deg` sont la rotation TOTALE (somme des
## |Δlacet|, deg) accumulée dans les 50 ms / 500 ms précédant le tir. Vrai si
## au moins `SNAP_RATIO_THRESHOLD` (80 %) de la rotation des 500 ms a eu lieu
## dans les 50 dernières ms — jamais vrai sur un tir quasi immobile
## (`rotation_last_500ms_deg < SNAP_MIN_ROTATION_DEG`, évite un ratio 0/0 ou
## bruité qui classerait un tir posé comme un snap).
static func is_snap_then_fire(rotation_last_50ms_deg: float, rotation_last_500ms_deg: float) -> bool:
	if rotation_last_500ms_deg < SNAP_MIN_ROTATION_DEG:
		return false
	return (rotation_last_50ms_deg / rotation_last_500ms_deg) >= SNAP_RATIO_THRESHOLD

## BOT-20 — B12 « fenêtre de synchronisation » : nombre maximal d'éléments de
## `times` (s, ANY ordre) contenus dans une fenêtre glissante de `window_s`
## secondes — algorithme classique à deux pointeurs sur le tableau trié.
## `0` si `times` est vide (jamais un plantage sur un tableau vide).
static func max_simultaneous_events(times: Array, window_s: float) -> int:
	if times.is_empty():
		return 0
	var sorted: Array = times.duplicate()
	sorted.sort()
	var best := 1
	var left := 0
	for right in range(sorted.size()):
		while float(sorted[right]) - float(sorted[left]) > window_s:
			left += 1
		best = maxi(best, right - left + 1)
	return best

## LD-27 — distance (m) d'un point au segment [a, b] le plus proche d'une
## polyligne (`polyline` : Array[Vector3], >= 2 points). `INF` si moins de 2
## points (rien à projeter dessus). Projection standard clampée à [0, 1] sur
## chaque segment, minimum retenu sur tous les segments.
static func point_to_polyline_distance(point: Vector3, polyline: Array) -> float:
	if polyline.size() < 2:
		return INF
	var best := INF
	for i in range(polyline.size() - 1):
		var a: Vector3 = polyline[i]
		var b: Vector3 = polyline[i + 1]
		var ab := b - a
		var len_sq := ab.length_squared()
		var t := 0.0
		if len_sq > 0.00001:
			t = clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
		var closest: Vector3 = a + ab * t
		best = minf(best, point.distance_to(closest))
	return best

## LD-27 — lane (clé de `lanes`, "" si aucune) portée par un but de
## patrouille `pos` : correspondance directe à un hotspot déclaré
## (`hotspots`, chaque élément `{pos, lane, ...}`) dans un rayon de 1 m —
## les bots patrouillent via ces points (WastelandBots._hotspots()), donc
## un but qui EST un hotspot en hérite la lane sans ambiguïté — sinon plus
## proche polyligne de `lanes` (`point_to_polyline_distance`), pour un but
## de mémoire d'ennemi qui ne tombe pas pile sur un hotspot. "" si `lanes`
## est vide (carte sans données bots, ex. cargo_ship).
static func lane_for_goal(pos: Vector3, lanes: Dictionary, hotspots: Array) -> String:
	for h in hotspots:
		var hpos: Vector3 = h.get("pos")
		if hpos.distance_to(pos) <= 1.0:
			return String(h.get("lane", ""))
	if lanes.is_empty():
		return ""
	var best_key := ""
	var best_dist := INF
	for lane_key in lanes.keys():
		var d := point_to_polyline_distance(pos, lanes[lane_key])
		if d < best_dist:
			best_dist = d
			best_key = String(lane_key)
	return best_key

## Squelette JSON complet, sentinelles partout — sert de base à l'agrégation
## réelle (`_finish`) ET aux tests (une seule clé à écraser par scénario).
static func empty_metrics() -> Dictionary:
	var accuracy := {}
	for diff_key in ACCURACY_RANGES:
		var bands := {}
		for band in DISTANCE_BANDS:
			bands[band] = NO_DATA
		accuracy[diff_key] = bands
	var ttfs_by_diff := {}
	for diff_key in ACCURACY_RANGES:
		ttfs_by_diff[diff_key] = NO_DATA
	return {
		"stuck_time_ratio": NO_DATA,
		"goal_changes_per_min": NO_DATA,
		"accuracy": accuracy,
		"ttk_median_s": NO_DATA,
		"ability_uses_per_min": NO_DATA,
		"plant_rate": NO_DATA,
		"defuse_rate": NO_DATA,
		"rounds_played": 0,
		# BOT-20 — B1-B15, B17, B18, B20 (docs/research/08_bots_humanlike.md
		# §4). Voir la docstring de tête pour le périmètre (phases Vétéran
		# uniquement, sauf B4) et `check_observed_thresholds` pour les seuils.
		"humanity": {
			"b1_yaw_speed_p99_deg_s": NO_DATA,
			"b1_yaw_snap_violations": 0,
			"b2_yaw_accel_p99_deg_s2": NO_DATA,
			"b3_look_move_divergence_ratio": NO_DATA,
			"b3_pitch_stddev_deg": NO_DATA,
			"b4_ttfs_median_s": ttfs_by_diff.duplicate(true),
			"b4_ttfs_cv": ttfs_by_diff.duplicate(true),
			"b4_ttfs_p5_s": ttfs_by_diff.duplicate(true),
			"b5_shots_moving_ratio": NO_DATA,
			"b5_moving_accuracy_ratio": NO_DATA,
			"b5_fast_moving_shots_ratio": NO_DATA,
			"b6_dodge_segment_median_s": NO_DATA,
			"b6_dodge_segment_max_s": NO_DATA,
			"b6_dodge_lateral_p99_m": NO_DATA,
			"b6_dodge_stop_ratio": NO_DATA,
			"b7_ads_toggles_p99": NO_DATA,
			"b7_ads_rapid_toggle_ratio": NO_DATA,
			"b8_semi_auto_interval_cv": NO_DATA,
			"b8_semi_auto_max_rate_ratio": NO_DATA,
			"b9_aim_point_jumps": 0,
			"b10_snap_then_fire_ratio": NO_DATA,
			"b11_ally_distance_median_m": NO_DATA,
			"b11_close_ally_ratio": NO_DATA,
			"b11_far_from_all_ratio": NO_DATA,
			"b12_max_simultaneous_goal_changes": 0,
			"b12_shuttle_events": 0,
			"b13_spawn_presence_ratio": NO_DATA,
			"b14_random_jumps": 0,
			"b14_low_speed_crouches": 0,
			"b14_goalless_slides": -1,
			"b15_stuck_episodes_per_5min": NO_DATA,
			"b15_wall_contact_ratio": NO_DATA,
			"b17_trade_ratio": NO_DATA,
			"b18_zone_bot_count_median": NO_DATA,
			"b18_zone_spacing_median_m": NO_DATA,
			"b18_watch_bot_count_median": NO_DATA,
			"b18_rotation_arrival_ratio": NO_DATA,
			"b20_hearing_error_median_m": NO_DATA,
		},
		# LD-27 — seuils de régression Wasteland (§e), BLOQUANTS (voir la
		# docstring de tête et `check_wasteland_thresholds`). Sentinelles
		# partout : NO_DATA sur une autre carte que Wasteland, ou si la
		# phase concernée n'a pas tourné (`--phases=` restreint).
		"wasteland": {
			"kills_per_min_tdm_veteran": NO_DATA,
			"first_contact_median_s": NO_DATA,
			# LD-43 : clés alignées sur `WastelandBots._lanes()` (v4 : Grand-Rue/
			# Intérieurs/Canyon, docs/research/11_wasteland_v4_layout.md §5) —
			# "crete"/"ravin" étaient les noms de lanes v3 (jamais mis à jour par
			# LD-40 quand la carte a été refaite) : `check_wasteland_thresholds`
			# lisait donc deux clés FANTÔMES toujours à 0 % (échec garanti, "hors
			# de [20,45] %") pendant que les vraies traversées "interieurs"/
			# "canyon" (comptées par `_lane_crossing_counts`, cf. la boucle plus
			# bas) restaient invisibles du rapport, jamais exportées en JSON.
			"lane_share": {"grand_rue": NO_DATA, "interieurs": NO_DATA, "canyon": NO_DATA},
			"strong_position_max_domination_ratio": NO_DATA,
			"early_death_ratio": NO_DATA,
			"hp_zone_occupancy_min_ratio": NO_DATA,
		},
	}

## Compare `metrics` (même forme que `empty_metrics`) aux seuils BLOQUANTS
## documentés ci-dessus (BOT-13). Renvoie la liste (FRANÇAIS, un libellé par
## violation) des seuils dépassés — vide = tout est dans les clous (y compris
## "pas assez de données", jamais traité comme une régression : voir la
## sentinelle NO_DATA sur chaque champ optionnel). INCHANGÉ par BOT-20 — les
## métriques B1-B20 passent par `check_observed_thresholds` (avertissement).
static func check_thresholds(metrics: Dictionary) -> Array:
	var failures: Array[String] = []

	var stuck := float(metrics.get("stuck_time_ratio", NO_DATA))
	if stuck >= 0.0 and stuck > STUCK_TIME_MAX_RATIO:
		failures.append("temps bloqué %.2f %% > seuil %.2f %%" % [stuck * 100.0, STUCK_TIME_MAX_RATIO * 100.0])

	var goal_changes := float(metrics.get("goal_changes_per_min", NO_DATA))
	if goal_changes >= 0.0 and goal_changes > GOAL_CHANGES_PER_MIN_MAX:
		failures.append("changements de but/min %.2f > seuil %.2f" % [goal_changes, GOAL_CHANGES_PER_MIN_MAX])

	var accuracy: Dictionary = metrics.get("accuracy", {})
	for diff_key in ACCURACY_RANGES:
		var bands: Dictionary = ACCURACY_RANGES[diff_key]
		var observed: Dictionary = accuracy.get(diff_key, {})
		for band in bands:
			var v := float(observed.get(band, NO_DATA))
			if v < 0.0:
				continue  # pas assez de tirs échantillonnés dans cette bande.
			var bounds: Array = bands[band]
			if v < float(bounds[0]) or v > float(bounds[1]):
				failures.append("précision %s/%s hors seuil : %.3f (attendu [%.2f, %.2f])" % [
					diff_key, band, v, bounds[0], bounds[1]])

	var ttk := float(metrics.get("ttk_median_s", NO_DATA))
	if ttk >= 0.0 and (ttk < TTK_MEDIAN_MIN_S or ttk > TTK_MEDIAN_MAX_S):
		failures.append("TTK effectif médian %.2f s hors de [%.2f, %.2f]" % [ttk, TTK_MEDIAN_MIN_S, TTK_MEDIAN_MAX_S])

	var ability_rate := float(metrics.get("ability_uses_per_min", NO_DATA))
	if ability_rate >= 0.0 and ability_rate > ABILITY_PER_MIN_MAX:
		failures.append("capacités utilisées/min %.2f > seuil %.2f" % [ability_rate, ABILITY_PER_MIN_MAX])

	var plant := float(metrics.get("plant_rate", NO_DATA))
	if plant >= 0.0 and (plant < PLANT_RATE_MIN or plant > PLANT_RATE_MAX):
		failures.append("taux de pose %.2f hors de [%.2f, %.2f]" % [plant, PLANT_RATE_MIN, PLANT_RATE_MAX])

	var defuse := float(metrics.get("defuse_rate", NO_DATA))
	if defuse >= 0.0 and (defuse < DEFUSE_RATE_MIN or defuse > DEFUSE_RATE_MAX):
		failures.append("taux de désamorçage %.2f hors de [%.2f, %.2f]" % [defuse, DEFUSE_RATE_MIN, DEFUSE_RATE_MAX])

	return failures

## BOT-20 — compare `metrics["humanity"]` aux seuils OBSERVÉS (B1-B20).
## Renvoie une liste d'avertissements (FRANÇAIS, préfixés "B<n>") — jamais
## traités comme des échecs par `_finish` (mode « observé » du contrat,
## jusqu'à la fin de BOT-29). Même règle NO_DATA que `check_thresholds` :
## une valeur sentinelle n'est jamais un avertissement.
## Pour rendre ces seuils BLOQUANTS (fin de BOT-29) : faire renvoyer à
## `check_thresholds` la concaténation de son propre résultat et de celui-ci
## (`check_thresholds(m) + check_observed_thresholds(m)`), seul changement
## nécessaire.
static func check_observed_thresholds(metrics: Dictionary) -> Array:
	var warnings: Array[String] = []
	var h: Dictionary = metrics.get("humanity", {})

	var yaw_p99 := float(h.get("b1_yaw_speed_p99_deg_s", NO_DATA))
	if yaw_p99 >= 0.0 and yaw_p99 > OBS_YAW_SPEED_P99_MAX_DEG_S:
		warnings.append("B1 p99 vitesse de lacet %.1f°/s > seuil %.1f°/s" % [yaw_p99, OBS_YAW_SPEED_P99_MAX_DEG_S])
	var yaw_snap := int(h.get("b1_yaw_snap_violations", 0))
	if yaw_snap > 0:
		warnings.append("B1 %d rotation(s) > 45° en moins de 60 ms hors combat" % yaw_snap)

	var yaw_accel := float(h.get("b2_yaw_accel_p99_deg_s2", NO_DATA))
	if yaw_accel >= 0.0 and yaw_accel > OBS_YAW_ACCEL_P99_MAX_DEG_S2:
		warnings.append("B2 p99 accélération angulaire %.0f°/s² > seuil %.0f°/s²" % [yaw_accel, OBS_YAW_ACCEL_P99_MAX_DEG_S2])

	var divergence := float(h.get("b3_look_move_divergence_ratio", NO_DATA))
	if divergence >= 0.0 and (divergence < OBS_DIVERGENCE_RATIO_RANGE[0] or divergence > OBS_DIVERGENCE_RATIO_RANGE[1]):
		warnings.append("B3 écart regard/déplacement %.1f %% hors de [%.0f, %.0f] %%" % [
			divergence * 100.0, OBS_DIVERGENCE_RATIO_RANGE[0] * 100.0, OBS_DIVERGENCE_RATIO_RANGE[1] * 100.0])
	var pitch_stddev := float(h.get("b3_pitch_stddev_deg", NO_DATA))
	if pitch_stddev >= 0.0 and pitch_stddev < OBS_PITCH_STDDEV_MIN_DEG:
		warnings.append("B3 écart-type du tangage %.1f° < seuil %.1f°" % [pitch_stddev, OBS_PITCH_STDDEV_MIN_DEG])

	var ttfs_median: Dictionary = h.get("b4_ttfs_median_s", {})
	for diff_key in OBS_TTFS_MEDIAN_RANGES:
		var v := float(ttfs_median.get(diff_key, NO_DATA))
		if v < 0.0:
			continue
		var bounds: Array = OBS_TTFS_MEDIAN_RANGES[diff_key]
		if v < float(bounds[0]) or v > float(bounds[1]):
			warnings.append("B4 TTFS médian %s %.2f s hors de [%.2f, %.2f]" % [diff_key, v, bounds[0], bounds[1]])
	var ttfs_cv: Dictionary = h.get("b4_ttfs_cv", {})
	for diff_key in ttfs_cv:
		var cv := float(ttfs_cv.get(diff_key, NO_DATA))
		if cv >= 0.0 and cv < OBS_TTFS_CV_MIN:
			warnings.append("B4 coefficient de variation TTFS %s %.2f < seuil %.2f" % [diff_key, cv, OBS_TTFS_CV_MIN])
	var ttfs_p5: Dictionary = h.get("b4_ttfs_p5_s", {})
	for diff_key in ttfs_p5:
		var p5 := float(ttfs_p5.get(diff_key, NO_DATA))
		if p5 >= 0.0 and p5 < OBS_TTFS_P5_MIN_S:
			warnings.append("B4 p5 TTFS %s %.2f s < seuil %.2f s" % [diff_key, p5, OBS_TTFS_P5_MIN_S])

	var shots_moving := float(h.get("b5_shots_moving_ratio", NO_DATA))
	if shots_moving >= 0.0 and (shots_moving < OBS_SHOTS_MOVING_RATIO_RANGE[0] or shots_moving > OBS_SHOTS_MOVING_RATIO_RANGE[1]):
		warnings.append("B5 tirs en mouvement %.1f %% hors de [%.0f, %.0f] %%" % [
			shots_moving * 100.0, OBS_SHOTS_MOVING_RATIO_RANGE[0] * 100.0, OBS_SHOTS_MOVING_RATIO_RANGE[1] * 100.0])
	var moving_accuracy := float(h.get("b5_moving_accuracy_ratio", NO_DATA))
	if moving_accuracy >= 0.0 and moving_accuracy > OBS_MOVING_ACCURACY_MAX:
		warnings.append("B5 précision en mouvement %.1f %% > seuil %.1f %%" % [moving_accuracy * 100.0, OBS_MOVING_ACCURACY_MAX * 100.0])
	var fast_moving_shots := float(h.get("b5_fast_moving_shots_ratio", NO_DATA))
	if fast_moving_shots >= 0.0 and fast_moving_shots > OBS_FAST_MOVING_SHOTS_MAX:
		warnings.append("B5 tirs à plus de 6.5 m/s %.1f %% > seuil %.1f %%" % [fast_moving_shots * 100.0, OBS_FAST_MOVING_SHOTS_MAX * 100.0])

	var dodge_median := float(h.get("b6_dodge_segment_median_s", NO_DATA))
	if dodge_median >= 0.0 and (dodge_median < OBS_DODGE_SEGMENT_MEDIAN_RANGE[0] or dodge_median > OBS_DODGE_SEGMENT_MEDIAN_RANGE[1]):
		warnings.append("B6 durée médiane d'esquive %.2f s hors de [%.2f, %.2f]" % [dodge_median, OBS_DODGE_SEGMENT_MEDIAN_RANGE[0], OBS_DODGE_SEGMENT_MEDIAN_RANGE[1]])
	var dodge_max := float(h.get("b6_dodge_segment_max_s", NO_DATA))
	if dodge_max >= 0.0 and dodge_max > OBS_DODGE_SEGMENT_MAX_S:
		warnings.append("B6 segment d'esquive le plus long %.2f s > seuil %.2f s" % [dodge_max, OBS_DODGE_SEGMENT_MAX_S])
	var dodge_lateral := float(h.get("b6_dodge_lateral_p99_m", NO_DATA))
	if dodge_lateral >= 0.0 and dodge_lateral > OBS_DODGE_LATERAL_MAX_M:
		warnings.append("B6 p99 écart latéral d'esquive %.1f m > seuil %.1f m" % [dodge_lateral, OBS_DODGE_LATERAL_MAX_M])
	var dodge_stop := float(h.get("b6_dodge_stop_ratio", NO_DATA))
	if dodge_stop >= 0.0 and (dodge_stop < OBS_DODGE_STOP_RATIO_RANGE[0] or dodge_stop > OBS_DODGE_STOP_RATIO_RANGE[1]):
		warnings.append("B6 part de l'état ARRÊT %.1f %% hors de [%.0f, %.0f] %%" % [
			dodge_stop * 100.0, OBS_DODGE_STOP_RATIO_RANGE[0] * 100.0, OBS_DODGE_STOP_RATIO_RANGE[1] * 100.0])

	var ads_p99 := float(h.get("b7_ads_toggles_p99", NO_DATA))
	if ads_p99 >= 0.0 and ads_p99 > OBS_ADS_TOGGLES_P99_MAX:
		warnings.append("B7 p99 bascules ADS/engagement %.1f > seuil %.1f" % [ads_p99, OBS_ADS_TOGGLES_P99_MAX])
	var ads_rapid := float(h.get("b7_ads_rapid_toggle_ratio", NO_DATA))
	if ads_rapid > OBS_ADS_RAPID_TOGGLE_RATIO_MAX:
		warnings.append("B7 %.1f %% des engagements bascule l'ADS plus d'1 fois/1.5 s" % [ads_rapid * 100.0])

	var semi_cv := float(h.get("b8_semi_auto_interval_cv", NO_DATA))
	if semi_cv >= 0.0 and semi_cv < OBS_SEMI_AUTO_CV_MIN:
		warnings.append("B8 coefficient de variation cadence semi-auto %.2f < seuil %.2f" % [semi_cv, OBS_SEMI_AUTO_CV_MIN])
	var semi_max_rate := float(h.get("b8_semi_auto_max_rate_ratio", NO_DATA))
	if semi_max_rate >= 0.0 and semi_max_rate > OBS_SEMI_AUTO_MAX_RATE_SHARE_MAX:
		warnings.append("B8 tirs à cadence max %.1f %% > seuil %.1f %%" % [semi_max_rate * 100.0, OBS_SEMI_AUTO_MAX_RATE_SHARE_MAX * 100.0])

	var aim_jumps := int(h.get("b9_aim_point_jumps", 0))
	if aim_jumps > OBS_AIM_POINT_JUMPS_MAX:
		warnings.append("B9 %d saut(s) du point visé > 1.5° hors flick/recul" % aim_jumps)

	var snap_fire := float(h.get("b10_snap_then_fire_ratio", NO_DATA))
	if snap_fire >= 0.0 and snap_fire > OBS_SNAP_THEN_FIRE_RATIO_MAX:
		warnings.append("B10 « snap puis tir » %.1f %% > seuil %.1f %%" % [snap_fire * 100.0, OBS_SNAP_THEN_FIRE_RATIO_MAX * 100.0])

	var ally_median := float(h.get("b11_ally_distance_median_m", NO_DATA))
	if ally_median >= 0.0 and (ally_median < OBS_ALLY_DISTANCE_MEDIAN_RANGE[0] or ally_median > OBS_ALLY_DISTANCE_MEDIAN_RANGE[1]):
		warnings.append("B11 distance médiane au coéquipier %.1f m hors de [%.0f, %.0f]" % [ally_median, OBS_ALLY_DISTANCE_MEDIAN_RANGE[0], OBS_ALLY_DISTANCE_MEDIAN_RANGE[1]])
	var ally_close := float(h.get("b11_close_ally_ratio", NO_DATA))
	if ally_close >= 0.0 and ally_close > OBS_ALLY_CLOSE_RATIO_MAX:
		warnings.append("B11 temps à moins de 3 m d'un coéquipier %.1f %% > seuil %.1f %%" % [ally_close * 100.0, OBS_ALLY_CLOSE_RATIO_MAX * 100.0])
	var ally_far := float(h.get("b11_far_from_all_ratio", NO_DATA))
	if ally_far >= 0.0 and ally_far > OBS_ALLY_FAR_RATIO_MAX:
		warnings.append("B11 temps à plus de 30 m de tous %.1f %% > seuil %.1f %%" % [ally_far * 100.0, OBS_ALLY_FAR_RATIO_MAX * 100.0])

	var max_sync := int(h.get("b12_max_simultaneous_goal_changes", 0))
	if max_sync > OBS_MAX_SIMULTANEOUS_GOAL_CHANGES_MAX:
		warnings.append("B12 %d bots ont changé de but dans la même fenêtre de 200 ms" % max_sync)

	var spawn_presence := float(h.get("b13_spawn_presence_ratio", NO_DATA))
	if spawn_presence >= 0.0 and spawn_presence > OBS_SPAWN_PRESENCE_MAX:
		warnings.append("B13 présence au spawn %.1f %% > seuil %.1f %%" % [spawn_presence * 100.0, OBS_SPAWN_PRESENCE_MAX * 100.0])

	var random_jumps := int(h.get("b14_random_jumps", 0))
	if random_jumps > OBS_SUSPICIOUS_GESTURES_MAX:
		warnings.append("B14 %d saut(s) hors combat sans obstacle détecté" % random_jumps)
	var low_speed_crouches := int(h.get("b14_low_speed_crouches", 0))
	if low_speed_crouches > OBS_SUSPICIOUS_GESTURES_MAX:
		warnings.append("B14 %d appui(s) accroupi sous 1 m/s hors combat" % low_speed_crouches)

	var stuck_episodes := float(h.get("b15_stuck_episodes_per_5min", NO_DATA))
	if stuck_episodes >= 0.0 and stuck_episodes > OBS_STUCK_EPISODES_PER_5MIN_MAX:
		warnings.append("B15 %.2f épisode(s) de blocage/5 min > seuil %.2f" % [stuck_episodes, OBS_STUCK_EPISODES_PER_5MIN_MAX])
	var wall_contact := float(h.get("b15_wall_contact_ratio", NO_DATA))
	if wall_contact >= 0.0 and wall_contact > OBS_WALL_CONTACT_RATIO_MAX:
		warnings.append("B15 contacts latéraux avec un mur %.1f %% > seuil %.1f %%" % [wall_contact * 100.0, OBS_WALL_CONTACT_RATIO_MAX * 100.0])

	var trade_ratio := float(h.get("b17_trade_ratio", NO_DATA))
	if trade_ratio >= 0.0 and trade_ratio < OBS_TRADE_RATIO_MIN:
		warnings.append("B17 taux de trade %.1f %% < seuil %.1f %%" % [trade_ratio * 100.0, OBS_TRADE_RATIO_MIN * 100.0])

	var hp_count := float(h.get("b18_zone_bot_count_median", NO_DATA))
	if hp_count >= 0.0 and (hp_count < OBS_HP_ZONE_BOT_COUNT_RANGE[0] or hp_count > OBS_HP_ZONE_BOT_COUNT_RANGE[1]):
		warnings.append("B18 bots médians dans la zone %.1f hors de [%d, %d]" % [hp_count, OBS_HP_ZONE_BOT_COUNT_RANGE[0], OBS_HP_ZONE_BOT_COUNT_RANGE[1]])
	var hp_spacing := float(h.get("b18_zone_spacing_median_m", NO_DATA))
	if hp_spacing >= 0.0 and hp_spacing < OBS_HP_ZONE_SPACING_MIN_M:
		warnings.append("B18 espacement médian dans la zone %.1f m < seuil %.1f m" % [hp_spacing, OBS_HP_ZONE_SPACING_MIN_M])
	var hp_watch := float(h.get("b18_watch_bot_count_median", NO_DATA))
	if hp_watch >= 0.0 and hp_watch < OBS_HP_WATCH_BOT_COUNT_MIN:
		warnings.append("B18 bots médians en surveillance %.1f < seuil %d" % [hp_watch, OBS_HP_WATCH_BOT_COUNT_MIN])
	var hp_arrival := float(h.get("b18_rotation_arrival_ratio", NO_DATA))
	if hp_arrival >= 0.0 and hp_arrival < OBS_HP_ROTATION_ARRIVAL_RATIO_MIN:
		warnings.append("B18 rotations avec un bot arrivé en moins de 10 s %.1f %% < seuil %.1f %%" % [hp_arrival * 100.0, OBS_HP_ROTATION_ARRIVAL_RATIO_MIN * 100.0])

	var hearing := float(h.get("b20_hearing_error_median_m", NO_DATA))
	if hearing >= 0.0:
		if is_zero_approx(hearing):
			warnings.append("B20 erreur d'ouïe médiane exactement 0 m (ouïe non bruitée, attendu avant BOT-29)")
		elif hearing < OBS_HEARING_ERROR_MEDIAN_RANGE[0] or hearing > OBS_HEARING_ERROR_MEDIAN_RANGE[1]:
			warnings.append("B20 erreur d'ouïe médiane %.1f m hors de [%.0f, %.0f]" % [hearing, OBS_HEARING_ERROR_MEDIAN_RANGE[0], OBS_HEARING_ERROR_MEDIAN_RANGE[1]])

	return warnings


## LD-27 — compare `metrics["wasteland"]` aux seuils de régression §e.
## BLOQUANT (contrairement à `check_observed_thresholds`) : son résultat est
## concaténé à celui de `check_thresholds` par `_finish`, jamais fusionné
## DANS `check_thresholds` lui-même (pour ne rien changer au comportement
## des tests BOT-13 existants qui l'appellent directement). Même règle
## NO_DATA que partout ailleurs : une sentinelle n'est jamais un échec.
static func check_wasteland_thresholds(metrics: Dictionary) -> Array:
	var failures: Array[String] = []
	var w: Dictionary = metrics.get("wasteland", {})

	var kills_per_min := float(w.get("kills_per_min_tdm_veteran", NO_DATA))
	if kills_per_min >= 0.0 and kills_per_min < LD27_KILLS_PER_MIN_MIN:
		failures.append("LD-27 kills/min TDM Vétéran %.2f < seuil %.2f" % [kills_per_min, LD27_KILLS_PER_MIN_MIN])

	var first_contact := float(w.get("first_contact_median_s", NO_DATA))
	if first_contact >= 0.0 and (first_contact < LD27_FIRST_CONTACT_MEDIAN_RANGE[0] or first_contact > LD27_FIRST_CONTACT_MEDIAN_RANGE[1]):
		failures.append("LD-27 premier contact médian %.2f s hors de [%.1f, %.1f]" % [
			first_contact, LD27_FIRST_CONTACT_MEDIAN_RANGE[0], LD27_FIRST_CONTACT_MEDIAN_RANGE[1]])

	var lane_share: Dictionary = w.get("lane_share", {})
	for lane_key in lane_share:
		var share := float(lane_share[lane_key])
		if share < 0.0:
			continue  # pas assez de traversées échantillonnées pour cette lane.
		if share < LD27_LANE_SHARE_RANGE[0] or share > LD27_LANE_SHARE_RANGE[1]:
			failures.append("LD-27 part des traversées lane %s %.1f %% hors de [%.0f, %.0f] %%" % [
				lane_key, share * 100.0, LD27_LANE_SHARE_RANGE[0] * 100.0, LD27_LANE_SHARE_RANGE[1] * 100.0])

	var domination := float(w.get("strong_position_max_domination_ratio", NO_DATA))
	if domination >= 0.0 and domination > LD27_STRONG_POSITION_DOMINATION_MAX:
		failures.append("LD-27 position forte tenue par la même équipe %.1f %% > seuil %.1f %%" % [
			domination * 100.0, LD27_STRONG_POSITION_DOMINATION_MAX * 100.0])

	var early_death := float(w.get("early_death_ratio", NO_DATA))
	if early_death >= 0.0 and early_death >= LD27_EARLY_DEATH_RATIO_MAX:
		failures.append("LD-27 morts à <= 3 s d'un spawn %.1f %% >= seuil %.1f %%" % [
			early_death * 100.0, LD27_EARLY_DEATH_RATIO_MAX * 100.0])

	var hp_occupancy := float(w.get("hp_zone_occupancy_min_ratio", NO_DATA))
	if hp_occupancy >= 0.0 and hp_occupancy < LD27_HP_ZONE_OCCUPANCY_MIN_RATIO:
		failures.append("LD-27 zone HP occupée au minimum %.1f %% < seuil %.1f %%" % [
			hp_occupancy * 100.0, LD27_HP_ZONE_OCCUPANCY_MIN_RATIO * 100.0])

	return failures


# ======================================================================
#  Nœud d'échantillonnage PHYSIQUE — le rappel MainLoop._process ci-dessous
#  (une fois par IMAGE, jamais garanti aligné sur un tick physique, voir
#  Godot MainLoop) ne convient pas à un ratio "temps bloqué" ou à la détection
#  d'un saut de but : ce petit nœud, ajouté à `root`, lit l'état des bots à
#  CHAQUE tick physique, comme BotBrain lui-même.
# ======================================================================
class BenchSampler extends Node:
	var on_tick: Callable
	func _physics_process(delta: float) -> void:
		if on_tick.is_valid():
			on_tick.call(delta)


# ======================================================================
#  État d'exécution (CLI + phases)
# ======================================================================
var _phases: Array = []
var _tdm_duration := DEFAULT_TDM_DURATION
var _snd_rounds := DEFAULT_SND_ROUNDS
var _map_id := DEFAULT_MAP
var _time_scale := DEFAULT_TIME_SCALE
var _out_path := OUT_DEFAULT
var _presence_cell := 2.0
var _presence_out_path := ""   ## résolu depuis `_out_path` si vide, voir `_initialize`.

var _started := false
var _phase_index := -1
var _phase_active := false
var _phase_kind := ""          ## "tdm" | "hp" | "snd"
var _phase_difficulty_key := ""
var _phase_elapsed := 0.0

var _world: Node = null
var _mode: Node = null
var _sampler: BenchSampler = null
var _last_goal_by_bot: Dictionary = {}         ## bot_id (int) -> Vector3
var _hooked_bot_ids: Dictionary = {}           ## bot_id (int) -> true (voir _hook_bot)
var _last_bomb_state := -1

## Compteurs GLOBAUX, cumulés sur TOUTES les phases où ils s'appliquent.
var _shots_by_band: Dictionary = {}      ## "recrue" -> {"5m": int, ...}
var _hits_by_band: Dictionary = {}
var _blocked_ticks := 0
var _total_bot_ticks := 0
## Somme des `delta` observés PAR BOT (pas par tick de match) : dénominateur
## de `goal_changes_per_min`/`ability_uses_per_min`, pour un taux "PAR bot"
## comparable d'un match à l'autre quel que soit le nombre de bots présents —
## jamais la simple durée du match (`_goal_changes`/`_ability_events` sont
## eux-mêmes des SOMMES sur tous les bots, voir `_sample_tick`).
var _bot_seconds_total := 0.0
var _goal_changes := 0
var _shuttle_events := 0                   ## navettes A→B→A détectées (comptées à part, voir _register_goal_change).
var _goal_change_history: Dictionary = {}  ## bot_id -> Array (max 3) de {pos, time} — voir _register_goal_change.
var _ttk_samples: Array = []
var _ability_events := 0
var _snd_rounds_played := 0
var _snd_planted := 0
var _snd_defused := 0
var _phase_reports: Array = []           ## un résumé par phase, pour le JSON (traçabilité).

# ---- BOT-20 : accumulateurs B1-B15, B17, B18, B20 (phases Vétéran only, cf. tête) ----
var _b1_yaw_speed_samples: Array = []
var _b1_yaw_snap_violations := 0
var _b2_yaw_accel_samples: Array = []
var _b3_divergence_ticks := 0
var _b3_hors_combat_ticks := 0
var _b3_pitch_samples: Array = []
var _b4_ttfs_by_diff: Dictionary = {}     ## diff_key -> Array[float] (TOUTES difficultés/phases).
var _b5_shots_moving := 0
var _b5_shots_total_veteran := 0
var _b5_hits_moving := 0
var _b5_fast_moving_shots := 0
var _b6_dodge_segment_samples: Dictionary = {}  ## bot_id -> Array de [strafe_dir, dt] (en combat).
var _b6_dodge_durations: Array = []
var _b6_dodge_laterals: Array = []
var _b6_dodge_stop_count := 0
var _b6_dodge_total_count := 0
var _b7_ads_toggle_counts: Array = []
var _b7_ads_rapid_violations := 0
var _b7_ads_engagements := 0
var _b8_semi_auto_intervals: Array = []
var _b8_semi_auto_at_max_rate := 0
var _b8_semi_auto_total := 0
var _b9_aim_point_jumps := 0
var _b10_snap_shots := 0
var _b10_shots_with_rotation_data := 0
var _b11_ally_distance_samples: Array = []
var _b11_close_count := 0
var _b11_far_count := 0
var _b11_total_count := 0
var _b12_goal_change_times_by_team: Dictionary = {0: [], 1: []}
## Max glissant "par phase" plutôt qu'un seul calcul global : les horodatages
## de `_b12_goal_change_times_by_team` sont relatifs à `_phase_elapsed`, qui
## repart de zéro à chaque phase (`_begin_phase`) — les comparer TELS QUELS
## entre deux phases différentes ferait passer pour "simultanés" deux
## changements qui n'ont rien à voir. Calculé et cumulé à chaque `_end_phase`,
## AVANT la remise à zéro par phase.
var _b12_running_max_simultaneous := 0
var _b13_spawn_close_ticks := 0
var _b13_spawn_total_ticks := 0
var _b14_random_jumps := 0
var _b14_low_speed_crouches := 0
var _b15_stuck_episodes := 0
var _b15_wall_contact_ticks := 0
var _b15_wall_ticks_total := 0
var _deaths_log: Array = []       ## {time, phase_index, killer_id, victim_team}
var _damage_log: Array = []       ## {time, phase_index, attacker_id, target_id}
var _team_by_bot_id: Dictionary = {}
var _b18_zone_counts: Array = []
var _b18_zone_spacings: Array = []
var _b18_watch_counts: Array = []
var _last_hp_zone_pos := Vector3.INF
var _hp_rotation_pending := false
var _hp_rotation_time := 0.0
var _hp_rotation_arrivals: Array = []   ## Array[bool]
var _b20_hearing_errors: Array = []

## Suivi par bot — état vivant pendant la phase courante, remis à zéro à
## chaque `_begin_phase` (comme `_last_goal_by_bot`/`_hooked_bot_ids`).
var _bot_track: Dictionary = {}   ## bot_id -> Dictionary (voir `_hook_bot`).

## Grille de présence 2 m (B19, format tools/heatmap.gd — voir doc de tête) :
## remplie SEULEMENT pendant tdm_veteran/hp_veteran (la "mesure de départ").
var _presence_bounds: Dictionary = {}
var _presence_grid_w := 0
var _presence_grid_h := 0
var _presence_team0: Array = []
var _presence_team1: Array = []

# ---- LD-27 : données bots Wasteland (chargées une fois, `_load_wasteland_
# bot_data`) + accumulateurs des seuils §e (phases tdm_veteran/hp_veteran
# seules, voir la docstring de tête). Vides sur toute autre carte : chaque
# métrique dérivée retombe alors sur NO_DATA sans code séparé par carte. ----
var _phase_key := ""                      ## "tdm_veteran"/"hp_veteran"/... — mis à jour par `_begin_phase`.
var _lane_points: Dictionary = {}         ## lane_key -> Array[Vector3] (WastelandBots._lanes()).
var _hotspots: Array = []                 ## Array[{pos, lane, weight, callout}] (WastelandBots._hotspots()).
var _strong_positions: Array = []         ## Array[Vector3] (WastelandMarkers._strong_positions()).
var _strong_position_hold_time: Array = []  ## parallèle à `_strong_positions` : Dictionary team(int) -> float(s).
var _strong_position_observed_time := 0.0
var _lane_crossing_counts: Dictionary = {}  ## lane_key -> int, incrémenté par `_register_goal_change`.
var _first_contact_samples: Array = []      ## Array[float] (s), une par vie de bot, phase tdm_veteran seule.
var _hp_window_stats: Dictionary = {}       ## str(window_index) -> {occupied, total, first_t, last_t} — clé String (jamais int : sérialisation JSON de `raw`).


func _initialize() -> void:
	var phases_arg := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tdm-duration="):
			_tdm_duration = maxf(1.0, float(a.get_slice("=", 1)))
		elif a.begins_with("--snd-rounds="):
			_snd_rounds = maxi(1, int(a.get_slice("=", 1)))
		elif a.begins_with("--map="):
			_map_id = a.get_slice("=", 1)
		elif a.begins_with("--time-scale="):
			_time_scale = maxf(0.05, float(a.get_slice("=", 1)))
		elif a.begins_with("--out="):
			_out_path = a.get_slice("=", 1)
		elif a.begins_with("--phases="):
			phases_arg = a.get_slice("=", 1)
		elif a.begins_with("--presence-cell="):
			_presence_cell = maxf(0.1, float(a.get_slice("=", 1)))
		elif a.begins_with("--presence-out="):
			_presence_out_path = a.get_slice("=", 1)
	if phases_arg != "":
		var requested: Array[String] = []
		for p in phases_arg.split(","):
			if ALL_PHASES.has(p):
				requested.append(p)
		_phases = requested if not requested.is_empty() else ALL_PHASES.duplicate()
	else:
		_phases = ALL_PHASES.duplicate()
	if _presence_out_path == "":
		var dir := _out_path.get_base_dir()
		_presence_out_path = "%s/presence_grid.json" % dir if dir != "" else "presence_grid.json"
	_setup_presence_grid()
	_load_wasteland_bot_data()


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_sampler = BenchSampler.new()
		_sampler.on_tick = _sample_tick
		root.add_child(_sampler)
		_phase_index = 0
		_begin_phase()
		return false
	if not _phase_active:
		return false
	_phase_elapsed += _delta
	var phase_done := false
	if _phase_kind == "tdm" or _phase_kind == "hp":
		phase_done = _phase_elapsed >= _tdm_duration
	else:
		phase_done = _mode != null and int(_mode.round_state.rounds_played) >= _snd_rounds
	if not phase_done:
		return false
	_end_phase()
	_phase_index += 1
	if _phase_index >= _phases.size():
		_finish()
		return true
	_begin_phase()
	return false


# ======================================================================
#  Phases — une partie complète (TDM/Hardpoint une durée, SnD N manches),
#  même patron de démarrage que tools/bot_smoke.gd._start.
# ======================================================================
func _begin_phase() -> void:
	var key: String = _phases[_phase_index]
	var parts := key.split("_")
	_phase_kind = parts[0]
	_phase_difficulty_key = parts[1]
	_phase_key = key
	_phase_elapsed = 0.0
	_last_goal_by_bot.clear()
	_hooked_bot_ids.clear()
	_last_bomb_state = -1
	_bot_track.clear()
	_goal_change_history.clear()
	_team_by_bot_id.clear()
	_b6_dodge_segment_samples.clear()
	_b12_goal_change_times_by_team = {0: [], 1: []}
	_last_hp_zone_pos = Vector3.INF
	_hp_rotation_pending = false
	_hp_rotation_time = 0.0

	var mode_id := "tdm"
	if _phase_kind == "hp":
		mode_id = "hardpoint"
	elif _phase_kind == "snd":
		mode_id = "snd"
	MatchConfig.set_mode(mode_id)
	MatchConfig.map_id = _map_id
	MatchConfig.bots_enabled = true
	MatchConfig.bot_difficulty = int(DIFFICULTY_BY_KEY[_phase_difficulty_key])
	Engine.time_scale = _time_scale

	var net := NetworkManager.get_net(self)
	var peer := get_multiplayer().multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		net.host()

	var level_path := MatchConfig.resolve_scene(MatchConfig.mode_id, _map_id)
	var scene: PackedScene = load(level_path)
	_world = scene.instantiate()
	_world.set("allow_bot_fill", true)
	# Pas d'écran de sélection d'agent (même garde que tools/map_shots.gd) :
	# les bots ne remplissent les équipes qu'au spawn de l'hôte, soit 15 s
	# (compte à rebours d'AgentSelectScreen) APRÈS le début de la phase — la
	# minuterie de rotation Hardpoint et la 1re fenêtre LD-27 de 60 s
	# tournaient donc 15 s sans aucun bot (diag 2026-09-25 : premier bot
	# observé à t = 15 s), ce qui plafonnait l'occupation de cette fenêtre.
	_world.set("agent_select", false)
	root.add_child(_world)
	current_scene = _world

	_mode = get_first_node_in_group("game_mode")
	if _phase_kind == "snd" and _mode != null and _mode.round_state != null:
		# Ne jamais couper la série de manches avant `--snd-rounds` sur un
		# score déséquilibré (contrat : "SnD 10 manches", pas "jusqu'à la
		# victoire") — voir la doc de SND_ROUNDS_TO_WIN_OVERRIDE.
		_mode.round_state.rounds_to_win = SND_ROUNDS_TO_WIN_OVERRIDE

	print("BOT_BENCH_PHASE_START phase=%s mode=%s difficulty=%s map=%s" % [
		key, MatchConfig.mode_id, _phase_difficulty_key, _map_id])
	_phase_active = true


func _end_phase() -> void:
	_phase_active = false
	_flush_pending_humanity_state()
	_b12_running_max_simultaneous = maxi(_b12_running_max_simultaneous, maxi(
		max_simultaneous_events(_b12_goal_change_times_by_team.get(0, []), SYNC_WINDOW_S),
		max_simultaneous_events(_b12_goal_change_times_by_team.get(1, []), SYNC_WINDOW_S)))
	var report := {"phase": "%s_%s" % [_phase_kind, _phase_difficulty_key]}
	if _phase_kind == "snd" and _mode != null and _mode.round_state != null:
		var played := int(_mode.round_state.rounds_played)
		_snd_rounds_played += played
		report["rounds_played"] = played
	else:
		report["duration_s"] = _phase_elapsed
	_phase_reports.append(report)
	print("BOT_BENCH_PHASE_END %s" % [JSON.stringify(report)])
	if _world:
		# `queue_free()` ne retire le nœud (et son appartenance au groupe
		# "game_mode") qu'à LA FIN de l'image — la phase suivante
		# (`_begin_phase`, appelée synchrone juste après par `_process`)
		# verrait alors encore l'ANCIEN mode via `get_first_node_in_group`,
		# potentiellement avant même que le NOUVEAU n'y soit (ordre du
		# groupe). Un retrait + libération IMMÉDIATS évitent cette course.
		root.remove_child(_world)
		_world.free()
	_world = null
	_mode = null


func _finish() -> void:
	Engine.time_scale = 1.0
	var metrics := _collect_metrics()
	# LD-27 — concaténé APRÈS check_thresholds (jamais fusionné dans son
	# corps, voir la docstring de `check_wasteland_thresholds`) : les deux
	# décident ensemble du code de sortie, comme n'importe quel autre échec
	# BOT-13.
	var failures := check_thresholds(metrics) + check_wasteland_thresholds(metrics)
	var warnings := check_observed_thresholds(metrics)
	_write_presence_grid()
	var out := {
		"generated_at": Time.get_unix_time_from_system(),
		"map": _map_id,
		"phases": _phase_reports,
		"metrics": metrics,
		"failures": failures,
		"observed_warnings": warnings,
		"presence_grid": _presence_out_path,
		"raw": {
			"shots_by_band": _shots_by_band,
			"hits_by_band": _hits_by_band,
			"blocked_ticks": _blocked_ticks,
			"total_bot_ticks": _total_bot_ticks,
			"bot_sim_seconds": _bot_seconds_total,
			"goal_changes": _goal_changes,
			"shuttle_events": int(metrics.humanity.b12_shuttle_events),
			"ttk_samples": _ttk_samples,
			"ability_events": _ability_events,
			"snd_rounds_played": _snd_rounds_played,
			"snd_planted": _snd_planted,
			"snd_defused": _snd_defused,
			# LD-27 — compteurs bruts pour l'investigation (§e), même esprit
			# que le reste de `raw` : jamais seulement le ratio final.
			"lane_crossing_counts": _lane_crossing_counts,
			"strong_position_hold_time_s": _strong_position_hold_time,
			"strong_position_observed_time_s": _strong_position_observed_time,
			"hp_zone_window_stats": _hp_window_stats,
			"first_contact_samples_s": _first_contact_samples,
		},
	}
	_write_json(_out_path, out)
	var ok := failures.is_empty()
	print("BOT_BENCH_RESULT ok=%s failures=%d warnings=%d out=%s" % [
		ok, failures.size(), warnings.size(), ProjectSettings.globalize_path(_out_path)])
	for f in failures:
		print("BOT_BENCH_FAILURE %s" % [f])
	for w in warnings:
		print("BOT_BENCH_OBSERVED %s" % [w])
	quit(0 if ok else 1)


func _write_json(path: String, data: Dictionary) -> void:
	var dir := path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("bot_bench: impossible d'écrire %s (err=%s)" % [path, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()


# ======================================================================
#  Agrégation finale — traduit les compteurs bruts dans la forme exportée
#  (même schéma que `empty_metrics`, voir tests/ai/test_bot_bench_thresholds.gd).
# ======================================================================
func _collect_metrics() -> Dictionary:
	var m := empty_metrics()
	m.stuck_time_ratio = ratio(_blocked_ticks, _total_bot_ticks)
	m.goal_changes_per_min = per_minute(_goal_changes, _bot_seconds_total)
	m.ttk_median_s = median(_ttk_samples)
	m.ability_uses_per_min = per_minute(_ability_events, _bot_seconds_total)
	m.plant_rate = ratio(_snd_planted, _snd_rounds_played)
	m.defuse_rate = ratio(_snd_defused, _snd_rounds_played)
	m.rounds_played = _snd_rounds_played
	for diff_key in ACCURACY_RANGES:
		var shots: Dictionary = _shots_by_band.get(diff_key, {})
		var hits: Dictionary = _hits_by_band.get(diff_key, {})
		for band in DISTANCE_BANDS:
			m.accuracy[diff_key][band] = ratio(int(hits.get(band, 0)), int(shots.get(band, 0)))

	var h: Dictionary = m.humanity
	h.b1_yaw_speed_p99_deg_s = p99(_b1_yaw_speed_samples)
	h.b1_yaw_snap_violations = _b1_yaw_snap_violations
	h.b2_yaw_accel_p99_deg_s2 = p99(_b2_yaw_accel_samples)
	h.b3_look_move_divergence_ratio = ratio(_b3_divergence_ticks, _b3_hors_combat_ticks)
	h.b3_pitch_stddev_deg = _stddev(_b3_pitch_samples)
	for diff_key in _b4_ttfs_by_diff:
		var samples: Array = _b4_ttfs_by_diff[diff_key]
		h.b4_ttfs_median_s[diff_key] = median(samples)
		h.b4_ttfs_cv[diff_key] = coefficient_of_variation(samples)
		h.b4_ttfs_p5_s[diff_key] = percentile(samples, 0.05)
	h.b5_shots_moving_ratio = ratio(_b5_shots_moving, _b5_shots_total_veteran)
	h.b5_moving_accuracy_ratio = ratio(_b5_hits_moving, _b5_shots_moving)
	h.b5_fast_moving_shots_ratio = ratio(_b5_fast_moving_shots, _b5_shots_total_veteran)
	h.b6_dodge_segment_median_s = median(_b6_dodge_durations)
	h.b6_dodge_segment_max_s = _max_or_sentinel(_b6_dodge_durations)
	h.b6_dodge_lateral_p99_m = p99(_b6_dodge_laterals)
	h.b6_dodge_stop_ratio = ratio(_b6_dodge_stop_count, _b6_dodge_total_count)
	h.b7_ads_toggles_p99 = p99(_b7_ads_toggle_counts)
	h.b7_ads_rapid_toggle_ratio = ratio(_b7_ads_rapid_violations, _b7_ads_engagements)
	h.b8_semi_auto_interval_cv = coefficient_of_variation(_b8_semi_auto_intervals)
	h.b8_semi_auto_max_rate_ratio = ratio(_b8_semi_auto_at_max_rate, _b8_semi_auto_total)
	h.b9_aim_point_jumps = _b9_aim_point_jumps
	h.b10_snap_then_fire_ratio = ratio(_b10_snap_shots, _b10_shots_with_rotation_data)
	h.b11_ally_distance_median_m = median(_b11_ally_distance_samples)
	h.b11_close_ally_ratio = ratio(_b11_close_count, _b11_total_count)
	h.b11_far_from_all_ratio = ratio(_b11_far_count, _b11_total_count)
	h.b12_max_simultaneous_goal_changes = _b12_running_max_simultaneous
	h.b12_shuttle_events = _shuttle_events
	h.b13_spawn_presence_ratio = ratio(_b13_spawn_close_ticks, _b13_spawn_total_ticks)
	h.b14_random_jumps = _b14_random_jumps
	h.b14_low_speed_crouches = _b14_low_speed_crouches
	# b14_goalless_slides reste à -1 (NO_DATA) : nécessite l'INTENTION du but
	# de BotBrain (glissade "vers un but à plus de 8 m"), illisible de
	# l'extérieur avant que BOT-21 n'expose cette décision — voir M1/§3.3.
	h.b15_stuck_episodes_per_5min = _rate_per_n_minutes(_b15_stuck_episodes, _bot_seconds_total, 5.0)
	h.b15_wall_contact_ratio = ratio(_b15_wall_contact_ticks, _b15_wall_ticks_total)
	h.b17_trade_ratio = _compute_trade_ratio()
	h.b18_zone_bot_count_median = median(_b18_zone_counts)
	h.b18_zone_spacing_median_m = median(_b18_zone_spacings)
	h.b18_watch_bot_count_median = median(_b18_watch_counts)
	h.b18_rotation_arrival_ratio = _ratio_of_bools(_hp_rotation_arrivals)
	h.b20_hearing_error_median_m = median(_b20_hearing_errors)

	var w: Dictionary = m.wasteland
	var tdm_veteran_index := _phases.find("tdm_veteran")
	var kills_tdm_veteran := 0
	for death in _deaths_log:
		if int(death.phase_index) == tdm_veteran_index:
			kills_tdm_veteran += 1
	w.kills_per_min_tdm_veteran = per_minute(kills_tdm_veteran, _duration_for_phase_key("tdm_veteran"))
	w.first_contact_median_s = median(_first_contact_samples)
	var lane_total := 0
	for lane_key in _lane_crossing_counts:
		lane_total += int(_lane_crossing_counts[lane_key])
	var lane_share: Dictionary = w.lane_share
	for lane_key in lane_share.keys():
		lane_share[lane_key] = ratio(int(_lane_crossing_counts.get(lane_key, 0)), lane_total)
	w.strong_position_max_domination_ratio = _compute_strong_position_domination()
	w.early_death_ratio = _compute_early_death_ratio(tdm_veteran_index)
	w.hp_zone_occupancy_min_ratio = _compute_hp_zone_occupancy_min_ratio()
	return m


func _stddev(values: Array) -> float:
	if values.size() < 2:
		return NO_DATA
	var sum := 0.0
	for v in values:
		sum += float(v)
	var mean := sum / values.size()
	var sq := 0.0
	for v in values:
		sq += (float(v) - mean) * (float(v) - mean)
	return sqrt(sq / values.size())


func _max_or_sentinel(values: Array) -> float:
	if values.is_empty():
		return NO_DATA
	var m: float = -INF
	for v in values:
		m = maxf(m, float(v))
	return m


## `per_minute(...)` ramené à un rythme "par N minutes" — NO_DATA reste
## NO_DATA (jamais multipliée en sentinelle bruitée type "-5.0").
func _rate_per_n_minutes(count: int, duration_s: float, n: float) -> float:
	var per_min := per_minute(count, duration_s)
	if per_min < 0.0:
		return NO_DATA
	return per_min * n


func _ratio_of_bools(values: Array) -> float:
	if values.is_empty():
		return NO_DATA
	var hits := 0
	for v in values:
		if bool(v):
			hits += 1
	return ratio(hits, values.size())


## B17 — voir la doc de tête : une mort alliée est "tradée" si, dans les
## `TRADE_WINDOW_S` qui suivent, un AUTRE allié de la victime blesse le
## tueur — même phase uniquement (les horloges/positions repartent de zéro
## à chaque `_begin_phase`, comparer entre deux phases n'aurait aucun sens).
func _compute_trade_ratio() -> float:
	if _deaths_log.is_empty():
		return NO_DATA
	var traded := 0
	for death in _deaths_log:
		var traded_this_death := false
		for dmg in _damage_log:
			if int(dmg.phase_index) != int(death.phase_index):
				continue
			if int(dmg.target_id) != int(death.killer_id):
				continue
			if float(dmg.time) <= float(death.time) or float(dmg.time) > float(death.time) + TRADE_WINDOW_S:
				continue
			if int(dmg.attacker_team) == int(death.victim_team) and int(dmg.attacker_id) != int(death.killer_id):
				traded_this_death = true
				break
		if traded_this_death:
			traded += 1
	return ratio(traded, _deaths_log.size())


## LD-27 — durée RÉELLE (s) d'une phase déjà terminée, par sa clé complète
## ("tdm_veteran"/"hp_veteran"/...), lue dans `_phase_reports` (déjà écrit
## par `_end_phase`, jamais recalculée séparément) — NO_DATA (-1.0) si cette
## phase n'a pas tourné (`--phases=` l'a exclue).
func _duration_for_phase_key(key: String) -> float:
	for report in _phase_reports:
		if String(report.get("phase", "")) == key:
			return float(report.get("duration_s", NO_DATA))
	return NO_DATA


## LD-27 — part des morts de la phase `phase_index` (déjà résolu par
## `_collect_metrics`, "tdm_veteran") survenues à `LD27_EARLY_DEATH_WINDOW_S`
## s ou moins du dernier spawn de la victime (`victim_life_clock_s`, posé par
## `_on_bot_died`) — même discipline que `_compute_trade_ratio` (dérivé
## post-hoc de `_deaths_log`, rien accumulé à part). `phase_index < 0`
## (phase absente de ce run) ou aucune mort avec un âge de vie valide (NO_DATA
## sur `victim_life_clock_s`, hors phase Vétéran) renvoie NO_DATA.
func _compute_early_death_ratio(phase_index: int) -> float:
	if phase_index < 0:
		return NO_DATA
	var total := 0
	var early := 0
	for death in _deaths_log:
		if int(death.phase_index) != phase_index:
			continue
		var life_clock := float(death.get("victim_life_clock_s", NO_DATA))
		if life_clock < 0.0:
			continue
		total += 1
		if life_clock <= LD27_EARLY_DEATH_WINDOW_S:
			early += 1
	return ratio(early, total)


## LD-27 — MAX, sur toutes les (position forte, équipe), du temps de tenue
## rapporté au temps total observé (`_strong_position_observed_time`, avancé
## une fois par tick par `_sample_strong_positions`, jamais par position) —
## NO_DATA si rien n'a jamais été observé (carte sans `strong_positions`, ou
## phase tdm_veteran absente de ce run).
func _compute_strong_position_domination() -> float:
	if _strong_position_observed_time <= 0.0:
		return NO_DATA
	var best := 0.0
	for by_team in _strong_position_hold_time:
		for team in (by_team as Dictionary):
			best = maxf(best, float(by_team[team]) / _strong_position_observed_time)
	return best


## LD-27 — MINIMUM, sur chaque fenêtre de `LD27_HP_ZONE_WINDOW_S` s
## ENTIÈREMENT observée (`LD27_HP_ZONE_WINDOW_MIN_COVERAGE_S`, écarte une
## fenêtre finale tronquée), de la fraction de ticks où la zone active avait
## au moins un bot vivant dedans (`_hp_window_stats`, rempli par
## `_sample_hardpoint`) — NO_DATA si aucune fenêtre n'a été entièrement
## observée (phase hp_veteran absente de ce run, ou plus courte que
## `LD27_HP_ZONE_WINDOW_MIN_COVERAGE_S`).
func _compute_hp_zone_occupancy_min_ratio() -> float:
	var best := INF
	for window_index in _hp_window_stats:
		var stat: Dictionary = _hp_window_stats[window_index]
		var coverage := float(stat.last_t) - float(stat.first_t)
		if coverage < LD27_HP_ZONE_WINDOW_MIN_COVERAGE_S:
			continue
		var window_ratio := ratio(int(stat.occupied), int(stat.total))
		if window_ratio < 0.0:
			continue
		best = minf(best, window_ratio)
	return NO_DATA if is_inf(best) else best


# ======================================================================
#  Échantillonnage physique — temps bloqué, changements de but, bombe SnD
#  (BOT-13) + humanité B1-B15/B17/B18/B20 et présence (BOT-20).
# ======================================================================
func _sample_tick(delta: float) -> void:
	if _world == null or not _phase_active:
		return
	var players := _world.get_node_or_null(_world.players_root)
	if players == null:
		return
	# Seules les phases Vétéran alimentent les métriques B1-B20 (hors B4,
	# ventilée par difficulté comme la précision BOT-13) — voir doc de tête.
	var veteran_phase := _phase_difficulty_key == "veteran"
	var hp_zone: Area3D = (_mode.get("_zone") as Area3D) if (_phase_kind == "hp" and _mode != null) else null
	if hp_zone != null:
		_sample_hardpoint(hp_zone, players)

	var living_by_team := {0: [], 1: []}   ## team -> Array[Vector3] (bots vivants, hors grâce spawn, veteran only)

	for p in players.get_children():
		if not bool(p.get("is_bot")):
			continue
		var brain := p.get_node_or_null("BotBrain")
		if brain == null:
			continue
		var bot_id := str(p.name).to_int()
		if not _hooked_bot_ids.has(bot_id):
			_hook_bot(p, brain)
			_hooked_bot_ids[bot_id] = true
		_total_bot_ticks += 1
		_bot_seconds_total += delta

		var stuck = brain.get("_stuck")
		var blocked := false
		var stuck_phase_val := int(BotStuck.Phase.IDLE)
		if stuck != null:
			stuck_phase_val = int(stuck.get("_phase"))
			blocked = stuck_phase_val == BotStuck.Phase.WIGGLE or stuck_phase_val == BotStuck.Phase.JUMP or stuck_phase_val == BotStuck.Phase.REQUEST_REPATH
			if blocked:
				_blocked_ticks += 1
		var nav_agent = brain.get("nav_agent")
		var in_combat := int(brain.get("_target_id")) != -1
		_sample_acquisition_and_hearing(brain, bot_id)
		# "changements de but" = objectif de PATROUILLE/mémoire d'ennemi instable
		# (l'écart documenté, docs/research/02_bots_ai.md #2/#4.1), jamais le
		# nav_agent qui suit une cible de COMBAT vivante d'un tick à l'autre —
		# `_target_pos` bouge naturellement de plusieurs mètres entre deux
		# repaths (0.5 s) dès qu'un ennemi strafe, sans qu'aucun objectif n'ait
		# réellement "changé" (déjà couvert par la précision/le TTK). Ignoré
		# purement et simplement en combat (`_target_id != -1`), mais
		# `_last_goal_by_bot` reste à jour pendant ce temps (silencieusement)
		# pour que le premier échantillon HORS combat compare contre le dernier
		# but RÉEL, pas un vieux point de patrouille d'avant l'engagement.
		if nav_agent != null:
			var goal: Vector3 = nav_agent.target_position
			if _last_goal_by_bot.has(bot_id):
				var prev: Vector3 = _last_goal_by_bot[bot_id]
				if not in_combat and prev.distance_to(goal) > GOAL_JUMP_THRESHOLD_M:
					_register_goal_change(bot_id, int(p.get("team")), goal, _phase_elapsed)
			_last_goal_by_bot[bot_id] = goal

		if veteran_phase:
			_sample_humanity(p, brain, bot_id, delta, in_combat, blocked, stuck_phase_val)
			var health := _bot_track.get(bot_id, {}).get("health") as Health
			var alive := health == null or not health.is_dead
			var life_clock := float(_bot_track.get(bot_id, {}).get("life_clock", 0.0))
			if alive and life_clock >= SPAWN_GRACE_S:
				var team := int(p.get("team"))
				living_by_team[team].append((p as Node3D).global_position)
			# B19 : grille de présence — seulement tdm_veteran/hp_veteran (la
			# "mesure de départ" du contrat), jamais snd_veteran (aussi
			# "veteran_phase" mais hors périmètre de cette grille).
			if _phase_kind == "tdm" or _phase_kind == "hp":
				_sample_presence(p, health)

	if veteran_phase:
		_sample_spacing(living_by_team)
		# LD-27 — domination des positions fortes : phase tdm_veteran seule
		# (§e les groupe avec kills/premier contact/lanes, voir docstring de
		# tête), et seulement si la carte en déclare (`_strong_positions`
		# vide sur cargo_ship, jamais d'accumulation là-bas).
		if _phase_key == "tdm_veteran" and not _strong_positions.is_empty():
			_sample_strong_positions(delta, living_by_team)

	if _phase_kind == "snd" and _mode != null:
		_poll_bomb_state()


## BOT-20 — B1-B3, B5, B9, B13-B15 (échantillonnage géométrique/entrées) sur
## UN bot, à CE tick. `_bot_track[bot_id]` porte l'état roulant (voir
## `_hook_bot` pour son initialisation).
func _sample_humanity(node: Node, brain: Node, bot_id: int, delta: float, in_combat: bool, blocked: bool, stuck_phase: int) -> void:
	var track: Dictionary = _bot_track.get(bot_id)
	if track == null:
		return
	var health := track.get("health") as Health
	if health != null and health.is_dead:
		return
	var p := node as Node3D
	var now := _phase_elapsed

	# B15 — épisode de blocage (front montant) + contact latéral (mur).
	if blocked and not bool(track.get("prev_blocked", false)):
		_b15_stuck_episodes += 1
	track["prev_blocked"] = blocked
	if node.has_method("is_on_wall"):
		_b15_wall_ticks_total += 1
		if node.call("is_on_wall"):
			_b15_wall_contact_ticks += 1

	# B13 — présence au spawn, au-delà des 10 premières secondes de vie.
	track["life_clock"] = float(track.get("life_clock", 0.0)) + delta
	if float(track["life_clock"]) >= SPAWN_GRACE_S:
		var spawn_pos: Vector3 = track.get("spawn_pos", p.global_position)
		_b13_spawn_total_ticks += 1
		if p.global_position.distance_to(spawn_pos) < SPAWN_PRESENCE_RADIUS_M:
			_b13_spawn_close_ticks += 1

	# B1/B2/B3/B9 — lacet/tangage du regard réellement appliqué (rotation.y
	# du corps + tangage de la tête), seule direction observable de
	# l'extérieur (post-ressort, post-recul — c'est littéralement "où pointe
	# le viseur").
	var head: Node3D = node.get("head")
	var look_xz := Vector2(-p.global_transform.basis.z.x, -p.global_transform.basis.z.z)
	var look_pitch_deg := 0.0
	if head != null:
		look_pitch_deg = rad_to_deg(head.rotation.x)
		_b3_pitch_samples.append(look_pitch_deg)
	if look_xz.length() > 0.0001:
		look_xz = look_xz.normalized()
		if bool(track.get("prev_look_valid", false)):
			var prev_xz: Vector2 = track["prev_look_xz"]
			var cross := prev_xz.x * look_xz.y - prev_xz.y * look_xz.x
			var dot := prev_xz.dot(look_xz)
			var delta_yaw_deg := rad_to_deg(atan2(cross, dot))
			var yaw_speed := absf(delta_yaw_deg) / maxf(delta, 0.0001)
			if not in_combat:
				_b1_yaw_speed_samples.append(yaw_speed)
				# Fenêtre glissante ~60 ms (B1 "0 rotation > 45° en < 60 ms").
				var window: Array = track.get("yaw_window", [])
				window.append([now, absf(delta_yaw_deg)])
				while not window.is_empty() and now - float(window[0][0]) > 0.06:
					window.pop_front()
				var window_sum := 0.0
				for w in window:
					window_sum += float(w[1])
				if window_sum > 45.0:
					_b1_yaw_snap_violations += 1
				track["yaw_window"] = window
				var prev_rate := float(track.get("prev_yaw_rate", yaw_speed))
				_b2_yaw_accel_samples.append(absf(yaw_speed - prev_rate) / maxf(delta, 0.0001))
				track["prev_yaw_rate"] = yaw_speed
				# B3 — écart regard / cap de déplacement (`wish_dir`), seulement
				# quand le bot a une intention de mouvement mesurable.
				var wish: Vector3 = p.get("wish_dir")
				if wish != null and Vector2(wish.x, wish.z).length() > 0.05:
					_b3_hors_combat_ticks += 1
					var move_xz := Vector2(wish.x, wish.z).normalized()
					var angle := rad_to_deg(acos(clampf(look_xz.dot(move_xz), -1.0, 1.0)))
					if angle > 25.0:
						_b3_divergence_ticks += 1
			else:
				# B9 — saut du point visé en combat, hors flick d'acquisition
				# (1er tick de l'engagement) et hors grâce de recul.
				var just_acquired := not bool(track.get("prev_in_combat", false))
				var recoil_grace: float = track.get("recoil_grace_until", -INF)
				if not just_acquired and now > recoil_grace and absf(delta_yaw_deg) > 1.5:
					_b9_aim_point_jumps += 1
				# B10 — fenêtre glissante 500 ms de rotation totale (VACnet),
				# consommée par `_on_bot_fired` au moment du tir.
				var rot_window: Array = track.get("rotation_window", [])
				rot_window.append([now, absf(delta_yaw_deg)])
				while not rot_window.is_empty() and now - float(rot_window[0][0]) > SNAP_WINDOW_BEFORE_S:
					rot_window.pop_front()
				track["rotation_window"] = rot_window
		track["prev_look_xz"] = look_xz
		track["prev_look_valid"] = true
	track["prev_in_combat"] = in_combat

	# B5 — vitesse au moment du tir : mesurée dans `_on_bot_fired` (a besoin
	# de savoir QUAND un tir part) ; ici on ne fait que tenir `speed` à jour
	# pour que ce hook la lise à l'instant T.
	track["speed"] = node.call("horizontal_speed") if node.has_method("horizontal_speed") else 0.0

	# B6 — segments d'esquive (strafe gauche/droite) EN COMBAT seulement.
	if in_combat:
		var strafe_dir := int(brain.get("_strafe_dir"))
		var samples: Array = _b6_dodge_segment_samples.get(bot_id, [])
		samples.append([strafe_dir, delta])
		_b6_dodge_segment_samples[bot_id] = samples
	elif _b6_dodge_segment_samples.has(bot_id):
		_flush_dodge_segments(bot_id)

	# B7 — bascules ADS par engagement.
	var aim_held := bool(node.get("input").aim_held) if node.get("input") != null else false
	if in_combat and not bool(track.get("ads_engagement_active", false)):
		track["ads_engagement_active"] = true
		track["ads_toggle_count"] = 0
		track["ads_toggle_times"] = []
		track["ads_prev_held"] = aim_held
	elif not in_combat and bool(track.get("ads_engagement_active", false)):
		track["ads_engagement_active"] = false
		_b7_ads_engagements += 1
		_b7_ads_toggle_counts.append(int(track.get("ads_toggle_count", 0)))
		var toggle_times: Array = track.get("ads_toggle_times", [])
		if max_simultaneous_events(toggle_times, 1.5) > 1:
			_b7_ads_rapid_violations += 1
	if bool(track.get("ads_engagement_active", false)) and aim_held != bool(track.get("ads_prev_held", aim_held)):
		track["ads_toggle_count"] = int(track.get("ads_toggle_count", 0)) + 1
		var times: Array = track.get("ads_toggle_times", [])
		times.append(now)
		track["ads_toggle_times"] = times
	track["ads_prev_held"] = aim_held

	# B14 — gestes suspects : jump/crouch hors combat, hors déblocage (déjà
	# distingué via BotStuck.Phase — un jump_pressed vrai alors que
	# `_stuck._phase != JUMP` vient forcément de l'AUTRE branche, le tirage
	# aléatoire de BotBrain.gd:518-531, voir constat #2).
	var input_node = node.get("input")
	if input_node != null and not in_combat:
		if bool(input_node.jump_pressed) and stuck_phase != BotStuck.Phase.JUMP:
			_b14_random_jumps += 1
		if bool(input_node.crouch_pressed) and float(track.get("speed", 0.0)) < 1.0:
			_b14_low_speed_crouches += 1


## Un bot encore EN COMBAT (segment d'esquive ouvert) ou en engagement ADS
## quand la phase s'arrête (`_end_phase`, avant que `_begin_phase` ne remette
## `_bot_track`/`_b6_dodge_segment_samples` à zéro) verrait sinon sa dernière
## séquence perdue plutôt que comptée — même esprit que le reste du fichier
## ("jamais une donnée silencieusement jetée").
func _flush_pending_humanity_state() -> void:
	for bot_id in _b6_dodge_segment_samples.keys().duplicate():
		_flush_dodge_segments(bot_id)
	for bot_id in _bot_track:
		var track: Dictionary = _bot_track[bot_id]
		if bool(track.get("ads_engagement_active", false)):
			track["ads_engagement_active"] = false
			_b7_ads_engagements += 1
			_b7_ads_toggle_counts.append(int(track.get("ads_toggle_count", 0)))
			var toggle_times: Array = track.get("ads_toggle_times", [])
			if max_simultaneous_events(toggle_times, 1.5) > 1:
				_b7_ads_rapid_violations += 1


func _flush_dodge_segments(bot_id: int) -> void:
	var samples: Array = _b6_dodge_segment_samples.get(bot_id, [])
	_b6_dodge_segment_samples.erase(bot_id)
	if samples.is_empty():
		return
	for seg in segment_durations(samples):
		var duration := float(seg.duration)
		_b6_dodge_durations.append(duration)
		_b6_dodge_laterals.append(duration * SPRINT_LATERAL_SPEED_APPROX_MS)
		_b6_dodge_total_count += 1
		if int(seg.state) == 0:
			_b6_dodge_stop_count += 1
## Approximation de la vitesse latérale d'esquive (m/s) pour convertir une
## durée de segment en écart latéral (B6) : aucune mesure PROPRE de la
## composante latérale n'est exposée hors de BotCombatStyle (hors périmètre),
## on retient l'allure ADS/marche typique — assez proche pour un seuil
## "observé", à affiner par BOT-27 si besoin.
const SPRINT_LATERAL_SPEED_APPROX_MS := 4.0


func _sample_spacing(living_by_team: Dictionary) -> void:
	for team in living_by_team:
		var positions: Array = living_by_team[team]
		if positions.size() < 2:
			continue
		for i in positions.size():
			var nearest := INF
			for j in positions.size():
				if i == j:
					continue
				nearest = minf(nearest, (positions[i] as Vector3).distance_to(positions[j]))
			_b11_ally_distance_samples.append(nearest)
			_b11_total_count += 1
			if nearest < 3.0:
				_b11_close_count += 1
			if nearest > 30.0:
				_b11_far_count += 1


## LD-27 — un tick de domination des positions fortes (§e) : pour chaque
## position, l'équipe qui y a un bot vivant dans `LD27_STRONG_POSITION_
## HOLD_RADIUS_M` accumule `delta` — SEULE (les deux équipes présentes à la
## fois n'accumulent rien pour personne, ce n'est plus une "tenue"). Le
## dénominateur (`_strong_position_observed_time`) avance une seule fois par
## tick, pas par position, pour rester le même diviseur partout.
func _sample_strong_positions(delta: float, living_by_team: Dictionary) -> void:
	_strong_position_observed_time += delta
	for idx in _strong_positions.size():
		var center: Vector3 = _strong_positions[idx]
		var holding_team := -1
		var contested := false
		for team in living_by_team:
			for pos in living_by_team[team]:
				if (pos as Vector3).distance_to(center) <= LD27_STRONG_POSITION_HOLD_RADIUS_M:
					if holding_team == -1:
						holding_team = int(team)
					elif holding_team != int(team):
						contested = true
					break
		if holding_team != -1 and not contested:
			# Clé String (jamais int) : `_strong_position_hold_time` finit
			# dans `raw` du JSON exporté (`_finish`), voir la même précaution
			# sur `_hp_window_stats`.
			var by_team: Dictionary = _strong_position_hold_time[idx]
			var team_key := str(holding_team)
			by_team[team_key] = float(by_team.get(team_key, 0.0)) + delta
			_strong_position_hold_time[idx] = by_team


func _sample_hardpoint(zone: Area3D, players: Node) -> void:
	var center := zone.global_position
	if _last_hp_zone_pos != Vector3.INF and center.distance_to(_last_hp_zone_pos) > 0.5:
		_hp_rotation_pending = true
		_hp_rotation_time = _phase_elapsed
	_last_hp_zone_pos = center

	var present := {}
	var in_zone_positions: Array = []
	for b in zone.get_overlapping_bodies():
		if b is PlayerController:
			var hp := b.get_node_or_null("Health") as Health
			if hp and hp.is_dead:
				continue
			present[int(b.team)] = true
			in_zone_positions.append((b as Node3D).global_position)

	# LD-27 — occupation de zone par fenêtre de 60 s (§e), N'IMPORTE QUELLE
	# équipe (contrairement à B18 ci-dessous, qui ne regarde QUE les fenêtres
	# tenues par une seule équipe) : voir `_compute_hp_zone_occupancy_min_
	# ratio` pour la lecture des fenêtres partiellement observées.
	var window_key := str(int(_phase_elapsed / LD27_HP_ZONE_WINDOW_S))
	var window_stat: Dictionary = _hp_window_stats.get(window_key, {"occupied": 0, "total": 0, "first_t": _phase_elapsed, "last_t": _phase_elapsed})
	window_stat["total"] = int(window_stat["total"]) + 1
	if not in_zone_positions.is_empty():
		window_stat["occupied"] = int(window_stat["occupied"]) + 1
	window_stat["last_t"] = _phase_elapsed
	_hp_window_stats[window_key] = window_stat

	if present.size() == 1:
		_b18_zone_counts.append(in_zone_positions.size())
		if in_zone_positions.size() >= 2:
			var dists: Array = []
			for i in in_zone_positions.size():
				for j in range(i + 1, in_zone_positions.size()):
					dists.append((in_zone_positions[i] as Vector3).distance_to(in_zone_positions[j]))
			if not dists.is_empty():
				_b18_zone_spacings.append(median(dists))
		var holding_team: int = present.keys()[0]
		var watch_count := 0
		for p in players.get_children():
			if not bool(p.get("is_bot")) or int(p.get("team")) != holding_team:
				continue
			var hp2 := p.get_node_or_null("Health") as Health
			if hp2 and hp2.is_dead:
				continue
			var d := (p as Node3D).global_position.distance_to(center)
			if d >= HP_WATCH_MIN_M and d <= HP_WATCH_MAX_M:
				watch_count += 1
		_b18_watch_counts.append(watch_count)

	if _hp_rotation_pending:
		var arrived := not in_zone_positions.is_empty()
		if arrived:
			_hp_rotation_arrivals.append(true)
			_hp_rotation_pending = false
		elif _phase_elapsed - _hp_rotation_time > HP_ROTATION_ARRIVAL_WINDOW_S:
			_hp_rotation_arrivals.append(false)
			_hp_rotation_pending = false


func _sample_presence(node: Node, health: Health) -> void:
	if _presence_bounds.is_empty():
		return
	if health != null and health.is_dead:
		return
	var pos := (node as Node3D).global_position
	var mn: Vector2 = _presence_bounds["min"]
	var col := clampi(int(floor((pos.x - mn.x) / _presence_cell)), 0, _presence_grid_w - 1)
	var row := clampi(int(floor((pos.z - mn.y) / _presence_cell)), 0, _presence_grid_h - 1)
	var team := int(node.get("team"))
	if team == 1:
		_presence_team1[row][col] = int(_presence_team1[row][col]) + 1
	else:
		_presence_team0[row][col] = int(_presence_team0[row][col]) + 1


## Nettoyage du prototype 2026-09-26 : SnD (`SnDMode`) a été supprimé — cette
## fonction n'est plus jamais appelée (`_phase_kind == "snd"` ne se produit
## plus, voir l'appelant) mais reste PARSABLE : `SnDMode.BombState.PLANTED`/
## `DEFUSED` recopiés en dur (2/3, ex-`enum BombState { CARRIED, DROPPED,
## PLANTED, DEFUSED, EXPLODED }`) plutôt que de garder une dépendance à une
## classe qui n'existe plus.
func _poll_bomb_state() -> void:
	const BOMB_STATE_PLANTED := 2
	const BOMB_STATE_DEFUSED := 3
	var state := int(_mode.get("bomb_state"))
	if state != _last_bomb_state:
		if state == BOMB_STATE_PLANTED:
			_snd_planted += 1
		elif state == BOMB_STATE_DEFUSED:
			_snd_defused += 1
		_last_bomb_state = state


# ======================================================================
#  BOT-20 — changement de but avec détection de navette (voir doc de tête
#  et la constante GOAL_JUMP_THRESHOLD_M/SHUTTLE_WINDOW_S).
# ======================================================================
func _register_goal_change(bot_id: int, team: int, pos: Vector3, now: float) -> void:
	var times: Array = _b12_goal_change_times_by_team.get(team, [])
	times.append(now)
	_b12_goal_change_times_by_team[team] = times

	var hist: Array = _goal_change_history.get(bot_id, [])
	if hist.size() >= 2:
		var two_back: Dictionary = hist[hist.size() - 2]
		if pos.distance_to(two_back.pos) <= GOAL_JUMP_THRESHOLD_M and now - float(two_back.time) <= SHUTTLE_WINDOW_S:
			# Navette A→B→A bouclée : compte à part, ANNULE le comptage de la
			# jambe A→B (sinon la paire vaudrait deux "vrais" changements).
			_shuttle_events += 1
			_goal_changes = maxi(0, _goal_changes - 1)
			hist.append({"pos": pos, "time": now})
			if hist.size() > 3:
				hist.pop_front()
			_goal_change_history[bot_id] = hist
			return
	_goal_changes += 1
	# LD-27 — part des traversées par lane (§e) : SEUL un changement de but
	# réel (jamais une navette, déjà exclue par le `return` ci-dessus) compte,
	# et seulement pour la phase tdm_veteran (§e les groupe ensemble) sur une
	# carte qui déclare des lanes (`_lane_points` vide sur cargo_ship).
	if _phase_key == "tdm_veteran" and not _lane_points.is_empty():
		var lane_key := lane_for_goal(pos, _lane_points, _hotspots)
		if lane_key != "":
			_lane_crossing_counts[lane_key] = int(_lane_crossing_counts.get(lane_key, 0)) + 1
	hist.append({"pos": pos, "time": now})
	if hist.size() > 3:
		hist.pop_front()
	_goal_change_history[bot_id] = hist


# ======================================================================
#  Signaux par bot — accrochés dès la PREMIÈRE fois où `_sample_tick` (déjà
#  appelé à chaque tick physique, voir plus haut) observe un bot donné,
#  jamais via `PlayerSpawner.spawned` : ce signal de réplication ne s'émet
#  QUE vers un pair distant RÉEL qui reçoit le spawn (aucun ici — hôte et
#  bots sont tous simulés SUR ce même process, sans second pair connecté),
#  il ne se déclenche donc jamais dans ce banc solo (constaté en pratique :
#  `spawner.spawned` connecté avec succès mais jamais émis). `_hooked_bot_ids`
#  (remis à zéro à chaque phase, voir `_begin_phase`) évite un double
#  branchement si `_sample_tick` revoit le même bot au tick suivant. L'hôte
#  (is_bot == false) n'est jamais un combattant réel (immobile, sans entrée
#  en headless, voir doc de tête) : jamais hooké, jamais compté.
# ======================================================================
func _hook_bot(node: Node, brain: Node) -> void:
	var bot_id := str(node.name).to_int()
	var team := int(node.get("team"))
	_team_by_bot_id[bot_id] = team
	_bot_track[bot_id] = {
		"spawn_pos": (node as Node3D).global_position,
		"life_clock": 0.0,
		"first_contact_recorded": false,  # LD-27 — voir `_sample_acquisition_and_hearing`.
	}
	var weapon := node.get_node_or_null("Weapon")
	if weapon:
		weapon.fired.connect(_on_bot_fired.bind(node, brain, bot_id))
		weapon.hit_confirmed.connect(_on_bot_hit_confirmed.bind(node, brain, bot_id))
	var abilities := node.get_node_or_null("Abilities")
	if abilities and abilities.has_signal("ability_used"):
		abilities.ability_used.connect(_on_bot_ability_used)
	var health := node.get_node_or_null("Health") as Health
	if health:
		_bot_track[bot_id]["health"] = health
		health.damaged.connect(_on_bot_damaged.bind(bot_id))
		health.died.connect(_on_bot_died.bind(bot_id, team))
		health.respawned.connect(_on_bot_respawned.bind(node, bot_id))


func _on_bot_respawned(node: Node, bot_id: int) -> void:
	var track: Dictionary = _bot_track.get(bot_id, {})
	track["life_clock"] = 0.0
	track["spawn_pos"] = (node as Node3D).global_position
	track["first_contact_recorded"] = false  # LD-27 — "premier contact" est mesuré par VIE.
	_bot_track[bot_id] = track


## L'équipe de l'attaquant est résolue MAINTENANT (pendant la phase en cours,
## où `_team_by_bot_id` est à jour), jamais relue plus tard dans
## `_compute_trade_ratio` — `_team_by_bot_id` est remis à zéro à chaque
## `_begin_phase` et ne refléterait alors que la DERNIÈRE phase du banc.
func _on_bot_damaged(_amount: float, attacker_id: int, target_id: int) -> void:
	var attacker_team: int = _team_by_bot_id.get(int(attacker_id), -1)
	_damage_log.append({
		"time": _phase_elapsed, "phase_index": _phase_index,
		"attacker_id": attacker_id, "attacker_team": attacker_team, "target_id": target_id,
	})


func _on_bot_died(killer_id: int, victim_id: int, victim_team: int) -> void:
	# LD-27 — âge de la vie de la victime (s depuis son dernier spawn), pour
	# `early_death_ratio` (`_compute_early_death_ratio`, dérivé post-hoc de ce
	# journal — même discipline que `_compute_trade_ratio`) : NO_DATA (-1.0)
	# si `life_clock` n'a jamais été tenu à jour pour cette vie (hors phase
	# Vétéran, voir `_sample_humanity`), jamais confondu avec "0 s".
	var victim_life_clock: float = float(_bot_track.get(victim_id, {}).get("life_clock", NO_DATA))
	_deaths_log.append({
		"time": _phase_elapsed, "phase_index": _phase_index, "killer_id": killer_id,
		"victim_id": victim_id, "victim_team": victim_team, "victim_life_clock_s": victim_life_clock,
	})


## Dénominateur de la précision : un tir PARTI, bandé sur la distance
## tireur -> cible VISÉE à cet instant (BotBrain._target_pos, réflexion —
## voir la docstring de tête). `_target_id == -1` ne devrait jamais arriver
## ici (BotBrain ne met `fire_pressed` à vrai que dans la branche opposée,
## voir _tick_combat) mais reste ignoré par prudence plutôt que de fausser
## une bande avec une distance sans cible. BOT-20 : alimente aussi B4 (TTFS),
## B5 (tir en mouvement), B8 (cadence semi-auto) et B10 (snap puis tir).
func _on_bot_fired(_cfg: WeaponConfig, node: Node, brain: Node, bot_id: int) -> void:
	if brain == null:
		return
	var target_id := int(brain.get("_target_id"))
	if target_id == -1:
		return
	var target_pos: Vector3 = brain.get("_target_pos")
	var shooter_pos: Vector3 = (node as Node3D).global_position
	_bump(_shots_by_band, _phase_difficulty_key, distance_band(shooter_pos.distance_to(target_pos)))
	if _phase_difficulty_key != "veteran":
		return
	var track: Dictionary = _bot_track.get(bot_id, {})
	var speed := float(track.get("speed", 0.0))
	_b5_shots_total_veteran += 1
	if speed > 1.0:
		_b5_shots_moving += 1
	if speed > 6.5:
		_b5_fast_moving_shots += 1
	track["recoil_grace_until"] = _phase_elapsed + RECOIL_GRACE_S

	# B4 — TTFS : premier tir depuis l'acquisition en cours (voir la remise à
	# zéro dans `_sample_humanity`/transition de combat — ici on consomme le
	# "pending" posé à l'acquisition).
	var acq_time: float = track.get("ttfs_pending_since", -1.0)
	if acq_time >= 0.0:
		var arr: Array = _b4_ttfs_by_diff.get(_phase_difficulty_key, [])
		arr.append(_phase_elapsed - acq_time)
		_b4_ttfs_by_diff[_phase_difficulty_key] = arr
		track["ttfs_pending_since"] = -1.0

	# B8 — cadence semi-auto (arme NON automatique uniquement).
	var weapon_node := node.get_node_or_null("Weapon")
	var cfg: WeaponConfig = weapon_node.cfg() if weapon_node else null
	if cfg != null and not cfg.automatic:
		var last_fire: float = track.get("semi_auto_last_fire", -1.0)
		if last_fire >= 0.0:
			_b8_semi_auto_intervals.append(_phase_elapsed - last_fire)
			_b8_semi_auto_total += 1
			var expected := 1.0 / maxf(cfg.fire_rate, 0.01)
			if absf((_phase_elapsed - last_fire) - expected) <= 0.01:
				_b8_semi_auto_at_max_rate += 1
		track["semi_auto_last_fire"] = _phase_elapsed

	# B10 — snap puis tir (fenêtre 500 ms / 50 ms de rotation accumulée).
	var rot_window: Array = track.get("rotation_window", [])
	var total_500 := 0.0
	var total_50 := 0.0
	for w in rot_window:
		var age := _phase_elapsed - float(w[0])
		if age <= SNAP_WINDOW_BEFORE_S:
			total_500 += float(w[1])
		if age <= SNAP_WINDOW_RECENT_S:
			total_50 += float(w[1])
	if total_500 >= SNAP_MIN_ROTATION_DEG:
		_b10_shots_with_rotation_data += 1
		if is_snap_then_fire(total_50, total_500):
			_b10_snap_shots += 1
	_bot_track[bot_id] = track


## Numérateur : un tir CONFIRMÉ touché, bandé sur la distance tireur ->
## point d'impact réel (`pos`, voir Weapon._spawn_damage_number). Un kill
## alimente aussi le TTK effectif (BotBrain._tracking_time à cet instant).
func _on_bot_hit_confirmed(pos: Vector3, _dmg: float, _headshot: bool, is_kill: bool, node: Node, brain: Node, bot_id: int) -> void:
	var shooter_pos: Vector3 = (node as Node3D).global_position
	_bump(_hits_by_band, _phase_difficulty_key, distance_band(shooter_pos.distance_to(pos)))
	if is_kill and brain != null:
		_ttk_samples.append(float(brain.get("_tracking_time")))
	if _phase_difficulty_key == "veteran":
		var track: Dictionary = _bot_track.get(bot_id, {})
		if float(track.get("speed", 0.0)) > 1.0:
			_b5_hits_moving += 1
		_bot_track[bot_id] = track


func _on_bot_ability_used(_slot: String, _ability_name: String) -> void:
	_ability_events += 1


func _bump(by_difficulty: Dictionary, diff_key: String, band: String) -> void:
	if not by_difficulty.has(diff_key):
		by_difficulty[diff_key] = {}
	var bands: Dictionary = by_difficulty[diff_key]
	bands[band] = int(bands.get(band, 0)) + 1


# ======================================================================
#  BOT-20 — acquisition de cible (B4 TTFS) et audition (B20) : détectées au
#  moment où `_target_id`/`_heard_until` changent, via `_sample_tick` (les
#  signaux `fired`/`hit_confirmed` ne couvrent pas ces instants).
# ======================================================================
func _sample_acquisition_and_hearing(brain: Node, bot_id: int) -> void:
	var track: Dictionary = _bot_track.get(bot_id, {})
	var target_id := int(brain.get("_target_id"))
	var prev_target: int = track.get("prev_target_id", -1)
	if prev_target == -1 and target_id != -1:
		track["ttfs_pending_since"] = _phase_elapsed
		# LD-27 — "premier contact" (§e) : délai spawn -> première acquisition
		# de cible, UNE fois par vie (phase tdm_veteran seule, voir docstring
		# de tête). `life_clock` n'est tenu à jour que par `_sample_humanity`
		# (phase Vétéran), donc toujours valide ici puisque tdm_veteran l'est.
		if _phase_key == "tdm_veteran" and not bool(track.get("first_contact_recorded", false)):
			_first_contact_samples.append(float(track.get("life_clock", 0.0)))
			track["first_contact_recorded"] = true
	track["prev_target_id"] = target_id

	if _phase_difficulty_key == "veteran":
		var heard_until := float(brain.get("_heard_until"))
		var prev_heard_until: float = track.get("prev_heard_until", -INF)
		if heard_until > prev_heard_until:
			var heard_pos: Vector3 = brain.get("_heard_pos")
			var real: Variant = _closest_recent_shot(heard_pos)
			if real != null:
				_b20_hearing_errors.append(heard_pos.distance_to(real))
		track["prev_heard_until"] = heard_until
	_bot_track[bot_id] = track


## Corrèle un point d'audition (`BotBrain._heard_pos`) avec le tir RÉEL qui
## l'a produit (`Weapon.recent_gunfire`, même horloge murale que `_heard_
## until` — voir doc de tête) : le plus proche dans une fenêtre RÉCENTE et
## proche (aujourd'hui identique par construction, tant que BOT-29 n'ajoute
## pas de bruit de localisation — voir `check_observed_thresholds` B20).
func _closest_recent_shot(heard_pos: Vector3) -> Variant:
	var now := Time.get_ticks_msec() / 1000.0
	var best: Variant = null
	var best_d := HEARING_CORRELATION_RADIUS_M
	for shot in Weapon.recent_gunfire:
		if now - float(shot.time) > HEARING_CORRELATION_WINDOW_S:
			continue
		var d: float = heard_pos.distance_to(shot.pos)
		if d < best_d:
			best_d = d
			best = shot.pos
	return best


# ======================================================================
#  BOT-20 — grille de présence 2 m (B19), format tools/heatmap.gd (voir la
#  doc de tête pour la limite assumée sur les légendes "kills"/"morts").
# ======================================================================
func _setup_presence_grid() -> void:
	_presence_bounds = _bounds_for_map(_map_id)
	if _presence_bounds.is_empty():
		return
	var mn: Vector2 = _presence_bounds["min"]
	var mx: Vector2 = _presence_bounds["max"]
	_presence_grid_w = maxi(1, int(ceil((mx.x - mn.x) / _presence_cell)))
	_presence_grid_h = maxi(1, int(ceil((mx.y - mn.y) / _presence_cell)))
	_presence_team0 = _zero_grid(_presence_grid_w, _presence_grid_h)
	_presence_team1 = _zero_grid(_presence_grid_w, _presence_grid_h)


func _zero_grid(w: int, h: int) -> Array:
	var grid: Array = []
	for _r in h:
		var row: Array = []
		row.resize(w)
		row.fill(0)
		grid.append(row)
	return grid


## Bounds réels de la map. Nettoyage du prototype 2026-09-26 : les six cartes
## "dessinées à la main" (`Layouts.gd`) et Cargo Ship ont été supprimées avec
## leurs scènes — Wasteland est désormais la seule carte.
func _bounds_for_map(map_id: String) -> Dictionary:
	var data: Dictionary = WastelandLayout.data() if map_id == "wasteland" else {}
	if not data.has("bounds"):
		return {}
	return data["bounds"]


## LD-27 — charge `lanes`/`hotspots`/`strong_positions` UNE fois (`_initialize`),
## seulement pour `--map=wasteland` (vide ailleurs, chaque métrique LD-27
## retombe alors sur NO_DATA). Fusion DUPLIQUÉE ici plutôt que réutilisée
## depuis `MapSetup._assemble_wasteland` (hors de mon périmètre, même
## convention que `_bounds_for_map` ci-dessus vis-à-vis de `Layouts.gd`) :
## `WastelandLayout`/`WastelandMarkers`/`WastelandBots` sont des classes PURES
## (Dictionary/Vector3, aucun nœud), sans risque à relire directement.
func _load_wasteland_bot_data() -> void:
	if _map_id != "wasteland":
		return
	var lanes: Dictionary = WastelandBots.data().get("lanes", {})
	for lane_key in lanes.keys():
		_lane_points[lane_key] = lanes[lane_key]
		_lane_crossing_counts[lane_key] = 0
	_hotspots = WastelandBots.data().get("hotspots", [])
	for pos in WastelandMarkers.data().get("strong_positions", []):
		_strong_positions.append(pos)
		_strong_position_hold_time.append({})


func _write_presence_grid() -> void:
	if _presence_bounds.is_empty():
		push_warning("bot_bench: bounds introuvables pour --map=%s, grille de présence non écrite" % _map_id)
		return
	var mn: Vector2 = _presence_bounds["min"]
	var mx: Vector2 = _presence_bounds["max"]
	var team0_count := 0
	var team1_count := 0
	for row in _presence_team0:
		for c in row:
			team0_count += int(c)
	for row in _presence_team1:
		for c in row:
			team1_count += int(c)
	var payload := {
		"map_id": _map_id,
		"match_id": "bot_bench",
		"cell_size": _presence_cell,
		"bounds": {"min": [mn.x, mn.y], "max": [mx.x, mx.y]},
		"grid_w": _presence_grid_w,
		"grid_h": _presence_grid_h,
		# Réutilise EXACTEMENT le schéma de tools/heatmap.gd pour rester
		# rendable par tools/heatmap_render.py sans le modifier : "kills" =
		# présence équipe 0, "morts" = présence équipe 1 (voir doc de tête).
		"kills": _presence_team0,
		"deaths": _presence_team1,
		"kill_count": team0_count,
		"death_count": team1_count,
		"event_count": team0_count + team1_count,
	}
	_write_json(_presence_out_path, payload)
	print("BOT_BENCH_PRESENCE_GRID %s" % [ProjectSettings.globalize_path(_presence_out_path)])
