## PingMarkers.gd
## Pile de marqueurs de ping reçus (UX-10, contrat : « un marqueur affiche
## icône + distance + zone (« ENNEMI — CALE S-O ») pendant 6 s ») -- même
## famille visuelle que KillfeedPanel.gd (empilement haut de l'écran, chip
## charcoal, `create_tween`/`tween_interval`/`tween_callback(panel.queue_free)`
## porté par CHAQUE nœud, jamais `get_tree().create_timer()` avec un lambda
## capturant un nœud -- règle globale du projet). Alimentée par
## `GameWorld.ping_received` (câblage du signal : hors périmètre de cette
## tâche, voir tasks/backlog.yaml UX-10 -- `GameHUD.gd`/`player.tscn` n'y
## figurent pas) via `receive()`. La distance affichée est recalculée en
## direct par `update_viewer_position()`, appelée CHAQUE image par le HUD
## avec la position du joueur LOCAL -- même principe que
## `Minimap.set_player_state`/`GameHUD._update_minimap` (jamais figée à
## l'instant de réception : un ping "à 40 m" doit descendre à mesure qu'on
## s'en approche, comme dans Apex).
##
## Icônes/libellés : glyphes DÉJÀ éprouvés ailleurs dans ce projet (jamais
## un nouveau symbole non vérifié dans les polices du jeu) -- ▼ (déjà le
## glyphe "ennemi" de `Comic.team_glyph`), ◆ (déjà utilisé par
## `AgentSelectScreen` pour un rôle), ★ (déjà utilisé par `StunStars`), ! (déjà
## le marqueur de révélation de `Minimap.REVEAL_MARKER_TEXT`), → (déjà utilisé
## par `Settings.gd` pour les libellés de stick).
class_name PingMarkers
extends VBoxContainer

## Contrat UX-10 : "pendant 6 s".
const ENTRY_LIFETIME := 6.0
## Plafond d'entrées simultanées -- borne la pile en cas de rafale d'alliés
## (même esprit que KillfeedPanel.MAX_ENTRIES_1080, valeur propre à cette
## tâche : aucun contrat ne fixe de nombre pour les pings).
const MAX_ENTRIES := 5

## Clés = `PingController.KIND_*` (JAMAIS un littéral dupliqué ici : un
## kind ajouté/renommé côté PingController se répercute sans resynchroniser
## une seconde liste de chaînes).
const _ICONS := {
	PingController.KIND_GROUND: "▶",
	PingController.KIND_ENEMY: "▼",
	PingController.KIND_OBJECT: "◆",
	PingController.KIND_ENEMY_HERE: "▼",
	PingController.KIND_GOING: "→",
	PingController.KIND_DEFEND: "★",
	PingController.KIND_NEED_HELP: "!",
}
const _LABELS := {
	PingController.KIND_GROUND: "MARQUE",
	PingController.KIND_ENEMY: "ENNEMI",
	PingController.KIND_OBJECT: "OBJET",
	PingController.KIND_ENEMY_HERE: "ENNEMI ICI",
	PingController.KIND_GOING: "J'Y VAIS",
	PingController.KIND_DEFEND: "DÉFENDEZ",
	PingController.KIND_NEED_HELP: "BESOIN D'AIDE",
}

func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", Comic.SP_1)
	Comic.anchor(self, Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_top = Comic.SP_7
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Nouveau ping reçu (voir GameWorld._relay_ping/_deliver_ping_local) --
## `sender_id` gardé pour un futur filtrage (ex. masquer ses propres pings),
## non affiché aujourd'hui au-delà de `sender_name`. `pos` : position MONDE
## du ping (mémorisée en métadonnée pour `update_viewer_position`).
## `viewer_pos` : position COURANTE du joueur local (déjà connue de
## l'appelant, qui l'utilise de toute façon chaque image pour
## `update_viewer_position`) -- évite d'afficher une fausse distance "0 m"
## le temps d'une image avant le premier appel à `update_viewer_position`.
func receive(_sender_id: int, sender_name: String, kind: String, pos: Vector3, zone_name: String, viewer_pos: Vector3) -> void:
	var panel := ComicPanel.new()
	panel.bg_color = Comic.PANEL
	panel.border_color = Comic.RULE
	panel.content_margin = Comic.SP_2
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta("ping_pos", pos)
	add_child(panel)
	move_child(panel, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Comic.SP_2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.body.add_child(row)
	row.add_child(Comic.label(icon_for_kind(kind), Comic.SIZE_BODY, Comic.BULLET, Comic.FONT_BOLD))
	row.add_child(Comic.label(format_label(kind, zone_name), Comic.SIZE_FLOOR, Comic.TEXT, Comic.FONT_LABEL))
	var dist_label := Comic.label(format_distance(viewer_pos.distance_to(pos)), Comic.SIZE_FLOOR, Comic.TEXT_DIM, Comic.FONT_LABEL)
	row.add_child(dist_label)
	panel.set_meta("distance_label", dist_label)
	if sender_name != "":
		row.add_child(Comic.label(sender_name, Comic.SIZE_FLOOR, Comic.TEXT_DIM, Comic.FONT_LABEL))

	# `remove_child` D'ABORD (synchrone) puis `queue_free` -- voir
	# KillfeedPanel.push, même raison (queue_free seul ne retire l'enfant
	# qu'en fin de frame, un `while` sur get_child_count() boucle sinon).
	while get_child_count() > MAX_ENTRIES:
		var last := get_child(get_child_count() - 1)
		remove_child(last)
		last.queue_free()

	var tw := panel.create_tween()
	tw.tween_interval(ENTRY_LIFETIME)
	tw.tween_callback(panel.queue_free)

## Recalcule la distance affichée de CHAQUE marqueur encore vivant depuis
## `viewer_pos` (position du joueur LOCAL, poussée par le HUD chaque image --
## voir doc de classe). Un enfant sans métadonnée "ping_pos" (jamais le cas
## en usage normal, garde défensive) est ignoré plutôt que de planter.
func update_viewer_position(viewer_pos: Vector3) -> void:
	for child in get_children():
		if not is_instance_valid(child) or not child.has_meta("ping_pos"):
			continue
		var dist_label: Label = child.get_meta("distance_label", null)
		if dist_label == null or not is_instance_valid(dist_label):
			continue
		var pos: Vector3 = child.get_meta("ping_pos")
		dist_label.text = format_distance(viewer_pos.distance_to(pos))

# ================================================================= PUR

static func icon_for_kind(kind: String) -> String:
	return String(_ICONS.get(kind, "▶"))

static func label_for_kind(kind: String) -> String:
	return String(_LABELS.get(kind, kind.to_upper()))

## Jamais négative (imprécision de calcul plutôt qu'une distance qui n'existe
## pas), arrondie au mètre -- même esprit que HudFormat.format_ammo (jamais
## négatif).
static func format_distance(meters: float) -> String:
	return "%d m" % maxi(roundi(meters), 0)

## "ENNEMI — GRAND-RUE" (contrat : « icône + distance + zone » -- ce texte
## porte le libellé ET la zone, la distance restant un chip SÉPARÉ tenu à
## jour par `update_viewer_position` sans reconstruire tout le texte à
## chaque image). "ENNEMI" seul hors de toute zone déclarée (LD-04,
## `MapSetup.callout_at` renvoie "" -- même état "vide" que
## `LocationLabel.set_zone_name`).
static func format_label(kind: String, zone_name: String) -> String:
	var lbl := label_for_kind(kind)
	if zone_name == "":
		return lbl
	return "%s — %s" % [lbl, zone_name.to_upper()]
