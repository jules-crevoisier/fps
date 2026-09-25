## WastelandArt.gd
## ART-91 (fondation) — registre de la passe d'art v4 de Wasteland
## (docs/art/WASTELAND_V4_ART_PLAN.md §0 "coexistence de l'art et de la
## collision" / §6 "tâches"). Charge, DANS L'ORDRE de `MODULE_PATHS`, chaque
## module visuel-seul déclaré ci-dessous S'IL EXISTE — aucun n'existe encore à
## cette tâche (ART-94..100, vagues 2 et 3) : `load_modules` ne fait alors
## RIEN d'observable, comportement neutre verrouillé par
## `tests/maps/test_wasteland_art_parity.gd::test_collision_hash_identical_
## with_and_without_art`.
##
## Contrat imposé à CHAQUE futur module (§1 R9, "mise en œuvre") :
##   - une fonction STATIQUE `apply(parent: Node3D, data: Dictionary) -> void`,
##     `parent` = le `NavigationRegion3D` réel de `MapSetup` (mêmes enfants
##     que `Kit.build_piece`/`GeoBatcher.flush`), `data` = `WastelandLayout.
##     data()` déjà assemblée par `MapSetup._assemble_wasteland` ;
##   - PUREMENT VISUEL : ne pose jamais de `CollisionObject3D` ("Aucun
##     CollisionObject3D ajouté dans les bornes (la navmesh ne lit que les
##     collisions statiques)", §1 R9) — vérifié par la même sonde (comparaison
##     bit-à-bit de la collision réellement posée par `MapSetup`/`Kit`, avant/
##     après `load_modules`) ;
##   - une pièce qu'un module remplace ENTIÈREMENT porte `"visual": false`
##     dans `wasteland.gd` (Kit.gd, ADDITIF, ART-91) : `Kit.build_piece` pose
##     alors sa collision comme toujours, mais bascule son propre rendu vers
##     un `GeoBatcher` jetable — jamais deux visuels superposés (le Kit brut
##     ET la peau d'art) pour la même pièce ;
##   - l'ORDRE de `MODULE_PATHS` EST le contrat : bâtiments 1 niveau avant les
##     2 niveaux/Wagon (§6, vague 2), puis volumes pleins/couverts, puis sol,
##     roches/falaises/fond, repères/habillage (vague 2 fin), enfin
##     l'intégration finale (vague 3) — un module qui dépend d'un décor posé
##     par un module PRÉCÉDENT (ex. les repères sur le sol du Wagon) peut
##     compter sur cet ordre sans le redéclarer lui-même.
##
## `is_enabled()` (§1 R9 "art sauté en headless") : même lecture que
## `Settings.gd` (l.581/614, seule autre occurrence de `DisplayServer.
## get_name()` du dépôt) — vrai sur le serveur dédié (`ServerBoot.gd`, TOUJOURS
## lancé `--headless`, réseau autoritaire serveur) ET sous gdUnit4 (le contrat
## de tâche impose `--headless` à CHAQUE lancement de test) : les deux évitent
## le coût CPU/texture d'un rendu jamais affiché côté serveur, et le bruit
## connu "material is null" (rendu factice headless sur les cartes repeintes).
## `apply_all` (le hook de `MapSetup._enter_tree`) respecte ce garde ;
## `load_modules` (la mécanique nue, ci-dessous) ne le fait PAS EXPRÈS — elle
## reste exposée séparément pour que la sonde de parité puisse exercer le VRAI
## dispatcher sous gdUnit4 (toujours headless) sans jamais dépendre d'un rendu
## réel : un test qui ne passerait QUE parce que `is_enabled()` court-circuite
## tout ne prouverait rien sur le dispatcher lui-même.
class_name WastelandArt
extends RefCounted

## Ordre de la passe d'art (docs/art/WASTELAND_V4_ART_PLAN.md §6 "tâches",
## vague 2 puis 3). Un chemin qui ne résout à aucun script
## (`ResourceLoader.exists` faux) est silencieusement ignoré — c'est l'état
## NORMAL avant que sa tâche ne livre le fichier ; ce registre n'a donc jamais
## besoin d'être retouché quand ART-94..100 ajoutent leur module, tant qu'ils
## utilisent le nom de fichier déjà réservé ici.
const MODULE_PATHS: PackedStringArray = [
	"res://scripts/levels/maps/wasteland_art/ArtBuildings1F.gd",   # ART-94
	"res://scripts/levels/maps/wasteland_art/ArtBuildings2F.gd",   # ART-95
	"res://scripts/levels/maps/wasteland_art/ArtCovers.gd",        # ART-96
	"res://scripts/levels/maps/wasteland_art/ArtGround.gd",        # ART-97
	"res://scripts/levels/maps/wasteland_art/ArtRocksBackdrop.gd", # ART-98
	"res://scripts/levels/maps/wasteland_art/ArtLandmarks.gd",     # ART-99
	"res://scripts/levels/maps/wasteland_art/ArtDressing.gd",      # ART-99
]

## Vrai hors du serveur dédié/hors de gdUnit4 (voir l'en-tête) — faux dans
## CHAQUE contexte qui lance ce jeu avec `--headless` (dont le contrat de
## cette tâche impose l'usage pour tout test).
## Décision utilisateur 2026-09-25 : la carte reste en greybox pur (plan coté +
## blocs générés par script) ; l'habillage sera repris plus tard par l'utilisateur.
## Repasser à true pour réactiver la couche d'art.
const ART_ENABLED := false


static func is_enabled() -> bool:
	return ART_ENABLED and DisplayServer.get_name() != "headless"

## Hook réel, appelé une seule fois par `MapSetup._enter_tree` juste après
## `_build_geometry` (voir son commentaire d'appel) — ne fait rien quand
## `is_enabled()` est faux (§1 R9 "art sauté en headless").
static func apply_all(parent: Node3D, data: Dictionary) -> void:
	if not is_enabled():
		return
	load_modules(parent, data)

## Dispatch nu, SANS le garde headless (voir l'en-tête "pourquoi exposée à
## part") : charge chaque chemin de `MODULE_PATHS` qui existe et expose
## `apply(parent, data)`, dans l'ordre déclaré. Un module sans méthode `apply`
## (fichier présent mais pas encore au contrat) est ignoré plutôt que de
## planter toute la passe suivante.
static func load_modules(parent: Node3D, data: Dictionary) -> void:
	for path in MODULE_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var script: Variant = load(path)
		if script == null:
			continue
		if not script.has_method("apply"):
			continue
		script.apply(parent, data)
