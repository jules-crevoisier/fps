## WeaponIcon.gd
## Résout le NOM d'une arme (WeaponConfig.weapon_name, ex. "RAVAGE"/"Revolver")
## vers le radical de ses icônes dans assets/ui/icons/ (silhouette papier
## `_sil` pour l'inventaire/le fil des éliminations, autocollant couleur
## `_sticker` pour le panneau de munitions) — un seul point de vérité pour ce
## mappage, partagé par AmmoHUD/InventoryHUD/KillFeed plutôt que dupliqué
## trois fois. Fonctions PURES (aucun nœud), testées directement
## (tests/ui/test_weapon_icon.gd).
class_name WeaponIcon
extends RefCounted


## Radical d'icône ("ravage"/"revolver") pour `weapon_name`, "" si inconnu
## (aucune icône -> l'appelant garde alors un repli textuel/vide, jamais un
## crash sur une icône absente).
static func stem_for(weapon_name: String) -> String:
	var n := weapon_name.to_lower()
	if n.find("revolver") != -1:
		return "revolver"
	if n.find("ravage") != -1:
		return "ravage"
	return ""


static func sil(weapon_name: String) -> String:
	var stem := stem_for(weapon_name)
	return stem + "_sil" if stem != "" else ""


static func sticker(weapon_name: String) -> String:
	var stem := stem_for(weapon_name)
	return stem + "_sticker" if stem != "" else ""


## Radical d'icône pour un objet lancé (UtilityDatabase.FRAG/FLASH/SMOKE) —
## utilisé par KillFeed (silhouette) et AmmoHUD/InventoryHUD (autocollant).
static func grenade_stem(kind: int) -> String:
	match kind:
		UtilityDatabase.FRAG:
			return "frag"
		UtilityDatabase.FLASH:
			return "flash"
		UtilityDatabase.SMOKE:
			return "smoke"
		_:
			return ""


## Icône (silhouette papier) pour une entrée du fil des éliminations —
## `weapon_or_ability` vient de GameWorld.kill_logged (nom d'arme EN CAPITALES,
## ex. "RAVAGE", ou le nom d'une capacité future) : arme reconnue -> silhouette
## d'arme ; sinon (capacité, environnement...) -> pictogramme générique "kill"
## (contrat point 5 : "unknown -> kill picto").
static func icon_for_kill_feed(weapon_or_ability: String) -> String:
	var stem := stem_for(weapon_or_ability)
	return stem + "_sil" if stem != "" else "kill"
