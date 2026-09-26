# Wasteland v7 — conception (greybox asymétrique, 4v4 TDM)

Source unique : `data/maps/wasteland_plan.json` (v7-greybox-asym, `mirror.enabled = false`). Plan coté généré :
`docs/maps/WASTELAND_PLAN.md` (`python tools/maps/render_plan.py`). Contrôles : `python tools/maps/check_plan.py [--md]`.
Images : `docs/maps/img/wasteland_plan_top.png` (routes de sprint, fronts X, positions fortes ★), `wasteland_plan_3d.png`,
`wasteland_coupe_ns.png`, `wasteland_coupe_oe.png`, `wasteland_coupe_sud.png`.

![Vue de dessus](img/wasteland_plan_top.png)

## Thèse

Verdict v6 : « C'est symétrique, c'est boring à la mort. » La v7 garde ce qui marchait (trois couloirs lisibles,
bâtiments du nord reliés par un réseau haut, place ouverte avec wagon traversant, canyon large à rampes larges), mais
**chaque moitié est un lieu différent** : à l'ouest **la Ville** (rue droite, façades à deux niveaux, saloon), à
l'est **la Gare de fret et la Mine** (voies, portique, poste d'aiguillage, quai surélevé, trémie). Formes, repères,
hauteurs et tracés diffèrent ; ce qui est égal, ce sont les **temps**, les **positions fortes** et les **lignes de vue**
(mesurés, tableau plus bas). C'est le principe de Crash / Crossfire / Standoff : des moitiés qui ne se ressemblent pas
mais qui offrent les mêmes chances.

## Recherche (2026-09-26)

- Carte asymétrique en mode sans zone attribuée (Crash est l'exemple cité) : l'asymétrie rend le contrôle de zone
  dynamique, à condition que chaque côté ait des positions de force équivalentes (Tumblr, *Symmetrical vs
  Asymmetrical Level Design*, devspecmattross ; overdertoza.com, *Designing Symmetrical vs Asymmetrical Multiplayer Maps*).
- Crossfire : un côté de combat rapproché (murets, bennes) près du bord de carte, un autre ouvert (Activision,
  *CoD Mobile Map Snapshot: Crossfire*). Repris ici : la Ville est « intérieurs + galerie », la Gare « cour + quai ».
- Acquis v6 conservés : trois couloirs, une position forte appelle sa réplique, pas de position qu'on ne peut pas
  contourner, apparitions sans vue sur la moitié adverse.

## Les deux moitiés

| | Ouest — la Ville (équipe 0) | Est — la Gare de fret et la Mine (équipe 1) |
|---|---|---|
| Idée | la rue principale d'une ville de l'Ouest | ce qui fait vivre la ville : le rail et la mine |
| Silhouette | rangée continue de façades à 2 niveaux (Hôtel, Magasin), Saloon, Écurie basse ; Arbre du pendu | Halle à 2 niveaux (14 × 22), Bureau du fret, poste d'aiguillage en tour, château d'eau 12,5 m, chevalement 13 m |
| Hauteurs | sol 0, galerie et balcon 3,2, Colline du Pendu +1,2 | sol 0, **quai +1,2**, Trémie +1,2, portique et étages 3,2 |
| Couloir nord | Grand-Rue droite (24 × 10) sous une galerie continue | les Voies : cour en L, portique N-S au-dessus des rails, escalier du portique, fourgon de queue |
| Couloir milieu | traversée du Saloon, balcon sur la place, ruelle + Remise | quai surélevé fermé par la salle d'attente (guichet en chicane), lampisterie traversante dessous |
| Canyon | Ravin 12 m, aiguilles alternées, 3 rampes | Tranchée 12 m puis 10 m (décrochement à x = 24), terrils, pile d'étais, Recette du puits, 2 rampes |
| Apparition | grande cour ouverte (Écurie au nord, Saloon en écran) | cour étroite derrière l'estacade à charbon (portes en chicane), sortie nord par la Halle |

Centre partagé : Banque (deux portes sud décalées de l'axe du coffre), wagon traversant N-S, éolienne sur son bassin
(repère central ; le château d'eau passe à l'est, où il a un sens ferroviaire).

## Couloirs

| Couloir | Ouest | Est | Front partagé |
|---|---|---|---|
| 1 nord | rue droite, galerie au-dessus, passerelle vers le Saloon, escalier du balcon | sortie par la Halle, Voies en L, portique relié au Bureau (pont vers la Banque) et au Poste | intérieur de la Banque (0 ; −11,5) |
| 2 milieu | Saloon traversant puis place ; balcon 12 m | estacade (chicane) → marches du quai → quai +1,2 → salle d'attente → marches vers la place | bout nord du wagon (0 ; −6) |
| 3 canyon | rampe de la Cour, lacets entre 4 aiguilles et le Pendu | rampe du Carreau, lacets entre Recette, étais, terrils et la Trémie | gué (0 ; −2 ; 17) |

La place n'est plus un rectangle miroir : partie ouest profonde au nord (jusqu'à la Banque), partie est décalée au sud et
fermée par le Poste et les marches du quai ; 320 m², dont 284 m² libres (C1/C2 seulement).

## Positions fortes et répliques

Chaque équipe a **3 positions surélevées** (une par couloir), chacune à +3,2 m au-dessus de son couloir, avec au moins
deux accès et des répliques visibles depuis des directions écartées (mesuré en 3D, œil à œil).

| Équipe | Position | Accès | Répliques (visibles, écart angulaire) |
|---|---|---|---|
| 0 | PP1 Galerie de la Grand-Rue (3,2) | Hôtel, Magasin, passerelle, Banque | étage de la Banque en enfilade, rue sous la galerie, passerelle — 3/3, 90° |
| 0 | PP2 Balcon du Saloon (3,2) | Saloon, escalier du balcon | fenêtre O du Poste, place nord, place sud — 3/3, 72° |
| 0 | PP3 Colline du Pendu (+1,2 ; +3,2 sur le ravin) | marches terrasse, marches ravin | Trémie en face, gué, terrasse, ravin ouest — 4/4, 180° |
| 1 | PP4 Portique de signalisation (3,2) | Bureau, Poste, escalier du portique | sortie E de la Banque, devant la Halle, place nord-est — 3/3, 156° |
| 1 | PP5 Poste d'aiguillage, étage (3,2) | rampe intérieure, portique | balcon du Saloon, place nord-est, place sud-est (fenêtre O) — 3/3, 54° |
| 1 | PP6 Trémie (+1,2 ; +3,2 sur la tranchée) | marches voie de garage, marches tranchée | Pendu en face, gué, voie de garage, tranchée est — 4/4, 179° |
| — | PP7 Étage de la Banque (partagé) | 2 réseaux hauts + rampe | galerie (porte O1), pont du Bureau (porte E1) — 2/2, 138° |

Répliques croisées voulues : balcon ↔ poste (27 m, fenêtre contre balcon ouvert), Pendu ↔ Trémie (24 m au-dessus du gué),
galerie ↔ portique via l'étage de la Banque.

## Équilibre (mesuré par `check_plan.py`)

| Couloir | Sprint apparition → front O / E | Écart (≤ 10 %) | Premier contact O / E | Vue interne max O / E | Écart (≤ 15 %) |
|---|---|---|---|---|---|
| Nord | 43,7 m (5,33 s) / 46,8 m (5,71 s) | 7,0 % | 5,1 / 5,1 s | 24,7 / 26,1 m | 5,6 % |
| Milieu | 45,6 m (5,56 s) / 46,3 m (5,65 s) | 1,7 % | 5,1 / 5,1 s | 23,9 / 26,9 m | 12,9 % |
| Canyon | 61,8 m (7,54 s) / 61,9 m (7,55 s) | 0,1 % | 6,8 / 6,8 s | 28,5 / 26,4 m | 7,8 % |

Positions surélevées : 3 / 3. Surface marchable (sol + étages + dalles + plateformes) : ouest 2 464 m² (1 953 + 511),
est 2 575 m² (1 972 + 603), écart 4,5 %. Sprint 8,2 m/s, départ simultané ; « contact » = vue tenue ≥ 0,5 s ; « vue
interne » = plus longue ligne dont les deux bouts sont dans la même moitié (x < 0 ou x > 0).

## Contrôles (23/23 OK)

| Contrôle | Résultat | Détail |
|---|---|---|
| Empreinte 4v4 | OK | 84 × 50 m |
| Carte asymétrique | OK | aucun volume reflété : 47 W, 61 E, 11 C |
| Bâtiments ≥ 2 entrées RDC sur côtés différents | OK | 15 bâtiments, dont Fourgon, Salle d'attente, Lampisterie, Estacade, Recette |
| Trémie d'escalier sur un côté sans porte | OK | — |
| Étages ≥ 2 routes + reliés ; réseau haut connexe | OK | 13/13 espaces hauts dans un réseau, 9 accès depuis le sol |
| Écart ≥ 3 m entre obstacles ; aucun chevauchement | OK | plus petit 3,00 m ; niveaux −2, 0 et +1,2 |
| Rampes ≥ 4 m, 3 m dégagés ; pied d'escalier dégagé | OK | 5 rampes de 4,5 m, 8 escaliers |
| Place ≥ 280 m² libres, C1/C2 seulement, centre traversant | OK | 284 m² libres sur 320 ; wagon N-S |
| Canyon ≥ 10 m, rochers à 5–8 m, ≥ 2 rampes par moitié | OK | 12 m ouest, 10 m est ; voisins à 5,0 m ; 3 + 2 rampes |
| Vues max nord ≤ 60 / milieu ≤ 30 / canyon ≤ 40 m | OK | 27,1 / 29,5 / 30,4 m |
| Apparitions sans vue sur la moitié adverse | OK | aucune ligne, dans les deux sens |
| Routes de sprint praticables ; 3 sorties par équipe | OK | 6 routes ; est : Halle, estacade, rampe du Carreau |
| Premier contact 5–8 s | OK | 5,1 / 5,1 / 6,8 s |
| Équilibre (4 contrôles) | OK | tableau ci-dessus |

## Ce qui change par rapport à la v6, et pourquoi

| v6 | v7 | Pourquoi |
|---|---|---|
| moitié ouest reflétée en x | moitiés W / C / E décrites séparément (`mirror.enabled = false`) | « symétrique, boring » |
| est = copie de l'ouest | la Gare de fret et la Mine : voies, portique, poste, quai +1,2, halle, trémie, chevalement | autre lieu, autre silhouette, autres hauteurs |
| place rectangle 28 × 14 | place en deux parties décalées, bords différents (balcon / poste + marches du quai) | casser le miroir sans perdre l'ouverture |
| canyon droit 12 m des deux côtés | ravin 12 m à l'ouest ; tranchée 12 puis 10 m avec décrochement, recette et étais à l'est | largeur et tracé qui changent |
| château d'eau au centre | éolienne au centre, château d'eau dans la cour de la gare | repère qui dit « est » |
| aiguille N1 ouest | Colline du Pendu (+1,2) ; en face la Trémie (+1,2) | une position forte par couloir et par équipe |
| porte sud de la Banque en L dans l'axe | deux portes M décalées | coupait une ligne place ↔ intérieur de la Banque qui avançait le contact à 4,9 s |
| contrôles pour une carte miroir | `check_plan.py` : sol par surfaces, 3 niveaux, régions multi-rectangles, routes O et E, 4 contrôles d'équilibre | mesurer l'équilibre au lieu de le supposer |

Outils : `render_plan.py` sait lire une carte sans miroir (et trace routes, fronts, positions fortes, coupe du canyon) ;
`check_plan.py` est étendu (nouveau type de volume `platform` = dessus marchable ; écarts mesurés seulement là où le
milieu de l'écart est un sol du même niveau).

## Risques ouverts

- **Est plus long au nord** (+7 % : sortie par la Halle) : dans la marge, mais l'équipe est arrive 0,4 s plus tard à la
  Banque ; si le playtest le sent, descendre la porte ouest de la Halle vers z = −8 (≈ −1 m, −0,12 s).
- **Place à 284 m² libres et vue max du milieu à 29,5 m** : proches des seuils ; toute couverture ajoutée ou tout volume
  déplacé près du wagon doit être revérifié (fenêtre sud wagon / bassin).
- **Chicanes** (salle d'attente + guichet, lampisterie, estacade, fourgon de queue) : elles tiennent les lignes de vue
  et la protection d'apparition ; un changement de porte les casse. Vérifier aussi que les bots passent le guichet
  (1,2 m).
- **Halle 14 × 22 à 2 niveaux** : écran d'apparition et étage de compensation ; masse très présente, à habiller.
- **Portique de 3,2 m au-dessus des voies sans couvert** (garde-corps seulement) : exposé exprès ; si trop faible, ajouter
  un C2 sur la dalle.
- **Le jeu ne lit pas encore ce JSON** : le constructeur devra gérer `mirror.enabled`, le type `platform`, `levels.dock`,
  les bâtiments posés sur le quai (y0 = 1,2) ou dans le canyon (y0 = −2), les couloirs `route_w/route_e/front/regions`.
- `tools/maps/gen_wasteland_plan.py` est le générateur v6 (lit un fichier v5 absent) : obsolète, ne pas le relancer ;
  le JSON v7 est la source.
