## MapCatalog.gd
## Catalogue des maps (contract-r3.md, interface croisée "MapCatalog") : lu
## par le menu (R3-UI) pour proposer un choix de carte, et par les tests. Les
## six scènes vivent dans `scenes/levels/maps/`, une par identifiant de
## `Layouts.MAP_IDS`.
##
## UX-37 (retour lead 2026-09-25, §3 « PROTO = UNE CARTE ») : « on va garder
## qu'une seule map finie... pas besoin d'autres map. Le but c'est de faire un
## proto qui soit bien, qui soit jouable, qui soit fiable. » — `all()` ne
## liste par défaut QUE Wasteland tant que `proto_single_map` reste vrai ; les
## 7 autres cartes RESTENT définies ci-dessous intactes (rien n'est supprimé,
## seule leur EXPOSITION par défaut change) et restent joignables par
## `get_by_id()`/`default_for()` (jamais filtrés — d'autres fichiers hors de
## mon périmètre, ex. tests/networking/test_match_config_sync.gd, s'appuient
## dessus pour des cartes autres que Wasteland) ou via `all(true)` (« mode
## dev » : bascule EXPLICITE, jamais une détection d'environnement fragile —
## voir la note au-dessus de `all()`).
class_name MapCatalog
extends RefCounted

## Prototype à une seule carte (voir la docstring de tête). `false` restaure
## le catalogue complet dans `all()` sans argument — utile en test ou pour
## reprendre le multi-cartes plus tard sans toucher ce fichier ailleurs.
static var proto_single_map: bool = true

## `include_dev_maps` = « mode dev » (contrat UX-37) : bascule explicite plutôt
## qu'une détection d'environnement (OS.has_feature/debug build) — ce dépôt
## lance aussi bien le jeu que les outils de revue avec le MÊME binaire
## éditeur (voir CLAUDE.md), donc rien ne distingue fiablement "vrai joueur"
## de "outil de revue" par l'environnement seul. Les outils de revue internes
## (tools/map_shots.gd, tools/review/perf_bench.gd, tools/review/
## gameplay_probe.gd, tools/look_probe.gd — hors de mon périmètre cette
## tâche) appellent `all()` SANS argument : ils reçoivent donc, eux aussi, la
## liste réduite à Wasteland tant que le proto dure, cohérent avec la
## consigne « pas besoin d'autres map pour l'instant » (CLAUDE.md, vertical
## slice) — à rouvrir explicitement via `all(true)` le jour où on reprend les
## 7 autres cartes.
static func all(include_dev_maps: bool = false) -> Array[Dictionary]:
	var list := _full_list()
	if proto_single_map and not include_dev_maps:
		return list.filter(func(m): return String(m.get("id", "")) == "wasteland")
	return list

## Catalogue complet, INCHANGÉ — jamais filtré par `proto_single_map` (source
## unique lue par `all()`, `get_by_id()` et `default_for()`).
static func _full_list() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({
		"id": "port_ferraille", "number": 1, "name": "Port-Ferraille",
		"description": "Quais dans la brume du matin, conteneurs et grue portuaire.",
		"scene": "res://scenes/levels/maps/port_ferraille.tscn",
		"modes": ["tdm", "hardpoint", "snd"], "size": "4v4", "asymmetric": false,
	})
	list.append({
		"id": "val_poussiere", "number": 2, "name": "Val-Poussière",
		"description": "Ville-frontière à l'heure dorée, adobe et clôtures.",
		"scene": "res://scenes/levels/maps/val_poussiere.tscn",
		"modes": ["tdm", "hardpoint", "snd"], "size": "4v4", "asymmetric": false,
	})
	list.append({
		"id": "saint_ombre", "number": 3, "name": "Saint-Ombre",
		"description": "Fin d'orage au crépuscule, pavés et piliers industriels.",
		"scene": "res://scenes/levels/maps/saint_ombre.tscn",
		"modes": ["tdm", "hardpoint", "snd"], "size": "4v4", "asymmetric": false,
	})
	list.append({
		"id": "col_du_vautour", "number": 4, "name": "Col du Vautour",
		"description": "Midi alpin sur la base de montagne enneigée, barrières et antenne.",
		"scene": "res://scenes/levels/maps/col_du_vautour.tscn",
		"modes": ["tdm", "hardpoint", "snd"], "size": "4v4", "asymmetric": false,
	})
	list.append({
		"id": "la_fosse", "number": 5, "name": "La Fosse",
		"description": "Carrière à midi, arène de duel symétrique.",
		"scene": "res://scenes/levels/maps/la_fosse.tscn",
		"modes": ["duel", "duo"], "size": "duel", "asymmetric": false,
	})
	list.append({
		"id": "le_belvedere", "number": 6, "name": "Le Belvédère",
		"description": "Toits à l'aube, arène de duel.",
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
		"description": "Porte-conteneurs au mouillage, fin de matinée.",
		"scene": "res://scenes/levels/maps/cargo_ship.tscn",
		"modes": ["tdm", "hardpoint", "snd"], "size": "4v4", "asymmetric": false,
	})
	return list

## Toujours résolu contre le catalogue COMPLET (jamais filtré par
## `proto_single_map`, voir la docstring de tête) : un `map_id` explicite
## (mémorisé, transmis par le serveur...) doit rester joignable même s'il ne
## fait plus partie de la sélection par défaut du menu.
static func get_by_id(id: String) -> Dictionary:
	for m in _full_list():
		if String(m["id"]) == id:
			return m
	return {}

## Carte par défaut pour un mode donné (UX-37, retour lead : « carte par
## défaut = Wasteland pour tous les modes qu'elle supporte ») — Wasteland
## d'abord si elle couvre `mode_id` (tdm/hardpoint/snd), puis repli sur
## l'ancien comportement (première du catalogue complet qui le supporte,
## première carte de la bonne taille, puis toute première carte) pour les
## modes qu'elle ne couvre pas (duel/duo — la_fosse/le_belvédère restent
## leurs cartes, `proto_single_map` ne les concerne pas).
static func default_for(mode_id: String) -> Dictionary:
	var wasteland := get_by_id("wasteland")
	if not wasteland.is_empty() and (wasteland["modes"] as Array).has(mode_id):
		return wasteland
	var full := _full_list()
	for m in full:
		if (m["modes"] as Array).has(mode_id):
			return m
	var wants_duel := mode_id == "duel" or mode_id == "duo"
	for m in full:
		if wants_duel == (String(m["size"]) == "duel"):
			return m
	return full[0]
