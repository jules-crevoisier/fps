## MapCatalog.gd
## Catalogue des maps (contract-r3.md, interface croisée "MapCatalog") : lu
## par le menu (R3-UI) pour proposer un choix de carte, et par les tests.
##
## Nettoyage du prototype 2026-09-26 (« strip to minimal prototype »,
## UX-37 : « on va garder qu'une seule map finie... pas besoin d'autres
## map ») : les 7 autres cartes (Port-Ferraille, Val-Poussière, Saint-Ombre,
## Col du Vautour, La Fosse, Le Belvédère, Cargo Ship) ont été supprimées
## avec leurs scènes/layouts/tests — Wasteland est désormais la SEULE carte,
## `all()`/`get_by_id()`/`default_for()` ne connaissent plus qu'elle.
class_name MapCatalog
extends RefCounted

static func _full_list() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({
		"id": "wasteland", "number": 1, "name": "Wasteland",
		"description": "Relais pétrolier désertique, fin d'après-midi — asymétrique.",
		"scene": "res://scenes/levels/maps/wasteland.tscn",
		"modes": ["tdm"], "size": "4v4", "asymmetric": true,
	})
	return list

static func all(_include_dev_maps: bool = false) -> Array[Dictionary]:
	return _full_list()

static func get_by_id(id: String) -> Dictionary:
	for m in _full_list():
		if String(m["id"]) == id:
			return m
	return {}

## Carte par défaut pour un mode donné — Wasteland si elle couvre `mode_id`,
## sinon la première (et seule) carte du catalogue.
static func default_for(mode_id: String) -> Dictionary:
	var wasteland := get_by_id("wasteland")
	if not wasteland.is_empty() and (wasteland["modes"] as Array).has(mode_id):
		return wasteland
	return _full_list()[0]
