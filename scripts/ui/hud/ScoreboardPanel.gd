## ScoreboardPanel.gd
## Tableau des scores (maintenir Tab) — v4 « Encre, jaune, italique » (UX-34,
## docs/UI_DIRECTION_BL3.md §6 « Tableau des scores », §7 tokens) : plaque à
## coins coupés (`Comic.plate_style()`, remplace le panneau à coins arrondis
## v3), lignes de 54 px (`ROW_HEIGHT_PX`) zébrées `plate`/`plate_hi` SANS
## filet (§6 « sans filets » — remplace la bordure `Comic.RULE`/couleur
## d'équipe v3), onglet ●/▼ (glyphe de camp, jamais la couleur seule) inchangé
## dans le TEXTE de la ligne. Ta ligne (le joueur local) reste inclinée à 12°
## (StyleBoxFlat.skew, `Comic.SLANT_DEG`, jamais un radius — `Comic.
## RADIUS_SLANT`) mais passe en PLEIN `signal` (jaune), texte `ink` (§6
## « ta ligne pleine signal, texte encre ») — les autres lignes restent
## inclinées mais sans trait, seulement le zébrage. Allié/ennemi RELATIF au
## joueur local (docs/research/04_ui_ux.md §2.3), jamais l'indice d'équipe
## brut.
##
## ATTENTION contrat verrouillé (tests/ui/test_team_relative.gd, hors
## périmètre d'écriture de cette tâche) : le test caste CHAQUE enfant direct
## de `_list` en `Label` et lit `.text` SANS vérifier la nullité — donc (a)
## tout enfant direct de `_list` doit rester un `Label` réel (jamais un
## `Container` englobant : la barre inclinée est posée en stylebox `normal`
## DU LABEL LUI-MÊME, voir `_zebra_row_style`), et (b) les DEUX en-têtes d'équipe
## ("<glyphe> ÉQUIPE <n>", format et couleur inchangés) doivent rester les
## SEULS enfants dont le texte commence par "●"/"▼" — l'onglet d'une ligne
## joueur est donc posé APRÈS une indentation, jamais en tout premier
## caractère de la chaîne.
##
## Colonnes K/M (kills/morts) toujours, +A (assists) SEULEMENT si la clé
## existe déjà sur `player_info` (GameWorld.gd, hors de ma liste de fichiers,
## voir `_any_assists`) : elle n'y est portée par AUCUN appelant actuel, la
## colonne A n'apparaît donc jamais aujourd'hui, sans code mort pour autant si
## elle est ajoutée plus tard. `player_info` ne porte ni dégâts, ni économie,
## ni ping par joueur — les colonnes DÉG./ÉCO./PING de la maquette §6 ne
## peuvent pas être renseignées honnêtement ici (voir le rendu de tâche,
## `blocked_on`). Portrait : glyphe de camp agrandi, jamais une image inventée
## (voir `_player_row`, même repli que `DeathPanel`).
class_name ScoreboardPanel
extends Control

## Hauteur de ligne v4 (§6 « lignes de 54 px zébrées »).
const ROW_HEIGHT_PX := 54.0

## Libellés de mode courts (UX-34, REVUE LEAD point 4 « en-tête = ligne meta
## 21 "TDM · WASTELAND · PREMIER À 40" ») -- `MatchConfig.mode_id`
## (scripts/core/MatchConfig.gd, lu mais JAMAIS modifié) n'est qu'un id
## machine ("tdm"...) : ce dictionnaire est un simple libellé d'affichage pour
## un id CONNU (`MatchConfig.MODES`), jamais une statistique inventée.
const _MODE_LABELS := {
	"tdm": "TDM", "hardpoint": "HARDPOINT", "snd": "SND", "duel": "DUEL", "duo": "DUO",
}

var _panel: PanelContainer
var _list: VBoxContainer
## En-tête meta 21 (UX-34 point 4) -- mode + carte + objectif, voir
## `_update_meta_header()`.
var _meta_header: Label
## Score 118 RÉEL (même patron que EndPanel._score_row, voir sa note) -- 3
## labels, allié/tiret/ennemi séparément colorés, voir `_update_score_row()`.
var _score_row: HBoxContainer
var _score_ally_label: Label
var _score_enemy_label: Label
## Ligne d'en-têtes de colonnes meta 21 (point 4 « colonnes alignées ... avec
## une ligne d'en-têtes de colonnes meta 21 ») -- HORS de `_list` (contrat
## verrouillé de `_list`, voir la note de tête de fichier), reconstruite à
## chaque `refresh()` par `_update_columns_header()` (la colonne A n'apparaît
## que si `player_info` porte vraiment la clé `assists`).
var _columns_header: Label
## Empreinte texte du dernier `player_info` affiché (id/nom/équipe/kills/morts
## triés) + équipe locale — sert uniquement à éviter de reconstruire `_list`
## quand rien n'a changé (`refresh()` est appelé chaque image tant que Tab est
## maintenu). L'identité du joueur local (`multiplayer.get_unique_id()`) ne
## change pas en cours de partie : elle n'a pas besoin d'entrer dans cette
## empreinte.
var _last_snapshot: String = ""

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(Comic.BG.r, Comic.BG.g, Comic.BG.b, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", Comic.SP_1)
	center.add_child(wrap)

	# UX-34, REVUE LEAD point 4 (« SUPPRIMER le bandeau pinceau rouge (banni
	# par la direction) ») -- `BrushHeader` (bandeau `Comic.BRUSH` rouge,
	# STYLE_BIBLE v3) remplacé par le langage v4 : une ligne meta 21 mode ·
	# carte · objectif, un score 118 réel (allié/ennemi), une ligne d'en-têtes
	# de colonnes -- voir `_update_meta_header()`/`_update_score_row()`
	# ci-dessous, appelées à chaque `refresh()`.
	_meta_header = Comic.meta_label_v4("", Comic.SIZE_21, Comic.paper_dim_color())
	_meta_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_meta_header.custom_minimum_size = Vector2(760, 0)
	wrap.add_child(_meta_header)

	_score_row = HBoxContainer.new()
	_score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_score_row.add_theme_constant_override("separation", Comic.SP_2)
	wrap.add_child(_score_row)
	_score_ally_label = Comic.number_label_v4("", Comic.SIZE_118, Comic.ALLY)
	_score_row.add_child(_score_ally_label)
	_score_row.add_child(Comic.number_label_v4("—", Comic.SIZE_118, Comic.paper_color()))
	_score_enemy_label = Comic.number_label_v4("", Comic.SIZE_118, Comic.enemy_color())
	_score_row.add_child(_score_enemy_label)

	# En-tête de colonnes (point 4) -- « n'afficher que les stats que
	# player_info fournit déjà » (précision lead) : CAMP/NOM/É/M toujours,
	# +A seulement si `assists` existe (voir `_update_columns_header`). Pas de
	# colonne SCORE/PING inventée -- `player_info` (GameWorld.gd, hors de ma
	# liste de fichiers) ne les porte pas, voir la note de tête de fichier.
	_columns_header = Comic.meta_label_v4("", Comic.SIZE_21, Comic.paper_dim_color())
	_columns_header.custom_minimum_size = Vector2(760, 0)
	wrap.add_child(_columns_header)

	# v4 §3 « les contenants ont des coins coupés » -- plaque + ombre dure
	# portée en enfant, remplace le panneau à coins arrondis v3 (`ComicPanel`,
	# hors de ma liste de fichiers). `host` DOIT être un `Control` nu (jamais
	# un `Container`) : un `Container` reposerait `_panel` lui-même et
	# écraserait le décalage manuel de l'ombre (piège vérifié en lecture --
	# `PanelContainer`/tout `Container` forcent le rect de CHAQUE enfant,
	# ignorant ses propres ancres/offsets).
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.custom_minimum_size = Vector2(760, 0)
	wrap.add_child(host)

	# UX-34, REVUE LEAD point 5 (même défaut que la carte du tueur de
	# DeathPanel.gd, voir sa docstring) -- `Comic.plate_style(Comic.ink_color())`
	# partage le MÊME chamfer que `_panel` ci-dessous, jamais un rectangle
	# droit (`hard_shadow_style`) qui dépasserait au coin coupé.
	var shadow := PanelContainer.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.add_theme_stylebox_override("panel", Comic.plate_style(Comic.ink_color()))
	Comic.anchor(shadow, Control.PRESET_FULL_RECT)
	shadow.offset_left = Comic.SHADOW_HARD_OFFSET.x
	shadow.offset_top = Comic.SHADOW_HARD_OFFSET.y
	shadow.offset_right = Comic.SHADOW_HARD_OFFSET.x
	shadow.offset_bottom = Comic.SHADOW_HARD_OFFSET.y
	host.add_child(shadow)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Comic.plate_style(Comic.plate_color()))
	Comic.anchor(_panel, Control.PRESET_FULL_RECT)
	host.add_child(_panel)

	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(760, 0)
	_list.add_theme_constant_override("separation", 0)
	_panel.add_child(_list)

	# `host` (Control nu, voir plus haut) ne remonte JAMAIS sa taille mini
	# tout seul (ce n'est pas un Container) -- `_panel` (PanelContainer) LUI
	# réémet `minimum_size_changed` à chaque changement de taille mini d'un
	# descendant à n'importe quelle profondeur (comportement standard des
	# Container Godot, voir la note de ComicPanel.gd), donc `_list` rempli/
	# vidé par `refresh()` en aval suffit à déclencher cette resynchronisation
	# -- jamais le bug « host haut de 0 px » déjà documenté ailleurs
	# (EndPanel.gd, carte MVP) pour un piège identique.
	_panel.minimum_size_changed.connect(func():
		host.custom_minimum_size = _panel.get_combined_minimum_size()
	)

## `local_team` : équipe du joueur local — décide quelle colonne est Alliée
## (●, `Comic.ALLY`) et laquelle est Ennemie (▼, `Comic.enemy_color()`), voir
## `Comic.is_ally`.
func refresh(match_node: Node, local_team: int) -> void:
	if match_node == null or not is_instance_valid(match_node) or _list == null:
		return
	var info: Dictionary = match_node.player_info
	# Le mode/score (point 4) évoluent CHAQUE frame indépendamment du roster
	# (kills constants entre deux frags) -- toujours mis à jour, jamais soumis
	# au cache `_last_snapshot` qui ne protège QUE la reconstruction de `_list`.
	_update_meta_header()
	_update_score_row(local_team)
	var show_assists := _any_assists(info)
	_update_columns_header(show_assists)
	var snapshot := "%s#%s" % [str(show_assists), _build_snapshot(info, local_team)]
	if snapshot == _last_snapshot:
		return
	_last_snapshot = snapshot
	for c in _list.get_children():
		c.queue_free()
	for team in [0, 1]:
		var is_ally := Comic.is_ally(team, local_team)
		var team_color := Comic.ALLY if is_ally else Comic.enemy_color()
		_list.add_child(Comic.label("%s ÉQUIPE %d" % [Comic.team_glyph(is_ally), team + 1], Comic.SIZE_LABEL, team_color, Comic.FONT_NUMBER))
		var ids: Array = []
		for id in info:
			if int(info[id].team) == team:
				ids.append(id)
		# Classement par kills décroissants (lisibilité — la maquette §6
		# place le meilleur score en tête de chaque colonne).
		ids.sort_custom(func(a, b): return int(info[a].kills) > int(info[b].kills))
		# Zebrage (§6) : index REINITIALISE par colonne d'equipe, pas
		# global au tableau -- chaque colonne commence sur `plate`.
		var row_index := 0
		for id in ids:
			_list.add_child(_player_row(id, info[id], is_ally, team_color, row_index, show_assists))
			row_index += 1

## UX-34, REVUE LEAD point 4 « en-tête = ligne meta 21 "TDM · WASTELAND ·
## PREMIER À 40" » -- mode/carte lus honnêtement sur `MatchConfig`/
## `MapCatalog` (statiques, lus mais JAMAIS modifiés, comme `BuyMenu.gd`/
## `GameHUD.gd` le font déjà pour le nœud "game_mode", voir plus bas) ;
## l'objectif ("Premier à 40 éliminations") vient de `GameMode.hud_state`
## (déjà calculé pour `ScorePanel`, jamais dupliqué en dur ici) via le groupe
## "game_mode" -- MÊME patron de lecture que `BuyMenu._mode`/`GameHUD._mode`
## (`get_tree().get_first_node_in_group("game_mode")`), sans jamais toucher
## GameWorld.gd/GameMode.gd. Absent (capture isolée, entraînement) : repli
## honnête sur un titre générique, jamais un mode/une carte inventés.
func _update_meta_header() -> void:
	var parts: PackedStringArray = []
	var mode_label: String = _MODE_LABELS.get(MatchConfig.mode_id, MatchConfig.mode_id)
	parts.append(mode_label)
	var map_label := _map_label()
	if not map_label.is_empty():
		parts.append(map_label)
	var mode_node := _game_mode_node()
	if mode_node != null:
		var objective := String(mode_node.hud_state)
		if not objective.is_empty():
			parts.append(objective)
	_meta_header.text = (" · ".join(parts) if not parts.is_empty() else "Tableau des scores").to_upper()

## Nom de carte affiché (`MapCatalog.gd`, lu jamais modifié) -- `map_id` vide
## (carte par défaut du mode, voir `MatchConfig.gd`) résolu comme le fait déjà
## `MatchConfig.resolve_scene`.
func _map_label() -> String:
	var entry: Dictionary = MapCatalog.get_by_id(MatchConfig.map_id) if MatchConfig.map_id != "" else {}
	if entry.is_empty():
		entry = MapCatalog.default_for(MatchConfig.mode_id)
	return String(entry.get("name", ""))

## UX-34 point 4 « score 118 ally contre enemy » -- `GameMode.team_score(t)`
## (déjà la source du score affiché par `ScorePanel`, jamais recalculé depuis
## `player_info` qui ne le porte pas). Aucun nœud "game_mode" (capture isolée
## sans match réel) : le score reste VIDE plutôt qu'un "0 — 0" inventé.
func _update_score_row(local_team: int) -> void:
	var mode_node := _game_mode_node()
	if mode_node == null:
		_score_row.visible = false
		return
	_score_row.visible = true
	var my_index := local_team if local_team in [0, 1] else 0
	var other_index := 1 - my_index
	_score_ally_label.text = str(int(mode_node.team_score(my_index)))
	_score_enemy_label.text = str(int(mode_node.team_score(other_index)))

## Duck-typing (comme `BuyMenu._mode`/`GameHUD._mode`, voir la note de
## `_update_meta_header`) : n'importe quel nœud du groupe "game_mode" qui
## porte `hud_state`/`team_score`, jamais un type statique GameMode imposé ici.
func _game_mode_node() -> Node:
	if not is_inside_tree():
		return null
	var node := get_tree().get_first_node_in_group("game_mode")
	if node == null or not is_instance_valid(node) or not node.has_method("team_score"):
		return null
	return node

## Point 4 « n'afficher que les stats que player_info fournit déjà ... et A si
## la clé assists existe » -- vrai si AU MOINS un joueur connu porte la clé.
func _any_assists(info: Dictionary) -> bool:
	for id in info:
		if (info[id] as Dictionary).has("assists"):
			return true
	return false

## En-tête de colonnes meta 21 (point 4) -- CAMP/NOM/É/M toujours, +A
## seulement si `show_assists` (voir `_any_assists`). Pas de colonne
## SCORE/PING : `player_info` ne les porte pas (voir la note de tête de
## fichier).
func _update_columns_header(show_assists: bool) -> void:
	var text := "CAMP   NOM   É   M"
	if show_assists:
		text += "   A"
	_columns_header.text = text

## Ligne joueur v4 (§6, UX-34 REVUE LEAD point 4) : colonnes alignées
## (portrait/glyphe de camp, nom, É, M, +A si `show_assists`), fond zébré
## `plate`/`plate_hi` (voir `_zebra_row_style`) SANS filet -- la ligne locale
## (`multiplayer.get_unique_id()`) passe en PLEIN `signal`, texte `ink` (§6
## « ta ligne pleine signal, texte encre ») ; le suffixe « (toi) » de v3 est
## SUPPRIMÉ (précision lead : la ligne pleine signal le dit déjà, texte
## redondant). Portrait : glyphe ●/▼ agrandi à la place d'une vraie image
## (comme `DeathPanel._build_killer_card`, voir sa docstring) -- un vrai
## portrait suivrait l'ajout d'un `agent_index` à `player_info` (blocked_on,
## voir le rendu de tâche UX-34).
func _player_row(id, p: Dictionary, is_ally: bool, team_color: Color, row_index: int, show_assists: bool) -> Label:
	var is_local := int(id) == multiplayer.get_unique_id()
	var row := "   %s   %-18s  É %2d  M %2d" % [Comic.team_glyph(is_ally), str(p.name), int(p.kills), int(p.deaths)]
	if show_assists:
		row += "  A %2d" % int(p.get("assists", 0))
	var text_color := Comic.ink_color() if is_local else Comic.paper_color()
	var lbl := Comic.label(row, Comic.SIZE_28, text_color, Comic.body_font_v4())
	lbl.custom_minimum_size = Vector2(0.0, ROW_HEIGHT_PX)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bg := Comic.signal_color() if is_local else (Comic.plate_color() if row_index % 2 == 0 else Comic.plate_hi_color())
	lbl.add_theme_stylebox_override("normal", _zebra_row_style(bg))
	return lbl

## Ligne zébrée inclinée à 12° (§4.3 « boutons/barres/onglets... inclinés »,
## `Comic.SLANT_DEG`, même cisaillement que `KitSlantBar._slant_points`) --
## SANS trait (§6 « sans filets », remplace la bordure `Comic.RULE`/couleur
## d'équipe v3). Posée en stylebox `normal` d'un `Label` existant (jamais un
## `Container` séparé) : voir la note de tête de fichier sur le contrat
## verrouillé de `_list`.
func _zebra_row_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(Comic.RADIUS_SLANT)
	s.skew = Vector2(tan(deg_to_rad(Comic.SLANT_DEG)), 0.0)
	s.content_margin_left = Comic.SP_4
	s.content_margin_right = Comic.SP_4
	s.content_margin_top = Comic.SP_1
	s.content_margin_bottom = Comic.SP_1
	s.anti_aliasing = true
	return s

## Empreinte texte triée par id (stable d'une image à l'autre) des champs
## réellement affichés, plus l'équipe locale (une bascule d'équipe locale doit
## reconstruire la liste même si `info` n'a pas changé) — deux instantanés
## égaux en contenu produisent la même chaîne, même si `info` est un nouveau
## Dictionary à chaque appel.
func _build_snapshot(info: Dictionary, local_team: int) -> String:
	var ids := info.keys()
	ids.sort()
	var parts: PackedStringArray = []
	for id in ids:
		var p: Dictionary = info[id]
		parts.append("%s:%s:%d:%d:%d:%d" % [str(id), str(p.name), int(p.team), int(p.kills), int(p.deaths), int(p.get("assists", -1))])
	return "%d#%s" % [local_team, "|".join(parts)]
