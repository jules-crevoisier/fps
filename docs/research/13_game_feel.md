# 13 — Game feel v2 : armes, animations, retour de tir

> Recherche et plan du 25/09/2026 (Godot 4.7, serveur autoritaire, bots, 6 agents). Demande utilisateur :
> « focus sur les armes, les animations — c'est ça qui est intéressant — et le game feel ». Cible : arène
> rapide et « juteuse » (Far Far West pour le jus en première personne, COD / Apex / Valorant pour le tir).
> Ce document **prolonge** `01_game_feel.md` (fiabilité, lag comp, hitbox : déjà traités) et **s'imbrique**
> dans `12_viewmodel_v2.md` (FP-10 à FP-20 : mains, armes, clips cuits). Il ne refait ni l'un ni l'autre.

## 0. En cinq lignes

1. **L'arme ne « cogne » pas.** Mesuré : le recul visible du viewmodel vaut **0,04° et 0,05 mm** sur le Ravage
   (pic à 90 ms), la secousse caméra au tir **0,01°**, le flash est un carré fixe de 12 cm, le traceur une ligne
   d'**1 pixel**. Aucune douille, aucune fumée. Tout le « poids » repose sur le son.
2. **Le motif de recul est effacé** : la visée récupère pendant le spray, le Ravage ne monte que de **1,07° sur
   4,05° prévus (26 %)**. En plus, le recul avance au tick physique (60 Hz), donc par paliers à 144 Hz.
3. **La cadence des automatiques boite** : les tirs tombent sur les ticks à 60 Hz. La Rafale alterne
   **66,7 / 83,3 ms** au lieu de 76,9 ms, ce qui s'entend. L'ADS désynchronise le zoom (≈ 135 ms) et l'arme
   (120 à 380 ms), et la sensibilité en visée n'est pas mise à l'échelle du zoom (lunette du Faucheur ×2,84).
4. **L'audio est entièrement synthétisé, et bien structuré pour le tir local** (5 couches + queue). Il manque :
   des couches à hauteur commune, des tirs ennemis en couches et spatialisés, les impacts, les sifflements
   de balles, l'indice de fin de chargeur et l'escalade sonore des kills.
5. **Le plan : 11 tâches GF-40 à GF-50 et 3 tâches existantes à remonter.** Il faut d'abord un **banc de
   mesure** (GF-40) et un **socle de profils par arme** (GF-41). Viennent ensuite, en parallèle, recul, caméra,
   VFX et sons, puis le branchement dans `ViewModel.gd`, `Weapon.gd` et `Audio.gd` **après FP-14**, qui
   possède ces fichiers. Priorités remontées : GF-14 (hitmarker prédit) et ART-43 (élimination « REMBALLÉ »).

---

## 1. Audit de l'existant (lecture seule, mesures reproductibles)

### 1.1 Méthode

- **Lecture du code** (`fichier:ligne` cités ci-dessous).
- **Sonde headless jetable** (non versionnée, script du dossier temporaire de session). Elle exécute les
  **vraies** classes `ViewModel.AnimState`, `FireClock`, `WeaponFeel` et les `.tres`. Elle reproduit à 60 Hz la
  formule de recul caméra de `PlayerController._update_recoil` (`PlayerController.gd:183-190`). Le viewmodel
  est simulé à 144 i/s.
- **`tools/review/gameplay_probe.gd`** : 43/49 contrôles verts.
  - Tir accepté dans tous les états sauf Dive et Roll (voulu) ; glissade OK depuis GF-30 ; rechargement,
    changement d'arme et ADS OK.
  - Les 6 échecs portent sur les capacités de Roseau et Verrou, hors périmètre de ce document.
- **Audit audio / VFX / HUD délégué**, avec mesures WAV via le module `wave` (durée, crête, RMS).

**Mesures de la sonde** (hanche, sans mouvement de souris) :

| Arme | Kick VM (tangage) | Kick VM (recul) | Pic | Montée caméra / motif prévu | Intervalles de tir mesurés (cible) |
|---|---|---|---|---|---|
| Pistolet | 0,026° | 0,03 mm | 90 ms | 0,29° / 1,05° (27 %) | 133 / 150 ms (148) |
| Ravage | 0,041° | 0,05 mm | 90 ms | **1,07° / 4,05° (26 %)** | 100 ms (100) |
| Rafale | 0,030° | 0,04 mm | 90 ms | 0,85° / 3,00° (28 %) | **66,7 / 83,3 ms (76,9)** |
| Éclair | 0,026° | 0,03 mm | 90 ms | 0,65° / 2,75° (23 %) | **83,3 / 100 ms (94,3)** |
| Semeuse | 0,045° | 0,06 mm | 90 ms | 1,38° / 4,35° (31 %) | **83,3 / 83,3 / 100 ms (90,9)** |
| Magnum | 0,097° | 0,12 mm | 90 ms | 0,79° / 2,10° (37 %) | 450 ms (454,5) |
| Fracas | 0,135° | 0,17 mm | 90 ms | 1,34° / 2,00° (66 %) | — |
| Faucheur | 0,165° | 0,21 mm | 90 ms | 2,42° / 3,50° (69 %) | — |

### 1.2 Tir : cadence, dispersion, recul, ADS, rechargement, TTK

**Cadence.**
- `FireClock` avance dans `Weapon._physics_process` (`Weapon.gd:167-171`, `:326`).
- L'entrée est lue au tick physique (`PlayerInput.gd:77-91`, `:140-141`).
- Chaque tir tombe donc sur une frontière de tick de 16,7 ms. D'où l'alternance mesurée plus haut (±8,3 ms :
  on entend le rythme boiter) et 0 à 16,7 ms de latence ajoutée.
- Le buffer semi-auto de 120 ms (GF-12) est correct.

**Dispersion.**
- Disque dans le repère caméra (GF-13, `WeaponFeel.gd:176-186`) et pénalité de mouvement continue avec zone
  morte (MV-02) : c'est sain.
- Pas de dispersion qui grandit pendant le spray : c'est le motif de recul qui porte le spray, un choix cohérent.
- Le réticule est **déjà dynamique** (`GameHUD.gd:402-419`, `Crosshair.gd:174`), même si GF-09 est encore
  « todo ».
- Écart restant : le réticule ignore la pénalité de Stun (+3°) et Sang-froid (`GameHUD.gd:416` contre
  `Weapon.gd:451`).

**Recul.**
- Les données de motif existent (`ravage.tres` : 6 tirs, `recoil_pattern`).
- Trois défauts :
  - la cible revient vers 0 **à chaque tick, y compris pendant le spray** (`PlayerController.gd:185`,
    `recoil_recovery` 6,5) ;
  - chaque kick est lissé à 22/s (`:186`), donc environ 100 ms pour 90 % de l'effet ;
  - tout est appliqué au tick physique (`:368`), en paliers de 60 Hz.
- **GF-05 (todo) décrit déjà le correctif** : motif cumulé, récupération après l'arrêt du tir.

**ADS.**
- Le FOV converge en exponentielle à 16/s (`PlayerCamera.gd:236`) : 90 % en ≈ 135 ms, quelle que soit l'arme.
- L'arme se centre en linéaire sur `ads_time` (`ViewModel.gd:513-514`, `WeaponFeel.gd:153-155`) : de 120 à
  380 ms. Sur le Faucheur, le zoom est fini à 135 ms et l'arme arrive à 380 ms.
- Aucune accélération (easing).
- `WeaponConfig.aim_speed` n'est lu nulle part : c'est un champ mort.
- La sensibilité en visée n'est **pas** mise à l'échelle du zoom (`PlayerController.gd:644-645`, multiplicateur
  1,0 par défaut en `Settings.gd:200`). Rapports de zoom au FOV horizontal de 103°, soit 70,5° vertical :

  | Arme | Rapport de zoom |
  |---|---|
  | Pistolet, Fracas, Éclair | 1,0× |
  | Rafale | 1,05× |
  | Magnum | 1,18× |
  | Ravage | 1,23× |
  | Semeuse | 1,28× |
  | Marqueur | 1,36× |
  | Percuteur | 1,45× |
  | **Faucheur** | **2,84×** |

  Conséquence : en lunette, l'image défile 2,84 fois plus vite sous le réticule qu'à la hanche.

**Rechargement.**
- Le chargeur est crédité **à la fin** du rechargement (`Inventory.gd:203-210`).
- Rechargement à vide et rechargement tactique durent le même temps.
- L'animation est un creux sinusoïdal générique (`ViewModel.gd:1043-1052`) : FP-13 à FP-18 le remplacent.
- Les sons sont déclenchés par minuteur (`Audio.gd:826`, `:882-909`) : FP-14 les passe sur les événements des
  clips.

**Changement d'arme** : 0,25 s (`Weapon.gd:51`), contre 1,0 s pour Valorant et 0,6 s pour le R-301 d'Apex.
C'est très rapide, et voulu pour l'arène : on garde.

**TTK.**
- 100 PV (`Health.gd:27`). Armes principales : 385 à 430 ms au corps (`docs/BALANCE.md:19-23`).
- Références : The Finals de 0,54 à 1,86 s selon la classe, Splitgate (Warden) de 0,84 à 1,26 s, XM4 de BO6
  705 ms.
- **Notre TTK est plus court que toutes ces références d'arène.** Conséquence directe : chaque milliseconde de
  retour compte. Le hitmarker arrive après un RTT complet (40 à 100 ms). Si l'élimination n'a pas de « payoff »
  visuel, le kill passe inaperçu.

### 1.3 Retour de touche (HUD, cible)

- **Conforme à la bible §9.4 :**
  - hitmarker 90 ms, headshot 120 ms en orange, kill 270 ms avec punch d'échelle (`HitFeedback.gd:25-44`) ;
  - chiffres cumulés par cible sur 0,8 s ;
  - onomatopée par arme et multi-kill (`KillWordBurst.gd`) ;
  - killfeed, arcs de dégâts, vignette de vie basse ;
  - flash de rim sur la cible (`PlayerLook.gd:91-98`) ;
  - gel de pose de 50 ms au kill (`CharacterAnimator.gd:194`).
- **Manques :**
  - le hitmarker attend le serveur (GF-14 hitmarker prédit : todo) ;
  - pas d'escalade sonore des kills (seul « DOUBLÉ / TRIPLÉ » est visuel) ;
  - « CRAC ! » est défini mais inutilisé (`HitFeedback.gd:184`) ;
  - **la séquence d'élimination « REMBALLÉ » du §9.5 n'existe pas en jeu**. ART-43 est todo et bloqué par sa
    dépendance ART-17 (têtes-objets, bloquée), alors qu'un override dit déjà « ignorer les têtes-objets ».

### 1.4 Audio

**Chaîne de production.**
- 100 % synthèse Python : `tools/audio/gen_sfx.py` et `gen_weapon_layers.py` (bruit filtré, balayages,
  « click » résonant, queue par retard réinjecté).
- Tous les fichiers sont normalisés à −1 dBFS de crête.

**Tir local** (5 couches, sur le bus Shots) :
- transitoire (20 ms), corps (60 ms), mécanique (**10 ms**), sub (120 ms) ;
- queue intérieure (550 ms) ou extérieure (900 ms), choisie par raycast plafond (`Audio.gd:916-921`, `:937-947`).
- **Chaque couche tire sa propre hauteur aléatoire à ±5 %** (`Audio.gd:931`, `PITCH_SPREAD :127`) : la
  transitoire et le corps se désaccordent d'un tir à l'autre.
- 2 variations par couche seulement.

**Tir distant.**
- **Un seul échantillon prémixé** de 220 ms (variante `_far` au-delà de 30 m), sur le bus **SFX**, donc hors du
  ducking du bus Shots (`Audio.gd:860-865`, `:608-611`).
- `AudioStreamPlayer3D` n'est jamais réglé (valeurs moteur : `unit_size` 10, `max_distance` 0 = illimitée).

**Mix.**
- Ducking manuel de −4 dB pendant 120 ms sur le bus Shots quand un son de retour (hitmarker, headshot, kill)
  joue (`Audio.gd:141-145`, `:497-504`) : c'est bien.
- Aucun bus de réverbération.

**Absents :**
- son d'impact (monde et corps) ;
- sifflement ou claquement de balle qui frôle ;
- indice de fin de chargeur ;
- son de dernier coup ;
- bruitages de culasse, pompe et barillet (FP-14 ne câble que `mag_out` et `mag_in`) ;
- tintement de douille.

### 1.5 VFX de tir (comparés à la bible §9.2)

| Élément | Bible §9.2 | Code actuel |
|---|---|---|
| Flash FP | Étoile à 4 ou 5 branches + cœur, rotation ±25°, 3 images en 50 ms ; taille poing ×0,7, fusil ×1, pompe ×1,4, lourde ×1,2 ; Faucheur en longue étoile horizontale ; ≤ 6 % de l'écran | Carré billboard jaune de 12 cm, identique pour toutes les armes, 50 ms, sans rotation ni lueur (`ViewModel.gd:955-969`, `:984`) |
| Flash TP | ×1,5, ≥ 6 px à 60 m | Carré de 10 cm (`ThirdPersonWeapon.gd:192-197`), soit ≈ 1,5 px à 60 m en 1080p : la position du tireur ne se lit pas |
| Traceur | Trait de pinceau effilé de 2,5 cm, 3 à 6 m de long, 400 m/s, ≤ 80 ms ; 1 balle sur 2 (automatiques), 1 plomb sur 3 | Ligne `ImmediateMesh` d'**1 px**, instantanée, 80 ms, à chaque balle et à chaque plomb (`Weapon.gd:1164-1179`) |
| Douille | Laiton `#D9A21B` + encre, chute de 0,6 s, rebond, ≤ 4 visibles | **Absente** |
| Fumée | Palette crème (§9.1) | **Absente** : les constantes `SMOKE_1..3` ne servent pas au tir (`ComicFx.gd:39-41`) |
| Impacts | §9.3 | Générique monde et personnage conformes (ART-40). Variantes par matière bloquées : `Weapon.gd` ne transmet pas la surface (`ImpactFx.gd:22-27`) |

ART-40 a volontairement laissé de côté le §9.2, jugé « déjà livré » (`ComicFx.gd:27-29`) : ce n'est pas le cas.

### 1.6 Caméra

- **Secousse à trauma** (GF-08) : bien implémentée (Perlin, trauma², rotation seule), mais **calibrée trop
  bas**.
  - Trauma de tir de 0,08 à 0,25 (`CameraShake.gd:56-57`), amplitude = trauma² × 1,2° (`:32`, `:173-175`), soit
    **0,008° à 0,075°**.
  - Sur le Ravage, 0,10 par tir décroît de 0,15 entre deux balles (1,5/s) : le trauma ne s'accumule jamais et
    la secousse reste vers **0,012°**.
  - Dégât reçu (0,3) : **0,11°**.
  - Tout cela est imperceptible.
- **Punch FOV** −1,5° pendant 60 ms : seulement au kill (`Weapon.gd:1134`), jamais au tir.
- **Pas de couche « view punch »** purement visuelle.
- **Pas de creux à l'atterrissage** (MV-04 todo).
- FOV de sprint et de glissade ≤ +5° : OK.

### 1.7 Mouvement

- **Sol sec** : accélération 85, friction 75, soit 0 → 8,2 m/s en ≈ 0,1 s (`MovementConfig.gd:29-31`).
- **Saut** : 7,2 m/s, gravité 19, ×1,25 en chute. Apogée 1,36 m, ≈ 0,72 s en l'air.
- **Coyote / buffer** : 0,08 / 0,10 s (`:52-54`). La cible de MV-04 est 0,10 / 0,12.
- Sprint automatique sans délai de tir (BUG-K01). À titre de comparaison, sprint-to-fire de 190 ms sur le XM4 :
  notre choix d'arène est compensé par la dispersion de mouvement.
- **Glissade** : l'arme ne s'incline que de 6° (`ViewModel.gd:543`). Titanfall l'incline d'environ 45°.

### 1.8 Viewmodel procédural

**Sway** (`ViewModel.gd:1020-1024`, jusqu'à 5 cm et 4,3° de roulis) et **bob** (1,5 cm, `:1027-1036`) :
présents.

**Ressort de recul.**
- Paramètres : raideur 140, amortissement 16, soit ω ≈ 11,8 rad/s et ζ ≈ 0,68. Le pic arrive à **90 ms** (trop
  lent : un coup sec culmine en 1 à 2 images).
- La chaîne d'unités est incohérente : `deg_to_rad(recoil_vertical) × 6` (`:569`), puis
  `× 0,02 / × 0,03 / × 0,35` (`:528-529`, `:544`). Résultat : **0,04° et 0,05 mm** sur le Ravage.
- Toutes les couches passent ensuite dans un **passe-bas** `position.lerp(target, 18·Δ)` (`:541`, constante de
  temps ≈ 55 ms), qui avale ce qui reste du coup.

**Autres manques** : aucune inertie de strafe ni de saut.

**Point d'attention pour FP-14.** Le clip `fire` de FP-13 cuit 1,2 cm et 1,5° pour le Ravage, mais le doc 12
(§3.5) compte sur **ce ressort** pour « le gros du recul ». En l'état, il ne produit rien de visible.

### 1.9 Latence

- **Bon :**
  - souris appliquée à l'événement (`PlayerController.gd:322-327`) ;
  - rotation caméra non interpolée (`PlayerCamera.gd:337`), conforme à la doc Godot.
- **Moins bon :**
  - gâchette lue au tick physique (+8,3 ms en moyenne, +16,7 ms au pire) ;
  - VSync actif par défaut (`Settings.gd:166`).
- La doc Godot recommande, en VRR, VSync + plafond légèrement sous le rafraîchissement (141 i/s à 144 Hz). On
  ne monte pas le tick physique à 120 Hz (coût réseau et bots) : on tire plutôt à la fréquence d'image pour
  l'humain local (GF-46).

### 1.10 Checklist « The Art of Screenshake » (Nijman, 31 étapes) appliquée à notre tir

Légende : ✔ présent, ~ partiel ou trop faible, ✘ absent.

| Étape Nijman | État | Où |
|---|---|---|
| Muzzle flash (6) | ~ | Carré fixe, hors bible (§1.5) |
| Balles plus grosses et plus rapides (5, 7) | ✘ | Traceur d'1 px |
| Impact effects (9) | ✔ | ImpactFx / ComicFx (ART-40) |
| Hit animation (10) | ✔ | Flash de rim, recul de buste (GF-10) |
| Enemy knockback (11) | ~ | Flinch seulement : pas de recul physique en PvP, voulu |
| Permanence (12, 29) | ~ | Décalques 8 s ; ni douilles ni fumée |
| Screenshake (15) | ~ | Implémenté mais invisible (0,01°) |
| Sleep / hit-pause (17) | ~ | 50 ms sur la victime ; cosmétique uniquement en PvP |
| Gun kickback (19) | ✘ | 0,04° (§1.8) |
| Shell casings (21) | ✘ | — |
| More bass (22) | ✔ | Couche sub locale |
| Camera kick au tir (27) | ✘ | Pas de view punch |
| Meaning, player death (30) | ~ | Écran « REMBALLÉ » oui, séquence en jeu non (ART-43) |

---

## 2. Recherche (sources lues pendant cette session)

### 2.1 Recul

- **CS:GO / CS2.**
  - `recul_réel = aimPunch × 2,0` et `recul_visuel = viewPunch + aimPunch × 2,0 × 0,45`. Le **viewPunch** est
    purement visuel : il donne un retour immédiat aux premières balles, qui n'ont presque pas de recul réel,
    sans jamais dévier la balle. [davidbdurst](https://davidbdurst.com/blog/csknow_recoil.html) (vérifié par
    le lead).
  - **Pour nous :** l'arène veut « le réticule suit le recul » (comme Valorant). On garde donc un recul réel qui
    bouge la visée, et on **ajoute** un view punch visuel court, plus un gros kick du viewmodel (le « visual
    kick » façon COD).
- **Valorant.**
  - Montée verticale d'abord, puis dérive horizontale en tir soutenu.
  - Précision au premier tir : 0,25°.
  - Récupération ≈ 0,375 s.
  - Zoom ADS du Vandal ×1,25.
  - [Vandal](https://wiki.playvalorant.com/en-us/Vandal), [Sheriff](https://wiki.playvalorant.com/en-us/Sheriff)
- **Destiny 2** : un recul vertical (direction 100) est le plus facile à compenser, le recul latéral « le pire ».
  [wiki](https://d2.destinygamewiki.com/wiki/Recoil_Direction), [forum Bungie](https://www.bungie.net/en/Forums/Post/247015231)
- **Apex** : motifs par arme, lisibles (R-301 : haut puis légère droite).
  [Dexerto](https://www.dexerto.com/apex-legends/updated-recoil-patterns-for-all-weapons-in-apex-legends-1354210/)
- **Splitgate** traite le « visual recoil » comme une couche de réglage séparée.
  [Splitgate](https://www.splitgate.com/news/splitgate-arena-reloaded-launch-overview/)

### 2.2 Temps de maniement

| Jeu / arme | Mesure | Source |
|---|---|---|
| Apex R-301 | Dégainer 0,6 s ; ADS in 0,27 s / out 0,23 s (rapport 0,85) ; recharge tactique 2,4 s, à vide 3,2 s | [wiki](https://apexlegends.wiki.gg/wiki/R-301_Carbine) |
| BO6 XM4 | ADS 270 ms ; sprint-to-fire 190 ms ; recharge 2,43 s | [codmunity](https://codmunity.gg/weapon/bo6/xm4) |
| Valorant | Équipement 1,0 s ; Vandal recharge 2,5 s, ADS ×1,25 | [Vandal](https://wiki.playvalorant.com/en-us/Vandal) |

Nos valeurs sont plus rapides partout (ADS 120–380 ms, changement 0,25 s) : c'est cohérent avec l'arène. On ne
ralentit rien, on **synchronise** et on **donne de l'accélération** (easing).

### 2.3 Sensibilité ADS

Le standard compétitif est le « 0 % monitor distance », ou mise à l'échelle par focale : même rotation par
count **au centre de l'écran** à la hanche et en visée. CS2, Valorant et Apex calculent leurs multiplicateurs de
zoom par rapport au FOV de hanche. [dcprosens](https://dcprosens.com/ads/) (lu par le lead)

Formule : `sens_ads = sens × tan(fov_ads/2) / tan(fov_hanche/2) × multiplicateur_joueur`.

### 2.4 Retour de touche et de kill

- **Apex** :
  - chiffres de dégâts cumulés ou flottants ;
  - or pour la tête, couleur du bouclier ;
  - hitmarker de couleur différente selon bouclier ou chair.
  - [Shacknews](https://www.shacknews.com/article/110042/how-to-change-damage-numbers-in-apex-legends)
- **Valorant** : bannière de kill et **son de kill qui monte sur 5 paliers** (1er → 5e kill de la manche), plus
  un son « successif » pour les kills rapprochés. [Kill Banners](https://wiki.playvalorant.com/en-us/Kill_Banners)
- **Borderlands 3** : chiffres au-dessus des têtes, ennemis projetés, son « clair, ponctuant ».
  [PlayStation Blog](https://blog.playstation.com/2019/08/14/8-irresistible-gameplay-improvements-in-borderlands-3/)
- **Hitstop.**
  - Sakurai : longueur proportionnelle aux dégâts avec plafond ; les projectiles en ont moins ; 4 images de
    fondu vers la pose de douleur.
  - Chez nous, en PvP, le hitstop reste strictement cosmétique (01 §2.1).
  - [Source Gaming](https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/),
    [critpoints](https://critpoints.net/2017/05/17/hitstophitfreezehitlaghitpausehitshit/)

### 2.5 Audio d'arme

- **Mark Kilborn** : gabarit FPS en 5 couches (corps, transitoire, sub, mécanique, queue), avec « des dizaines
  de variations » pour que deux tirs ne sonnent jamais pareil.
  [Pro Sound Effects](https://blog.prosoundeffects.com/how-to-sound-design-first-person-shooter-gunshot-sound-effects-with-mark-kilborn)
- **Pipeline modulaire AAA** :
  - queues séparées du tir, en fondu intérieur / extérieur ;
  - mécanique randomisée en hauteur et en volume ;
  - dynamique préservée pour que le ducking fonctionne.
  - [Arcella](https://www.arcellasound.com/post/aaa-weapon-sound-design-architecting-modular-combat-audio-for-xdev-pipelines)
- **Apex** : le son de l'arme **change progressivement quand le chargeur se vide**. Le patch 1.1.3 a restauré
  les sons de fin de chargeur et de clic à vide manquants.
  [player.one](https://www.player.one/apex-legends-update-113-audio-hit-detection-issues-fixed-126388)
- **Godot 4.**
  - `AudioStreamRandomizer` : `random_pitch`, `random_volume_offset_db`, mode `RANDOM_NO_REPEATS`.
  - `AudioStreamPlayer3D` : `unit_size` 10, `max_distance` 0 (illimité), `max_polyphony` 1,
    `attenuation_filter_cutoff_hz` 5000 à −24 dB, `area_mask` pour les queues par zone.
  - `AudioEffectCompressor` : sidechain par nom de bus.
  - [Randomizer](https://docs.godotengine.org/en/stable/classes/class_audiostreamrandomizer.html),
    [Player3D](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html),
    [Compressor](https://docs.godotengine.org/en/stable/classes/class_audioeffectcompressor.html)

### 2.6 Jus et références stylisées

- **Nijman, liste complète des 31 étapes** : voir §1.10.
  [transcription](https://theengineeringofconsciousexperience.com/jan-willem-nijman-vlambeer-the-art-of-screenshake/),
  [notes](https://victorweidar.wordpress.com/2016/10/06/the-art-of-screenshake/)
- **Far Far West** :
  - armes « meaty and responsive dès le premier tir » ([GamingTrend](https://gamingtrend.com/previews/far-far-west-preview/)) ;
  - tir « weighty and meaningful » ([Game8](https://game8.co/articles/reviews/far-far-west-review-early-access)) ;
  - effets « impressionnamment animés » ([COGconnected](https://cogconnected.com/preview/far-far-west-preview/)) ;
  - le détail des animations est déjà couvert par le doc 12 §2.1.
- **Titanfall** :
  - réticule fixe pendant le bob ;
  - vue qui s'incline hors du mur ;
  - **creux à l'atterrissage proportionnel à la hauteur de chute** ;
  - arme inclinée d'environ 45° en glissade.
  - [Game Developer](https://www.gamedeveloper.com/design/designer-interview-getting-i-titanfall-i-s-controls-just-right)
- **Procédural** : impulsions de ressort au départ et au changement de direction, impulsion d'atterrissage selon
  la vitesse verticale, recul différent en hanche et en visée, « contre-poussée » en tir soutenu.
  [Dev_Unallocated](https://www.devunallocated.com/projects/project-killhouse/procedural-weapon-animations-condensed)

### 2.7 TTK d'arène

| Jeu | TTK | Source |
|---|---|---|
| The Finals, saison 11 | 0,54–0,72 s (Light), 0,90–1,34 s (Medium) | [thefinalsloadout](https://thefinalsloadout.com/ttk) |
| Splitgate, Warden | 0,84 s optimal, 1,26 s au corps ; Splitgate a « légèrement augmenté » le TTK pour des combats plus lisibles | [wiki](https://splitgatearenareloaded.wiki.gg/wiki/Warden), [annonce](https://www.splitgate.com/news/splitgate-arena-reloaded-launch-overview/) |
| BO6, XM4 | 705 ms | [wzstats](https://wzstats.gg/best-loadouts/xm4) |

Notre TTK de 385 à 430 ms est un choix d'équilibrage, hors périmètre ici. Voir §7, risque 5.

### 2.8 Latence et capture

- **Doc Godot « jitter, stutter, input lag »** :
  - VSync off réduit la latence ;
  - en VRR, VSync + plafond 3 i/s sous le rafraîchissement ;
  - `Input.use_accumulated_input(false)` traite chaque événement ;
  - l'interpolation physique ajoute de la latence.
  - [doc](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html),
    [interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html)
- **NVIDIA** : l'aim progresse encore sous 20 ms de latence système. [arXiv 2105.10498](https://arxiv.org/abs/2105.10498)
- **Movie Maker de Godot** : `--write-movie <sortie>.png --fixed-fps N` enregistre chaque image à pas fixe, avec
  le **WAV** à côté. On obtient des preuves image par image et son synchronisées, indépendantes des performances
  réelles. [doc](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html) (lu par le lead)

---

## 3. Plan : 15 changements par impact

L'ordre est celui de l'impact sur « ça se sent bien dans les mains ». Chaque cible se mesure avec le banc
**GF-40**.

| # | Changement | Cible mesurable | Vérification | Tâche |
|---|---|---|---|---|
| 1 | **Banc de mesure du ressenti** | Il reproduit l'audit (§1.1) à ±5 % ; une base de référence est archivée | `feel_reel` (Movie Maker 60 et 144 i/s) + `feel_metrics.py` + pytest | **GF-40** |
| 2 | **Kick du viewmodel visible** (le « visual kick » COD / FFW) | Tableau §4.1 ; pic ≤ 2 images à 60 i/s ; retour < 10 % en ≤ 0,9 × l'intervalle de tir ; en ADS ×0,4 ; couloir central vide | Télémétrie du nœud ViewModel + déplacement écran de la bouche (px à 1080p) | GF-41 → **GF-45** |
| 3 | **Recul de visée qui s'accumule**, appliqué à la fréquence d'image | Ravage 6 tirs = 4,05° ± 5 % (au lieu de 26 %) ; ≥ 90 % du kick en ≤ 25 ms ; aucun palier de 60 Hz à 144 i/s ; retour < 10 % en ≤ 0,5 s après relâche | Tests purs + `feel_reel --fixed-fps 144` | **GF-42** (remplace GF-05) |
| 4 | **View punch caméra + secousse recalibrée** | Punch visuel §4.2 (la balle ne dévie pas) ; spray Ravage d'1 s : secousse RMS de 0,10 à 0,25° ; dégât reçu : pic de 0,3 à 0,6° | Tests purs + télémétrie caméra | **GF-43** |
| 5 | **Effets de tir §9.2** : flash étoile, traceur pinceau, douilles, fumée | Valeurs de la bible §9.2 (§4.3) ; flash TP ≥ 6 px à 60 m ; ≤ 6 % de l'écran | `shot_fx_shots` + `style_check` + perf | **GF-44** → GF-45 / GF-46 |
| 6 | **Hitmarker prédit** (TTK court) | Hitmarker léger dans l'image du tir (≤ 1 image), au lieu d'un RTT (40–100 ms) ; kill jamais prédit | Test + `feel_reel` | **GF-14** (existant, P0) |
| 7 | **Élimination « REMBALLÉ »** (le payoff du kill) | Séquence §9.5 en 0,9 s, sans ragdoll ni sang | Capture | **ART-43** (existant, débloquer, P0) |
| 8 | **ADS synchronisé + sensibilité au zoom** | FOV et arme à 100 % dans la même image (± 1) à `ads_time`, easing identique ; sortie = 0,85 × entrée ; Faucheur 0,352× la sensibilité de hanche | Tests purs + courbes tracées | GF-42 / **GF-43** / GF-45 |
| 9 | **Cadence à la fréquence d'image** (humain local) | Écart-type des intervalles ≤ 3 ms (au lieu de ±8,3) ; clic → `fired` dans la même image ; 0 tir refusé par le serveur | Tests + détection d'attaques dans le WAV à 144 i/s | **GF-46** |
| 10 | **Tir local cohérent + tirs ennemis en couches et spatialisés** | 5 couches à la même hauteur (±1 %) ; ≥ 4 variations par couche ; tir ennemi à 20 m au moins 10 dB sous le tir local ; ennemis ducker | Tests purs + crêtes de bus | GF-47 → **GF-48** |
| 11 | **Indices sonores** : fin de chargeur, dernier coup, impacts, sifflements | Couche `mech_low` sous 25 % du chargeur (0 → +6 dB) ; « ping » au dernier coup ; sifflement si une balle passe à < 1,5 m ; impacts 3D (≤ 6 voix) | Tests purs + montage WAV | GF-47 → **GF-48** |
| 12 | **Escalade sonore des kills + « CRAC ! »** | 5 paliers de son de kill dans la fenêtre multi-kill de 1,2 s | Test pur | **GF-48** |
| 13 | **Atterrissage et inertie** | Creux caméra de 2 à 6 cm proportionnel, retour en 150 ms ; strafe ≤ 1,5 cm de retard ; arme inclinée de 15° en glissade | Télémétrie | **GF-43** (reprend MV-04) + GF-45 |
| 14 | **Règle de rechargement** (décision) | Chargeur crédité à `mag_in` (≈ 0,78 × `reload_time`) ; changer d'arme ensuite garde les balles | Tests Inventory | **GF-50** (P2, décision) |
| 15 | **Réglage fin + vidéo avant / après** | Toutes les métriques §4 PASS sur les 7 armes ; montage de 60 s | `feel_reel` complet | **GF-49** |

## 4. Cibles chiffrées

### 4.1 Kick du viewmodel (hanche ; ADS ×0,4 ; total mesuré = clip cuit + ressort procédural)

| Famille | Recul arrière | Relevé | Roulis aléatoire | Pic | Retour < 10 % | Bouche à l'écran, 1080p |
|---|---|---|---|---|---|---|
| Poing (Pistolet) | 1,5 cm | 3,0° | ±1,0° | ≤ 2 images | ≤ 130 ms | ≥ 15 px |
| SMG (Rafale, Éclair) | 0,8 cm | 1,2° | ±1,5° | ≤ 2 images | ≤ 0,9 × intervalle (70 / 85 ms) | ≥ 6 px |
| Fusil (Ravage, Semeuse) | 1,2 cm | 1,8° | ±1,2° | ≤ 2 images | ≤ 90 ms | ≥ 10 px |
| Précision (Marqueur, Percuteur) | 2,0 cm | 3,5° | ±1,0° | ≤ 2 images | ≤ 130 ms | ≥ 20 px |
| Magnum | 3,0 cm | 10° (le clip FP-16 lève à 12°) | ±2,0° | ≤ 2 images | ≤ 300 ms | ≥ 50 px |
| Pompe (Fracas) | 4,0 cm | 6,0° | ±2,0° | ≤ 2 images | ≤ 350 ms (la pompe suit) | ≥ 35 px |
| Sniper (Faucheur) | 4,0 cm | 7,0° | ±1,0° | ≤ 2 images | ≤ 250 ms (la culasse suit) | ≥ 40 px |

Règles :
- le kick s'applique **après** le passe-bas de position (`ViewModel.gd:541`), jamais dedans ;
- ressort amorti de ζ 0,55 à 0,7, spécifié en **amplitude et temps**, plus en « vitesse × constantes magiques » ;
- aucun sommet dans le carré central 20 % × 20 % au pic ;
- contre-poussée en tir soutenu (Dev_Unallocated) : l'amplitude par tir descend jusqu'à −30 % sur les 5
  premières balles d'un spray, pour ne pas vibrer comme un marteau-piqueur.

### 4.2 Caméra

| Réglage | Valeur |
|---|---|
| View punch (visuel seul, la balle ne dévie pas) | SMG 0,2° · fusil 0,3° · poing 0,4° · précision 0,6° · magnum 1,0° · pompe 1,2° · sniper 1,2° |
| Montée / retour du punch | Montée en 1 image ; retour < 10 % en 80 ms (automatiques) ou 150 ms (armes lourdes) |
| Secousse (trauma²) | Spray Ravage d'1 s → RMS de rotation 0,10–0,25° ; dégât reçu → pic 0,3–0,6° ; explosion proche → 1,0–1,5° ; plafond 2,5° |
| ADS | Easing « ease-out cubic » commun au FOV et à l'arme ; entrée = `ads_time` (inchangé, 120–380 ms) ; sortie = 0,85 × `ads_time` (rapport R-301 0,23 / 0,27) |
| Atterrissage | Creux de 0 à 6 cm ∝ vitesse de chute (dès 3 m), retour ease-out en 150 ms ; rien sur une marche (StairStep) |
| Mouvement réduit | Secousse 0 ; punch ≤ 0,3° ; creux 0 |
| « Secousses désactivées » | Secousse 0 et punch 0 |

### 4.3 VFX de tir (bible §9.2, sans ajout de style)

**Flash FP.**
- Étoile à 4 ou 5 branches + cœur, palette `#FFF3D6` / `#FFD24A` / `#F59A2E`, encre 2 px.
- Rotation ±25°, 3 images en 50 ms.
- Échelle : poing ×0,7, fusil ×1, pompe ×1,4, lourde ×1,2 ; Faucheur en étoile longue horizontale.
- ≤ 6 % de l'écran.
- Lueur optionnelle : `OmniLight3D` sur 1 image, énergie ≈ 2, portée 3 m, sans ombre, humain local seulement,
  coût ≤ 0,2 ms.

**Flash TP.** ×1,5, 50 ms, ≥ 6 px à 60 m.

**Traceur.**
- Trait effilé de 2,5 cm, 3 à 6 m, `#FFF3D6` à 90 % + bord encre à 40 %.
- 400 m/s, ≤ 80 ms.
- 1 balle sur 2 (automatiques), 1 plomb sur 3 (pompe) ; départ au bout du canon (GF-06).

**Douilles.**
- Éjection depuis le repère `Eject` du JSON FP (doc 12 §3.6), 2 à 3 m/s vers la droite et le haut, rotation.
- Chute de 0,6 s, 1 rebond ; ≤ 4 visibles ; FP seulement.
- Déclenchement :
  - Pistolet, fusils, Faucheur : à chaque tir (Faucheur : à l'événement `bolt_back`) ;
  - Fracas : à l'événement `pump_back` ;
  - Magnum : 6 douilles à l'événement `eject`.

**Fumée.** 3 bouffées rondes crème, 400 ms, animées « sur deux », après chaque rafale de 3 tirs ou plus, et
après chaque tir de pompe ou de sniper.

**Budgets.** ≤ 64 particules par effet ; rien ne masque le réticule plus de 80 ms.

### 4.4 Audio

**Tir local.**
- Une hauteur par tir (±4 %), partagée par les 5 couches, plus ±1 % par couche.
- ≥ 4 variations par couche, en `RANDOM_NO_REPEATS`.
- Couche mécanique de 60 à 120 ms, propre à chaque famille : claquement de culasse, glissière, pompe, barillet.

**Fin de chargeur.**
- Couche `mech_low` (grelot creux de 2 à 4 kHz) à partir de `mag ≤ 25 %` (`HudFormat.LOW_AMMO_RATIO`), rampe
  de 0 à +6 dB.
- « Ping » au dernier coup : clin d'œil western.

**Tir ennemi.**
- Couches selon la distance : proche < 15 m (transitoire + corps), moyen 15–45 m (prémixé), loin > 45 m
  (`_far`).
- `AudioStreamPlayer3D` : `unit_size` ≈ 8, `max_distance` 150 m, filtre d'atténuation par défaut.
- Bus **Shots**, donc soumis au ducking.
- Niveau : ≥ 10 dB sous le tir local à 20 m.

**Sifflement.**
- Rayon ennemi qui passe à < 1,5 m de la tête sans la toucher → sifflement 2D panoramiqué du bon côté.
- ≤ 4 par seconde.

**Impacts.**
- Monde « tak » en 3D, −6 dB sous le tir local.
- Corps « thwack » 3D sur la cible, entendu par le tireur.
- « CLING » métal dès que la matière est transmise (§9.3).
- ≤ 6 voix.

**Kills.** Son de kill sur 5 paliers (modèle Valorant) dans la fenêtre de multi-kill de 1,2 s ;
« CRAC ! » sur un kill à la tête.

**Rechargements.**
- Bruitage pour chaque événement de la liste fermée du doc 12 §3.5 : `mag_out`, `mag_in`, `mag_tap`, `bolt`,
  `slide_release`, `cylinder_open`, `eject`, `speedloader_in`, `cylinder_close`, `hammer`, `shell_in`,
  `pump_back`, `pump_fwd`, `bolt_up/back/fwd/down`, `twirl`, `inspect_touch`.
- Plus le tintement de douille.

**Mix mesuré** (crêtes de bus via `AudioServer.get_bus_peak_volume_left_db`) : pendant un spray, crête Feedback
≥ crête Shots − 3 dB dans les 90 ms qui suivent un hit.

---

## 5. Ordonnancement avec le viewmodel v2 (propriété des fichiers)

**Fichiers réservés.**
- FP-14 possède `ViewModel.gd`, `scripts/player/viewmodel/`, `Weapon.gd`, `Audio.gd` et `tools/fp_shots.gd`.
- FP-19 reprend ensuite `ViewModel.gd`, `Weapon.gd`, `ThirdPersonWeapon.gd` et les modèles.

Tout ce qui écrit dans ces fichiers passe donc **après FP-14**. Tout le reste démarre **maintenant**, sur des
fichiers disjoints.

| Vague | Tâches en parallèle (fichiers disjoints) | Condition |
|---|---|---|
| **F1 (maintenant)** | GF-40 banc · GF-41 socle profils + maths · GF-44 modules VFX (+ flash TP) · GF-47 sons synthétisés | Aucune. Tourne à côté de FP-13 et FP-14 |
| **F2** | GF-42 recul + sensibilité ADS · GF-43 caméra · ART-43 élimination | GF-41 et GF-40 livrés (ART-43 : dépendance ART-17 retirée) |
| **F3 (après FP-14)** | GF-45 viewmodel · GF-46 `Weapon.gd` · GF-48 `Audio.gd` ; puis GF-14 hitmarker prédit, sérialisé avec GF-46 | FP-14 livré. Les fenêtres FP-15 à FP-18 (Blender seulement) laissent ces fichiers libres |
| **F4** | GF-49 réglage fin + vidéo · GF-50 rechargement (si validé) | F3 livrée |
| Puis | FP-19, qui supprime le chemin legacy sur un code déjà branché | GF-44, GF-45 et GF-46 livrés |

**Overrides proposés au lead** pour `tasks/backlog.yaml` (à appliquer par le lead, pas par ce document) :

```yaml
overrides:
  GF-05: {status_hint: "remplacé par GF-42 — passer en dropped"}
  MV-04: {status_hint: "remplacé par GF-43 (le son d'atterrissage existe déjà, Audio.gd:416 ; le réglage de head-bob existe, Settings.gd:232) — dropped"}
  GF-09: {notes: "Réticule dynamique déjà en place (GameHUD.gd:402-419) ; reste à prendre en compte la pénalité de Stun et Sang-froid (GameHUD.gd:416 contre Weapon.gd:451), puis clore"}
  GF-14: {priority: P0, add_depends_on: [FP-14]}
  ART-43: {priority: P0, depends_on_replace: [ART-40], notes: "Sans têtes-objets (§4 v3.1) : l'emblème qui roule suffit"}
  FP-14: {notes_add: "Ne pas retoucher le ressort AnimState : GF-45 le remplace. Garder le signal `fired` et l'événement `anim_event`"}
  FP-19: {add_depends_on: [GF-44, GF-45, GF-46]}
```

---

## 6. Audio : décision « assets » pour l'utilisateur

**Aujourd'hui** : 100 % synthèse maison. Pas de licence à gérer, mais un plafond de qualité. Les tirs synthétisés
sonnent « jeu vidéo », rarement « meaty ».

**Option A (par défaut, sans action de l'utilisateur).** GF-47 pousse la synthèse : variations,
mécanique longue par famille, grelot de fin de chargeur, impacts, sifflements, bruitages de rechargement. Tout
est déterministe et testable. **C'est ce que planifient GF-47 et GF-48.**

**Option B (recommandée pour le « gros son »).** Garder la synthèse pour la transitoire, le sub et l'UI, et
**superposer des enregistrements réels** pour la mécanique, les rechargements, les douilles et les impacts.

Candidats vérifiés (pages de licence lues) :

| Source | Licence | Commercial | Attribution | Remarque |
|---|---|---|---|---|
| [Sonniss #GameAudioGDC](https://sonniss.com/gdc-bundle-license/) | EULA libre de droits | Oui, illimité, à vie | Non | Interdit de revendre ou redistribuer les sons bruts, et d'entraîner une IA dessus. Plusieurs Go ; contient des banques d'armes et de foley |
| [Kenney](https://kenney.nl/support) | CC0 | Oui | Non | Peu de tirs ; bon pour impacts et UI |
| [Freesound](https://freesound.org/help/faq/) | Au cas par cas | CC0 : oui ; CC-BY : oui ; CC-BY-NC : **non** | CC-BY : oui | Filtrer sur **CC0 uniquement** pour éviter un registre de crédits |
| [OpenGameArt](https://opengameart.org/content/faq) | CC0, CC-BY, CC-BY-SA, GPL, OGA-BY | Selon la licence | Selon la licence | La FAQ OGA dit que CC-BY et CC-BY-SA posent problème sur les plateformes à DRM (Steam) ; **CC0 ou OGA-BY seulement** |
| Gamemaster, Mixkit, Pixabay, Zapsplat | **Non vérifié** | ? | ? | Ne pas utiliser sans lire la licence |

**Règle.** Rien n'est téléchargé sans accord explicite de l'utilisateur. Rappel : Chrome tourne souvent sur un
autre PC. Si l'option B est choisie :
1. l'utilisateur dépose les fichiers dans `assets/incoming/audio/<source>/` ;
2. une tâche AUD les découpe, les normalise et les inscrit dans `docs/assets/AUDIO_CREDITS.md` (licence par
   fichier).

L'option B n'est **pas** bloquante pour GF-48 : les noms de sons restent les mêmes, seuls les fichiers
changent.

---

## 7. Risques

1. **Kick trop fort = nausée, ou arme qui masque la cible.** Parades :
   - couloir central vide au pic, vérifié à chaque capture ;
   - ADS ×0,4 ;
   - contre-poussée en tir soutenu ;
   - « Mouvement réduit » et « Secousses désactivées » respectés.
2. **Conflits avec FP-14 et FP-19** sur `ViewModel.gd`, `Weapon.gd` et `Audio.gd`. Parades :
   - socle et modules purs d'abord (F1–F2) ;
   - branchement en une passe courte juste après FP-14 ;
   - FP-19 attend GF-44 à GF-46 (overrides §5).
3. **Recul cumulé = bots moins précis en spray** : aucun bot ne compense le recul aujourd'hui (grep vide dans
   `scripts/ai/`). Critère de GF-42 : `bot_bench` sans régression de plus de 5 % du taux de touche. Sinon, la
   compensation va dans une tâche BOT.
4. **Tir à la fréquence d'image** : risque de refus serveur (limiteur de cadence) et de divergence de
   prédiction. Parades :
   - origine et direction inchangées (contrat GF-06 / BUG-26) ;
   - test de 30 s de spray à 144 i/s avec gigue, 0 refus exigé ;
   - les bots restent au tick physique.
5. **TTK très court (≤ 430 ms)** : même parfait, le retour de tir sera bref. Si le playtest post-GF-49 trouve
   encore les combats « expéditifs », il faudra une **décision d'équilibrage** (Splitgate a allongé son TTK pour
   des combats plus lisibles), hors de ce plan.
6. **Synthèse audio plafonnée** : voir §6, option B.
7. **Movie Maker en mode fenêtré** : le banc ouvre une fenêtre sur le poste, comme `fp_shots`. Timeout
   obligatoire ; jamais lancé sans `timeout`.

---

## 8. Tâches (à importer par le lead dans `tasks/backlog.yaml`)

```yaml
- id: GF-40
  epic: E2
  priority: P0
  size: M
  model: sonnet
  agent: builder
  title: "Banc de mesure du ressenti : feel_reel (Movie Maker) + feel_metrics (kick, recul, punch, ADS, cadence, audio)"
  depends_on: []
  files:
    - tools/review/feel_reel.gd
    - tools/review/feel_reel.tscn
    - tools/review/feel_metrics.py
    - tests/review/test_feel_metrics.py
    - reports/feel/
    - reports/checkpoints/2026-09-25_GF-40/
  reads:
    - docs/research/13_game_feel.md
    - tools/fp_shots.gd
    - tools/review/gameplay_probe.gd
    - scripts/player/ViewModel.gd
    - scripts/player/PlayerCamera.gd
    - scripts/core/Audio.gd
  notes: >-
    Scène lancée EN FENÊTRÉ comme scène principale :
    `godot --path . res://tools/review/feel_reel.tscn --write-movie reports/feel/<run>/frame.png --fixed-fps 60 -- --weapon=<id> --scenario=<nom>`
    (le Movie Maker écrit les PNG et le WAV). Toujours sous `timeout`.
    Scénarios par arme :
    1. un tir à la hanche ;
    2. spray d'1 s (automatiques) ou 3 tirs (semi-auto) ;
    3. ADS in, 3 tirs, ADS out ;
    4. rechargement ;
    5. changement d'arme ;
    6. chute de 3 m et de 6 m.
    Pilotage par `player.input` (comme gameplay_probe). Cible d'entraînement à 15 m et marqueur monde fixe.
    Télémétrie JSONL par image, par INTROSPECTION NON INTRUSIVE uniquement (aucun script de jeu modifié) :
    - transform locale du nœud ViewModel ;
    - base de la tête (visée) et base de la caméra (visuel) ;
    - fov ;
    - bouche projetée (Camera3D.unproject_position) ;
    - nœuds visibles dont le nom commence par MuzzleFlash, Tracer ou Shell ;
    - munitions ;
    - crêtes de bus via AudioServer.get_bus_peak_volume_left_db (Shots, Feedback, SFX).
    feel_metrics.py (numpy/scipy/PIL, ffmpeg présent) calcule :
    - pic, image du pic et retour du kick ;
    - montée de visée comparée à Σ recoil_pattern ;
    - pic et retour du view punch ;
    - courbes ADS du FOV et de l'arme ;
    - images de flash ;
    - attaques dans le WAV (écart-type des intervalles) ;
    - crêtes de bus.
    Il écrit metrics.json, summary.md (PASS/FAIL contre les cibles du §4 du doc 13), une planche JPG ≤ 1600 px
    et un mp4 ≤ 10 s. Première exécution = base de référence dans reports/feel/baseline/.
  acceptance: >-
    Sur le code actuel, la base reproduit l'audit du doc 13 §1.1 :
    - montée caméra du Ravage 26 % ± 5 points de Σ motif ;
    - kick VM du Ravage < 0,1° ;
    - à --fixed-fps 144, intervalles de la Rafale ∈ {66,7 ; 83,3} ± 1 ms.
    pytest tests/review/test_feel_metrics.py vert, dont :
    - détection d'attaques sur un WAV synthétique connu, erreur ≤ 2 ms ;
    - pic et retour d'un signal de ressort synthétique à ± 1 image.
    Exécution complète 7 armes ≤ 10 min.
    Captures : planche 4 JPG (pics de kick, spray, ADS mi-course, atterrissage) + mp4 Ravage dans
    reports/checkpoints/2026-09-25_GF-40/.
  source: recherche 13 (lead 2026-09-25)

- id: GF-41
  epic: E2
  priority: P0
  size: M
  model: sonnet
  agent: builder
  title: "Socle sensations : profils de ressenti par arme (WeaponConfig + .tres) et maths pures (ressort de kick, punch, easing ADS, sensibilité au zoom)"
  depends_on: []
  files:
    - scripts/combat/WeaponConfig.gd
    - resources/weapons/
    - scripts/combat/feel/KickSpring.gd
    - scripts/combat/feel/FeelCurves.gd
    - tests/combat/test_feel_math.gd
  reads:
    - docs/research/13_game_feel.md
    - scripts/player/ViewModel.gd
    - scripts/player/CameraShake.gd
    - scripts/combat/WeaponFeel.gd
  notes: >-
    Nouveau groupe @export « Sensations (GF-41) » :
    - kick : kick_back_m, kick_pitch_deg, kick_roll_deg, kick_settle_s ;
    - caméra : view_punch_deg, view_punch_return_s, shot_trauma ;
    - recul : recoil_recovery_delay (-1 = auto : 1/fire_rate + 0,05 s), recoil_kick_time_s (0,025) ;
    - ADS : ads_out_ratio (0,85).
    Valeurs des 10 armes + default_rifle d'après les tableaux §4.1 et §4.2 (famille = catégorie ; Éclair et
    Rafale en SMG ; Semeuse en fusil ; Percuteur et Marqueur en précision).
    Supprimer le champ mort aim_speed (jamais lu) du script ET des .tres.
    KickSpring (RefCounted pur) : ressort amorti SPÉCIFIÉ EN AMPLITUDE ET TEMPS. `configure(peak, settle_s, zeta)`
    calcule raideur, amortissement et impulsion initiale, pour ne plus passer par une chaîne
    vitesse × constantes (ViewModel.gd:569, 528-529, 544). Il prévoit une contre-poussée
    (`sustain_scale(shot_index)`, −30 % max sur 5 tirs).
    FeelCurves (fonctions statiques pures) :
    - ads_ease(p) : ease-out cubic ;
    - ads_progress(current, aiming, delta, ads_time, out_ratio) ;
    - zoom_sensitivity_scale(fov_hip_v, fov_ads_v) = tan(ads/2) / tan(hip/2) ;
    - view_punch_value(elapsed, peak, return_s) ;
    - recoil_kick_progress(elapsed, kick_time).
    reload_time n'est PAS modifié (lu par FP-13 à FP-18).
  acceptance: >-
    tests/combat/test_feel_math.gd :
    - pour les 10 profils, pic de KickSpring = amplitude demandée ± 5 %, atteint en ≤ 2 images à 60 Hz ;
    - résidu < 10 % à kick_settle_s ;
    - pic identique ± 5 % à 30, 60, 144 et 240 Hz ;
    - zoom_sensitivity_scale(70,53 ; 28) = 0,352 ± 0,005 ;
    - ads_ease(0) = 0, ads_ease(1) = 1, strictement croissante ;
    - sortie ADS = 0,85 × ads_time ± 1 image.
    Chaque .tres porte les valeurs du §4. grep « aim_speed » = 0 hors docs/.
    tests/combat complets verts.
  source: recherche 13 (lead 2026-09-25)

- id: GF-42
  epic: E2
  priority: P0
  size: M
  model: sonnet
  agent: builder
  title: "Recul de visée v2 (remplace GF-05) : motif cumulé, récupération différée, kick sec appliqué à la fréquence d'image, sensibilité ADS à l'échelle du zoom"
  depends_on: [GF-40, GF-41]
  files:
    - scripts/player/PlayerController.gd
    - scripts/combat/WeaponFeel.gd
    - scripts/core/Settings.gd
    - tests/combat/test_recoil_v2.gd
    - tests/core/test_ads_zoom_sensitivity.gd
    - reports/checkpoints/2026-09-25_GF-42/
  reads:
    - docs/research/13_game_feel.md
    - docs/research/01_game_feel.md
    - scripts/combat/Weapon.gd
    - scripts/combat/feel/
    - scripts/player/PlayerCamera.gd
  notes: >-
    Weapon.gd est en LECTURE SEULE (FP-14) : garder la signature add_recoil(pitch, yaw, recovery).
    recoil_recovery_delay et recoil_kick_time_s se lisent via Weapon.cfg().
    Pour l'humain local (is_local_human), appliquer le recul dans _process : rotation de la tête comme la
    souris, jamais interpolée (doc Godot). Bots et serveur : inchangés, au tick physique.
    Kick : ≥ 90 % en recoil_kick_time_s (ease-out), au lieu du lerp 22/s (PlayerController.gd:186).
    Aucune récupération tant que la gâchette est tenue et pendant recoil_recovery_delay (PlayerController.gd:185
    aujourd'hui).
    Settings.ads_zoom_scaling (défaut true, sauvegardé) :
    sens_ads = sens × FeelCurves.zoom_sensitivity_scale(...) × ads_sensitivity_multiplier.
    Désactivé = comportement actuel. L'exposition dans le menu d'options est à faire par une tâche UX.
  acceptance: >-
    Tests :
    - 6 tirs de Ravage sans souris → montée = Σ recoil_pattern.y (4,05°) ± 5 % (aujourd'hui 1,07°) ;
    - relâché → < 10 % en ≤ 0,5 s, et aucune récupération avant recoil_recovery_delay ;
    - chaque kick à ≥ 90 % en ≤ 25 ms ;
    - hanche et ADS respectent recoil_aim_mult ;
    - zoom : Faucheur 0,352× ± 0,005 ; option off → ×1,0.
    feel_reel --fixed-fps 144 : tangage caméra modifié sur ≥ 90 % des images des fenêtres de kick (plus de
    paliers de 60 Hz).
    bot_bench : taux de touche sans régression > 5 %.
    tests/combat, tests/player et tests/core verts.
    Captures : mp4 avant / après du spray Ravage + courbe de montée dans reports/checkpoints/2026-09-25_GF-42/.
  source: recherche 13 (lead 2026-09-25)

- id: GF-43
  epic: E2
  priority: P0
  size: M
  model: sonnet
  agent: builder
  title: "Caméra de tir : view punch visuel par arme, secousse recalibrée, ADS synchronisé et accéléré, creux d'atterrissage (reprend MV-04)"
  depends_on: [GF-40, GF-41]
  files:
    - scripts/player/PlayerCamera.gd
    - scripts/player/CameraShake.gd
    - scripts/movement/MovementConfig.gd
    - tests/player/test_camera_feel.gd
    - reports/checkpoints/2026-09-25_GF-43/
  reads:
    - docs/research/13_game_feel.md
    - scripts/combat/Weapon.gd
    - scripts/combat/feel/
    - scripts/player/StairStep.gd
    - tests/player/test_camera_shake.gd
  notes: >-
    PlayerCamera se branche lui-même sur le signal `fired` du Weapon de son joueur : Weapon.gd n'est pas
    modifié.
    View punch = rotation VISUELLE composée dans _apply_interpolated_transform, comme la secousse, jamais sur
    head.rotation : la direction de tir ne change pas.
    Recalibrer les constantes de trauma (CameraShake.gd:32, 49, 56-57) pour atteindre les cibles du §4.2.
    ADS : remplacer le lerp 16/s (PlayerCamera.gd:236) par FeelCurves.ads_progress(cfg.ads_time,
    cfg.ads_out_ratio), c'est-à-dire la MÊME courbe que le viewmodel GF-45.
    Creux d'atterrissage :
    - 0 à 6 cm ∝ vitesse de chute, dès 3 m ;
    - retour ease-out en 150 ms ;
    - exclu pour les pas de StairStep.
    coyote_time 0,10 et jump_buffer_time 0,12 (défauts de MovementConfig).
    « Mouvement réduit » : secousse 0, punch ≤ 0,3°, creux 0. « Secousses désactivées » : secousse et punch 0.
  acceptance: >-
    Tests purs :
    - pic de punch = cfg.view_punch_deg ± 10 % à l'image +1, retour < 10 % en view_punch_return_s ± 1 image ;
    - direction de tir identique avec et sans punch ;
    - spray Ravage d'1 s simulé → RMS de rotation 0,10–0,25° ; dégât reçu → pic 0,3–0,6° ; explosion → 1,0–1,5° ;
    - FOV à aim_fov exactement à ads_time ± 1 image (60 Hz), écart ≤ 2 % à la courbe FeelCurves ;
    - sortie en 0,85 × ads_time ;
    - chute de 3 m → creux 2–3 cm, de 6 m → 5–6 cm, retour 150 ± 17 ms ; marche d'escalier → 0 ;
    - réglages de confort respectés.
    feel_reel confirme les mêmes valeurs en jeu. tests/player verts.
    Captures : mp4 spray + ADS in/out + atterrissage, courbes FOV dans reports/checkpoints/2026-09-25_GF-43/.
  source: recherche 13 (lead 2026-09-25)

- id: GF-44
  epic: E2
  priority: P0
  size: M
  model: sonnet
  agent: builder
  title: "Effets de tir de la bible §9.2 : flash de bouche en étoile (FP/TP), traceur pinceau, douilles, bouffée de fumée"
  depends_on: []
  files:
    - scripts/vfx/MuzzleFlashFx.gd
    - scripts/vfx/TracerFx.gd
    - scripts/vfx/ShellFx.gd
    - assets/vfx/shot/
    - assets/shaders/fx_tracer.gdshader
    - scripts/player/ThirdPersonWeapon.gd
    - tests/vfx/test_shot_fx.gd
    - tools/review/shot_fx_shots.gd
    - reports/checkpoints/2026-09-25_GF-44/
  reads:
    - docs/STYLE_BIBLE.md
    - docs/research/13_game_feel.md
    - docs/research/12_viewmodel_v2.md
    - scripts/vfx/ComicFx.gd
    - assets/shaders/fx_flat.gdshader
    - scripts/combat/Weapon.gd
    - scripts/player/ViewModel.gd
  notes: >-
    Spécifications pures + spawners avec pools, dans le langage de ComicFx : GPUParticles3D à quads maillés,
    fx_flat, animés sur deux sauf le traceur. Valeurs du §4.3 (bible §9.2).
    Table famille → échelle du flash encodée dans MuzzleFlashFx (poing 0,7, fusil 1, pompe 1,4, lourde 1,2,
    Faucheur long).
    Pools : 1 flash réutilisé par arme, 32 traceurs, 8 douilles (≤ 4 visibles).
    Lueur OmniLight optionnelle (drapeau, 1 image, sans ombre).
    Le branchement FP se fait plus tard (GF-45 pour le flash et les douilles dans ViewModel.gd, GF-46 pour le
    traceur dans Weapon.gd).
    Le flash TP est branché ICI, dans ThirdPersonWeapon.gd (×1,5).
    Teintes réservées interdites (tasks/context.md).
  acceptance: >-
    Tests purs :
    - flash : 3 images en 50 ms, rotation ∈ [−25°, 25°], échelles par famille exactes, Faucheur allongé ≥ 2:1 ;
    - traceur : vie ≤ 80 ms, 400 m/s, longueur 3–6 m, largeur 2,5 cm, règle 1 balle sur 2 (automatiques) et
      1 plomb sur 3 ;
    - douille : chute de 0,6 s, ≤ 4 visibles ;
    - fumée ≤ 64 particules.
    shot_fx_shots (fenêtré) :
    - flash FP ≤ 6 % de l'écran à 1080p par famille ;
    - flash TP ≥ 6 px à 60 m (mesuré) ;
    - traceur en vol ;
    - douilles.
    style_check sans teinte réservée. perf_bench sans régression > 3 %.
    Captures : planche 4 JPG (flashs par famille, TP à 60 m, traceur, douilles) dans
    reports/checkpoints/2026-09-25_GF-44/.
  source: recherche 13 (lead 2026-09-25)

- id: GF-45
  epic: E2
  priority: P0
  size: M
  model: sonnet
  agent: builder
  title: "Viewmodel qui cogne : kick par profil (visible), inertie de strafe et de saut, inclinaison en glissade, ADS à easing partagé, flash et douilles §9.2 branchés"
  depends_on: [FP-14, GF-40, GF-41, GF-44]
  files:
    - scripts/player/ViewModel.gd
    - scripts/player/viewmodel/ViewModelKick.gd
    - tests/player/test_viewmodel_kick.gd
    - reports/checkpoints/2026-09-25_GF-45/
  reads:
    - docs/research/13_game_feel.md
    - docs/research/12_viewmodel_v2.md
    - docs/STYLE_BIBLE.md
    - scripts/combat/feel/
    - scripts/vfx/MuzzleFlashFx.gd
    - scripts/vfx/ShellFx.gd
    - scripts/player/viewmodel/
  notes: >-
    Remplacer le ressort AnimState et sa chaîne ×6 / ×0,02 / ×0,03 / ×0,35 (ViewModel.gd:569, 528-529, 544,
    978-979) par ViewModelKick (KickSpring + profil cfg).
    Kick composé APRÈS le passe-bas position.lerp 18/s (ViewModel.gd:541), jamais dedans.
    Roulis et lacet aléatoires par tir ; ADS ×0,4 ; contre-poussée en spray.
    Inertie :
    - strafe ≤ 1,5 cm avec retard (ressort) au départ et à l'arrêt ;
    - saut +1 cm ;
    - garder le creux d'atterrissage de FP-14.
    Glissade : inclinaison de 15° (au lieu de 6°, ViewModel.gd:543).
    ADS : FeelCurves.ads_progress, la même courbe que la caméra GF-43.
    Flash FP : MuzzleFlashFx au repère Muzzle ; supprimer _spawn_muzzle_flash (carré de 12 cm).
    Douilles : ShellFx au repère Eject du JSON FP (repli : décalage fixe pour les armes legacy) ; à chaque tir,
    ou sur anim_event pump_back (Fracas), eject (Magnum ×6), bolt_back (Faucheur).
    Ne pas changer les priorités de ViewModelAnimator (FP-14).
  acceptance: >-
    feel_reel (60 i/s, hanche) pour chacune des 7 armes :
    - déplacement de la bouche à 1080p ≥ minimum du §4.1 (poing 15, SMG 6, fusil 10, précision 20, magnum 50,
      pompe 35, sniper 40 px) ;
    - pic à ≤ +2 images ;
    - retour < 10 % en ≤ 0,9 × intervalle (automatiques) ou ≤ valeur du §4.1 ;
    - ADS : kick ×0,4 ± 10 % ;
    - carré central 20 % × 20 % vide au pic ;
    - FOV et arme à 100 % d'ADS dans la même image ± 1 ;
    - ≤ 4 douilles visibles.
    tests/player/test_viewmodel_kick.gd vert. Tests FP-14 (animator, contrat) et fp_shots verts.
    Captures : planche 4 JPG (pic de kick par famille) + mp4 avant / après dans
    reports/checkpoints/2026-09-25_GF-45/.
  source: recherche 13 (lead 2026-09-25)

- id: GF-46
  epic: E2
  priority: P0
  size: M
  model: sonnet
  agent: builder
  title: "Arme côté client : cadence et gâchette à la fréquence d'image pour l'humain local, traceurs §9.2 branchés"
  depends_on: [FP-14, GF-40, GF-44]
  files:
    - scripts/combat/Weapon.gd
    - scripts/combat/FireClock.gd
    - scripts/player/PlayerInput.gd
    - scripts/combat/RateLimiter.gd
    - tests/combat/test_fire_cadence.gd
    - reports/checkpoints/2026-09-25_GF-46/
  reads:
    - docs/research/13_game_feel.md
    - docs/research/01_game_feel.md
    - scripts/combat/ShotValidator.gd
    - scripts/vfx/TracerFx.gd
    - tests/combat/
  notes: >-
    Humain local seulement :
    - PlayerInput échantillonne les fronts de gâchette dans _process ;
    - Weapon fait avancer FireClock avec le delta de rendu et tire dans l'image du clic.
    Bots et serveur : inchangés, au tick physique.
    Origine (head.global_position) et contrat de validation inchangés (GF-06, BUG-26).
    Vérifier la tolérance de RateLimiter pour des intervalles gigués autour de 1/cadence, la corriger au besoin
    avec un test.
    Remplacer _spawn_tracer (ImmediateMesh d'1 px, Weapon.gd:1164-1179) par TracerFx : 1 balle sur 2 pour les
    automatiques, 1 plomb sur 3.
    Ne pas toucher au raycast local d'impact (GF-06).
    GF-14 écrit aussi dans Weapon.gd : sérialisé par plan.py.
  acceptance: >-
    Tests :
    - FireClock à 144 Hz avec ±20 % de gigue d'image → intervalle moyen = 1/cadence ± 1 %, écart-type ≤ 3 ms
      pour Rafale, Éclair, Semeuse et Ravage (aujourd'hui ±8,3 ms) ;
    - 30 s de tir automatique à 144 i/s gigué → 0 tir refusé par le serveur ;
    - clic → `fired` dans la même image de rendu ;
    - traceurs ≈ 50 % des balles (automatiques).
    feel_reel --fixed-fps 144 : écart-type des intervalles entre attaques du WAV ≤ 3 ms.
    gameplay_probe fire_in_state inchangé. tests/combat verts.
    Captures : histogramme des intervalles avant / après + mp4 Rafale dans reports/checkpoints/2026-09-25_GF-46/.
  source: recherche 13 (lead 2026-09-25)

- id: GF-47
  epic: E2
  priority: P1
  size: M
  model: sonnet
  agent: builder
  title: "Sons de tir v2 synthétisés : variations, mécanique par famille, fin de chargeur, dernier coup, impacts, sifflements, couches ennemies par distance, paliers de kill, bruitages de rechargement"
  depends_on: []
  files:
    - tools/audio/gen_sfx.py
    - tools/audio/gen_weapon_layers.py
    - tools/audio/gen_feel_sfx.py
    - tests/audio/test_gen_feel_sfx.py
    - assets/audio/sfx/
  reads:
    - docs/research/13_game_feel.md
    - docs/research/12_viewmodel_v2.md
    - scripts/core/Audio.gd
  notes: >-
    Synthèse UNIQUEMENT : aucun téléchargement (option B du §6 = tâche AUD séparée, sur accord de l'utilisateur).
    Réutiliser les primitives DSP de gen_sfx.py.
    À produire :
    - ≥ 4 variations par couche locale (transitoire, corps, mécanique, sub) et par classe ;
    - couche mécanique de 60 à 120 ms par famille (culasse, glissière, pompe, barillet) ;
    - mech_low (grelot creux 2–4 kHz) par classe ;
    - last_round (ping) ;
    - impacts : impact_world ×4, impact_metal ×3 (CLING), impact_body ×4 (thwack comique) ;
    - whizz ×4 (balayage de 150 à 250 ms) ;
    - couches ennemies close et mid par classe (far existe) ;
    - kill_confirm_t1..t5 ;
    - un son par événement de la liste fermée du doc 12 §3.5 ;
    - shell_tink ×3.
    Écrire assets/audio/sfx/feel_gains.json (gain relatif conseillé par nom, en dB), consommé par GF-48.
    Les noms existants restent valides : rien n'est supprimé.
  acceptance: >-
    pytest tests/audio/test_gen_feel_sfx.py :
    - chaque nom du manifeste existe, en mono 48 kHz, crête ≤ −1 dBFS ;
    - durées dans les fourchettes (mécanique 60–120 ms, whizz 150–250 ms) ;
    - centroïde spectral : whizz 2–6 kHz, impact_body < impact_world ;
    - 4 variations distinctes par couche (corrélation croisée < 0,95).
    Import Godot sans erreur.
    Captures : planche de spectrogrammes + montage d'écoute WAV de 20 s dans reports/checkpoints/2026-09-25_GF-47/.
  source: recherche 13 (lead 2026-09-25)

- id: GF-48
  epic: E2
  priority: P1
  size: M
  model: sonnet
  agent: builder
  title: "Mix de tir v2 : hauteur commune aux couches, tirs ennemis en couches et spatialisés (bus Shots), fin de chargeur, impacts, sifflements, paliers de kill, bruitages de rechargement sur événements"
  depends_on: [FP-14, GF-40, GF-47]
  files:
    - scripts/core/Audio.gd
    - default_bus_layout.tres
    - scripts/combat/ImpactFx.gd
    - tests/audio/test_audio_feel.gd
    - reports/checkpoints/2026-09-25_GF-48/
  reads:
    - docs/research/13_game_feel.md
    - scripts/ui/HudFormat.gd
    - scripts/ui/hud/HitFeedback.gd
    - scripts/combat/Weapon.gd
    - assets/audio/sfx/feel_gains.json
  notes: >-
    Une hauteur tirée par tir local, partagée par les 5 couches (±4 %), plus ±1 % par couche : aujourd'hui
    chaque couche tire ±5 % indépendamment (Audio.gd:931). AudioStreamRandomizer en RANDOM_NO_REPEATS.
    Fin de chargeur : mech_low via ammo_changed, quand mag/mag_size ≤ HudFormat.LOW_AMMO_RATIO, rampe 0 → +6 dB ;
    last_round au passage 1 → 0.
    Tirs ennemis :
    - couche close, mid ou far selon la distance (15 / 45 m) ;
    - AudioStreamPlayer3D réglé (unit_size ≈ 8, max_distance 150) ;
    - bus Shots (ducké).
    Sifflement : fonction pure de distance minimale entre le rayon distant (origine, directions de
    remote_fired) et la tête d'écoute. < 1,5 m sans toucher → whizz 2D panoramiqué, ≤ 4/s.
    Impacts : ImpactFx appelle Sfx.play_at (monde, corps), ≤ 6 voix.
    Kill : palier t1..t5 selon HitFeedback.MULTI_KILL_WINDOW.
    anim_event (FP-14) : mapper TOUS les événements de la liste fermée, plus seulement mag_out et mag_in.
  acceptance: >-
    Tests purs :
    - les 5 couches à la même hauteur ± 1 % ;
    - courbe de gain de fin de chargeur (25 % → 0 dB, 1 balle → +6 dB) ;
    - sifflement : raté à 1,0 m → oui, à 2,0 m → non, touché → non ;
    - couche selon la distance (10 / 30 / 60 m → close / mid / far) ;
    - palier de kill borné à 1..5.
    feel_reel :
    - pendant un spray, crête Feedback ≥ crête Shots − 3 dB dans les 90 ms qui suivent un hit ;
    - tir ennemi à 20 m ≥ 10 dB sous le tir local.
    tests/audio verts.
    Captures : graphique des crêtes de bus + montage WAV (spray, fin de chargeur, kill ×3, sifflements) dans
    reports/checkpoints/2026-09-25_GF-48/.
  source: recherche 13 (lead 2026-09-25)

- id: GF-49
  epic: E2
  priority: P1
  size: S
  model: sonnet
  agent: builder
  title: "Réglage fin du ressenti des 7 armes (valeurs .tres uniquement) + vidéo avant / après pour l'utilisateur"
  depends_on: [GF-42, GF-43, GF-45, GF-46, GF-48]
  files:
    - resources/weapons/
    - docs/WEAPONS.md
    - reports/checkpoints/2026-09-25_GF-49/
  reads:
    - docs/research/13_game_feel.md
    - reports/feel/
  notes: >-
    Lancer feel_reel sur les 7 armes v2 et n'ajuster que les champs du groupe « Sensations » et les motifs de
    recul, dans les fourchettes du §4.
    Ajouter une section « Sensations » d'1 page à docs/WEAPONS.md (valeurs et mesures avant / après).
    Monter la vidéo pour le lead (≤ 60 s, les 7 armes, en hanche, ADS, spray et rechargement).
    Aucun code.
  acceptance: >-
    summary.md de feel_reel : toutes les métriques du §4 en PASS pour les 7 armes.
    Suite gdUnit complète verte ; run_review complet sans nouvel échec.
    Captures : mp4 ≤ 60 s + 4 JPG dans reports/checkpoints/2026-09-25_GF-49/.
  source: recherche 13 (lead 2026-09-25)

- id: GF-50
  epic: E2
  priority: P2
  size: S
  model: sonnet
  agent: builder
  title: "Rechargement : chargeur crédité à mag_in (≈ 0,78 × reload_time), changement d'arme ensuite sans perte (DÉCISION requise)"
  depends_on: []
  files:
    - scripts/combat/Inventory.gd
    - tests/combat/test_reload_commit.gd
  reads:
    - docs/research/12_viewmodel_v2.md
    - docs/research/13_game_feel.md
    - scripts/combat/Weapon.gd
  notes: >-
    NE PAS LANCER sans décision du lead et de l'utilisateur. Le doc 12 §3.6 laisse cette question à E2 ; Far Far
    West crédite vers 60 %.
    Nouveau reload_commit_ratio (constante, 0,78 = mag_in du FP-13, fourchette 0,70–0,82) :
    - passé ce point, le chargeur est crédité et un changement d'arme ou une annulation garde les balles ;
    - avant, le rechargement est perdu.
    La fin du rechargement reste à reload_time : les clips FP et le test de FP-14 sont inchangés.
    Même fonction pure côté serveur et côté prédiction client.
    On garde un seul reload_time. Apex rallonge le rechargement à vide de 33 % (2,4 → 3,2 s), mais FP-13 cuit
    reload et reload_empty à la même durée.
  acceptance: >-
    Tests :
    - changement d'arme à 0,80 × reload_time → chargeur plein et réserve décrémentée ;
    - à 0,50 × → chargeur inchangé ;
    - serveur et client identiques.
    tests/combat verts ; gameplay_probe reload OK.
  source: recherche 13 (lead 2026-09-25)
```

---

## 9. Sources de ce document

**Lues par le lead :**
- [davidbdurst — CS:GO recoil](https://davidbdurst.com/blog/csknow_recoil.html)
- [dcprosens — ADS 0 % MDM](https://dcprosens.com/ads/)
- [Godot — Movie Maker](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html)

**Lues par l'agent de recherche pendant cette session :**
- Recul et maniement :
  - [Valorant Vandal](https://wiki.playvalorant.com/en-us/Vandal), [Valorant Sheriff](https://wiki.playvalorant.com/en-us/Sheriff),
    [Valorant Kill Banners](https://wiki.playvalorant.com/en-us/Kill_Banners)
  - [Apex R-301](https://apexlegends.wiki.gg/wiki/R-301_Carbine),
    [Dexerto, motifs Apex](https://www.dexerto.com/apex-legends/updated-recoil-patterns-for-all-weapons-in-apex-legends-1354210/)
  - [BO6 XM4](https://codmunity.gg/weapon/bo6/xm4), [wzstats XM4](https://wzstats.gg/best-loadouts/xm4)
  - [Destiny Recoil Direction](https://d2.destinygamewiki.com/wiki/Recoil_Direction),
    [forum Bungie](https://www.bungie.net/en/Forums/Post/247015231)
- TTK d'arène :
  - [Splitgate](https://www.splitgate.com/news/splitgate-arena-reloaded-launch-overview/),
    [Warden](https://splitgatearenareloaded.wiki.gg/wiki/Warden)
  - [The Finals TTK](https://thefinalsloadout.com/ttk)
- Retour de touche et hitstop :
  - [Shacknews Apex](https://www.shacknews.com/article/110042/how-to-change-damage-numbers-in-apex-legends)
  - [Borderlands 3](https://blog.playstation.com/2019/08/14/8-irresistible-gameplay-improvements-in-borderlands-3/)
  - [Ultrakill parry](https://ultrakill.wiki.gg/wiki/Parrying)
  - [Smash hitlag](https://www.ssbwiki.com/Hitlag),
    [critpoints](https://critpoints.net/2017/05/17/hitstophitfreezehitlaghitpausehitshit/),
    [Sakurai](https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/)
- Audio d'arme :
  - [Kilborn](https://blog.prosoundeffects.com/how-to-sound-design-first-person-shooter-gunshot-sound-effects-with-mark-kilborn)
  - [Arcella](https://www.arcellasound.com/post/aaa-weapon-sound-design-architecting-modular-combat-audio-for-xdev-pipelines)
  - [Apex 1.1.3](https://www.player.one/apex-legends-update-113-audio-hit-detection-issues-fixed-126388)
- Doc Godot :
  - [AudioStreamRandomizer](https://docs.godotengine.org/en/stable/classes/class_audiostreamrandomizer.html),
    [AudioStreamPlayer3D](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html),
    [AudioEffectCompressor](https://docs.godotengine.org/en/stable/classes/class_audioeffectcompressor.html)
  - [jitter / stutter / input lag](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html),
    [interpolation physique](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html)
  - [forum Godot, head-bob](https://forum.godotengine.org/t/how-to-make-a-smooth-camera-bob-system/90613)
- Licences audio :
  - [Sonniss GDC](https://sonniss.com/gdc-bundle-license/), [Kenney](https://kenney.nl/support),
    [Freesound](https://freesound.org/help/faq/), [OpenGameArt](https://opengameart.org/content/faq),
    [juicy-breakout](https://github.com/grapefrukt/juicy-breakout)
- Jus et références stylisées :
  - [Nijman, transcription](https://theengineeringofconsciousexperience.com/jan-willem-nijman-vlambeer-the-art-of-screenshake/),
    [notes Weidar](https://victorweidar.wordpress.com/2016/10/06/the-art-of-screenshake/),
    [Juice it or lose it](https://www.richtaur.com/GameDevTreasure/post/juice-it-or-lose-it/)
  - Far Far West : [GamingTrend](https://gamingtrend.com/previews/far-far-west-preview/),
    [COGconnected](https://cogconnected.com/preview/far-far-west-preview/),
    [Game8](https://game8.co/articles/reviews/far-far-west-review-early-access),
    [Steam](https://store.steampowered.com/app/3124540/)
  - [Titanfall](https://www.gamedeveloper.com/design/designer-interview-getting-i-titanfall-i-s-controls-just-right),
    [Dev_Unallocated](https://www.devunallocated.com/projects/project-killhouse/procedural-weapon-animations-condensed)
- Latence : [arXiv 2105.10498](https://arxiv.org/abs/2105.10498)

**Déjà cités et non relus ici :** voir `01_game_feel.md` §2 et `12_viewmodel_v2.md` §7.
