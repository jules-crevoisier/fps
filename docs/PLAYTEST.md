# Playtest — Wasteland v4 contre bots

Ce document explique comment lancer, en quelques clics, une partie **Wasteland
v4** (le nouveau blockout 3 lanes de `docs/research/11_wasteland_v4_layout.md`,
scripts/levels/maps/layouts/wasteland.gd) contre des bots, pour un test humain
rapide — et résume ce que le banc de bots automatique (`tools/bot_bench.gd`) a
déjà mesuré dessus, comparé à l'ancienne carte (v3, le damier gelé sous
`wasteland_v3.gd`). Rédigé pour la tâche LD-43, corrigé sur retour du
vérificateur (v5, voir §2 « Deux runs de plus, après correctif »).

---

## 1. Lancer une partie

Ouvrir le jeu (`Godot_v4.7-stable_win64.exe`, ou ▶ dans l'éditeur Godot) fait
apparaître le menu principal directement sur l'onglet **Partie** : un seul
bouton visible par défaut, **▶ JOUER** — c'est la conception voulue (UX-08,
`scripts/ui/MainMenu.gd`) : « le joueur qui ne touche à rien n'a qu'une
surface cliquable ». Sous ce bouton, une ligne résume ce qui va être lancé,
par ex. `Arène — 07. WASTELAND` ou `Hardpoint — 07. WASTELAND`.

Le nombre de clics dépend d'un seul état : **Wasteland est-elle déjà la carte
mémorisée sur ce poste** (`MatchConfig.map_id`, persistée dans
`user://match_config.cfg`) ? Rien dans `scripts/ui/MainMenu.gd` ni
`scripts/levels/maps/MapCatalog.gd` (tous deux hors de mon périmètre de
fichiers pour cette tâche) ne fait de Wasteland la carte par défaut au tout
premier lancement sur un poste neuf — `MapCatalog.default_for("tdm")` renvoie
la première carte du catalogue qui supporte le mode (« Port-Ferraille »), pas
Wasteland. Les trois cas réels, du plus rapide au plus lent :

### 1 clic — Wasteland déjà mémorisée, aucune vérification voulue

Si la dernière partie lancée ici était déjà Wasteland (le cas courant sur ce
poste de dev, où c'est la carte de test répétée), la ligne de résumé sous
JOUER l'indique déjà : cliquer **▶ JOUER** suffit. Bots et Vétéran sont
activés par défaut (`MatchConfig.bots_enabled = true`, `bot_difficulty =
VETERAN`).

### 2 clics — Wasteland déjà mémorisée, avec le panneau ouvert pour vérifier

Pour un test utilisateur qui veut VOIR la sélection (carte/mode/bots/
difficulté) avant de lancer, plutôt que de faire confiance à la ligne de
résumé :

1. Cliquer **▸ Partie personnalisée** (déplie le panneau) — si Wasteland est
   déjà la carte mémorisée, sa carte y apparaît déjà sélectionnée
   (`MainMenu._refresh_maps`, `remembered_index`) : rien d'autre à cliquer
   dans la liste des cartes.
2. Cliquer **▶ JOUER**.

C'est le chemin recommandé pour le test utilisateur de cette tâche : deux
clics, panneau visible (donc Bots/Vétéran vérifiables d'un coup d'œil), aucune
sélection de carte à faire puisqu'elle est déjà la bonne. **Condition
préalable** (à faire une seule fois, pas un clic dans le jeu) : que
`user://match_config.cfg` porte déjà `map_id = "wasteland"` — déjà le cas sur
ce poste après n'importe quel lancement précédent de Wasteland (banc de bots
exclu : `tools/bot_bench.gd` ne passe jamais par ce menu, il ne touche pas ce
fichier). Sur un poste neuf, faire une fois le chemin « 3 clics » ci-dessous
et tous les lancements suivants retombent sur 1 ou 2 clics.

### 3 clics — premier choix explicite (poste neuf, ou autre carte mémorisée)

Si le résumé sous JOUER n'indique pas Wasteland :

1. Cliquer **▸ Partie personnalisée** (déplie mode/carte/bots/difficulté).
2. Cliquer la carte **« 07. WASTELAND »** dans la liste (mode par défaut :
   **Arène**, TDM — cliquer **Hardpoint** juste au-dessus si c'est plutôt ce
   mode qu'on veut tester : c'est la même carte, seul le mode change).
3. Cliquer **▶ JOUER**.

Ce choix est mémorisé : au lancement suivant, 1 ou 2 clics suffisent (voir
ci-dessus).

### Ce qu'on doit voir

- Sélection d'agent (15 s), puis apparition côté bleu ou rouge (cours de
  spawn ouest/est symétriques).
- TDM (« Arène ») : premier contact au sprint entre 4 et 7 s selon la lane
  empruntée (Grand-Rue au nord, Intérieurs au centre, Canyon au sud —
  §5 de `docs/research/11_wasteland_v4_layout.md`). En partie réelle contre
  des bots Vétéran, le banc de bots mesure actuellement plus lent et plus
  variable que cette cible géométrique — voir §2, colonne « Cible » non
  atteinte pour `first_contact_median_s`.
- Hardpoint : rotation des 3 zones (Wagon → Magasin ouest → Gué, 45 s
  chacune, préavis 10 s).

---

## 2. Ce qui a déjà été mesuré (banc de bots automatique)

`tools/bot_bench.gd` fait tourner une vraie partie headless (pas de rendu) et
en extrait des métriques — c'est plus rapide et plus répétable qu'un test
humain pour les régressions de timing/équilibrage. Lancé ici pour LD-43 sur
**hp_veteran + tdm_veteran**, sur la v4 (`wasteland`) et sur l'ancienne carte
figée pour comparaison (`wasteland_v3`, §12.6 de la spec v4) :

```bash
"C:\Users\srko\Desktop\Godot_v4.7-stable_win64.exe" --headless --path . \
  -s res://tools/bot_bench.gd -- --map=wasteland --phases=tdm_veteran,hp_veteran \
  --tdm-duration=180 --time-scale=6 --out=reports/bot_bench/ld43_v4.json
```

(`--map=wasteland_v3` pour la comparaison ; `--time-scale=6` documenté dans
`docs/TESTING.md` — ~180 s simulées tournent en ~30-60 s réelles.)

### v3 (ancien damier) vs v4 (nouveau blockout 3 lanes)

| Métrique | v3 | v4 | Cible | v4 dans la cible ? |
|---|---|---|---|---|
| Premier contact médian (TDM Vétéran) | 4,1 s | 7,9 à 14,2 s (4 runs, voir détail ci-dessous) | 4–7 s | **Non** — toujours au-dessus, très variable d'un run à l'autre |
| Temps bloqué | 1,9 % | 3,0 à 3,6 % (4 runs) | ≤ 2 % | **Non** — systématiquement au-dessus, réduit mais pas résorbé par le correctif §2.2 |
| Occupation zone HP (minimum sur une fenêtre pleine de 60 s) | 77 % | 43,7 à 86,0 % (4 runs, voir détail) | ≥ 70 % | **Variable** — sous cible avant le correctif §2.2 (43,7 %, 60,8 %), dans la cible après (74,7 %, 86,0 %) sur les 2 runs disponibles |
| Part des traversées par lane (Grand-Rue / Intérieurs / Canyon) | non mesurable (v3 n'a pas de lanes déclarées, `NO_DATA`) | ex. 15,4–18,1 % / 77,9–78,4 % / 4,1–6,2 % (2 derniers runs) | 20–45 % chacune | **Non** — Intérieurs surreprésentée (60 à 84 % selon le run), Canyon quasi désertée, Grand-Rue sous cible dans 3 runs sur 4 |
| Kills/min (TDM Vétéran) | 20,3 | 6,3 à 11,3 | ≥ 6 | Oui |
| Position forte tenue par une seule équipe (max) | non mesurable sur v3 | 18,7–44,4 % | ≤ 35 % | Limite (2 runs sur 4 au-dessus) |
| Morts à ≤ 3 s d'un spawn | 1,6 % | **0,0 % dans les 4 runs enregistrés** | < 5 % | Oui |

Fichiers sources : `reports/bot_bench/ld43_v3.json` (v3) ;
`reports/bot_bench/ld43_v4.json` + `ld43_v4_run2.json` (v4, AVANT le
correctif de portes §2.2 ci-dessous) ; `reports/bot_bench/ld43_v5.json` +
`ld43_v5_run2.json` (v4, APRÈS ce correctif — même carte `wasteland`, même
`data()`, seule la largeur de 5 portes a changé). 4 runs au total pour cette
tâche, tous sur le même layout v4.

**Correction du 1er retour du vérificateur** — les deux lignes suivantes du
tableau v4, dans une version antérieure de ce document, citaient des chiffres
absents des fichiers `reports/bot_bench/*.json` réellement produits :
- « Premier contact médian ... 7,9 à 11,8 s (3 runs) » : FAUX — seuls 2 runs
  v4 existaient alors (`ld43_v4.json` = 7,9 s, `ld43_v4_run2.json` = 11,4 s),
  jamais 11,8 s, jamais un 3ᵉ run. Le tableau ci-dessus n'affiche plus que des
  bornes directement lues dans les fichiers listés.
- « Morts à ≤ 3 s d'un spawn ... 0–5,3 % » : FAUX — `early_death_ratio` vaut
  très exactement `0.0` dans LES QUATRE runs v4 disponibles au dépôt (les 2
  d'origine ET les 2 nouveaux du §2.2), jamais 5,3 %. Corrigé ci-dessus en
  « 0,0 % dans les 4 runs enregistrés ».

Détail des 4 runs (bruts, `jq`/lecture directe des fichiers cités) :

| Run | `first_contact_median_s` | `stuck_time_ratio` | `lane_share` (grand_rue/intérieurs/canyon) | `hp_zone_occupancy_min_ratio` | `early_death_ratio` |
|---|---|---|---|---|---|
| `ld43_v4.json` (avant) | 7,9 s | 3,37 % | 11,9 % / 83,8 % / 4,3 % | 43,7 % | 0,0 % |
| `ld43_v4_run2.json` (avant) | 11,4 s | 3,55 % | 35,1 % / 59,9 % / 5,0 % | 60,8 % | 0,0 % |
| `ld43_v5.json` (après) | 14,2 s | 3,02 % | 18,1 % / 77,9 % / 4,1 % | 74,7 % | 0,0 % |
| `ld43_v5_run2.json` (après) | 10,4 s | 3,13 % | 15,4 % / 78,4 % / 6,2 % | 86,0 % | 0,0 % |

### 2.1 Correction du critère de bug « lanes fantômes » (déjà en place)

`check_wasteland_thresholds` (`tools/bot_bench.gd`) lisait autrefois deux clés
de lane v3 (« crete »/« ravin ») toujours à 0 %, masquant les vraies clés v4
(« interieurs »/« canyon ») du rapport JSON. Déjà corrigé avant ce retour de
vérification — `lane_share` exporte désormais les 3 clés réelles de
`WastelandBots._lanes()`, visibles dans le détail ci-dessus.

### 2.2 Correctif géométrique appliqué pour ce retour (`stuck_time_ratio`)

Seule modification de `scripts/levels/maps/layouts/wasteland.gd` pour cette
correction : les 5 portes d'EchoppesW et les 5 de SaloonW (mirorées
automatiquement vers EchoppesE/SaloonE) sont passées de 1,6 m à 2,4 m — le
HAUT de la fourchette VERROUILLÉE §4 du research (« largeur des lanes...
intérieurs : portes 1,6 à 2,4 m »), jamais un dépassement du spec, et sans
toucher aux pièces à coordonnées verrouillées (Pompe, MuretGouletO/E, §9).
Ces deux bâtiments sont ceux de la lane Intérieurs
(`WastelandBots._lane_interieurs`, hors de mon périmètre de fichiers), la
plus chargée en trafic bot par construction — voir §2.3. `stuck_time_ratio`
passe de 3,37–3,55 % (avant) à 3,02–3,13 % (après) : amélioration réelle et
cohérente sur les 2 runs, mais qui ne suffit pas à passer sous le plafond de
2 % — voir §2.3 pour pourquoi le reste de l'écart est hors de mon périmètre
de fichiers. Régression connue et INCHANGÉE (déjà présente avant ce correctif,
non causée par lui) : `tests/ai/test_wasteland_bot_data.gd::
test_bot_knowledge_corridor_points_are_on_navmesh_and_reachable_from_both_
spawns` échoue d'un point sur 31 (couloir Sud, point #3, décalage 0,85 m pour
une tolérance de 0,5 m) à cause de l'élargissement de `RampeCanyonW2` (fait
avant ce retour de vérification, pour le critère de lane Canyon 4-6,5 s) —
fichier hors de mon périmètre, déjà signalé au lead.

### 2.3 Ce qui N'EST TOUJOURS PAS corrigé par cette tâche, et pourquoi (investigation faite pour ce retour)

Le premier passage de cette tâche avait signalé, sans preuve détaillée, que
`lane_share`/`hp_zone_occupancy`/le reste de `first_contact_median_s`
dépendaient du *comportement* des bots, hors de mon périmètre de fichiers.
Ce retour de vérification demandait de corriger ces critères : voici
l'investigation faite (lecture seule de `scripts/modes/TDMMode.gd` et
`scripts/levels/maps/layouts/wasteland_bots.gd`, aucun des deux dans ma liste
de fichiers) qui montre PRÉCISÉMENT pourquoi la géométrie seule
(`wasteland.gd`) ne peut pas les ramener dans la cible :

- **`lane_share`** : `TDMMode._LANE_BY_MOD4 := ["C", "N", "C", "S"]` affecte
  DE FAÇON FIXE 2 bots sur 4 par équipe à la lane Intérieurs (« C »), 1 à
  Grand-Rue (« N »), 1 à Canyon (« S ») — décision de design documentée
  (`docs/research/08_bots_humanlike.md` §3.6 « Deux bots au Centre... Un au
  Nord, un au Sud »). Même si chaque bot changeait de but à un rythme
  parfaitement uniforme, cette seule répartition donnerait déjà 50 % à
  Intérieurs, AU-DESSUS du plafond de 45 % du critère — avant même de
  compter les traversées. Au-delà de cette base, `TDMMode.
  _wasteland_bot_goal`/`_maybe_trigger_sighting_reaction` envoie n'importe
  quel bot (donc aussi ceux de Grand-Rue/Canyon) enquêter vers la dernière
  position ennemie signalée par l'équipe — et la majorité des contacts ont
  lieu près de la place de la Gare (le « centre disputé » voulu par le
  design, §5 du research), classée « interieurs » par
  `bot_bench.gd::lane_for_goal` (plus proche polyligne). Les deux mécanismes
  vivent entièrement dans `scripts/modes/TDMMode.gd`, hors de ma liste de
  fichiers pour cette tâche.
- **`hp_zone_occupancy_min_ratio`** : passe la cible sur les 2 runs après le
  correctif de portes (74,7 %, 86,0 % contre 43,7 %, 60,8 % avant) — mesure
  encourageante, mais 2 points ne suffisent pas à conclure sur une métrique
  déjà documentée comme très variable d'un run à l'autre (§ tableau
  ci-dessus), et sa logique de tenue/rotation de zone (comportement des bots
  en Hardpoint) reste elle aussi hors de `wasteland.gd`.
- **`first_contact_median_s`** : la part géométrique (distance spawn→front)
  est verrouillée par `tests/maps/test_wasteland.gd::
  test_first_contact_per_lane_within_4_to_6s_and_mirrored` (toujours vert,
  20/20 tests de la suite passent après le correctif de portes). L'écart
  restant vient du comportement réel en combat : tenue de 4 à 10 s à chaque
  point de couloir avant d'avancer (`TDMMode.LANE_HOLD_MIN/MAX`), délais
  d'enquête (0,5 à 1,2 s + `KILL_INVESTIGATE_TTL` 4 s) — encore
  `scripts/modes/TDMMode.gd`.

**Recommandation au lead** (`blocked_on`, voir aussi le rendu de tâche) :
une tâche de suite touchant `scripts/modes/TDMMode.gd` (répartition de lane,
délais de patrouille/enquête) et `scripts/levels/maps/layouts/
wasteland_bots.gd` (poids des hotspots, points de corridor) est nécessaire
pour ramener `lane_share`/`first_contact_median_s` dans les cibles §4 de
`docs/research/11_wasteland_v4_layout.md` — ces fichiers sont hors de la
liste que ce contrat de tâche m'autorise à modifier.

---

## 3. Captures de référence

- 16 vues caméra recalées sur la v4 (aucune dans la géométrie, garde
  automatique `tools/map_shots.gd`), produites lors du 1er passage de cette
  tâche (avant ce retour de vérification) — inchangées par le correctif de
  portes §2.2 (portes intérieures, jamais un mur extérieur ni une pièce
  visible depuis les poses de caméra) :
  `godot --path . -s res://tools/map_shots.gd -- --maps=wasteland --out=<dossier>`
- 4 vues déposées pour cette tâche : `reports/checkpoints/2026-09-25_LD-43/`
  (vue du dessus, Grand-Rue, zone Hardpoint Magasin, Canyon).
- Grille de présence bots (heatmap TDM/Hardpoint Vétéran v4) :
  `reports/bot_bench/ld43_v4_presence.json` (avant correctif) et
  `reports/bot_bench/ld43_v5_run2_presence.json` (après — seul le dernier des
  2 runs après correctif a été conservé sous un nom distinct, le premier a
  été écrasé par `tools/bot_bench.gd` faute de `--presence-out=` explicite
  sur cette invocation) — `tools/heatmap_render.py` pour les rendre en image.
