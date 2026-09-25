# Tests (gdUnit4) & intégration continue

Ce document explique comment lancer les tests en local et ce que fait la CI.

---

## 1. Lancer les tests en local

Prérequis : **Godot 4.7** installé (ex. `Godot_v4.7-stable_win64.exe`) et le
plugin **gdUnit4** présent dans `addons/gdUnit4/` (déjà dans le repo).

```bash
GODOT_BIN=/c/Users/srko/Desktop/Godot_v4.7-stable_win64.exe tools/test.sh
```

- `GODOT_BIN` doit pointer vers l'exécutable Godot 4.7 (headless ou non, peu
  importe : le script ajoute `--headless` lui-même). Le script s'arrête avec
  une erreur explicite si `GODOT_BIN` n'est pas défini.
- Par défaut la suite lancée est `res://tests` (tout `tests/`).

### Lancer une seule suite

Passe le chemin `res://` de la suite (fichier ou dossier) en premier argument :

```bash
GODOT_BIN=/c/Users/srko/Desktop/Godot_v4.7-stable_win64.exe \
  tools/test.sh res://tests/smoke/test_smoke.gd
```

```bash
# tout un sous-dossier
GODOT_BIN=/c/Users/srko/Desktop/Godot_v4.7-stable_win64.exe \
  tools/test.sh res://tests/combat
```

### Où atterrissent les rapports

Chaque exécution crée un nouveau dossier `reports/report_<n>/` (HTML +
`results.xml` au format JUnit). Ce dossier est ignoré par git
(`.gitignore` → `reports/`).

### Codes de sortie

| Code | Sens | Bloquant ? |
|------|------|------------|
| `0`  | tous les tests passent | non |
| `100`| au moins un test a échoué | **oui** |
| `101`| avertissements seulement (pas d'échec) | non |

---

## 2. Ce que fait la CI (`.github/workflows/ci.yml`)

Déclenchée sur `push` et `pull_request`.

1. **`tests`** (Ubuntu, image `barichello/godot-ci:4.7`) :
   - importe le projet (`godot --headless --path . --import`) ;
   - lance `GODOT_BIN=godot tools/test.sh` ;
   - le job échoue si le code de sortie n'est ni `0` ni `101` (donc surtout
     sur `100` = échecs réels) ;
   - `reports/` est toujours uploadé comme artefact du job, même en cas
     d'échec ;
   - les résultats JUnit (`reports/report_*/results.xml`) sont publiés via
     `mikepenz/action-junit-report`.
2. **`export`** (dépend de `tests`) : exporte les trois presets
   (`Windows Desktop`, `Linux`, `Linux Server`) avec les modèles d'export de
   la **même version Godot 4.7**, puis uploade `build/` en artefact. L'export
   serveur dédié (`build/server/fps_server.x86_64`) est ce que consommera la
   future image Docker (Phase 1).

La CI exécute la même version de Godot que celle utilisée en local
(`4.7-stable`) pour éviter tout écart de comportement entre les tests et
l'export.

---

## 3. Le framework de test n'est pas exporté

`export_presets.cfg` exclut explicitement du build joueur/serveur tout ce qui
ne sert qu'au développement :
`addons/gdUnit4/*`, `tests/*`, `tools/*`, `reports/*`, `docs/*`,
`.orchestrator/*` (filtre `exclude_filter`, un par preset). Le plugin gdUnit4
ne fait donc partie que du projet source, jamais d'un `.exe` / build serveur
livré.

---

## 4. Banc de mesure des bots (`bot_bench`, headless)

`tools/bot_bench.gd` (BOT-13, docs/research/02_bots_ai.md #18 : « Pas de banc
de mesure. Aucune métrique automatique... les régressions de comportement ne
sont visibles qu'en playtest ») héberge, dans un seul process headless, une
partie bot-vs-bot TDM 4v4 à chaque difficulté (Recrue/Vétéran/Élite), une
partie Hardpoint 4v4 à Vétéran (`hp_veteran`, BOT-20) puis une série de
manches SnD à Vétéran, et exporte en JSON des métriques de comportement
comparées à des seuils de régression documentés — BLOQUANTS pour les
métriques BOT-13, OBSERVÉS (avertissement) pour les métriques d'« humanité »
B1-B20 ajoutées par BOT-20 (docs/research/08_bots_humanlike.md), le temps que
BOT-21 à BOT-29 comblent les écarts qu'elles révèlent.

### Lancer le banc

```bash
GODOT_BIN=/c/Users/srko/Desktop/Godot_v4.7-stable_win64.exe
"$GODOT_BIN" --headless --path . -s res://tools/bot_bench.gd -- \
    --tdm-duration=180 --snd-rounds=10 --map=wasteland --time-scale=1.0 \
    --out=reports/bot_bench/latest.json
```

- `--tdm-duration` : secondes **simulées** par phase TDM/Hardpoint (défaut
  180 s ; compte le temps de l'écran de sélection d'agent, ~15 s, avant que
  l'hôte — jamais un vrai combattant, voir plus bas — ne déclenche le
  remplissage par des bots).
- `--snd-rounds` : nombre de manches SnD jouées (défaut 10) — `rounds_to_win`
  est relevé à l'infini le temps de la phase pour ne JAMAIS couper la série
  avant ce nombre de manches sur un score déséquilibré.
- `--map` : identifiant `MapCatalog` — **`wasteland` par défaut depuis BOT-20**
  (l'ancien défaut, `cargo_ship`, ne fait pas apparaître les défauts
  diagnostiqués sur Wasteland, docs/research/08_bots_humanlike.md constat
  #12 : « le banc tourne sur cargo_ship par défaut »). `--map=cargo_ship`
  reste disponible pour comparer.
- `--time-scale` : accélère la simulation (`Engine.time_scale`) — un
  `--tdm-duration=180` à `--time-scale=6` tourne en ~30 s réelles ; le
  chronomètre du mode et l'écran de sélection d'agent (15 s) sont accélérés de
  la MÊME façon (delta scalé par le moteur pour tout le process). Les
  métriques BOT-20 ont leur PROPRE horloge (`_phase_elapsed`, secondes
  SIMULÉES) — indépendante de `--time-scale` — sauf B20 (précision de l'ouïe),
  qui corrèle avec `Weapon.recent_gunfire` sur l'horloge MURALE du jeu
  (`Time.get_ticks_msec()`, comme `BotBrain._heard_until`) : un `--time-scale`
  élevé peut donc fausser spécifiquement B20 (à éviter pour cette métrique).
- `--phases` : sous-ensemble parmi
  `tdm_recrue,tdm_veteran,tdm_elite,hp_veteran,snd_veteran` (défaut : les 5),
  séparés par des virgules — utile pour un dev-loop rapide sur une seule
  phase (`--phases=hp_veteran`).
- `--out` : chemin du JSON exporté (défaut `reports/bot_bench/latest.json`,
  sous `reports/` donc ignoré par git comme les autres rapports).
- `--presence-cell` : taille de cellule (m) de la grille de présence B19
  (défaut `2.0`, le critère d'acceptation BOT-20).
- `--presence-out` : chemin du JSON de la grille de présence (défaut :
  `presence_grid.json` à côté de `--out`).

**Limite connue — `--time-scale` élevé + SnD.** Au-delà de `--time-scale=10`,
dès qu'une manche SnD va à son terme, une cascade d'erreurs Jolt Physics
("Vector3 cannot be normalized", "body_test_motion was passed an invalid
transform", "... nan ...") apparaît sur un ou plusieurs bots et ne se résorbe
plus (le process n'affiche alors jamais `BOT_BENCH_RESULT`). Isolé : ce n'est
PAS un effet de l'enchaînement de phases de `bot_bench.gd` (`_begin_phase`/
`_end_phase`) — la même cascade apparaît avec `--phases=snd_veteran
--snd-rounds=1` seul (aucune transition, aucun second monde, un fonctionnement
en tout point identique à un run `tools/bot_smoke.gd --mode=snd`), et
disparaît avec les MÊMES arguments à `--time-scale=10`. `tools/bot_smoke.gd
--mode=snd --time-scale=15` ne suffit PAS à l'exclure : à `--duration=40` il
affiche `kills=0` (aucune manche menée à son terme), donc n'exerce jamais le
chemin de code qui casse — il faut une `--duration` assez longue pour qu'une
manche SnD complète se joue. La cause réelle est donc dans la logique de
manche SnD / le mouvement joueur sous un `Engine.time_scale` élevé (traces :
`scripts/player/PlayerController.gd` `_physics_process`/`move_and_slide`/
`_publish_net_snapshot` lisant/écrivant un `global_transform` déjà NaN,
`scripts/ai/BotBrain.gd` le propageant), hors du périmètre de
`tools/bot_bench.gd` — un run `--time-scale` élevé enchaînant une manche SnD
complète reste donc à éviter tant que ce point n'est pas corrigé ailleurs.

Affiche `BOT_BENCH_RESULT ok=<bool> failures=<n>` puis quitte `0` (tous les
seuils respectés, ou pas assez de données pour juger — jamais confondu avec
un échec, voir `NO_DATA` dans `tools/bot_bench.gd`) ou `1` (au moins un seuil
dépassé, imprimé en `BOT_BENCH_FAILURE <libellé>`).

### Métriques exportées (`metrics` du JSON)

| Champ | Sens | Seuil documenté |
|---|---|---|
| `stuck_time_ratio` | Fraction des ticks physiques bot en séquence de déblocage (BotStuck WIGGLE/JUMP/REQUEST_REPATH) | `< 0.02` (2 %) |
| `goal_changes_per_min` | Changements d'objectif de PATROUILLE/mémoire d'ennemi par bot et par minute (ignore le suivi d'une cible de combat vivante, qui bouge sans qu'aucun objectif n'ait changé) | `<= 8` |
| `accuracy.<difficulté>.<bande>` | Précision RÉELLE (tirs -> touches confirmées) par bande de distance (`5m`/`20m`/`40m`, sous 12,5 m / 12,5-30 m / 30 m+) et par difficulté | voir `ACCURACY_RANGES` — ex. contrat BOT-13 : Vétéran/20 m entre 0,25 et 0,45 |
| `ttk_median_s` | TTK effectif médian (durée de suivi d'une cible jusqu'au kill, pas le TTK théorique d'arme de `docs/BALANCE.md`) | `[0.1 s, 8 s]` |
| `ability_uses_per_min` | Capacités utilisées par bot et par minute | `<= 8` |
| `plant_rate` / `defuse_rate` | Fraction des manches SnD avec une pose / un désamorçage | pose `[0.15, 1.0]`, désamorçage `[0.0, 0.85]` |
| `rounds_played` | Nombre de manches SnD réellement jouées | — |

Une bande/valeur sans assez d'échantillons vaut `-1.0` (sentinelle "pas assez
de données") et n'est **jamais** traitée comme une régression par
`check_thresholds()` — seule une valeur mesurée réellement hors fourchette
compte comme un échec. Le JSON garde aussi les compteurs bruts (`raw`, tirs/
touches par bande, échantillons de TTK, changements de but VS navettes...)
pour l'investigation d'une régression.

**Un changement de but compte dès 0,5 m** (au lieu de 5 m avant BOT-20) —
l'ancien seuil rendait invisible la navette de 2 m entre spawns TDM Wasteland
(constat #12 du research, « angle mort à 5 m »). Un aller-retour A→B→A qui
boucle en moins de 10 s est une **navette** : détecté et compté à part
(`raw.shuttle_events`), jamais comme deux « vrais » changements de but dans
`goal_changes_per_min`.

### Métriques « humanité » B1-B20 (BOT-20, `metrics.humanity`)

`docs/research/08_bots_humanlike.md` §4 chiffre 21 métriques (B1-B21) sur la
capacité des bots à se comporter comme des joueurs (regard, rythme,
déplacement, placement, synchronisation). `tools/bot_bench.gd` en exporte
B1-B15, B17, B18 et B20 sous `metrics.humanity` (B16 et B19-en-partie sont
hors périmètre BOT-20 — voir plus bas ; B21 est un test perceptif humain,
hors CI par nature). **Mesurées uniquement sur les phases Vétéran**
(`tdm_veteran`, `hp_veteran`, `snd_veteran` — le research donne ses seuils
« pour le Vétéran »), sauf B4 (TTFS) qui reste ventilée par difficulté comme
la précision BOT-13.

| # | Champ(s) | Sens | Seuil observé (Vétéran) |
|---|---|---|---|
| B1 | `b1_yaw_speed_p99_deg_s`, `b1_yaw_snap_violations` | p99 de la vitesse de lacet hors combat ; nombre de rotations > 45° en moins de 60 ms | `<= 360°/s` ; `0` |
| B2 | `b2_yaw_accel_p99_deg_s2` | p99 de l'accélération angulaire (inclut recul/étourdissement — non isolés, voir limite ci-dessous) | `<= 5000°/s²` |
| B3 | `b3_look_move_divergence_ratio`, `b3_pitch_stddev_deg` | Part du temps hors combat où \|lacet − cap de déplacement (`wish_dir`)\| > 25° ; écart-type du tangage | `[0.20, 0.60]` ; `>= 3°` |
| B4 | `b4_ttfs_median_s`/`b4_ttfs_cv`/`b4_ttfs_p5_s` (par difficulté) | Temps avant le 1er tir depuis l'acquisition d'une cible | médiane R `[0.8,1.3]`/V `[0.5,0.8]`/É `[0.35,0.55]` ; CV `>= 0.2` ; p5 `>= 0.18 s` |
| B5 | `b5_shots_moving_ratio`, `b5_moving_accuracy_ratio`, `b5_fast_moving_shots_ratio` | Part des tirs à plus de 1 m/s ; précision de ces tirs ; part des tirs à plus de 6,5 m/s | `[0.40, 0.80]` ; `<= 0.15` ; `<= 0.05` |
| B6 | `b6_dodge_segment_median_s`/`_max_s`, `b6_dodge_lateral_p99_m`, `b6_dodge_stop_ratio` | Segments d'esquive (`BotCombatStyle._strafe_dir`) : durée médiane/max, p99 de l'écart latéral (approximé, voir constante `SPRINT_LATERAL_SPEED_APPROX_MS`), part d'un état ARRÊT (0 tant que BOT-27 n'ajoute pas ce 3e état) | médiane `[0.3,0.8]` ; max `<= 1.5 s` ; `<= 3.5 m` ; `[0.15,0.35]` |
| B7 | `b7_ads_toggles_p99`, `b7_ads_rapid_toggle_ratio` | p99 des bascules ADS par engagement ; part des engagements avec plus d'1 bascule/1,5 s | `<= 2` ; `0` |
| B8 | `b8_semi_auto_interval_cv`, `b8_semi_auto_max_rate_ratio` | Coefficient de variation de l'intervalle entre appuis semi-auto ; part des tirs à cadence max (±10 ms) | `>= 0.15` ; `<= 0.30` |
| B9 | `b9_aim_point_jumps` | Sauts du point visé > 1,5°/tick en combat, hors flick d'acquisition et grâce de recul (120 ms après un tir) | `0` |
| B10 | `b10_snap_then_fire_ratio` | Fenêtre VACnet (500 ms avant / 50 ms) : part des tirs « snap puis tir » | `<= 5 %` |
| B11 | `b11_ally_distance_median_m`, `b11_close_ally_ratio`, `b11_far_from_all_ratio` | Distance au coéquipier vivant le plus proche (hors 10 premières secondes de vie) : médiane, part `< 3 m`, part `> 30 m` de tous | `[6,15]` ; `<= 0.10` ; `<= 0.25` |
| B12 | `b12_max_simultaneous_goal_changes`, `b12_shuttle_events` | Bots d'une équipe changeant de but dans la même fenêtre de 200 ms (max sur tout le run) ; nombre de navettes A→B→A détectées | `< 3` ; — |
| B13 | `b13_spawn_presence_ratio` | Part du temps (au-delà de 10 s de vie) passée à moins de 10 m du spawn | `<= 5 %` |
| B14 | `b14_random_jumps`, `b14_low_speed_crouches`, `b14_goalless_slides` | Sauts hors combat hors séquence BotStuck ; appuis accroupi sous 1 m/s hors combat ; glissades sans but (**non mesuré**, `-1` : nécessite l'intention interne de BotBrain, illisible de l'extérieur avant BOT-21) | `0` ; `0` ; — |
| B15 | `stuck_time_ratio` (BOT-13) + `b15_stuck_episodes_per_5min`, `b15_wall_contact_ratio` | Temps bloqué (déjà bloquant, inchangé) ; épisodes de blocage par bot/5 min ; contacts latéraux avec un mur (`CharacterBody3D.is_on_wall()`) | `<= 1 %` (bloquant) ; `<= 1` ; `<= 3 %` |
| B17 | `b17_trade_ratio` | Part des morts alliées suivies de dégâts d'un allié sur le tueur en moins de 3 s | `>= 30 %` |
| B18 | `b18_zone_bot_count_median`, `b18_zone_spacing_median_m`, `b18_watch_bot_count_median`, `b18_rotation_arrival_ratio` | Hardpoint (phase `hp_veteran` uniquement), quand une équipe SEULE tient la zone : bots dans la zone (médiane) et leur espacement médian ; bots de la même équipe en surveillance (8-20 m) ; part des rotations de zone avec au moins un bot arrivé en moins de 10 s | `[1,3]` ; `>= 2.5 m` ; `>= 1` ; `>= 50 %` |
| B20 | `b20_hearing_error_median_m` | Distance entre le point d'enquête (`BotBrain._heard_pos`) et le tir réel corrélé (`Weapon.recent_gunfire`) | `[2,6]`, **jamais 0** |

**Limites assumées (documentées dans `tools/bot_bench.gd`, jamais cachées) :**
- B2/B9 n'isolent pas proprement le recul (seule une fenêtre de grâce de
  120 ms après un tir est exclue) — un pic occasionnel peut donc venir du
  recul plutôt que d'un vrai saut de visée.
- B6 (écart latéral) est une **approximation** (vitesse latérale constante
  supposée) : aucune mesure propre de la composante latérale n'est exposée
  hors de `BotCombatStyle` (hors périmètre BOT-20).
- B14 (glissades sans but) n'est **pas mesuré** : nécessite l'intention du
  but de `BotBrain` (M1, « glissade... vers un but à plus de 8 m »),
  illisible de l'extérieur.
- **B20 vaut aujourd'hui exactement 0** (l'ouïe n'est pas encore bruitée,
  `BotBrain._heard_pos` == la position réelle du tir) : c'est le défaut
  documenté que BOT-29 doit corriger (P1, bruit `σ = 0,15 × distance`) —
  `check_observed_thresholds` le signale explicitement plutôt que de le
  masquer derrière la sentinelle "pas de données".

### Grille de présence (B19, `--presence-out`)

BOT-20 exporte une grille de présence 2 m (`--presence-cell`), pendant les
phases `tdm_veteran`/`hp_veteran` uniquement, au **même format JSON** que
`tools/heatmap.gd` (`map_id`/`cell_size`/`bounds`/`grid_w`/`grid_h`/`kills`/
`deaths`) — pour rester directement rendable par `tools/heatmap_render.py`
**sans le modifier** (hors de mon périmètre de fichiers, propriété LD-08) :

```bash
python tools/heatmap_render.py reports/bot_bench/presence_grid.json
```

Produit 3 PNG : `wasteland_kills.png` (présence équipe 0), `wasteland_deaths.png`
(présence équipe 1) et `wasteland_diff.png` (équipe 0 moins équipe 1, une
carte de contrôle territorial). **Limite assumée** : les légendes du rendu
restent celles de `heatmap_render.py` ("kills"/"morts"/"kills moins morts")
puisqu'il n'est pas modifié ici — à lire comme "présence équipe 0"/"présence
équipe 1"/"différentiel territorial" pour cette grille précise. Vérifié en
image (`SendUserFile`/capture) avant de considérer B19 acquis, comme toute
sortie visuelle du dépôt (voir `docs/STYLE_BIBLE.md`).

### Seuils « observés » vs bloquants

Les métriques BOT-13 (`check_thresholds`) restent **bloquantes** : un échec
fait quitter `bot_bench` avec le code `1` et imprime `BOT_BENCH_FAILURE`.

Les métriques B1-B20 (`check_observed_thresholds`) sont en mode **« observé »**
(avertissement) jusqu'à la fin de BOT-29, imprimées en `BOT_BENCH_OBSERVED`
et listées dans `observed_warnings` du JSON, mais **ne changent jamais**
`failures`/le code de sortie. Une fois BOT-29 terminé, les rendre bloquantes
est un changement d'une ligne dans `tools/bot_bench.gd` (voir la docstring de
`check_observed_thresholds`) : faire renvoyer à `check_thresholds` la
concaténation de son propre résultat et de `check_observed_thresholds(m)`.

### Mesure de départ archivée (BOT-20)

La mesure de référence Wasteland (`tdm_veteran` + `hp_veteran`, 180 s
simulées chacune) sert de repère "avant BOT-21..29" pour juger la
progression des tâches suivantes. Reproduire :

```bash
"$GODOT_BIN" --headless --path . -s res://tools/bot_bench.gd -- \
    --phases=tdm_veteran,hp_veteran --tdm-duration=180 --map=wasteland \
    --out=reports/bot_bench/baseline_2026-09-24.json \
    --presence-out=reports/bot_bench/baseline_2026-09-24_presence.json
```

Le JSON produit (métriques + `observed_warnings` + chemin de la grille de
présence) est le document à archiver comme référence ; `docs/audit/bots.md`
en garde le lien une fois généré.

### Seuils vérifiés en CI

La partie qui héberge réellement une partie (`tools/bot_bench.gd` lancé via
`-s`) n'entre pas dans la suite gdUnit4 rapide (durée d'une partie réelle
incompatible avec la boucle "scopée pendant l'itération" — même convention
que le reste du dépôt, voir tests/agents/test_round_props_cleanup.gd : "aucun
test gdUnit4 du dépôt" n'héberge de vraie partie). Ce que `tools/test.sh`
exécute — et donc ce que la CI (`.github/workflows/ci.yml`) vérifie à chaque
push — est `tests/ai/test_bot_bench_thresholds.gd` : les fonctions PURES de
`tools/bot_bench.gd` (bandes de distance, `ratio`/`median`/`per_minute`,
`percentile`/`p99`, `coefficient_of_variation`, `segment_durations`,
`is_snap_then_fire`, `max_simultaneous_events`, et surtout `check_thresholds()`/
`check_observed_thresholds()` contre des métriques synthétiques couvrant
chaque seuil documenté ci-dessus, y compris l'exemple littéral du contrat
"Vétéran 20 m entre 25 et 45 %"). Lancer `bot_bench` en vrai (commande
ci-dessus) reste une étape MANUELLE (ou une étape CI dédiée à ajouter
séparément, plus lente qu'un test gdUnit4) pour obtenir une mesure réelle et
la comparer aux mêmes seuils.
