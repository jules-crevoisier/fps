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
