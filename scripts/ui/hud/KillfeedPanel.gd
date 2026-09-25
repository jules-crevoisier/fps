## KillfeedPanel.gd
## Pile de cartouches (haut-droite, UI_DIRECTION_BL3.md §5) : 4 maximum à
## 1080p (3 en dessous de `COMPACT_HEIGHT_PX`), 5 s chacune. Couleurs
## RELATIVES au joueur local (docs/research/04_ui_ux.md §2.3, jamais l'indice
## d'équipe brut) : `Comic.is_ally(team, local_team)` décide allié/ennemi pour
## le tueur ET la victime, indépendamment l'un de l'autre — un joueur en
## équipe 1 voit ses propres kills en Allié, ceux de l'équipe 0 en Ennemi.
## Entrée enrichie (docs/research/04_ui_ux.md §2.3 « killfeed standard ») :
## icône d'arme/capacité entre crochets et ✦ de headshot, tous deux
## optionnels — jamais un texte factice quand l'appelant ne connaît pas
## l'information.
## Une entrée de kill LOCAL (contract-r4a.md "R4-FX" #4) est mise en évidence
## par un trait Allié alourdi — jamais le rouge `vital`, réservé aux
## dégâts/erreurs.
## v4 « Encre, jaune, italique » (UX-31, §5 #1 « zéro fond derrière le texte
## du HUD », règle BLOQUANTE, retour QA 2026-09-25) : TOUTES les entrées,
## local comprise, ont désormais un fond ET un trait de PANNEAU à alpha 0
## (`CHIP_BG`) — la maquette suggérait « ta ligne sur plaque » pour l'entrée
## locale, mais §5 règle 1 ne documente aucune exception et le retour QA
## confirme qu'une plaque `plate_hi` à 85 % d'opacité derrière le texte reste
## une violation visible (capture 04_killfeed_local_1080p.jpg, « plaque foncée
## bien visible »). L'entrée locale se distingue donc UNIQUEMENT par un trait
## (pas un remplissage) Allié épais — un contour n'est pas « un fond derrière
## le texte », juste une bordure autour de la ligne — ce qui reste conforme à
## tests/ui/test_team_relative.gd (hors de ma liste de fichiers,
## `panel.border_width == Comic.RULE_W_STRONG` / `panel.border_color ==
## Comic.ALLY`, qui ne teste QUE le trait, jamais `bg_color`) : la classe
## conteneur de chaque entrée reste un `ComicPanel` (typée ainsi par ce test).
## UX-36 (retour lead 2026-09-25) : le texte de l'arme perd ses crochets
## (§5 « arme 21 sans crochets ») -- `tests/ui/test_team_relative.gd` est
## maintenant dans ma liste de fichiers, son assertion `"[RAVAGE]"` mise à
## jour en `"RAVAGE"` (décision du lead, rien d'autre changé dans ce test).
class_name KillfeedPanel
extends VBoxContainer

## 4 entrées à 1080p (UI_DIRECTION_BL3.md §5/§7 `hud.killfeed_entries`), 3 en
## dessous de `COMPACT_HEIGHT_PX` de hauteur PHYSIQUE de fenêtre (720p).
const MAX_ENTRIES_1080 := 4
const MAX_ENTRIES_COMPACT := 3
const COMPACT_HEIGHT_PX := 800
## §7 `hud.killfeed_entries.row_ttl_ms` : 5000 (était 4000 en v3).
const ENTRY_LIFETIME := 5.0
## Glyphe de headshot (contrat UX-01 « ✦ en cas de headshot »).
const HEADSHOT_GLYPH := "✦"
## Fond de TOUTE entrée (ordinaire ou locale, §5 #1) : alpha 0 — le
## `ComicPanel` reste le conteneur (type verrouillé, voir doc de classe) mais
## ne peint plus jamais de remplissage derrière le texte.
const CHIP_BG := Color(Comic.PANEL.r, Comic.PANEL.g, Comic.PANEL.b, 0.0)

func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", Comic.SP_1)
	Comic.anchor(self, Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_top = Comic.SP_7
	offset_right = -Comic.SAFE_MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Seuil sur `get_window().size` — la taille RÉELLE (physique) de la fenêtre
## OS, jamais `get_viewport().get_visible_rect()` : le stretch
## canvas_items+expand du projet garde ce dernier proche de 1920x1080 même à
## 1280x720 (même rapport d'aspect que la base, un seul facteur d'échelle
## uniforme sur les deux axes), donc inutilisable pour détecter la résolution
## physique ici.
func _max_entries() -> int:
	if is_inside_tree() and get_window().size.y <= COMPACT_HEIGHT_PX:
		return MAX_ENTRIES_COMPACT
	return MAX_ENTRIES_1080

## `killer_team`/`victim_team` : indices d'équipe bruts, recolorés ici par
## rapport à `local_team` (jamais une couleur fixée d'avance par l'appelant).
## `victim_team` : -1 si l'équipe de la victime n'a pas pu être résolue par
## l'appelant (ex. nom introuvable dans `player_info`) — la victime reste
## alors en `paper_dim` sans glyphe plutôt que d'inventer un camp.
## `weapon_or_ability` : nom déjà résolu par l'appelant (arme du tireur ou
## capacité active), "" si inconnu — dans ce cas AUCUNE puce n'est affichée
## (jamais un texte factice). `headshot` : seulement `true` quand un tir
## confirmé l'a établi.
func push(killer: String, victim: String, killer_team: int, victim_team: int, local_team: int, is_local: bool = false, weapon_or_ability: String = "", headshot: bool = false) -> void:
	var killer_ally := Comic.is_ally(killer_team, local_team)
	var killer_color := Comic.ALLY if killer_ally else Comic.enemy_color()
	var killer_glyph := Comic.team_glyph(killer_ally)

	var panel := ComicPanel.new()
	panel.bg_color = CHIP_BG
	panel.border_width = Comic.RULE_W_STRONG if is_local else 0
	panel.border_color = Comic.ALLY if is_local else Color(0, 0, 0, 0)
	panel.content_margin = Comic.SP_2
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	move_child(panel, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Comic.SP_1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.body.add_child(row)

	# Ordre FIXE des 5 puces (killer, arme/capacité, headshot, flèche, victime)
	# — texte vide pour les puces optionnelles absentes, jamais retirées de
	# l'arbre : une entrée reste structurellement prévisible (tests, capture).
	row.add_child(Comic.label("%s %s" % [killer_glyph, killer], Comic.SIZE_28, killer_color, Comic.FONT_BOLD))
	# UX-36 (§5 « arme 21 sans crochets ») : nom d'arme/capacité nu, plus de
	# "[...]" -- la puce reste vide (jamais un texte factice) quand inconnue.
	var weapon_text := weapon_or_ability.to_upper()
	row.add_child(Comic.label(weapon_text, Comic.SIZE_21, Comic.paper_dim_color(), Comic.FONT_LABEL))
	row.add_child(Comic.label(HEADSHOT_GLYPH if headshot else "", Comic.SIZE_28, Comic.vital_color(), Comic.FONT_BOLD))
	row.add_child(Comic.label("▸", Comic.SIZE_28, Comic.paper_dim_color(), Comic.FONT_BOLD))
	if victim_team >= 0:
		var victim_ally := Comic.is_ally(victim_team, local_team)
		row.add_child(Comic.label("%s %s" % [Comic.team_glyph(victim_ally), victim], Comic.SIZE_28, Comic.ALLY if victim_ally else Comic.enemy_color(), Comic.FONT_BOLD))
	else:
		row.add_child(Comic.label(victim, Comic.SIZE_28, Comic.paper_dim_color(), Comic.FONT_BOLD))

	# `remove_child` D'ABORD (synchrone) puis `queue_free` : `queue_free()` seul
	# ne retire l'enfant qu'en fin de frame (différé) — un `while` qui ne
	# reteste que `get_child_count()` boucle alors indéfiniment dès qu'il faut
	# retirer plus d'une entrée d'un coup (ex. `max_entries` qui vient de
	# baisser de 4 à 3 après un redimensionnement de fenêtre).
	var max_entries := _max_entries()
	while get_child_count() > max_entries:
		var last := get_child(get_child_count() - 1)
		remove_child(last)
		last.queue_free()

	var tw := panel.create_tween()
	tw.tween_interval(ENTRY_LIFETIME)
	tw.tween_callback(panel.queue_free)
