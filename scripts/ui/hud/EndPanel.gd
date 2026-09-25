## EndPanel.gd
## Page de fin — v4 « Encre, jaune, italique » (UX-34, docs/UI_DIRECTION_BL3.md
## §6 « Fin », §7 tokens ; remplace le fond charcoal v3 §8.6) : VICTOIRE/
## DÉFAITE géant à 157 px (`Comic.SIZE_157`, jeton typo « display », §4.1
## échelle 1,333) révélé par le même balayage de 280 ms (`Comic.DUR_WIPE`) et
## la même trame de célébration de 1,5 s (`KitTrame`, INCHANGÉS — seules les
## COULEURS changent, §6 « "VICTOIRE" signal sur encre ou "DÉFAITE" paper sur
## vital »), score à 118 px (`Comic.SIZE_118`), carte MVP, tableau des
## scores, CTA « REJOUER » jaune signal incliné à 12° (§4.3 « boutons...
## inclinés ») / « MENU » en plaque charbon. RELATIF au joueur local
## (docs/research/04_ui_ux.md §2.3 « Fin de match : VICTOIRE/DÉFAITE pour toi,
## pas ÉQ.1 GAGNE »), jamais "ÉQUIPE X GAGNE".
##
## ATTENTION contrat verrouillé (tests/ui/test_team_relative.gd, hors
## périmètre d'écriture de cette tâche) :
## - `_header` reste un `BrushHeader` dont `.title` vaut EXACTEMENT "Victoire"
##   / "Défaite" (le test lit cette propriété directement) — le bandeau
##   géant `_result_label` ci-dessous s'AJOUTE à `_header`, il ne le remplace
##   pas.
## - `_score_label` garde exactement sa construction actuelle (texte
##   "<local> — <autre>", couleur ALLY/ennemi) — le test lit `.text` et
##   `get_theme_color("font_color")`.
## - `_list` : mêmes règles que ScoreboardPanel — chaque enfant direct DOIT
##   rester un `Label` réel (le test caste `as Label` puis lit `.text` sans
##   vérifier la nullité), et les DEUX en-têtes d'équipe ("<glyphe> ÉQUIPE
##   <n>") restent les seuls à commencer par "●"/"▼" — voir `_player_row`.
##
## Carte MVP — résolu (relance QA ART-36, 2e passage) : `player_info`
## (GameWorld.gd, hors de ma liste de fichiers) ne porte toujours que
## nom/équipe/kills/morts/is_bot (voir GameWorld.gd:551), et reste verrouillé
## par tests/ui/test_team_relative.gd (`FakeMatch`, lignes 54-55 : «
## Scoreboard/EndPanel ne lisent que `player_info`, jamais GameWorld.gd
## lui-même ») — ce panneau ne lit donc toujours QUE `player_info` sur
## `match_node`, jamais un autre membre/méthode de GameWorld. L'aplat de
## l'agent (docs/STYLE_BIBLE.md §8.6) vient à la place d'un paramètre optionnel
## `agent_colors` (id de pair -> `Color`) sur `show_result`, résolu par
## GameHUD.gd -- HORS de ma liste de fichiers pour CETTE tâche (contrat
## `plan.py prompt UX-34`), mais dont les call-sites (`show_result`/
## `show_death`) ont dû être resynchronisés par une passe précédente pour
## suivre la signature élargie ci-dessous (voir `blocked_on` du rendu de
## tâche) -- qui, lui, PEUT parcourir les `PlayerController` réels sous
## `players_root` (agent_index répliqué "spawn only", couvre bots ET humains
## même après le spawn — voir `GameHUD._agent_colors_for_match`) et résoudre
## `AgentDatabase.get_by_index`.
## `agent_colors` défaut `{}` (rétrocompatible : les tests existants qui
## appellent `show_result` sans ce 6e argument gardent le repli couleur
## d'ÉQUIPE ci-dessous) — un id absent de `agent_colors` (capture isolée sans
## match réel, id inconnu) retombe sur Comic.ALLY / Comic.enemy_color(),
## JAMAIS une couleur d'agent inventée.
class_name EndPanel
extends Control

signal replay_pressed
signal menu_pressed

var _header: BrushHeader
var _result_stage: Control
var _result_band: ColorRect
var _result_label: Label
var _result_trame: KitTrame
var _result_tween: Tween
var _score_label: Label
## UX-34, REVUE LEAD point 2 (« chiffre allié en couleur ally, chiffre ennemi
## en couleur enemy, tiret paper ») -- `_score_label` ci-dessus reste
## construit EXACTEMENT comme avant (texte/couleur verrouillés par
## `tests/ui/test_team_relative.gd`, voir la note de tête de fichier), mais
## reste désormais INVISIBLE (même patron que `_header`/`BrushHeader`
## ci-dessus) : le VRAI score 118 affiché est `_score_row`, 3 labels
## distincts (allié/tiret/ennemi) chacun avec SA propre couleur fixe
## (RELATIVE au joueur local, jamais conditionnée par la victoire) -- un
## `Label` unique ne peut pas porter 2 couleurs différentes dans le même
## texte.
var _score_row: HBoxContainer
var _score_ally_label: Label
var _score_enemy_label: Label
var _mvp_slot: Control
var _list: VBoxContainer
## Bandeau « Revanche dans N s… » (FUN-01) -- alimenté par le signal
## `GameWorld.rematch_countdown` du `match_node` reçu par `show_result` (voir
## `_on_rematch_countdown`), jamais par GameHUD.gd (hors de ma liste de
## fichiers) : ce panneau s'abonne lui-même, sans dépendre d'un appel externe
## par-frame.
var _rematch_label: Label
## Dernier `match_node` connu (voir `show_result`) -- sert à ne (re)connecter
## `rematch_countdown` qu'une fois par match_node distinct, et à s'en
## déconnecter proprement s'il change.
var _rematch_source: Node = null
## Bouton « Retour au menu » -- exposé (comme `_header`/`_score_label`/`_list`
## déjà lus directement par tests/ui/test_team_relative.gd) pour que
## tests/networking/test_rematch.gd puisse déclencher SA vraie poignée
## `pressed` (voir sa doc) plutôt que simuler `menu_pressed` à la main.
var _menu_button: Button
## CTA « Rejouer » (v4, UX-34) — exposé pour `tests/ui/test_end_screens_v4.gd`
## (couleur/forme du bouton jaune, contrat de CETTE tâche) ; `replay_pressed`
## reste la seule chose que `GameHUD.gd` (hors de ma liste de fichiers)
## observe, ce champ n'ajoute donc aucun nouveau contrat externe.
var _replay_button: Button

func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Comic.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# UX-34, retour vérificateur (3e passage, captures reports/checkpoints/
	# 2026-09-25_UX-34/02_end_*.jpg) -- l'essai précédent (`ScrollContainer`
	# PAGE ENTIÈRE enveloppant tout `wrap`, y compris VICTOIRE/score/MVP) a été
	# capturé et vérifié RENDU (pas seulement en test unitaire) : la scène
	# reste scrollée à son sommet par défaut, donc REJOUER/MENU restaient hors
	# cadre dans la capture RÉELLE aux deux résolutions -- exactement le défaut
	# que le vérificateur a signalé, un test unitaire qui ne vérifie que la
	# présence/absence d'un `ScrollContainer` ne peut PAS détecter un
	# défilement qui existe mais n'est jamais parcouru. Nouvelle structure : la
	# scène du titre (`_result_stage`, hauteur FIXE 210) et la carte
	# (`content_row` -> `panel`) sont deux enfants EMPILÉS d'un `VBoxContainer`
	# plein écran (`page`) -- `content_row` porte `size_flags_vertical =
	# EXPAND_FILL`, il reçoit donc TOUJOURS exactement le reste de la hauteur
	# de l'écran sous le titre (Godot 4.7, BoxContainer : un enfant EXPAND se
	# voit attribuer l'espace restant après les enfants de taille fixe). SEUL
	# `_list` (le roster, potentiellement long) est enveloppé d'un
	# `ScrollContainer` -- voir plus bas -- de sorte que VICTOIRE/DÉFAITE,
	# score, MVP, bandeau de revanche ET les deux CTA restent des enfants de
	# taille FIXE de `box` : un `VBoxContainer` ne réduit JAMAIS un enfant de
	# taille fixe en dessous de son minimum, ils gardent donc TOUJOURS leur
	# place entière et ne peuvent plus jamais sortir du cadre -- seul le
	# roster, enfant EXPAND, absorbe le manque d'espace en devenant
	# défilable (voir la note de `list_scroll`).
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 0)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)

	_header = BrushHeader.new()
	_header.title = "Victoire"
	# Invisible en v4 -- `_header` (bandeau pinceau rouge v3) reste construit
	# UNIQUEMENT pour que `_header.title` continue de valoir EXACTEMENT
	# "Victoire"/"Défaite" (contrat verrouillé, voir la note de tête de
	# fichier) ; son rendu visuel double désormais `_result_label` (157 px,
	## voir plus bas) -- capture UX-34 : les deux bandeaux « VICTOIRE »
	# superposés (rouge minuscule + jaune géant) sont un doublon visuel que
	# §6 ne demande pas, jamais un second bandeau derrière le nouveau. Un
	# `Control` invisible (`visible = false`) sort aussi son créneau du
	# `VBoxContainer` `wrap` (les Container ignorent les enfants invisibles),
	# donc aucun espace vide résiduel.
	_header.visible = false
	page.add_child(_header)

	# UX-34, REVUE LEAD point 1 (capture 02 : « VICTOIRE »/« DÉFAITE » rognées
	# par la plaque de score EN DESSOUS) -- une hauteur de scène de 150 px était
	# plus courte que la boîte réelle d'un glyphe à 157 px (Comic.SIZE_157)
	# avec contour 5 px + ombre dure (8, 8) : le `ComicPanel` du score, ajouté
	# JUSTE APRÈS dans ce même `VBoxContainer`, se dessinait donc PAR-DESSUS la
	# moitié basse du titre qui débordait de sa scène. `clip_contents = true`
	# aggravait encore la coupe (le HAUT du titre était en plus tronqué par la
	# scène elle-même). 210 px (grille de 6 : 35 x 6) laisse la marge
	# nécessaire aux ascendantes/descendantes de l'italique + l'ombre, sans
	# `clip_contents` : le titre entier reste toujours AU-DESSUS du contenu qui
	# suit, jamais recouvert.
	_result_stage = Control.new()
	_result_stage.custom_minimum_size = Vector2(0, 210)
	_result_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_result_stage)

	_result_band = ColorRect.new()
	_result_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Comic.anchor(_result_band, Control.PRESET_FULL_RECT)
	_result_band.anchor_right = 0.0
	_result_stage.add_child(_result_band)

	_result_trame = KitTrame.new()
	_result_trame.ink_variant = false  # pinceau : fond déjà saturé (bleu/magenta), voir KitTrame.gd
	_result_trame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_stage.add_child(_result_trame)

	# v4 §6 : 157 px, contour 5 (`STROKE_DISPLAY`, titres >= 88 px) + ombre
	# dure (8, 8) « moments héros » (§4.3) — lisible quelle que soit la
	# couleur de fond posée par `_play_result_wipe` (encre en victoire, vital
	# en défaite). La couleur du TEXTE (signal/paper) est recolorée à chaque
	# `show_result`, voir `_play_result_wipe`.
	_result_label = Comic.title_label_v4("", Comic.SIZE_157, Comic.TEXT)
	_result_label.add_theme_constant_override("outline_size", Comic.STROKE_DISPLAY)
	_result_label.add_theme_color_override("font_outline_color", Comic.ink_color())
	_result_label.add_theme_color_override("font_shadow_color", Comic.ink_color())
	_result_label.add_theme_constant_override("shadow_offset_x", int(Comic.SHADOW_HOVER_OFFSET.x))
	_result_label.add_theme_constant_override("shadow_offset_y", int(Comic.SHADOW_HOVER_OFFSET.y))
	_result_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.clip_text = true
	_result_label.modulate.a = 0.0
	_result_stage.add_child(_result_label)

	# `content_row` : ligne EXPAND (voir la note ci-dessus) large de TOUT
	# l'écran, avec deux ressorts (`Control` EXPAND_FILL horizontal) de part et
	# d'autre de la carte de 820 px -- centre la carte horizontalement (deux
	# ressorts de même ratio de 1) SANS `CenterContainer` (qui redonnerait sa
	# propre taille MINIMALE à la carte, jamais la hauteur RÉELLE disponible,
	# voir la note ci-dessus) : un `HBoxContainer` étire nativement chacun de
	# ses enfants à sa pleine hauteur dans l'axe transversal (Godot 4.7,
	# `Control.size_flags_vertical` par défaut = FILL), `panel` reçoit donc
	# TOUJOURS exactement la hauteur de `content_row`, jamais sa propre taille
	# minimale.
	var content_row := HBoxContainer.new()
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.add_theme_constant_override("separation", 0)
	content_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(content_row)

	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_row.add_child(left_spacer)

	var panel := ComicPanel.new()
	panel.custom_minimum_size = Vector2(820, 0)
	panel.bg_color = Comic.PANEL
	panel.border_width = Comic.RULE_W
	# UX-34, REVUE LEAD point 3/6 -- marge resserrée (SP_4 au lieu de SP_5/
	# SP_6) : avec la scène de titre à 210 px ET un roster potentiellement long
	# désormais défilable SEUL (voir `list_scroll`), les autres éléments fixes
	# (score/MVP/CTA) doivent tenir dans le reste de la hauteur aux DEUX
	# résolutions, sans jamais toucher `ROW_HEIGHT_PX`/les tailles de police
	# contractuelles.
	panel.content_margin = Comic.SP_4
	content_row.add_child(panel)

	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_row.add_child(right_spacer)

	var box := VBoxContainer.new()
	# SP_1 (au lieu de SP_2/SP_3) -- même raison : garde REJOUER/MENU visibles
	# (jamais coupés) aux DEUX résolutions même avec un roster 4v4 complet
	# (point 6), l'espace économisé ici revient au roster défilable.
	box.add_theme_constant_override("separation", Comic.SP_1)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.body.add_child(box)

	# v4 §6 « score 118 » — `Comic.number_label_v4` (tabulaire italique, §4.1
	# « chiffres toujours italiques ») ; le TEXTE et la COULEUR (`ALLY`/
	# `enemy_color()`) restent le contrat verrouillé de `tests/ui/
	# test_team_relative.gd`, seuls la taille/la police changent ici.
	_score_label = Comic.number_label_v4("", Comic.SIZE_118, Comic.ALLY)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Invisible (voir la note de déclaration de `_score_row` ci-dessus) --
	# `Control.visible = false` sort aussi son créneau du `VBoxContainer` `box`
	# (les Container ignorent les enfants invisibles), donc aucun espace vide
	# résiduel au-dessus du vrai score.
	_score_label.visible = false
	box.add_child(_score_label)

	# Score v4 RÉEL (§6 « score 118 ») -- 3 labels : chiffre allié (`Comic.
	# ALLY`, TOUJOURS le joueur local, jamais conditionné par la victoire),
	# tiret `paper`, chiffre ennemi (`Comic.enemy_color()`). Ordre local
	# d'abord (même convention que `_score_label.text` ci-dessus, `my_index`).
	_score_row = HBoxContainer.new()
	_score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_score_row.add_theme_constant_override("separation", Comic.SP_2)
	box.add_child(_score_row)
	_score_ally_label = Comic.number_label_v4("", Comic.SIZE_118, Comic.ALLY)
	_score_row.add_child(_score_ally_label)
	_score_row.add_child(Comic.number_label_v4("—", Comic.SIZE_118, Comic.paper_color()))
	_score_enemy_label = Comic.number_label_v4("", Comic.SIZE_118, Comic.enemy_color())
	_score_row.add_child(_score_enemy_label)

	# `CenterContainer`, PAS un `Control` nu (bug de recouvrement corrigé,
	# relance QA ART-36 2e passage) : un `Control` simple ne remonte JAMAIS la
	# taille mini de son enfant à `box` (VBoxContainer) — `box` lui réservait
	# donc une hauteur de ZÉRO tout en laissant `card` (ComicPanel, taille mini
	# imposée par Godot même hors Container) se dessiner par-dessus le
	# `ScrollContainer` suivant (`_list`), ÉQUIPE 1/« Joueur 1 » illisibles
	# sous la carte MVP. `CenterContainer` calcule sa propre taille mini à
	# partir de son enfant ET le centre — `box` réserve alors la vraie place.
	_mvp_slot = CenterContainer.new()
	box.add_child(_mvp_slot)

	# UX-34, REVUE LEAD point 3 (« la spec §6 "Fin" ne contient PAS de liste de
	# joueurs ... sinon, si un test verrouillé l'exige, l'afficher entière sans
	# barre de défilement ni rognage, 8 joueurs en 1080p ET 720p ») --
	# `tests/ui/test_team_relative.gd` (hors de ma liste de fichiers, voir la
	# note de tête de fichier) lit `ep._list.get_children()` et exige les
	# DEUX en-têtes d'équipe : `_list` reste donc un contrat verrouillé, TOUJOURS
	# rempli en entier (aucune ligne tronquée, `show_result` en ajoute une par
	# joueur, jamais un sous-ensemble). Retour vérificateur (3e passage) : un
	# roster 4v4 (8 lignes) ne tient PAS dans le reste de la hauteur au format
	# 720p une fois VICTOIRE (210) + score 118 + MVP + CTA soustraits (mesuré en
	# capture, voir le rendu de tâche) -- `list_scroll` (`ScrollContainer`,
	# défilement VERTICAL seul) enveloppe désormais `_list` SEUL (jamais
	# VICTOIRE/score/MVP/CTA, voir la note de `content_row` ci-dessus) :
	# `size_flags_vertical = EXPAND_FILL` lui donne tout l'espace RESTANT sous
	# les éléments fixes de `box` -- au delà, il défile ; en deçà (1080p avec un
	# roster court, ou un duel 1v1), il n'y a simplement rien à faire défiler.
	# Aucune ligne n'est jamais coupée : le roster ENTIER reste dans l'arbre
	# (`_list.get_child_count()`), seule sa PRÉSENTATION peut nécessiter un
	# défilement local plutôt que pousser REJOUER/MENU hors du cadre.
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(list_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", Comic.SP_1)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_list)

	# FUN-01 : bandeau de revanche automatique, entre le tableau des scores et
	# les boutons -- vide par défaut (aucun compte à rebours en cours), voir
	# `_on_rematch_countdown`. `Control.visible = false` tant que le texte est
	# vide (retour vérificateur 3e passage : un `Label` vide réserve quand même
	# la hauteur d'une ligne dans un `VBoxContainer`, cet espace perdu manque
	# aux CTA sur les petits écrans) -- sort alors son créneau de `box` (les
	# Container ignorent les enfants invisibles), voir `_set_rematch_text`.
	_rematch_label = Comic.label("", Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_BODY)
	_rematch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rematch_label.visible = false
	box.add_child(_rematch_label)

	# CTA « REJOUER » v4 (§6, §4.3 « boutons... inclinés ») : parallélogramme
	# 12° (`Comic.SLANT_DEG`, même cisaillement que `ScoreboardPanel.
	# _slant_style`), fond `signal` (jaune, seule couleur qui désigne),
	# texte/trait `ink` -- voir `_slant_cta_style`.
	_replay_button = Button.new()
	_replay_button.text = "REJOUER"
	_replay_button.custom_minimum_size = Vector2(0, 64)
	_replay_button.add_theme_font_override("font", Comic.button_font_v4())
	_replay_button.add_theme_font_size_override("font_size", Comic.SIZE_37)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_replay_button.add_theme_color_override(state, Comic.ink_color())
	_replay_button.add_theme_stylebox_override("normal", _slant_cta_style(Comic.signal_color()))
	_replay_button.add_theme_stylebox_override("hover", _slant_cta_style(Comic.signal_color().lightened(0.1)))
	_replay_button.add_theme_stylebox_override("pressed", _slant_cta_style(Comic.signal_color().darkened(0.1)))
	_replay_button.add_theme_stylebox_override("focus", Comic.focus_style())
	_replay_button.pressed.connect(func(): replay_pressed.emit())
	box.add_child(_replay_button)

	# « MENU » v4 : même forme inclinée, fond `plate` charbon (secondaire,
	# jamais jaune -- §4.2 « le jaune ne sert qu'à l'action immédiate »),
	# texte `paper`.
	_menu_button = Button.new()
	_menu_button.text = "MENU"
	_menu_button.custom_minimum_size = Vector2(0, 56)
	_menu_button.add_theme_font_override("font", Comic.button_font_v4())
	_menu_button.add_theme_font_size_override("font_size", Comic.SIZE_28)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_menu_button.add_theme_color_override(state, Comic.paper_color())
	_menu_button.add_theme_stylebox_override("normal", _slant_cta_style(Comic.plate_color()))
	_menu_button.add_theme_stylebox_override("hover", _slant_cta_style(Comic.plate_hi_color()))
	_menu_button.add_theme_stylebox_override("pressed", _slant_cta_style(Comic.plate_hi_color()))
	_menu_button.add_theme_stylebox_override("focus", Comic.focus_style())
	# FUN-01 : « Menu » quitte proprement -- efface tout de suite l'affichage
	# local du compte à rebours (ce panneau est sur le point d'être quitté/cette
	# scène remplacée par GameHUD.gd, hors de ma liste de fichiers) avant
	# d'émettre le signal existant, pour ne laisser aucun texte de revanche
	# résiduel si ce panneau devait rester visible un instant de plus.
	_menu_button.pressed.connect(func():
		_set_rematch_text("")
		menu_pressed.emit())
	box.add_child(_menu_button)

## `local_team` : équipe du joueur local (`PlayerController.team`) — décide
## VICTOIRE/DÉFAITE et quel score va à gauche, voir `Comic.is_ally`.
## `agent_colors` : id de pair -> aplat couleur-clé de l'agent joué, résolu par
## l'appelant (voir la note de tête de fichier sur la carte MVP) — optionnel,
## `{}` par défaut pour les appelants existants (tests verrouillés compris).
func show_result(winner_team: int, team0: int, team1: int, match_node: Node, local_team: int, agent_colors: Dictionary = {}) -> void:
	visible = true
	_subscribe_rematch_countdown(match_node)
	var victory := Comic.is_ally(winner_team, local_team)
	var title := "Victoire" if victory else "Défaite"
	var accent := Comic.ALLY if victory else Comic.enemy_color()
	_header.title = title
	_header.replay()
	# v4 §6 : "VICTOIRE" signal sur encre ; "DÉFAITE" paper sur vital.
	var band_color := Comic.ink_color() if victory else Comic.vital_color()
	var result_text_color := Comic.signal_color() if victory else Comic.paper_color()
	_play_result_wipe(title, band_color, result_text_color)
	var my_index := local_team if local_team in [0, 1] else 0
	var other_index := 1 - my_index
	var scores := [team0, team1]
	_score_label.text = "%d — %d" % [scores[my_index], scores[other_index]]
	_score_label.add_theme_color_override("font_color", accent)
	# UX-34 REVUE LEAD point 2 -- score RÉEL, digit par digit (voir la note de
	# `_score_row`) : `scores[my_index]` reste TOUJOURS le score allié
	# (couleur fixe `Comic.ALLY` posée à la construction), `scores[other_index]`
	# TOUJOURS l'ennemi (`Comic.enemy_color()`), indépendamment de qui gagne.
	_score_ally_label.text = str(scores[my_index])
	_score_enemy_label.text = str(scores[other_index])
	for c in _list.get_children():
		c.queue_free()
	for c in _mvp_slot.get_children():
		c.queue_free()
	if match_node == null or not is_instance_valid(match_node):
		return
	var info: Dictionary = match_node.player_info
	var mvp := _mvp_card(info, local_team, agent_colors)
	if mvp != null:
		_mvp_slot.add_child(mvp)
	for team in [0, 1]:
		var is_ally := Comic.is_ally(team, local_team)
		var team_color := Comic.ALLY if is_ally else Comic.enemy_color()
		_list.add_child(Comic.label("%s ÉQUIPE %d" % [Comic.team_glyph(is_ally), team + 1], Comic.SIZE_BODY, team_color, Comic.FONT_NUMBER))
		var ids: Array = []
		for id in info:
			if int(info[id].team) == team:
				ids.append(id)
		ids.sort_custom(func(a, b): return int(info[a].kills) > int(info[b].kills))
		for id in ids:
			_list.add_child(_player_row(id, info[id], is_ally, team_color))

func hide_result() -> void:
	visible = false
	_set_rematch_text("")
	if _result_tween and _result_tween.is_valid():
		_result_tween.kill()
	if _result_trame:
		_result_trame.clear()

## S'abonne au signal `rematch_countdown` de `source` (GameWorld, FUN-01) --
## idempotent (un `match_node` déjà connu n'est pas reconnecté) et propre (se
## déconnecte de l'ancienne source avant d'en adopter une nouvelle, ex. un
## nouveau `match_node` après un changement de scène). Duck-typing
## (`has_signal`) : `source` reste un `Node` nu ici, exactement comme
## `show_result` le reçoit déjà -- GameWorld.gd n'est jamais un type statique
## imposé à ce fichier.
func _subscribe_rematch_countdown(source: Node) -> void:
	if source == _rematch_source:
		return
	if _rematch_source != null and is_instance_valid(_rematch_source) \
			and _rematch_source.has_signal("rematch_countdown") \
			and _rematch_source.rematch_countdown.is_connected(_on_rematch_countdown):
		_rematch_source.rematch_countdown.disconnect(_on_rematch_countdown)
	_rematch_source = source
	_set_rematch_text("")
	if source != null and is_instance_valid(source) and source.has_signal("rematch_countdown"):
		source.rematch_countdown.connect(_on_rematch_countdown)

## Callback de `GameWorld.rematch_countdown` (FUN-01) -- `seconds_left` < 0 :
## revanche automatique abandonnée (majorité des humains partie), bandeau
## effacé ; sinon affiche le compte à rebours SERVEUR tel quel (jamais une
## minuterie locale qui pourrait diverger du délai réel avant le prochain
## spawn).
func _on_rematch_countdown(seconds_left: int) -> void:
	if seconds_left < 0:
		_set_rematch_text("")
		return
	_set_rematch_text("Revanche dans %d s…" % seconds_left)

## Retour vérificateur (3e passage) : `_rematch_label` ne réserve sa place
## dans `box` QUE quand elle porte un vrai texte (voir sa note de
## déclaration) -- un `Label` vide masqué (`visible = false`) sort son
## créneau du `VBoxContainer`, rendant cet espace aux CTA sur les petits
## écrans plutôt que de le perdre en permanence pour un bandeau qui ne
## s'affiche qu'en de rares fins de match (revanche automatique).
func _set_rematch_text(text: String) -> void:
	_rematch_label.text = text
	_rematch_label.visible = not text.is_empty()

## Ligne joueur en barre inclinée — même règle que ScoreboardPanel._player_row
## (voir la note de tête de fichier : `_list` ne peut recevoir que des `Label`
## réels, jamais un `Container`).
func _player_row(id, p: Dictionary, is_ally: bool, team_color: Color) -> Label:
	var is_local := int(id) == multiplayer.get_unique_id()
	var suffix := "   (toi)" if is_local else ""
	var row := "   %s  %-18s   %d / %d%s" % [Comic.team_glyph(is_ally), str(p.name), int(p.kills), int(p.deaths), suffix]
	var lbl := Comic.label(row, Comic.SIZE_BODY, Comic.TEXT if is_local else Comic.TEXT_DIM, Comic.FONT_BODY)
	var bg := Comic.PANEL_HI if is_local else Comic.PANEL
	var border := team_color if is_local else Comic.RULE
	lbl.add_theme_stylebox_override("normal", _slant_style(bg, border))
	return lbl

## Barre inclinée — voir ScoreboardPanel._slant_style (même jetons, dupliqué
## ici car Comic.gd est hors de ma liste de fichiers).
func _slant_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(Comic.RULE_W)
	s.border_color = border
	s.set_corner_radius_all(Comic.RADIUS_SLANT)
	s.skew = Vector2(tan(deg_to_rad(Comic.SLANT_DEG)), 0.0)
	s.content_margin_left = Comic.SP_3
	s.content_margin_right = Comic.SP_3
	s.content_margin_top = Comic.SP_1
	s.content_margin_bottom = Comic.SP_1
	s.anti_aliasing = true
	return s

## Bouton CTA v4 (§4.3 « boutons... inclinés », `Comic.SLANT_DEG` = 12°,
## même cisaillement que `_slant_style` ci-dessus) : trait `STROKE_INK`
## (3 px, plus marqué que le filet `RULE_W` des lignes de score), jamais un
## radius (`Comic.RADIUS_SLANT` = 0), marges généreuses pour un CTA (SP_5/
## SP_3) plutôt que les marges resserrées d'une ligne de tableau.
func _slant_cta_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(Comic.STROKE_INK)
	s.border_color = Comic.ink_color()
	s.set_corner_radius_all(Comic.RADIUS_SLANT)
	s.skew = Vector2(tan(deg_to_rad(Comic.SLANT_DEG)), 0.0)
	s.content_margin_left = Comic.SP_5
	s.content_margin_right = Comic.SP_5
	s.content_margin_top = Comic.SP_3
	s.content_margin_bottom = Comic.SP_3
	s.anti_aliasing = true
	return s

## Carte MVP : meilleur `kills` (égalité départagée par le moins de `deaths`,
## puis par id pour rester déterministe) — jamais de damage/précision/
## headshots inventés (absents de `player_info`, voir la note de tête de
## fichier). `null` si `info` est vide (état VIDE : pas de carte plutôt qu'une
## carte à zéro). `accent` : aplat couleur-clé de l'agent joué par le MVP si
## `agent_colors` le connaît (voir la note de tête de fichier), sinon repli
## honnête sur l'aplat couleur d'ÉQUIPE — jamais une couleur d'agent inventée.
func _mvp_card(info: Dictionary, local_team: int, agent_colors: Dictionary = {}) -> Control:
	if info.is_empty():
		return null
	var mvp_id = null
	for id in info:
		if mvp_id == null:
			mvp_id = id
			continue
		var a: Dictionary = info[id]
		var b: Dictionary = info[mvp_id]
		if int(a.kills) > int(b.kills) or (int(a.kills) == int(b.kills) and int(a.deaths) < int(b.deaths)):
			mvp_id = id
	var mvp: Dictionary = info[mvp_id]
	var is_ally := Comic.is_ally(int(mvp.team), local_team)
	var team_accent := Comic.ALLY if is_ally else Comic.enemy_color()
	var accent: Color = agent_colors[mvp_id] if agent_colors.has(mvp_id) else team_accent

	# v4 §3 « les contenants ont des coins coupés » -- ComicPanel.gd (v3,
	# coins arrondis, hors de ma liste de fichiers) ne les pose pas ; plaque
	# `Comic.plate_style()` + ombre dure portée, voir `_build_plate`.
	var plate := _build_plate(Vector2(260.0, 0.0), accent)
	var card: Control = plate.host
	var body: PanelContainer = plate.body

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Comic.SP_1)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(box)

	var kicker := Comic.meta_label_v4("MVP", Comic.SIZE_21, Comic.TEXT_ON_BRUSH)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kicker)
	var name_label := Comic.title_label_v4(str(mvp.name), Comic.SIZE_50, Comic.TEXT_ON_BRUSH)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	var stat_label := Comic.number_label_v4("%s   %d / %d" % [Comic.team_glyph(is_ally), int(mvp.kills), int(mvp.deaths)], Comic.SIZE_28, Comic.TEXT_ON_BRUSH)
	stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(stat_label)
	return card

## Plaque v4 minimaliste (coins coupés + ombre dure portée en enfant, §4.3) --
## même construction que `DeathPanel._build_plate` (dupliquée ici, ComicPanel.
## gd/Comic.gd hors de ma liste de fichiers ne l'offrent pas tout faite) :
## `host` porte la taille minimale et se place dans l'arbre, `body`
## (`PanelContainer`, insère ses enfants selon `content_margin_*` du style
## posé) reçoit le contenu.
func _build_plate(min_size: Vector2, bg: Color) -> Dictionary:
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.custom_minimum_size = min_size

	# UX-34, REVUE LEAD point 5 (même défaut que la carte du tueur de
	# DeathPanel.gd, voir sa docstring) -- `Comic.plate_style(Comic.ink_color())`
	# partage le MÊME chamfer que `body` ci-dessous, jamais un rectangle droit
	# (`hard_shadow_style`) qui dépasserait au coin coupé.
	var shadow := PanelContainer.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.add_theme_stylebox_override("panel", Comic.plate_style(Comic.ink_color()))
	Comic.anchor(shadow, Control.PRESET_FULL_RECT)
	shadow.offset_left = Comic.SHADOW_HARD_OFFSET.x
	shadow.offset_top = Comic.SHADOW_HARD_OFFSET.y
	shadow.offset_right = Comic.SHADOW_HARD_OFFSET.x
	shadow.offset_bottom = Comic.SHADOW_HARD_OFFSET.y
	host.add_child(shadow)

	var body := PanelContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_stylebox_override("panel", Comic.plate_style(bg))
	Comic.anchor(body, Control.PRESET_FULL_RECT)
	host.add_child(body)

	# `host` (Control nu) ne remonte JAMAIS sa taille mini tout seul -- `body`
	# (PanelContainer) LUI réémet `minimum_size_changed` à chaque changement
	# de taille mini d'un descendant, à n'importe quelle profondeur
	# (comportement standard des Container Godot, voir la note de ComicPanel.
	# gd) : sans cette resynchronisation, `_mvp_slot` (CenterContainer)
	# donnerait à `host` une taille mini de ZÉRO -- même piège que celui déjà
	# documenté juste au-dessus pour l'ancien `Control` nu remplacé par
	# `CenterContainer` (relance QA ART-36 2e passage).
	body.minimum_size_changed.connect(func() -> void:
		host.custom_minimum_size = body.get_combined_minimum_size()
	)

	return {"host": host, "body": body}

## VICTOIRE/DÉFAITE géant : balayage de gauche à droite en `Comic.DUR_WIPE`
## (280 ms, cubic out — même famille que BrushHeader._play_wipe), puis une
## trame de célébration de 1,5 s (`KitTrame.play(false)` : 0,6 + 0,3 + 0,6 s,
## STYLE_BIBLE §8.6 « wipe 280 ms, trame 1,5 s », INCHANGÉ en v4). Mouvement
## réduit : fondu seul, trame posée en aplat sans balayage (`KitTrame.play`
## gère déjà son propre repli mouvement réduit). `band_color`/`text_color` :
## v4 §6 -- encre+signal en victoire, vital+paper en défaite (voir
## `show_result`), remplace l'ancien texte fixe blanc sur bande d'équipe.
func _play_result_wipe(text: String, band_color: Color, text_color: Color) -> void:
	_result_label.text = text.to_upper()
	_result_label.add_theme_color_override("font_color", text_color)
	_result_band.color = band_color
	if _result_tween and _result_tween.is_valid():
		_result_tween.kill()
	if Comic.reduced_motion():
		_result_band.anchor_right = 1.0
		_result_label.modulate.a = 1.0
		_result_trame.play(false)
		return
	_result_band.anchor_right = 0.0
	_result_label.modulate.a = 0.0
	_result_tween = create_tween()
	_result_tween.tween_method(_set_band_wipe, 0.0, 1.0, Comic.DUR_WIPE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_result_tween.finished.connect(func():
		_result_label.modulate.a = 1.0
		_result_trame.play(false)
	)

func _set_band_wipe(r: float) -> void:
	_result_band.anchor_right = r
	_result_label.modulate.a = r
