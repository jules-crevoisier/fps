## MatchModeCatalog.gd
## Cartes de mode de l'écran d'accueil (reports/ui/mockups/home.html "Choisis ton
## match"). Le prototype n'a qu'UN SEUL mode MatchConfig ("tdm", voir
## MatchConfig.MODES) : « Match à mort par équipe », « Duel » et
## « Entraînement » sont donc trois PRÉRÉGLAGES de taille d'équipe/difficulté
## sur ce même mode, jamais trois mode_id différents — seul « Rejoindre /
## héberger » (JOIN_HOST) n'a pas de config locale (il ouvre le panneau IP).
## Fonctions pures, testées sans scène (tests/ui/menu/test_match_mode_catalog.gd).
class_name MatchModeCatalog
extends RefCounted

const TDM := "tdm4"
const DUEL := "duel"
const TRAINING := "training"
const JOIN_HOST := "join_host"

## Ordre d'affichage = ordre de la maquette. `num`/`name`/`sub` sont la copie
## FR réelle de home.html, jamais un texte de substitution.
const PRESETS: Array[Dictionary] = [
	{"id": TDM, "num": "4", "name": "Match à mort par équipe", "sub": "4 contre 4 · 50 éliminations"},
	{"id": DUEL, "num": "1", "name": "Duel", "sub": "1 contre 1 · 10 minutes"},
	{"id": TRAINING, "num": "B", "name": "Entraînement", "sub": "Contre des bots, sans classement"},
	{"id": JOIN_HOST, "num": "IP", "name": "Rejoindre / héberger", "sub": "Partie privée entre amis"},
]

static func is_join_host(preset_id: String) -> bool:
	return preset_id == JOIN_HOST

## Paramètres MatchConfig (mode_id/team_size/bot_difficulty) pour un préréglage
## LOCAL (jamais bots_enabled : ce champ suit le bouton dédié "Compléter avec
## des bots", indépendant du préréglage choisi). Dictionnaire vide pour
## JOIN_HOST (pas de config locale à appliquer) ou un id inconnu.
static func params_for(preset_id: String) -> Dictionary:
	match preset_id:
		TDM:
			return {"mode_id": "tdm", "team_size": 4, "bot_difficulty": MatchConfig.Difficulty.VETERAN}
		DUEL:
			return {"mode_id": "tdm", "team_size": 1, "bot_difficulty": MatchConfig.Difficulty.VETERAN}
		TRAINING:
			# Entraînement = difficulté la plus facile disponible (RECRUE).
			return {"mode_id": "tdm", "team_size": 4, "bot_difficulty": MatchConfig.Difficulty.RECRUE}
	return {}

## Index dans PRESETS pour un id donné, -1 si inconnu.
static func index_of(preset_id: String) -> int:
	for i in PRESETS.size():
		if PRESETS[i]["id"] == preset_id:
			return i
	return -1
