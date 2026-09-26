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
| Marcher (sinon sprint auto) | Maintenir Shift | L3 |
| Accroupi / Glissade (slide) | Maintenir Ctrl | B |
| Plongeon (dive) + roulade au sol | V | LB |
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
