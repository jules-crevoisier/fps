## AgentConfig.gd
## Un agent / une classe : nom, rôle, couleur d'identité. Construit dans
## AgentDatabase. Prototype à un seul personnage (décision 2026-09-26, "strip
## to minimal prototype") : plus aucune capacité/passif — les champs
## `abilities`/`passive` (Ability/Passive, supprimés avec tout le système de
## capacités) ont disparu avec eux.
class_name AgentConfig
extends Resource

@export var agent_name: String = "Agent"
## Rôle affiché (écran de sélection + menu Agents) : "Entrée", "Contrôle" ou "Soutien".
@export var role: String = ""
@export var description: String = ""
@export var color: Color = Color.WHITE
