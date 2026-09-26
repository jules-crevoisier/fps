# Style BD (« façon Borderlands »)

Tranche 2026-09-26 (« il faut tirer vraiment sur Borderlands »). Source unique :
[`toon_style.json`](toon_style.json) v2. Ne recopiez jamais un nombre du JSON à la
main dans un shader/script — passez toujours par `ToonStyle.gd` (Godot) ou
`art/style/blender/_style.py` (Blender).

## Le style en 6 points

1. **L'encre vit dans la texture, pas dans le shader.** Borderlands n'est pas un
   cel-shading à bandes plates : le trait vient de textures peintes qui portent
   déjà les traits/hachures. Reproduit par `art/style/blender/ink_bake.py`
   (bake Cycles pointiness+AO -> composite numpy -> nouvelle texture), **jamais**
   généré procéduralement dans `toon_bd.gdshader`.
2. **Contour fin en post-traitement**, pas par objet. Sobel sur profondeur +
   normales, ~1,5 px à 1080p, qui s'estompe avec la distance
   (`assets/shaders/toon_bd_outline.gdshader` + `ToonOutlineQuad.gd`).
3. **Éclairage réel, ombre affûtée** (pas de paliers) : `smoothstep` resserré
   autour d'un terminator, sur N·L wrappé × l'ombre portée
   (`assets/shaders/toon_bd.gdshader::light()`).
4. **Les ombres sont teintées**, jamais grises : l'albédo est décalé en teinte
   et plus saturé côté ombre (`shadow_tint`).
5. **Couleurs très saturées + étalonnage** : `ToonStyle.environment()` pousse
   `grading.saturation`/`grading.contrast` via `Environment.adjustment_*`
   (jamais un tonemap Filmic, qui désaturerait les hautes lumières).
6. Sources : voir `toon_style.json.references` (VS Squad, Retro Style Games,
   godotshaders.com « 3D edge detection shader Borderlands style », Creative
   Bloq sur Marvel Rivals).

## Portée de cette tranche

Appliqué à **Verrou** (joueur + bots, `scripts/player/PlayerLook.gd`, branche
`"verrou_tex"`), l'arme **Ravage** + les **gants viewmodel**
(`scripts/player/ViewModel.gd` — seule arme de `WeaponDatabase.PATHS`
aujourd'hui) et la carte **Shipment** (`scenes/levels/maps/shipment.tscn` +
`scripts/core/LevelLook.gd`, branche `map_id == "shipment"`). Le contour
post-traitement (`ToonStyle.add_outline_pass`) est posé sur la Camera3D locale
dans `ViewModel._ready()` (différé d'une frame, voir son commentaire) : il
s'applique donc à **tout ce qui est rendu**, y compris les 5 autres agents/
l'ancien pipeline `ink_toon.gdshader` — un doublement léger du contour sur ces
éléments, pas un bug, juste une conséquence d'un post-traitement plein écran.

Le reste du jeu (choc/guet/roseau/vanne/vif, `Cartoon.gd`, `ink_toon.gdshader`
et les 6 autres shaders `ink_*`/`fx_flat`/`ui_halftone`) **n'est pas touché** —
toujours actif, toujours utilisé par ces agents/systèmes. `dev_grid.gdshader`
n'a **pas** été supprimé malgré son retrait de `shipment.tscn` : `Cartoon.gd`
le précharge encore (`Cartoon.dev_grid()`, dispatch `"dev_grid"` dans
`_KIND_ALIASES`), un reliquat de l'ancien pipeline Wasteland (retiré de la
carte mais pas du code) — signalé séparément, hors périmètre de cette tranche.

## Toucher au JSON

Toute valeur de `toon_style.json` se propage automatiquement : `ToonStyle.gd`
(matériau/environnement/soleil/contour côté Godot) et `_style.py` (Blender) le
relisent à chaque appel (`ToonStyle.style()`, `ToonStyle.reload_style()` pour
forcer un rechargement en session éditeur). Aucune valeur numérique n'est
dupliquée en dur ailleurs — sauf les défauts de secours dans
`assets/shaders/toon_bd.gdshader`/`toon_bd_outline.gdshader` (utilisés
seulement si un matériau est créé sans passer par `ToonStyle`), qui doivent
rester synchronisés à la main avec le JSON s'il change.

## Blender : add-on + encrage

**Panneau** (`art/style/blender/bd_style_addon.py`) : le plus simple est
d'ouvrir ce fichier dans l'onglet *Scripting* de Blender (Text Editor > Open)
puis *Run Script* — il s'enregistre pour la session et retrouve ses fichiers
frères (`toon_bd_nodes.py`/`ink_bake.py`/`_style.py`) via son propre chemin sur
disque. Une installation via *Preferences > Add-ons > Install...* ne copie que
ce seul fichier : gardez les quatre fichiers ensemble si vous l'installez ainsi
de façon permanente. Une fois actif : onglet **« Style BD »** dans la barre
latérale (touche N) de la vue 3D —
*« Appliquer le style BD à la sélection »* (matériau ToonBD + contour Line Art
sur chaque maillage sélectionné) et *« Scène d'aperçu BD »* (soleil/ambiance/
étalonnage de la scène courante).

**Encrage d'un nouveau modèle** (le cœur du style) :

```
blender -b --factory-startup --python-exit-code 1 -P art/style/blender/ink_bake.py -- \
    --in assets/models/characters/<modele>.glb \
    --out assets/models/characters/<modele>_inked.glb
```

Bake GPU si possible (`tools/blender/lib/gpu_compute.use_gpu_for_cycles` — HIP
sur le poste de dev), CPU plafonné sinon. Écrit le GLB ré-encré **et** la/les
texture(s) bakée(s) en PNG à côté (jamais le fichier source touché). Déjà
lancé sur `verrou.glb` -> `verrou_inked.glb` et `ravage.glb` -> `ravage_inked.glb`
(captures avant/après dans `reports/checkpoints/2026-09-26_toon_bd/`) — **pas**
branché dans le jeu à la place de l'original : à comparer et valider avant de
remplacer `verrou.glb`/`ravage.glb` eux-mêmes.

## Parité Godot / Blender

`parity_scene` (JSON) décrit une scène commune : sphère rouge, cube bleu,
Verrou, sol, même caméra. Rendue par les deux moteurs, comparée par un script
neutre :

```
"%GODOT%" --path . -s res://tools/style/render_parity_godot.gd -- --out=reports/checkpoints/2026-09-26_toon_bd/parity_godot.png
blender -b --factory-startup --python-exit-code 1 -P art/style/blender/render_parity.py -- --out reports/checkpoints/2026-09-26_toon_bd/parity_blender.png
python tools/style/compare_parity.py --godot .../parity_godot.png --blender .../parity_blender.png --out .../parity_side_by_side.png
```

`render_parity_godot.gd` tourne **fenêtré**, jamais `--headless` (un pilote de
rendu factice ne produit pas de vraie image — le script le détecte et
s'arrête proprement plutôt que de boucler). `compare_parity.py` écrit une
image à 3 volets (Godot | Blender | écart en fausses couleurs) et compare
l'écart absolu moyen à `parity_scene.max_mean_abs_diff` (0,06).

**État actuel (2026-09-26) : écart mesuré ≈ 0,45, hors cible.** Deux causes
identifiées, pas encore résolues :
- le ciel Blender utilise la couleur d'AMBIANCE (`light.ambient_color`, faute
  de concept de ciel dédié pour Blender dans le JSON) alors que Godot utilise
  `palette.sky_blue` — les deux fonds n'ont donc aucune raison de coïncider ;
- le cadrage caméra diffère nettement (FOV/sensor/aspect) : la sphère/le cube
  occupent une fraction de l'image très différente d'un moteur à l'autre.

Le **matériau** lui-même (terminator, teinte d'ombre, rim, spéculaire) est
comparable au premier coup d'œil entre les deux rendus (voir
`parity_side_by_side.png`) — c'est le cadrage/fond qui reste à recaler. Un bug
plus profond a été trouvé et corrigé en cours de route : `apply_toon_bd_to_material`
reconstruisait le groupe de nœuds partagé "ToonBD" à **chaque matériau**,
invalidant les couleurs déjà posées sur les matériaux précédents (tout sauf le
dernier objet traité ressortait NOIR) — `build_toon_bd_node_group` ne
reconstruit plus que si le groupe est vide, ou sur `force_rebuild=True`
explicite.

## Tests

`tests/rendering/test_toon_style.gd` (JSON chargé, paramètres propagés au
matériau, `apply_to` conserve texture/teinte, environnement/soleil/contour) +
`tests/rendering/test_player_look.gd` (bascule `"verrou_tex"` -> ToonStyle,
régression : les 5 autres agents gardent l'ancien pipeline) +
`tests/player/test_viewmodel_toon_style.gd` (Ravage + gants) :

```
addons\gdUnit4\runtest.cmd --godot_binary "%GODOT%" -a res://tests/rendering/test_toon_style.gd -a res://tests/rendering/test_player_look.gd -a res://tests/player/test_viewmodel_toon_style.gd
```
