# FPS — Cartoon Movement Shooter

FPS cartoon dynamique fait sous **Godot 4.7** (Forward+, Jolt Physics, GDScript).
Le cœur du projet est un système de mouvement **ultra fluide** : air-strafe façon
Source, slide avec momentum, et **slide cancel** pour enchaîner la vitesse.

## Lancer le projet

1. Ouvrir le dossier dans Godot 4.7.
2. Appuyer sur **F5** (la scène principale est `scenes/levels/test_arena.tscn`).
3. En solo, l'arène démarre automatiquement un serveur local et fait spawn le joueur.

## Contrôles

| Action   | Touche (position physique, donc ZQSD sur AZERTY) |
|----------|--------------------------------------------------|
| Avancer / reculer | W / S |
| Gauche / droite   | A / D |
| Sauter            | Espace |
| Sprint            | Shift (maintenu) |
| Crouch / Slide    | Ctrl |
| Libérer la souris | Échap |

**Slide** : en sprint, appuyer sur Ctrl → glissade boostée.
**Slide cancel** : re-tapper Ctrl (ou sauter) pendant le slide → on garde le
momentum et on peut re-slider immédiatement.

## Architecture

```
fps/
├── project.godot          # Input map, autoload réseau, scène principale
├── scenes/
│   ├── player/            # player.tscn (CharacterBody3D + state machine)
│   ├── levels/            # test_arena.tscn (sol, rampe, spawns, spawner réseau)
│   ├── ui/                # HUD, menus (à venir)
│   └── weapons/           # armes (à venir)
├── scripts/
│   ├── core/              # systèmes transverses
│   ├── movement/          # MovementConfig.gd (tous les réglages, .tres tunables)
│   ├── player/            # PlayerController.gd, PlayerCamera.gd
│   │   └── states/        # State machine : Idle/Walk/Sprint/Crouch/Air/Slide
│   ├── networking/        # NetworkManager (autoload "Net"), GameWorld
│   ├── weapons/           # logique d'armes (à venir)
│   └── ui/                # logique UI (à venir)
├── resources/
│   └── movement/          # default_movement.tres + variantes de feel
├── assets/                # audio, models, textures, materials, shaders, fonts
└── docs/                  # MOVEMENT.md (détail du système + tuning)
```

## Tuning du mouvement

Tout se règle sans toucher au code via la ressource
`resources/movement/default_movement.tres` (inspector). Voir
[`docs/MOVEMENT.md`](docs/MOVEMENT.md) pour le détail de chaque paramètre.

## Multijoueur

Base posée avec l'API multijoueur haut-niveau de Godot (ENet) :
`Net.host()` / `Net.join(ip)`. Le `MultiplayerSpawner` réplique les joueurs ;
l'autorité de chaque perso est donnée à son pair propriétaire.

## Roadmap

- [ ] Menu host/join + écran de connexion
- [ ] Reconciliation / prédiction côté client (netcode robuste)
- [ ] Armes (hitscan + projectiles cartoon)
- [ ] Wall-run / grapple (mouvement avancé)
- [ ] Style visuel cartoon (toon shader, outline)
