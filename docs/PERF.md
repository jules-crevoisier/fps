# Performance — mesures et outils

## Outils

- **Overlay** (autoload `Perf`, `scripts/core/PerfOverlay.gd`) : **F3** en jeu.
  Affiche fps, temps de frame, 1 % low (sur ~10 s), draw calls, objets,
  primitives, fréquence physique, ping (en client), et les 5 moniteurs de
  compilation de pipelines `RenderingServer.RenderingInfo` — ligne
  `Pipelines CANVAS .. MESH .. SURFACE .. DRAW .. SPECIALIZATION ..`
  (docs/research/07_godot_tech.md §C2). Ces 5 compteurs sont **cumulatifs**
  depuis le démarrage du moteur (ils ne redescendent jamais, doc officielle
  Godot) : l'overlay affiche leur valeur brute. Un `DRAW` qui progresse en
  pleine partie déjà chargée signale un trou dans le préchauffage
  (`ShaderWarmup`, TECH-01).
- **Benchmark** (`scenes/levels/benchmark.tscn`) : géométrie de la map
  compétitive, 8 mannequins, caméra sur un parcours fixe. 3 s de chauffe
  (où un `ShaderWarmup` précompile aussi les pipelines des matériaux Cartoon)
  puis 20 s de mesure ; affiche une ligne `BENCH …` et écrit
  `user://benchmark_<unix>.json`, puis quitte avec un **code de sortie 1**
  si l'un des deux seuils suivants est dépassé (consts documentées dans
  `scripts/levels/Benchmark.gd`), sinon 0 :
  - `p99_ms > P99_FAIL_THRESHOLD_MS` (9 ms — budget 144 fps, §C5) ;
  - le compteur `RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW` a progressé de
    plus de `MAX_DRAW_PIPELINE_COMPILATIONS_DURING_MEASURE` (0) entre le
    début et la fin de la fenêtre de mesure — un pipeline DRAW compilé
    pendant la mesure est un trou de préchauffage (TECH-01).

  Le JSON et la ligne `BENCH …` portent aussi les 5 compteurs de pipelines
  (delta mesuré pendant la fenêtre, pas leur valeur cumulée brute) et le
  booléen `pass` :

  ```json
  {"avg_fps": 144.94, "low1": 144.0, "p99_ms": 6.94,
   "draw_calls": 0, "objects": 0, "frames": 2899,
   "pipeline_canvas": 0, "pipeline_mesh": 0, "pipeline_surface": 0,
   "pipeline_draw": 0, "pipeline_specialization": 0, "pass": true}
  ```

```bash
godot --path . res://scenes/levels/benchmark.tscn
```

En `--headless` le benchmark tourne mais ses chiffres de fps/draw calls ne
veulent rien dire (pas de rendu réel) : il sert surtout à vérifier qu'il ne
casse pas. Les compteurs de pipelines y restent normalement à 0 des deux
côtés (aucune compilation déclenchée sans rendu réel), donc `pass` y reste
`true` sauf régression du code lui-même.

## Référence (Phase 0)

Mesure du 23/09/2026, avant tout travail artistique (maps en boîtes, capsules,
matériaux plats). Machine de dev : Windows 11, GPU AMD, D3D12, fenêtre par défaut.

| Mesure | Valeur |
|---|---|
| fps moyen | 274,8 |
| 1 % low | 180 fps |
| p99 temps de frame | 5,56 ms |
| Draw calls (moyenne) | 65 |
| Objets (moyenne) | 65 |

Chaque phase qui touche au rendu (Phase 3 surtout) refait cette mesure et la
compare à celle-ci. Cibles de la roadmap : 144 fps en 1080p en config
recommandée, 60 fps sur Steam Deck en 800p.
