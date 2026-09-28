## MapCatalog.gd
## Catalogue des maps : lu par les scripts de démarrage (QuickStart.gd), le
## sélecteur de carte du salon (scripts/ui/menu/HomeScreen.gd) et par les
## tests.
##
## Nettoyage du prototype 2026-09-26 (« clean absolument tout, repart sur de
## bonnes bases ») : Wasteland (géométrie procédurale) est supprimée, remplacée
## par Shipment (scenes/levels/maps/shipment.tscn) — une petite cour à
## conteneurs, scène PLATE et éditable (voir MapSetup.gd).
##
## Canyon Express (2026-09-28, phase 2 : `canyon_express.tscn` livrée) :
## DEUXIÈME carte — un train à l'arrêt sur un pont au-dessus d'un canyon.
## Géométrie (109 StaticBody3D `COL_<surface>_*` + 46 MeshInstance3D
## `VIS_<matériau>`) importée depuis `assets/maps/canyon_express/
## canyon_express.glb` (art/collision Blender du lead), posée au runtime par
## ImportedMapGeometry.gd (voir sa doc) sous un nœud "Art" (méta
## `imported_art = true`) de `canyon_express.tscn`. `catalog_has_scene(id)`
## (ResourceLoader.exists) reste en place pour toute carte FUTURE dont la
## scène n'existerait pas encore au moment où son entrée est ajoutée ici (le
## sélecteur de carte du salon dégrade alors proprement -- voir
## `selectable()`) ; elle a simplement cessé de filtrer Canyon Express
## elle-même depuis que sa scène existe.
##
## `look` (STYLE_BIBLE.md v3, ToonStyle.gd) : préréglage de rendu de la
## carte -- "toon" pour le pipeline "BD façon Borderlands" (ToonStyle.gd,
## Verrou/Ravage/Shipment), consommé par LevelLook.gd (`_style`/
## `_apply_key_light`) à la place d'un `map_id == "shipment"` en dur, pour
## que toute carte future déclarée "toon" ici bascule automatiquement sur le
## même pipeline sans toucher LevelLook.gd.
class_name MapCatalog
extends RefCounted

static func _full_list() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({
		"id": "shipment", "number": 1, "name": "Shipment",
		"description": "Cour à conteneurs, combat rapproché — symétrique.",
		"scene": "res://scenes/levels/maps/shipment.tscn",
		"modes": ["tdm"], "size": "4v4", "asymmetric": false,
		"look": "toon",
	})
	list.append({
		"id": "canyon_express", "number": 2, "name": "Canyon Express",
		"description": "Train à l'arrêt sur un pont au-dessus d'un canyon — trois niveaux, trois traversées.",
		"scene": "res://scenes/levels/maps/canyon_express.tscn",
		"modes": ["tdm"], "size": "4v4", "asymmetric": false,
		"look": "toon",
	})
	return list

static func all(_include_dev_maps: bool = false) -> Array[Dictionary]:
	return _full_list()

static func get_by_id(id: String) -> Dictionary:
	for m in _full_list():
		if String(m["id"]) == id:
			return m
	return {}

## Carte par défaut pour un mode donné — Shipment si elle couvre `mode_id`,
## sinon la première carte du catalogue (ordre `_full_list()`).
static func default_for(mode_id: String) -> Dictionary:
	var shipment := get_by_id("shipment")
	if not shipment.is_empty() and (shipment["modes"] as Array).has(mode_id):
		return shipment
	return _full_list()[0]

## Préréglage de rendu (`ToonStyle`/`LevelLook`) de la carte `id` -- chaîne
## vide si l'id est inconnu/absent de la clé "look" (jamais une erreur : le
## repli est le pipeline ink_toon historique, voir LevelLook.gd).
static func look_for(id: String) -> String:
	return str(get_by_id(id).get("look", ""))

## Vrai si `id` est une carte connue ET que sa scène existe déjà sur disque
## -- Canyon Express est dans `_full_list()` avant que sa scène n'arrive :
## ce garde-fou est ce qui permet à MapCatalog de porter son entrée dès
## maintenant sans rendre `resolve_scene`/le sélecteur de carte du salon
## incapables de charger quoi que ce soit.
static func catalog_has_scene(id: String) -> bool:
	var entry := get_by_id(id)
	if entry.is_empty():
		return false
	return ResourceLoader.exists(str(entry.get("scene", "")))

## Cartes RÉELLEMENT choisissables aujourd'hui (scène présente sur disque),
## dans l'ordre du catalogue -- lu par le sélecteur de carte du salon
## (HomeScreen._build_map_picker_row) : une carte dont la scène n'existe pas
## encore (Canyon Express avant sa livraison) est simplement absente de
## cette liste, jamais proposée ni activable.
static func selectable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in _full_list():
		if catalog_has_scene(str(m["id"])):
			out.append(m)
	return out
