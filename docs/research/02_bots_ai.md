# 02 — Bots : perception, visée, décision, tactique

> Recherche du 23/09/2026 (Godot 4.7, GDScript typé). Les bots sont simulés
> par le serveur via `player.input`. Contexte : playtest utilisateur, « les
> bots sont nuls ».

## 1. Résumé en 10 lignes

1. Nos bots ne sont pas « nuls » parce qu'ils manquent d'IA sophistiquée. Ils le sont à cause de **quatre défauts simples** qui brisent l'illusion, et Booth le dit : « blatantly mindless behavior breaks the illusion ».
2. **Objectifs instables.** En TDM, `bot_goal_for` renvoie un ennemi *au hasard* à chaque appel (re-path toutes les 0,5 s). En SnD, c'est un site au hasard. Résultat : les bots font des allers-retours, et en TDM ils connaissent la position des ennemis (wall-hack caché).
3. **Visée inversée.** L'erreur est retirée à chaque frame (tremblement) et exprimée en mètres fixes : environ 11° d'erreur à 3 m, environ 0,9° à 40 m. Les bots ratent au contact et sont des lasers de loin. Ils tirent aussi avant d'être alignés.
4. **Auto-sabotage.** Sauts, plongeons et accroupis aléatoires en plein combat, alors que le plongeon interdit le tir pendant environ 1,1 s.
5. **Aucune tactique.** Le bot fonce sur la cible, ignore les dégâts reçus hors champ, oublie l'ennemi dès que la ligne de vue est coupée, n'utilise ni couverture ni repli.
6. Les jeux de référence (CS bot de Booth, Killzone 2/3, Halo Infinite) partagent quatre briques : une **carte tactique pré-calculée** (cachettes, couverture par direction), une **perception limitée avec mémoire**, une **visée à ressort-amortisseur avec offset régénéré périodiquement**, et une **hiérarchie équipe → individu**.
7. Recommandation de décision : un sélecteur **utility** pur et testé (gdUnit4) pour l'individu, plus une **couche équipe** légère pour les modes à objectif. Les addons BT (LimboAI MIT v1.8.1 compatible 4.7.2, Beehave MIT v2.9.3 compatible 4.7) restent optionnels : aucun ne fournit la partie tactique qui nous manque.
8. **Équité réseau** : un bot serveur a 0 ms de latence, soit environ 70-140 ms d'avance sur un humain en ligne (peeker's advantage selon Valorant). Il faut lui ajouter une latence de perception équivalente.
9. **Éthique** : on garde les bots toujours signalés (roadmap). Pas de bots cachés ni de lobbies de bots punitifs, voir le contre-exemple Marvel Rivals.
10. Ordre recommandé : BOT-01 (objectifs), BOT-02 (visée), BOT-04 (discipline), BOT-03 (perception), BOT-09 (anti-blocage), puis tactique (BOT-05 à BOT-07), équipe (BOT-08) et le reste.

## 2. Findings (avec sources)

### 2.1 Ce que font les jeux livrés

**Counter-Strike bot** (Michael Booth, GDC 2004, [slides](https://media.gdcvault.com/gdc04/slides/making_of_official.pdf), [GDC Vault](https://www.gdcvault.com/play/1022878/The-Making-of-the-Official)) :

- **Navmesh annotée** : aires avec attributs (saut, accroupi, « danger », lieux de scénario). Génération automatique des **hiding spots** et **approach points** par apprentissage de la carte.
- **A\*** avec surcoût saut/accroupi/échelle et coût de **danger** : quand un coéquipier meurt, du danger s'ajoute aux aires proches et décroît lentement. Le poids dépend de la personnalité, donc les routes changent d'un round à l'autre.
- **Anti-blocage** : surveiller la vitesse moyenne sur une courte fenêtre. Si bloqué : « wiggle » aléatoire, puis saut aléatoire.
- **Attention dirigée** : la vue est **indépendante du mouvement**. Le bot regarde victime, cachettes, dernière position connue, points d'approche et bruits. Il réagit aux blessures, aux kills, aux impacts de balle et aux annonces.
- **Physique de la vue** : ressort-amortisseur `ω' += (k·α − d·ω)·ΔT`, avec une raideur augmentée en visée.
- **Visée** : un point P sur la victime, plus un **offset régénéré périodiquement** selon le skill, plus une **dérive de vue**, puis des forces angulaires vers ce point.
- **Maîtrise des armes** : rafales avec un fusil à distance, passer au pistolet plutôt que recharger, pistolet si sniper au contact, viser la tête sauf avec certains snipers et fusils à pompe.
- **Repli** : vers une cachette qu'aucun ennemi connu ne voit et plus proche des alliés que des ennemis (sinon, la moins exposée). **Moral** : augmente avec les kills et les objectifs, pousse à « rusher ou camper ».
- **Difficulté** : Easy combine réaction faible, visée terrible, « substantial additional delay before opening fire », mauvaise maîtrise des armes et mauvais choix d'armes. Expert a des réactions « very good (but still human) ».
- **Fun** : créer des « moments » (bots qui se font flasher, qui reculent, qui se faufilent), respecter le joueur (lui laisser l'objectif), et varier les personnalités. Booth : « The last 10% will take 90% of the time — Navigation is hell ».

**Killzone 2/3** (Straatman, Verweij, Champandard, [Game AI Pro ch. 29](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter29_Hierarchical_AI_for_Multiplayer_Bots_in_Killzone_3.pdf), [Guerrilla KZ2](https://www.guerrilla-games.com/read/killzone-2-multiplayer-bots)) :

- Trois couches : **stratégie** (commandant par équipe, qui assigne escouades et objectifs : Attack/Defend area, Escort, Regroup), **escouade** (traduit les objectifs en ordres), **individu** (autonome : choisit sa cible et sa position).
- Planificateur **HTN** à chaque niveau.
- **Graphe de waypoints avec couverture par direction calculée hors ligne.**
- **Position picking** : générer des waypoints candidats proches et les **scorer** (couverture contre les menaces connues, distance aux menaces et aux alliés, ligne de tir, distance de trajet). Les poids varient selon le comportement.
- **Prédiction des cachettes** d'une menace cachée, et **influence map** par faction pour choisir les points de regroupement et pondérer le pathfinding.

**Halo Infinite** (343, [Game Informer](https://gameinformer.com/preview/2021/11/15/how-halo-infinites-bots-became-so-ruthless-and-helped-343-develop-multiplayer), [GameSpot](https://www.gamespot.com/articles/heres-why-halo-infinites-bots-act-like-people/1100-6495427/)) :

- Les bots sont modélisés **en observant des playtests internes**. On isole d'abord le mouvement (marche, sprint, accroupi, mantle), puis la visée et le tir, puis la « confiance » en combat.
- Ils réagissent aux tirs en **sautant ou strafant comme les humains**, et contestent les armes puissantes.
- En difficulté max (Spartan), ils lisent le **même radar** que le joueur : ils ne trichent pas, ils utilisent l'info disponible.
- Objectif explicite : que le bot ne paraisse jamais « tricheur ».

**BotPrize 2012** (UT2004, [UT Austin](https://news.utexas.edu/2012/09/26/artificially-intelligent-game-bots-pass-the-turing-test-on-turings-centenary/), [MirrorBot](https://www.researchgate.net/publication/261452209_MirrorBot_Using_Human-inspired_Mirroring_Behavior_To_Pass_A_Turing_Test)) : les gagnants ont obtenu 52,2 % et 51,9 % d'« humanité », contre 41,4 % pour les humains. La clé : **faire des erreurs, tirer imparfaitement, hésiter puis attaquer**, et imiter le comportement observé.

### 2.2 Perception

- **Cône de vue et portée**, avec LOS vers **plusieurs points** du corps (sinon un bot ne voit pas un ennemi dont seule la jambe dépasse, ou voit « à travers » une tête).
- **Ouïe** : tirs, pas de course, impacts proches, avec position approximative.
- **Toucher** : dégâts reçus. Booth : réagir aux « Injuries ».
- **Mémoire** : dernière position et vitesse connues, qui décroissent. Le bot va « checker » la dernière position (Booth), et Killzone prédit les cachettes probables.
- **Info d'équipe** : messages « Enemy spotted » ou « Need backup » (Booth), messages entre agents (Killzone).
- **Temps de réaction humain** : réaction visuelle simple d'environ 190 ms en labo, **médiane d'environ 273 ms** en population générale. Les joueurs esport sont plus rapides (latence P300 plus précoce de 20-70 ms). Sources : [ResearchGate](https://www.researchgate.net/publication/351247177_Comparison_of_Reaction_Time_Between_eSports_Players_of_Different_Genres_and_Sportsmen), [PMC10393144](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10393144/). Une réaction à choix (ami ou ennemi, où viser) est plus lente qu'une réaction simple.
- **Latence réseau** : l'humain en ligne subit **71-141 ms** de retard structurel (peeker's advantage, [Riot](https://www.riotgames.com/en/news/peeking-valorants-netcode)). Un bot serveur n'en subit aucun. Sans compensation, un bot « Vétéran » à 300 ms équivaut à un humain qui réagirait en environ 200 ms.

### 2.3 Modèle de visée humain

- **Booth** : offset aléatoire **régénéré périodiquement** (pas à chaque frame), plus une dérive, plus un ressort-amortisseur sur la vitesse angulaire.
- **Travaux sur la visée humaine** : trois phases, **inertie** (reconnaissance), **mouvement rapide**, puis **freinage et correction** (micro-ajustements). L'erreur **augmente avec l'amplitude et la vitesse angulaire** (un flick est moins précis qu'un suivi lent). Ce qui trahit un aimbot : précision irréaliste, réactions trop courtes, absence de compromis vitesse/précision. Sources : [arXiv 2203.12050](https://arxiv.org/pdf/2203.12050), [brevet USPTO de détection de triche](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/11896910).
- **À traduire chez nous**, une erreur en **angle** (pas en mètres) qui :
  - naît grande à l'acquisition (flick avec léger dépassement de 5-15 %) ;
  - rétrécit pendant le suivi (déjà fait : τ = 0,8 s) ;
  - grossit avec la vitesse angulaire apparente de la cible et avec le propre mouvement du bot ;
  - n'est tirée à nouveau que toutes les 0,3-0,7 s.
- **Le bot ne tire que si l'erreur est inférieure à la demi-largeur angulaire de la hitbox** (plus la dispersion de l'arme), sauf un « spray and pray » volontaire en Recrue.

### 2.4 Décision : FSM, BT, utility, GOAP, HTN

- **FSM ou HSM** (CS bot : plusieurs FSM concurrentes). Simple, mais la complexité « grows geometrically » (Booth).
- **HTN** (Killzone 2/3). Puissant pour les plans multi-étapes (poser la bombe, soigner un allié), mais c'est un planificateur à écrire et outiller.
- **Utility AI** (Dave Mark, IAUS, [GDC 2013](https://www.gdcvault.com/play/1018040/Architecture-Tricks-Managing-Behaviors-in), [gameai.com/iaus](https://www.gameai.com/iaus.php)). Chaque action est scorée par un produit de *considérations* normalisées [0,1] passées dans des **courbes de réponse**. Data-driven, facile à tester en fonctions pures. Il faut de l'**hystérésis** pour éviter l'oscillation, le même mal que notre ciblage actuel.
- **Choix pour nous** :
  - **Utility pur** pour le « quoi faire » (Engager, Se replier, Traquer, Enquêter, Objectif, Patrouiller, Capacité). Chaque comportement est un petit état avec enter/update/exit.
  - **Position picking** scoré (Killzone) pour le « où ».
  - **Couche équipe** qui fixe les objectifs.
  
  Cela colle au style du repo (logique pure dans `BotReaction`/`BotTargetSelect`, testée par gdUnit4).

### 2.5 Tactique : couverture, peek, strafe, repli, objectif

- **Couverture et cachettes** : générées automatiquement hors ligne à partir de la navmesh (Booth, Killzone). Il faut une recherche **en largeur sur la navmesh**, pas en distance à vol d'oiseau, qui est « very misleading » (Booth). Ne jamais choisir une cachette déjà occupée.
- **Peek** : sortir de la couverture vers la ligne de tir, tirer, revenir. C'est le comportement humain standard en tactique.
- **Strafe** : Halo Infinite modélise le strafe et le saut *en réaction aux tirs reçus*, pas au hasard.
- **Repli** à PV bas vers une cachette hors de vue des ennemis connus et plus proche des alliés (Booth). Chez nous, la régénération démarre après 4 s sans dégâts (`Health.gd:21`) : le repli est donc une vraie option.
- **Objectif** (SnD) : l'attaque choisit **un** site par round (pondéré par le danger), désigne un porteur, nettoie le site puis pose pendant que les autres couvrent. La défense se répartit, puis tourne sur info (« The bomb has been planted », Booth). Par défaut, les bots **laissent l'objectif au joueur humain** (Booth : « defer key scenario objective to human Players »).

### 2.6 Coordination d'équipe

- **Commandant par équipe** (Killzone) qui émet des ordres (attaquer une zone, défendre une zone, regrouper). Les individus restent autonomes sur l'exécution.
- **Suivre un leader** (Booth) : re-path périodique, marcher s'il marche, se poster en couverture s'il se cache.
- **Espacement et échanges de kill** : ne pas grouper à moins de quelques mètres, suivre l'allié engagé pour « trader ».
- **Callouts** : exposer l'état interne (« je garde B »), l'ennemi repéré, le nombre restant. Ne jamais se répéter ni parler par-dessus les autres (Booth). Côté HUD, un ping de la position partagée suffit.

### 2.7 Difficulté, rubber-banding, bots de remplissage

- **Difficulté multi-axes** (Booth) : temps de réaction, visée, délai d'attaque, maîtrise des armes, choix d'armes, travail d'équipe. Plus des **personnalités** (agressivité, skill, teamwork, moral) pour varier les bots d'une même difficulté.
- **Pas de triche** : Halo Spartan utilise le radar du joueur, pas un wall-hack.
- **Rubber-banding et bots cachés** : Marvel Rivals a été accusé en 2025 de placer les joueurs en **lobbies de bots non signalés après 2 défaites**. Résultat : backlash, boycotts de streamers, démenti d'EOMM par NetEase. Sources : [PC Gamer](https://www.pcgamer.com/games/third-person-shooter/evidence-mounts-that-marvel-rivals-stealthily-places-losing-players-in-bot-matches-and-i-know-because-im-the-loser/), [Game Rant](https://gamerant.com/marvel-rivals-bot-lobby-controversy-explained-why/). Notre règle roadmap, « bots toujours signalés, casual seulement », est la bonne. Une difficulté adaptative n'est acceptable qu'en **entraînement** et **annoncée**.

### 2.8 Options Godot 4.7 (licence, maintenance)

| Option | Licence | État au 23/09/2026 | Pour nous |
|---|---|---|---|
| **NavigationServer3D / NavigationAgent3D** (moteur) | MIT | intégré. `bake_from_source_geometry_data` utilisé par `BotNavMesh.gd` | on garde. Activer `avoidance_enabled` et utiliser `navigation_layers` et `travel_cost` par région |
| **LimboAI** ([GitHub](https://github.com/limbonaut/limboai)) | MIT | v1.8.1 du 20/08/2026, builds **Godot 4.7.2-stable**. GDExtension (4.6+) ou module. BT + HSM + blackboard + **débogueur visuel**. 3k étoiles, actif | meilleur choix *si* on passe aux BT/HSM. Coût : binaire natif à embarquer dans l'image serveur Linux |
| **Beehave** ([GitHub](https://github.com/bitbrain/beehave)) | MIT | v2.9.3 du 18/08/2026, « compatible with latest Godot 4.7 ». 100 % GDScript, arbres en nœuds de scène, débogueur, testé unitairement | pas de natif, mais un arbre de nœuds par bot. Bug de duplication de scènes corrigé seulement en 2.9.3 (#309) |
| **Utility AI** ([Asset Library #1937](https://godotengine.org/asset-library/asset/1937)) | voir la fiche | considérations et courbes éditables dans l'inspecteur. Maintenance incertaine | inspirer le format, ne pas en dépendre |
| **Maison** (utility pur + états RefCounted) | — | ~200-300 lignes, testables gdUnit4 | **recommandé maintenant** : la valeur est dans la tactique, la perception et la visée, qu'aucun addon ne fournit |

Décision proposée : utility maison maintenant. LimboAI en seconde étape si la couche comportement dépasse environ 8 états ou si le débogage visuel devient nécessaire. Beehave est écarté au profit de LimboAI (HSM natif et perf C++ pour 8 bots par conteneur).

## 3. Chiffres de référence

| Paramètre | Référence | Chez nous | Proposition |
|---|---|---|---|
| Réaction visuelle simple | ~190 ms (labo), médiane ~273 ms (population) ; pros −20 à −70 ms | 450 / 300 / 200 ms fixes | tirage normal (σ ≈ 40 ms) autour de 480 / 330 / 230 ms, +120 ms si cible > 35° hors du centre |
| Retard réseau équivalent | peeker's adv. 71-141 ms (Valorant) | 0 ms (bot serveur) | +60 ms de perception en partie en ligne (réglable), 0 en entraînement solo |
| Délai avant d'ouvrir le feu | CS Easy « substantial », Hard 0 | 0 | Recrue +250 ms, Vétéran +80 ms, Élite 0 |
| Erreur de visée initiale | offset régénéré périodiquement (CS) | 6 / 3,5 / 1,5° en mètres@10 m, retirée **chaque frame** | angle : 5 / 2,5 / 1,0°, régénéré toutes les 0,35-0,7 s |
| Décroissance en suivi | — | τ = 0,8 s | garder 0,8 s ; ×1,5 d'erreur si la cible a une vitesse angulaire > 60°/s |
| Vitesse de rotation | ressort-amortisseur (CS) | plafond linéaire 220°/s | ressort k/d par difficulté, pic 300 / 500 / 800°/s, dépassement de 5-15 % au flick |
| Condition de tir | — | tire dès la réaction écoulée | erreur < demi-largeur angulaire de la hitbox + dispersion |
| Rafales à distance | CS : burst au fusil à distance | spray permanent | autos au-delà de 25 m : 3-5 balles puis 150-250 ms de pause |
| Mémoire de l'ennemi | dernière position connue (CS), cachettes prédites (KZ) | effacée dès la perte de LOS | 6 s (dernière position + vitesse), puis enquête |
| Portée d'ouïe | — | tirs 22 m, pas : aucune | tirs 40 m, sprint 15 m, marche 0 |
| Humanité perçue | BotPrize 52 % (humains 41 %) | — | objectif : erreurs visibles, hésitations, strafes réactifs |
| Couches IA | 3 (KZ), plusieurs FSM concurrentes (CS) | 1 (monolithique) | équipe → individu → visée |

## 4. Écarts avec notre code

1. **Objectif TDM aléatoire et omniscient.** `scripts/modes/TDMMode.gd:57-61` renvoie `enemies[randi() % size]`, soit une position **vivante** d'ennemi. `BotBrain._current_goal()` (`BotBrain.gd:313-321`) est appelé à chaque tick, et la cible navmesh est réassignée toutes les 0,5 s (`BotBrain.gd:254-258`). **Impact** : le bot change d'ennemi cible toutes les 0,5 s, va et vient, et « sait » où sont les ennemis. Cela contredit le principe « pas de wall-hack » de `BotBrain.gd:15-18`.
2. **Objectif SnD aléatoire.** `scripts/modes/SnDMode.gd:401-408` tire A ou B au hasard à chaque appel. Pas de rôles attaque/défense, pas de porteur de bombe, pas de planification. **Impact** : les bots oscillent entre les deux sites et le mode tactique est injouable avec eux.
3. **Erreur de visée re-tirée à chaque frame, en mètres fixes.** `BotBrain.gd:204-213` : `radius := err * 10.0`, puis un bruit uniforme dans un **cube** chaque tick. **Impact** : tremblement non humain. Environ 11° d'erreur (Vétéran) à 3 m, donc ratés au contact, contre environ 0,9° à 40 m, donc laser de loin, et en visant toujours la tête (`BotBrain.gd:118-119`).
4. **Tir sans alignement.**
   - `BotBrain.gd:199-202` : `fire_held` et `fire_pressed` passent à vrai dès que la réaction est écoulée, même si le bot tourne encore (220°/s, `BotBrain.gd:29`), et `fire_pressed` reste vrai à chaque frame.
   - Aucune rafale ni pause à distance.
   
   **Impact** : les premières balles partent dans le décor, et le recul est mal géré de loin.
5. **Mouvements spéciaux aléatoires en combat.** `BotBrain.gd:289-301` : toutes les 3-7 s, 40 % de saut, 30 % d'accroupi (en simple *tap*, donc un slide s'il court) et 30 % de plongeon. **Impact** : dispersion aérienne de +2° (`ravage.tres`), et le plongeon interdit le tir (`Weapon._can_act`, `Weapon.gd:195-196`, plus `dive_to_fire` 0,46 s). Le bot se désarme lui-même au pire moment.
6. **Pas de perception des dégâts.** Rien n'écoute `Health.damaged` dans `BotBrain`. **Impact** : un bot touché dans le dos (hors du cône de 100°, `BotBrain.gd:26`) continue sa route. C'est le comportement le plus « stupide » aux yeux d'un joueur.
7. **Pas de mémoire.** Quand la LOS se coupe, `_target_id` repasse à -1 (`BotBrain.gd:174-185`) et le bot retourne à l'objectif du mode. **Impact** : l'ennemi qui recule derrière un mur est « oublié » instantanément.
8. **LOS sur un seul point (la tête).** `BotBrain.gd:118-140`. **Impact** : un corps exposé tête cachée n'est pas vu, alors qu'une tête qui dépasse de 5 cm l'est.
9. **Ouïe limitée aux tirs.** `BotBrain.gd:145-157` (22 m, 1 s). Pas de pas ni d'impacts. **Impact** : un joueur qui sprinte derrière un bot n'est jamais entendu.
10. **Cible = ennemi le plus proche.** `BotTargetSelect.gd:12-20`. **Impact** : ignore qui tire sur le bot, qui a peu de PV, qui est déjà dans le viseur (coût de rotation).
11. **Mouvement de combat = foncer.** `BotBrain.gd:254` prend la position de la cible comme but de navigation, avec un strafe latéral de ±0,8 qui pousse hors du chemin (`BotBrain.gd:276-284`). Aucune distance préférée par arme, aucune couverture, aucun repli à PV bas. **Impact** : les bots meurent en terrain ouvert, et un pompe tente d'engager un sniper à 40 m.
12. **Toujours en sprint.** `walk_held = false` (`BotBrain.gd:287`). **Impact** : dispersion de mouvement maximale en permanence, et aucune approche furtive (Booth : « sneaking » en fin de round).
13. **Pas d'anti-blocage ni d'évitement.** `avoidance_enabled = false` (`BotBrain.gd:62`), pas de surveillance de la vitesse moyenne. **Impact** : bots coincés les uns contre les autres ou contre un rebord (aggravé par l'absence de step-up, voir MV-01 dans `01_game_feel.md`).
14. **Capacités au hasard.** `BotBrain.gd:353-361` : 0,2 % par tick à 60 Hz, soit une capacité toutes les ~8 s, choisie au hasard (ultime compris), sans condition. **Impact** : soin à pleins PV, mur face au vide, ultime gâché. Le joueur le voit.
15. **Achat fixe.** `BotBrain.gd:339-348` achète toujours `default_loadout_ids()[0]`. **Impact** : pas d'économie ni de variété d'armes, ce qui rend les armes des bots prévisibles.
16. **Difficulté à deux axes seulement.** `BotReaction.gd:16-41` ne gère que la réaction et l'erreur. **Impact** : Recrue et Élite ont les mêmes décisions, et aucune personnalité ne varie entre bots.
17. **Latence nulle.** Les bots perçoivent l'état serveur instantanément. **Impact** : en ligne, ils ont un avantage structurel d'environ 70-140 ms sur les humains (voir §2.2).
18. **Pas de banc de mesure.** Aucune métrique automatique (temps bloqué, changements d'objectif par minute, précision par distance). **Impact** : les régressions de comportement ne sont visibles qu'en playtest.

## 5. Tâches

```
- id: BOT-01
  title: "Objectifs de mode stables, par bot et sans omniscience (TDM/SnD/Hardpoint/Duel)"
  files: [scripts/modes/GameMode.gd, scripts/modes/TDMMode.gd, scripts/modes/SnDMode.gd, scripts/modes/HardpointMode.gd, scripts/modes/DuelMode.gd, scripts/ai/BotBrain.gd, tests/ai/test_bot_goals.gd]
  depends_on: []
  size: M
  acceptance: "`bot_goal_for(team, bot_id, bot_pos)` ; le but d'un bot ne change que sur événement (kill, bombe posée, zone qui tourne, but atteint) ou au plus toutes les 6 s ; TDM ne renvoie plus de position vivante d'ennemi (points de patrouille/zones chaudes de la carte + dernière position connue partagée par l'équipe) ; SnD : site choisi une fois par round par équipe ; test : 60 s de simulation → <= 12 changements de but par bot, 0 appel qui lit une position ennemie hors perception."

- id: BOT-02
  title: "Modèle de visée humain (angle, offset périodique, ressort-amortisseur, tir conditionné)"
  files: [scripts/ai/BotAim.gd, scripts/ai/BotReaction.gd, scripts/ai/BotBrain.gd, tests/ai/test_bot_aim.gd]
  depends_on: []
  size: M
  acceptance: "BotAim pur : erreur en DEGRÉS régénérée toutes les 0.35-0.7 s (jamais par frame), décroissance τ=0.8 s en suivi, ×1.5 si vitesse angulaire cible > 60°/s ; rotation par ressort-amortisseur (k, d, pic par difficulté 300/500/800°/s, dépassement 5-15 % au flick) ; tir autorisé seulement si erreur < demi-largeur angulaire de la hitbox visée + dispersion arme ; point visé = torse au-delà de 20 m sauf Élite ; tests : précision attendue (Monte-Carlo 1000 engagements) à 5 m / 20 m / 40 m par difficulté dans des fourchettes documentées, monotone Recrue < Vétéran < Élite, précision à 5 m >= précision à 40 m."

- id: BOT-03
  title: "Perception complète (multi-points, dégâts reçus, pas, mémoire, info d'équipe, latence équivalente)"
  files: [scripts/ai/BotPerception.gd, scripts/ai/BotMemory.gd, scripts/ai/BotBrain.gd, scripts/combat/Weapon.gd, tests/ai/test_bot_memory.gd]
  depends_on: []
  size: M
  acceptance: "LOS testée sur tête/torse/bassin (visible si >= 1 point) ; Health.damaged → le bot oriente sa vue vers l'attaquant (±20° d'erreur) en <= réaction+100 ms ; ouïe : tirs 40 m, sprint ennemi 15 m, impacts proches 5 m ; mémoire : dernière position + vitesse, confiance qui décroît sur 6 s ; partage équipe avec 0.5-1 s de délai ; délai de perception réseau réglable (défaut 60 ms en ligne, 0 en solo) ; réaction = N(base, 40 ms) + 120 ms si cible > 35° du centre ; tests purs sur BotMemory (décroissance, fusion d'observations)."

- id: BOT-04
  title: "Discipline de combat (plus de sauts/plongeons aléatoires, strafe réactif, distance par arme, rafales)"
  files: [scripts/ai/BotBrain.gd, scripts/ai/BotCombatStyle.gd, tests/ai/test_bot_combat_style.gd]
  depends_on: [BOT-02]
  size: S
  acceptance: "suppression du tirage saut/crouch/dive aléatoire en combat ; strafe ADAD à intervalles 0.25-0.6 s déclenché quand le bot est pris pour cible ; armes de précision (Marqueur/Percuteur/Faucheur) : s'arrêter (vitesse < 30 % sprint) avant de tirer ; distance préférée par catégorie (pompe < 6 m, SMG 5-15, fusil 10-35, sniper > 25) ; autos au-delà de 25 m : rafales de 3-5 balles + pause 150-250 ms ; walk_held quand il enquête ou en fin de round ; tests purs sur la table de style."

- id: BOT-05
  title: "Données tactiques de carte pré-calculées (cachettes, couverture par direction, spots de tir)"
  files: [tools/bake_bot_spots.gd, scripts/ai/BotSpots.gd, resources/bot_spots/test_arena.tres, tests/ai/test_bot_spots.gd]
  depends_on: []
  size: M
  acceptance: "une ressource par carte sous resources/bot_spots/<map_id>.tres (test_arena d'abord) ; outil headless qui échantillonne la navmesh (pas ~2 m) et stocke par spot la couverture sur 8 directions à hauteur accroupi et debout (raycasts), un flag 'sniping' (lignes de vue > 30 m) et des 'approach points' ; ressource par carte chargée par GameWorld ; requête BFS sur la navmesh (pas à vol d'oiseau) ; test sur test_arena : >= 1 spot couvert à < 10 m de chaque point navigable, temps de bake < 30 s."

- id: BOT-06
  title: "Choix de position par score (attaque, peek, repli, tenue d'objectif)"
  files: [scripts/ai/BotPositionPicker.gd, scripts/ai/BotBrain.gd, tests/ai/test_bot_position_picker.gd]
  depends_on: [BOT-03, BOT-05]
  size: M
  acceptance: "fonction pure qui score les candidats BotSpots (couverture vs menaces connues, ligne de tir vers la cible ou absence de LOS pour le repli, bande de distance de l'arme, coût de trajet, occupation par un allié, danger) avec des poids par comportement ; repli = spot non vu par les ennemis connus et plus proche des alliés (sinon le moins exposé) ; tests : scénarios fixes → spot attendu choisi ; jamais deux bots sur le même spot."

- id: BOT-07
  title: "Sélecteur de comportement utility avec hystérésis + personnalités + moral"
  files: [scripts/ai/BotUtility.gd, scripts/ai/BotBehaviors.gd, scripts/ai/BotBrain.gd, tests/ai/test_bot_utility.gd]
  depends_on: [BOT-03]
  size: L
  acceptance: "actions Engager, Peek, Se replier/Régénérer (PV < 35 %), Traquer (dernière position), Enquêter (bruit), Objectif, Patrouiller, Recharger à couvert, Capacité ; score = produit de considérations [0,1] via courbes ; hystérésis +0.1 pour l'action courante et engagement minimum 0.5 s ; personnalité (agressivité, patience, esprit d'équipe) tirée par bot, moral (+kill/objectif, −mort) qui module rush/camp ; BotBrain réduit à capteurs → utility → comportement → input ; tests : tables de scénarios → action attendue, aucune oscillation > 2 changements/s sur 30 s de replay."

- id: BOT-08
  title: "Couche équipe (commandant) pour SnD/Hardpoint/TDM + carte de danger"
  files: [scripts/ai/TeamBrain.gd, scripts/ai/DangerMap.gd, scripts/modes/SnDMode.gd, scripts/modes/HardpointMode.gd, scripts/modes/TDMMode.gd, tests/ai/test_team_brain.gd]
  depends_on: [BOT-01, BOT-06, BOT-07]
  size: L
  acceptance: "un TeamBrain par équipe côté serveur ; SnD attaque : un site par round (pondéré par DangerMap), un porteur désigné (un humain de l'équipe a priorité si présent), 1 lurker, pose quand le site est 'clear' (aucun ennemi connu depuis 3 s), alliés en couverture ; défense : répartition 2/2 puis rotation sur info (bombe vue/posée) ; post-plant : positions de tenue ; désamorçage seulement si aucun ennemi connu ou fumée/mur posé ; TDM : 2 axes, espacement >= 6 m, suivi pour trader ; DangerMap : +1 autour d'une mort alliée, décroissance 30 s, utilisée dans le choix d'axe ; test : 20 rounds SnD bot vs bot → taux de pose >= 60 % côté attaque, 0 round où un bot alterne A/B plus de 2 fois."

- id: BOT-09
  title: "Anti-blocage, évitement entre bots, strafe contraint à la navmesh"
  files: [scripts/ai/BotBrain.gd, scripts/ai/BotStuck.gd, tests/ai/test_bot_stuck.gd]
  depends_on: []
  size: S
  acceptance: "vitesse moyenne sur 1 s < 0.5 m/s avec chemin actif → séquence wiggle latéral 0.3 s, puis saut, puis repath vers un point intermédiaire alternatif ; NavigationAgent3D avoidance_enabled (radius 0.45) ; déplacement de strafe projeté sur la navmesh (map_get_closest_point) avant d'être appliqué ; métrique : sur 5 min bot vs bot en test_arena, temps cumulé bloqué < 2 % par bot (dépend aussi de MV-01 dans 01_game_feel.md pour les marches)."

- id: BOT-10
  title: "Usage des capacités par règles de situation"
  files: [scripts/ai/BotAbilityRules.gd, scripts/ai/BotBrain.gd, tests/ai/test_bot_ability_rules.gd]
  depends_on: [BOT-07]
  size: M
  acceptance: "fonction pure (agent, slot, contexte) → utiliser ou non + direction ; soin si PV < 50 % et hors combat ; mur/fumée pendant un repli, une pose ou un désamorçage ; éblouissement juste avant de peeker un ennemi connu ; reveal à la perte de contact ; tremplin pour rotation ; ultime si >= 2 ennemis dans le rayon ou PV < 30 % ; plus aucun tirage aléatoire par tick ; tests : un scénario par capacité."

- id: BOT-11
  title: "Profils de difficulté data-driven (multi-axes, façon CS bot) + transparence"
  files: [scripts/ai/BotProfile.gd, resources/bots/recrue.tres, resources/bots/veteran.tres, resources/bots/elite.tres, scripts/ai/BotReaction.gd, tests/ai/test_bot_profile.gd]
  depends_on: [BOT-02, BOT-03]
  size: S
  acceptance: "chaque profil fixe réaction (moyenne, σ), délai d'ouverture du feu (250/80/0 ms), erreur de visée, ressort k/d, discipline de rafale, probabilité d'utiliser la couverture, qualité d'achat, usage des capacités ; aucun profil ne voit à travers les murs ni ne connaît les positions hors perception ; aucune difficulté adaptative cachée (adaptatif seulement en entraînement, affiché) ; tests : chaque champ monotone entre les trois profils."

- id: BOT-12
  title: "Achat SnD selon l'économie et la personnalité"
  files: [scripts/ai/BotBuy.gd, scripts/ai/BotBrain.gd, tests/ai/test_bot_buy.gd]
  depends_on: []
  size: S
  acceptance: "décision pure (crédits, round, score, préférence) → eco / force / achat complet ; choix d'arme dans la catégorie préférée de la personnalité, dans le budget ; test : 3000 crédits → arme principale >= 2900 ; 800 → pistolet/Magnum ou eco ; jamais d'achat refusé par le serveur."

- id: BOT-13
  title: "Banc de mesure automatique des bots (headless) avec seuils de régression"
  files: [tools/bot_bench.gd, tests/ai/test_bot_bench_thresholds.gd, docs/TESTING.md]
  depends_on: [BOT-01, BOT-02, BOT-09]
  size: M
  acceptance: "partie headless bot vs bot (TDM 4v4, SnD 10 rounds) qui exporte en JSON : temps bloqué, changements de but/min, précision par bande de distance et difficulté, TTK effectif médian, taux de pose/désamorçage, capacités utilisées/min ; seuils vérifiés en CI (ex. précision Vétéran 20 m entre 25 et 45 %, temps bloqué < 2 %) ; commande documentée dans docs/TESTING.md."```
