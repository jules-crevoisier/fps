## SpeedHUD.gd
## Affiche la vitesse horizontale et l'état de mouvement du joueur local.
## Indispensable pour régler le feeling du mouvement. À mettre sur un CanvasLayer
## avec un Label enfant nommé "Label".
extends CanvasLayer

@onready var label: Label = $Label

func _process(_delta: float) -> void:
	var p := _local_player()
	if p == null:
		label.text = ""
		return
	var ground := "SOL" if p.is_on_floor() else "AIR"
	label.text = "%.1f m/s\n%s  [%s]" % [p.horizontal_speed(), p.state_machine.current_name, ground]

func _local_player() -> PlayerController:
	var arr := get_tree().get_nodes_in_group("local_player")
	return arr[0] if arr.size() > 0 else null
