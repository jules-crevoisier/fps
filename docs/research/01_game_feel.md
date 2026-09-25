# 01 — Game feel : gunplay + mouvement

> Recherche du 23/09/2026 (Godot 4.7, GDScript typé, serveur autoritaire).
> Contexte : playtest utilisateur — « les bots sont nuls », « il y a des bugs
> partout », « là ce n'est pas jouable ». Ce fichier couvre **A. gunplay /
> juice** et **B. mouvement**. Les bots sont dans `02_bots_ai.md`.

## 1. Résumé en 10 lignes

1. Le plus gros problème n'est pas le « juice » : c'est la **fiabilité du tir**. Le serveur résout les tirs sur les positions *actuelles*, sans rembobinage ni interpolation des joueurs distants. En ligne, on rate des tirs qui étaient sur la cible à l'écran. C'est la principale source du ressenti « bugs partout ».
2. Les hitbox sont fausses : l'accroupi n'existe que chez le propriétaire, et le headshot est un simple seuil `y > 1.4 m`. Un joueur accroupi (0,9 m) ne peut jamais prendre de headshot.
3. La caméra bouge au tick physique (60 Hz) sans interpolation physique : saccades visibles à 144 Hz.
4. Le recul récupère *pendant* le spray (lerp continu), donc le motif fixe « façon Valorant » est lissé et devient illisible.
5. Le traceur part de la caméra (point au centre de l'écran) et va jusqu'à `max_range` en traversant les murs. Aucun impact n'est affiché localement.
6. Il n'y a ni shake caméra, ni kick FOV, ni flash sur la cible touchée. Le retour de hit repose sur le hitmarker, le son et les chiffres, ce qui est correct mais sec.
7. Le fusil à pompe envoie 12 `hit_confirmed` pour un seul tir (12 sons, 12 chiffres), et le kill est deviné par une fenêtre de 350 ms.
8. Le réticule est statique alors que la dispersion varie de 0,25° à 5°. Le joueur ne comprend pas pourquoi il rate.
9. Mouvement : les bases sont saines (coyote, buffer, air-strafe, slide), mais il manque le step-up (on se bloque sur les marches) et le stun de chute (jusqu'à 2,5 s figé) est une perte de contrôle.
10. Ordre recommandé : fiabilité (GF-01 à GF-04), puis lisibilité (GF-05 à GF-09), puis juice (GF-10 et suivantes) et mouvement (MV-xx).

## 2. Findings (avec sources)

### 2.1 Juice et retour de tir

- **Vlambeer, « The Art of Screenshake »** (Jan Willem Nijman, INDIGO 2013) donne une trentaine d'astuces. Les plus transposables : *sleep*, c'est-à-dire figer 1 à 2 frames sur un kill ou un impact (« pausing the action for a frame or a couple of frames when enemies die »), screenshake, kickback de l'arme, knockback de l'ennemi, impacts permanents et gros projectiles lisibles. Sources : [vidéo](https://www.youtube.com/watch?v=AJdEqssNZ-U), [résumé Blue Tengu](https://www.bluetengu.com/2014/12/12/art-of-screenshake-experiments/). **Adaptation PvP** : on ne fige jamais la simulation en multijoueur. Le « sleep » se réserve aux couches cosmétiques locales (victime ragdoll, mot-bruit, impact).
- **Squirrel Eiserloh, « Juicing Your Cameras With Math »** (GDC 2016) :
  - un modèle de *trauma* dans [0,1], incrémenté par les événements (+0,2 à +0,5) et décroissant **linéairement** ;
  - amplitude du shake = **trauma² ou trauma³** ;
  - en 3D, shake **rotationnel uniquement** (le translationnel est jugé « super lame ») ;
  - bruit de **Perlin** plutôt que du random pur (plus doux, gère pause et slow-mo).
  
  Sources : [texte du talk](https://archive.org/stream/GDC2016Eiserloh/GDC2016-Eiserloh_djvu.txt), [GDC Vault](https://gdcvault.com/play/1023146/Math-for-Game-Programmers-Juicing). Godot 4.7 fournit `FastNoiseLite` pour le Perlin.
- **Doom 2016** (GDC 2018, Loudy & Campbell, « push forward combat ») : ce sont le rythme et la lisibilité du retour (stagger, glory kill) qui rendent le combat bon, pas un effet isolé. [gamedeveloper.com](https://www.gamedeveloper.com/design/video-the-combat-design-of-i-doom-i-).

### 2.2 Recul, dispersion, précision au premier tir, ADS

- **Valorant**, trois sources d'imprécision : premier tir, erreur de tir (spray) et erreur de mouvement. [gamer.org](https://www.gamer.org/valorant-gun-mechanics-explained-accuracy-spray-movement/)
  - Vandal : 0,25° au premier tir à la hanche, 0,157° en ADS. [Sportskeeda](https://www.sportskeeda.com/valorant/valorant-rising-frustrations-vandal-s-first-shot-accuracy-pushing-players-use-phantom)
  - À l'arrêt 0,2°, en marche 3°, en course 6,2°, accroupi 0,17°. Le patch 6.11 porte la course des fusils à 6. [Sportskeeda](https://sportskeeda.com/valorant/all-run-gun-changes-valorant-patch-6-11)
  - Course à 6,75 m/s, marche à 3,8 m/s. Précision retrouvée sous **30 % de la vitesse** (deadzone), transition course→marche en **55 ms**. [BattlePooja](https://battlepooja.com/movement-guide/), [support Riot](https://support-valorant.riotgames.com/hc/en-us/articles/4414682724755-Walking-Running-and-Crouching)
- **Leçon pour nous** : la pénalité de mouvement doit être **continue en fonction de la vitesse**, avec une zone morte basse, et non un booléen « bouge > 0,5 m/s ». Le motif de recul n'a de sens que s'il **s'accumule** pendant le spray. La récupération démarre à l'arrêt du tir (ou après un délai d'environ un intervalle de tir).

### 2.3 TTK

- Valorant (Vandal) : 1 tête = 0 ms, 4 corps ≈ 270-310 ms. CS2 : environ 200 ms. Battlefield 6 : environ 166 ms. Apex : 2,1-2,7 s. Overwatch : 1-3 s. Halo Infinite : Sidekick optimal environ 1,1 s. Sources : [synthèse TTK](https://www.blueberries.gg/halo/halo-infinite-ttk/), [Apex TTK](https://esports.gg/guides/apex-legends/apex-ttk-season-10-time-to-kill-by-bears-say-meow/), docs/ROADMAP.md §4 (BO6 165-350 ms).
- Nos armes principales tuent au corps en **385-430 ms**, et en **285-300 ms** avec des headshots (docs/BALANCE.md). C'est cohérent avec le pilier « les capacités comptent ».
- **Attention** : le TTK *effectif* est dominé par la précision réelle. Avec des hitbox fausses et sans lag comp (voir §4), le TTK ressenti explose, et c'est ce que le joueur perçoit comme « pas jouable ».

### 2.4 Confirmation de touche et de kill (visuel + audio)

- **Valorant** : les résultats de tir sont 100 % serveur. Le client affiche le traceur tout de suite, mais le hit-confirm et les VFX de hit arrivent après un **RTT** (ping 40 ms = 80 ms de délai). Le serveur rembobine positions **et poses d'animation** au timestamp client. La plupart des « bugs de hitreg » signalés sont des problèmes de **lisibilité**, pas de calcul (ex. l'impact s'affiche à l'endroit où l'ennemi s'est ensuite accroupi). [The State of Hit Registration](https://playvalorant.com/en-us/news/dev/the-state-of-hit-registration/)
- **Séparation standard** : on prédit localement ce qui est certain (tir, muzzle flash, son, recul, décalque ou impact décoratif). On attend le serveur pour ce qui a des conséquences (hitmarker, PV, kill). [The art of Hit Registration](https://danieljimenezmorales.github.io/2023-10-29-the-art-of-hit-registration/)
- **CS2** propose une *prédiction de dégâts* optionnelle : effets de hit joués tout de suite, au risque de se tromper parfois.
- **Overwatch** : le « hit-pip » a été conçu pour **percer le mix** sans ressembler à un héros. Il est satisfaisant (une canette de bière inversée). Le jeu a été construit sur le pilier « Play by Sound ». Sources : [Kotaku](https://kotaku.com/the-sound-of-a-hit-in-overwatch-is-made-by-beer-1778482754), [GDC Vault](https://gdcvault.com/play/1023317/Overwatch-The-Elusive-Goal-Play). Les joueurs se plaignent quand le son de crit est **masqué par le tir** ([forum](https://us.forums.blizzard.com/en/overwatch/t/crit-sound-getting-masked-by-gunshot/662522)) : il faut donc du ducking.

### 2.5 Audio d'arme en couches

- Un tir de joueur se compose d'un **transitoire** (le claquement), d'un **corps** (le poids), d'une couche **mécanique**, d'une **queue** (réverbération selon le lieu : intérieur, extérieur, rue) et d'un **sub** réservé à l'arme du joueur local pour la puissance. [Splice](https://splice.com/blog/design-weapon-sound-video-games/), [A Sound Effect](https://www.asoundeffect.com/supreme-scifi-weapon-sound-effects/)
- Nous avons un seul échantillon par arme (3 variations + `_far`), sans queue selon l'environnement ni sub local. `dry_fire_*.wav` existe mais n'est **jamais joué**.

### 2.6 Latence d'entrée, prédiction du tir, favor-the-shooter

- **Valorant** : `peeker's advantage = RTT + buffering serveur (2 frames) + buffering client (3 frames)`. Cela donne **141 ms** de base, ramenés à environ **71-100 ms** avec 128 tick, 35 ms de ping et 144 fps. Mouvement en pas fixe, identique client et serveur. [Peeking into VALORANT's Netcode](https://www.riotgames.com/en/news/peeking-valorants-netcode)
- **Rembobinage** : `instant du tir = temps serveur − RTT moyen − délai d'interpolation client`. Plafonds utilisés : **250 ms** (Battlefield 4, Overwatch) et **500 ms** (CoD IW). Au-delà, le tireur doit anticiper. [The art of Hit Registration](https://danieljimenezmorales.github.io/2023-10-29-the-art-of-hit-registration/). Notre roadmap vise 200 ms, ce qui est raisonnable.
- **CS2 sub-tick** : le serveur reste à 64 Hz, mais chaque entrée est horodatée *entre* deux ticks et le tir est évalué à cet instant exact. [DMarket](https://dmarket.com/blog/cs2-tick-rate/). Pour nous : envoyer avec chaque tir un horodatage fin (tick + fraction), pas seulement le tick.
- **Overwatch** (GDC 2017, Tim Ford) : prédiction client massive, serveur autoritaire, ECS, et dilatation du temps client quand le buffer serveur se vide. [GDC Vault](https://www.gdcvault.com/play/1024001/-Overwatch-Gameplay-Architecture-and), [Edgegap](https://edgegap.com/blog/game-backend-deep-dive-overwatch-2016-netcode-architecture-rollback)
- **Latence locale** : NVIDIA Research mesure des gains d'aim même **sous 20 ms** de latence système ([arXiv 2105.10498](https://arxiv.org/pdf/2105.10498)). Donc : souris traitée dans `_process` ou `_input`, jamais retardée au tick physique. Proposer un plafond fps et le mode VSync off.
- **Godot 4.7, interpolation physique** : pour une caméra FPS, placer la caméra en position **interpolée** (`get_global_transform_interpolated()`) mais appliquer la **rotation souris sans interpolation**, avec `physics_interpolation_mode = OFF` et `top_level`. [docs Godot](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html), [issue #102142](https://github.com/godotengine/godot/issues/102142) (bug si fps < tick).

### 2.7 Mouvement

- **Coyote time et jump buffer** : environ **100 ms** de coyote est la norme (Celeste : 5 frames ≈ 83 ms, Mario Odyssey : 8 frames). Jump buffer de **67-150 ms** (Celeste : 4 frames, Odyssey : 6 frames). [GameJuice](https://www.gamejuice.co.uk/articles/coyote-time-input-buffering), [MyGameDesign](https://www.mygamedesign.com/what-makes-jump-mechanics-feel-responsive-and-satisfying/). Nos valeurs (80 ms / 100 ms) sont dans la fourchette, à peine serrées.
- **Apex / Titanfall** : sauter depuis un slide conserve mieux l'élan que sauter depuis un sprint. Le bhop existe parce que la friction ne s'applique qu'au sol. Respawn surveille les capacités qui combinent vitesse et évasion, car elles rendent la cible **impossible à suivre**. [Dot Esports](https://dotesports.com/apex-legends/news/apex-legends-season-29-developer-axle-interview), [GameRiv](https://gameriv.com/respawn-says-movement-is-still-core-to-apex-legends-as-mobility-balance-changes-continue/)
- **Valorant** : l'arrêt est quasi instantané au relâchement. Le counter-strafe ne gagne qu'un résidu, et la précision se joue sur la **vitesse** (deadzone 30 %).
- **Step-up (Godot)** : `move_and_slide()` ne monte pas les marches ([proposition #2751](https://github.com/godotengine/godot-proposals/issues/2751)). La solution de référence est `PhysicsServer3D.body_test_motion()` avec la forme du joueur (monter, avancer, redescendre), plus un lissage de la caméra. Deux références : [Godot-Stair-Step-Demo](https://github.com/kelpysama/Godot-Stair-Step-Demo) (Asset Library [#2481](https://godotengine.org/asset-library/asset/2481)), qui recommande Jolt (déjà utilisé chez nous), et [Character Step](https://godotengine.org/asset-library/asset/4093). Explication détaillée : [dresswithpockets](https://dresswithpockets.github.io/2025/03/19/godot-stair-stepping.html).
- **Fun contre flottant** : un sol sec avec arrêt net (déjà fait, `ground_accel` 85 / `ground_friction` 75), une gravité de descente plus forte (fait, ×1,25), une réception lisible (dip caméra et son d'atterrissage, **absents**) et **aucune perte de contrôle longue**. Le stun de chute jusqu'à 2,5 s va à l'encontre de ce dernier point.

## 3. Chiffres de référence

| Sujet | Référence | Chez nous | Verdict |
|---|---|---|---|
| Peeker's advantage | 141 ms de base, 71-100 ms optimisé (Valorant) | non mesuré, 60 Hz, pas d'interpolation | à mesurer (P1.9) |
| Plafond de rembobinage | 250 ms (BF4/OW), 500 ms (IW) | pas de rembobinage | **manquant** (GF-01) |
| Délai du hit-confirm | = RTT (Valorant) | = RTT | OK |
| Tick simulation | 128 (Valorant), 64 + sub-tick (CS2), 63 (OW) | 60, pas d'horodatage fin | OK pour la gray-box |
| TTK corps, arme principale | 166-350 ms (BF6, BO6, Vandal), 1-3 s (OW, Apex) | 385-430 ms | OK (piliers capacités) |
| TTK tête | 0 (Vandal 1 HS), environ 150-300 ms | 285-300 ms | OK |
| Premier tir | Vandal 0,25° hanche, 0,157° ADS | Ravage 2,0° hanche, 0,25° ADS | la hanche est volontairement « CoD » ; à expliquer via le réticule |
| Imprécision en mouvement | 0,2 / 3 / 6,2° (arrêt / marche / course, Valo) | +1,0° booléen au-delà de 0,5 m/s | **à rendre continue** (MV-02) |
| Deadzone de précision | < 30 % de la vitesse de course | aucune | MV-02 |
| Vitesse de course | 6,75 m/s (Valo), 5,5-6,4 m/s (CS) | 8,2 m/s (sprint auto) | arène rapide, assumé |
| Coyote / buffer | 83-133 ms / 67-150 ms | 80 / 100 ms | OK, passer à 100 / 120 ms |
| Shake caméra | trauma², décroissance linéaire, rotation seule | aucun | **manquant** (GF-08) |
| Hitstop | 1-2 frames (Vlambeer) | aucun | cosmétique uniquement (GF-10) |
| Durée du hitmarker | 120-200 ms | 160 ms | OK |
| Latence locale | gains même < 20 ms (NVIDIA) | souris en `_unhandled_input` (OK), caméra au tick | GF-03 |

## 4. Écarts avec notre code

1. **Aucune compensation de lag.** `scripts/combat/Weapon.gd:397-403` le reconnaît en commentaire, et `_resolve_ray` (`Weapon.gd:619-635`) raycaste contre les positions serveur *courantes*. **Impact** : à 50-100 ms de ping, une cible qui strafe à 8 m/s s'est déplacée de 0,4 à 0,8 m. Le tir visé au centre rate, ce qui explique le ressenti « le jeu bug ».
2. **Joueurs distants non interpolés.** `scenes/player/player.tscn:34-42` réplique `position`, `rotation` et `velocity` bruts (`replication_mode = 1`), sans buffer de snapshots. **Impact** : saccades des ennemis, cible difficile à suivre, et aucune base de temps commune pour le rembobinage.
3. **Caméra saccadée.** `project.godot` (section `[physics]`, lignes 249-251) : 60 Hz, sans `physics_interpolation`. La caméra est enfant de `Head` et bouge dans `PlayerController._physics_process` (`PlayerController.gd:191-221`). **Impact** : micro-saccades à 144 Hz, sensation de « jeu pas fini ».
4. **Hitbox fausses.**
   - `WeaponMath.gd:10,23-24` : headshot si `hit_y > origin + 1.4`, alors que l'accroupi mesure 0,9 m (`docs/MOVEMENT.md` §11). Tête accroupie **impossible à headshot**.
   - `PlayerController._update_crouch_height` (`PlayerController.gd:504-512`) ne tourne que chez le propriétaire, donc la capsule serveur d'un humain accroupi reste debout.
   
   **Impact** : on touche de l'air au-dessus d'un joueur à couvert, et pas de headshot sur un joueur accroupi, que ce soit un humain ou un bot.
5. **Recul lissé.** `PlayerController.gd:105-112` fait revenir la cible de recul vers 0 à chaque frame (`recoil_recovery` 6,5 pour le Ravage), y compris pendant le spray. À 10 tirs/s, environ 50 % du kick disparaît entre deux balles : le motif fixe (`ravage.tres`, 6 tirs) est quasi effacé. **Impact** : le spray ne s'apprend pas, les armes se ressemblent toutes.
6. **Traceur illisible et faux.** Il part de `camera.global_position` (`Weapon.gd:228`), c'est-à-dire du centre de l'écran : vu par le tireur, c'est un point. Il va jusqu'à `max_range` (`Weapon.gd:244-245`, `452-454`) et traverse donc les murs. Aucun impact n'est prédit localement. **Impact** : pas de retour visuel de « où est partie ma balle ».
7. **Dispersion carrée, axes mondiaux.** `Weapon.gd:258-263` tire `randf_range` indépendamment sur deux axes (distribution carrée, coins surreprésentés) et tourne autour de `Vector3.UP` au lieu de l'axe haut de la caméra. **Impact** : cône faussé en regardant haut ou bas.
8. **Imprécision de mouvement booléenne.** `Weapon.gd:231` (`moving := horizontal_speed() > 0.5`) et `WeaponFeel.gd:30-36`. **Impact** : aucune récompense pour l'arrêt ou le counter-strafe, et aucune différence entre 1 m/s et 12 m/s en slide.
9. **Réticule statique.** `GameHUD.gd:89-99` dessine des traits fixes. **Impact** : la dispersion réelle (hanche 2° + mouvement + air) est invisible.
10. **Confirmations par plomb et kill deviné.**
    - `_resolve_ray` émet un `hit_confirmed` par rayon (`Weapon.gd:635-644`, `677-680`) : le Fracas (12 plombs) donne 12 sons `hitmarker` (`Audio.gd:538-542`) et 12 chiffres superposés.
    - Le kill est déduit d'une fenêtre de 0,35 s (`HitFeedback.gd` `KILL_MATCH_WINDOW`, `GameHUD.gd:285-293`).
    
    **Impact** : bruit, et croix de kill manquée ou erronée.
11. **Pas de shake, pas de kick FOV.** `PlayerCamera.gd:46-110` ne gère que le FOV, le tilt, le bob, la roulade et le stun. **Impact** : les tirs et les dégâts reçus manquent de poids. Le ViewModel a un ressort de recul, mais la caméra reste inerte.
12. **Pas de flash ni de réaction sur la cible touchée.** Rien côté `PlayerLook.gd` / `CharacterAnimator.gd` à la réception de dégâts. **Impact** : on ne « voit » pas le hit sur le personnage, alors que le style cel-shadé Borderlands s'y prête parfaitement.
13. **Semi-auto sans buffer d'entrée.** `Weapon.gd:173-174` et `FireClock.tick()` : un clic arrivé 20 ms avant la fin de l'intervalle est **perdu**. **Impact** : « j'ai cliqué et rien ne s'est passé » sur le Marqueur, le Magnum ou le Faucheur.
14. **Pas de son à vide.** `dry_fire_*.wav` n'est câblé nulle part (grep vide). **Impact** : aucun retour quand le chargeur est vide.
15. **Pas de step-up.** `PlayerController.gd` s'appuie uniquement sur `move_and_slide` et `floor_snap_length = 0.4` (l. 156). **Impact** : blocages sur les marches et rebords (bots compris), perçus comme des « bugs partout ».
16. **Stun de chute long.** `MovementConfig` : `fall_min_height` 4 m, stun de 0,5 à 2,5 s (`docs/MOVEMENT.md` §8). **Impact** : perte de contrôle totale en plein combat, frustrante en compétitif.
17. **Pas de retour d'atterrissage.** Pas de dip caméra, et aucun son d'atterrissage dans `assets/audio/sfx`. **Impact** : les sauts paraissent « flottants » malgré la gravité ×1,25.
18. **ADS sans ralentissement.** Aucun état ne lit `input.aim_held` pour la vitesse. **Impact** : on strafe à 8,2 m/s en ADS avec 1,25° de dispersion, ce qui donne un run-and-gun laser et un mouvement de visée incohérent.

## 5. Tâches

```
- id: GF-01
  title: "Compensation de lag serveur (historique des hitbox + rembobinage plafonné à 200 ms)"
  files: [scripts/combat/LagCompensation.gd, scripts/combat/Weapon.gd, scripts/combat/ShotValidator.gd, tests/combat/test_lag_compensation.gd]
  depends_on: [GF-02, GF-04]
  size: L
  acceptance: "le client envoie avec chaque tir un horodatage (tick + fraction) ; le serveur garde un historique de >= 250 ms des transforms/hauteurs de capsule de chaque joueur, rembobine à (horodatage - délai d'interpolation), raycaste, puis restaure ; test auto avec 100 ms de latence simulée et cible en strafe à 8 m/s → >= 95 % des tirs visés sur la position rendue sont des hits ; tir plus vieux que 200 ms → résolu au plafond (pas plus loin) ; si P1 adopte netfox, utiliser son historique au lieu d'un buffer maison."

- id: GF-02
  title: "Interpolation des joueurs distants (buffer de snapshots ~2 ticks)"
  files: [scripts/networking/RemoteInterpolator.gd, scenes/player/player.tscn, scripts/player/PlayerController.gd, tests/networking/test_remote_interpolator.gd]
  depends_on: []
  size: M
  acceptance: "les pairs distants rendent position/rotation interpolées entre les deux derniers snapshots reçus avec un délai fixe (réglable, défaut 2 ticks = 33 ms) ; test : snapshots à 60 Hz d'un mouvement rectiligne à 8 m/s avec 20 % de gigue → écart max rendu vs trajectoire vraie < 5 cm, aucun saut arrière ; le délai est exposé (utilisé par GF-01)."

- id: GF-03
  title: "Interpolation physique + caméra FPS lisse (position interpolée, rotation souris immédiate)"
  files: [project.godot, scripts/player/PlayerCamera.gd, scripts/player/PlayerController.gd]
  depends_on: []
  size: M
  acceptance: "physics/common/physics_interpolation=true ; la caméra lit la position via get_global_transform_interpolated() dans _process et applique la rotation souris sans interpolation (docs Godot 'advanced physics interpolation') ; mesure en jeu à 144 fps / 60 Hz, strafe à vitesse constante : écart-type du déplacement caméra frame à frame < 10 % de la moyenne (avant : motif 3-2 visible) ; le ViewModel ne tremble pas."

- id: GF-04
  title: "Hitbox serveur fiables (tête dédiée + accroupi répliqué)"
  files: [scripts/combat/WeaponMath.gd, scripts/combat/Weapon.gd, scripts/player/PlayerController.gd, scenes/player/player.tscn, tests/combat/test_weapon_math.gd]
  depends_on: []
  size: M
  acceptance: "`is_crouching`/`current_height` répliqués (always) et appliqués à la capsule sur le serveur ; headshot déterminé par une forme 'tête' dédiée (ou seuil relatif à current_height, pas 1.4 m fixe) ; tests : tir sur la tête d'une cible accroupie → headshot ; tir 10 cm au-dessus d'une tête accroupie → aucun hit ; tir sur la tête debout → headshot."

- id: GF-05
  title: "Recul lisible (motif qui s'accumule, récupération après l'arrêt du tir)"
  files: [scripts/player/PlayerController.gd, scripts/combat/WeaponFeel.gd, scripts/combat/WeaponConfig.gd, scripts/combat/Weapon.gd, tests/combat/test_weapon_feel.gd]
  depends_on: []
  size: M
  acceptance: "nouveau champ `recoil_recovery_delay` (défaut = 1 intervalle de tir + 50 ms) ; aucune récupération tant que l'on tire ; test : 6 tirs de Ravage sans mouvement souris → décalage vertical cumulé = somme(recoil_pattern.y) ± 5 % ; relâché → retour à < 10 % du cumul en <= 0.5 s ; hanche vs ADS respecte recoil_aim_mult."

- id: GF-06
  title: "Traceurs du canon jusqu'au point d'impact + impact prédit localement"
  files: [scripts/combat/Weapon.gd, scripts/combat/ImpactFx.gd, scripts/player/ViewModel.gd, scripts/player/ThirdPersonWeapon.gd]
  depends_on: []
  size: M
  acceptance: "le rayon logique part toujours de la caméra, mais le traceur est dessiné du muzzle du ViewModel (local) ou du ThirdPersonWeapon (distant) jusqu'au premier impact d'un raycast local (même masque SHOT_MASK) ; test : tir contre un mur à 5 m → extrémité du traceur à < 2 cm du point d'impact ; un effet d'impact cel-shadé (éclat + tache d'encre 3 s, pool max 64) apparaît dans la même frame que le tir."

- id: GF-07
  title: "Une confirmation par tir (plombs agrégés) avec drapeau kill envoyé par le serveur"
  files: [scripts/combat/Weapon.gd, scripts/ui/GameHUD.gd, scripts/ui/hud/HitFeedback.gd, scripts/core/Audio.gd, tests/ui/test_hit_feedback.gd]
  depends_on: []
  size: S
  acceptance: "`hit_confirmed(pos, total_dmg, headshot, is_kill)` émis UNE fois par tir et par cible (somme des plombs) ; test Fracas 12 plombs sur une cible → 1 son hitmarker, 1 chiffre = somme ; is_kill vient du serveur (Health mort dans la même résolution), KILL_MATCH_WINDOW supprimé ; chiffres empilés par cible sur 0.4 s (façon Borderlands/Apex : le chiffre grossit au lieu de se superposer)."

- id: GF-08
  title: "Shake caméra à trauma (Eiserloh) + punch FOV sur tir / dégâts reçus / kill"
  files: [scripts/player/CameraShake.gd, scripts/player/PlayerCamera.gd, scripts/core/Settings.gd, tests/player/test_camera_shake.gd]
  depends_on: [GF-03]
  size: S
  acceptance: "CameraShake pur : trauma ∈ [0,1], décroissance linéaire (défaut 1.5/s), amplitude = trauma², rotation seule (yaw/pitch/roll via FastNoiseLite), max 1.2° ; ajouts : tir (0.08-0.25 selon arme, champ WeaponConfig), dégât reçu (0.3), explosion proche (0.6) ; punch FOV -1.5° en 60 ms au tir des armes lourdes ; réglage 'intensité' 0-100 % et reduced-motion → 0 ; tests purs sur la courbe."

- id: GF-09
  title: "Réticule dynamique qui montre la dispersion réelle"
  files: [scripts/ui/hud/Crosshair.gd, scripts/ui/GameHUD.gd, scripts/combat/WeaponFeel.gd, tests/ui/test_crosshair.gd]
  depends_on: [MV-02]
  size: S
  acceptance: "écart des traits (px) = tan(spread) / tan(fov_v/2) × hauteur_écran/2 ± 1 px, recalculé chaque frame depuis la même fonction que le tir ; bloom visible au spray ; masqué en ADS/lunette comme aujourd'hui ; option 'réticule statique' dans les réglages."

- id: GF-10
  title: "Réaction visible de la cible (flash de hit cel-shadé + flinch) et micro-hitstop cosmétique au kill"
  files: [scripts/player/PlayerLook.gd, scripts/player/CharacterAnimator.gd, scripts/combat/Health.gd]
  depends_on: [GF-07]
  size: M
  acceptance: "à chaque dégât confirmé, le mesh de la victime flashe (rim blanc, ou rouge pour un headshot) 70 ms chez TOUS les pairs ; petit recul additif du haut du corps 120 ms ; au kill, la pose de la victime se fige 50 ms avant le ragdoll/la disparition (jamais la simulation) ; visible en 3e personne sur un bot au stand de tir."

- id: GF-11
  title: "Audio d'arme en couches + mix priorisé (hit/kill jamais masqués)"
  files: [scripts/core/Audio.gd, default_bus_layout.tres, tools/audio/gen_weapon_layers.py, tests/audio/test_audio_mix.gd]
  depends_on: [GF-07]
  size: M
  acceptance: "tir local = transitoire + corps + mécanique + sub (local seulement) + queue intérieur/extérieur (raycast plafond) ; bus 'Feedback' (hitmarker/headshot/kill) avec sidechain/ducking -4 dB sur le bus des tirs pendant 120 ms ; pas ennemis +3 dB vs alliés ; son de réception d'atterrissage ; test pur : sélection de la queue et règles de ducking."

- id: GF-12
  title: "Buffer d'entrée pour armes semi-auto + clic à vide"
  files: [scripts/combat/Weapon.gd, scripts/combat/FireClock.gd, scripts/core/Audio.gd, tests/combat/test_fire_clock.gd]
  depends_on: []
  size: S
  acceptance: "un fire_pressed reçu pendant le cooldown est mémorisé 120 ms et tire dès que l'intervalle est écoulé (test : clic à 90 % de l'intervalle → 1 tir exactement à 100 %) ; jamais plus d'un tir bufferisé ; gâchette sur chargeur vide avec réserve 0 → dry_fire joué (1 par appui)."

- id: GF-13
  title: "Dispersion en disque, dans le repère caméra"
  files: [scripts/combat/Weapon.gd, scripts/combat/WeaponFeel.gd, tests/combat/test_weapon_feel.gd]
  depends_on: []
  size: S
  acceptance: "fonction pure `spread_dir(base_dir, cam_basis, spread_rad, rng)` : angle uniforme, rayon sqrt(u) (ou gaussien tronqué), rotation autour des axes X/Y de la caméra ; test sur 10 000 tirages : 100 % dans le cône, densité des coins du carré englobant ≈ 0, pitch à ±80° → cône toujours circulaire."

- id: GF-14
  title: "Hitmarker prédit (option, façon 'damage prediction' CS2)"
  files: [scripts/combat/Weapon.gd, scripts/ui/GameHUD.gd, scripts/core/Settings.gd]
  depends_on: [GF-07, GF-06]
  size: S
  acceptance: "option désactivée par défaut ; activée → le raycast local qui touche une hitbox joue immédiatement un hitmarker 'léger' (sans son de kill ni chiffre) ; le hit confirmé serveur garde la version pleine ; les kills ne sont jamais prédits."

- id: MV-01
  title: "Montée et descente de marches (step-up/step-down via body_test_motion)"
  files: [scripts/player/StairStep.gd, scripts/player/PlayerController.gd, scripts/movement/MovementConfig.gd, tests/player/test_stair_step.gd]
  depends_on: []
  size: M
  acceptance: "max_step_up 0.4 m, max_step_down 0.4 m (MovementConfig) ; en sprint contre une marche de 0.3 m → montée sans perte de vitesse > 10 % ; marche de 0.5 m → bloque ; descente d'escalier sans passer en état Air ; la tête (caméra) lisse le saut vertical sur ~80 ms ; fonctionne aussi pour les bots (même contrôleur)."

- id: MV-02
  title: "Imprécision de mouvement continue avec zone morte (façon Valorant) + ADS qui ralentit"
  files: [scripts/combat/WeaponFeel.gd, scripts/combat/WeaponConfig.gd, scripts/combat/Weapon.gd, scripts/player/states/Sprint.gd, scripts/player/states/Walk.gd, scripts/movement/MovementConfig.gd, tests/combat/test_weapon_feel.gd]
  depends_on: []
  size: M
  acceptance: "spread_mouvement = move_spread_add × smoothstep(deadzone, 1, vitesse / sprint_speed), deadzone défaut 0.3 ; test : à 0.25 × sprint → 0 pénalité ; à 1.0 → pénalité pleine ; slide → pénalité × 1.3 ; en ADS la vitesse cible est multipliée par `ads_move_mult` (défaut 0.7) et le sprint auto est suspendu."

- id: MV-03
  title: "Stun de chute adouci (perte de contrôle courte, désactivé en Duel/Duo/SnD)"
  files: [scripts/movement/MovementConfig.gd, resources/movement/default_movement.tres, scripts/player/states/Stun.gd, scripts/modes/GameMode.gd]
  depends_on: []
  size: S
  acceptance: "fall_min_height 6 m, stun_max_time 0.6 s, pendant le stun le joueur peut viser et tirer avec +3° de dispersion (plus de freeze total) ; propriété `fall_stun_enabled` du mode = false en Duel/Duo/SnD ; test : chute de 5 m → aucun stun ; 14 m → 0.6 s."

- id: MV-04
  title: "Retour d'atterrissage (dip caméra + son) et réglages de confort"
  files: [scripts/player/PlayerCamera.gd, scripts/core/Audio.gd, resources/movement/default_movement.tres, scripts/core/Settings.gd]
  depends_on: []
  size: S
  acceptance: "à l'atterrissage, dip caméra de 0 à 6 cm proportionnel à la vitesse de chute, retour en 150 ms (easeOut) ; son land_soft/land_hard ; coyote_time 0.10, jump_buffer_time 0.12 ; option 'head-bob' 0-100 % (défaut 50 %) ; reduced-motion coupe dip et bob."```
