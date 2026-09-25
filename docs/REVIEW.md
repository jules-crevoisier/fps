# Review pipeline automatisée

Une seule commande fait tourner tous les checks automatisés du jeu (tests,
sondes de gameplay, fumées réseau/bots, captures d'écran, benchmark de perf,
scan des logs) et produit **un rapport HTML unique**, pensé pour être lu
aussi bien par un humain que par une IA pour juger l'état du jeu.

## Lancer la pipeline

```powershell
# Boucle rapide (tests + sondes + fumées, sans écran ni benchmark) :
powershell -File tools/review/run_review.ps1 -Quick

# Run complet (ajoute captures d'écran + benchmark de perf, fenêtré) :
powershell -File tools/review/run_review.ps1

# Un sous-ensemble d'étapes seulement :
powershell -File tools/review/run_review.ps1 -Only unit_tests,map_shots

# Dossier de sortie explicite :
powershell -File tools/review/run_review.ps1 -Out reports/review/mon_run
```

`GODOT_BIN` (variable d'environnement) surcharge l'exécutable Godot utilisé
(par défaut `C:\Users\srko\Desktop\Godot_v4.7-stable_win64.exe`). Les étapes
fenêtrées (captures, benchmark) ont besoin d'une vraie fenêtre — pas la peine
d'essayer en session totalement headless (RDP sans session graphique, CI sans
Xvfb...), elles échoueront proprement (statut `fail`, jamais un crash de toute
la pipeline) plutôt que de bloquer les autres étapes.

Le rapport atterrit dans `reports/review/<yyyyMMdd-HHmmss>/index.html`
(`-Out` pour choisir un autre dossier). `reports/` est gitignored : chaque run
crée son propre dossier horodaté, rien n'écrase le précédent, et
`report.py` compare automatiquement au run précédent pour lister les
régressions.

## Étapes

| Étape | Ce qu'elle fait | Fenêtré ? | Fait partie de `-Quick` |
|---|---|---|---|
| `import` | `godot --headless --import` (bootstrap, toujours en premier) | non | oui |
| `unit_tests` | Suite gdUnit4 complète (`tools/test.sh`) | non | oui |
| `gameplay_probe` | `tools/review/gameplay_probe.gd` (contrat agent parallèle) | non | oui |
| `net_smoke` | `tools/net_smoke.gd` — 2 process (hôte+client), tir légitime accepté / triche rejetée | non | oui |
| `bot_smoke` | `tools/bot_smoke.gd` — match TDM 4v4 avec bots, 120 s (paramétrable, voir plus bas) | non | oui |
| `map_shots` | `tools/map_shots.gd` — top-down + vues in-game de toutes les maps | oui | non |
| `ui_shots` | `tools/review/ui_shots.gd` (contrat agent parallèle) | oui | non |
| `viewmodel_fp_shots` | `tools/blender/viewmodel_shots.gd` + `tools/fp_shots.gd` — armes en vue 1re personne, sprint, ADS | oui | non |
| `character_shots` | `tools/character_shots.gd` (poses statiques) + `tools/char_ingame_shots.gd` (en match) | oui | non |
| `perf_bench` | `tools/review/perf_bench.gd` — vol de caméra déterministe sur chaque map, 8 s de mesure | oui | non |
| `log_scan` | `tools/review/log_scan.py` — regroupe les lignes d'erreur/avertissement de TOUS les logs | non | oui |
| `report` | `tools/review/report.py` — assemble `index.html` / `summary.json` / `summary.md` | non | oui |

`log_scan` et `report` tournent **toujours** en dernier, même avec `-Only` :
le premier a besoin des logs de toutes les étapes déjà exécutées, le second
doit toujours produire un rapport (c'est la promesse d'« une seule
commande »). `import` tourne toujours en premier pour la même raison
(bootstrap requis par tout ce qui suit).

### Pourquoi `bot_smoke` ne tourne qu'une fois

Le contrat demandait de lancer 2 seeds « si le script le permet ». Lu le
code de `tools/bot_smoke.gd` : il n'accepte aucun argument de graine
(`_initialize` parse `--duration`/`--mode`/`--map`/`--team-size`/
`--time-scale` — voir « `bot_smoke` paramétrable » plus bas — mais aucune
graine aléatoire). Le relancer deux fois donnerait donc deux exécutions
identiques en intention (pas un vrai test de variance), pour +120 s sur un
budget de run complet à tenir sous ~10 min. Une seule exécution honore donc
le contrat tel qu'écrit — l'étape de la pipeline continue de tourner SANS
argument (défauts inchangés : 120 s, mode `tdm`, carte `cargo_ship`, taille
d'équipe du mode, `time_scale` 1.0).

### `bot_smoke` paramétrable (OPS-10)

Hors pipeline (`run_review.ps1` l'invoque toujours sans argument), pour
rejouer un match de bots plus long ou différent — ex. valider un système sur
un vrai match de 10 min (`GameMode.match_time_limit` vaut déjà 600 s par
défaut, scripts/modes/GameMode.gd) plutôt que la coupe à 120 s de la revue
rapide :

```powershell
godot --headless --path . -s res://tools/bot_smoke.gd -- `
    --duration=600 --mode=tdm --map=cargo_ship --team-size=4 [--time-scale=3]
```

- `--duration` (s, défaut 120) : durée du match SIMULÉ avant que le script
  ne conclue et quitte — indépendante de `GameMode.match_time_limit` (le
  mode peut décider un gagnant avant ou pendant une mort subite après ce cap).
- `--mode` : identifiant `MatchConfig.MODES` (`tdm`/`hardpoint`/`snd`/`duel`/
  `duo`) ; un id inconnu retombe silencieusement sur `tdm`
  (`MatchConfig.set_mode`).
- `--map` : identifiant `MapCatalog` (`scripts/levels/maps/MapCatalog.gd`),
  résolu par `MatchConfig.resolve_scene` — exactement la même résolution que
  le serveur en jeu (carte demandée, sinon carte par défaut du mode).
- `--team-size` : par défaut celle du mode (`MatchConfig.team_size_for`),
  l'argument la force explicitement (host + bots jusqu'à ce nombre par
  équipe).
- `--time-scale` (défaut 1.0, remis à 1.0 avant de quitter) : `Engine.time_scale`
  — accélère la simulation pour qu'un match de 600 s n'immobilise pas le
  process 10 minutes réelles ; `--duration` reste un temps SIMULÉ (même delta
  mis à l'échelle que `GameMode.match_elapsed`), donc la valeur choisie ne
  change pas le déroulé du match, seulement le temps réel du process.
  **Plafond pratique ~3** (testé) : au-delà, le lerp par tick physique de
  `PlayerController._update_crouch_height` (`scripts/player/PlayerController.gd`,
  hors périmètre de cette tâche — poids `crouch_lerp_speed * delta` avec
  `crouch_lerp_speed = 16`, voir `MovementConfig.gd`) dépasse 1 et
  extrapole `current_height` en négatif, ce qui fait planter
  `CapsuleShape3D.set_height` à chaque tick (spam `ERROR: CapsuleShape3D
  height cannot be negative`, observé à `--time-scale=25`) — sans rapport
  avec la logique de ce script.

**Télémétrie** : ce script n'écrit pas son propre fichier — `GameWorld.gd`
héberge déjà la télémétrie FUN-05 (`scripts/core/Telemetry.gd`, JSONL
versionné : `match_start`/`spawn`/`kill` (avec `time_since_spawn`)/`match_end`…)
dès qu'un match tourne, y compris ici (`GameWorld._ready` appelle
`Telemetry.start_session()`). La ligne `BOT_SMOKE_START` affiche le chemin
RÉEL du journal (`Telemetry.log_path()` globalisé, ex.
`C:/Users/.../AppData/Roaming/Godot/app_userdata/<projet>/telemetry/session_<horodatage>.jsonl`)
pour qu'un outil aval (ex. `tools/heatmap.gd --in=<chemin>`, LD-08) le
retrouve sans deviner le dossier utilisateur par défaut.

### Chaque étape, en détail

- Timeout individuel (voir le tableau des constantes en tête de chaque
  fonction `Step-*` dans `run_review.ps1`) : au-delà, le process (et son
  arbre, via `taskkill /T`) est tué, l'étape est marquée `fail`, **la
  pipeline continue**.
- stdout+stderr fusionnés en direct (ordre chronologique réel) dans
  `<out>/logs/<étape>.log`.
- Chaque étape écrit ses propres artefacts sous `<out>/<étape>/` (résultat
  JSON parsé depuis les lignes de sortie du script Godot, captures PNG,
  `results.xml` JUnit copié depuis `reports/report_<n>/`...).
- Un script du contrat parallèle absent (`tools/review/gameplay_probe.gd`,
  `tools/review/ui_shots.gd`) donne le statut `missing`, jamais un échec —
  le rapport l'affiche en gris avec la note « absent ».

## Ce que veut dire chaque gate

Les seuils vivent dans le dictionnaire `GATES` en tête de
`tools/review/report.py` — à modifier là, pas ailleurs, si un seuil doit
changer.

| Gate | Seuil actuel | FAIL si | WARN si |
|---|---|---|---|
| `unit_tests` | — | au moins un test échoue | code retour gdUnit4 = 101 (avertissements seuls) |
| `gameplay_probe` | `errors == 0`, tous les checks `ok` | sinon | — |
| `net_smoke` | `ok == true` | `ok == false` | `rejected_shots < 2` |
| `bot_smoke` | `kills >= 1` et `errors == 0` | sinon | — |
| `perf_bench` | fps moyen par map | `< 30 fps` | `< 60 fps`, ou régression `> 10 %` vs run précédent |
| `log_scan` | groupes d'erreur non-bruit | `>= 10` groupes | `>= 1` groupe |

« Bruit connu » (jamais compté comme échec, mais toujours affiché à part) :
erreurs `material is null` en `--headless` sur les maps repeintes — dû au
renderer factice (dummy renderer) qui ne charge pas les matériaux, sans
rapport avec un vrai bug de rendu. Liste dans `_KNOWN_NOISE` en tête de
`tools/review/log_scan.py`.

Le statut global du run est le pire statut parmi toutes les sections
(FAIL > WARN/MISSING > PASS). `report.py` compare aussi au run précédent
(`reports/review/<horodatage précédent>/summary.json`) et liste les
régressions : tests nouvellement en échec, erreurs de log en hausse, fps en
baisse de plus de 10 % sur une map, kills de `bot_smoke` en baisse.

## Ajouter une étape

1. Écrire le script (`tools/review/mon_outil.gd` ou `.py`) — imprime une
   ligne de résultat reconnaissable (`MON_OUTIL_DONE`/`MON_OUTIL_FAIL ...`,
   comme les outils existants) et/ou écrit un JSON dans son `--out=DIR`.
2. Dans `run_review.ps1` : ajouter une fonction `Step-MonOutil` (calquer sur
   `Step-MapShots` pour un outil fenêtré à un seul process, sur
   `Step-ViewmodelFpShots` pour deux process séquentiels), l'ajouter à
   `$CoreSteps` (et à `$QuickSteps` si elle est headless et rapide), et à
   `$StepDispatch`.
3. Dans `report.py` : ajouter une fonction `eval_mon_outil` (calquer sur
   `eval_generic_shots` si c'est une capture, ou écrire un gate dédié comme
   `eval_perf_bench`), l'appeler dans `build_summary`, ajouter l'entrée dans
   `STEP_ORDER`/`STEP_TITLES`.
4. Relancer avec `-Only mon_outil` pour vérifier l'étape isolément avant un
   run complet.

## Bugs de jeu observés en testant cette pipeline

Voir le rapport de la tâche qui a livré `tools/review/` (pas ce document —
il ne doit décrire QUE la pipeline) pour la liste des bugs relevés en la
faisant tourner pour de vrai.
