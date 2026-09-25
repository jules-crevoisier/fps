# 03 — Level design compétitif : métriques, structure, spawns, sites

> Statut : REMPLI (recherche du 2026-09-23). Les chiffres marqués *(hypothèse)* sont
> nos propositions, à valider en playtest ; tous les autres sont sourcés.
> Lecture préalable : `docs/MOVEMENT.md`, `docs/MODES.md`, `.orchestrator/maps-spec.md` (v1),
> `.orchestrator/maps-spec-v2.md`, `scripts/levels/maps/*`, `scripts/networking/SpawnPick.gd`.

## 1. Résumé (10 lignes)

1. Nos gabarits de base tiennent la route : saut 1,36 m = 0,76 × la taille du joueur (CS : 54/72 = 0,75) ; couvert bas 1,0–1,2 m OK face à un œil debout à 1,6 m et accroupi à 0,7 m.
2. **Défaut de jouabilité n°1 côté carte : pas de marche automatique.** Toute arête > 0,15 m bloque le joueur ; CS monte 18/72 = 0,25 × sa taille (≈ 0,45 m chez nous). Ça « accroche » partout.
3. **Défaut n°2 : spawns TDM figés.** 4 points par équipe, toujours du même côté. Halo recommande 40 à 60 points pour du 4v4 Slayer, et CoD fait tourner les spawns selon la pression ennemie et les lignes de vue. Chez nous, un spawn-trap est donc possible.
4. Les spawns doivent être notés : pénalité si un ennemi est proche ou a une ligne de vue, bonus si un allié est proche, pénalité qui décroît sur un lieu de mort récent.
5. R&D : la rotation d'un site à l'autre est *le* chiffre clé. Côté CS, 10–15 s pour une bombe de 40 s. Chez nous, Cargo A↔B ≈ 5 s au sprint : les retakes sont trop faciles, à mesurer.
6. Les bandes de ligne de vue (TF2 : ≤ 6,5 m / ≤ 26 m / ≤ 52 m) collent à nos armes (Fracas / Rafale-Ravage / Faucheur). La spec v2 les respecte déjà.
7. Chaque position forte a besoin d'au moins 3 accès (Game Developer, flow en deathmatch) et d'un contre (Activision MW2019). La spec v2 le fait pour les toits ; à généraliser aux sites R&D.
8. Il manque les repères de lecture en jeu : pas de minimap ni de noms de zones (callouts) affichés. Riot fait des callouts un outil de gameplay (biomes contrastés sur Fracture).
9. Process : gameplay d'abord en gray-box (Riot : « the graybox leads the way »), puis un playtest hebdo à la Valve (lundi on planifie, vendredi on teste), et des heatmaps de morts et de kills (Bungie publiait celles de Halo 3).
10. Priorités : marche automatique, spawns dynamiques, callouts + minimap, mesure des rotations R&D, carte-gym de métriques, heatmaps.

## 2. Findings (sources inline)

### 2.1 Métriques joueur et gabarits

- **Gabarits de référence.** [Level Design Book — Metrics](https://book.leveldesignbook.com/process/blockout/metrics) :
  - Unity : 1,0 × 1,8 m, yeux à 1,5–1,7 m ; couloir minimal 2,0 m ; porte 1,25 × 2,5 m.
  - Unreal : 60 × 176 cm, yeux à 152 cm ; couloir minimal 150 cm ; porte 110 × 220 cm.
  - Source : 32 × 72 u, yeux à 64 u, porte 56 × 112 u.
  - Règle : « le couloir minimal fait au moins le double de la largeur du joueur » ; escaliers à 30–35° ; palier tous les 12–16 marches.
- **L'échelle de jeu est exagérée volontairement** : « build at the player's scale ». La cohérence interne compte plus que le réalisme, et les métriques ne remplacent pas le test (même source).
- **Counter-Strike** ([Mapper's Reference, Valve](https://developer.valvesoftware.com/wiki/Counter-Strike:_Global_Offensive_Mapper's_Reference), [World of Level Design](https://www.worldofleveldesign.com/categories/csgo-tutorials/csgo-sdk-beginner-03-scale-dimension-proportion.php)) :
  - joueur 32 × 72 u debout, 32 × 54 u accroupi ;
  - saut 54 u, saut accroupi 64 u ;
  - **obstacle franchissable sans sauter : 18 u** ;
  - portes 56 × 112 u, doubles portes de préférence « pour un mouvement fluide » ;
  - œil à 64 u.
- **Construire une « metrics zoo »**, une carte de test qui aligne portes, couloirs, couverts, sauts et pentes, et un outil de debug qui montre l'arc de saut (Psychonauts 2) ([LDB](https://book.leveldesignbook.com/process/blockout/metrics)). Texture de prototypage quadrillée, jamais de couleur unie (on perd l'échelle).

**Transposé chez nous** (joueur 0,8 × 1,8 m, œil 1,6 m debout / 0,7 m accroupi, `scenes/player/player.tscn`, `PlayerController.gd:512`) : voir §3.1.

### 2.2 Structure : 3 couloirs, chokes, rotations, timings

- **Flow.** Les maps doivent proposer des options sans demi-tour à 180° : « everything needs to be presented to you as you move ». Toute position forte a **au moins 3 entrées**, car on peut en couvrir une, voire deux, jamais trois. Il faut mesurer le temps avant le premier contact et supprimer les zones mortes ([Game Developer — Deathmatch map design: the architecture of flow](https://www.gamedeveloper.com/design/deathmatch-map-design-the-architecture-of-flow)).
- **Trois couloirs** (CoD) : [GamesRadar](https://www.gamesradar.com/how-to-build-a-great-call-of-duty-multiplayer-map-according-to-the-players-that-know-the-game-best/), déjà dans la roadmap. Un choke par couloir, et aucun point ne couvre tous les chokes ([LDB — Balance](https://book.leveldesignbook.com/process/combat/balance), repris en `maps-spec.md` §1).
- **Riot, gameplay d'abord.** Joe Lansford : « Our maps are 'gameplay first', so the graybox definitely leads the way » ; « Metrics are all determined by the needs of the space » ([ONE Esports](https://www.oneesports.gg/valorant/valorant-map-design-explained-riot-devs/)). Chaque map a **un crochet** (téléporteurs de Bind, tyroliennes de Fracture).
- **Rotation sûre pour les défenseurs.** Sur Fracture, Riot a dû ajouter « a safer rotation for defenders through their spawn ». Avant cela, les attaquants en post-plant pouvaient « completely choke out defenders in their spawn » ([Riot — Controlled Ruptures](https://playvalorant.com/en-us/news/dev/controlled-ruptures-making-valorant-s-fracture/)). Même idée sur Corrode : laisser aux défenseurs de quoi tenir le site face à l'utilitaire ([esports.gg](https://esports.gg/news/valorant/corrode-inspiration-and-design-behind-the-new-valorant-map-with-developers/)).
- **Temps de rotation (CS).** C'est le chiffre le plus important à cause du timer de la bombe (40 s). Une rotation de **10–15 s** marche pour la plupart des maps : trop courte, elle avantage les CT ; trop longue, ils ne peuvent plus défuser ([guide communautaire « The dos and don'ts of CS level design »](https://steamcommunity.com/sharedfiles/filedetails/?id=1110438811), cité via la recherche ; page non chargée, erreur 429). Défuse : 10 s, 5 s avec kit ([gamertagmythras](https://gamertagmythras.com/blog/counter-strike-2/cs2-bomb-timer-defuse-blast-guide)).
- **Maps à 3 sites** : on étire la défense, donc les rotations comptent plus que l'aim (Haven). Des sites équivalents rendent les rotations « wonky » ([ScreenRant, Lansford sur Lotus](https://screenrant.com/joe-lansford-interview-valorant-lotus-map-design/)).

### 2.3 Lignes de vue par classe d'arme

- **Bandes TF2** ([LDB](https://book.leveldesignbook.com/process/blockout/metrics)) : courte ≤ 256 u, moyenne ≤ 1024 u, sniper ≤ 2048 u. Avec 1 u = 2,54 cm, ça donne **≤ 6,5 m, ≤ 26 m, ≤ 52 m**.
- **Chez nous** (`maps-spec-v2.md` §4–5) : Fracas ≤ 8 m, Rafale ≤ 17 m, Ravage/Marqueur ≤ 28–30 m, et deux lignes Faucheur volontaires à 51–52 m par map. C'est cohérent : **ne pas élargir**.

### 2.4 Spawns TDM / Hardpoint et protection

- **Halo 3** ([FyreWulff, Understanding Halo 3 spawns](https://halo.bungie.org/misc/fyrewulff_spawnsystem/)) :
  - chaque point part à 1000 ;
  - allié proche +500, ennemi proche −500 (≈ 5 cases) ;
  - **mort récente sur place −700**, qui remonte de +100/s ;
  - un coéquipier passé sur le point dans les 7 dernières secondes bloque ce point.
  - Minimum de points par mode : **2v2 : 10 (25 optimal)**, **4v4 Slayer : 40 (55–60)**, 4v4 objectif : 50 (70).
  - Halo 3 ignorait la ligne de vue ; les jeux récents, eux, la comptent.
- **Call of Duty BO7** ([mitchcactus](https://mitchcactus.co/blog/call-of-duty/bo7-how-spawns-work/), d'après les notes Treyarch) :
  - influences : pression ennemie, **contrôle de ligne de vue** (éviter d'apparaître près d'un ennemi visible), répartition des alliés, poches libres, objectifs ;
  - en TDM les spawns bougent souvent (flips) faute d'objectif pour les ancrer ;
  - en Hardpoint on « ancre » le spawn en tenant le bon côté avant la rotation de zone.
- **Principe CoD** ([CoD Wiki, How spawns work](https://callofduty.fandom.com/wiki/User_blog:Bibliomaniac15/How_Spawns_Work,_part_1:_Spawnpoints)) : spawns répartis plutôt en bordure qu'au centre, jamais près d'un ennemi.
- **L'orientation au spawn guide le trafic** : le joueur part là où il regarde ([Game Developer](https://www.gamedeveloper.com/design/deathmatch-map-design-the-architecture-of-flow)). Notre champ `look` sert à ça.

### 2.5 Sites plant/défuse (R&D)

- Un site Valorant a plusieurs entrées, des cubbies réglés au centimètre (« how deep cubbies should be ») et de la verticalité ([esports.gg / Corrode](https://esports.gg/news/valorant/corrode-inspiration-and-design-behind-the-new-valorant-map-with-developers/)).
- **Post-plant** : les positions hors site ne doivent pas tout verrouiller. Riot a limité le « post-plant off-site » sur Corrode.
- **Chez nous** : ratio d'arrivée attaque/défense de 2,0 à 2,29 (`maps-spec-v2.md` §4–5) ; c'est un bon indicateur. Il manque :
  1. le temps de rotation A↔B ;
  2. l'avance des défenseurs sur le premier choke ;
  3. le nombre d'entrées par site (≥ 3 : main, flanc, vertical/rotation).

### 2.6 Arènes Duel 1v1 / Duo 2v2

- **Gunfight** (CoD) : maps minuscules, majoritairement symétriques (ex. Docks : un bâtiment de 2 étages de chaque côté, un pont entre les deux) ; flow, lignes de vue et cadrage du combat pensés pour du 2v2 ([BOCW, blog officiel](https://www.callofduty.com/blog/2020/12/black-ops-cold-war-gunfight-returns-new-maps-tips-and-tricks), [Treyarch via Forbes](https://www.forbes.com/sites/erikkain/2024/10/23/treyarch-explains-how-call-of-duty-black-ops-6-gunfight-mode-works-and-how-they-designed-the-games-smallest-maps/)).
- **Avis de joueurs pros** : des maps Gunfight 20–30 % plus grandes, avec une couche de couvert en plus ([Dexerto](https://www.dexerto.com/call-of-duty/modern-warfare-dr-disrespect-shares-how-to-improve-2v2-gunfight-maps-946041/)). Trop petit, ça devient une loterie au spawn.
- **Halo** : 10 à 25 points de spawn en 2v2. En Duel/Duo à manches, on n'a besoin que de 2 spawns fixes et symétriques par camp.
- **Chez nous** : La Fosse 28 × 28 m, Belvédère 30 × 24 m, lignes ≤ 30 m, manche de 40 s puis zone. C'est aligné sur Gunfight. À vérifier :
  - temps jusqu'au premier contact *(hypothèse : 4–7 s)* ;
  - 3 routes vers la zone centrale.

### 2.7 Verticalité, repères, lisibilité

- **Repères.** Des marqueurs distincts orientent instantanément : une falaise derrière une base, un littoral derrière l'autre, une silhouette de ville ([Game Developer](https://www.gamedeveloper.com/design/deathmatch-map-design-the-architecture-of-flow)). Riot : un repère par district ([Création de Split](https://playvalorant.com/en-us/news/dev/the-creation-of-split/)). Sur Fracture, le double biome sert aux callouts ([Riot](https://playvalorant.com/en-us/news/dev/controlled-ruptures-making-valorant-s-fracture/)).
- **Hauteur.** Positions fortes à contester, mais toujours pénétrables : chaque nid a des contre-routes ([Game Developer](https://www.gamedeveloper.com/design/deathmatch-map-design-the-architecture-of-flow), [Activision MW2019](https://blog.activision.com/call-of-duty/2019-08/Modern-Warfare-Multiplayer-First-Look-Creating-Multiplayer-Maps)).
- **Les 3 questions** du joueur : où suis-je, où vais-je, comment y aller ([Pascal Luban](https://www.gamedeveloper.com/design/multiplayer-level-design-in-depth-part-2-the-rules-of-map-design)). Sans minimap ni callouts, on ne répond qu'à la première, et encore.

### 2.8 Process : blockout → art pass, playtest, heatmaps

- **Tester en blockout** : les changements coûtent cher une fois l'art posé ([LDB Metrics](https://book.leveldesignbook.com/process/blockout/metrics)). Notre pipeline le respecte : collision Kit figée, habillage par `skin`/`dress`, test d'invariance §8.16.
- **Méthode de playtest** ([LDB Playtesting](https://book.leveldesignbook.com/process/blockout/playtesting)) :
  - s'asseoir un peu en retrait, regarder l'écran, pas la personne ;
  - **ne jamais expliquer la map** ni s'excuser ;
  - questions de compréhension (« as-tu vu X ? qu'est-ce que ça voulait dire ? ») ;
  - testeurs à distance enregistrés sous OBS ;
  - cycle hebdo à la Valve : lundi planification, vendredi playtest ;
  - on mesure temps de jeu, morts, taux de victoire, heatmaps, et le « clumping » (objets ou routes sur-utilisés).
- **Heatmaps** : Bungie calculait les heatmaps de kills et de morts de Halo 3 sur ses serveurs et les publiait ([Cool Infographics](https://coolinfographics.com/blog/2009/1/12/halo-3-heatmaps.html)). La recherche compare aussi kills, morts et leur différence ([ResearchGate](https://www.researchgate.net/figure/Global-heatmaps-for-deaths-top-row-kills-middle-row-and-their-difference-bottom_fig8_221890304)). La carte « différence » montre les positions dominantes.

## 3. Tableaux de métriques

### 3.1 Gabarits : référence vs nous

| Mesure | CS (u → m, 1 u = 2,54 cm) | Ratio / taille joueur | Nous | Ratio | Verdict |
|---|---|---|---|---|---|
| Taille debout | 72 u = 1,83 m | 1 | 1,8 m | 1 | — |
| Taille accroupi | 54 u = 1,37 m | 0,75 | 0,9 m | 0,5 | Crouch très bas : un couvert de 1,0 m cache tout le corps. Voulu, à garder |
| Œil debout | 64 u = 1,63 m | 0,89 | 1,6 m | 0,89 | OK |
| Saut | 54 u = 1,37 m | 0,75 | 1,36 m | 0,76 | OK |
| **Marche auto (step)** | **18 u = 0,46 m** | **0,25** | **≈ 0 (aucune)** | **0** | **À corriger (LD-01)** |
| Porte | 56 × 112 u = 1,42 × 2,84 m | 1,56 en hauteur | 1,6 × 2,4 m | 1,33 | Largeur OK ; hauteur : 2,8 m pour les portes de passage principales *(hypothèse)* |
| Couloir mini | 2 × largeur joueur (LDB) | — | 0,8 m → 1,6 m mini | — | Avec sprint 8,2 m/s et slide : ≥ 2,5 m sur les routes principales *(hypothèse)* |
| Hauteur sous plafond | — | — | 2,2 m (headroom) | 1,22 | Un saut en intérieur cogne (1,8 + 1,36 = 3,16 m). Routes de mouvement : ≥ 3,2 m *(hypothèse)* |

### 3.2 Couverts vs hauteurs d'œil (nous)

| Hauteur de couvert | Accroupi (œil 0,7 m, tête 0,9 m) | Debout (œil 1,6 m, tête 1,8 m) | Usage |
|---|---|---|---|
| 0,8–0,9 m | tête visible | tire par-dessus | Éviter : ni couvert ni passage clair |
| **1,0–1,2 m** (couvert bas, spec v1) | caché entier | tire par-dessus, tête exposée | Couvert de peek, le bon standard |
| 1,3–1,6 m | caché | les yeux ne dépassent pas | Zone morte : éviter (mauvaise lecture) |
| ≥ 1,8 m (couvert plein) | caché | caché | Coin de peek latéral |

### 3.3 Bandes de ligne de vue

| Bande | TF2 | Nous (armes) | Règle de spec |
|---|---|---|---|
| Courte | ≤ 6,5 m | Fracas (one-shot ≤ 4 m) | intérieurs, tubes, cales |
| Moyenne | ≤ 26 m | Rafale ≤ 17 m, Ravage/Marqueur ≤ 28–30 m | caps 2D par map ≤ 30 m |
| Longue | ≤ 52 m | Faucheur | ≤ 2 lignes déclarées par map, 51–52 m |

### 3.4 Spawns : cible par mode

| Mode | Halo (min / optimal) | Nous aujourd'hui | Cible *(hypothèse)* |
|---|---|---|---|
| TDM 4v4 | 40 / 55–60 | 4 par équipe, côté fixe | 16–24 points par map, sans camp, notés dynamiquement |
| Hardpoint 4v4 | 50 / 70 | 4 par équipe | idem + bonus selon la zone active (ancrage) |
| R&D 4v4 | — (pas de respawn) | 4 par rôle | OK |
| Duel / Duo | 10 / 25 (2v2 à respawn) | 1–2 par camp | OK (manches) |

### 3.5 R&D : timings à mesurer (navmesh, sprint 8,2 m/s)

| Mesure | Référence | Nous | Cible *(hypothèse)* |
|---|---|---|---|
| Rotation site A ↔ site B | CS : 10–15 s pour une bombe de 40 s (25–37 % du timer) | Cargo ≈ 38 m en ligne droite ≈ 5 s ; Wasteland non mesuré | 7–12 s (15–27 % de notre bombe de 45 s) |
| Ratio attaque/défense jusqu'au site | — | 2,0–2,29 | 1,8–2,4 (garder) |
| Entrées par site | Valorant : main + flanc + vertical/rotation | non tracé | ≥ 3, dont 1 rotation défenseur sûre (leçon Fracture) |
| Taux de victoire attaque par site | roadmap : 45–55 % | non mesuré | 45–55 % |

## 4. Écarts avec notre jeu

1. **Pas de marche automatique** : le mouvement bute sur toute arête > 0,15 m (`maps-spec.md` §2 : « Players have no step-up »). C'est très probablement une grosse part du « pas jouable ». Fichiers : `scripts/player/PlayerController.gd` (seul `floor_snap_length = 0.4` existe), `scripts/movement/MovementConfig.gd`.
2. **Spawns TDM/Hardpoint figés à 4 par équipe** : `SpawnPick.safest()` (`scripts/networking/SpawnPick.gd`) choisit juste le point le plus loin de l'ennemi le plus proche, sans ligne de vue, sans alliés, sans mémoire des morts. Points : `scripts/levels/maps/Layouts.gd`, choix : `scripts/networking/GameWorld.gd`.
3. **Aucun callout ni minimap** : la direction artistique prévoit une minimap de 240 px (`.orchestrator/design.md` §12), mais aucun code ne la dessine (`grep minimap` = 0). Il n'y a pas non plus de nom de zone. Fichiers : `scripts/ui/GameHUD.gd`, `scripts/levels/maps/Layouts.gd`.
4. **Rotation R&D non mesurée** : les tests valident le ratio attaque/défense (`tests/maps/`), pas la rotation A↔B ni le nombre d'entrées par site.
5. **Headroom 2,2 m** : un saut sous une passerelle cogne ; il faut vérifier que les routes de slide et de dive gardent ≥ 3,2 m. Paires déclarées : `HEADROOM_PAIRS` (`maps-spec-v2.md` §8).
6. **Pas de carte-gym de métriques** : le terrain d'entraînement (`scripts/training/TrainingBuilder.gd`) enseigne le mouvement, mais ne sert pas d'étalon pour les portes, couverts, sauts et pentes.
7. **Heatmaps absentes** : P2.8 non fait (`docs/ROADMAP.md` §6), aucun événement de kill ou de mort n'est journalisé.
8. **Arènes Duel/Duo** : pas de test de temps jusqu'au premier contact ni de nombre de routes vers la zone (`.orchestrator/maps-spec.md` §3.5–3.6).

## 5. Tâches

```
- id: LD-01
  title: Marche automatique (step-up) de 0,45 m dans le contrôleur joueur, bots compris
  files: [scripts/player/PlayerController.gd, scripts/movement/MovementConfig.gd, resources/movement/default_movement.tres, tests/player/test_step_up.gd]
  depends_on: []
  size: M
  acceptance: test gdUnit4 — un joueur qui sprinte vers une marche de 0,40 m la franchit sans sauter ni perdre plus de 10 % de vitesse horizontale ; une marche de 0,50 m le bloque ; aucune montée d'escalier en slide ne déclenche de stun ; tests de mouvement existants verts.
- id: LD-02
  title: Spawns dynamiques notés (distance ennemie, ligne de vue, alliés, mort récente) pour TDM et Hardpoint
  files: [scripts/networking/SpawnPick.gd, scripts/networking/GameWorld.gd, tests/networking/test_spawn_pick.gd]
  depends_on: []
  size: M
  acceptance: fonction pure SpawnPick.score(point, enemies, allies, recent_deaths, los_fn) testée — un point vu par un ennemi vivant à moins de 30 m n'est jamais choisi s'il existe une alternative ; un point où un allié est mort il y a moins de 5 s est pénalisé ; en simulation de bots 4v4 sur 10 min, moins de 5 % des morts surviennent dans les 3 s suivant un spawn.
- id: LD-03
  title: 16–24 points de spawn neutres par map 4v4 (TDM/Hardpoint), répartis en bordure des 3 couloirs
  files: [scripts/levels/maps/Layouts.gd, scripts/levels/maps/MapSetup.gd, tests/maps/test_layouts.gd]
  depends_on: [LD-02]
  size: M
  acceptance: chaque map 4v4 déclare ≥ 16 points `tdm_spawns` sur le navmesh, chacun avec un `look` ; aucun n'est vu depuis une position forte déclarée à moins de 20 m (rayons 3D) ; R&D garde ses spawns par rôle inchangés.
- id: LD-04
  title: Callouts — volumes nommés par zone sur les 8 maps
  files: [scripts/levels/maps/Layouts.gd, scripts/levels/maps/MapSetup.gd, tests/maps/test_callouts.gd]
  depends_on: []
  size: M
  acceptance: chaque map déclare 8–14 zones {name, aabb} ; ≥ 95 % des polygones du navmesh tombent dans une zone ; les noms sont uniques par map et ≤ 14 caractères ; API `MapSetup.callout_at(pos) -> String` testée.
- id: LD-05
  title: Mesure automatique des timings R&D (rotation A↔B, avance défenseur, entrées par site)
  files: [tests/maps/test_snd_timings.gd, scripts/levels/maps/Layouts.gd]
  depends_on: []
  size: S
  acceptance: le test calcule sur le navmesh la rotation A↔B au sprint (8,2 m/s) et échoue hors de 7–12 s ; il vérifie ≥ 3 entrées par site (portails navmesh distincts dans un rayon de 12 m) ; les maps qui échouent sont listées dans le rapport, puis corrigées ou exemptées avec une justification écrite.
- id: LD-06
  title: Audit de hauteur libre sur les routes de mouvement (≥ 3,2 m au-dessus des rampes de slide, gaps de dive et escaliers)
  files: [tests/maps/test_layouts.gd, scripts/levels/maps/Layouts.gd]
  depends_on: []
  size: S
  acceptance: pour chaque SLIDE_RAMP, DESIGN_GAP et escalier, aucun solide n'est à moins de 3,2 m au-dessus du sol de la route (échantillonnage tous les 0,5 m) ; les exceptions déclarées restent ≥ 2,4 m.
- id: LD-07
  title: Carte-gym de métriques (portes, couloirs 1,6/2,5/3,5 m, couverts 0,9/1,1/1,4/1,8 m, marches 0,2/0,4/0,5 m, gaps 6/8/10 m, pentes 15/22/27/37°)
  files: [scripts/levels/MetricsGym.gd, scenes/levels/metrics_gym.tscn, scripts/ui/MainMenu.gd]
  depends_on: [LD-01]
  size: S
  acceptance: accessible depuis le menu (Entraînement → Gym) ; chaque élément porte son étiquette de mesure en 3D ; texture quadrillée à 1 m ; se charge en moins de 3 s.
- id: LD-08
  title: Outil de heatmap (kills, morts, différence) par map, depuis les événements de télémétrie
  files: [tools/heatmap.gd, tools/heatmap_render.py]
  depends_on: [FUN-05]
  size: M
  acceptance: à partir d'un fichier JSONL d'événements `kill`, l'outil produit 3 PNG top-down (kills, morts, kills − morts) calés sur les bounds de la map, avec une grille de 2 m ; testé sur un match de bots de 10 min.
- id: LD-09
  title: Validation des arènes Duel/Duo (premier contact, routes vers la zone, symétrie)
  files: [tests/maps/test_arenas.gd]
  depends_on: []
  size: S
  acceptance: sur La Fosse et Belvédère, le temps navmesh spawn → milieu au sprint est de 2–4 s par camp (écart ≤ 5 %), la zone d'overtime a ≥ 3 accès distincts, aucune ligne de vue > 30 m.
```
