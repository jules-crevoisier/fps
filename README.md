# FPS — Cartoon Movement Shooter

FPS cartoon dynamique fait sous **Godot 4.7** (Forward+, Jolt Physics, GDScript).
Le cœur du projet est un système de mouvement **ultra fluide** : air-strafe façon
Source, slide avec momentum, et **slide cancel** pour enchaîner la vitesse.

## Lancer le projet

1. Ouvrir le dossier dans Godot 4.7.
2. Appuyer sur **F5** → le **menu principal** s'ouvre (`scenes/ui/main_menu.tscn`).
3. **Héberger** (1v1/2v2) ou **Rejoindre** une IP, ou **Terrain d'entraînement**
   pour tester le mouvement en solo.

### Tester le multijoueur à 2 fenêtres
**Debug → Run Multiple Instances → Run 2 Instances**, puis **F5**. Fenêtre 1 :
*Héberger*. Fenêtre 2 : *Rejoindre* (`127.0.0.1`). Détails et netcode :
[`docs/MULTIPLAYER.md`](docs/MULTIPLAYER.md).

## Contrôles

| Action   | Clavier (position physique → ZQSD sur AZERTY) | Manette |
|----------|-----------------------------------------------|---------|
| Déplacement       | W / A / S / D | Stick gauche |
| Sauter            | Espace | A |
| Marche lente (sinon **sprint auto**) | Shift (maintenu) | L3 |
| Accroupi / Slide  | Ctrl (maintien) | B |
| Dive / Landing-roll | V | LB |
| Tirer / ADS       | Clic G / Clic D | RT / LT |
| Recharger         | R | X |
| Pause             | Échap | Start |

Clavier + manette entièrement **remappables** dans Options, libellés adaptés à la
disposition système. Détails : [`docs/CONTROLS.md`](docs/CONTROLS.md).

Mouvement hybride **MW2019 (sol) + CS/Valorant (air)** :
- **Sprint automatique** : tu cours à fond dès que tu bouges ; Shift pour marcher.
- **Crouch en maintien** : tenir Ctrl = accroupi, relâcher = debout.
- **Slide** : tap Ctrl en courant → glissade qui accélère en descente. Relâcher
  Ctrl = **slide-cancel** (garde l'élan). Avec **slide-jump** et **slide-hop**.
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
- [x] Menu host/join + map 1v1/2v2 (goulag) + spawns par équipe
- [x] Vie serveur-autoritaire + zones dégâts/soin + mort/respawn + HUD
- [x] Tir hitscan validé serveur (type BO2 : falloff, headshot, munitions)
- [x] Système d'armes complet (types, recul, ADS/lunette, inventaire 2 slots, buy menu) — voir [`docs/WEAPONS.md`](docs/WEAPONS.md)
- [x] Drop/pickup physique + chiffres de dégâts + mannequins d'entraînement
- [x] Options complètes (rebind clavier/manette, AZERTY/QWERTY, navigation pad)
- [x] Classes / agents + capacités (hero-shooter) — voir [`docs/AGENTS.md`](docs/AGENTS.md)
- [x] Map compétitive + écran de sélection d'agent (style Valo)
- [x] Modes **Hardpoint** + **Team Deathmatch** (choix au menu) — voir [`docs/MODES.md`](docs/MODES.md)
- [x] Boucle de match : killfeed, scoreboard (Tab), kills/morts, écran de fin + rejouer
- [ ] Lisibilité multi (couleurs d'équipe, plaques de nom, hitmarkers)
- [ ] Économie + rounds · Mode SnD
- [ ] Prédiction client + lag compensation (netcode compétitif)
- [ ] Modèles 3D armes/persos + animations
- [ ] Style visuel cartoon (toon shader, outline)
