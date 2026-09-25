# Pipeline 3D — génération, auto-revue, import Godot

Boîte à outils pour qu'un agent IA en terminal produise des assets 3D
stylisés en Blender **headless** et **VOIE** le résultat avant de l'importer
dans Godot — sans jamais ouvrir l'éditeur Blender. Référence de style unique :
`docs/STYLE_BIBLE.md` (+ `docs/style/tokens.json` quand il existera).

Blender : `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`
(5.1/4.4 aussi installés, mais tout ce dossier est écrit/vérifié pour 5.2).

## 1. La boucle

```
1. Générer         bpy script (make_*.py existant, OU un nouveau via toonkit)
                    └─> assets/models/<famille>/<nom>.glb
2. Vérifier         blender -b -P tools/blender/check_asset.py --
                       --in <glb> [--budget-tris N] [--json OUT.json]
                    └─> lint texte + JSON, exit 1 si échec dur
3. Regarder         blender -b -P tools/blender/turntable.py --
                       --in <glb> [--views 8] [--size 512]
                    └─> <glb>_turntable/<stem>_contact_sheet.png
                    L'agent lit CETTE image (outil Read : les images sont
                    rendues visuellement) — contour visible, 3 bandes de
                    lumière distinctes, pas de zone cramée/noire, silhouette
                    humaine 1,8 m lisible à côté pour l'échelle.
4. Itérer           Retour à 1) si le rendu ne convient pas. Ne JAMAIS juger
                    un asset sur le .glb brut ou sur du code relu : toujours
                    sur la planche-contact.
5. Exporter         Le .glb produit à l'étape 1 EST le livrable (aucune
                    conversion supplémentaire) — il suit déjà les réglages
                    "Godot-friendly" (voir §3).
6. Importer/valider Godot ré-applique le style au runtime par nom de
                    matériau/kind (scripts/core/Cartoon.gd) — les scripts
                    tools/prop_shots.gd et tools/character_shots.gd
                    (`godot --path . -s tools/xxx_shots.gd -- --out=<dossier>`)
                    donnent la vue "dans le jeu, avec le vrai shader"
                    complémentaire de la planche-contact Blender.
```

La planche-contact (étape 3) et les captures Godot (étape 6) répondent à
DEUX questions différentes et complémentaires : "la géométrie/le matériau
brut est-il propre ?" (Blender, avant tout habillage runtime) vs "le rendu
en jeu, avec `ink_toon.gdshader` + `ink_outline.gdshader` + la vraie
lumière de la carte, est-il bon ?" (Godot). Un asset qui échoue à l'étape 6
alors qu'il passait l'étape 3 pointe presque toujours vers un nom de
matériau/kind qui ne correspond à rien côté `Cartoon.gd` (voir §5).

## 2. `tools/blender/lib/toonkit.py`

Bibliothèque commune, importée par `sys.path.insert(...)` (voir l'en-tête de
chaque script de ce dossier). **Ne remplace PAS** `make_weapons.py` /
`make_props.py` / `make_characters.py` / `make_gloves.py` (laissés tels
quels, ils ont leurs propres helpers dupliqués) — sert aux PROCHAINS
générateurs.

Convention d'axes : toutes les primitives construisent **directement en
repère Z-up natif de Blender** (Z = vertical, X/Y = horizontal). Aucune
rotation manuelle n'est nécessaire : `export_glb()` passe `export_yup=True`
à l'exporteur glTF, qui convertit toujours automatiquement ce Z-up natif
en Y-up pour le fichier (`.glb`/Godot). C'est plus simple que la convention
"auteur Y-up + rotation +90°/X" des générateurs existants — un choix
d'écriture qui leur est propre, pas un contrat à reproduire ici.

| Fonction | Rôle |
|---|---|
| `reset_scene()` | Vide la scène + purge les data-blocks orphelins. À appeler en tête de script. |
| `repo_root()` | Racine du dépôt (chemins `assets/…` robustes). |
| `palette(name)` | Couleur RGBA d'un token. Lit `docs/style/tokens.json` s'il existe (clé directe ou sous `"colors"`), sinon une palette de repli alignée sur `docs/STYLE_BIBLE.md` §6.4/§7.7 (avertissement one-shot `TOONKIT_NOTE` si le repli est utilisé — voir §6 ci-dessous). |
| `toon_material(name, color, kind)` | Matériau Principled BSDF nommé `name`. `kind` choisit les réglages PBR d'aperçu (roughness/metallic/alpha) — voir §5 pour le vocabulaire de `kind`. |
| `add_bevel(obj, width, segments, angle_limit_deg=30.0)` | Bevel appliqué, `limit_method='ANGLE'` (défaut 30°, STYLE_BIBLE §7.9/§6.6 — `segments=2` architecture, `1` petit prop). |
| `weighted_normals(obj, weight=50, sharp_angle_deg=30.0)` | Lissage hard-surface : arêtes dures marquées par angle + modificateur `WEIGHTED_NORMAL` appliqué (§7.9). |
| `bake_vertex_ao(obj)` | AO peinte dans un attribut de couleur ("AO", domaine CORNER) via l'opérateur "Dirty Vertex Colors". |
| `curvature_edge_mask(obj)` | 2e attribut de couleur ("Curvature") : même opérateur, plage resserrée sans flou → surbrillances d'arêtes convexes. Heuristique, pas une vraie courbure différentielle. |
| `apply_transforms(obj)` | Applique position/rotation/échelle dans la mesh. |
| `set_origin_bottom(obj)` | Origine au centre-bas de la bbox, sans déplacer la géométrie. |
| `join(objs)` | Fusionne plusieurs objets mesh en un seul. |
| `rounded_box/capsule/tapered_cylinder/blob(...)` | Primitives (voir docstrings). |
| `tri_count(objs)` | Triangles (ngons en éventail). |
| `export_glb(path, objs)` | Export Godot-friendly : Y-up, modifieurs appliqués, matériaux + TOUTES les color_attributes (AO/Curvature), sans caméra/lumière/anim. |

## 3. `tools/blender/turntable.py`

```
blender -b -P tools/blender/turntable.py -- --in PATH.glb|.blend
    [--out DIR] [--views 8] [--size 512]
```

Importe une COPIE en mémoire (jamais de réécriture du fichier source),
cadre automatiquement (bbox combinée asset + silhouette humaine 1,8 m),
rend `--views` vues en orbite + 1 vue de dessus + 1 gros plan avec :

- **Rendu "3 bandes + encre"** : Shader-to-RGB → Color Ramp (interpolation
  `CONSTANT`, donc des paliers francs) → multiplié par l'albédo d'origine de
  chaque matériau importé (jamais l'albédo réel n'est modifié dans le
  fichier source — tout ceci est reconstruit en mémoire pour CE rendu).
  Teinte d'ombre bleu-violet (`palette("shadow_tint")`), bande médiane
  éclaircie ("hot edge").
- **Contour à l'encre** : Freestyle (silhouette + bordure + arêtes vives +
  frontière de matériau), pas de coque inversée par objet — s'applique
  uniformément à n'importe quel asset importé.
- **Fond gris neutre**, sol + silhouette humaine 1,8 m à côté pour l'échelle.

Compose tout en UNE planche-contact PNG (grille + légendes : vues, tri
count, dimensions en mètres, liste de matériaux) — chemin imprimé **seul**
sur la toute dernière ligne de sortie.

**Correctif TOOL-01 (2026-09-25).** Un matériau dont la Base Color est liée
à une image (`_find_albedo_image` — directement, comme tout matériau
`<id>_painted` de `paint_bake.py` ci-dessous, ou via le montage vertex-color
× albédo de `bake_vertex_ao`/`curvature_edge_mask`) affiche désormais **sa
vraie texture** dans l'aperçu 2 tons, au lieu de l'aplat bleu-gris constaté
avant ce correctif (`_read_albedo` seule ne reconnaissait que le second
montage, jamais une image liée directement — le cas de tout asset peint).

## 4. `tools/blender/paint_bake.py` — peinture automatique (TOOL-01)

```
blender -b -P tools/blender/paint_bake.py -- --in X --out Y \
    [--res 1024|2048] [--palette kind] [--margin-px 4] [--bake-margin-px 8] \
    [--samples 24] [--seed 0] [--hue-max-deg 6] \
    [--skip-turntable] [--views 8] [--size 512]
```

Cuit une texture albédo « peinte à la main » (Cycles, bake `EMIT`) sur
N'IMPORTE QUEL modèle `.glb`/`.gltf`/`.blend` d'entrée, sans peintre et sans
Substance — outil maison demandé par l'utilisateur le 2026-09-25 (« crée-toi
des outils en surcouche de Blender… »). Ne modifie jamais le fichier source
(import en mémoire, comme les autres scripts de ce dossier).

Par objet mesh de l'asset importé :

1. **UV dédiée à la cuisson, toujours.** Smart UV Project systématique
   (marge `--margin-px` px à la résolution `--res`) vers un calque UV FRAIS,
   jamais une UV existante réutilisée telle quelle — bogue réel constaté en
   écrivant ce script (`wall_1_level.glb`, kit shanty) : sa projection boîte
   à l'échelle du monde (`Cartoon.prop_uv()`, tuilée par construction) fait
   PARTAGER la même petite région UV à plusieurs planches, laissant la
   majeure partie du canevas de cuisson inutilisée (~49 % de pixels noirs
   mesurés). L'UV d'origine est retirée après l'unwrap (`ensure_uv`).
2. **Îles UV** par connexité UV réelle (deux faces adjacentes ne sont dans la
   même île que si leurs UV coïncident aux deux extrémités de l'arête
   partagée — distinct d'une île de maillage), `compute_uv_face_islands`.
3. **Teinte par île**, décalage déterministe (`island_hue_offset`, hash
   SHA-256 de la graine + nom d'objet + index d'île, jamais un `random` non
   seedé) baké dans un attribut de couleur temporaire, retiré après la
   cuisson — comme TOUT attribut de couleur préexistant (AO/Curvature d'un
   générateur d'origine) : un `COLOR_0` de primitive glTF est toujours
   multiplié dans le baseColor par tout consommateur conforme (dont Godot),
   ce qui redoublerait à tort l'AO déjà cuite dans la nouvelle texture (bogue
   réel constaté sur `oil_drum.glb`).
4. **Shader de cuisson** par slot de matériau d'origine : couleur de base =
   texture peinte existante échantillonnée TRIPLANAIRE (comme
   `Cartoon.painted()`/`ink_toon.gdshader`) si le slot en porte une, sinon
   `toonkit.palette(kind)` ; decalage de teinte par île ; creux AO+Pointiness
   assombris et **teintés** (mélange vers `palette("shadow_tint")`, jamais un
   simple facteur gris, §7.2) ; arêtes convexes éclaircies ; trait d'encre
   fin sur les arêtes très vives ; dégradé de lumière vertical (bbox objet
   normalisée) ; grain de coups de pinceau (Noise Texture, espace objet).
5. **Cuisson** : une image partagée par objet, un seul `bpy.ops.object.bake
   (type='EMIT')` — Cycles évalue chaque face avec le matériau du slot
   d'origine correspondant, toutes vers la même image/UV.
6. **Matériau final** : un seul par objet, nommé `<id>_painted` (ou
   `<id>_painted_N` au-delà du premier objet) — convention DÉJÀ reconnue côté
   jeu par `scripts/player/ViewModel.gd`/`ThirdPersonWeapon.gd`
   (`name.contains("_painted")` → `Cartoon.painted_texture_prop()`).
7. **Export** : `toonkit.export_glb` (.glb + rapport JSON), puis sidecar
   augmenté (`"painted": true`, `"source"`, `"res"`, îles/slots cuits par
   objet — même idée que `ai_import_painted.py::_augment_sidecar`).
8. **Turntables** avant (fichier source) / après (sortie peinte), en
   sous-process, comme `ai_restyle.py::run_turntable` — sauf
   `--skip-turntable`.

Testé (`tools/blender/tests/test_paint_bake.py`) : UV présentes, texture non
uniforme, aucun pixel hors bande de teinte réservée, aucune île préexistante
en tuile réutilisée telle quelle (régression), texture triplanaire sur slot
déjà peint, variation de teinte déterministe par île, fusion multi-slots, et
le correctif `turntable.py::_find_albedo_image` ci-dessus.

## 5. `tools/blender/check_asset.py`

```
blender -b -P tools/blender/check_asset.py -- --in PATH
    [--budget-tris N] [--json OUT.json]
```

Lint texte + JSON. **Échecs durs** (`exit 1`) : aucun mesh, mesh vide,
budget de triangles dépassé, sommets orphelins, arêtes non-manifold "dures"
(≥ 3 faces sur une même arête). Tout le reste (origine hors centre-bas,
transform non appliqué, UV absentes, noms de matériau inconnus, vertex
colors absents, normales suspectes) est un **avertissement** : ce sont des
conventions qui varient légitimement entre familles d'assets (une arme n'a
pas son origine au sol, un baril n'a pas forcément d'UV s'il ne vit que de
vertex colors, etc.).

## 6. Conventions

**Échelle :** 1 unité Blender = 1 mètre (partagé avec Godot). Origine :
props/décor = base centrée au sol (`set_origin_bottom`) ; armes = poignée
(voir `make_weapons.py`) ; gants = point de contact (voir `make_gloves.py`).
Ces deux dernières conventions sont **volontairement** hors du "centre-bas"
générique — `check_asset.py` ne les pénalise que d'un avertissement, jamais
d'un échec dur.

**Nommage des matériaux** (`docs/STYLE_BIBLE.md` §7.9, `f"{id}_{slot}"`) :
cible v3 = 5 slots génériques `base`/`accent`/`metal`/`glass`/`sign`.
`scripts/core/Cartoon.gd` **actuel** (celui qui tourne vraiment aujourd'hui,
la migration v3 n'est pas faite) reconnaît en plus les kinds peints
texturés de `Cartoon._PAINTED` : `painted_metal`, `rust`, `corrugated_metal`,
`container_paint`, `wood_planks`, `sand_dirt`, `cracked_concrete`, `asphalt`,
`ship_deck`, `rubber_tire`, `dirty_glass` — ainsi que les slots persos
(`skin`/`cloth`/`outfit`/`gear` via `character_surface`) et les slots
historiques armes/gants (`body`/`grip`/`metal`/`accent`/`glove`/`cuff`,
recolorés par `Cartoon.character()`/`prop()`, pas par un "kind" peint).
`toon_material(name, color, kind)` accepte les deux vocabulaires ; un `kind`
inconnu retombe sur `"flat"` avec un avertissement `TOONKIT_WARN`.

**Palette :** `toonkit.palette(name)` lit `docs/style/tokens.json` s'il
existe. **Il n'existe pas encore** au moment d'écrire ce document — la
palette de repli de `toonkit._FALLBACK_PALETTE` est utilisée à la place
(tokens `Cartoon.gd`/`STYLE_BIBLE.md` §6.4, ex. `ink`, `shadow_tint`,
`sand_dirt`, `container_red/blue/orange/white`, les kinds peints). Si
`tokens.json` apparaît (un autre agent peut l'écrire en parallèle), il prend
automatiquement le dessus — aucun changement de code requis. Le premier
appel qui retombe sur le repli imprime `TOONKIT_NOTE` une seule fois.

**Budgets/biseaux/densité de texels par famille** — `docs/STYLE_BIBLE.md`
§6.6 fait référence, résumé ici :

| Famille | Densité texel | Biseau | Budget tris (LOD0) |
|---|---|---|---|
| Architecture, skins (≥ 3 m) | 256 px/m (trim-sheet) | 6 cm, 2 segments | ≤ 6 000 |
| Props moyens (1–3 m) | 256 px/m | 4 cm (conteneur), 2,5 cm (caisse) | 800–3 000 |
| Petits props (< 1 m) | 256 px/m | 1,2 cm | 200–800 |
| Repères | 256 px/m + décalques 512 px/m | 6–8 cm | ≤ 15 000 |
| Personnage | 384 px/m (tête 512 px/m) | 1 cm | ≤ 15 000 (tête ≤ 3 000) |
| Arme FP / TP | 512 px/m / 128 px/m | 3 mm / 1 cm | 8–12 000 (+ gants 5 000) / 1 200–2 000 |

`tools/blender/examples/make_sample_prop.py` (caisse + baril, tous deux
"petits props") illustre le budget 200–800 tris et le biseau 1,2 cm.

## 7. Assets générés par une IA externe (import futur)

Un maillage produit par un outil externe (image/texte → 3D) entre dans la
MÊME boucle, avec une étape d'adaptation en plus AVANT `check_asset.py` :

```
import (.glb/.obj/.fbx)
  -> decimate (Decimate modifier, ratio visé selon le budget §6, appliqué)
  -> restyle materials (remplacer CHAQUE matériau importé par
     toonkit.toon_material(name, couleur_moyenne_du_matériau_d_origine, kind)
     — jamais garder les textures PBR importées telles quelles : ce jeu
     n'a pas de textures baked par mesh, tout passe par les "kinds" peints
     de Cartoon.gd, voir §6)
  -> toonkit.apply_transforms + set_origin_bottom (l'import externe a
     presque toujours une échelle/origine à corriger)
  -> check_asset.py (--budget-tris selon la famille, §6)
  -> turntable.py (même regard qu'un asset "maison")
```

Rien de spécifique à cette provenance ne doit fuiter plus loin dans le
pipeline : une fois passé par `restyle materials` + `check_asset.py` vert,
l'asset est indiscernable d'un asset construit à la main avec `toonkit`.

## 8. Personnages Tripo riggés (`rig_tripo_character.py`)

Un agent jouable peut aussi partir d'un maillage **déjà habillé et texturé**
livré par Tripo (image→3D, "forme seule" : un seul matériau, une texture 2K
bakée, aucun squelette) plutôt que d'un vêtement construit à la main sur le
mannequin nu (voie de `make_characters.py`, §1-3, §5-6). Contrairement à la voie
générique du §7 (repeindre chaque matériau importé avec `toonkit`), ici la
texture peinte est **conservée telle quelle** — c'est tout l'intérêt de
partir d'un Tripo déjà texturé plutôt que "forme seule".

```
1. Aperçu en jeu  godot --path . -s res://tools/review/model_preview.gd --
                     --in=<glb Tripo> [--enemy]
                   └─> planche face/3-4/profil/dos/gros-plan À CÔTÉ d'une
                       capsule témoin (0,40 m rayon, 1,80 m haut) — validation
                       utilisateur AVANT tout rig (proportions, silhouette,
                       lisibilité de la texture).
2. Rig + skin     blender -b -P tools/blender/rig_tripo_character.py --
                     --in <glb Tripo> --id <agent_id>
                  └─> assets/models/characters/<agent_id>.glb
3. Vérifier       blender -b -P tools/blender/check_asset.py --
                     --in <sortie> --budget-tris 15000
4. Regarder       godot --path . -s tools/character_shots.gd -- --out=<dossier>
                  └─> Idle + 3/4 + Sprint dans le VRAI shader (ink_toon +
                      contour), planche relue à l'œil (épaules/poncho/
                      chapeau sans étirement — jamais jugé sur le .glb brut).
```

**`rig_tripo_character.py`** (voir sa docstring de tête pour le détail
mesure-par-mesure) prend un .glb Tripo `--in` et un `--id` d'agent, et :

1. **Répare les arêtes non-manifold** (échec dur de `check_asset.py`) par
   suppression ciblée de la plus petite face en cause à chaque arête à ≥ 3
   faces — pas une simple fusion par distance (voir sa docstring : sur
   `verrou_v1.glb`, les 21 arêtes en défaut forment un repli de géométrie
   superposée sur ~5 cm, pas des sommets quasi-coïncidents ; la fusion seule
   en corrige certaines et EN CRÉE d'autres ailleurs). L'export glTF d'un
   maillage skinné peut lui-même réintroduire quelques arêtes non-manifold
   (sommets de couture UV dont les poids d'os quantifiés finissent par
   coïncider) : le script réexporte, réimporte et répare le FICHIER RÉEL en
   boucle jusqu'à convergence (jamais l'état en mémoire, cf. §1).
2. **Recale au gabarit commun** : 1,80 m pieds à l'origine (mêmes seuils que
   `docs/STYLE_BIBLE.md` §4), squelette commun (UAL-G, mêmes 46 actions que
   `make_characters.py`, importé de la même source `ual.glb`) mis à l'échelle
   sur la même hauteur.
3. **Repose les bras** de la T-pose de repos du squelette commun vers une
   pose relâchée le long du corps, PUIS applique cette pose comme nouveau
   repos de CET agent (`armature_apply`) — nécessaire pour que la liaison
   par poids automatiques (étape suivante) capture les bras au lieu de tout
   assigner au torse le plus proche (les bras du maillage Tripo pendent le
   long du corps, pas en croix comme la T-pose de repos). N'affecte que le
   fichier de CET agent ; les 46 actions restent celles de `make_characters.py`
   pour les 5 autres.
4. **Lie le maillage au squelette par poids automatiques** (`ARMATURE_AUTO`,
   seule option praticable sur un maillage Tripo sans groupes de sommets
   préexistants — l'alternative offerte par le contrat, un transfert de poids
   depuis le mannequin UAL, n'a pas été retenue pour cette passe). Liaison
   calculée sur une copie fusionnée par distance jetable (le solveur de poids
   de Blender échoue TOTALEMENT sur la densité de sommets dupliqués aux
   coutures d'un maillage Tripo non fusionné), puis transférée sur le
   maillage réel par correspondance de position — jamais le maillage réel
   n'est fusionné (perte d'UV à chaque couture).
5. **Renomme l'unique matériau** en `f"{agent_id}_tex"` — texture 2K gardée
   intacte, aucun repeint (contrairement aux slots `outfit`/`cloth`/`gear`/
   `skin`/`accent` plats de `make_characters.py`).
6. **Exporte** avec les 46 actions (`export_animation_mode='ACTIONS'`,
   `export_apply=False` — mêmes réglages que `make_characters.py`).

**Convention `*_tex`** (lue par `scripts/player/PlayerLook.gd` et
`tools/character_shots.gd`, même technique que
`tools/review/model_preview.gd::_restyle`) : un matériau dont le nom se
termine par `_tex` garde son `albedo_texture` au lieu d'être repeint en
aplat, et son `paint_grain_strength` est forcé à 0 (la texture porte déjà le
détail peint, le grain de `Cartoon.character_surface`/`character()` le
doublerait). Un agent Tripo n'a donc PAS de slot `cloth` dédié à la couleur
d'équipe — le contour d'équipe (`Cartoon.apply_team_outline` en jeu,
`Cartoon.character()` dans `character_shots.gd`) reste la SEULE information
d'équipe qu'il porte.

**Limite connue** : l'ajustement des proportions du squelette au modèle se
limite à une mise à l'échelle UNIFORME (même hauteur totale que le
mannequin de référence) — un ajustement fin par membre (longueur de jambe/
bras individuelle) demanderait une détection de repères anatomiques sur un
maillage sans squelette existant, hors budget de cette passe. La liaison par
poids automatiques compense raisonnablement les écarts de proportion
restants pour un jeu stylisé en cel-shading ; la vérification reste visuelle
(étape 4 ci-dessus), pas un seuil numérique.

## 9. Limitations connues

- `turntable.py`/`check_asset.py` travaillent sur une **copie en mémoire** :
  un `.blend` source lié à des données externes (images, autres fichiers
  `.blend`) peut se comporter différemment une fois rouvert seul.
- Le rendu "3 bandes" de `turntable.py` est une **approximation** du vrai
  `ink_toon.gdshader` (voir §1 : les deux se complètent, ne se remplacent
  pas) — ne pas y chercher le rendu final au pixel près.
- `curvature_edge_mask` est une heuristique (deux passes de l'opérateur
  "Dirty Vertex Colors" à plages d'angle différentes), pas un calcul de
  courbure différentielle.
