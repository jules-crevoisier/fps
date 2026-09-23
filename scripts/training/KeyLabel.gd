## KeyLabel.gd
## Enrobe `Settings.binding_text()` (lu seul, hors de mon lot) pour rester
## sûr en `--headless` : le serveur d'affichage headless ne supporte pas
## `DisplayServer.keyboard_get_label_from_physical` (utilisé par
## `Settings.event_text` pour les touches à code PHYSIQUE — le cas par
## défaut de ce projet, voir docs/CONTROLS.md), ce qui ferait planter tout
## `_ready()` appelant `Settings.binding_text()` pendant le boot headless
## (contract-r4a.md, gate "headless boot ... zero SCRIPT ERROR" — constaté
## en isolant le crash sur `res://scenes/levels/training/training_ground.tscn`
## `--headless --quit-after 300`). Ce garde-fou vit ici, PAS dans Settings.gd.
class_name KeyLabel
extends RefCounted

static func for_action(action: String) -> String:
	if DisplayServer.get_name() == "headless":
		return "[%s]" % action
	return Settings.binding_text(action)
