## RosterPadding.gd
## Complète le roster réel (AgentDatabase.all(), un seul agent aujourd'hui) avec
## des cartes verrouillées « Bientôt » jusqu'à `count` (reports/ui/mockups/
## heroes.html : grille 2×2 fixe). Fonction pure, testable sans scène
## (tests/ui/menu/test_roster_padding.gd).
class_name RosterPadding
extends RefCounted

const LOCKED_TAG := "Bientôt"

## `names` : noms d'agents réels, dans l'ordre d'AgentDatabase.all(). Renvoie un
## tableau de `count` entrées {name, locked} — jamais plus court même si
## `names` dépasse déjà `count` (une carte réelle en trop n'est alors jamais
## retirée, seul le padding s'arrête).
static func pad(names: Array, count: int = 4) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in names:
		out.append({"name": str(n), "locked": false})
	while out.size() < count:
		out.append({"name": "", "locked": true})
	return out
