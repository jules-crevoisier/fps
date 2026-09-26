# FPS — prototype

Prototype de FPS en ligne (Godot 4.7, GDScript), style cel-shading peint. Le jeu
démarre directement en partie locale : Team Deathmatch sur la carte **Shipment**
(cour à conteneurs), joueur + 3 bots alliés contre 4 bots ennemis (difficulté
Vétéran). Un seul agent jouable (Verrou), une seule arme (Ravage). Pas de menu,
pas de boutique, pas de capacités — juste le mouvement, le tir et les bots.

## Lancer le jeu

1. Ouvrir le dossier du projet dans Godot 4.7 (`C:\Users\srko\Desktop\Godot_v4.7-stable_win64.exe`),
   ou double-cliquer `project.godot`.
2. Appuyer sur **F5**. La partie s'héberge et démarre toute seule
   (`scenes/boot.tscn` → `scripts/core/QuickStart.gd`).
3. **Échap** quitte le jeu.

Pour tester le réseau à deux fenêtres : **Debug → Run Multiple Instances → Run 2
Instances**, puis **F5** dans chacune (la première héberge, la seconde rejoint
en LAN).

## Contrôles

| Action | Clavier (ZQSD/AZERTY → WASD/QWERTY) | Manette |
|---|---|---|
| Déplacement | Z/Q/S/D (W/A/S/D) | Stick gauche |
| Regarder | Souris | Stick droit |
| Sauter | Espace | A |
| Sprint façon Apex (un appui ; reste actif jusqu'à l'arrêt, reprend seul après tir/visée) | Shift | L3 |
| Accroupi / Glissade (slide) | Maintenir Ctrl | B |
| Dash dans la direction des touches (ZQSD) + roulade qui garde l'élan | V | LB |
| Tirer / Viser (ADS) | Clic gauche / Clic droit | RT / LT |
| Recharger | R | X |
| Quitter | Échap | Start |

Le mouvement est hybride : sprint automatique, glissade qui accélère en pente,
slide-cancel pour garder l'élan, air-strafe façon CS/Valorant, et un plongeon
suivi d'une roulade de réception (annule l'étourdissement de chute si le timing
est bon).

## Lancer les tests

Suite gdUnit4 (headless) :

```
"C:\Users\srko\Desktop\Godot_v4.7-stable_win64.exe" --headless --path . --import
bash tools/test.sh
```

`tools/test.sh` lance d'abord le garde-fou de licence des assets 3D
(`tools/ai3d/licence_check.py`), puis toute la suite sous `res://tests`. Pour ne
lancer qu'un dossier : `GODOT_BIN=<chemin> tools/test.sh res://tests/ai`.

La CI (`.github/workflows/ci.yml`) enchaîne : import, suite gdUnit4, sonde de
gameplay headless (`tools/review/gameplay_probe.gd` + `tools/review/report.py`),
export Windows/Linux/serveur, puis build + healthcheck de l'image Docker.

## Importer un modèle Tripo

1. **Réception automatique** (Tripo Studio → Blender) : lancer Blender avec le
   watcher du DCC Bridge —

   ```
   "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --factory-startup \
       --python tools/ai3d/bridge_autoexport.py
   ```

   Dans Tripo Studio, *Exporter → Envoyer à Blender* : chaque modèle envoyé est
   récupéré automatiquement dans `assets/incoming/tripo/studio/<nom>.glb`
   (journal : `assets/incoming/tripo/studio/_bridge_log.txt`). L'extension
   « Tripo Bridge » doit être installée une fois dans le dossier d'extensions
   utilisateur de Blender 5.2.

2. **Import « peinture conservée »** (garde la texture peinte, redimensionne à
   une hauteur cible, respecte un budget de triangles) :

   ```
   "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup \
       --python-exit-code 1 -P tools/blender/ai_import_painted.py -- \
       --in assets/incoming/tripo/studio/<nom>.glb --height-m 2.0 \
       --budget-tris 6000 --texture-size 2048 \
       --out assets/models/props/<nom>.glb
   ```

3. **Traçabilité de licence** : tout fichier sous `assets/models/**` doit avoir
   soit une ligne dans `THIRD_PARTY_LICENSES.md`, soit un
   `<nom_du_fichier>.provenance.json` à côté (voir ce fichier pour le format).
   Sans l'un des deux, `tools/ai3d/licence_check.py` (et donc `tools/test.sh`)
   échoue.

## Personnage : régler l'arme et les animations

Le personnage tiers (bots, joueurs distants, votre propre corps vu par les
autres) est **Frog Cowboy** (`assets/models/characters/frog_cowboy.glb`,
squelette Mixamo peint par vos soins). Il est chargé depuis une scène éditable,
`scenes/characters/frog_cowboy.tscn`, plutôt que directement depuis le `.glb` —
c'est là que vous réglez la position de l'arme et que vous prévisualisez les
animations, sans jamais toucher au modèle lui-même.

### Déplacer/tourner l'arme dans la main

1. Ouvrir `scenes/characters/frog_cowboy.tscn` dans l'éditeur Godot.
2. Dans le panneau Scène, déplier `frog_cowboy > Armature > Skeleton3D >
   BoneAttachment3D` et sélectionner **`WeaponSocket`** (un `Node3D` simple,
   attaché à l'os `WeaponGrip`, un enfant de la main droite retargetée
   `RightHand` dont les axes sont déjà orientés canon-vers-l'avant — laissez
   son transform à l'identité sauf besoin réel d'ajustement fin).
3. Utiliser le gizmo de déplacement/rotation (barre d'outils 3D en haut, ou
   `W`/`E`) pour ajuster la position et l'angle : l'arme (Ravage) vient se
   greffer exactement sur le transform local de ce nœud, sans aucun décalage
   caché ailleurs dans le code.
4. **Enregistrer (`Ctrl+S`)**.
5. Lancer le jeu (`F5` ou le bouton ▶) pour vérifier en situation, sur un bot
   ou un pair distant (votre propre corps ne s'affiche jamais à la première
   personne — c'est `PlayerLook.gd`/`ThirdPersonWeapon.gd` qui gèrent ça).

### Prévisualiser une animation

Toujours dans `frog_cowboy.tscn` : sélectionner le nœud **`AnimationPlayer`**
(généré automatiquement par l'import glTF dès que `frog_cowboy.glb` embarque
des clips — frère d'`Armature`), ouvrir le panneau **Animation** en bas de
l'éditeur, choisir un clip dans la liste déroulante (`Idle`, `Walk`,
`Jog_Fwd`, `Sprint`, `Death01`, `Rifle_Reload`, ...) puis appuyer sur ▶
(lecture) pour le voir tourner directement sur le squelette dans la vue 3D.

Les clips sont EMBARQUÉS nativement dans `frog_cowboy.glb` (authored en
Blender par le lead, pas de retargeting) : `scripts/import/
FrogCowboyPostImport.gd` renomme leurs pistes (`mixamorig_*` -> noms de
profil humanoïde, même table que le squelette) et force le mode de boucle des
clips qui bouclent réellement en jeu à chaque réimport. L'ancien chemin
« retargeting UAL » (`tools/rigging/bake_frog_animations.gd`,
`resources/agents/anim/frog_cowboy_humanoid.tres`,
`assets/incoming/quaternius/ual.glb`) est abandonné pour Frog Cowboy — ces
fichiers restent sur disque (nettoyage prévu plus tard) mais ne sont plus
utilisés au runtime.

### Réexporter le modèle depuis Blender

Si vous retouchez la peinture (texture) ou le maillage dans
`art/characters/frog_cowboy/frog_cowboy_paint.blend` :

```
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b art/characters/frog_cowboy/frog_cowboy_paint.blend \
    -P art/characters/frog_cowboy/export_frog.py
```

Ceci régénère `assets/models/characters/frog_cowboy.glb` avec **le même rig
Mixamo inchangé** (l'armature du `.blend` est exportée telle quelle) — tant
que vous ne touchez pas aux noms d'os ni à la hiérarchie de l'armature, tout
le reste (retargeting, `WeaponSocket`, animations) continue de fonctionner
sans rien recalculer. Si Godot ne voit pas le nouveau fichier tout de suite,
rouvrir le projet (ou attendre le prochain scan du système de fichiers)
suffit à le réimporter.

## Repère du dépôt

- `scenes/`, `scripts/` — le jeu : `scripts/core` (boot, réglages, style),
  `scripts/player`/`movement` (déplacement + arme vue-première-personne),
  `scripts/networking` (autorité serveur, spawns, sync), `scripts/modes`
  (Team Deathmatch), `scripts/ai` (bots), `scripts/levels/maps` (carte
  Shipment : `MapSetup.gd` bake juste la navmesh + instancie le mode ; la
  géométrie elle-même vit dans `scenes/levels/maps/shipment.tscn`, une scène
  normale éditable dans Godot).
- `assets/` — modèles, textures, shaders, audio, polices livrés avec le jeu.
- `resources/` — ressources `.tres` (armes, agents, mouvement, entrées, UI).
- `tests/` — suite gdUnit4 (`tests/<domaine>/test_*.gd`).
- `tools/ai3d/`, `tools/blender/` — import de modèles Tripo (voir ci-dessus) et
  garde-fou de licence.
- `tools/review/` — sonde de gameplay headless utilisée par la CI.
- `addons/gdUnit4/` — framework de test.
- `Dockerfile`, `docker-compose.yml` — image du serveur dédié (Dokploy).
