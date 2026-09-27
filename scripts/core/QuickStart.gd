## QuickStart.gd
## Scène de boot (scenes/boot.tscn, run/main_scene dans project.godot).
##
## Deux chemins (tâche "lobby / menus", 2026-09-27) :
##  - normal (défaut) : va au menu principal (scenes/ui/main_menu.tscn), qui
##    laisse le joueur choisir mode/carte/bots avant de lancer une partie ;
##  - `--quickstart` (argument utilisateur, `OS.get_cmdline_user_args()`) :
##    reproduit EXACTEMENT l'ancien comportement "prototype minimal" (décision
##    2026-09-26) — TDM sur Shipment, joueur contre un bot Vétéran, sans écran
##    à traverser. Réservé aux captures du lead (tools/ui/*.gd, comparaisons
##    avant/après) : jamais le chemin normal d'un joueur.
## La logique de lancement elle-même (config + hébergement + changement de
## scène, même course "Parent node is busy adding/removing children" que
## documentée ici avant cette tâche) vit maintenant dans MatchLauncher.gd,
## réutilisée par le menu principal — ce fichier ne fait plus que choisir
## LEQUEL des deux chemins prendre.
extends Node

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

func _ready() -> void:
	Settings.load_all()
	if OS.get_cmdline_user_args().has("--quickstart"):
		await _quickstart()
	else:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)

## Ancien comportement direct-au-match (voir doc de tête) : TDM, 1v1 (joueur
## contre un bot), Shipment, bot Vétéran.
func _quickstart() -> void:
	var err := await MatchLauncher.start_local(get_tree(), "tdm", 1, true, MatchConfig.Difficulty.VETERAN, "shipment")
	if err != OK:
		push_error("QuickStart : échec de l'hébergement local.")
