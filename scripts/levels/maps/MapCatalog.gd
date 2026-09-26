## MapCatalog.gd
## Catalogue des maps : lu par les scripts de démarrage (QuickStart.gd) et par
## les tests.
##
## Nettoyage du prototype 2026-09-26 (« clean absolument tout, repart sur de
## bonnes bases ») : Wasteland (géométrie procédurale) est supprimée, remplacée
## par Shipment (scenes/levels/maps/shipment.tscn) — une petite cour à
## conteneurs, scène PLATE et éditable (voir MapSetup.gd). Shipment est la
## SEULE carte : `all()`/`get_by_id()`/`default_for()` ne connaissent qu'elle.
class_name MapCatalog
extends RefCounted

static func _full_list() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({
		"id": "shipment", "number": 1, "name": "Shipment",
		"description": "Cour à conteneurs, combat rapproché — symétrique.",
		"scene": "res://scenes/levels/maps/shipment.tscn",
		"modes": ["tdm"], "size": "4v4", "asymmetric": false,
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
## sinon la première (et seule) carte du catalogue.
static func default_for(mode_id: String) -> Dictionary:
	var shipment := get_by_id("shipment")
	if not shipment.is_empty() and (shipment["modes"] as Array).has(mode_id):
		return shipment
	return _full_list()[0]
