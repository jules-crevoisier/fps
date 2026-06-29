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
| Marche lente      | Shift (maintenu) — sinon **sprint automatique** |
| Crouch / Slide    | Ctrl (tap) |
| Dive / Landing-roll | V |
| Libérer la souris | Échap |

Mouvement hybride **MW2019 (sol) + CS/Valorant (air)** :
- **Sprint automatique** : tu cours à fond dès que tu bouges ; Shift pour marcher.
- **Crouch en toggle** : un tap de Ctrl pour s'accroupir, un autre pour se relever.
- **Slide** : tap Ctrl en courant → glissade qui accélère en descente, puis tu te
  relèves. Avec **slide-cancel** (re-tap Ctrl), **slide-jump** et **slide-hop**.
- **Air-strafe CS** : tourner la souris en strafant gagne de la vitesse ;
  un contrôle direct permet de freiner / réorienter dans toutes les directions.
- **Dolphin dive** (V) : plongée plus haute et plus longue qu'un saut sprint,
  suivie d'une roulade (galipette caméra).
- **Stun de chute cartoon** : une grosse chute t'étourdit (étoiles ★ qui tournent),
  durée selon la hauteur — **annulable** en faisant une roulade au bon timing (V).

Référence complète de toutes les mécaniques et de leurs réglages :
[`docs/MOVEMENT.md`](docs/MOVEMENT.md).

## Architecture

```
fps/
├── project.godot          # Input map, autoload réseau, scène principale
├── scenes/
│   ├── player/            # player.tscn (CharacterBody3D + state machine + étoiles de stun)
│   ├── levels/            # test_arena.tscn (parcours de test généré par code)
│   ├── ui/                # HUD, menus (à venir)
│   └── weapons/           # armes (à venir)
├── scripts/
│   ├── core/              # systèmes transverses
│   ├── movement/          # MovementConfig.gd (tous les réglages, .tres tunables)
│   ├── player/            # PlayerController.gd, PlayerCamera.gd, StunStars.gd
│   │   └── states/        # Idle/Walk/Sprint/Crouch/Air/Slide/Dive/Roll/Stun
│   ├── levels/            # ArenaBuilder.gd (parcours), JumpPad.gd
│   ├── networking/        # NetworkManager (autoload "Net"), GameWorld
│   ├── weapons/           # logique d'armes (à venir)
│   └── ui/                # SpeedHUD.gd (vitesse + état à l'écran)
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

- [x] Système de mouvement complet (sol MW2019, air CS, slide, dive/roll, stun)
- [x] Arène de test + HUD vitesse/état + respawn à la chute
- [ ] Menu host/join + écran de connexion
- [ ] Reconciliation / prédiction côté client (netcode robuste)
- [ ] Armes (hitscan + projectiles cartoon)
- [ ] Wall-run / grapple (mouvement avancé)
- [ ] Style visuel cartoon (toon shader, outline)
