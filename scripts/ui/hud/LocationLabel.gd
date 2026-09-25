## LocationLabel.gd
## Nom de la zone courante (UX-04, UI_DIRECTION_BL3.md §5 « sous la minimap,
## 21 caps ») — posé SOUS la minimap (voir GameHUD._build_minimap), largeur
## alignée sur `Minimap.SIZE_PX`. Alimenté par
## `MapSetup.callout_at(player.global_position)` (LD-04) : GameHUD lit cette
## zone CHAQUE IMAGE (`GameHUD._update_minimap`), donc largement sous les
## 250 ms exigés par le contrat — l'affichage reflète toujours la dernière
## position connue du joueur, jamais un sondage plus lent.
## État "vide" (toute UI a un état vide) : hors de toute zone déclarée (bord
## de carte, ou carte/scène sans callouts, ex. stand de tir) — le bandeau se
## CACHE plutôt que d'afficher une case vide.
## v4 « Encre, jaune, italique » (UX-31) : remplace le chip ComicPanel v3
## (fond charbon.bg + puce rouge) par un nom de zone encré directement sur la
## 3D (§5 #1 « zéro fond derrière le texte du HUD ») — AUCUN test verrouillé
## ne dépend de la classe de base ou de la puce (grep sur tests/, vérifié
## avant cette tâche : seuls `.visible`/`.current_text()`/
## `.custom_minimum_size.x` sont lus), donc ce changement de classe de base
## est sans risque de régression.
class_name LocationLabel
extends Control

var _label: Label
var _zone_name: String = ""

func _ready() -> void:
	custom_minimum_size = Vector2(Minimap.SIZE_PX, 0.0)
	Comic.anchor(self, Control.PRESET_TOP_LEFT)
	offset_left = Comic.SAFE_MARGIN
	offset_top = Comic.SAFE_MARGIN + Minimap.SIZE_PX + Comic.SP_2
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label = Comic.ink_label("", Comic.SIZE_21, Comic.paper_color(), Comic.meta_font_v4(Comic.SIZE_21))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.clip_text = true
	add_child(_label)

	visible = false  # état vide : aucune zone connue avant la 1re image de jeu.

## Nom de zone courant (`MapSetup.callout_at`, "" hors de toute zone
## déclarée) — idempotent (pas de redessin/texte inutile si inchangé).
func set_zone_name(zone_name: String) -> void:
	if zone_name == _zone_name:
		return
	_zone_name = zone_name
	visible = zone_name != ""
	if _label:
		_label.text = zone_name.to_upper()

## Exposé pour rester testable sans dépendre du rendu du `Label` interne.
func current_text() -> String:
	return _label.text if _label else ""
