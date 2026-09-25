## ComicChip.gd
## Tuile penchée de capacité du HUD (bas-centre, UI_DIRECTION_BL3.md §4.3/§5,
## UX-36 -- remplace l'hexagone v3, désormais BANNI : §4.3 « pas d'autre
## forme (hexagones, pastilles supprimés) »). Parallélogramme cisaillé à 12°
## (même géométrie que KitSlantTile/KitSlantBar, dupliquée ici : ce contrôle
## n'est pas interactif -- `KitSlantTile extends BaseButton`, alors qu'un
## badge HUD n'a jamais le focus, `mouse_filter` reste IGNORE partout dans
## GameHUD, voir sa doc de classe). 72 px pour C/A/E, 88 px pour l'ultime X
## (§5 « bas-centre : C · A · E (tuiles penchées 72) + X (88) »).
##
## États de JEU (§5, colonne « bas-centre » -- indépendants des états
## d'interaction du kit : un badge HUD ne reçoit jamais le focus) :
##   Prêt         — papier, glyphe encre.
##   Recharge     — charbon (`plate`), légende en CHIFFRE 37 px (§5 « recharge
##                  = chiffre 37 », remplace le remplissage radial + légende
##                  21 px de l'hexagone v3) : secondes restantes pour une
##                  capacité à cooldown fixe (AbilityBar._apply_state les
##                  calcule depuis le ratio 0..1 de AbilityController.
##                  slot_info() -- hors de mon périmètre d'écriture -- et
##                  Ability.cooldown, reçu de GameHUD.gd) ; pourcentage pour
##                  l'ultime en cours de charge, dont la progression n'est pas
##                  un minuteur pur (gain continu + bonus irréguliers sur
##                  kill/dégâts) -- des secondes y seraient fabriquées et
##                  fausses dès le kill suivant.
##   Charges      — barrettes sous la tuile (§5 « charges = barrettes »,
##                  remplace les pastilles ● v3 -- voir `_draw_bars`).
##   Ultime prêt  — jaune `signal` (Comic.SIGNAL, dont la doc liste « ultime
##                  prêt » parmi les rôles du jaune, §4.2), glyphe encre
##                  (§4.2 règle 4 « jaune = texte encre »), pulsation
##                  d'échelle 1 → 1,05 à 1 Hz (aucune en mouvement réduit,
##                  Comic.reduced_motion()).
##   Désactivé (Duel, Duo) — masqué : AbilityBar ne construit aucun chip
##                  quand `slot_info()` est vide (agent sans capacités), donc
##                  rien à masquer explicitement ici.
class_name ComicChip
extends Control

## Ø tuile HUD (§5 « bas-centre »).
const TILE_SIZE := 72.0
const TILE_SIZE_ULT := 88.0
## Légende de recharge (§5 « recharge = chiffre 37 »).
const CAPTION_SIZE := 37
const _CAPTION_GAP := 6.0
## Barrettes de charge (§5 « charges = barrettes ») -- remplacent les
## pastilles ● v3 (`_draw_pips`).
const _BAR_W := 14.0
const _BAR_H := 6.0
const _BAR_GAP := 4.0
## Encombrement total du plus grand badge (ultime, 88 px) : TOUS les chips
## réservent ce même gabarit -- AbilityBar dimensionne sa barre avant de
## savoir si un chip donné est l'ultime (même parti qu'en v3, où le diamètre
## était de toute façon fixe pour tous). Les tuiles C/A/E (72 px), plus
## petites, restent alignées sur ce même bas de tuile (`TILE_SIZE_ULT - d`
## dans `_draw`), pas sur leur propre haut -- toute la rangée partage la même
## ligne de base, comme le HUD réel de référence.
const SIZE := Vector2(TILE_SIZE_ULT + 16.0, TILE_SIZE_ULT + _CAPTION_GAP + float(CAPTION_SIZE) + _CAPTION_GAP + _BAR_H)

var _key := ""
## Nom de la capacité (setup) — non affiché en match : la maquette HUD du §5
## ne montre que la touche et l'état de la tuile, jamais le nom (réservé à
## l'écran de sélection d'agent, KitSlantTile.tile_title). Conservé pour un
## éventuel usage d'accessibilité futur plutôt que jeté à l'appel.
var _title := ""
var _is_ult := false

var _ready_state := true
var _ratio := 1.0
## -1 = pas de barrettes (ultime), 0 = capacité à charge unique en recharge
## (pas de barrette non plus), > 0 = nombre de charges disponibles.
var _charges := -1

var _caption_label: Label
var _pulse_tween: Tween


func setup(key: String, title: String, is_ult: bool = false) -> void:
	_key = key
	_title = title
	_is_ult = is_ult


## Diamètre EFFECTIF de CETTE tuile (72 ou 88, voir doc de classe).
func tile_diam() -> float:
	return TILE_SIZE_ULT if _is_ult else TILE_SIZE


## Centre du parallélogramme (repère LOCAL du chip) — utilisé par AbilityBar
## pour superposer l'icône peinte (UX-21, composition externe : ComicChip ne
## connaît jamais l'icône elle-même, voir sa doc de classe) sans dupliquer la
## géométrie de `_draw` dans AbilityBar.gd.
func tile_center() -> Vector2:
	var d := tile_diam()
	return Vector2(SIZE.x * 0.5, TILE_SIZE_ULT - d + d * 0.5)


func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false

	_caption_label = Comic.number_label("", CAPTION_SIZE, Comic.paper_color())
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.position = Vector2(0.0, TILE_SIZE_ULT + _CAPTION_GAP)
	_caption_label.size = Vector2(SIZE.x, float(CAPTION_SIZE) + 4.0)
	add_child(_caption_label)

	resized.connect(queue_redraw)


## `text` : légende affichée pendant la recharge ("" quand prêt, voir doc de
## classe). `ready_state` : capacité utilisable (charge disponible ou ultime
## au maximum). `ratio` (0..1) : progression de recharge/accumulation
## d'ultime -- conservé pour un futur indicateur visuel, non dessiné
## aujourd'hui (§5 ne documente que la légende chiffrée, pas un remplissage
## radial pour la tuile penchée). `charges` : voir la doc du champ `_charges`.
func set_status(text: String, ready_state: bool, ratio: float, charges: int) -> void:
	_ready_state = ready_state
	_ratio = clampf(ratio, 0.0, 1.0)
	_charges = charges
	if _caption_label:
		_caption_label.text = text
		_caption_label.add_theme_color_override("font_color", Comic.paper_color() if ready_state else Comic.paper_dim_color())
	_update_pulse()
	queue_redraw()


## Ultime prêt : pulsation d'échelle 1 → 1,05 à 1 Hz (§4.7), désactivée par
## `Comic.reduced_motion()` — même garde que KillWordBurst.gd/LowHealthVignette.gd.
func _update_pulse() -> void:
	var should_pulse := _ready_state and _is_ult and not Comic.reduced_motion()
	if should_pulse:
		if _pulse_tween == null or not _pulse_tween.is_valid():
			pivot_offset = tile_center()
			_pulse_tween = create_tween().set_loops()
			_pulse_tween.tween_property(self, "scale", Vector2(1.05, 1.05), 0.5).set_trans(Tween.TRANS_SINE)
			_pulse_tween.tween_property(self, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)
	else:
		if _pulse_tween and _pulse_tween.is_valid():
			_pulse_tween.kill()
		_pulse_tween = null
		scale = Vector2.ONE


## Parallélogramme cisaillé de `tan(Comic.SLANT_DEG)` sur X, ancré à `origin`,
## de côté `d` — même géométrie que KitSlantTile._slant_points (dupliquée,
## voir doc de classe).
func _slant_points(origin: Vector2, d: float) -> PackedVector2Array:
	var shear := d * tan(deg_to_rad(Comic.SLANT_DEG))
	return PackedVector2Array([
		origin + Vector2(shear, 0.0),
		origin + Vector2(d + shear, 0.0),
		origin + Vector2(d, d),
		origin + Vector2(0.0, d),
	])


func _draw() -> void:
	var d := tile_diam()
	# Bas de tuile aligné sur `TILE_SIZE_ULT` pour toute la rangée (voir doc
	# de `SIZE`) : une tuile C/A/E (72) démarre plus bas qu'une ultime (88),
	# leurs deux bords BAS coïncident.
	var origin := Vector2((SIZE.x - d) * 0.5, TILE_SIZE_ULT - d)
	var body := _slant_points(origin, d)

	var shadow := PackedVector2Array()
	for p in body:
		shadow.append(p + Comic.SHADOW_HARD_SMALL_OFFSET)
	draw_colored_polygon(shadow, Comic.ink_color())

	var ult_ready := _ready_state and _is_ult
	var cooling := not _ready_state
	var fill := Comic.paper_color()
	if ult_ready:
		fill = Comic.signal_color()
	elif cooling:
		fill = Comic.plate_color()
	draw_colored_polygon(body, fill)

	var closed := body.duplicate()
	closed.append(body[0])
	draw_polyline(closed, Comic.ink_color(), Comic.STROKE_INK)

	# Contenu (glyphe + touche) : encre sur papier/jaune (§4.2 règle 4 « jaune
	# = texte encre ») ; papier sur charbon (Recharge).
	var content_color := Comic.paper_color() if cooling else Comic.ink_color()

	# Glyphe abstrait (losange) -- jamais un pictogramme figuratif, hors
	# périmètre de cette tâche (même choix que KitSlantTile/KitHexagon.gd) ;
	# AbilityBar superpose l'icône peinte de la capacité par-dessus, en
	# composition externe (voir doc de classe).
	var center := origin + Vector2(d, d) * 0.5
	var half := d * 0.16
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -half), center + Vector2(half, 0.0),
		center + Vector2(0.0, half), center + Vector2(-half, 0.0),
	]), content_color)

	_draw_key_tab(origin, d, content_color)
	_draw_bars()


## Touche en haut-gauche de la tuile, suivant le cisaillement du bord haut —
## même tracé que KitSlantTile._draw (`key_label`).
func _draw_key_tab(origin: Vector2, d: float, color: Color) -> void:
	if _key == "":
		return
	var kc := origin + Vector2(d * tan(deg_to_rad(Comic.SLANT_DEG)) + Comic.SP_2, Comic.SP_2)
	KitStates.draw_centered_string(self, Comic.title_font(), kc, _key, Comic.SIZE_21, color)


## Barrettes de charge (§5 « charges = barrettes »), centrées sous la
## légende — position FIXE (indépendante de `tile_diam()`) : toute la rangée
## (tuiles 72 et 88) partage la même ligne de barrettes, comme la légende.
func _draw_bars() -> void:
	if _charges <= 0:
		return
	var y := TILE_SIZE_ULT + _CAPTION_GAP + float(CAPTION_SIZE) + _CAPTION_GAP + _BAR_H * 0.5
	var total_w := float(_charges) * _BAR_W + float(_charges - 1) * _BAR_GAP
	var x0 := SIZE.x * 0.5 - total_w * 0.5
	for i in _charges:
		var x := x0 + float(i) * (_BAR_W + _BAR_GAP)
		draw_rect(Rect2(Vector2(x, y - _BAR_H * 0.5), Vector2(_BAR_W, _BAR_H)), Comic.paper_color(), true)
