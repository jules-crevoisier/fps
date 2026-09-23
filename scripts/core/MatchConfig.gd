## MatchConfig.gd
## Réglages de la partie choisis au menu (mode, carte, taille d'équipe, bots),
## lus par la scène de jeu à son chargement. Statique : survit au changement de
## scène. Seul l'hôte les applique — le serveur décide, les clients reçoivent
## l'état de la partie par le jeu lui-même.
class_name MatchConfig
extends RefCounted

enum Difficulty { RECRUE, VETERAN, ELITE }

## Identifiants de mode reconnus par MapSetup (scripts/levels/maps/).
const MODES := ["tdm", "hardpoint", "snd", "duel", "duo"]

static var mode_id: String = "tdm"
## Identifiant MapCatalog ; vide = carte par défaut du mode.
static var map_id: String = ""
## Joueurs par équipe : 4 en 4v4, 2 en Duo, 1 en Duel (voir team_size_for).
static var team_size: int = 4
## Compléter les équipes avec des bots (toujours affichés « BOT »).
static var bots_enabled: bool = true
static var bot_difficulty: int = Difficulty.VETERAN

## Taille d'équipe imposée par un mode.
static func team_size_for(id: String) -> int:
	match id:
		"duel":
			return 1
		"duo":
			return 2
	return 4

## Sélectionne un mode (et la taille d'équipe qui va avec). Un id inconnu
## retombe sur le TDM.
static func set_mode(id: String) -> void:
	mode_id = id if id in MODES else "tdm"
	team_size = team_size_for(mode_id)
