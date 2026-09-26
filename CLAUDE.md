# Projet FPS (Godot 4.7) — instructions de session

Prototype de FPS rapide en cel-shading. Base volontairement minimale (remise à zéro du 2026-09-26,
état précédent complet dans le tag git `avant-nettoyage-2026-09-26`) :

- démarrage direct en partie TDM 4v4 contre des bots (`scenes/boot.tscn` → `scripts/core/QuickStart.gd`) ;
- une carte : **Shipment** (`scenes/levels/maps/shipment.tscn`), scène Godot ordinaire, éditable dans
  l'éditeur (pas de génération procédurale), centrée sur l'origine ; points d'apparition = `Marker3D`
  sous `SpawnPoints` (méta `team`), navigation = `NavigationRegion3D` « NavRegion » ;
- une arme (Ravage), un personnage (Verrou, la grenouille), aucune capacité ;
- aucune interface hors réticule et marqueur de touche.

**L'utilisateur crée lui-même les cartes et les modèles.** Ne pas générer de décor, de textures ni de
cartes sans demande explicite ; se concentrer sur le code de jeu (mouvement, tir, sensations, bots,
réseau) et sur l'intégration de ce qu'il fournit.

## Où est quoi

- Mode de jeu : `scripts/modes/` (TDM seul). Réseau : `scripts/networking/` (hôte/client, serveur
  dédié `ServerBoot.gd`). Joueur : `scripts/player/` (états de mouvement). Tir : `scripts/combat/`.
  Bots : `scripts/ai/`. Chargement de carte : `scripts/levels/maps/MapSetup.gd`.
- Import de modèles Tripo : `tools/ai3d/bridge_autoexport.py` (Blender en arrière-plan, reçoit le DCC
  Bridge) et `tools/blender/ai_import_painted.py` (import peint) — voir README. Licences des assets :
  `THIRD_PARTY_LICENSES.md` + `python tools/ai3d/licence_check.py` (0 violation exigé).
- Godot : `C:\Users\srko\Desktop\Godot_v4.7-stable_win64.exe`. Blender :
  `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`.

## Règles propres au projet

- Réseau autoritaire serveur ; l'hôte et les bots sont simulés côté serveur.
- Tests : gdUnit4 (`bash tools/test.sh`, ou un dossier : `tools/test.sh res://tests/<dir>`). Tests
  ciblés pendant l'itération, suite complète avant un commit. Les tests UI se lancent avec
  `--ignoreHeadlessMode`.
- Écrire les modifications de fichiers en UTF-8 (jamais `Set-Content` PowerShell sans
  `-Encoding utf8`).
- Budget d'usage : un seul agent à la fois (deux au plus), modèle économique par défaut ; faire
  soi-même les petites modifications ; annoncer l'ampleur avant toute vague plus grosse.
- Toute modification visible se vérifie en capture d'écran avant d'être déclarée finie.
- Branche de travail : `feature/aaa-roadmap` (jamais `main`). Commit et push sur demande ou en fin
  d'étape validée, format `{type} | {description}`.
