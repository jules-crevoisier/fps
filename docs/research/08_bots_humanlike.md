# 08 — Des bots qui jouent comme des joueurs : spec mesurable (Wasteland, TDM + Hardpoint)

> Recherche du 24/09/2026. Verdict du playtest : les bots ont encore des « mouvements suspects ».
> Il faut une attitude de jeu qui imite de vrais joueurs, « comme Apex ou d'autres FPS ».
> Ce document complète `02_bots_ai.md` (architecture, tâches BOT-01 à BOT-13) et `docs/audit/bots.md`.
> Il ne traite que **ce qui se voit** : regard, rythme, déplacement, placement, synchronisation.
> Chaque règle est chiffrée et testable. Périmètre : **une carte, Wasteland, en TDM 4v4 et Hardpoint**.
> Aucun code n'a été modifié.
>
> Déjà en place (à ne pas refaire) :
> - visée en angle avec ressort-amortisseur et tir conditionné (BOT-02) ;
> - discipline de combat : rafales, distance par arme, plantage des armes de précision (BOT-04) ;
> - anti-blocage et évitement RVO (BOT-09) ;
> - objectifs stables et sans omniscience (BOT-01) ;
> - BotSpots bakés (BOT-05/05B) ;
> - banc `tools/bot_bench.gd` (BOT-13, en cours).

## 0. Résumé

1. **Ce qui trahit un bot** (études de perception CHI 2023, BotPrize, Halo) : une caméra qui pivote d'un coup, des blocages ou collisions, des déplacements sans but, un rythme mécanique. Ce n'est pas un « manque d'intelligence ».
2. **Nos pires signes sont visibles hors combat.**
   - En TDM sur Wasteland, les bots font la navette entre deux marqueurs de spawn distants de 2 m.
   - Ils sautent ou s'accroupissent au hasard toutes les 3 à 7 s, même à l'arrêt. Vu de loin, ça ressemble à du teabag.
   - Ils regardent pile dans l'axe du chemin, tangage figé, à 220°/s constants.
3. **En combat, leurs gestes sont mécaniques.**
   - Ils avancent toujours vers la cible : « reculer » ralentit seulement l'avance.
   - Ils strafent en sprint, jusqu'à 15 m du même côté.
   - Le viseur fait un micro-flick visible toutes les 0,35 à 0,7 s.
   - Les armes semi-auto tirent au métronome, à cadence max, et l'ADS clignote.
4. **L'équipe se déplace en essaim** : toute l'équipe fonce au même point au même tick. En cause, une mémoire d'équipe partagée sans délai et l'invalidation de tous les buts à chaque kill.
5. **Référence la plus chiffrée : le bot CS** (Booth / Turtle Rock, code reconstruit dans ReGameDLL, plus botprofile.db).
   - Regard sur un ressort quasi critique, accélération plafonnée à 3000°/s².
   - L'erreur de visée dérive au lieu de sauter.
   - Le bot voit les ennemis avec son temps de réaction de retard.
   - Il change de point de regard toutes les 1 à 2 s.
   - Esquive à 4 états, changée toutes les 0,3 à 1,0 s.
   - Tir semi-auto espacé de 0,15 à 0,4 s.
6. **Halo Infinite** :
   - choix des actions par score (utility) avec hystérésis ;
   - une « confiance » qui décide d'avancer ou de reculer ;
   - 200 à 250 ms de latence de décision, jugée plus humaine ;
   - connaissance des positions ennemies partagée seulement aux hautes difficultés.
7. **La spec** : 38 règles numérotées (regard L, visée A, mouvement M, combat C, perception P, équipe T), une table de connaissance de carte (K) et 21 métriques de banc (B1 à B21).
8. **Wasteland n'a pas de données exploitables.** `resources/bot_spots/wasteland.tres` est inutilisable : 71 spots, dont 3 au sol. Il faut une table de connaissance de carte (couloirs, angles, perchoirs, positions Hardpoint), fournie ici en brouillon (§3.7).
9. **Le banc actuel ne voit pas ces défauts.**
   - Il tourne sur cargo_ship par défaut.
   - Il ne compte un changement de but qu'au-delà de 5 m.
   - Il ne mesure ni le regard ni le rythme.

   Il faut d'abord le compléter pour avoir une mesure de départ.
10. **Plan** : BOT-20 (banc), puis BOT-21 (signes immédiats), puis BOT-22 à BOT-24 (carte, objectifs, Hardpoint), puis BOT-25 à BOT-27 (regard, visée, mouvement de combat), puis BOT-28 et BOT-29 (suivi de chemin, perception).

## 1. Constats sourcés

Numéros de source [Sx] : voir §6. Les valeurs CS sont en unités Hammer (1 u ≈ 2,54 cm).

| # | Pratique observée dans un jeu livré ou une étude | Source | Chiffre | Chez nous |
|---|---|---|---|---|
| 1 | Regard CS : ressort `accel = k·Δ − d·ω`, accélération plafonnée, tangage à 2·k | [S2] [S5] | CS 1.6 : k 200 / d 25 hors combat, k 300 / d 30 en combat, plafond 3000°/s². Profils CS:GO : 100/25 et 150/30, plafond 2000/3000. ζ ≈ 0,87-1,25, donc dépassement quasi nul. Le plafond donne un pic ≈ 520°/s sur 90° et ≈ 735°/s sur 180° | Combat : ζ = 0,59, soit 10 % de dépassement à chaque flick, sans plafond d'accélération (180° atteint 1000°/s en Vétéran). Hors combat : 220°/s linéaires, accélération infinie |
| 2 | Offset de visée CS : l'offset courant **dérive** vers un nouvel objectif. La précision s'affine en restant sur la cible, et repart si la vue tourne vite | [S3] | Nouvel objectif toutes les 0,25-1,0 s. Dérive : 10 % de l'écart par mise à jour (τ ≈ 0,16 s à 60 Hz). Affinage en 2-5 s, plafonné à 75 %. Remise à zéro si la vue tourne à plus de 100°/s | L'offset **saute** sur un anneau toutes les 0,35-0,7 s, puis le ressort flicke jusqu'à lui |
| 3 | Profils de difficulté CS (botprofile.db, Easy / Normal / Hard / Expert) | [S5] | Réaction 0,70 / 0,5 / 0,3 / 0,2 s. Délai avant le 1er tir 0,8 / 0 / 0 / 0. Erreur initiale 20 / 6 / 2,2 / 1,2°. Part d'erreur restante après 1 s 0,8 / 0,6 / 0,18 / 0,1 (τ ≈ 4,5 / 2,0 / 0,58 / 0,43 s). Intervalle de réglage 0,8 / 0,6 / 0,3 / 0,08 s | Erreur initiale 5 / 2,5 / 1° : cohérent. Mais τ = 0,8 s et intervalle 0,35-0,7 s identiques aux trois difficultés |
| 4 | File de réaction CS : le bot voit l'ennemi tel qu'il était un temps de réaction plus tôt | [S2] | Retard = `ReactionTime` (Expert 0,2 s) | Réaction appliquée seulement avant le 1er tir. Ensuite, suivi de la position **vraie** à chaque tick |
| 5 | Visée humaine en FPS : l'erreur finale est allongée dans l'axe du mouvement | [S14] | Ellipses d'erreur de rapport 2,14 à 2,51. Acquisition souris ≈ 614 ms (sujets entraînés). Vitesse de pointe proportionnelle à l'amplitude | Erreur isotrope, de rayon constant (anneau) |
| 6 | Sous-mouvements de visée : la littérature est partagée | [S15] | Elliott : le 1er mouvement vise plutôt court. PLOS One 2017 : sous contrainte de temps, les dépassements dominent et viser court est rare. Il faut donc un ratio tiré à chaque flick | 10 % de dépassement fixe à chaque flick |
| 7 | Temps de réaction humain | [S16] [S6] | Distribution asymétrique (ex-gaussienne). Médiane grand public ≈ 273 ms (voir 02). Halo : 200-250 ms de traitement, « human reactions are slower » | Constante : 450 / 300 / 200 ms, sans aucune variance |
| 8 | Cadence de tir CS | [S3] | Pistolet : 0,15-0,4 s entre tirs. Cible au-delà de ~20 m (800 u) : 0,3-0,7 s. Rafales à mi-distance : 0,15-0,5 s | Semi-auto : `fire_pressed` vrai à chaque tick, donc cadence max en métronome |
| 9 | Tirer en bougeant | [S17] | Tir précis si la vitesse est sous 34 % du max (définition Leetify du contre-strafe) | Armes de précision : moins de 30 % du sprint (OK). Autres armes : strafe en sprint permis |
| 10 | Détection anti-triche : on juge un tir sur la rotation qui l'entoure | [S18] | VACnet : fenêtre de 0,5 s avant et 0,25 s après chaque tir | Non mesuré |
| 11 | Esquive CS : 4 états (STEADY, SLIDE_LEFT, SLIDE_RIGHT, JUMP). L'accroupi dépend de la distance | [S4] | Changement d'état toutes les 0,3-1,0 s. Probabilité d'esquiver : 80 % × skill. Accroupi : 50 % au sniper ou au-delà de ~19 m (750 u), sinon 20 % × (1 − agressivité), et seulement si la ligne de vue est dégagée | 2 états seulement, gauche et droite. 0,8-1,8 s entre inversions tant qu'il n'est pas touché, en sprint. Jamais d'arrêt, sauf arme de précision |
| 12 | Poursuite CS | [S4] | Attendre 2 + 2·(1 − agressivité) s avant de poursuivre, +3 s pour un sniper. « Pinned down » : 7-10 s | À la perte de la ligne de vue, retour immédiat au but (souvent la dernière position partagée), en sprint |
| 13 | Regard hors combat CS | [S2] | Nouveau point d'intérêt toutes les 1-2 s (sniper : 5-10 s). Revérification d'un point de rencontre toutes les 10 s. Vision périphérique toutes les 0,29 s | Regard = cap du chemin |
| 14 | Remarquer un ennemi (CS, reconstruit par ReGameDLL, activable) | [S2] | Parties visibles pondérées : torse 40 %, tête 10 %, chaque côté 20 %, pieds 10 %. Baisse avec la distance, dépend de la posture et de la vitesse. Test toutes les 0,25 s | Un seul rayon vers la tête, à chaque tick |
| 15 | Halo Infinite : utility avec hystérésis, « confidence » pour avancer ou reculer, info d'équipe selon la difficulté | [S6] [S8] | Sans hystérésis, le bot oscille entre deux choix (« thrash »). Le partage des positions ennemies les a gardés trop longtemps en combat, au détriment des objectifs. Réaction aux tirs par saut ou strafe « comme les joueurs » | Pas d'hystérésis de comportement (prévu en BOT-07). Pas de notion de confiance |
| 16 | Halo : un bug de traversée perçu comme du teabag | [S9] | Un saut raté sur une marche ou une rampe lance une boucle d'atterrissage qui ressemble à des accroupis répétés | Notre déblocage (oscillation à 5 Hz puis saut) et nos accroupis au hasard |
| 17 | MLMove : bots de CS:GO appris sur 123 h de matchs pros | [S11] | Les bots par défaut combattent en terrain ouvert, suivent des trajets rigides et quittent la hauteur. Les humains restent près des murs en attaque. Distance à l'occupation de carte humaine (EMD) : 8,2 pour MLMove contre 14,7 et 15,2 pour les bots scriptés. Coût < 0,5 ms par pas | Chemin navmesh le plus court. Combats en terrain ouvert |
| 18 | Comment les gens reconnaissent une navigation humaine (CHI 2023) | [S12] | Critères des juges : fluidité (du **déplacement et de la caméra**), but apparent, évitement des collisions, attention à l'environnement. Défauts relevés chez les agents : caméra qui pivote brutalement, collisions, lenteur. Précision médiane des juges face à ces agents : 0,83 | — |
| 19 | UT^2 / BotPrize | [S13] | Être bloqué est « très bot » (priorité n°1 du bot). Précision réduite par le mouvement propre, celui de la cible et la distance. Toujours regarder l'adversaire pendant ses actions. Pas de recul vers un mur, strafe forcé si un mur est proche. Gagnants 2012 : 52 % d'humanité, contre 41 % pour les humains | Partiel (BOT-02, BOT-09) |
| 20 | Killzone 3, F.E.A.R., Rainbow Six Siege | [S21] [S22] [S23] | Killzone 3 : positions choisies par score, couverture par direction. F.E.A.R. : tir de suppression pendant que les alliés avancent, ordres criés qui rendent l'intention lisible. Siege (Terrohunt) : archétypes (le Roamer contourne), un « AI Strategy Manager », difficulté portée par le placement, la précision et le mouvement plutôt que par les dégâts | — |
| 21 | Portée des sons | [S20] | Tir : toute la carte. Pas de course : ~28 m (CS, ~1100 u) à ~50 m (Valorant, chiffre communautaire) ; marche : 15 m. Riot privilégie le fait d'**entendre** sur celui de **situer** | Tirs uniquement, 22 m, position exacte |
| 22 | Échange de kill (trade) | [S26] (secondaire) | Un vrai trade arrive 0,5-1 s après la mort de l'allié | Aucun |
| 23 | Bots de remplissage récents | [S10] [S25] | Apex : escouades ennemies complètes, lobbies de bas niveau. Respawn mesure l'écart de niveau, l'attente en file et la progression, et parle de « test ». Overwatch 2 : bots possibles sur les 5 premiers matchs. Aucune doc technique publique | Règle maison : bots toujours signalés |

**Sources manquantes.** Pas de source primaire sur les bots joueurs de Titanfall 2, de Call of Duty ni de Splitgate. Pour Titanfall, seule l'IA « popcorn » des minions est décrite, volontairement non joueuse. Leçon utile : la grimpe des Spectres est prise pour des Pilotes [S24]. Le vocabulaire de déplacement suffit à lire « joueur ». Pour Apex et Siege, on n'a que les descriptions de l'éditeur.

## 2. Diagnostic : ce qui paraît suspect chez nous (classé)

| Rang | Ce que voit le joueur | Cause (fichier:ligne) | Pourquoi ça trahit | Règles |
|---|---|---|---|---|
| 1 | **En TDM, bots qui piétinent au spawn puis foncent à 4** | La patrouille utilise les marqueurs de spawn (`GameMode.gd:290-300`). Wasteland n'a pas de `tdm_spawns` (`MapSetup.gd:315-316`) : il n'y a que 8 marqueurs, en deux carrés 2×2 à x = ±36,5 / ±38,5 (`wasteland.gd:204-215`). Le bot apparaît pile sur un marqueur (`GameWorld.gd:897-927`) et le but est « atteint » à 2,5 m (`GameMode.gd:48,244-246`). Il alterne donc entre deux marqueurs distants de 2 m. Seule une vue directe (portée 45 m, alors que les spawns sont à 74 m l'un de l'autre) ou un tir à moins de 22 m l'en fait sortir. *Déduit du code, à confirmer par B13.* | Aucun but apparent (CHI 2023), puis ruée collective | T1, K |
| 2 | **Sauts et accroupis au hasard hors combat** | Tirage toutes les 3-7 s : 40 % saut, 30 % accroupi, même à l'arrêt (`BotBrain.gd:518-531`). En sprint, un appui accroupi déclenche une glissade (`Sprint.gd:2`) | Bunny-hop sans raison et « teabag » (cas Halo [S9]) | M1 |
| 3 | **Regard de robot** | Hors combat, le lacet suit le cap du chemin. Le tangage reste figé à sa dernière valeur de combat. Rotation à 220°/s linéaires, sans accélération (`BotBrain.gd:32,395-401,447-451`). Virage sec à chaque coin de la navmesh | La « caméra qui pivote brutalement » est le 1er défaut relevé (CHI 2023, P1). Un joueur regarde les angles, pas ses pieds (CS : 1-2 s par point) | L1-L6 |
| 4 | **En Hardpoint, pile de 8 bots au centre de la zone, puis statues** | Tous les bots visent le centre exact de la zone (`HardpointMode.gd:141-142`). Arrivé, `move_world_dir` vaut zéro, donc plus aucune rotation (cf. BOTFIX-01). Les bots se bousculent entre eux (évitement RVO) | Synchronisation et immobilité | T5, K |
| 5 | **Avance toujours vers la cible, strafe en sprint** | En combat, le but de navigation *est* la cible (`BotBrain.gd:413`). « Reculer » ajoute +0,6 à une avance de −1 : le bot avance encore à 40 % (`:474-477`). Strafe ±0,8, inversé toutes les 0,8-1,8 s (`BotCombatStyle.gd:134-135`), en sprint automatique à 8,2 m/s (`Sprint.gd:1`) : soit 6 à 15 m d'un côté, sans jamais s'arrêter | Un fusil à pompe qui « recule » en avançant. Un latéral de 15 m sans raison | M4, C2 |
| 6 | **Micro-flicks réguliers du viseur** | L'offset saute sur un anneau de rayon égal à l'erreur toutes les 0,35-0,7 s (`BotBrain.gd:360-366`). Le ressort flicke jusqu'à lui avec 10 % de dépassement (`BotAim.gd:131`) | Visible en killcam et en spectateur, avec le même ratio à chaque flick. CS fait **dériver** l'offset | A2-A4 |
| 7 | **Tir en métronome, ADS qui clignote** | `fire_pressed` est vrai à chaque tick (`BotBrain.gd:329-330`, lu par `Weapon.gd:210`), donc cadence max. `aim_held` suit `base_can_shoot` (`BotBrain.gd:328`) : l'ADS s'allume et s'éteint quand l'erreur franchit le seuil, et la vitesse saute entre 8,2 et 3,6 m/s | Rythme inhumain | A7, A8 |
| 8 | **Réaction toujours identique** | `BotReaction.gd:16-23` : valeur constante | Une réaction humaine varie, avec une queue de valeurs lentes | A6 |
| 9 | **Essaim** | Chaque bot qui voit un ennemi le signale à chaque tick, sans délai (`BotBrain.gd:235-240`, `GameMode.gd:273-274`). En TDM, le but devient ce point pour tous (`TDMMode.gd:89-93`). Chaque kill invalide les buts de **tous** les bots des deux équipes (`TDMMode.gd:78`, `GameMode.gd:226-227`). Les recalculs de chemin sont en phase (`BotBrain.gd:52,414-417`) | Changements de direction synchronisés | T2, T3 |
| 10 | **Sourd et sans réflexe** | Ouïe limitée aux tirs, à 22 m, avec la position exacte, et ignorée dès qu'un ennemi est visible (`BotBrain.gd:30,130-135,216-228`). Aucune réaction aux dégâts reçus hors champ (BOT-03 non fait) | « Touché dans le dos, il continue ». En enquête, il va pile au bon endroit | P1-P3, C3 |
| 11 | **Déblocage visible** | Oscillation à 5 Hz puis saut (`BotStuck.gd:40-41`). Banc sur Cargo Ship : 3,8 à 5,0 % du temps bloqué (`reports/bot_bench/verify_chain.json`, `verify_elite_snd_ts6.json`, runs courts), au-dessus du seuil de 2 %. Wasteland compte 5 escaliers et 3 rampes | Le « teabag » de Halo, le bot qui rebondit dans les portes (BotPrize) | M5, M6 |
| 12 | **Outillage aveugle** | Le banc tourne sur cargo_ship par défaut (`bot_bench.gd:72`). Un changement de but n'est compté qu'au-delà de 5 m (`:86`) : la navette à 2 m est invisible. Rien ne mesure le regard, le rythme ni l'écart entre coéquipiers. `wasteland.tres` : 71 spots, 3 au sol (y ≈ 0,5), 68 marqués « sniping », donc inutilisable pour la couverture et le peek | On ne peut pas prouver qu'on s'améliore | BOT-20, BOT-22 |

## 3. Comportement cible (règles testables)

Les triplets de valeurs se lisent Recrue / Vétéran / Élite (R/V/É). U(a;b) désigne un tirage uniforme entre a et b, N(m;s) un tirage gaussien de moyenne m et d'écart-type s.

### 3.1 Regard hors combat (L)

- **L1 — Le regard est indépendant du déplacement** (Booth).
  - Il change de cible toutes les U(1,0 ; 2,0) s. Priorité : dernière position ennemie connue (< 6 s), puis son entendu, puis angle de carte (K) à moins de 25 m dans ±60° du cap, puis coin du chemin, puis point du chemin 4 m devant.
  - En tenue d'angle (perchoir, surveillance), il reste U(5 ; 10) s sur la même cible, avec un balayage de ±15°.
- **L2 — Pré-visée des coins.** Si le chemin tourne de plus de 30° à moins de 4 m, le bot regarde le côté opposé du coin, à hauteur de tête (1,5 m), 0,3 à 0,6 s avant d'y arriver.
- **L3 — Tangage.**
  - Le bot vise le point regardé à 1,5 m de hauteur : il lève les yeux vers les toits, le derrick, la grue.
  - Sur sol plat, il reste à ±5° de l'horizon.
  - Après un combat, il y revient progressivement ; jamais de tangage figé.
- **L4 — Dynamique du regard.** Ressort quasi critique (ζ 0,85-1,0), accélération ≤ 3000°/s², vitesse ≤ 360°/s hors combat. Jamais plus de 45° en moins de 60 ms.
- **L5 — But atteint** (navigation terminée) : le bot balaie les angles K visibles depuis sa position. Cette règle remplace BOTFIX-01.
- **L6 — Écart regard / déplacement.** Si le regard s'écarte de plus de 70° du cap de déplacement, le bot passe en marche (`walk_held`). Pas de sprint à reculons.

### 3.2 Visée et tir (A)

- **A1 — Accélération plafonnée.** L'accélération angulaire du ressort de combat est plafonnée à 2000 / 3000 / 4500°/s². Les pics de 300 / 500 / 800°/s restent valables sur 90°, mais un 180° ne dépasse plus 1000°/s.
- **A2 — Offset qui dérive.** Un nouvel objectif d'offset est tiré toutes les U(0,6 ; 1,0) / U(0,3 ; 0,6) / U(0,15 ; 0,35) s. L'offset courant le rejoint par un filtre du 1er ordre de τ = 0,16 s (comme CS) : plus aucun saut.
- **A3 — Forme de l'erreur.**
  - Gaussienne 2D anisotrope : σ dans l'axe du dernier flick = 2,2 × σ perpendiculaire.
  - Même amplitude quadratique moyenne qu'aujourd'hui (5 / 2,5 / 1°).
  - Décroissance en suivi : τ = 1,5 / 0,8 / 0,45 s.
- **A4 — Flick.** Le ratio d'amplitude est tiré à chaque flick selon N(0,97 ; 0,05), borné à [0,85 ; 1,08]. Le ressort corrige ensuite. Plus de dépassement fixe.
- **A5 — Retard de perception en suivi.** La visée poursuit la position de la cible d'il y a 250 / 200 / 150 ms (file, comme CS), plus 60 ms en ligne (BOT-03). Quand la cible change de direction, l'erreur remonte puis se résorbe.
- **A6 — Réaction.**
  - Loi ex-gaussienne de paramètres μ/σ/τ : 400/40/110, 280/35/70 et 200/25/45 ms, soit des médianes d'environ 475 / 330 / 230 ms.
  - +120 ms si la cible est à plus de 35° du centre.
  - Délai d'ouverture du feu : +250 / +80 / 0 ms.
  - Plancher à 150 ms.
- **A7 — Rythme de tir.**
  - Semi-auto : un appui = un front montant. Intervalle entre appuis : max(cadence de l'arme, U(0,15 ; 0,40) s) à moins de 20 m, U(0,30 ; 0,70) s au-delà.
  - Automatiques au-delà de 25 m : rafales de 3 à 5 balles, puis pause de U(0,2 ; 0,5) s.
- **A8 — ADS avec hystérésis.** Activé à la fin de la réaction si la cible est à plus de 6 m (Vétéran et Élite). Maintenu jusqu'à U(0,5 ; 0,9) s après la dernière vue. Au plus 1 bascule par 1,5 s.
- **A9 — Précision qui se dégrade.**
  - Si la vue propre du bot tourne à plus de 100°/s, l'erreur remonte à au moins 50 % de sa valeur initiale (comme CS).
  - Si le bot se déplace à plus de 50 % du sprint, l'erreur est multipliée par 1,3 (comme UT^2).
- **A10 — Recul.** Le ressort compense 60 / 80 / 90 % du recul accumulé. Réglage maison, à valider au banc.

### 3.3 Mouvement (M)

- **M1 — Plus aucun geste tiré au hasard** (saut, accroupi, glissade).
  - Saut : uniquement sur obstacle bas détecté, pour se débloquer, ou en esquive C2.
  - Glissade : uniquement en sprint au-delà de 6,5 m/s, vers un but à plus de 8 m sur une ligne droite, au plus 1 toutes les 6 s.
  - Accroupi : uniquement derrière une couverture basse (C5) ou pour un tir de précision au-delà de 19 m.
  - Jamais d'appui accroupi à moins de 1 m/s hors combat.
- **M2 — Suivi de chemin lissé.**
  - Le bot vise un point du chemin 2,5 m devant lui.
  - Les coins sont arrondis, avec un rayon d'au moins 1 m.
  - Il reste à au moins 0,7 m des murs quand le passage fait au moins 2,2 m de large.
  - Il ralentit à l'allure de marche dans les virages de plus de 60°.
- **M3 — Allure.**
  - Sprint en transit, loin des menaces.
  - Marche à moins de 12 m d'un angle K que l'équipe n'a pas vérifié depuis 10 s, en enquête, et à l'approche d'une dernière position connue.
  - Pauses de 0,3 à 1,2 s sur un point de vue, une toutes les 10 à 20 s de trajet.
- **M4 — En combat, le but de navigation n'est jamais la cible.**
  - Dans la bande de distance de l'arme : ancre = position au début de l'engagement, ±2 m.
  - Trop près : point à 4-6 m dans la direction opposée, projeté sur la navmesh.
  - Trop loin : dernière position connue de la cible.
- **M5 — Déblocage.**
  - Recul de 0,3 s, puis pas de côté de 0,4 s vers le côté le plus dégagé (mesuré par 2 rayons).
  - Saut seulement si un rayon à hauteur de genou touche et qu'un rayon à hauteur de poitrine est libre.
  - Plus d'oscillation à 5 Hz.
- **M6 — Escaliers et rampes.** Ceux de Wasteland (ResStair, ShedStairS, CraneStair, OfficeStair, RiseStair, DuneUp/Slide, DerrickRamp) sont franchis sans déclencher le déblocage, dans au moins 95 % de 20 essais chacun.

### 3.4 Combat (C)

- **C1 — Choix de cible.**
  - Engagement d'au moins 0,6 s sur une cible avant d'en changer ; hystérésis de +0,15 (comme Halo).
  - Score : menace (m'a touché il y a moins de 1,5 s) 0,4 + coût de rotation 0,3 + PV bas 0,2 + distance 0,1.
- **C2 — Esquive à 3 états** : ARRÊT, GAUCHE, DROITE.
  - Un 4e état, SAUT, est réservé à l'Élite sous le feu à moins de 15 m, au plus 1 fois toutes les 4 s.
  - Durée d'un état : U(0,3 ; 1,0) s, ou U(0,2 ; 0,5) s sous le feu. Jamais 3 segments de suite du même côté.
  - Déplacement latéral à l'allure ADS ou marche, au plus 3,5 m par segment.
  - Probabilité d'esquiver : 40 / 70 / 90 % (CS : 80 % × skill).
- **C3 — Réaction aux dégâts.** Le bot tourne vers la direction approximative de l'attaquant (±20°) en moins de réaction + 100 ms. Sans ligne de vue au bout de 0,5 s, il casse la ligne de vue.
- **C4 — Perte de la ligne de vue.** Il tient l'angle sur la dernière position connue pendant U(2 ; 4) s (comme CS), puis enquête en marchant. Jamais de sprint en ligne droite vers le point exact.
- **C5 — Peek** (avec BOT-06).
  - Depuis une couverture K ou BotSpots : exposé 0,6 à 1,5 s, retiré 0,8 à 2 s.
  - Il change de côté ou de hauteur après 2 peeks.
  - Le viseur est déjà sur l'angle au moment de sortir, à moins de 25 / 15 / 10° près (Leetify : 10°, c'est peu).
- **C6 — Repli** (la « confidence » de Halo).
  - Si ses PV passent sous 35 % alors que la cible a encore plus de 50 %, il rejoint un spot hors de vue des ennemis connus et plus proche des alliés.
  - Il revient au combat au-dessus de 80 % de PV (la régénération démarre après 4 s).
  - Probabilité de repli : 20 / 60 / 90 %.
- **C7 — Rechargement.** Chargeur sous 30 % et aucun ennemi vu depuis 1 s, de préférence à couvert. Jamais sous la ligne de vue d'un ennemi, sauf chargeur vide.

### 3.5 Perception (P)

- **P1 — Ouïe au niveau d'un humain.**
  - Portées : tirs 60 m, pas de course 25 m, pas de marche 10 m (nos pas de marche sont audibles), atterrissage 20 m.
  - Localisation bruitée : σ = 0,15 × distance.
  - Le bot entend aussi quand un ennemi est déjà visible (menace supplémentaire).
- **P2 — Remarquer un ennemi.** Test toutes les 0,25 s (comme CS). Parties visibles pondérées (torse 40 %, tête 10 %, côtés 20 %, pieds 10 %). Remarqué si au moins 20 % est visible, ou s'il tire.
- **P3 — Info d'équipe.** Chaque coéquipier la reçoit après U(0,5 ; 1,0) s (0,5 s en Élite). La Recrue ne partage pas (chez Halo, le partage dépend de la difficulté).

### 3.6 Équipe (T)

- **T1 — Répartition TDM 4v4.** Deux bots au Centre, en binôme espacé de 6 à 12 m. Un au Nord, un au Sud. En Élite, un rôdeur. Buts distincts : au moins 8 m entre coéquipiers.
- **T2 — Une info d'équipe ne mobilise pas tout le monde.** Seuls réagissent les bots dont le couloir ou la zone est à moins de 25 m du point, ou les bots inactifs. Point d'arrivée décalé de ±3 m vers une couverture.
- **T3 — Désynchronisation.**
  - Les minuteries de décision sont déphasées par bot (recalcul de chemin : décalage U(0 ; 0,5) s).
  - Un kill n'invalide que les buts des bots à moins de 30 m ou du couloir concerné, chacun après U(0,3 ; 1,2) s.
  - Jamais 3 bots d'une même équipe ou plus ne changent de but dans la même fenêtre de 200 ms.
- **T4 — Trade** (BOT-08). Si un allié à moins de 20 m est engagé, prendre une ligne de vue sur sa cible en moins de 1,5 s. Probabilité 0 / 50 / 80 %.
- **T5 — Hardpoint.**
  - 2 bots dans la zone, sur des positions distinctes (au moins 3 m d'écart).
  - 1 ou 2 bots en surveillance, entre 8 et 20 m, qui couvrent les entrées.
  - 1 bot part vers la zone suivante 15 s avant la rotation (l'aperçu HUD existe déjà).
- **T6 — Lisibilité** (comme F.E.A.R.). Un bot qui repère un ennemi pose un ping d'équipe (système UX-10), avec le même délai que P3.

### 3.7 Connaissance de Wasteland (K) — brouillon à valider

Toutes les coordonnées sont tirées de `scripts/levels/maps/layouts/wasteland.gd`. Elles restent à projeter sur la navmesh et à vérifier en capture (map_shots) dans BOT-22.

- x va d'ouest en est : l'équipe 0 (FUEL, bleu) est à l'ouest, vers x ≈ −37 ; l'équipe 1 (GAS, rouge) à l'est, vers x ≈ +37.
- z va du nord (valeurs négatives) au sud (valeurs positives).
- Les angles se visent à 1,5 m au-dessus du point.

**Couloirs** (trajet de l'ouest vers l'est, inversé pour l'équipe 1) :

| Couloir | Points dans l'ordre |
|---|---|
| Nord | bas de DuneUp (−25,0,−12) → sommet de la dune (−17,3.2,−12) → crête de DuneSlide (−14,3.2,−12.25) → épave de bus (1,0,−17) → bas de DerrickRamp (15,0,−7) → plateau du Derrick (19,4.5,−19) |
| Centre | épave citerne (−24,0,1) → porte S du garage (−17.5,0,−4.5) → pied de l'escalier du réservoir (−11.5,0,0) → chapelle, portes N et S (−7.5,0,−3 / 3) → caisses de rue (8,0,−2) → porte O du WestBlock (17,0,−2) → cour GAS (24,0,2) |
| Sud | Shack (−30,0,2.5) → pompes (−17.5,0,4.5) → berline (−1,0,4.5) → pick-up (4,0,9.5) → entrepôt (13,0,7) → caisses du quai (16,0,13) → porte N du SouthBlock (24,0,7.5) |

Buts TDM par couloir, du plus sûr au plus avancé :

| Équipe | Nord | Centre | Sud |
|---|---|---|---|
| 0 | dune → crête → bus | épave citerne → escalier du réservoir → caisses de rue | pompes → berline → pick-up |
| 1 | Derrick → bas de la rampe → bus | TankMid (27,0,1) → porte O du WestBlock → caisses de rue | caisses de la cour (22.5,0,5) → entrepôt → pick-up |

**Angles à pré-viser** (22 points) :
- Passerelle FuelPlank, bout est (−21,3.2,−7.5).
- FuelHouse, porte E de l'étage (−27,3.2,−7.5).
- Garage, porte S (−17.5,0,−4.5) et porte O (−21,0,−7.5).
- Réservoir : haut de l'escalier (−11.5,3.2,−5), porte S (−10.5,0,−5).
- Chapelle, porte N (−7.5,0,−3) et porte S (−7.5,0,3).
- Hangar-grue : haut de ShedStairS (0.75,3.2,−5.5), porte S (3.5,0,−5.5), porte E (7,0,−9.5).
- Plateforme de grue CraneDeck (1.5,5.6,−11.5).
- Derrick : haut de la rampe (15,4.5,−17), haut de RiseStair (25,4.5,−19).
- GasOffice : porte S (26.5,0,−4.5), porte O (23,0,−7), haut d'OfficeStair (24.5,3.2,−4.5).
- WestBlock, portes O (17,0,−2) et E (20.5,0,−2).
- Entrepôt, portes O (9,0,7), E (17,0,7) et N (13,0,3).
- SouthBlock, porte N (24,0,7.5).

**Perchoirs** (tenue de U(5 ; 10) s, voir L1) :

| Perchoir | Position | Ce qu'il surveille |
|---|---|---|
| CraneDeck | (1.5,5.6,−11.5) | rue et centre |
| Derrick | (19,4.5,−21) | couloir Nord |
| Toit du FuelHouse | (−30,6.4,−7.5) | cour FUEL |
| Toit du GasOffice | (26.5,3.2,−7) | cour GAS |
| Haut de ResStair | (−11.5,3.2,−5) | centre-ouest |

**Couvertures** (hauteur ; en dessous de 1,5 m, on s'accroupit derrière) :

| Couverture | Position | Hauteur |
|---|---|---|
| Pompes | (−19 et −16, 0, 5.25) | 1,6 m |
| Épave citerne | (−24,0,−1) | 3 m |
| Berline | (−1,0,4.5) | 1,4 m (accroupi) |
| Pick-up | (4,0,9.5) | 1,8 m |
| Voiture bleue | (2.5,0,13) | 1,6 m |
| Caisses de rue | (8,0,−2) | 1,8 m |
| Caisses du quai | (16,0,13) | 1,8 m |
| Fûts de la cour | (24,0,2) | 1,2 m (accroupi) |
| Caisses de la cour | (22.5,0,5) | 1,8 m |
| TankMid | (27,0,1) | 3,5 m |

**Hardpoint** :

| Zone | Centre | Dans la zone (2) | Surveillance | Entrées à tenir |
|---|---|---|---|---|
| HP1 rue/voitures | (0,1.5,7) | derrière la berline (−1.5,0,7.5) ; flanc O du pick-up (2.5,0,9) | porte S de la chapelle (−7.5,0,3.5) ; porte O de l'entrepôt (9,0,7) ; haut de ShedStairS (0.75,3.2,−5.5) | rue ouest, rue est, sud (voiture bleue) |
| HP2 réservoir | (−13,1.5,−1) | à l'ouest de l'escalier (−13,0,−2) ; mur O de la chapelle (−10.5,0,0.5) | porte S du garage (−17.5,0,−4) ; pompe est (−16,0,4.5) ; haut de ResStair (−11.5,3.2,−5) | chapelle N et S, garage, auvent |
| HP3 toit du hangar | (1,4.7,−9.5) | sous la plateforme de grue (0.8,3.2,−12.5) ; flanc S du toit (2.5,3.2,−7) | CraneDeck (1.5,5.6,−11.5) ; pied de ShedStairS (0.75,0,0) | ShedStairS (seul accès depuis la rue), CraneStair |
| HP4 entrepôt | (13,1.5,7) | coin NO intérieur (10,0,4) ; coin SE intérieur (16,0,10) | porte O du WestBlock (17,0,−2) ; caisses du quai (16,0,13) ; caisses de la cour (22.5,0,5) | portes O, E et N |

### 3.8 Paliers de difficulté

Aucun palier n'a de wall-hack ni de difficulté adaptative cachée. Cette table alimente BOT-11.

| Axe | Recrue | Vétéran | Élite | Référence |
|---|---|---|---|---|
| Réaction, loi ex-gaussienne μ/σ/τ (ms) → médiane | 400/40/110 → ~475 | 280/35/70 → ~330 | 200/25/45 → ~230 | CS 0,5 / 0,3 / 0,2 s ; Halo 200-250 ms |
| Délai d'ouverture du feu | +250 ms | +80 ms | 0 | CS AttackDelay (Easy 0,8 s) |
| Retard de perception en suivi | 250 ms | 200 ms | 150 ms | file de réaction CS |
| Erreur initiale / τ de décroissance | 5° / 1,5 s | 2,5° / 0,8 s | 1° / 0,45 s | CS 6 / 2,2 / 1,2° ; 2,0 / 0,58 / 0,43 s |
| Intervalle de l'offset | 0,6-1,0 s | 0,3-0,6 s | 0,15-0,35 s | CS 0,6 / 0,3 / 0,08 s |
| Pic de rotation / accélération max | 300°/s / 2000°/s² | 500 / 3000 | 800 / 4500 | CS 3000°/s² |
| ADS | jamais (tir à la hanche) | oui | oui | existant |
| Esquive / accroupi au-delà de 19 m | 40 % / 10 % | 70 % / 35 % | 90 % / 50 % | CS 80 %×skill, 50 % |
| Pré-visée des angles K | 30 % | 70 % | 95 % | CS : vérification des points selon le skill |
| Info d'équipe partagée | non | oui, délai 1,0 s | oui, délai 0,5 s | Halo : selon la difficulté |
| Trade / repli à PV bas | 0 % / 20 % | 50 % / 60 % | 80 % / 90 % | Booth, Halo |
| Compensation du recul | 60 % | 80 % | 90 % | réglage maison |

## 4. Métriques d'acceptation (banc `tools/bot_bench.gd`)

- Mesures sur Wasteland : phases `tdm_veteran` et `hp_veteran`, 180 s simulées ; seuils donnés pour le Vétéran.
- Un « engagement » va de l'acquisition d'une cible à sa perte.
- Hors combat : `_target_id == -1`.

| # | Métrique | Définition | Seuil (Vétéran) |
|---|---|---|---|
| B1 | Vitesse de lacet hors combat | p99 de \|Δlacet\|/Δt | ≤ 360°/s ; 0 rotation > 45° en moins de 60 ms |
| B2 | Accélération angulaire | p99, en excluant recul et étourdissement | ≤ 5000°/s² (Élite ≤ 7000) |
| B3 | Écart regard / déplacement | part du temps hors combat où \|lacet − cap de déplacement\| > 25° ; écart-type du tangage | entre 20 et 60 % ; tangage ≥ 3° |
| B4 | Temps avant le 1er tir (TTFS) | de l'acquisition au premier tir | médiane R 0,8-1,3 s, V 0,5-0,8 s, É 0,35-0,55 s ; coefficient de variation ≥ 0,2 ; p5 ≥ 0,18 s |
| B5 | Tir en mouvement | part des tirs à plus de 1 m/s | automatiques 40-80 % ; précision ≤ 15 % ; tirs à plus de 6,5 m/s ≤ 5 % |
| B6 | Segments d'esquive | durée des segments, écart latéral par segment, part de l'état ARRÊT | médiane 0,3-0,8 s ; aucun > 1,5 s ; ≤ 3,5 m ; ARRÊT 15-35 % |
| B7 | ADS | bascules par engagement | ≤ 2 ; ≤ 1 par 1,5 s |
| B8 | Cadence semi-auto | coefficient de variation de l'intervalle entre appuis ; part des tirs à cadence max (±10 ms) | ≥ 0,15 ; ≤ 30 % |
| B9 | Sauts du viseur | saut du point visé > 1,5° en un tick, hors flick d'acquisition et recul | 0 |
| B10 | « Snap puis tir » | fenêtre VACnet −0,5 / +0,25 s : part des tirs dont au moins 80 % de la rotation des 500 ms précédentes a lieu dans les 50 dernières ms | ≤ 5 % |
| B11 | Espacement | distance au coéquipier vivant le plus proche, hors spawn | médiane 6-15 m ; < 3 m ≤ 10 % du temps ; à plus de 30 m de tous ≤ 25 % |
| B12 | Synchronisation | nombre de bots d'une équipe qui changent de but dans une fenêtre de 200 ms (tout changement > 0,5 m compte) | jamais ≥ 3 ; 1 à 6 changements par minute et par bot |
| B13 | Présence au spawn | part du temps de vie passée à moins de 10 m de son spawn, au-delà des 10 premières secondes | ≤ 5 % |
| B14 | Gestes suspects | sauts hors combat sans obstacle ; appuis accroupi sous 1 m/s hors combat ; glissades sans but | 0 / 0 / 0 |
| B15 | Blocage | temps bloqué ; épisodes de blocage ; contacts latéraux avec un mur | ≤ 1 % ; ≤ 1 par bot et par 5 min ; ≤ 3 % des ticks |
| B16 | Réflexe aux dégâts | part des coups reçus hors champ suivis d'une rotation vers l'attaquant (±30°) en moins de réaction + 300 ms | ≥ 80 % |
| B17 | Trades | part des morts alliées suivies de dégâts d'un autre allié sur le tueur en moins de 3 s | ≥ 30 % (Élite ≥ 50 %) |
| B18 | Hardpoint | quand l'équipe tient la zone : bots dedans et espacement médian ; bots en surveillance entre 8 et 20 m ; délai d'arrivée à la nouvelle zone | 1-3 bots, ≥ 2,5 m ; ≥ 1 ; ≥ 1 bot en moins de 10 s |
| B19 | Occupation de la carte | zones nommées (§3.7) visitées par équipe en 5 min ; zones où ont lieu les kills ; grille de présence 2 m au format `tools/heatmap.gd`, comparée à un playtest humain (comme MLMove) | ≥ 70 % ; ≥ 5 zones ; comparaison suivie, sans seuil |
| B20 | Précision de l'ouïe | distance entre le point d'enquête et la source réelle | médiane 2-6 m, jamais 0 |
| B21 | Test perceptif (hors CI) | 12 clips de 20 s en vue spectateur (6 humains, 6 bots), jugés par au moins 5 personnes | bots correctement identifiés ≤ 65 % (réf. : juges à 0,83 face à des agents non humains, CHI 2023) |

## 5. Tâches priorisées (focalisées sur Wasteland, TDM + Hardpoint)

`BotBrain.gd` est un fichier chaud. Les tâches qui le modifient passent en série : BOT-21, puis BOT-25 → BOT-26 → BOT-27 → BOT-28 → BOT-29. En parallèle, on peut lancer d'abord BOT-20, BOT-21 et BOT-22, puis BOT-23 et BOT-24.

Effets sur les tâches existantes :
- **BOTFIX-01** est absorbé par BOT-25.
- **BOT-03** se réduit à la mémoire, à la ligne de vue sur plusieurs points et à la latence réseau ; ouïe, dégâts et partage d'équipe passent dans BOT-29.
- **BOT-04** : ses constantes de strafe sont remplacées par BOT-27.
- **BOT-11** reprend la table §3.8.
- **BOT-06** démarre sur Wasteland, avec les données de BOT-22.
- **BOT-08** porte T4 (trade) et la carte de danger.

```yaml
- id: BOT-20
  title: "Banc « humanité » : métriques B1-B20, phase Hardpoint, Wasteland, traces de présence"
  files: [tools/bot_bench.gd, tests/ai/test_bot_bench_thresholds.gd, docs/TESTING.md]
  depends_on: [BOT-13]
  size: M
  acceptance: >-
    Nouvelle phase hp_veteran. `--map=wasteland` documenté et utilisé par défaut dans la revue bots.
    Échantillonnage par tick de chaque bot : lacet/tangage, vitesse, entrées (jump/crouch/aim/fire),
    état du cerveau. Export JSON de B1-B15, B17, B18, B20.
    Un changement de but compte dès 0,5 m, et la navette A→B→A en moins de 10 s est comptée à part,
    ce qui corrige l'angle mort à 5 m. Grille de présence 2 m au format heatmap.gd, rendue par
    tools/heatmap_render.py et jointe au rapport (vérification en image).
    Fonctions pures testées : p99, coefficient de variation, découpage en segments, détection de
    « snap puis tir », fenêtre de synchronisation.
    Seuils en mode « observé » (avertissement) jusqu'à la fin de BOT-29, puis bloquants.
    La mesure de départ (Wasteland, tdm_veteran + hp_veteran, 180 s) est archivée dans le rapport.

- id: BOT-21
  title: "Supprimer les gestes suspects immédiats (sauts/accroupis au hasard, métronome, ADS qui clignote, tangage figé, phases)"
  files: [scripts/ai/BotBrain.gd, scripts/ai/BotCombatStyle.gd, tests/ai/test_bot_combat_style.gd]
  depends_on: []
  size: S
  acceptance: >-
    Suppression du tirage saut/accroupi hors combat (BotBrain.gd:518-531) : le saut ne vient plus que
    de BotStuck (M1). Aucun crouch_pressed sous 1 m/s.
    Semi-auto : fire_pressed seulement sur le front montant, intervalle donné par
    STYLE.semi_auto_interval(distance, rng) : U(0,15;0,40) s sous 20 m, U(0,30;0,70) s au-delà,
    jamais plus vite que la cadence de l'arme (A7).
    ADS avec hystérésis via STYLE.ads_hold(...) : au plus 1 bascule par 1,5 s, maintien
    U(0,5;0,9) s après la dernière vue (A8).
    Hors combat, le tangage revient dans ±5° de l'horizon à 90°/s au plus.
    Minuterie de recalcul de chemin déphasée U(0;0,5) s par bot.
    Tests purs pour chaque fonction de style. Sur le banc Wasteland : B7, B8 et B14 respectés.

- id: BOT-22
  title: "Connaissance de carte Wasteland (couloirs, angles, perchoirs, couvertures, positions HP) + rebake BotSpots au sol"
  files: [scripts/levels/maps/layouts/wasteland.gd, scripts/ai/BotMapKnowledge.gd, tests/ai/test_bot_map_knowledge.gd, scripts/ai/BotSpots.gd, resources/bot_spots/wasteland.tres]
  depends_on: []
  size: M
  acceptance: >-
    Nouvelle clé "bot_knowledge" dans WastelandLayout.data(), en partant du brouillon §3.7 :
    au moins 14 zones nommées (AABB), couloirs N/C/S ordonnés par équipe, au moins 20 angles
    (position + direction), au moins 4 perchoirs, au moins 10 couvertures (direction de protection,
    hauteur), hp_holds pour les 4 zones (au moins 2 positions dans la zone et 2 en surveillance chacune).
    Test headless sur la scène : chaque point est à moins de 0,5 m de la navmesh et atteignable
    depuis les deux spawns.
    BotMapKnowledge pur : area_of(pos), lane_goals(team, lane), angles_near(pos, fwd, 25 m, ±60°),
    hp_holds(index, role).
    BotSpots._sample_navmesh échantillonne plusieurs niveaux (pile de rayons verticaux). wasteland.tres
    rebaké : au moins 250 spots, au moins 60 % au sol (y < 1 m), moins de 50 % en « sniping ».
    Capture vue de dessus avec les points superposés, vérifiée à l'œil.

- id: BOT-23
  title: "Objectifs TDM par couloir, sans convergence ni synchronisation (fin du piétinement au spawn)"
  files: [scripts/modes/GameMode.gd, scripts/modes/TDMMode.gd, tests/ai/test_bot_goals.gd]
  depends_on: [BOT-22]
  size: M
  acceptance: >-
    Si la carte fournit bot_knowledge, la patrouille ne lit plus les marqueurs de spawn.
    Affectation par couloir (T1) : 2 au Centre, 1 au Nord, 1 au Sud. But = point suivant du couloir,
    tenue de 4 à 10 s, puis point suivant.
    Dernière position partagée (T2) : elle ne mobilise que les bots à moins de 25 m ou inactifs, avec un
    délai U(0,5;1,0) s par bot et un point décalé de ±3 m vers une couverture.
    Invalidation ciblée (T3) : un kill n'invalide que les bots à moins de 30 m ou du couloir concerné,
    chacun après U(0,3;1,2) s.
    Tests : 60 s simulées. B12 (jamais 3 changements ou plus en 200 ms), B13 (≤ 5 %), buts des
    coéquipiers écartés d'au moins 8 m dans 90 % des échantillons. Le test « aucune lecture de
    position ennemie hors perception » est conservé.

- id: BOT-24
  title: "Hardpoint : rôles zone / surveillance / pré-rotation sur les positions de Wasteland"
  files: [scripts/modes/HardpointMode.gd, tests/ai/test_bot_goals_hardpoint.gd]
  depends_on: [BOT-22, BOT-23]
  size: S
  acceptance: >-
    _compute_bot_goal lit hp_holds (T5) : 2 positions distinctes dans la zone (au moins 3 m d'écart),
    1 ou 2 en surveillance, 1 bot en pré-rotation pendant les 15 s de l'aperçu.
    Rôle stable au moins 10 s ; jamais 2 bots sur la même position.
    B18 respecté sur hp_veteran (Wasteland, 180 s).

- id: BOT-25
  title: "Regard humain hors combat (BotLook : attention dirigée, pré-visée des coins, tangage, ressort plafonné) — absorbe BOTFIX-01"
  files: [scripts/ai/BotLook.gd, tests/ai/test_bot_look.gd, scripts/ai/BotBrain.gd]
  depends_on: [BOT-21, BOT-22]
  size: M
  acceptance: >-
    BotLook pur, règles L1-L6 : choix de la cible de regard toutes les U(1;2) s (U(5;10) s en tenue
    d'angle), pré-visée des coins de plus de 30° à moins de 4 m, tangage vers le point à 1,5 m,
    ressort ζ 0,85-1,0 avec accélération ≤ 3000°/s², vitesse ≤ 360°/s, balayage des angles une fois
    le but atteint, marche au-delà de 70° d'écart regard/cap.
    _face_direction est remplacé.
    Tests purs (scénarios de coin, de perchoir, de but atteint). B1, B2 et B3 respectés sur Wasteland.

- id: BOT-26
  title: "Visée v2 : offset qui dérive, erreur anisotrope, flick aléatoire, retard de perception, réaction ex-gaussienne"
  files: [scripts/ai/BotAim.gd, scripts/ai/BotReaction.gd, tests/ai/test_bot_aim.gd, tests/ai/test_bot_reaction.gd, scripts/ai/BotBrain.gd]
  depends_on: [BOT-25]
  size: M
  acceptance: >-
    Règles A1-A6 et A9 avec les valeurs §3.8 : intervalle d'offset par difficulté, filtre τ 0,16 s,
    erreur gaussienne 2D avec σ dans l'axe = 2,2 × σ perpendiculaire, ratio de flick N(0,97;0,05)
    borné [0,85;1,08], accélération plafonnée 2000/3000/4500°/s², file de perception 250/200/150 ms,
    réaction ex-gaussienne avec plancher 150 ms, erreur remontée si la vue tourne à plus de 100°/s.
    Les bandes Monte-Carlo existantes restent monotones Recrue < Vétéran < Élite.
    Nouveaux tests : médiane et coefficient de variation de la réaction, absence de saut de l'offset.
    Sur le banc : B4, B9 et B10 respectés. Les valeurs sont écrites dans BotAim/BotReaction ;
    BOT-11 les déplacera dans resources/bots/*.tres.

- id: BOT-27
  title: "Mouvement de combat : esquive 3 états à l'allure de marche, gestion de distance corrigée, tenue d'angle après perte de LOS"
  files: [scripts/ai/BotCombatStyle.gd, tests/ai/test_bot_combat_style.gd, scripts/ai/BotBrain.gd]
  depends_on: [BOT-26]
  size: M
  acceptance: >-
    Machine d'esquive C2 : ARRÊT / GAUCHE / DROITE, plus SAUT en Élite sous le feu à moins de 15 m,
    au plus 1 toutes les 4 s. Durées U(0,3;1,0) s ou U(0,2;0,5) s, jamais 3 segments de suite du
    même côté. Latéral en walk_held ou ADS.
    M4 : le but de navigation n'est plus _target_pos ; ancre ±2 m, recul à 4-6 m projeté sur la
    navmesh, avance vers la dernière position connue.
    C4 : tenue d'angle U(2;4) s, puis enquête en marchant.
    Accroupi seulement selon M1/C5.
    Tests purs de la machine d'états et de la bande de distance. B5 et B6 respectés sur Wasteland.

- id: BOT-28
  title: "Suivi de chemin lissé et déblocage « humain » (fin de l'oscillation 5 Hz), escaliers/rampes de Wasteland"
  files: [scripts/ai/BotPathFollow.gd, scripts/ai/BotStuck.gd, tests/ai/test_bot_path_follow.gd, tests/ai/test_bot_stuck.gd, scripts/ai/BotBrain.gd]
  depends_on: [BOT-27]
  size: M
  acceptance: >-
    Règles M2, M5 et M6 : point visé 2,5 m devant, coins arrondis (rayon ≥ 1 m), au moins 0,7 m des
    murs quand le passage fait au moins 2,2 m, ralentissement dans les virages de plus de 60°.
    Déblocage : recul 0,3 s + pas de côté 0,4 s vers le côté dégagé, saut seulement si le rayon genou
    touche et le rayon poitrine est libre.
    Test headless : chaque escalier et rampe de Wasteland franchi dans au moins 95 % de 20 essais.
    B15 respecté (temps bloqué ≤ 1 %, contacts avec les murs ≤ 3 %).

- id: BOT-29
  title: "Perception humaine ciblée : réflexe aux dégâts, ouïe pas/tirs bruitée, délai d'équipe, test toutes les 0,25 s (réduit BOT-03)"
  files: [scripts/ai/BotPerception.gd, tests/ai/test_bot_perception.gd, scripts/ai/BotBrain.gd]
  depends_on: [BOT-28]
  size: M
  acceptance: >-
    C3 : sur Health.damaged, rotation vers la direction de l'attaquant (±20°) en moins de
    réaction + 100 ms ; sans ligne de vue au bout de 0,5 s, le bot casse la ligne de vue.
    P1 : tirs 60 m, pas de course 25 m, pas de marche 10 m, atterrissage 20 m. L'audibilité se calcule
    côté serveur à partir de la vitesse et de la distance, comme pour le bot CS. Localisation bruitée
    σ = 0,15·d, et l'ouïe reste active quand un ennemi est visible.
    P2 : test toutes les 0,25 s, parties visibles pondérées, +120 ms en périphérie (au-delà de 35°).
    P3 : délai d'équipe U(0,5;1,0) s par coéquipier, pas de partage en Recrue.
    Tests purs (audibilité, bruit, délais). B16 et B20 respectés.
    BOT-03 garde : mémoire (position + vitesse, décroissance sur 6 s), ligne de vue sur plusieurs
    points, latence réseau équivalente.
```

## 6. Sources

**Primaires : jeux, code et studios**
- [S2] ReGameDLL_CS, reconstruction open source du bot CS 1.6 / Condition Zero (Turtle Rock) : [cs_bot_vision.cpp](https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/bot/cs_bot_vision.cpp) (ressort, regard périphérique, file de réaction, « remarquer »).
- [S3] Même dépôt : [cs_bot_weapon.cpp](https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/bot/cs_bot_weapon.cpp) (SetAimOffset / UpdateAimOffset, cadences de tir).
- [S4] Même dépôt : [states/cs_bot_attack.cpp](https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/bot/states/cs_bot_attack.cpp) (esquive, accroupi, poursuite).
- [S5] botprofile.db de CS:GO, copie communautaire avec l'en-tête Turtle Rock : [Crazylamb/CSGO_ImprovedBots](https://github.com/Crazylamb/CSGO_ImprovedBots/blob/main/botprofile.db) ; valeurs de regard par défaut commentées dans [ce gist](https://gist.github.com/so0k/7505931) et [ce fil Steam](https://steamcommunity.com/app/730/discussions/0/2934616148055943634/). *À recouper avec les fichiers du jeu.*
- [S1] Booth, « The Making of the Official Counter-Strike Bot », GDC 2004 : [slides](https://media.gdcvault.com/gdc04/slides/making_of_official.pdf) (déjà analysé dans 02).
- [S6] Chin-Deyerle, « Thinking Like Players: How Halo Infinite's Multiplayer Bots Make Decisions », GDC 2022 : [slides](https://media.gdcvault.com/GDC+2022/Speaker+Slides/ThinkingLikePlayersHowHaloInfinitesBotsMakeDecision_ChinDeyerle_Brie.pdf), [Vault](https://gdcvault.com/play/1027689/Thinking-Like-Players-How-Halo).
- [S7] Stern, « Deconstructing the Combat Dance: Designing Multiplayer Bots for Halo Infinite », GDC 2022 : [programme](https://schedule.gdconf.com/session/deconstructing-the-combat-dance-designing-multiplayer-bots-for-halo-infinite/882306) (contenu derrière le Vault payant, non lu).
- [S8] Game Informer, interview de 343 : [How Halo Infinite's Bots Became So Ruthless](https://gameinformer.com/preview/2021/11/15/how-halo-infinites-bots-became-so-ruthless-and-helped-343-develop-multiplayer).
- [S9] 343 sur le faux teabag (bug de traversée) : [PC Gamer](https://www.pcgamer.com/halo-infinites-bots-arent-teabagging-you-at-least-not-on-purpose/), [Shacknews](https://www.shacknews.com/article/126119/halo-infinites-bots-arent-programmed-to-teabag-you-after-a-kill-says-343).
- [S10] Respawn, Apex Legends, mise à jour anti-triche et matchmaking de février 2025 : [ea.com](https://www.ea.com/nb/games/apex-legends/apex-legends/news/dev-update-0225).
- [S18] McDonald (Valve), « Robocalypse Now », GDC 2018 : [Vault](https://www.gdcvault.com/play/1024994/Robocalypse-Now-Using-Deep-Learning) ; synthèse [PC Gamer](https://www.pcgamer.com/vacnet-csgo/).
- [S21] Straatman, Verweij, Champandard, Killzone 3 : [Game AI Pro, ch. 29](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter29_Hierarchical_AI_for_Multiplayer_Bots_in_Killzone_3.pdf).
- [S22] Orkin, « Three States and a Plan: The AI of F.E.A.R. », GDC 2006 : [PDF](https://www.gamedevs.org/uploads/three-states-plan-ai-of-fear.pdf).
- [S23] Ubisoft, Terrohunt dans Rainbow Six Siege : [ubisoft.com](https://www.ubisoft.com/en-us/game/rainbow-six/siege/news-updates/2XcizywHyHKAGTfsg363rI/terrohunt-returns-in-rainbow-six-siege).
- [S24] Respawn, l'IA de Titanfall : [Xbox Wire](https://news.xbox.com/en-us/2014/02/18/games-titanfall-ai/).
- [S25] Bots d'Overwatch 2 en partie rapide : [Blizzard Watch](https://blizzardwatch.com/2025/01/29/overwatch2-ai-bots-quickplay/).

**Recherche**
- [S11] Durst et al., « Learning to Move Like Professional Counter-Strike Players » (MLMove), CGF 2024 : [arXiv 2408.13934](https://arxiv.org/abs/2408.13934).
- [S12] Zhuang et al., « Navigates Like Me: Understanding How People Evaluate Human-Like AI in Video Games », CHI 2023 : [arXiv 2303.02160](https://arxiv.org/abs/2303.02160).
- [S13] Schrum, Karpov, Miikkulainen, « UT^2: Human-like Behavior via Neuroevolution of Combat Behavior and Replay of Human Traces » : [PDF](https://nn.cs.utexas.edu/downloads/papers/schrum.cig11competition.pdf) ; BotPrize 2012 : [UT Austin](https://news.utexas.edu/2012/09/26/artificially-intelligent-game-bots-pass-the-turing-test-on-turings-centenary/).
- [S14] « Kinematic markers of skill in first-person shooter video games », PNAS Nexus 2023 : [article](https://academic.oup.com/pnasnexus/article/2/8/pgad249/7233873).
- [S15] « Submovement control processes in discrete aiming as a function of space-time constraints », PLOS One 2017 : [article](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0189328) ; Elliott et al. 2010, « Goal-directed aiming: two components but multiple processes » : [ResearchGate](https://www.researchgate.net/publication/46168942_Goal-Directed_Aiming_Two_Components_but_Multiple_Processes).
- [S16] Whelan 2008, « Effective Analysis of Reaction Time Data » : [ResearchGate](https://www.researchgate.net/publication/46061497_Effective_Analysis_of_Reaction_Time_Data) ; lois de temps de réaction : [Lindeløv](https://lindeloev.github.io/shiny-rt/).
- [S27] « Human-like Bots for Tactical Shooters Using Compute-Efficient Sensors », 2024 : [arXiv 2501.00078](https://arxiv.org/abs/2501.00078) (imitation, capteurs par rayons ; pas de chiffres exploitables).

**Secondaires : communauté et outils de stats (à prendre avec prudence)**
- [S17] Leetify : [glossaire](https://leetify.com/blog/leetify-stats-glossary/) (contre-strafe sous 34 %, placement du viseur), [Enemy (actually) spotted](https://leetify.com/blog/enemy-actually-spotted/) (temps avant dégâts de 400-500 ms = rapide).
- [S20] Sons : Riot sur les pas dans Valorant, via [The Loadout](https://www.theloadout.com/valorant/footsteps) ; portées communautaires pour [Valorant](https://www.ggamechamps.com/blogs/valorant-audio-settings-footsteps) et [CS2](https://csgo-guides.com/gameplay/sound).
- [S26] Fenêtre de trade : [scope.gg](https://blog.scope.gg/trade-kills-en/).
