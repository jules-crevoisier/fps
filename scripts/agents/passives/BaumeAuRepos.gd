## BaumeAuRepos.gd
## Passif de Roseau, "Baume au repos" (docs/research/10_ammo_kits_input.md
## §3.3, fiche Roseau) — remplace l'ancien C Apaisement (soin conditionnel,
## devenu redondant avec la régénération de base) : "le baume ne prend qu'au
## repos". Sa régénération démarre après 2,5 s sans dégât (au lieu de 4 s), à
## 40 PV/s (au lieu de 35) -- POUR ELLE SEULE, jamais pour ses coéquipiers
## (Health.regen_delay/regen_rate existent déjà sur le composant de vie,
## contract-r2.md ; ce passif se contente de les régler au spawn, une fois
## par vie, via le hook Passive.on_spawn, comme documenté dans
## scripts/agents/Passive.gd).
extends Passive

## Délai sans dégât avant la reprise de régénération (4 s de base -> 2,5 s).
@export var regen_delay: float = 2.5
## PV/s régénérés une fois la reprise commencée (35 PV/s de base -> 40 PV/s).
@export var regen_rate: float = 40.0

func _init() -> void:
	display_name = "Baume au repos"
	description = "Sa régénération démarre après 2,5 s sans dégât (au lieu de 4 s), à 40 PV/s (au lieu de 35)."

## SERVEUR, au spawn de `player` (AbilityController._ready, une fois par vie) :
## règle son propre composant Health, jamais celui d'un autre joueur.
func on_spawn(player: PlayerController) -> void:
	if player == null:
		return
	var hp := player.get_node_or_null("Health") as Health
	if hp == null:
		return
	hp.regen_delay = regen_delay
	hp.regen_rate = regen_rate
