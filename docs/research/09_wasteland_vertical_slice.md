# 09 — Wasteland, tranche verticale : une carte finie, testable, jouée par des bots

> Statut : proposition du 2026-09-24 (level design + direction environnement). Rien n'est modifié dans le code ni dans les assets.
> Verdict de playtest à l'origine du document : « very big research and 3D work needed on level design and maps, many visual problems ». La priorité est **une** carte finie qui serve d'étalon : Wasteland, en TDM 4v4 et Hardpoint.
> Lu avant d'écrire :
> - `scripts/levels/maps/layouts/wasteland.gd`, `MapSetup.gd`, `PropCatalog.gd`, `Kit.gd`, `MapCatalog.gd`, `scripts/levels/Backdrop.gd`, `scripts/core/LevelLook.gd` ;
> - `scripts/modes/{GameMode,TDMMode,HardpointMode}.gd`, `scripts/ai/{BotBrain,BotSpots}.gd` ;
> - `tests/maps/test_wasteland.gd`, `.orchestrator/maps-spec-v2.md` §5, `docs/research/03_level_design.md`, `docs/audit/bots.md` ;
> - `docs/STYLE_BIBLE.md` §6, `docs/style/tokens.json`, `docs/assets/ASSET_PLAN.md`, `docs/assets/CREDITS.md` ;
> - `assets/incoming/tripo/restyled/` (planches et `g2_verdicts.json`) ;
> - planches `.orchestrator/refs/wasteland_sheet.png`, `wasteland_hero.png`, épingles 18, 20, 21 et 22.
>
> Preuves : captures `reports/review/20260924-193722/map_shots/wasteland_*.png`, dernière revue avec map_shots ; mesures OKLab sur ces captures ; trois runs `tools/bot_smoke.gd` lancés pour ce document (§b.4).
> Ce document **complète** `03_level_design.md` et ne répète pas ses constats.

## 0. Résumé

1. **Visuel.** La carte actuelle est un blockout habillé, pas une carte finie :
   - sol orange trop saturé (C 0,14–0,15 mesuré, cible 0,09) ;
   - falaises de la même couleur que le sol ;
   - repères noirs, bleu répandu sur toute la carte ;
   - marches qui flottent en l'air ;
   - en vue aérienne, la carte flotte dans un vide gris.
2. **Layout.** La ville est plate : 9 bâtiments sur 10 font 3,2 m. La Grand-Rue est droite. Les 4 zones Hardpoint tiennent dans une boîte de 26 × 17 m, et deux d'entre elles sont à 13 m l'une de l'autre. La crête nord et le lit sud sont mal utilisés.
3. **Données absentes.** La carte ne déclare ni spawns neutres (`tdm_spawns`), ni callouts, ni positions fortes. Les bots patrouillent entre les seuls marqueurs de spawn, placés aux deux extrémités.
4. **Bots.** Au lancement, les 4 membres d'une équipe apparaissent sur le même point (télémétrie). Le bot_smoke donne 0 kill en 120 s sur Wasteland, **mais aussi sur Cargo Ship aujourd'hui** (24 kills à 16 h 43). C'est une régression globale des bots, à régler avant de juger la carte.
5. **Cible.** Trois lanes lisibles :
   - la Crête au nord ;
   - la Grand-Rue sinueuse au centre, coupée par des chicanes tous les 20–25 m ;
   - le Ravin au sud, en contrebas de 1,2 m.

   S'y ajoutent 5 positions fortes, chacune avec au moins 3 accès, et 3 zones Hardpoint espacées de 17 à 28 m et à parité (±8 %). La carte a 14 callouts, 24 spawns neutres et 8 spawns d'équipe.
6. **Art.** Le monde est zoné par camp, comme le RED/BLU de TF2 et les biomes de Fracture :
   - ouest froid (tôle bleue, crème) ;
   - centre neutre (béton, ocre de chantier) ;
   - est chaud (rouille, rouge GAS).

   Le sol se tait (C ≤ 0,10) et la piste est plus sombre que les murs. Les 5 repères de rang 1 se découpent sur un horizon clair.
7. **Repères.** Les treillis Tripo ont échoué : grue coupée à 3,15 m, derrick à 0,92 m, château d'eau facetté. On les refait en **bpy procédural (0 crédit)**. On garde les 3 sorties Tripo exploitables : l'auvent, le panneau FUEL et les cuves.
8. **Tripo.** Une vague de 11 générations de volumes pleins (épaves, industrie, roches) coûte **1 320 cr**, soit 1 520 cr avec la réserve de 15 %. Il reste environ 6 800 cr sur 8 320.
9. **Données bots à ajouter.**
   - Hotspots par lane.
   - Points de tenue et entrées par zone HP.
   - Liens de navigation pour les sauts et les chutes.
   - Tracés de lanes.
   - Callouts exposés.
   - Banc bots dédié à Wasteland.
10. **Plan.** 8 tâches LD-2x et 9 tâches ART-7x, en 6 vagues, chacune avec ses fichiers propres, des critères mesurables et des captures imposées (§f).

---

## (a) Constats de recherche : pratique → source → chiffre

Conversions TF2 et CS : 1 u = 2,54 cm (échelle monde, déjà retenue en `03`). L'échelle joueur de 1 u = 1,905 cm donne des distances 25 % plus courtes ; les deux sont indiquées quand ça change la décision.
Les mentions « extrait » signalent des pages qui ont refusé la lecture directe (403 ou 402) : le chiffre vient de l'extrait de recherche.

| # | Pratique | Chiffre | Source | Pour Wasteland |
|---|---|---|---|---|
| R1 | Trois lanes ; chaque lane a une raison d'être ; une position forte dans une lane appelle son équivalent en face ; aucune position ne domine toute la carte | 3 lanes (2 latérales + centre) | [Treyarch BO7, Xbox Wire](https://news.xbox.com/en-us/2025/10/27/how-treyarch-crafts-multiplayer-maps-call-of-duty-black-ops-7/) | Crête / Grand-Rue / Ravin ; FUEL ↔ GAS et Château d'eau ↔ Derrick se répondent |
| R2 | Pas plus de 3 décisions de navigation | 3 lanes max | [Super Jump, trois lanes CoD](https://medium.com/super-jump/why-have-three-lane-maps-endured-in-call-of-duty-9d3d2837efc9) (extrait) | Pas de 4ᵉ couloir |
| R3 | Chokes répartis, environ un par lane | 3–4 chokes par carte | [LDB — Balance](https://book.leveldesignbook.com/process/combat/balance) | 1 choke par lane + la place de la Grue |
| R4 | Une position défendable a au moins 3 entrées : on en couvre une, voire deux, jamais trois | ≥ 3 | [Game Developer, Architecture of flow](https://www.gamedeveloper.com/design/deathmatch-map-design-the-architecture-of-flow) | Aujourd'hui, pont de grue : 1 accès ; butte du derrick : 2 |
| R5 | La position centrale « Overshield » de The Pit | 3 accès | [Halo Wiki — The Pit](https://halo.fandom.com/wiki/The_Pit) | Même règle pour la Grue |
| R6 | Environ 3 fronts de combat et 3 entrées par objectif en 5v5 ; Dust2 ≈ 4000 × 4000 u | 3 ; ≈ 100 m (≈ 76 m à l'échelle joueur) | [Guide CS communautaire](https://steamcommunity.com/sharedfiles/filedetails/?id=1110438811) (extrait) | 80 × 43 m, c'est déjà serré : pas de 4ᵉ lane |
| R7 | Bandes de portée TF2 | ≤ 256 / 1024 / 2048 u, soit 6,5 / 26 / 52 m (4,9 / 19,5 / 39 m à l'échelle joueur) | [LDB — Metrics](https://book.leveldesignbook.com/process/blockout/metrics) | Au sol : intérieurs ≤ 8 m, lanes ≤ 25–30 m, ≤ 2 lignes longues de 45–52 m, en hauteur uniquement |
| R8 | Hauteurs de couvert (Uncharted 4, E. Schatz) | haut ≥ 1,75 m ; bas 1,0–1,25 m ; pas un couvert ≤ 0,5 m | [LDB — Cover](https://book.leveldesignbook.com/process/combat/cover) | Nos classes : 1,1 m (accroupi) et ≥ 2,0 m ; 1,4 m déclaré, « tête seule » |
| R9 | En PvP, peu de couvert vaut mieux que trop : le couvert haut et large crée des labyrinthes | qualitatif | [LDB — Balance](https://book.leveldesignbook.com/process/combat/balance), [LDB — Cover](https://book.leveldesignbook.com/process/combat/cover) | Le nombre de couverts plafonne par zone (§d.5) |
| R10 | Détail visuel uniquement sous 0,3 m et au-dessus de 2,7 m (Ascent) | 0,3 / 2,7 m | [The Spike, design d'Ascent](https://www.thespike.gg/valorant/news/the-design-behind-ascent-explained/317) | Bande 0,3–2,7 m réservée aux couverts normés et aux corps |
| R11 | Détails au-dessus de la hauteur du joueur ; valeurs voisines entre matériaux, pas d'intérieurs sombres ; un conteneur jaune sert de callout ; instanciation | qualitatif | [Riot — Art of VALORANT map environments](https://playvalorant.com/en-us/news/dev/the-art-of-valorant-map-environments/) | Décor en hauteur, intérieurs L ≥ 0,35, une couleur-callout par zone, MultiMesh |
| R12 | Castillo : sol plus sombre que les murs, murs peu bruités ; un repère unique n'est utilisé qu'une fois ; on réserve la saturation ; Cache a gagné en lisibilité en devenant plus clair et moins contrasté | qualitatif | [LDB — Environment art](https://book.leveldesignbook.com/process/env-art) | Piste plus sombre que les façades ; un modèle de repère = une seule instance |
| R13 | Fracture : biome chaud / biome froid pour retenir les callouts ; rotation sûre pour les défenseurs | 2 biomes | [Riot — Controlled Ruptures](https://playvalorant.com/en-us/news/dev/controlled-ruptures-making-valorant-s-fracture/) | Ouest froid (FUEL), est chaud (GAS), centre neutre |
| R14 | Un repère par district | 1 par zone | [Riot — Creation of Split](https://playvalorant.com/en-us/news/dev/the-creation-of-split/) | 1 repère de rang 1 ou 2 par callout majeur |
| R15 | Un repère derrière chaque base (falaise, littoral) ; l'orientation au spawn guide le trafic ; pas de zones mortes | qualitatif | [Game Developer](https://www.gamedeveloper.com/design/deathmatch-map-design-the-architecture-of-flow) | Mesa derrière le bleu, raffinerie derrière le rouge ; le `look` des spawns vise les lanes |
| R16 | Halo 3 : nombre de points de spawn | 4v4 Slayer 40 min / 55–60 optimal ; 4v4 objectif 50 / 70 ; score 1000, ±500 selon allié ou ennemi proche, −700 sur une mort récente (+100/s), fenêtre de 7 s | [FyreWulff, spawns Halo 3](https://halo.bungie.org/misc/fyrewulff_spawnsystem/) | Carte 4× plus petite qu'une carte Halo : 24 neutres + 8 d'équipe, notés par LD-02 |
| R17 | Halo 1 : un spawn se bloque à ≤ 3 m ; risque croissant dès 15 m | 3 m / 15 m | [c20 Reclaimers](https://c20.reclaimers.net/h1/guides/multiplayer/player-spawns/) | Anti-empilement : ≥ 3 m entre spawns simultanés |
| R18 | Hardpoint CoD : zone active 60 s, 5 zones par carte dans un ordre fixe (P1–P5) | 60 s ; 5 | [Guide CoD BO6 Hardpoint](https://www.callofduty.com/guides/blackops6/modes/call-of-duty-guides-black-ops-6-multiplayer-mode-guide-hardpoint), [Dot Esports](https://dotesports.com/call-of-duty/news/all-mw3-hardpoint-rotations) (extraits) | 3 zones demandées (carte 4v4, 80 × 43 m) ; on garde 60 s |
| R19 | La zone suivante est annoncée 10 s avant | 10 s | [CoD Esports Wiki](https://cod-esports.fandom.com/wiki/Game_Modes/Hardpoint) (extrait) | Préavis 10 s (LD-25) |
| R20 | Callouts d'objets courts, 1–2 syllabes | ≤ 2 syllabes | [Dot Esports, callouts Valorant](https://dotesports.com/valorant/news/all-callouts-in-valorant) (extrait) | Grue, Bus, Ravin, Cuves… (≤ 14 caractères, LD-04) |
| R21 | Orientation : une barrière dure est quasi certaine, la composition l'est peu ; le joueur ne lève pas les yeux sans y être invité | ≈ 98 % contre ≈ 35 % | [LDB — Wayfinding](https://book.leveldesignbook.com/process/blockout/wayfinding) | Repères au-dessus des toits, découpés sur l'horizon clair |
| R22 | Carte asymétrique jouée en Slayer 4v4 | Guardian (Halo 3) | [Halo Wiki — Guardian](https://halo.fandom.com/wiki/Guardian_(level)) | L'asymétrie est tenable si les positions fortes se répondent (R1) |
| R23 | Points de passage d'IA tous les 2 m environ, plus serrés près des couverts ; table de ligne de tir précalculée | ≈ 2 m | [Straatman, IA de Killzone](http://cse.unl.edu/~choueiry/Documents/straatman_remco_killzone_ai.pdf) | `BotSpots` (pas de 2 m) existe mais n'est lu par personne |
| R24 | Liens de navigation pour les sauts et les chutes | — | [Epic — Nav Link Proxy](https://dev.epicgames.com/documentation/en-us/unreal-engine/automatic-navigation-link-generation) | `NavigationLink3D` pour les toits, la dune, la butte et le Ravin |
| R25 | Bots de Halo Infinite : patrouille sur routes prédéfinies (tier 2), puis combat agressif | routes | [Game Informer](https://gameinformer.com/preview/2021/11/15/how-halo-infinites-bots-became-so-ruthless-and-helped-343-develop-multiplayer) | Hotspots et tracés de lanes (LD-24) |
| R26 | Borderlands 3 : l'encre est un filtre de Sobel en post-process ; l'ombrage hachuré a été réduit en jeu | qualitatif | [Cook & Becker, Scott Kester](https://www.cookandbecker.com/en/article/224/borderlands-3-art-director-scott-kester-on-communicating-an-attitude.html) | Notre `ink_edges` + `InkPost` va dans le même sens ; pas de hachures au sol |
| R27 | TF2 : monde terne avec de petites zones saturées ; ombres froides, pas noires ; RED chaud et bois, BLU froid et industriel | qualitatif | [TF2 Wiki, Illustrative Rendering (NPAR 2007)](https://wiki.teamfortress.com/wiki/Illustrative_Rendering_in_Team_Fortress_2) | Ombre teintée `#5B6CA6` ; architecture par camp |
| R28 | Sable : brouillard clé de la lisibilité à distance ; encre qui s'efface avec la distance ; forme claire sur fond sombre | qualitatif | [Game Developer, Sable](https://www.gamedeveloper.com/marketing/how-shedworks-refined-the-art-of-sable-in-pursuit-of-readability) | Brouillard de la bible §6.3 gardé ; coulisses voilées |
| R29 | Fortnite : rien de plus petit qu'une boîte aux lettres ; silhouettes massives ; pas de lignes parallèles | ≈ 0,4 m min | [GDC 2018 Fortnite](https://www.gdcvault.com/play/1024936/Developing-the-Art-of-Fortnite), résumé [Habrador](https://blog.habrador.com/2018/08/stylized-graphics-fortnite-sea-of-thieves.html) | Pas de miettes ; gravats de 10–40 cm (bible §6.1) |
| R30 | Overwatch : quand les joueurs vont partout, le travail devient de contenir la verticalité | qualitatif | [Game Developer, Overwatch maps](https://www.gamedeveloper.com/design/the-challenge-of-designing-i-overwatch-i-maps-when-players-can-get-literally-everywhere-) | Toits atteignables seulement là où c'est voulu ; les autres restent hors d'atteinte ou sont fermés |

**Ce que la recherche ne donne pas (hypothèses de ce document) :**
- espacement des couverts : aucune source ne chiffre un rythme, d'où les règles de §c.8 ;
- temps jusqu'au premier contact : l'étude CoG 2019 (« ≤ 10 s jusqu'au combat, ≤ 20 s pour traverser ») n'a pas pu être relue ;
- valeurs numériques par plan : on garde celles de la bible §6.2.

---

## (b) Audit de la Wasteland actuelle

### b.1 Layout

| # | Problème | Preuve | Gravité |
|---|---|---|---|
| L1 | Ni `tdm_spawns`, ni `callouts`, ni `strong_positions` : en TDM et en Hardpoint, 4 spawns fixes par équipe à x ±36,5–38,5 | `wasteland.gd` l.204–248 ; `MapSetup.gd` l.305–307 (« absent des… wasteland ») ; LD-03 ne visait que `Layouts.gd` ; LD-04B est « prête » dans le backlog mais n'est pas livrée | Bloquant |
| L2 | Empilement : au début du match, les 4 joueurs de chaque équipe apparaissent sur **le même** point, (−36,5 ; 1 ; −1) et (36,5 ; 1 ; −1) | Télémétrie `session_1790280280.jsonl` (bot_smoke du 24/09) | Bloquant |
| L3 | Hardpoint : 4 zones dans une boîte centrale de 26 × 17 m ; Épaves (0,7) et Hangar (13,7) sont à 13 m, soit 3 m entre deux zones de 10 × 10 ; rotations de 13 à 21 m (1,6–2,6 s au sprint) : pas de vraie rotation ni de bascule de spawn | `wasteland.gd` l.236 ; `MapSetup.gd` l.375 (`hp_size` 10 × 4 × 10) | Majeur |
| L4 | Ville plate : 9 bâtiments sur 10 font 3,2 m, seul FuelHouse fait 6,4 m. La planche montre des blocs de 2–3 étages serrés qui cadrent la rue | Extraction des `building2` ; `wasteland_sheet.png` | Majeur |
| L5 | La Grand-Rue est une droite est-ouest (z −3,5 à 3) sans chicane. Le test des lignes de vue (`test_sightline_caps_x_32_z_30`) compte chaque escalier comme un bloc plein, alors que ses marches sont ajourées et que sa moitié basse passe sous l'œil. Au sol, la rangée z ≈ −3,2 à −4,3 laisse une ligne d'environ **57 m** une fois les escaliers retirés | `Kit.piece_blocks_sight` (l.724) ; tramage à 0,5 m des boîtes de `wasteland.gd` | Majeur |
| L6 | Les positions fortes ont trop peu d'accès : pont de grue 1 escalier, butte du derrick 2, toit FUEL 1 rampe intérieure + 1 planche. La règle R4 en demande ≥ 3 | `maps-spec-v2.md` §5, « Power positions » | Majeur |
| L7 | Bande sud z 11,5–18 : ruban de sable de 80 m presque vide entre les rochers, zone morte (R15) ; aucune verticalité négative | Aériennes SE et SW | Moyen |
| L8 | Le spawn rouge regarde un mur. Les 4 `look` rouges visent (33 ; 1 ; 1), à 3–5 m, entre deux cuves ; la capture `spawn_rouge` ne montre qu'un aplat de falaise orange | `wasteland.gd` l.210–215 ; `wasteland_spawn_rouge.png` | Moyen |
| L9 | Les parités sont mesurées à vol d'oiseau (§5.6.3 du spec) et la ligne de vue est testée en 2D sans hauteur | `test_wasteland.gd` l.149–153 et 234 | Moyen |
| L10 | Boîte de rocher à 1,5 m sous la dune : la capture `route_secondaire` est prise **dans** la roche (image 100 % orange). Aucune preuve visuelle de la lane nord | `tools/map_shots.gd` l.265 ; `wasteland_route_secondaire.png` | Moyen, bloque la revue |

### b.2 Visuel

Mesures OKLab faites sur le tiers bas des vues, hors HUD. Référence : bible §6.1–6.7.

| # | Problème | Preuve | Règle violée |
|---|---|---|---|
| V1 | Sol orange saturé et uniforme : médiane C 0,14–0,15, teinte 46–47°. Le jeton `#D2A46C` vaut C 0,09 et 71°. Pas de piste, pas de traces ; texture floue et étirée | `centre_map` et `spawn_rouge` : L 0,69, C 0,141–0,150 ; style_check CHK-04/05 FAIL | §6.1 (sol ≤ 0,10), CHK-04 |
| V2 | Les falaises sont des boîtes de 6 m peintes du même `sand_dirt` que le sol, sans aucun écart de valeur : la carte se lit comme un bac à sable | Aériennes ; palette `rock_kind: sand_dirt` l.230 | §6.7.3 (ΔL ≥ 25 %) |
| V3 | La carte flotte : dalle dans un vide gris. Les coulisses sont un anneau bleu-gris pâle à pointes pyramidales, avec des poteaux blancs, qui fait chapiteau ; aucune mesa | `aerial_*.png`, `point_haut.png` ; `Backdrop.gd` (mur à 170 m, formes « box » ou « pyramid ») | §6.3 « plus aucune vue où la carte flotte » |
| V4 | Le bleu est partout : `cover_kind: corrugated_metal` rend chaque pièce `cover` (CraneShed, Warehouse, caisses, cuves) en tôle bleue saturée, y compris côté rouge. Le bleu FUEL ne désigne plus le camp bleu | `top.png`, `centre_map.png` ; palette l.229 | §6.7.2 (repère de camp) |
| V5 | Repères noirs : l'accent `#4A4640` (L 0,40, C 0,01) couvre le château d'eau, le mât de grue (monolithe 1,6 × 16 × 1,6), l'auvent et le derrick. `crane_lattice` est aliasé vers le portique de Port-Ferraille | `aerial_se.png` ; `PropCatalog.ALIASES` l.48 | §6.5 (repère = couleur la plus saturée) |
| V6 | Skins sans modèle, donc des boîtes : `canopy_station`, `tank_horizontal`, `tank_skid` et `bus_wreck` n'ont aucun `.glb`. L'auvent devient une « table » noire, les cuves des blocs. Les 7 repères Tripo générés ne sont pas branchés : aucune entrée `wl_*` dans `manifest.json` | `PropCatalog.gd` l.53–57 ; `spawn_bleu.png` | §6.5 |
| V7 | Les escaliers sont des planches qui flottent : marches de 8 cm sans limon ni contremarche, au-dessus d'une rampe de collision invisible | `Kit._ramp_with_treads` l.135–149 ; `centre_map`, `point_haut`, aériennes | §3.2 du plan d'assets (le visuel épouse la collision) |
| V8 | Façades posées au jugé, sans convention d'orientation : volumes doublés. Dans `point_haut`, la façade en bois dépasse du toit du Réservoir. L'adobe sort en béton blanc marbré | `wasteland.gd` l.146–175 (« à confirmer en image ») | §6.1 |
| V9 | Les boîtes de zone translucides (Hardpoint, sites A et B) sont visibles en TDM | `point_haut.png` ; `MapSetup._build_markers` l.352–398, qui construit toutes les zones quel que soit le mode | Lisibilité |
| V10 | Nuages : bouffées floues sous 6°, devant la ligne des toits | `centre_map.png`, `spawn_bleu.png` | §6.3 et §6.7.4 |
| V11 | Densité faible et mécanique : environ 57 instances de décor (32 entrées `prop`) pour environ 3 400 m², avec une rangée de fouillis alignée sur z ±3. Aucun pochoir ni décalque, aucune enseigne lisible (FUEL et GAS sans texte) | `wasteland.gd` l.182–199 | R11, R12, bible §6.1 |
| V12 | Le soleil a un azimut diagonal fixe, commun aux 8 cartes (X = Z) : il est au nord-ouest, à 45° des lanes est-ouest. Les rouges sortent de spawn à contre-jour | `LevelLook._sun_direction` l.137 | §6.3 (60–90° des lanes) |
| V13 | Vues de revue peu exploitables : `route_secondaire` est prise dans la roche ; en `top`, la carte occupe environ 13 % de l'image ; le HUD est incrusté partout | `map_shots/` | Revue |
| V14 | *Hors carte :* l'arme en vue FP est un bâton de bois | `centre_map.png` | À signaler |

### b.3 Repères Tripo déjà générés (`assets/incoming/tripo/restyled/`)

| Asset | G2 | État observé (planche ou turntable) | Décision |
|---|---|---|---|
| `wl_canopy_station` | PASS | Toit plat, bandeau, 4 poteaux ; générique, se lit comme une table | **Garder** ; ajouter le bandeau FUEL en décalque (ART-72) |
| `wl_fuel_billboard` | PASS | Dalle bleue pleine, soubassement dentelé | **Garder** comme bouclier de spawn ; le texte FUEL passe en décalque |
| `wl_tank_horizontal` | PENDING | Cuve lisible ; bbox à −8,4 % | **Garder**, recalée à l'échelle 1,09 (plage 0,8–1,25) |
| `wl_gas_billboard` | PENDING | La ferme a disparu, il reste une planche | Refaire en bpy (ferme + panneau) |
| `wl_water_tower` | PENDING | Triangulation en éventail facettée, pieds cassés en éclats | Refaire en bpy |
| `wl_oil_derrick` | PENDING | Amputé à 0,92 m au lieu de 10 m : seule la poulie survit | Refaire en bpy |
| `wl_crane_lattice` | FAIL | Flèche seule, 3,15 m au lieu de 16 m, 2 046 arêtes non-manifold | Refaire en bpy |

**Leçon.** Tripo échoue sur les treillis ouverts : les îlots disjoints sont jetés par `ai_restyle`, conformément à CHK-16. Il réussit les volumes pleins. Le budget Tripo va donc aux volumes pleins, et bpy fait les treillis (§d.4).

### b.4 Bots sur cette carte

**Mesures (bot_smoke, 4v4, TDM, 24/09) :**

| Carte | Durée | time_scale | Kills |
|---|---|---|---|
| Wasteland | 120 s | 1 | 0 |
| Wasteland | 240 s | 3 | 0 |
| Cargo Ship (contrôle) | 120 s | 1 | 0 |
| Cargo Ship (contrôle) | 240 s | 3 | 0 |
| Cargo Ship (revue de 16 h 43) | 120 s | 1 | 24 |

`rejected_shots` vaut 0 partout, donc aucun tir n'a été tenté. **Régression globale des bots depuis 16 h 43, hors périmètre de la carte**, à corriger en premier : sans elle, aucune mesure de carte ne vaut.

**Défauts propres à Wasteland** (lecture du code, confirmée par la télémétrie) :
- **Patrouille TDM = marqueurs de spawn.** `GameMode._map_patrol_points` (l.290) lit `SpawnPoints` ; sur Wasteland, ce sont 8 points collés deux à deux aux extrémités. Un bot sans mémoire d'ennemi va vers le point le plus proche, c'est-à-dire un voisin de son propre spawn : il tourne dans sa base.
- **Hardpoint.** Le but du bot est le **centre** de la zone (`HardpointMode._compute_bot_goal`, l.141) : tous les bots convergent au même mètre carré, sans point de tenue ni entrée.
- **`BotSpots` est baké mais inutilisé.** `resources/bot_spots/wasteland.tres` existe, `GameWorld` le charge (l.171), mais `BotBrain` ne le lit jamais (BOT-06 non livré).
- **Aucun `NavigationLink3D`.** Chutes de toit, plongeon Réservoir → hangar et descente de la butte sont invisibles pour la navigation : les bots n'utilisent jamais la verticalité, sauf par les escaliers.

---

## (c) Design cible

### c.1 Thèse

« Un relais pétrolier grandi en bidonville ». Le bleu (FUEL) tient l'ouest froid, le rouge (GAS) l'est chaud. Au centre, un chantier neutre dominé par la grue.

On lit la carte à trois hauteurs :
- le **Ravin**, en contrebas ;
- la **rue** ;
- les **toits et crêtes**.

On lit aussi trois lanes, et un repère par quartier. Chaque combat se décide sur une position forte qui a toujours une contre-route.

### c.2 Plan (grille indicative de 2 m par case ; les coordonnées exactes sont en c.3 et c.5)

```
x:   -40       -30       -20       -10        0        10        20        30       40
z -25 ###################BB#####XXXXXXX#######     NORD
z -23 ###################BB.....XXXXxxX.######
z -21 ###################BB.....XXXXxx^^^^####     La Crête : Bus -> butte du Derrick
z -19 ###################BB.....XXXXXX^^^^####
z -17 #######............BB.....^^^.......####
z -15 .....ddddDDDDdddddd.x.....^^^.......####     Dune (3,2) -> glissade 15°
z -13 .P...ddddDDDDdddddd.CCSS..^^^.......####
z -11 ...FFFF..GGGGRRR....CCSS..^^^..OOOO.####
z  -9 ...FFFF..GGGGRRR....2SSS..^^^..OOOO.MM..
z  -7 ...FFFF..GGGGRRR....SSSS..^^LL.OOOOTMM..
z  -5 bbb.........................LL.....TMrrr
z  -3 bbb===tttt.....KK......=====LL=====TTrrr     La Grand-Rue (=) : 3 coudes
z  -1 bbb===tttt=====KK=.....=====LL=====TTrrr
z   1 bbb......====1=KK=======....LL.....TTrrr
z   3 bbbHHHH..AAAA....=======VVVVV......TTrrr
z   5 ...HHHH..AAAA......eeee.VVV3V.YYYY.TT...
z   7 ...HHHH..AAAA......eeee.VVVVV.YYYY......
z   9 ......vv........vv....vv.....vv.vv......     connecteurs rue <-> Ravin (v)
z  11 ......vv~~~~~~~~vvooo~vv~~~~~vv~vv......     Le Ravin (~) à y -1,2
z  13 ######~~~~~~~~~~~~ooo~~~~~~~~~~~~#######
z  15 ########################################     SUD
```

Légende :
- **Bords** : `#` falaise ou massif (non praticable, habillé de roches à strates).
- **Sol** : `.` sable, `=` piste de la Grand-Rue, `~` Ravin (−1,2 m), `o` rochers-couverts du Ravin, `v` rampes et connecteurs.
- **Camp bleu (ouest)** :
  - `b` spawn bleu ;
  - `P` pylône FUEL (repère de spawn) ;
  - `F` maison FUEL (2 étages, toit 6,4) ;
  - `G` garage (toit 3,2) ;
  - `H` baraque ;
  - `A` auvent et pompes ;
  - `t` épave de citerne.
- **Relief nord** : `D` et `d` dune (3,2 m) avec ses rampes.
- **Centre** :
  - `R` Réservoir et château d'eau ;
  - `K` chapelle ;
  - `S` hangar de la grue (toit 3,2), `C` pont de grue (5,6), `x` pied de la grue ;
  - `B` bus ;
  - `e` épaves.
- **Camp rouge (est)** :
  - `X` butte du derrick (4,5), `x` derrick, `^` rampes et escaliers ;
  - `L` saloon (ex-WestBlock) ;
  - `V` hangar ;
  - `Y` bloc sud ;
  - `O` bureau GAS (2 étages, toit 6,4, panneau GAS) ;
  - `T` cuves, `M` collecteur ;
  - `r` spawn rouge.
- **Hardpoint** : `1`, `2`, `3` = centres des zones A, B, C.

### c.3 Lanes, connecteurs, positions fortes

**Lanes (ouest → est) :**

| Lane | Tracé | Portée au sol | Rôle |
|---|---|---|---|
| **Crête** (nord) | FUEL → montée de dune → dune (3,2) → glissade → chemin du Bus (z −23 à −15) → pied de la butte → butte du Derrick (4,5) | segments ≤ 30 m (Ravage, Marqueur) | Moyenne et longue portée, hauteur |
| **Grand-Rue** (centre) | Place FUEL → citerne → coude 1 (place de la Chapelle) → coude 2 (Épaves / Grue) → coude 3 (Saloon) → cour GAS | ≤ 25 m entre coudes ; au sol, aucune ligne > 30 m | Contact principal, Rafale et Ravage |
| **Ravin** (sud) | Arrière de la baraque → Ravin (y −1,2, 5 m de large) → rochers et buses → quai du Hangar → arrière du bloc sud | ≤ 18 m par segment | Courte portée, Fracas, flanc |

**Connecteurs.** Il y a 3 connecteurs Crête ↔ Rue, au garage, au hangar de la grue et au saloon, et 5 connecteurs Rue ↔ Ravin (`v`). Aucune lane ne reste isolée plus de 25 m.

**Positions fortes.** Au moins 3 accès chacune, dont 1 invisible depuis la position :

| # | Position | Hauteur | Camp | Accès cibles |
|---|---|---|---|---|
| PF1 | Toit FUEL | 6,4 | bleu, domicile | escalier intérieur, planche depuis le garage, **échelle extérieure sud (nouvelle)** |
| PF2 | Toit du Réservoir, pied du château d'eau | 3,2 | bleu, avancée | escalier sud, **échelle ouest (nouvelle)**, saut depuis la dune |
| PF3 | Pont de grue | 5,6 | neutre | escalier est, **échelle ouest (nouvelle)**, plongeon depuis le Réservoir sur le toit du hangar, escalier sud du hangar |
| PF4 | Butte du Derrick | 4,5 | rouge, avancée | rampe de glissade, escalier est, **rochers-marches ouest depuis le chemin du Bus (nouveau)** |
| PF5 | Toit du bureau GAS | 6,4 (**monté d'un étage**) | rouge, domicile | escalier intérieur, escalier extérieur, **passerelle depuis les cuves (nouvelle)** |

**Équilibre de hauteur.** Indice Σ(aire × h ≥ 2,5 m), écart ≤ 10 %.
- Aujourd'hui, avec GAS à 6,4 m, le rouge monterait à environ 656 contre 522 pour le bleu (+26 %).
- **Correctif** : réduire le plateau du derrick de 12 × 8 à 8 × 8 m. Le reste devient roche-décor non praticable. Le rouge revient à environ 512 contre 522 (2 %).

**Lignes longues déclarées** (seules lignes ≥ 45 m, en hauteur uniquement) :
- toit FUEL ↔ butte du Derrick, environ 51 m ;
- toit GAS ↔ sommet de la dune, environ 44–46 m.

La cuve du château d'eau coupe volontairement la ligne toit FUEL ↔ toit GAS (56 m).

### c.4 Spawns TDM et Hardpoint

**Points :**
- 8 spawns d'équipe (4 + 4) gardés pour le Litige et l'échange de côté. Les `look` sont corrigés pour viser l'entrée des lanes : la Grand-Rue et le Ravin, jamais un mur à moins de 8 m.
- **24 `tdm_spawns` neutres** :
  - 6 par « domicile » (place FUEL, cour GAS) ;
  - 12 en bordure des lanes, soit 2 par lane et par moitié ;
  - 4 dans les angles (arrière de la baraque, arrière du bloc sud, pied nord de la dune, arrière des cuves) ;
  - chaque point a un `look` vers la lane la plus proche.

**Règles de choix** (LD-02 existant, complété par LD-23) :
- **Sécurité.** Jamais à ≤ 30 m **et** en ligne de vue d'un ennemi vivant ; jamais à ≤ 12 m d'un ennemi.
- **Anti-empilement.** ≥ 3 m entre deux spawns de la même seconde (R17).
- **Hardpoint.** Jamais dans la zone active, ni à ≤ 15 m d'elle, ni en ligne de vue d'elle à ≤ 25 m. Bonus du côté opposé à la zone qui monte : c'est la bascule CoD.
- **Échange de côté** (spec §5.6.2) inchangé : les spawns domicile suivent le côté.

### c.5 Hardpoint : 3 zones

| Zone | Callout | Centre | Emprise | Distance (bleu / rouge, à vol d'oiseau) | Entrées (≥ 3, dont 1 verticale) |
|---|---|---|---|---|---|
| **A** | Chapelle | (−13 ; 0 ; 1) | 9 × 4 × 9 | 24,0 / 50,0 | Grand-Rue ouest, Grand-Rue est, connecteur du Ravin, escalier du Réservoir (vertical) |
| **B** | Grue | (0,5 ; 0–6,7 ; −8,5) | 9 × 7 × 9, trois niveaux : hangar, toit, pont | 38,4 / 37,5 (2,5 %) | porte sud du hangar, porte est, escalier sud, échelle ouest du pont, plongeon depuis le Réservoir |
| **C** | Hangar | (14 ; 0 ; 6) | 10 × 4 × 8 | 51,4 / 23,8 | portes ouest, est et nord, quai du Ravin (vertical, −1,2) |

**Parité et ordre :**
- La parité miroir A ↔ C tient : 24,0 contre 23,8 m, soit 1 %.
- Ordre : **B → A → C → B…** On ouvre au neutre, puis la rotation traverse une fois la carte (A → C, environ 28 m à vol d'oiseau), ce qui force une bascule de spawn par cycle.
- 60 s par zone (R18), préavis de 10 s (R19).

**Contenu de chaque zone :** 2–3 couverts de 1,1 m, 1 couvert ≥ 2,0 m, et aucun point de la zone vu en entier depuis une seule entrée.

**Rotations cibles (navmesh, sprint 8,2 m/s) :**

| Rotation | Durée | Distance |
|---|---|---|
| B → A | 2,5–4 s | ≈ 22 m |
| A → C | 4–6 s | ≈ 35 m |
| C → B | 2,5–4 s | ≈ 24 m |

La zone Épaves disparaît : elle collait au Hangar (L3).

### c.6 Callouts (14, ≤ 14 caractères, uniques)

| Callouts | Repère ou ancre visuelle |
|---|---|
| Station FUEL, Auvent, Garage | pylône FUEL, auvent bleu, rideau du garage |
| Dune | crête de sable, poteaux |
| Château d'eau, Chapelle | cuve crème à bande bleue ; clocher-arche |
| Grand-Rue | piste, enseignes de façade |
| Grue, Bus, Épaves | grue ocre-orange, bus, épaves |
| Hangar | pochoir « HANGAR 2 » |
| Derrick, Cour GAS, Cuves | derrick rouille, panneau GAS, cuves |
| Ravin | éolienne de pompage, lit à sec |

**Couverture :** ≥ 95 % des polygones du navmesh dans une zone (règle LD-04). Chaque callout porte **au sol ou au mur** un pochoir de son nom, dans l'atlas de décalques à 512 px/m.

### c.7 Métriques cibles

| Mesure | Cible | Mesuré comment |
|---|---|---|
| Premier contact spawn → Grand-Rue centre (navmesh, sprint) | 5–7 s par camp, écart ≤ 8 % | test navmesh (LD-20) |
| Traversée spawn bleu → spawn rouge (navmesh) | ≤ 14 s | idem |
| Ligne de vue au sol, dans chaque lane, **à hauteur d'œil 1,6 m, raycast 3D** | Crête ≤ 30 m, Rue ≤ 30 m, Ravin ≤ 18 m, intérieurs ≤ 8 m | nouveau test 3D (LD-20), à la place du test 2D optimiste (L5) |
| Lignes ≥ 45 m | ≤ 2, déclarées, en hauteur uniquement | idem |
| Accès par position forte | ≥ 3 portails navmesh distincts dans un rayon de 6 m | test radial (motif de `test_snd_timings.gd`) |
| Indice de hauteur Σ(aire × h) bleu / rouge | écart ≤ 10 % | `test_wasteland.gd` |
| Sol praticable à > 8 m d'un couvert (≥ 1,0 m) | ≤ 3 % | tramage à 0,5 m (déjà 0 % aujourd'hui, à garder) |
| Portion ouverte continue sans couvert à ≤ 3 m du chemin | ≤ 12 m (≈ 1,5 s de sprint) | tramage sur les tracés de lanes |
| Zones HP : parité A ↔ C, parité B | ≤ 10 % et ≤ 8 % (navmesh) | test |
| Spawns : `tdm_spawns` | 24 sur le navmesh ; aucun vu depuis une position forte adverse à ≤ 20 m | test (règle LD-03) |
| Callouts | 14 ; ≥ 95 % du navmesh couvert | test (règle LD-04) |
| Hauteur libre sur les routes de mouvement | ≥ 3,2 m (exceptions ≥ 2,4 m) | règle LD-06 |

### c.8 Règles couverts et verticalité

**Couverts :**
- Deux hauteurs seulement : 1,1 m et ≥ 2,0 m. Classe 1,4 m (« tête seule ») : 4 au plus, déclarées (épaves de berline).
- Décor 0,3–2,7 m interdit dans le cœur de lane (2,5 m au centre du tracé) (R10).
- Ni petit couvert isolé au milieu d'une place, ni labyrinthe de couverts hauts (R9).
- Un couvert tous les 8–12 m le long de chaque tracé. Dessus plus clair (+6 % L), ΔL couvert/sol ≥ 0,12.

**Verticalité** en 4 étages lisibles :

| Étage | Hauteur |
|---|---|
| Ravin | −1,2 |
| Rue | 0 |
| Toits et dune | 3,2 |
| Hauts | 4,5–6,4, plus le pont de grue à 5,6 |

- Un écart ≥ 2,5 m entre étages fait « hauteur » ; en dessous, on parle de marche.
- Toute descente > 3,2 m hors rampe coûte l'étourdissement existant, déjà réglé par le spec.
- Les toits non prévus sont hors d'atteinte : parapet ≥ 1,5 m ou pente > 46° (R30).

**Façades :**
- La silhouette monte par des **fausses façades** western de 5–7 m, décor au-dessus de 2,7 m, **sans changer les volumes jouables**.
- La skyline suit 5 paliers : 3,2 / 4,5 / 6,4 / 7 (fausses façades) / 12–18 m (repères).

---

## (d) Plan d'art

### d.1 Zonage couleur par quartier

**Règle** : une couleur saturée par objet (bible §6.1). On garde les teintes hors des bandes réservées. Les chromas sont en OKLCH.

| Quartier (callouts) | Humeur | Neutres | Accents, ≤ 2 par quartier | Repère |
|---|---|---|---|---|
| **Ouest** (Station FUEL, Auvent, Garage, Dune) | station-service propre, froide | bois `#9C6A42`, crème `#E6E1D6` (trims, L 0,91) | tôle `#4F7FA8` (C 0,08) ; FUEL `#3E7BB5` (C 0,11), **réservé au repère** | pylône FUEL + auvent |
| **Vieille ville** (Château d'eau, Chapelle) | adobe blanchi, calme | enduit `#D9C3A0` (L 0,83, C 0,05), béton `#B8AFA0` | volets sarcelle `#3FA3A0` (h 192°, C 0,09) | château d'eau crème à bande bleue |
| **Chantier** (Grue, Bus, Épaves, Grand-Rue) | neutre, poussière | béton `#B8AFA0`, piste | grue ocre-orange `#E3872A` (C 0,15, **nouveau jeton Wasteland**) | grue |
| **Est** (Hangar, Cour GAS, Cuves, Derrick) | raffinerie chaude | bois sombre `#7A6250`, tôle rouillée | rouille `#B5562A` (C 0,14) ; GAS `#B8322A` (C 0,17), **réservé au repère** | panneau GAS + derrick |
| **Ravin** | lit à sec, ombre | roche `#8C6B55` (L 0,56), strates `#A0715A` et `#B89A7A` | aucun | éolienne de pompage |

**Conséquences :**
- `cover_kind` n'est plus unique : la tôle bleue ne vit qu'à l'ouest, la tôle rouillée à l'est. Le rôle `cover` se décline par quartier, soit une clé de palette par quartier (ART-70).
- Plus de rouge GAS près de FUEL, ni de bleu FUEL près de GAS (bible §6.7.2).

### d.2 Structure de valeurs pour Wasteland

Bible §6.2, précisée pour cette carte.

| Plan | Couleur | L / C cibles | Aujourd'hui |
|---|---|---|---|
| Sable | `#D2A46C` | 0,75 / 0,09 | 0,69 / 0,14–0,15, teinte 46° |
| Piste de la Grand-Rue | `#BF8E5C` (au lieu de `#C58B4E`, C 0,105 > 0,10) | 0,68 / 0,09 : plus sombre que le sable et les façades (R12) | inexistante |
| Façades éclairées | enduit `#D9C3A0` ou crème | 0,80–0,85 | bois 0,55 et béton blanc marbré |
| Façades en bois (est) | `#7A6250` à `#9C6A42` | 0,52–0,57 | — |
| Falaises et roches | `#8C6B55` + strates | 0,52–0,60 / ≤ 0,07 ; ΔL ≥ 0,15 avec le sable | = sol |
| Ombres | teinte `#5B6CA6`, 35–45 % | 0,62–0,70 × L éclairé, jamais < 0,30 | à mesurer (CHK-02) |
| Intérieurs | remplissage | murs L ≥ 0,35 (R11) | sombres (spawn_bleu) |
| Horizon / zénith | `#BFDDF2` / `#2F74D8` | 0,82–0,93 / 0,52–0,65 | conforme |

### d.3 Repères : placement et source

| Rang | Repère | Position (x ; y ; z) | Hauteur totale | Couleur | Source |
|---|---|---|---|---|---|
| 1 | Grue à tour | pied (1,5 ; 0 ; −14,3), flèche vers l'est | 18 m | ocre-orange `#E3872A` + contrepoids béton | **bpy** (Tripo FAIL) ; la collision Kit (mât + pont) ne bouge pas |
| 1 | Derrick | (22 ; 4,5 ; −21) | 18,5 m | rouille + tête crème | **bpy** (Tripo amputé) ; pieds Kit gardés |
| 1 | Château d'eau | (−10,5 ; 3,2 ; −7,5) | 12 m | cuve crème, bande `#3E7BB5` | **bpy** (Tripo facetté) |
| 1 | Pylône FUEL | (−37 ; 0 ; −11,5) | 10 m | `#3E7BB5` + décalque FUEL | panneau Tripo PASS + mât bpy |
| 1 | Panneau GAS | toit GAS (26,5 ; 6,4 ; −7,5) | ≈ 10,5 m | `#B8322A` + décalque GAS | **bpy** (ferme) |
| 2 | Auvent | (−17,5 ; 0 ; 5,25) | 4,1 m | bandeau bleu + FUEL | Tripo PASS |
| 2 | Cuves ×2 + cuve sur châssis | (31,5 ; 0 ; −3 et 5), (27 ; 0 ; 1) | 3,5 m | rouille | Tripo PASS (échelle 1,09) + Tripo `tank_skid` |
| 2 | Bus | (1 ; 0 ; −20) | 3 m | crème et rouille | Tripo (vague ART-74) |
| 2 | Éolienne de pompage | Ravin (−18 ; −1,2 ; 13) | 9 m | tôle crème, pales rouille | **bpy** (treillis fin ≤ 0,15 m) |
| 2 | Clocher-arche de la chapelle | toit (−7,5 ; 3,2 ; 0) | 5,5 m | enduit + cloche | **bpy** |
| 3 | Pochoirs de callout, enseignes de façade | 1 à 3 par callout | — | encre et crème | atlas de décalques |

**Critère :** au moins 3 repères de rang 1 visibles au-dessus des toits depuis ≥ 70 % d'une grille de 4 m à 1,6 m (CHK-14). Chaque modèle de rang 1 n'est posé qu'une fois (R12).

### d.4 Assets manquants : Tripo ou Blender

Tarifs réels (`CREDITS.md`) : Smart Mesh 100 cr (4 variantes au même prix) + texture 20 cr = **120 cr par génération**. Les estimations de 45–65 cr de `ASSET_PLAN.md` §5 sont caduques.

**Vague Tripo « Wasteland volumes pleins » (ART-74) :**

| # | Asset | Couvert | Pourquoi Tripo | cr |
|---|---|---|---|---|
| 1 | `wl_bus_wreck` | ≥ 2,0 m (3 × 3 × 9) | forme organique, vitres condamnées | 120 |
| 2 | `wl_car_sedan_wreck` | 1,4 m | 4 variantes → berline et voiture bleue | 120 |
| 3 | `wl_car_pickup_wreck` | 1,8 m | plateau plein | 120 |
| 4 | `wl_tanker_wreck` | ≥ 2,0 m | crème et tôle, jamais rouge GAS | 120 |
| 5 | `wl_tank_skid` | ≥ 2,0 m | cuve sur châssis | 120 |
| 6 | `wl_pipe_manifold` | ≥ 2,0 m | bloc dense, jours ≤ 0,1 m | 120 |
| 7 | `wl_pump_jack` (nouveau) | décor sur la butte | silhouette iconique du désert | 120 |
| 8 | `wl_generator` (nouveau) | 1,1 m | couvert bas de la cour GAS | 120 |
| 9 | `wl_fuel_pump` | 1,6 m, tag `ok_not_humanoid` | sous l'auvent | 120 |
| 10 | `wl_rock_outcrop` | skin de falaise | 4 variantes de roches à strates | 120 |
| 11 | `wl_mesa_chunk` | décor de la jupe de terrain | 4 variantes, vues de 40 à 150 m | 120 |
| | **Total** | | | **1 320** |
| | Réserve de 15 % pour les reprises | | | 200 |
| | **Plafond de la vague** | | | **1 520** |

- **Porte de calibration** : on lit le coût réel du premier job et on s'arrête s'il dépasse 1,3 × 120 cr.
- **Solde** : 8 320 − 1 520 ≈ **6 800 cr** pour le reste du projet.

**Blender procédural, 0 crédit** (`tools/blender/`) :
- **Treillis** : grue, derrick, château d'eau, ferme du panneau GAS, mât du pylône FUEL, éolienne, clocher-arche (ART-72) ;
- **Kit « bidonville »** (ART-73) : fausses façades de 1 à 2 étages alignées sur les ouvertures Kit, bardages, tôles de toit ondulées, auvents, balcons, garde-corps ;
- **Escaliers et échelles avec limons et contremarches**, calés au centimètre sur la collision (ART-71, `Kit.gd`) ;
- **Jupe de terrain et coulisses** : dunes et silhouettes de mesas à 2–3 teintes (ART-75 et ART-76) ;
- **Décalques** : FUEL, GAS, pochoirs de callouts, traces de pneus, craquelures (atlas).

### d.5 Densité de props par zone

**Règles (R10, R11, R29) :**
- ≥ 70 % du décor au mur, en bord de lane ou au-dessus de 2,7 m ;
- aucun décor dans le cœur de lane ;
- rien de plus petit que 0,4 m hors décalques ;
- tout prop répété 3 fois ou plus passe en MultiMesh.

| Zone | Sol praticable approx. | Couverts (1,1 / ≥ 2,0) | Décor (instances) | Décalques |
|---|---|---|---|---|
| Station FUEL + Auvent + Garage | 450 m² | 4 / 3 | 35–45 | 4–5 |
| Dune + chemin du Bus | 300 m² | 2 / 2 (roches, bus) | 10–15 | 1–2 |
| Château d'eau + Chapelle | 350 m² | 3 / 3 | 30–40 | 3–4 |
| Chantier (Grue, Épaves, Grand-Rue centre) | 450 m² | 5 / 4 | 35–45 | 4–5 |
| Derrick | 250 m² | 2 / 2 | 15–20 | 1–2 |
| Hangar + Cour GAS + Cuves | 450 m² | 4 / 4 | 35–45 | 4–5 |
| Ravin | 300 m² | 3 / 3 (rochers, buses) | 15–20 | 2 |
| **Carte** | ≈ 2 550 m² | ≈ 45 | **≈ 190–230** (aujourd'hui ≈ 57) | 25–35 |

**Budget** (bible §6.6, Steam Deck) : ≤ 800 draw calls, ≤ 1,2 M triangles visibles, ≤ 24 matériaux. Pour la variété, on passe par les vertex colors et la teinte d'instance.

### d.6 Ciel, coulisses, lumière

**Soleil** : `#FFD99A`, 32° (tokens), **azimut propre à la carte**, venant du sud-sud-ouest (≈ 200°).
- Il fait 70° avec les lanes est-ouest : aucune équipe ne sort de spawn à contre-jour (V12).
- Les ombres des façades sud tracent des bandes d'ombre en travers de la rue, un rythme lisible.
- Il faut un paramètre d'azimut par carte dans `LevelLook` (ART-70).

**Rampe et ambiance** : bible §6.3 et §7.2 inchangées. Ombre à 0,62–0,70, teintée `#5B6CA6` à 35–45 %. Ciel à 0,18. SSAO de 0,8 m. Bounce sable à 0,12.
- **Intérieurs** : une lumière de remplissage sans ombre par bâtiment praticable, réglée pour que les murs restent à L ≥ 0,35.

**Coulisses en 3 couches** (ferment CHK-12 et suppriment le vide de V3) :
1. **Jupe de 40 à 150 m.** Dunes et chaos de roches éclairés, dans le même brouillard ; mesa-chunks Tripo et poteaux électriques qui s'éloignent au nord.
2. **Anneau à 170 m.** Mesas à strates, 2–3 teintes chaudes voilées : `backdrop_near` passe de bleu-gris pâle à ocre rosé voilé. Le profil « pyramides » est remplacé par des plateaux à flancs verticaux.
3. **Fond de 400 à 600 m.** Mesas pâles fondues dans l'horizon.

**Repères directionnels d'horizon** (R15) :
- à l'ouest, derrière le bleu : une grande mesa, « le Pouce », côté soleil couchant ;
- à l'est, derrière le rouge : une raffinerie avec 2 torchères et des cuves en silhouette ;
- au nord : une ligne de pylônes ;
- au sud : une mer de dunes et un panneau routier.

**Nuages** : 3 à 5 cumulus plats à deux tons par demi-ciel, **tous au-dessus de 6°** (V10).

---

## (e) Besoins des bots pour cette carte

**Préalable hors carte.** Il faut d'abord régler la régression « 0 tir » (§b.4), puis livrer BOT-06 (choix de position) et BOT-08 (équipe), déjà au backlog. Les données ci-dessous leur sont destinées. Elles sont **pures** (Dictionary et Vector3), testables sans moteur, et vivent dans un fichier propre à la carte.

| Donnée | Contenu | Usage bot | Critère |
|---|---|---|---|
| `lanes` | 3 polylignes (Crête, Rue, Ravin), 8–12 points chacune | affectation de lane par bot (répartition 1-2-1), stats de banc | chaque point est sur le navmesh ; les polylignes relient les deux spawns |
| `hotspots` | 12 points {pos, lane, poids, callout} : 3 par lane + PF2, PF3, PF4 | remplace les marqueurs de spawn comme points de patrouille TDM (L1) | ≥ 3 par lane ; aucun à ≤ 10 m d'un spawn |
| `strong_positions` | PF1 à PF5 {pos, accès[]} | tenue ou contestation ; le banc surveille la domination | ≥ 3 accès chacun |
| `hp_hold_points` | 5 points par zone {pos, facing, stance, entrées couvertes} | tenir la zone au lieu de s'agglutiner au centre | dans la zone ; couvert ≤ 2 m ; chaque entrée couverte par ≥ 1 point |
| `hp_entries` | 3–4 portails par zone {pos, lane} | approche par des routes différentes | ≥ 3 distincts |
| `nav_links` | chutes FUEL → place (6,4), garage → rue (3,2), dune → rue, butte → pied ouest (4,5), plongeon Réservoir → toit du hangar (8 m), montées du Ravin (1,2 m, saut 1,36 m) | les bots utilisent la verticalité et les flancs | chaque lien est franchi en simulation par un bot (test) |
| `danger_spans` | tronçons à forte exposition (Grand-Rue entre les coudes, plateau de la butte) | traverser au sprint, ne pas s'y arrêter | ≤ 6 tronçons |
| `callouts` | 14 AABB (§c.6), via `MapSetup.callout_at()` | annonces, fil de kills (« à la Grue ») | ≥ 95 % du navmesh |
| `bot_spots` | rebake de `resources/bot_spots/wasteland.tres` après LD-20 | couverture par direction (BOT-06) | bake ≤ 30 s ; ≥ 1 spot couvert à ≤ 10 m de 95 % des points navigables |

**Banc bots Wasteland** (LD-27), sur la base de `tools/bot_bench.gd` et de la télémétrie FUN-05 :
- TDM 4v4 Vétéran, 10 min : kills par minute ≥ 6 ;
- premier contact médian entre 5 et 9 s après le spawn ;
- temps bloqué ≤ 2 % ;
- chaque lane porte 20 à 45 % des traversées ;
- aucune position forte tenue plus de 35 % du temps par la même équipe ;
- < 5 % de morts dans les 3 s qui suivent un spawn ;
- Hardpoint : une zone occupée ≥ 70 % de chaque fenêtre de 60 s.

---

## (f) Tâches priorisées

**Captures WL** (imposées pour toute tâche visible, via `tools/map_shots.gd` corrigé par LD-26, sans HUD) :

| Groupe | Vues | Nombre |
|---|---|---|
| Plans du dessus | `top_ortho`, sans toits ; `top_ortho_roofs` | 2 |
| Aériennes | NE, NW, SE, SW | 4 |
| Spawns | `spawn_bleu`, `spawn_rouge` | 2 |
| Lanes | `grand_rue`, `route_nord` (dune → bus), `route_sud` (Ravin) | 3 |
| Positions et zones | `point_haut` (pont de grue), `hp_a`, `hp_b`, `hp_c` à hauteur d'œil | 4 |
| Ligne longue | `ligne_longue` (toit FUEL → butte) | 1 |
| **Total** | | **16** |

S'y ajoutent `prop_shots` et turntables pour tout nouvel asset, et `perf_bench`.

**Revue** : `powershell -File tools/review/run_review.ps1`, puis lecture de `summary.md`.

**Propriété des fichiers.** Les données de la carte sont découpées en 5 fichiers pour que les vagues puissent être parallèles :

| Fichier | Contenu | Créé par |
|---|---|---|
| `layouts/wasteland.gd` | géométrie | existe ; LD-20 le refond |
| `layouts/wasteland_look.gd` | palette | ART-70, en vague 1 ; c'est sa seule retouche de `wasteland.gd` : il en retire la clé `palette` |
| `layouts/wasteland_markers.gd` | marqueurs | LD-20, en fichier vide |
| `layouts/wasteland_bots.gd` | données bots | LD-20, en fichier vide |
| `layouts/wasteland_dressing.gd` | dressing | LD-20, en fichier vide |

Deux règles complètent cette découpe :
- `assets/models/props/manifest.json` est fusionné par le lead, jamais par deux tâches à la fois ;
- LD-21 remplace LD-04B pour Wasteland. LD-04B ne garde que Cargo Ship.

```
# ---------- Vague 0 : prérequis (hors carte, à ouvrir côté BOT par le lead) ----------
# Régression « 0 tir » : bot_smoke 120 s, cargo_ship ET wasteland = 0 kill, 0 tir (24 kills à 16 h 43).

# ---------- Vague 1 (parallèle) ----------
- id: LD-26
  title: Caméras de revue Wasteland (16 vues WL, ortho du dessus, sans HUD, aucune caméra dans la géométrie)
  size: S
  files: [tools/map_shots.gd]
  depends_on: []
  acceptance: >
    Les 16 vues sont produites pour wasteland ; aucune vue ne contient plus de 60 % de pixels d'une seule teinte
    (garde anti-caméra dans un mur) ; la carte occupe au moins 70 % de la hauteur de top_ortho ; aucun HUD.
  captures: [les 16 vues WL de l'état actuel, archivées comme « avant »]

- id: LD-23
  title: Choix de spawn (anti-empilement de 3 m, ancrage Hardpoint, pas de spawn dans ou en vue de la zone active)
  size: M
  files: [scripts/networking/SpawnPick.gd, tests/networking/test_spawn_pick.gd]
  depends_on: []
  acceptance: >
    Au début du match, 4 joueurs d'une équipe apparaissent sur 4 points distincts à au moins 3 m les uns des autres.
    En Hardpoint, aucun spawn n'est choisi dans la zone active, à 15 m ou moins d'elle, ni en ligne de vue d'elle
    à 25 m ou moins, s'il existe une alternative. Tests purs verts ; la télémétrie d'un bot_smoke Wasteland
    montre 8 positions de spawn distinctes à t0.
  captures: []

- id: ART-70
  title: Look Wasteland (palette par quartier, sol #D2A46C réellement rendu, azimut solaire par carte, remplissage des intérieurs)
  size: M
  files: [scripts/levels/maps/layouts/wasteland_look.gd (nouveau), scripts/levels/maps/layouts/wasteland.gd (retrait de la clé palette uniquement), scripts/core/LevelLook.gd, scripts/core/Cartoon.gd, docs/style/tokens.json]
  depends_on: []
  acceptance: >
    Sur spawn_bleu, grand_rue et spawn_rouge : médiane du sol L 0,60–0,78 et C ≤ 0,10, teinte 65–75° (CHK-04 PASS).
    Falaises : ΔL avec le sable ≥ 0,15. Tôle bleue absente de l'est, rouge GAS absent de l'ouest (masque de teinte
    sur les captures). Azimut du soleil à 60–90° des lanes pour wasteland, les autres cartes inchangées.
    Murs intérieurs à L ≥ 0,35 dans hp_c. CHK-02 et CHK-05 PASS sur les vues WL. Nouveau jeton « grue »
    ajouté à tokens.json (hors bandes réservées, CHK-07 PASS).
  captures: [WL complet, avant/après]

- id: ART-72
  title: Repères bpy (grue, derrick, château d'eau, pylône FUEL, ferme GAS, éolienne, clocher) + intégration de 3 sorties Tripo
  size: L
  files: [tools/blender/make_wl_landmarks.py, "assets/models/props/wasteland/{crane_tower,oil_derrick_v2,water_tower_v2,fuel_pylon,gas_sign_truss,windpump,chapel_bell}.glb/.json", assets/models/props/wasteland/canopy_station.glb, assets/models/props/wasteland/fuel_billboard_v2.glb, assets/models/props/wasteland/tank_horizontal.glb]
  depends_on: []
  acceptance: >
    check_asset PASS (budget de repère ≤ 15 000 triangles, aucune pièce flottante CHK-16, bbox ±2 %).
    Membrures ≥ 0,15 m, treillis ajouré à au moins 50 %. Hauteurs : grue 18 m, derrick 14 m au-dessus de la butte,
    château d'eau 8,8 m au-dessus du toit ; chaque visuel reste dans son enveloppe Kit à ±5 cm là où il y a collision.
    Décalques FUEL et GAS lisibles à 40 m. Auvent, panneau FUEL et cuves Tripo branchés
    (cuves à l'échelle 1,09 ; fuel_billboard_v2 = restyle Tripo PASS, distinct du fuel_billboard bpy déjà dans le jeu).
  captures: [turntable de chaque asset, aerial_ne, aerial_sw, point_haut]

- id: ART-74
  title: Vague Tripo « Wasteland volumes pleins » (11 générations, plafond 1 520 cr)
  size: M
  files: [tools/ai3d/manifests/wave_wl.yaml, "assets/incoming/tripo/restyled/wl_{bus_wreck,car_sedan_wreck,car_pickup_wreck,tanker_wreck,tank_skid,pipe_manifold,pump_jack,generator,fuel_pump,rock_outcrop,mesa_chunk}*", docs/assets/CREDITS.md]
  depends_on: []
  acceptance: >
    Arrêt si le premier job coûte plus de 1,3 × 120 cr. Au plus 1 520 cr dépensés, chaque dépense notée dans
    CREDITS.md avec le solde lu dans Studio. Chaque asset : G2 PASS et G3 PASS (check_asset) ; couverts à
    1,1 / 1,4 / 1,8 / ≥ 2,0 ±0,05 m ; aucune teinte des bandes réservées. Jamais de rouge sur tanker_wreck.
  captures: [planche turntable de chaque asset]

- id: ART-76
  title: Coulisses désert (jupe 40–150 m, anneau de mesas à strates, fond, repères directionnels) + nuages ≥ 6°
  size: M
  files: [scripts/levels/Backdrop.gd, assets/shaders/ink_sky.gdshader, tests/levels/test_backdrop.gd]
  depends_on: []
  acceptance: >
    CHK-12 PASS : 0 pixel de vide dans les 4 aériennes et dans top_ortho, sol visible jusqu'à l'anneau.
    CHK-13 : 3 à 5 masses nuageuses par demi-ciel, aucune sous 6°. Silhouettes : mesa ouest, raffinerie est,
    pylônes nord, visibles dans spawn_rouge, spawn_bleu et point_haut. Au plus 40 draw calls ajoutés (perf_bench).
    Val-Poussière relue sans régression.
  captures: [aerial_*, spawn_bleu, spawn_rouge, point_haut]

# ---------- Vague 2 ----------
- id: LD-20
  title: Blockout v3 de Wasteland (3 lanes, Grand-Rue à 3 coudes, Ravin à -1,2 m, GAS à 2 étages, accès des positions fortes, découpe en 5 fichiers)
  size: L
  files: [scripts/levels/maps/layouts/wasteland.gd, "scripts/levels/maps/layouts/wasteland_{markers,bots,dressing}.gd (fichiers vides)", scripts/levels/maps/MapSetup.gd (le seul _data_for, pour assembler les 5 fichiers), tests/maps/test_wasteland.gd, tests/maps/test_wasteland_los3d.gd]
  depends_on: [LD-26, ART-70]
  acceptance: >
    Les métriques de §c.7 passent en test : premier contact 5–7 s et écart ≤ 8 % ; traversée ≤ 14 s ;
    ligne de vue 3D à 1,6 m ≤ 30/30/18 m par lane et ≤ 8 m en intérieur ; ≤ 2 lignes ≥ 45 m, en hauteur ;
    au moins 3 accès navmesh par position forte ; indice de hauteur à ≤ 10 % ; ≤ 3 % de sol à plus de 8 m d'un couvert ;
    hauteur libre ≥ 3,2 m. Les anciens tests (parité, périmètre, rampes ≤ 37,5°, spawns bloqués) restent verts ;
    le test 2D des lignes de vue est remplacé par le test 3D (L5). Bounds 80 × 43 inchangés.
  captures: [top_ortho, top_ortho_roofs, aerial_*, grand_rue, route_nord, route_sud (en gray-box, avant tout art)]

- id: ART-71
  title: Kit — escaliers et échelles à limons et contremarches, arêtes et trims de bâtiments, débords de toit
  size: M
  files: [scripts/levels/maps/Kit.gd, tests/maps/test_kit.gd]
  depends_on: []
  acceptance: >
    Aucune marche sans appui : limons pleins sous chaque volée, contremarches fermées ; collision inchangée
    (test d'invariance Kit vert). Trims crème de 6 cm sur les arêtes verticales et en haut des murs ;
    débords de toit de 0,3 m hors espace praticable. Draw calls +5 % au plus sur les 8 cartes (perf_bench).
  captures: [grand_rue, point_haut, route_nord + une vue de chaque autre carte]

# ---------- Vague 3 ----------
- id: LD-21
  title: Marqueurs Wasteland (24 tdm_spawns + 8 d'équipe, 3 zones HP, 14 callouts, strong_positions)
  size: M
  files: [scripts/levels/maps/layouts/wasteland_markers.gd, tests/maps/test_wasteland_markers.gd]
  depends_on: [LD-20]
  acceptance: >
    24 tdm_spawns sur le navmesh, chacun avec un look qui ne vise pas un mur à moins de 8 m (raycast).
    Aucun spawn vu depuis une position forte adverse à 20 m ou moins. 3 zones HP : parité A↔C ≤ 10 % et B ≤ 8 %
    (navmesh) ; rotations B→A 2,5–4 s, A→C 4–6 s, C→B 2,5–4 s ; au moins 3 entrées navmesh par zone.
    14 callouts uniques de 14 caractères au plus, couvrant au moins 95 % du navmesh ; MapSetup.callout_at() testé.
  captures: [top_ortho annoté (zones, spawns, callouts), spawn_bleu, spawn_rouge]

- id: LD-22
  title: MapSetup — zones construites selon le mode, NavigationLink3D depuis les données, emprise HP par zone
  size: M
  files: [scripts/levels/maps/MapSetup.gd, tests/maps/test_mapsetup_modes.gd]
  depends_on: [LD-20]
  acceptance: >
    En TDM, aucune boîte de zone HP ni de site visible (V9) ; en Hardpoint, seule la zone active est visible,
    à l'emprise déclarée par zone. Les nav_links déclarés sont créés comme NavigationLink3D, bidirectionnels
    ou non selon la donnée. Les 8 cartes chargent sans erreur (bot_smoke de 30 s par carte, 0 SCRIPT ERROR).
  captures: [point_haut (TDM), hp_b (Hardpoint)]

- id: ART-73
  title: Kit « bidonville » bpy (fausses façades 1-2 étages alignées sur les ouvertures Kit, bardages, tôles, auvents, balcons)
  size: L
  files: [tools/blender/make_wl_shanty_kit.py, "assets/models/props/wasteland/shanty_*.glb/.json"]
  depends_on: [LD-20]
  acceptance: >
    Chaque façade laisse les portes et fenêtres Kit libres à ±5 cm (test sur les 10 bâtiments) ; rien ne dépasse
    dans l'espace praticable. Les fausses façades montent la silhouette à 5–7 m, décor au-dessus de 2,7 m.
    Budget skin ≤ 6 000 triangles par module, check_asset PASS. La skyline compte au moins 4 paliers de hauteur
    distincts dans spawn_bleu et spawn_rouge.
  captures: [turntables, grand_rue, spawn_bleu, spawn_rouge]

- id: ART-75
  title: Sol et bords (sable, piste, craquelures, traces de pneus ; falaises en roches à strates ; lit du Ravin)
  size: M
  files: [tools/textures/gen_textures.py (entrées wasteland), assets/textures/wasteland/, scripts/levels/maps/dressing/WastelandDressing.gd]
  depends_on: [LD-20, ART-70, ART-74]
  acceptance: >
    Piste visible en continu du spawn bleu au spawn rouge, plus sombre que le sable (ΔL 0,05–0,09).
    Aucune face de falaise plate de plus de 4 m² non habillée. Texture du sol : 1 répétition par 4 m, 1024²,
    netteté sans étirement dans grand_rue. CHK-04 et CHK-05 PASS.
  captures: [grand_rue, route_sud, aerial_*, top_ortho]

# ---------- Vague 4 ----------
- id: LD-24
  title: Données bots Wasteland (lanes, hotspots, hp_hold_points, hp_entries, nav_links, danger_spans) + rebake de BotSpots
  size: M
  files: [scripts/levels/maps/layouts/wasteland_bots.gd, resources/bot_spots/wasteland.tres, tests/ai/test_wasteland_bot_data.gd]
  depends_on: [LD-21, LD-22]
  acceptance: >
    Tous les critères du tableau de §e sont testés : points sur le navmesh, au moins 3 hotspots par lane,
    5 points de tenue par zone avec chaque entrée couverte, nav_links franchis par un bot simulé.
    Bake BotSpots en 30 s au plus.
  captures: [top_ortho annoté (lanes, hotspots, liens)]

- id: LD-25
  title: Buts de bots (patrouille par hotspots et lanes, tenue HP par points et entrées, préavis HP de 10 s)
  size: M
  files: [scripts/modes/GameMode.gd, scripts/modes/TDMMode.gd, scripts/modes/HardpointMode.gd, tests/ai/test_bot_goals.gd]
  depends_on: [LD-24]
  acceptance: >
    TDM : sans mémoire d'ennemi, le but vient des hotspots (plus jamais d'un marqueur de spawn) et les bots
    d'une équipe se répartissent sur au moins 2 lanes. Hardpoint : chaque bot vise un point de tenue distinct
    ou une entrée, jamais le centre commun ; la prochaine zone est annoncée 10 s avant (HUD et buts).
    Repli propre sur une carte sans données (les autres cartes ne régressent pas, tests existants verts).
  captures: []

# ---------- Vague 5 ----------
- id: ART-77
  title: Dressing par zone (≈ 190–230 instances, 25–35 décalques dont les pochoirs de callouts, enseignes), budgets de §d.5
  size: L
  files: [scripts/levels/maps/layouts/wasteland_dressing.gd, assets/textures/decals/wasteland_atlas.png]
  depends_on: [ART-72, ART-73, ART-74, ART-75, LD-21]
  acceptance: >
    Comptes par zone dans les fourchettes de §d.5 (test sur les données). Au moins 70 % du décor au mur,
    en bord ou au-dessus de 2,7 m ; 0 décor dans le cœur de lane de 2,5 m ; rien d'humanoïde entre 1,5 et 1,9 m
    (CHK-17). Tout prop répété 3 fois ou plus passe en MultiMesh. Steam Deck : ≤ 800 draw calls et ≤ 1,2 M triangles
    au pire point (perf_bench). Les 14 pochoirs sont lisibles à 15 m.
  captures: [WL complet]

- id: LD-27
  title: Banc bots Wasteland (TDM 10 min et Hardpoint 10 min, Vétéran), seuils de régression
  size: S
  files: [tools/bot_bench.gd (profil wasteland), reports/bot_bench/wasteland_*.json]
  depends_on: [LD-25]
  acceptance: >
    Seuils de §e atteints : ≥ 6 kills/min, premier contact médian de 5 à 9 s, temps bloqué ≤ 2 %,
    20–45 % des traversées par lane, aucune position forte tenue plus de 35 % du temps par la même équipe,
    moins de 5 % de morts à 3 s ou moins d'un spawn, zone HP occupée au moins 70 % du temps.
    Heatmap LD-08 kills/morts produite.
  captures: [heatmaps kills, morts et différence]

# ---------- Vague 6 : porte de sortie ----------
- id: ART-78
  title: Passe finale Wasteland (checklist bible §11, perf, playtest humain)
  size: M
  files: [docs/maps/wasteland_final.md]
  depends_on: [ART-77, LD-27, ART-76, ART-71]
  acceptance: >
    style_check sur les 16 vues WL : au moins 90 % PASS et 0 FAIL bloquant parmi CHK-02 à CHK-21 ; CHK-12,
    CHK-14 (au moins 3 repères au-dessus des toits depuis 70 % de la grille) et CHK-46 PASS. Perf : bureau
    ≥ 144 fps à 1080p, Deck ≥ 60 fps à 800p. Suite de tests complète verte. Un playtest 4v4 humains + bots avec
    une grille de questions « où suis-je / où vais-je » (03 §2.7) : au moins 80 % des callouts cités juste
    sans aide.
  captures: [WL complet + comparaison côte à côte avec wasteland_sheet.png]
```

**Ordre et parallélisme :**

| Vague | Tâches |
|---|---|
| 0 | régression des bots (préalable) |
| 1 | LD-26, LD-23, ART-70, ART-72, ART-74, ART-76, en parallèle, fichiers disjoints |
| 2 | LD-20, ART-71 |
| 3 | LD-21, LD-22, ART-73, ART-75 |
| 4 | LD-24, puis LD-25 |
| 5 | ART-77, LD-27 |
| 6 | ART-78 |

Deux tâches concurrentes ne touchent jamais `MapSetup.gd` : LD-20 ne modifie que `_data_for`, LD-22 passe en vague 3.
