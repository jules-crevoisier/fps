## wasteland_dressing.gd
## Squelette (LD-20, "découpe en 5 fichiers") — futur décor pur supplémentaire
## pour Wasteland (pochoirs de callouts, decalques FUEL/GAS, densité de
## props par zone, docs/research/09_wasteland_vertical_slice.md §d.5),
## distinct des pièces déjà posées dans `wasteland.gd`. VOLONTAIREMENT VIDE
## cette tâche (le contrat LD-20 ne porte que sur la géométrie de
## `wasteland.gd` ; les tâches ART-7x, hors de mon périmètre, rempliront ce
## fichier). `entries()` ne renvoie rien à ajouter tant qu'aucune entrée
## n'est ajoutée ici — voir `MapSetup._assemble_wasteland`, qui les
## ajouterait à `data["pieces"]` (jamais dans l'espace praticable,
## `cover: false`, même contrat que le décor déjà posé dans `wasteland.gd`).
class_name WastelandDressing
extends RefCounted

static func entries() -> Array:
	return []
