# Performance — mesures et outils

## Outils

- **Overlay** (autoload `Perf`, `scripts/core/PerfOverlay.gd`) : **F3** en jeu.
  Affiche fps, temps de frame, 1 % low (sur ~10 s), draw calls, objets,
  primitives, fréquence physique et ping (en client).
- **Benchmark** (`scenes/levels/benchmark.tscn`) : géométrie de la map
  compétitive, 8 mannequins, caméra sur un parcours fixe. 3 s de chauffe puis
  20 s de mesure ; affiche une ligne `BENCH …` et écrit
  `user://benchmark_<unix>.json`, puis quitte.

```bash
godot --path . res://scenes/levels/benchmark.tscn
```

En `--headless` le benchmark tourne mais ses chiffres ne veulent rien dire
(pas de rendu) : il sert seulement à vérifier qu'il ne casse pas.

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
