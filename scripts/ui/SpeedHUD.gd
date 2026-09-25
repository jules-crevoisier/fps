## SpeedHUD.gd
## Affiche la vitesse horizontale et l'état de mouvement du joueur local.
## Indispensable pour régler le feeling du mouvement (outil de développement,
## pas le HUD de jeu -- non instancié en dehors de scenes/levels/test_arena.tscn,
## voir son `ext_resource`). À mettre sur un CanvasLayer avec un Label enfant
## nommé "Label".
## v4 « Encre, jaune, italique » (UX-31) : le libellé de vitesse reste un
## texte encré direct sur la 3D (§5 #1 « zéro fond derrière le texte du
## HUD »), jamais dans une boîte -- restylé ici au premier `_ready()` plutôt
## que dans la scène (hors de ma liste de fichiers).
extends CanvasLayer

@onready var label: Label = $Label

func _ready() -> void:
	label.add_theme_font_override("font", Comic.number_font_v4())
	label.add_theme_font_size_override("font_size", Comic.SIZE_21)
	label.add_theme_color_override("font_color", Comic.paper_color())
	label.add_theme_constant_override("outline_size", Comic.STROKE_INK)
	label.add_theme_color_override("font_outline_color", Comic.ink_color())
	label.add_theme_color_override("font_shadow_color", Comic.ink_color())
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)

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
