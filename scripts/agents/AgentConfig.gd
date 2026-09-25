## AgentConfig.gd
## Un agent / une classe : nom, rôle, couleur d'identité, et sa liste de
## capacités (instances d'Ability). Construits dans AgentDatabase.
class_name AgentConfig
extends Resource

@export var agent_name: String = "Agent"
## Rôle affiché (écran de sélection + menu Agents) : "Entrée", "Contrôle" ou "Soutien".
@export var role: String = ""
@export var description: String = ""
@export var color: Color = Color.WHITE
@export var abilities: Array = []  # Array[Ability]
## Passif TOUJOURS actif de cet agent (docs/research/10_ammo_kits_input.md
## §3.5), sans touche ni cooldown. `null` = agent sans passif -- repli sûr :
## chaque hook a un no-op par défaut sur `Passive` elle-même, et
## AbilityController garde en plus ses propres gardes (`agent.passive != null`)
## avant d'appeler quoi que ce soit.
@export var passive: Passive = null
