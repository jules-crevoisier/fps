## MecheCourte.gd
## Passif de Vif, "Mèche courte" (docs/research/10_ammo_kits_input.md §3.3,
## fiche Vif) : chaque ÉLIMINATION ou ASSISTANCE lui rend une charge de Ruée
## (plafonnée à son maximum -- AbilityState.grant_charge, socle AGT-01) et lui
## donne +10 % de vitesse au sol pendant 2 s (StatusEffects.apply_speed_mult,
## AGT-01 -- exemple documenté explicitement dans sa propre docstring : "ex.
## Mèche courte de Vif : 1.1 pendant 2 s").
##
## La Ruée de Vif occupe TOUJOURS le slot "C" (capacité de BASE -- §3.2 : "C
## et Q (capacités de base), E = signature, X = ultime", voir
## AgentDatabase._vif : Ruée est la première capacité, slot "C") : ce passif
## cible donc la capacité de slot "C" du porteur, jamais un index fixe ni un
## type concret -- ce qui le rend aussi directement testable avec l'agent de
## test générique de tests/agents/test_passives.gd (une seule capacité,
## `Ability.slot` par défaut = "C").
##
## Flamme/"fshh" cosmétiques (§3.3, "sa chevelure s'embrase... audible à 20 m")
## : purement visuel/audio, hors périmètre de ce fichier -- aucune capacité de
## ce dépôt (Flash, Wall, Smoke...) ne porte encore ce genre d'effet dans son
## propre script.
extends Passive

## Bonus de vitesse au sol et durée (§3.3 : "+10 % de vitesse au sol pendant 2 s").
const SPEED_MULT := 1.1
const SPEED_DURATION := 2.0

func _init() -> void:
	display_name = "Mèche courte"
	description = "Chaque élimination ou assistance rend une charge de Ruée (plafond 2) et donne +10% de vitesse au sol pendant 2 s."

## SERVEUR, sur une ÉLIMINATION de `player` (AbilityController.server_on_kill).
func on_kill(player: PlayerController, _victim_id: int) -> void:
	_reward(player)

## SERVEUR, sur une ASSISTANCE de `player` (AbilityController.server_on_assist
## -- AssistTracker.assists_for_kill : >= 40 dégâts dans les 5 s avant la mort).
func on_assist(player: PlayerController, _victim_id: int) -> void:
	_reward(player)

func _reward(player: PlayerController) -> void:
	if player == null:
		return
	var ctrl := player.get_node_or_null("Abilities") as AbilityController
	if ctrl == null or ctrl.agent == null:
		return
	var i := _dash_slot_index(ctrl.agent)
	if i >= 0:
		ctrl.server_grant_charge(i)
	ctrl.server_apply_speed_mult(SPEED_MULT, SPEED_DURATION)

## Index de la capacité de slot "C" dans `agent.abilities` (-1 si aucune --
## uniquement un agent de test dépourvu de capacité "C", jamais un vrai Vif).
static func _dash_slot_index(agent: AgentConfig) -> int:
	for i in agent.abilities.size():
		var ab: Ability = agent.abilities[i]
		if ab.slot == "C":
			return i
	return -1
