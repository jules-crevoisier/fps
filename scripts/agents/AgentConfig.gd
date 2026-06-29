## AgentConfig.gd
## Un agent / une classe : nom, couleur d'identité, et sa liste de capacités
## (instances d'Ability). Construits dans AgentDatabase.
class_name AgentConfig
extends Resource

@export var agent_name: String = "Agent"
@export var description: String = ""
@export var color: Color = Color.WHITE
@export var abilities: Array = []  # Array[Ability]
