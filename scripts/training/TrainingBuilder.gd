## TrainingBuilder.gd
## Construit la géométrie STATIQUE du terrain d'entraînement (contract-r4a.md,
## R4-TRAIN) à partir de `TrainingLayout.pieces()`, avec le kit de map
## (`Kit.gd`, lu seul — contract-r4a.md : "built with the map kit"). Même
## patron que `MapSetup._build_geometry` (GeoBatcher : un MeshInstance3D par
## couleur), mais SANS NavigationRegion3D (pas de bots en entraînement) ni de
## GameMode (achat libre, pas de mode — voir BuyMenu.gd, lu seul).
##
## PAS de signalétique en `Label3D` dans le hall : un texte du monde (police/
## contour identiques à un panneau HUD qui, lui, s'affiche très bien) reste
## invisible à l'écran dans cette scène précise — reproduit en isolant le
## bug (un `MeshInstance3D` neuf à la même position/distance s'affiche
## normalement ; un `Label3D` neuf, avec ou sans police personnalisée,
## `billboard`, `no_depth_test`, ne s'affiche JAMAIS une fois GameWorld/HUD
## en place, y compris ajouté après coup — semble un accroc moteur propre à
## Label3D dans ce contexte de rendu D3D12/Forward+, pas un bug de mon code).
## Le repère de direction reste donc une simple bande de sol teintée
## (`accent`) : fiable, et les panneaux CanvasLayer de chaque zone (qui,
## eux, s'affichent bien) prennent le relais dès qu'on approche.
class_name TrainingBuilder
extends Node3D

@export var build_on_ready: bool = true

func _ready() -> void:
	if build_on_ready:
		build()

func build() -> void:
	var batcher := Kit.GeoBatcher.new()
	var palette := TrainingLayout.palette()
	for piece in TrainingLayout.pieces():
		Kit.build_piece(self, batcher, piece as Dictionary, palette)
	batcher.flush(self)
