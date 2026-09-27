## DamageNumber3D.gd
## Chiffre de dégâts flottant en 3D, façon Borderlands/Apex (contrat lead
## 2026-09-27, HUD en jeu, point 8, RESTYLE de la direction « Planche ») :
## Bangers (`UiTokens.FONT_DISPLAY`) — remplace Barlow Condensed ExtraBold,
## réservé aux libellés — remplissage JAUNE signal (`UiTokens.YELLOW`), ROUGE
## (`UiTokens.RED`) sur headshot ×1,25, contour + ombre d'encre ÉPAIS
## (`UiTokens.INK`, `STROKE_PX`), léger tremblé de rotation ±8° tiré à
## l'apparition (jamais animé). Monte de `RISE_PX` sur `DURATION`, fondu
## SEULEMENT sur les `FADE_LAST` dernières secondes
## (`HitFeedback.damage_number_alpha`, pure et testable — INCHANGÉE, ce
## restyle ne touche qu'à l'apparence). L'empilement
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
## Contour d'encre ÉPAIS (contrat point 8 : "thick ink outline") — plus large
## que le contour standard des libellés HUD (`UiTokens.STROKE` = 4).
const STROKE_PX := 6
const RISE_PX := 40.0
const DURATION := 0.6
const FADE_LAST := 0.2
const HEADSHOT_SCALE := 1.25
## Tremblé de rotation aléatoire (contrat point 8 : "±8° random tilt"),
## tiré UNE FOIS à l'apparition (jamais animé — juste un désordre BD, pas un
## mouvement continu qui violerait `reduced_motion`).
const TILT_MAX_DEG := 8.0
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
	n.font = UiTokens.FONT_DISPLAY
	n.font_size = FONT_SIZE
	n.pixel_size = PIXEL_SIZE
	n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.no_depth_test = true
	n.outline_size = STROKE_PX
	n.outline_modulate = UiTokens.INK
	parent.add_child(n)
	n.global_position = pos + Vector3(randf_range(-0.15, 0.15), 0.25, 0.0)
	if not Comic.reduced_motion():
		n.rotation.z = deg_to_rad(randf_range(-TILT_MAX_DEG, TILT_MAX_DEG))
	n.apply(total_dmg, headshot, stack_count)
	return n

## Réaffiche pour un nouveau tir empilé (GF-07) : relance l'animation à partir
## de la position/alpha ACTUELLES (jamais reposée à son point de départ
## d'origine) — met à jour texte/couleur/échelle, jamais un second nœud posé
## par-dessus (Borderlands/Apex). Appelée aussi par `spawn()` pour le tout
## premier affichage (`stack_count` = 1).
func apply(total_dmg: float, headshot: bool, stack_count: int) -> void:
	text = str(int(round(total_dmg)))
	modulate = UiTokens.RED if headshot else UiTokens.YELLOW
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
