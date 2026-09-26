## PauseMenu.gd
## Prototype à interface minimale (décision 2026-09-26, "strip to minimal
## prototype") : le menu pause a été supprimé — Échap quitte directement le
## jeu (voir GameHUD.gd). Ce script ne fait plus rien ; il ne reste qu'en
## façade parce que les cartes existantes (scenes/levels/maps/*.tscn, dont
## wasteland.tscn — regénérées séparément, hors périmètre de cette tâche)
## attachent encore ce script à un nœud CanvasLayer : le supprimer casserait
## leur chargement avant cette régénération.
extends CanvasLayer
