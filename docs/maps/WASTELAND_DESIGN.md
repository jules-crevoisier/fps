# Wasteland v6 — conception (greybox, 4v4 TDM)

Source unique : `data/maps/wasteland_plan.json` (v6-greybox). Plan coté généré : `docs/maps/WASTELAND_PLAN.md`
(`python tools/maps/render_plan.py`). Images : `docs/maps/img/wasteland_plan_top.png`, `wasteland_plan_3d.png`,
`wasteland_coupe_ns.png`, `wasteland_coupe_oe.png`.

![Vue de dessus](img/wasteland_plan_top.png)

## Thèse

Une petite ville de l'Ouest en **trois couloirs lisibles**, chacun avec une raison d'y aller, reliés au centre et
surmontés d'**un seul réseau haut continu**. Le centre est **ouvert** : on s'y bat à courte ou moyenne distance, on y
revient en 5 s. Chaque position forte a sa réplique en face (balcon contre balcon, galerie contre galerie) et au moins
deux entrées.

## Recherche (lue le 2026-09-26)

- Treyarch, *Black Ops 7* (Xbox Wire, 27/10/2025) : « Every lane needs a purpose » ; une position forte dans un couloir
  appelle une position forte adverse (Toshin : deux bâtiments qui se font face au-dessus de la rue centrale) ; couverts
  symétriques pour des duels équitables ; aucun point ne doit dominer toute la carte.
- SuperJump, *Why have three lane maps endured in Call of Duty* : trois routes d'une apparition à l'autre, jamais plus de
  trois décisions à la fois (règle attribuée à D. Vonderhaar).
- The Level Design Book, *Map balance* / *Cover* : le couvert règle la portée d'une ligne de vue ; une position est un
  « camping spot » si on ne peut pas la contourner ou si toutes ses menaces tiennent dans un seul champ de vision.
- Wiki Call of Duty, *Nuketown* : chaque maison offre trois choix (contourner, traverser le rez, monter à l'étage qui
  domine le centre et la maison d'en face) ; revers : les cartes compactes favorisent l'encerclement des apparitions.

Conséquences ici : 3 couloirs, bâtiments traversants, étages qui se font face et se rejoignent, apparitions sans vue
sur la moitié adverse (contrôlé).

## Dimensions

Empreinte **84 × 50 m** (x −42…42, z −25…25), moitié ouest miroir de l'est. Au sprint (8,2 m/s), une apparition est à
~10 s de l'autre en ligne droite ; le premier contact tombe à **5,0–6,7 s** (tableau plus bas) : assez court pour un
jeu nerveux, assez long pour que l'apparition ne soit pas déjà la ligne de front. À 4 contre 4, quatre zones de combat
(rue/Banque, place, gué de la carrière, réseau haut) suffisent à occuper 8 joueurs sans couloir mort. Chaque mètre
retiré par moitié avance le contact d'environ 0,12 s : sous ~82 m de large, on passerait sous 5 s.

Niveaux : sol 0, étage 3,2, carrière −2. Métriques joueur, portes, escaliers inchangées (bloc `metrics`).

## Couloirs

| Couloir | Zone | Largeur | Vue max mesurée | Rôle |
|---|---|---|---|---|
| 1 Grand-Rue (nord) | x ±30, z −18…−8 | 10 m façade à façade ; bouche escalier→Banque 5,5 m | 24,7 m | rue à deux étages : rez + galerie au-dessus ; la Banque au centre coupe la rue en deux demi-rues de 24 m |
| 2 Place (centre) | x ±26, z −8…13 | place 28 × 14 m + terrasse du bord 28 × 6,5 m | 29,5 m | combat courte-moyenne entre deux Saloons qui se font face ; wagon traversant au centre |
| 3 Carrière (sud, −2 m) | x ±42, z 13…25 | 12 m paroi à paroi ; passages 5–5,5 m | 30,8 m | route basse en lacets, contournement ; gué central où débouchent les rampes de la place |

Sorties de chaque apparition (4 points à x = ±41) : **nord** → Grand-Rue (coude Écurie/Citerne 3 m, Citerne/Saloon 5 m, ou
à travers l'Écurie) ; **est** → Place (porte L du Saloon) ; **sud** → Carrière (Rampe Cour 4,5 m) ; en plus, sud-est →
ruelle → Remise ou Rampe Ruelle.

Routes au sprint (symétriques, départ simultané ; contact = vue tenue ≥ 0,5 s sur un adversaire) :

| Couloir | Route jusqu'au centre | Contact même couloir | Contact tout couloir |
|---|---|---|---|
| Grand-Rue | 49,5 m (6,0 s) | 5,1 s (coin sud de la Banque) | 5,0 s |
| Place | 45,6 m (5,6 s) | 5,1 s (bout nord du wagon) | 5,0 s |
| Carrière | 63,9 m (7,8 s) | 6,7 s (gué) | 6,7 s |

## Bâtiments : rôle et liaisons

| Bâtiment | Taille | Niv. | Rôle | Entrées RDC | Étage |
|---|---|---|---|---|---|
| Écurie (×2) | 12×12 | 1 | ferme le bout de la rue, cache l'apparition | S (cour), E (rue) | — |
| Hôtel / Pension | 11×7 | 2 | façade nord de la rue | S (rue), E (→ Magasin) | S1 → galerie ; fenêtres sur rue |
| Magasin / Épicerie | 13×7 | 2 | façade nord, relie Hôtel et Banque | S L (rue), O (Hôtel), E (Banque) | S1 → galerie |
| **Banque** (centre) | 12×15 | 2 | bâtiment-héros du couloir nord | O/E (rues), O/E (Magasins), S L (place) | O1/E1 depuis les deux galeries ; fenêtres S sur la place, O/E sur les rues |
| Coffre (dans la Banque) | 4×3 | — | coupe l'axe des portes de rue, boucle de combat rapproché | — | — |
| **Saloon** (×2) | 12×12 | 2 | couloir central, se font face à 28 m | O L (cour), N (rue), E L (place) | N1 → passerelle, E1 L → balcon ; fenêtres |
| Remise (×2) | 4×9 | 1 | ferme la ruelle, traversante en biais | O, E (décalées) | — |
| **Wagon** (centre) | 3×9 | 1 | pièce centrale, traversante N-S, flancs aveugles | N, S | — |
| Pompe + château d'eau | 4×5,5 | — | repère, coupe la terrasse du bord | — | — |

**Réseau haut** (13 espaces, 9 accès depuis le sol) : galerie 24 × 2,5 m devant Hôtel + Magasin → porte O1/E1 de la
Banque (les deux équipes s'y rejoignent) ; passerelle 7,5 × 2,5 m au-dessus de la rue → étage du Saloon → balcon
12 × 2,5 m sur la place → escalier du balcon qui redescend dans la rue. Accès : 7 rampes intérieures (Kit) + 2
escaliers de balcon. Raisons d'y monter : dominer la rue (galerie), la place (balcon, fenêtres S de la Banque), passer
de la rue à la place à couvert. Répliques : garde-corps à 1 m (couvert accroupi seulement), balcon adverse à 23 m,
fenêtres S de la Banque, tirs depuis la rue, chaque étage a au moins 2 entrées.

## Ce qui change par rapport à la v5, et pourquoi

| Plainte (2026-09-26) | v5 | v6 |
|---|---|---|
| « Bâtiments du nord pas reliés, pas envie d'y monter » | Hôtel / Magasin / Forge séparés, étages atteints par des escaliers d'impasse, aucune liaison entre eux | galerie continue devant les façades, passerelle vers le Saloon, balcon sur la place, Banque centrale reliée aux deux galeries ; rez-de-chaussée enchaînés Hôtel ↔ Magasin ↔ Banque ; un seul réseau haut de 13 espaces |
| « Carrière : pas assez d'espace entre obstacles et rampes, mal agencé » | 8 m de large, passages 3,5 m, rampes 2,5 m posées dans la carrière | 12 m de large, 10 aiguilles de 3,5–4 × 6,5 m alternées N/S à **5 m** d'intervalle, passages 5,5 m ; 6 rampes **4,5 m** creusées dans le plateau (ne mangent plus la carrière), 3 m dégagés aux deux bouts |
| « Mid collé, pas de place, bâtiments qui ne fonctionnent pas ensemble » | 16 m entre Saloons, wagon 12 × 3 et château d'eau au milieu | place **28 × 14 m** + terrasse 6,5 m, seulement C1/C2 + wagon traversant ; ≥ 3 m partout ; Saloons, Banque et balcons se répondent et se rejoignent |

Aussi : footprint 88 × 45 → 84 × 50 ; repères des autres modes (points, sites, barrières duel) retirés : TDM seul.

## Contrôles (script lancé sur le JSON)

Script : `check_plan.py` (bloc-notes de session, à copier en `tools/maps/check_plan.py` si on le garde). Volumes après
miroir ; lignes de vue en 3D œil à œil (1,6 m), murs percés de leurs portes et fenêtres, dalles, rampes intérieures du
Kit ; écarts = distance entre emprises au même niveau.

| Contrôle | Résultat | Détail |
|---|---|---|
| Empreinte 4v4 (70–85 × 45–55 m) | OK | 84 × 50 m = 4 200 m² |
| Bâtiments : ≥ 2 entrées RDC sur côtés différents | OK | Écurie ES, Hôtel ES, Magasin ESO, Banque ESO, Saloon ENO, Remise EO, Wagon NS |
| Trémie sur un côté sans porte RDC | OK | toutes conformes |
| Étages : ≥ 2 routes + reliés à un autre espace haut | OK | Hôtel/Magasin 2 entrées d'étage, Banque/Saloon 3 ; 9 accès depuis le sol dans le réseau |
| Réseau haut connexe | OK | 13/13 espaces |
| Écart libre ≥ 3 m entre obstacles | OK | plus petit 3,00 m (Écurie ↔ Citerne) ; aucun passage serré |
| Aucun volume qui se chevauche | OK | aucun |
| Rampes ≥ 4 m, 3 m dégagés aux deux bouts ; pied d'escalier dégagé | OK | 6 rampes de 4,5 m |
| Place ≥ 20 × 14, C1/C2 seulement, centre traversant | OK | 28 × 14 m, Wagon portes N/S |
| Carrière ≥ 10 m, couverts à 5–8 m, 2 rampes/moitié vers le centre | OK | 12 m ; voisins à 5,0 m ; Rampe Ruelle + Rampe Place |
| Vue max Grand-Rue ≤ 60 m | OK | 24,7 m |
| Vue max Place ≤ 30 m | OK | 29,5 m (ruelle ouest → place est, par l'intervalle wagon/pompe) |
| Vue max Carrière ≤ 40 m | OK | 30,8 m |
| Apparitions sans vue sur la moitié adverse | OK | aucune ligne |
| 3 sorties → 3 couloirs ; premier contact 5–8 s | OK | 5,1 / 5,1 / 6,7 s (même couloir), 5,0 s au plus tôt |

## Risques ouverts

- **Contact à 5,0 s** : pile au seuil. Si le playtest le trouve trop court, décaler les apparitions de 1–2 m ou passer
  à 86 m de large. Le calcul suppose un sprint instantané et un départ simultané ; en TDM les réapparitions varient.
- **Aucune ligne > 31 m** : la carte est courte-moyenne, les fusils longs y sont faibles. Si on veut une vraie ligne
  longue, retirer le Coffre ouvre ~60 m à travers les portes de la Banque (à tester, risque de ligne d'apparition à
  apparition).
- **Étage de la Banque** : position centrale atteinte par les deux galeries, elle peut devenir un hachoir ou provoquer
  des bascules d'apparition. Répliques prévues : fenêtres S exposées aux balcons (10–16 m), trois entrées.
- **Dessous des passerelles à 2,95 m** : un saut sous la galerie ou la passerelle cogne la tête (apex 3,16 m).
  Acceptable ; sinon relever `upper`.
- **Rampes intérieures du Kit** : Hôtel et Magasin font 7 m de profondeur, donc trémie de 5,5 m pour une rampe de 6 m :
  vérifier le rendu du Kit. Les 6 rampes de carrière font 6 m pour 2 m de dénivelé (18°).
- **Le jeu ne lit pas encore ce JSON** : le constructeur devra gérer le sol découpé autour des entailles de rampe, les
  portes d'étage (`floor: 1`), les dalles `solid_below: false`, les garde-corps `class: rail` (t 0,05) et la clé
  `plaza`, ajoutée pour les contrôles.
- **Couverture de la place volontairement légère** (2 couverts par moitié) : à étoffer en C1/C2 après playtest si la
  traversée paraît trop exposée.
