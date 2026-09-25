## KillWordBurst.gd
## Onomatopée de confirmation de kill LOCALE (docs/STYLE_BIBLE.md §9.4
## "Confirmation de kill"/"Multi-kill", UI_DIRECTION_BL3.md §5 ligne
## « (0,61 ; 0,31) : mot de kill Bangers 88 + ▼ victime 28 ») : halo
## ComicBurst pinceau (SEUL usage sanctionné, voir ComicBurst.gd) + mot en
## Bangers (Comic.onomatopoeia_label, 88 px — v4, remplace `label_lg` 41 de
## v3, jamais un chiffre — CHK-39), papier + contour encre 5 px (§4.1 « titres
## ≥ 88 px 5 px ») + ombre dure (6, 6) — jamais Protest Revolution, retirée en
## v3. Sous le mot : le nom de la victime (▼, 28 px, couleur ennemi — un kill
## LOCAL ne peut cibler qu'un ennemi). 700 ms (pop 90 ms, maintien, sortie
## 200 ms — HitFeedback.burst_alpha/burst_scale avec les constantes
## KILL_WORD_*), un seul à la fois (`is_busy`, consommé par GameHUD).
## Position v4 : `POS_V4`/`burst_rect_v4` (0,61 ; 0,31) remplacent
## `HitFeedback.burst_rect`/`KILL_WORD_POS` (0,72 ; 0,38, hors de ma liste de
## fichiers, INCHANGÉ et toujours verrouillé tel quel par
## tests/ui/test_hit_feedback.gd) — un seul côté fixe (plus d'alternance
## gauche/droite v2/v3, non demandée par §5 et risquée à ce nouveau
## coefficient, voir la docstring de `burst_rect_v4`).
## Enchaînement (STYLE_BIBLE "Multi-kill") : deux `play()` à moins de
## `HitFeedback.MULTI_KILL_WINDOW` l'un de l'autre postent en plus
## « DOUBLÉ »/« TRIPLÉ »/« GRAND CHELEM » (HitFeedback.multi_kill_label) en h3
## sous l'onomatopée, sur une pastille de trame pinceau (KitTrame,
## ink_variant = false) — ≤ 1,2 s au total, sur sa PROPRE chronologie
## (indépendante du mot-bruit : `is_busy()` ne porte que sur celui-ci, jamais
## sur la pastille). Mouvement réduit (Comic.reduced_motion(), STYLE_BIBLE
## "en mouvement réduit : fondu seul") : fondu conservé, pas de "pop"
## d'échelle — la pastille de trame gère son propre repli mouvement réduit
## (voir KitTrame.play()).
class_name KillWordBurst
extends Control

signal finished

## Position v4 (UI_DIRECTION_BL3.md §5/§7 `hud.kill_word_pos`) : coin
## haut-gauche du burst à 61 %/31 % de la taille de viewport — calculée ICI
## (pas dans HitFeedback.gd, hors de ma liste de fichiers) puisque le
## coefficient a changé (§7 : « [0,72 ; 0,38] -> [0,61 ; 0,31] »). Réutilise
## `HitFeedback.BURST_SIZE` (halo + mot, INCHANGÉ) par simple lecture — pas de
## second nombre magique dupliqué pour la taille du burst.
const POS_V4 := Vector2(0.61, 0.31)

## Rectangle du burst à la position v4 — toujours À DROITE (voir doc de
## classe) : à 61 % de la largeur, le rectangle (largeur `HitFeedback.
## BURST_SIZE.x` = 340) reste entièrement hors de la zone centrale 40 % × 40 %
## (`HudFormat.center_zone_rect`, bord droit à 60 % de la largeur) quelle que
## soit la résolution — CHK-35. Le mirroir gauche de l'ancien `HitFeedback.
## burst_rect(false, ...)` chevaucherait cette zone à ce nouveau coefficient
## (61 % vs 72 % avant), d'où l'abandon de l'alternance de côté.
static func burst_rect_v4(viewport_size: Vector2) -> Rect2:
	return Rect2(viewport_size * POS_V4, HitFeedback.BURST_SIZE)

var _burst: ComicBurst
var _label: Label
var _victim_label: Label
var _elapsed: float = -1.0
var _reduced_motion: bool = false

# ------------------------------------------------------------ Multi-kill (STYLE_BIBLE "Multi-kill")
var _multi_row: Control
var _multi_trame: KitTrame
var _multi_label: Label
var _multi_tween: Tween
var _streak: int = 0
var _last_kill_time: float = -1.0

const _MULTI_ROW_HEIGHT := 56.0
const _MULTI_ROW_GAP := Comic.SP_1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_burst = ComicBurst.new()
	_burst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_burst)
	_label = Comic.onomatopoeia_label("", Comic.SIZE_88, Comic.paper_color())
	# UI_DIRECTION_BL3.md §4.1 « titres >= 88 px : contour 5 px » + §4.3
	# « ombre (6, 6) plaques et CTA » — v4, remplace le 3 px/(3, 3) de v3.
	_label.add_theme_constant_override("outline_size", Comic.STROKE_DISPLAY)
	_label.add_theme_color_override("font_outline_color", Comic.ink_color())
	_label.add_theme_color_override("font_shadow_color", Comic.ink_color())
	_label.add_theme_constant_override("shadow_offset_x", int(Comic.SHADOW_HARD_OFFSET.x))
	_label.add_theme_constant_override("shadow_offset_y", int(Comic.SHADOW_HARD_OFFSET.y))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Comic.anchor(_label, Control.PRESET_TOP_WIDE)
	_label.offset_bottom = float(Comic.SIZE_88) + Comic.SP_3
	add_child(_label)
	# Victime (▼, 28 px, §5) — sous le mot, encrée directement (§5 #1 « zéro
	# fond derrière le texte du HUD »). Couleur ennemi : un kill LOCAL ne peut
	# cibler qu'un ennemi (voir Comic.is_ally), rafraîchie à chaque
	# `_apply_victim` plutôt que figée ici (`Comic.enemy_color()` suit
	## `Settings.enemy_color` en direct, comme partout ailleurs dans ce fichier).
	_victim_label = Comic.ink_label("", Comic.SIZE_28, Comic.enemy_color(), Comic.meta_font_v4(Comic.SIZE_28))
	_victim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Comic.anchor(_victim_label, Control.PRESET_TOP_WIDE)
	_victim_label.offset_top = float(Comic.SIZE_88) + Comic.SP_3
	_victim_label.offset_bottom = float(Comic.SIZE_88) + Comic.SP_3 + float(Comic.SIZE_28) + Comic.SP_2
	_victim_label.visible = false
	add_child(_victim_label)
	_build_multi_row()
	_reduced_motion = Comic.reduced_motion()
	set_process(false)

## Ligne « DOUBLÉ »/« TRIPLÉ »/« GRAND CHELEM » : cachée par défaut, révélée
## par `_show_multi_kill` uniquement quand un enchaînement est détecté.
func _build_multi_row() -> void:
	_multi_row = Control.new()
	_multi_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_multi_row.visible = false
	Comic.anchor(_multi_row, Control.PRESET_TOP_WIDE)
	_multi_row.offset_bottom = _MULTI_ROW_HEIGHT
	add_child(_multi_row)
	_multi_trame = KitTrame.new()
	_multi_trame.ink_variant = false  # pinceau (STYLE_BIBLE : "pastille de trame pinceau")
	_multi_trame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_multi_row.add_child(_multi_trame)
	_multi_label = Comic.title_label("", Comic.SIZE_DISPLAY_SM, Comic.TEXT_ON_BRUSH)
	_multi_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_multi_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_multi_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_multi_row.add_child(_multi_label)

func is_busy() -> bool:
	return _elapsed >= 0.0

## `rect` : voir `burst_rect_v4` (déjà hors zone centrale, CHK-35). `victim` :
## nom de la victime (▼, §5) — peut être "" si pas encore connu au moment de
## l'appel (voir GameHUD._trigger_kill_word/`set_victim` pour le rattrapage).
func play(word: String, victim: String, rect: Rect2) -> void:
	position = rect.position
	size = rect.size
	pivot_offset = rect.size * 0.5
	_multi_row.offset_top = rect.size.y + _MULTI_ROW_GAP
	_multi_row.offset_bottom = rect.size.y + _MULTI_ROW_GAP + _MULTI_ROW_HEIGHT
	_label.text = word
	_apply_victim(victim)
	visible = true
	_elapsed = 0.0
	set_process(true)
	_apply_frame()
	_update_streak()

## Rattrapage (même limite documentée que GameHUD._last_death_weapon) : la
## victime peut être connue APRÈS `play()` (`GameWorld.kill_logged` arrivant
## après `Weapon.hit_confirmed`, ordre non garanti) — rafraîchit le burst déjà
## affiché SANS relancer son horloge (`_elapsed` intact). Ignoré si le burst
## n'est plus actif (`is_busy()` faux) : rien à rafraîchir.
func set_victim(victim: String) -> void:
	if not is_busy():
		return
	_apply_victim(victim)

func _apply_victim(victim: String) -> void:
	_victim_label.visible = victim != ""
	if victim == "":
		return
	_victim_label.text = "%s %s" % [Comic.team_glyph(false), victim]
	_victim_label.add_theme_color_override("font_color", Comic.enemy_color())

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > HitFeedback.KILL_WORD_DURATION:
		visible = false
		_elapsed = -1.0
		set_process(false)
		finished.emit()
		return
	_apply_frame()

func _apply_frame() -> void:
	scale = Vector2.ONE if _reduced_motion else Vector2.ONE * HitFeedback.burst_scale(_elapsed, HitFeedback.KILL_WORD_IN, HitFeedback.KILL_WORD_HOLD)
	modulate.a = HitFeedback.burst_alpha(_elapsed, HitFeedback.KILL_WORD_IN, HitFeedback.KILL_WORD_HOLD, HitFeedback.KILL_WORD_OUT)

## Enchaînement (STYLE_BIBLE "Multi-kill") : deux kills à moins de
## `HitFeedback.MULTI_KILL_WINDOW` l'un de l'autre comptent pour le MÊME
## streak. Horloge murale (`Time.get_ticks_msec`), indépendante de `_elapsed`
## (le mot-bruit lui-même) — un enchaînement reste détecté même si l'appelant
## (GameHUD._trigger_kill_word) n'a pas encore laissé le mot précédent finir.
func _update_streak() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _last_kill_time >= 0.0 and (now - _last_kill_time) <= HitFeedback.MULTI_KILL_WINDOW:
		_streak += 1
	else:
		_streak = 1
	_last_kill_time = now
	var label_text := HitFeedback.multi_kill_label(_streak)
	if not label_text.is_empty():
		_show_multi_kill(label_text)

## Affiche la pastille de trame pinceau + le libellé, ≤ `MULTI_KILL_WINDOW`
## au total (STYLE_BIBLE : "≤ 1,2 s au total") : `KitTrame.play(true)` la
## révèle puis la fige en aplat (jamais sa propre dissolution à 1,5 s, hors
## budget) — c'est CE nœud qui décide de la couper à temps via `clear()`.
func _show_multi_kill(label_text: String) -> void:
	_multi_label.text = label_text
	_multi_row.visible = true
	_multi_row.modulate.a = 1.0
	_multi_trame.play(true)
	if _multi_tween and is_instance_valid(_multi_tween):
		_multi_tween.kill()
	_multi_tween = _multi_row.create_tween()
	_multi_tween.tween_interval(HitFeedback.MULTI_KILL_WINDOW - Comic.DUR_REDUCED_FADE)
	_multi_tween.tween_property(_multi_row, "modulate:a", 0.0, Comic.DUR_REDUCED_FADE)
	_multi_tween.tween_callback(_hide_multi_kill)

func _hide_multi_kill() -> void:
	_multi_row.visible = false
	_multi_trame.clear()
