## MapCatalog.gd
## Catalogue des maps (contract-r3.md, interface croisée "MapCatalog") : lu
## par le menu (R3-UI) pour proposer un choix de carte, et par les tests. Les
## six scènes vivent dans `scenes/levels/maps/`, une par identifiant de
## `Layouts.MAP_IDS`.
class_name MapCatalog
extends RefCounted

static func all() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({
		"id": "port_ferraille", "number": 1, "name": "Port-Ferraille",
		"description": "Quais embrumés, conteneurs et grue portuaire.",
		"scene": "res://scenes/levels/maps/port_ferraille.tscn",
		"modes": ["tdm", "hardpoint", "snd"], "size": "4v4", "asymmetric": false,
	})
	list.append({
		"id": "val_poussiere", "number": 2, "name": "Val-Poussière",
		"description": "Ville-frontière écrasée de soleil, adobe et clôtures.",
		"scene": "res://scenes/levels/maps/val_poussiere.tscn",
		"modes": ["tdm", "hardpoint", "snd"], "size": "4v4", "asymmetric": false,
	})
	list.append({
		"id": "saint_ombre", "number": 3, "name": "Saint-Ombre",
		"description": "Nuit pluvieuse, pavés et piliers industriels.",
		"scene": "res://scenes/levels/maps/saint_ombre.tscn",
		"modes": ["tdm", "hardpoint", "snd"], "size": "4v4", "asymmetric": false,
	})
	list.append({
		"id": "col_du_vautour", "number": 4, "name": "Col du Vautour",
		"description": "Base de montagne enneigée, barrières et antenne.",
		"scene": "res://scenes/levels/maps/col_du_vautour.tscn",
		"modes": ["tdm", "hardpoint", "snd"], "size": "4v4", "asymmetric": false,
	})
	list.append({
		"id": "la_fosse", "number": 5, "name": "La Fosse",
		"description": "Carrière symétrique, arène de duel.",
		"scene": "res://scenes/levels/maps/la_fosse.tscn",
		"modes": ["duel", "duo"], "size": "duel", "asymmetric": false,
	})
	list.append({
		"id": "le_belvedere", "number": 6, "name": "Le Belvédère",
		"description": "Toits au petit matin, arène de duel.",
		"scene": "res://scenes/levels/maps/le_belvedere.tscn",
		"modes": ["duel", "duo"], "size": "duel", "asymmetric": false,
	})
	list.append({
		"id": "wasteland", "number": 7, "name": "Wasteland",
		"description": "Relais pétrolier désertique, fin d'après-midi — asymétrique.",
		"scene": "res://scenes/levels/maps/wasteland.tscn",
		"modes": ["tdm", "hardpoint", "snd"], "size": "4v4", "asymmetric": true,
	})
	list.append({
		"id": "cargo_ship", "number": 8, "name": "Cargo Ship",
		"description": "Porte-conteneurs au mouillage, crépuscule.",
		"scene": "res://scenes/levels/maps/cargo_ship.tscn",
		"modes": ["tdm", "hardpoint", "snd"], "size": "4v4", "asymmetric": false,
	})
	return list

static func get_by_id(id: String) -> Dictionary:
	for m in all():
		if String(m["id"]) == id:
			return m
	return {}

## Carte par défaut pour un mode donné : la première du catalogue qui le
## supporte ; repli sur la première carte de la bonne taille si `mode_id` est
## inconnu, puis sur la toute première carte.
static func default_for(mode_id: String) -> Dictionary:
	for m in all():
		if (m["modes"] as Array).has(mode_id):
			return m
	var wants_duel := mode_id == "duel" or mode_id == "duo"
	for m in all():
		if wants_duel == (String(m["size"]) == "duel"):
			return m
	return all()[0]
