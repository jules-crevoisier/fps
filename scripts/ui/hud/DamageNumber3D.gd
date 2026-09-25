## DamageNumber3D.gd
## Chiffre de dégâts flottant en 3D, façon Borderlands/Apex (docs/STYLE_BIBLE.md
## §9.4 "Chiffres de dégâts", jetons docs/style/tokens.json
## "vfx.damage_number") : Barlow Condensed ExtraBold — `Comic.FONT_NUMBER`,
## JAMAIS Bangers (réservée aux onomatopées, CHK-39) — papier + contour encre
## 3 px ; headshot orange `HitFeedback.HEADSHOT_COLOR` ×1,25. Monte de
## `RISE_PX` sur `DURATION`, fondu SEULEMENT sur les `FADE_LAST` dernières
## secondes (`HitFeedback.damage_number_alpha`, pure et testable). L'empilement
## PAR CIBLE (une même cible touchée à moins de `HitFeedback.DAMAGE_STACK_WINDOW`,
## GF-07) reste piloté par l'appelant (Weapon._spawn_damage_number, qui
## possède le dictionnaire cible -> instance) via `apply()` sur l'instance
## EXISTANTE plutôt qu'un nouveau nœud posé par-dessus — cette classe ne
## connaît que SA propre étiquette, jamais la cible ni le dictionnaire
## d'empilement. Minuterie : un seul `Tween` PORTÉ par le nœud lui-même
## (`create_tween`), jamais `get_tree().create_timer()` (règle du projet).
class_name DamageNumber3D
extends Label3D

const FONT_SIZE := 64
const PIXEL_SIZE := 0.007
## STYLE_BIBLE §9.4 / tokens.json vfx.damage_number.
const STROKE_PX := 3
const RISE_PX := 40.0
const DURATION := 0.6
const FADE_LAST := 0.2
const HEADSHOT_SCALE := 1.25
## Conversion px (authored 1080p, cohérente avec `FONT_SIZE`/tokens.json
## hud.sizes_px_1080) -> mètres monde : un "pixel" de police vaut `PIXEL_SIZE`
## mètres, comme `font_size` lui-même est mis à l'échelle par `pixel_size`.
const _RISE_WORLD := RISE_PX * PIXEL_SIZE

var _tween: Tween
var _base_y: float

## Pose un NOUVEAU chiffre à `pos` (léger tremblé horizontal pour ne pas
## superposer deux cibles exactement au même point) et lance son animation.
static func spawn(parent: Node, pos: Vector3, total_dmg: float, headshot: bool, stack_count: int) -> DamageNumber3D:
	var n := DamageNumber3D.new()
	n.font = Comic.FONT_NUMBER
	n.font_size = FONT_SIZE
	n.pixel_size = PIXEL_SIZE
	n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.no_depth_test = true
	n.outline_size = STROKE_PX
	n.outline_modulate = Comic.HARD_SHADOW_COLOR
	parent.add_child(n)
	n.global_position = pos + Vector3(randf_range(-0.15, 0.15), 0.25, 0.0)
	n.apply(total_dmg, headshot, stack_count)
	return n

## Réaffiche pour un nouveau tir empilé (GF-07) : relance l'animation à partir
## de la position/alpha ACTUELLES (jamais reposée à son point de départ
## d'origine) — met à jour texte/couleur/échelle, jamais un second nœud posé
## par-dessus (Borderlands/Apex). Appelée aussi par `spawn()` pour le tout
## premier affichage (`stack_count` = 1).
func apply(total_dmg: float, headshot: bool, stack_count: int) -> void:
	text = str(int(round(total_dmg)))
	modulate = HitFeedback.HEADSHOT_COLOR if headshot else Comic.TEXT
	modulate.a = 1.0
	var stack_scale := HitFeedback.damage_stack_scale(stack_count)
	scale = Vector3.ONE * stack_scale * (HEADSHOT_SCALE if headshot else 1.0)
	if _tween and is_instance_valid(_tween):
		_tween.kill()
	_tween = create_tween()
	if Comic.reduced_motion():
		# tokens.json reduced_motion.forbid: position — pas de montée, fondu
		# seul, même budget total.
		_tween.tween_interval(DURATION - FADE_LAST)
		_tween.tween_property(self, "modulate:a", 0.0, FADE_LAST)
	else:
		_base_y = global_position.y
		_tween.tween_method(_tick, 0.0, DURATION, DURATION)
	_tween.tween_callback(queue_free)

## `elapsed` = valeur du tween (0 -> DURATION sur DURATION secondes, donc
## littéralement le temps écoulé) : pilote à la fois la montée et le fondu à
## partir des mêmes jetons (HitFeedback.damage_number_alpha).
func _tick(elapsed: float) -> void:
	global_position.y = _base_y + _RISE_WORLD * clampf(elapsed / DURATION, 0.0, 1.0)
	modulate.a = HitFeedback.damage_number_alpha(elapsed, DURATION, FADE_LAST)
