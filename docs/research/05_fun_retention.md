# 05 — Fun, rétention, F2P cosmétique, playtests

> Statut : REMPLI (recherche du 2026-09-23). Les chiffres marqués *(hypothèse)* sont nos
> propositions ; les autres sont sourcés. Code lu : `scripts/modes/*`, `scripts/core/MatchConfig.gd`,
> `scripts/ui/hud/EndPanel.gd`, `docs/ROADMAP.md` §4, §6 (P2.8, P2.9, P4–P5), §10.

## 1. Résumé (10 lignes)

1. **Spectre Divide** avait une bonne rétention, mais pas assez de nouveaux joueurs chaque jour (400 k la première semaine, pic à 10 k simultanés). Pour un petit jeu, le haut de l'entonnoir compte autant que la rétention.
2. **Trois causes de mort récurrentes (2024–2026)** :
   - serveurs ou hitreg défaillants au lancement (Spectre Divide, Splitgate 2, XDefiant) ;
   - bundles à 80–90 $ (Spectre, Splitgate 2) ;
   - identité diluée (Splitgate 2 a perdu ses portails ; Concord était « fine », et c'est mortel).
3. **Relancer marche rarement** : Splitgate: Arena Reloaded a fait moins de 10 % du pic de lancement (2 297 joueurs) et s'éteint en 2026. La première impression est la seule.
4. **Régulation** : depuis juin 2026, PEGI classe **16 minimum** tout jeu qui vend des objets aléatoires payants, et **12 minimum** en cas d'offres limitées dans le temps ou en quantité. Le Digital Fairness Act de l'UE est attendu au T4 2026 (prix réels, contrôle parental, peut-être l'interdiction des loot boxes).
5. **France** : le régime JONUM (loi SREN, décret du 4 février 2026) ne vise que les objets **monétisables et échangeables**. Des cosmétiques non échangeables n'y entrent pas.
6. Notre modèle (cosmétiques seuls, sans loot box, pass permanent) est donc le bon. **Pas de boutique tournante à minuteur**, sinon PEGI 12 minimum ; prix affichés en euros.
7. **Durées de match** : nos modes durent 8 à 20 min (§3.1). Valorant a ajouté des formats courts : Spike Rush ≈ 8 min. Notre R&D (premier à 6) est au bon format ; il manque un enchaînement rapide après un match.
8. **Boucle de session** : fin de match, puis progression visible, puis « Rejouer » en 1 action. Aujourd'hui, `EndPanel` n'offre que Rejouer/Menu, sans progression ni résumé.
9. **Playtests** :
   - cadence hebdo (Valve) ;
   - questionnaires sur des échelles de 5 à 7 points, répétés d'un test à l'autre (PlaytestCloud) ;
   - télémétrie pour le *quoi*, observation pour le *pourquoi* ;
   - vagues d'invitations à la Deadlock, où l'invitation récompense la qualité des retours.
10. **Repères de rétention PC** (GameAnalytics) : J1 top 25 % > 30 % ; J7 médiane < 4 %, top 25 % 6–7 % ; J30 top 10 % ≈ 2,5 %.

## 2. Findings (sources inline)

### 2.1 Boucles : core, session, méta

- **Core (≈ 30 s)** : se déplacer (slide, dive, roulade), puis engager, tuer ou mourir, puis réapparaître ou finir la manche. C'est notre pilier n°1 (`ROADMAP.md` §1) ; on le mesure par le temps jusqu'au premier engagement et par la part du temps passée sans contact *(métriques proposées, §3.3)*.
- **Session (10–30 min)** : un match, un écran de fin (progression, performances), puis on rejoue. Les leçons de Valorant vont dans ce sens : des modes courts (Spike Rush ≈ 8 min, 4 manches, sans économie) pour débuter et s'échauffer ([Hotspawn](https://www.hotspawn.com/valorant/guide/valorant-guide-for-beginners), [Riot — Beginner's Guide](https://playvalorant.com/en-us/news/announcements/beginners-guide/)).
- **Méta (jours, semaines)** : niveau de compte, maîtrise d'arme et d'agent, défis, rang (`ROADMAP.md` P5.3, P4.6). Sans pouvoir à vendre (pilier « Respect du joueur »).

### 2.2 Durée de match par mode

- **Valorant** : Spike Rush ≈ 8 min (source ci-dessus).
- **CoD** : TDM en 6v6 à 75 kills, ramené chez nous à 50 en 4v4 ; Hardpoint et R&D selon les règles de la ligue CDL (`ROADMAP.md` §4, sources au §11).
- **Nos durées estimées** : §3.1.

### 2.3 Matchmaking et estimation de niveau

- **OpenSkill** (Weng-Lin, licence libre) gère les équipes et les tailles inégales ([arXiv 2401.05451](https://arxiv.org/abs/2401.05451), déjà retenu en `ROADMAP.md` §5).
- **Une note par file** (4v4, Duel, Duo) *(hypothèse)* : le skill en 1v1 ne se transfère pas au 4v4.
- **Faible population** *(hypothèse, standard du genre)* :
  - d'abord le ping, puis l'écart de niveau, qui s'élargit avec l'attente ;
  - des bots signalés en casual seulement (`ROADMAP.md` P4.4) ;
  - le questionnaire PvP de PlaytestCloud demande explicitement si le joueur savait quand il affrontait des bots ([PlaytestCloud](https://help.playtestcloud.com/en/articles/6292049-survey-questions-for-playtesting-your-pvp-multiplayer-gameplay)). Bots cachés : les joueurs le sanctionnent (`ROADMAP.md` §10).

### 2.4 Progression sans pay-to-win

- **Marvel Rivals** : cosmétiques seulement, et le pass acheté ne périme jamais ([GameSpot](https://www.gamespot.com/articles/marvel-rivals-will-only-sell-cosmetics-will-let-players-keep-purchased-battle-passes-forever/1100-6528239/)).
- **Ce qui a échoué** : Concord payant 40 $, sans différenciation ; « the roster is your brand » ([gamedesignskills](https://gamedesignskills.com/game-design/why-did-concord-fail/), [Tom's Guide](https://tomsguide.com/gaming/concord-review)).
- **Chez nous** :
  - progression de maîtrise d'arme (camos d'encre) et d'agent ;
  - niveau de compte ;
  - agents tous gratuits ;
  - un cosmétique ne doit **jamais** toucher les teintes réservées à l'ennemi (magenta, citron), règle de `design.md` §9 à étendre aux skins.

### 2.5 Battle pass, loot boxes, régulation UE/France, mineurs

- **PEGI, juin 2026** ([Reed Smith](https://www.reedsmith.com/articles/pegi-launches-interactive-risk-categories-overhauls-age-ratings-for-loot-boxes-in-game-spending-and-communication-features/), [Wccftech](https://wccftech.com/games-with-loot-boxes-now-get-pegi-16-rating-starting-june-2026-ea-sports-fc/)) :
  - « paid random items » (loot boxes, packs, gacha, roues) : **PEGI 16 minimum**, 18 si c'est central ;
  - **offres limitées dans le temps ou en quantité : PEGI 12 minimum** ;
  - NFT ou blockchain : PEGI 18 ;
  - s'applique aux nouveaux jeux soumis à partir de juin 2026.
- **UE, Digital Fairness Act** ([Freshfields](https://www.freshfields.com/en/our-thinking/blogs/technology-quotient/the-eus-proposed-digital-fairness-act-a-game-developers-guide-to-potential-imp-102ltio), [CADE](https://cadeproject.org/updates/eu-weighs-stricter-rules-for-addictive-gaming-features/)) :
  - proposition attendue au **T4 2026** ;
  - pistes : prix en euros à côté de toute monnaie virtuelle, fenêtre de confirmation avant achat, autorisation parentale pour les mineurs ;
  - interdiction possible des loot boxes, poussée notamment par les Pays-Bas.
- **France, JONUM** ([ANJ](https://anj.fr/jeux-objets-numeriques-monetisables-jonum), [Bird & Bird](https://www.twobirds.com/fr/insights/2025/france/loi-sren-nouvelle-definition-et-nouveau-regime-pour-les-jeux-a-objets-numeriques-monetisables-jonum)) :
  - loi SREN du 21 mai 2024, décret n° 2026-60 du 4 février 2026 (expérimentation) ;
  - 4 critères cumulatifs : sacrifice financier, hasard, distribution en ligne, **objets monétisables** (échangeables ou convertibles) ;
  - aucune communication commerciale vers les mineurs.
  - Des cosmétiques liés au compte et non échangeables n'entrent pas dans le régime JONUM.
- **Conséquence pour nous** :
  - ni hasard payant, ni échange ou revente de cosmétiques ;
  - prix en euros (idéalement **sans monnaie premium** : achat direct via Steam) ;
  - pass permanent, pas de boutique à minuteur, confirmation avant achat.
  - Tout ça tient sous PEGI 12 (thème cartoon) et reste compatible avec le DFA quelle que soit sa version finale.

### 2.6 Playtests pour une petite équipe : méthode, questions, télémétrie

- **Cadence** : à la Valve, lundi on planifie, vendredi on playtest. On observe sans expliquer, on enregistre les testeurs à distance sous OBS ([LDB — Playtesting](https://book.leveldesignbook.com/process/blockout/playtesting)).
- **Questionnaire PvP** ([PlaytestCloud](https://help.playtestcloud.com/en/articles/6292049-survey-questions-for-playtesting-your-pvp-multiplayer-gameplay)), échelle de 7 points, répétée à chaque test :
  - « je savais quand je jouais contre de vrais joueurs / contre des bots » ;
  - « mes adversaires étaient plus ou moins forts que moi » ;
  - « il était clair comment lancer un match » ;
  - « mes contrôles ont nui à ma performance » (codage inversé) ;
  - « les contrôles marchaient bien pour ce type de jeu ».
- **Classiques en plus** : fun sur 10, envie de rejouer, recommandation ([PlaytestCloud — default questions](https://help.playtestcloud.com/en/articles/1187190-default-survey-questions-five-star-ratings)).
- **Limite des chiffres** : sur de petits échantillons, les notes ne sont pas la source principale d'insights ; la télémétrie dit quoi, pas pourquoi ([PlaytestCloud](https://help.playtestcloud.com/en/articles/6292049-survey-questions-for-playtesting-your-pvp-multiplayer-gameplay), [NN/g — Games User Research](https://www.nngroup.com/articles/game-user-research/)).
- **Apex** : un mois de tests internes micros coupés, sous pseudos aléatoires, pour valider le ping ([Game Developer](https://www.gamedeveloper.com/design/respawn-played-with-muted-mics-to-get-i-apex-legends-i-smart-comms-system-just-right)). Il faut tester *la condition réelle* : chez nous, jouer avec des inconnus et sans vocal.
- **Deadlock** ([Game Developer](https://www.gamedeveloper.com/pc/what-the-heck-is-valve-doing-with-these-informal-deadlock-ndas-), [PC Gamer](https://www.pcgamer.com/games/moba/deadlock-playtest-how-to-get-in/)) :
  - invitations par vagues ; le droit d'inviter dépend du temps de jeu, de l'historique de signalements et du volume de retours ;
  - NDA levé le 23 août 2024 pour laisser la communauté streamer.
  - Transposé chez nous : Steam Playtest par créneaux (`ROADMAP.md` P6.5).

### 2.7 Survivre en shooter indé : leçons 2023–2026

| Jeu | Ce qui l'a tué | Leçon pour nous | Source |
|---|---|---|---|
| **Spectre Divide** (2024–2025) | Rétention bonne mais trop peu de nouveaux joueurs par jour ; serveurs cassés les premières heures (« it killed our early momentum ») ; bundle à 90 $ ; mécanique Duality trop dure pour les débutants ; attentes gonflées par Shroud ; pas de couverture presse entre bêta et lancement | Bots + gratuité + files courtes pour le haut de l'entonnoir ; test de charge avant tout lancement public ; aucun prix fort au lancement ; FTUE qui enseigne *notre* mécanique (slide/dive) en ≤ 3 min | [80.lv](https://80.lv/articles/nate-mitchell-and-matt-hansen-on-the-death-of-spectre-divide-mountaintop-studios), [Kotaku](https://kotaku.com/spectre-divide-shroud-refunds-season-1-shutting-down-1851769661) |
| **XDefiant** (2024–2025) | Bon lancement, puis < 20 k simultanés en août 2024 ; hitreg, serveurs, peu de contenu, quasi pas de marketing après le lancement | Hitreg juste (P1.3 lag comp) avant tout public ; cadence de contenu tenable ; communication continue | [Game World Observer](https://gameworldobserver.com/2024/12/04/why-ubisoft-shut-down-xdefiant-retention-layoffs), [ONE Esports](https://www.oneesports.gg/gaming/why-is-xdefiant-shutting-down/) |
| **Concord** (2024) | 40 $, « fine » mais pas urgent, roster sans personnalité, invisible avant sa fermeture | Gratuit ; persos excentriques et lisibles (notre direction) ; identité forte | [gamedesignskills](https://gamedesignskills.com/game-design/why-did-concord-fail/), [Bryter](https://www.bryter-global.com/blog/concord-video-game-marketing) |
| **Splitgate 2** (2025–2026) | « We launched too early » ; abandon des portails au profit de capacités et factions ; bundle à 80 $ ; relance à 2 297 joueurs au pic ; serveurs coupés en 2026 | Ne jamais diluer le mouvement, notre crochet ; une seule vraie sortie : passer par Playtest/Early Access honnête plutôt que relancer | [TheGamer](https://www.thegamer.com/splitgate-2s-relaunch-arena-reloaded-troubles/), [VGC](https://www.videogameschronicle.com/news/splitgate-2-is-unlaunching-as-developer-1047-games-cuts-staff/), [Wikipedia](https://en.wikipedia.org/wiki/Splitgate_2) |
| **Deadlock** (en cours) | — (succès en playtest fermé) | Vagues d'invitations, feedback filtré, lever le NDA quand le jeu est prêt à être montré | [Game Developer](https://www.gamedeveloper.com/pc/what-the-heck-is-valve-doing-with-these-informal-deadlock-ndas-) |

## 3. Tableaux de métriques

### 3.1 Durée de match estimée par mode (nos règles, `ROADMAP.md` §4)

| Mode | Règle | Estimation | Référence | Verdict |
|---|---|---|---|---|
| TDM 4v4 | 50 kills ou 10 min, respawn 3 s | 8–10 min | CoD 6v6 75 kills / 10 min | OK |
| Hardpoint 4v4 | 250 pts ou 10 min, zones de 60 s | 7–10 min | Ligue CoD 250 pts | OK |
| R&D 4v4 | premier à 6, changement de camp après 5, achat 15 s + manche 90 s (+ bombe 45 s) | 6–11 manches × 1,7–2,5 min ≈ **12–25 min** | Valorant Spike Rush ≈ 8 min | OK en classé ; trop long pour découvrir le jeu : proposer un format court en premier match *(hypothèse)* |
| Duel / Duo | premier à 6, manche de 40 s puis zone | 6–11 manches × 45–70 s ≈ **6–12 min** | Gunfight CoD | OK |
| Sélection d'agent | 15 s | — | — | OK |

### 3.2 Rétention PC (GameAnalytics 2025/2026)

| Jalon | Médiane | Top 25 % | Top 10 % | Notre cible Playtest *(hypothèse)* |
|---|---|---|---|---|
| J1 | — | > 30 % | ≈ 40 % | ≥ 30 % |
| J7 | < 4 % | 6–7 % | — | ≥ 7 % |
| J30 | — | — | ≈ 2,5 % | ≥ 2,5 % |

Source : [GameAnalytics 2026 Mobile & PC Benchmarks](https://www.gameanalytics.com/reports/2026-mobile-pc-gaming-benchmarks), [résumé gamedevreports](https://gamedevreports.substack.com/p/gameanalytics-mobile-and-pc-game) (3 582 jeux à ≥ 100 MAU).

### 3.3 Indicateurs de fun à suivre par match *(proposés, à croiser avec les playtests)*

| Indicateur | Cible *(hypothèse)* | Pourquoi |
|---|---|---|
| Temps spawn → premier dégât infligé ou subi (TDM) | 5–12 s | Trop court : spawn-trap ; trop long : ennui |
| Morts < 3 s après un spawn | < 5 % | Protection de spawn et spawns dynamiques (LD-02) |
| Part de kills après une action de mouvement (slide, dive, roulade) dans les 2 s | ≥ 20 % | Le pilier n°1 existe-t-il en jeu ? |
| Taux de victoire par camp et par site R&D | 45–55 % | `ROADMAP.md` P2 |
| Taux d'utilisation max d'une arme | ≤ 30 % | `ROADMAP.md` P2 |
| Abandons en cours de match | < 5 % | Frustration |
| Note « fun » post-match (1–5) | ≥ 4 | Critère de sortie P2 |
| Délai fin de match → match suivant | ≤ 20 s | Boucle de session |

## 4. Écarts avec notre jeu

1. **Aucune télémétrie** : P2.8 non fait (`docs/ROADMAP.md` §6). Aucun événement kill, spawn, manche ou achat n'est journalisé, donc pas de heatmap et aucun des indicateurs du §3.3. Point d'accroche : `scripts/networking/GameWorld.gd` (`_record_kill`, spawn, `reset_match`).
2. **Fin de match sans session** : `scripts/ui/hud/EndPanel.gd` montre vainqueur, score, Rejouer et Menu. Pas de résumé personnel, pas de progression, pas de relance automatique, pas de question « fun ».
3. **Aucune progression** : P5.3 non fait, aucun `scripts/meta/`.
4. **Pas de note de niveau** : OpenSkill n'existe qu'en roadmap. Les bots ont 3 difficultés fixes (`MatchConfig.Difficulty`) et les équipes ne sont pas équilibrées.
5. **Monétisation pas encore bornée par le code** : la roadmap P5.6 dit « une seule monnaie ». Recommandation : **aucune monnaie premium** (prix directs en euros via Steam), pas d'offre à minuteur (PEGI 12) ; règles à figer en tests avant toute boutique.
6. **Pas de protocole de playtest écrit** : P2.9 (2 sessions internes par semaine, 1 externe par mois) sans questionnaire, grille d'observation ni outil d'agrégation.
7. **Premier match** : rien n'oriente le nouveau joueur vers un format court. Le menu propose les 5 modes à égalité (`scripts/ui/MainMenu.gd`, `MODE_LABELS`).

## 5. Tâches

```
- id: FUN-01
  title: Enchaînement de session — « Rejouer » relance le même salon en ≤ 20 s (vote ou compte à rebours de 10 s), bots gardés, équipes rééquilibrées
  files: [scripts/networking/GameWorld.gd, scripts/ui/hud/EndPanel.gd, tests/networking/test_rematch.gd]
  depends_on: []
  size: M
  acceptance: après la fin d'un match, un compte à rebours de 10 s relance automatiquement le même mode et la même carte si la majorité des humains n'a pas quitté ; « Menu » quitte proprement ; délai mesuré fin → nouveau spawn ≤ 20 s en test headless ; les stats par joueur sont remises à zéro.
- id: FUN-02
  title: Résumé de fin de match personnel (K/D/A, dégâts, précision, meilleure série, kills en mouvement, XP gagnée par ligne) sur une page à bandeau pinceau
  files: [scripts/ui/MatchSummary.gd, scripts/ui/hud/EndPanel.gd, scripts/networking/GameWorld.gd]
  depends_on: [FUN-03, FUN-05]
  size: M
  acceptance: la page s'affiche ≤ 1 s après la fin et se lit en 5 s (≤ 6 blocs) ; toutes les valeurs viennent de l'état serveur répliqué ; captures 1920×1080 et 1280×800 ; en mouvement réduit, le décompte d'XP est instantané.
- id: FUN-03
  title: Progression locale (niveau de compte, maîtrise d'arme et d'agent, paliers de camos d'encre) — module pur + sauvegarde user://, prêt pour Nakama
  files: [scripts/meta/Progression.gd, scripts/meta/ProgressionRules.gd, tests/meta/test_progression.gd]
  depends_on: []
  size: M
  acceptance: `ProgressionRules.xp_for(match_result)` est pur et testé (victoire, défaite, objectifs, pas d'XP pour les kills de bots en Classé) ; niveaux 1–50 avec une courbe documentée en commentaire ; aucun déblocage ne donne de puissance (test : l'arsenal et les agents disponibles sont identiques au niveau 1 et au niveau 50) ; la sauvegarde résiste à un fichier corrompu (retour aux valeurs par défaut + log).
- id: FUN-04
  title: Micro-questionnaire post-match (fun 1–5 + 0–2 puces de frustration) et questionnaire de playtest long (7 points, items PlaytestCloud)
  files: [scripts/ui/PostMatchSurvey.gd, scripts/core/Telemetry.gd]
  depends_on: [FUN-05]
  size: S
  acceptance: 1 match sur 3 au maximum affiche la question, qui se ferme en 1 clic ou toute seule en 8 s ; la réponse part en événement `survey` ; le questionnaire long s'ouvre depuis le menu Pause en mode playtest (drapeau `--playtest`).
- id: FUN-05
  title: Télémétrie — événements JSONL locaux (session, match, spawn, kill, manche, achat, capacité, agent, réglages, tutoriel, abandon, fps/ping par match), schéma versionné, envoi Talo plus tard
  files: [scripts/core/Telemetry.gd, scripts/networking/GameWorld.gd, tests/core/test_telemetry.gd]
  depends_on: []
  size: M
  acceptance: chaque événement porte {v, t, match_id, event, ...} et passe la validation du schéma (test) ; un `kill` contient positions tueur/victime, arme, distance, état de mouvement, capacité active, headshot, temps depuis le spawn ; écriture côté serveur seulement pour les événements de jeu ; aucune donnée personnelle hors pseudo (RGPD) ; coût ≤ 0,1 ms par événement.
- id: FUN-06
  title: Kit de playtest — protocole hebdo, grille d'observation, script d'agrégation (questionnaires + indicateurs §3.3) en rapport Markdown
  files: [docs/PLAYTEST.md, tools/playtest_report.py]
  depends_on: [FUN-04, FUN-05]
  size: S
  acceptance: `python tools/playtest_report.py runs/<date>/` produit un rapport avec : note fun moyenne, temps jusqu'au premier engagement, morts < 3 s après spawn, part de kills en mouvement, taux de victoire par camp/site, usage des armes, abandons ; testé sur un match de bots de 10 min ; le protocole dit comment observer sans expliquer et enregistrer sous OBS.
- id: FUN-07
  title: Note OpenSkill par file (4v4, Duel, Duo) + équilibrage des équipes des salons personnalisés
  files: [scripts/meta/OpenSkill.gd, scripts/meta/TeamBalance.gd, tests/meta/test_openskill.gd]
  depends_on: [FUN-03]
  size: M
  acceptance: implémentation Weng-Lin (Plackett-Luce) conforme aux vecteurs de test de la bibliothèque de référence openskill.py (écart < 1e-6) ; `TeamBalance.split(players)` minimise l'écart des moyennes μ entre équipes (test à 8 joueurs) ; les bots ont une note fixe par difficulté et ne modifient jamais la note d'un humain.
- id: FUN-08
  title: Garde-fous de monétisation en code — aucun objet aléatoire payant, pas d'offre à minuteur, prix en euros, cosmétiques non échangeables, lint des teintes réservées sur les skins
  files: [scripts/meta/ShopRules.gd, tools/cosmetic_lint.gd, tests/meta/test_shop_rules.gd]
  depends_on: []
  size: S
  acceptance: `ShopRules.validate(offer)` rejette toute offre avec `random: true`, `expires_at`, `stock_limit`, monnaie non-EUR ou `tradable: true` (tests) ; `cosmetic_lint` échoue si une texture de skin a > 2 % de pixels dans les bandes OKLCH réservées (300–355° et 105–145°, C > 0,08) ; la règle est citée avec ses sources (PEGI juin 2026, DFA, JONUM).
- id: FUN-09
  title: Premier match orienté — au premier lancement, la file par défaut est Arène TDM contre bots RECRUE, puis Duel ; R&D mise en avant après 3 matchs
  files: [scripts/core/MatchConfig.gd, scripts/ui/MainMenu.gd]
  depends_on: [UX-08]
  size: S
  acceptance: sur un profil neuf, « JOUER » lance TDM + bots RECRUE ; le compteur de matchs joués est persisté ; après 3 matchs, la carte R&D reçoit un badge « Nouveau » ; aucun mode n'est verrouillé (seulement ordonné).
- id: FUN-10
  title: Défis quotidiens (3) et hebdomadaires (5) sans FOMO payant — objectifs de jeu (kills en slide, manches gagnées, zones tenues), récompense d'XP seulement
  files: [scripts/meta/Challenges.gd, scripts/meta/ChallengeRules.gd, tests/meta/test_challenges.gd]
  depends_on: [FUN-03, FUN-05]
  size: M
  acceptance: tirage déterministe par date (graine = jour UTC) testé ; au moins 1 défi par jour récompense une action de mouvement ; aucun défi n'exige un achat ou un agent précis ; les défis non terminés restent reportables 1 jour.
```
