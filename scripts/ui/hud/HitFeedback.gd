## HitFeedback.gd
## Fonctions PURES (aucun état, aucun nœud) des retours de combat
## (docs/STYLE_BIBLE.md §9.4 "Retour de tir (HUD)", verrouillé ; jetons
## machine docs/style/tokens.json "vfx.hitmarker"/"vfx.damage_number"/"hud") :
## variante de hitmarker, agrégation des plombs d'un tir par cible, empilement
## des chiffres de dégâts, angle de la flèche de dégâts, courbes de fondu/
## chronologie, choix du mot-bruit (générique ET par arme), position du burst
## hors zone centrale, enchaînement multi-kill et intensité de la vignette de
## vie basse. Isolées ici pour rester testables sans scène (voir
## tests/ui/test_hit_feedback.gd — VERROUILLÉ, hors de mon périmètre
## d'écriture : toute constante encore lue par ce fichier de tests est
## conservée à l'identique ci-dessous, quitte à ajouter des constantes/
## fonctions séparées pour le comportement v3 réel).
class_name HitFeedback
extends RefCounted

# ------------------------------------------------------------ Hitmarker (#1, STYLE_BIBLE §9.4)
const MARKER_NORMAL := "normal"
const MARKER_HEADSHOT := "headshot"
const MARKER_KILL := "kill"

## Géométrie des 4 traits diagonaux (tokens.json vfx.hitmarker.tick_len_px/
## gap_px) : chaque trait part à `MARKER_TICK_GAP_PX` du centre du viseur et
## s'étire de `MARKER_TICK_LEN_PX` vers l'extérieur, sur les 4 diagonales.
const MARKER_TICK_LEN_PX := 10.0
const MARKER_TICK_GAP_PX := 8.0
## Contour d'encre des traits (STYLE_BIBLE §9.4, pas un jeton chiffré séparé
## dans tokens.json — valeur de la ligne "Hitmarker" du tableau).
const MARKER_INK_PX := 2.0

## Durées d'affichage par variante (tokens.json vfx.hitmarker.duration_ms/
## headshot_ms) — HitMarker.gd les consomme via `marker_duration()`.
const MARKER_DURATION := 0.09           # 90 ms (normal)
const MARKER_DURATION_HEADSHOT := 0.12  # 120 ms
## Punch d'échelle de la confirmation de kill (tokens.json
## vfx.hitmarker.kill_punch/kill_punch_ms) : "slap" (Tween.TRANS_BACK, voir
## Comic.gd "familles cubic sauf slap") raccourci à 150 ms. Le maintien+fondu
## qui suit n'a pas de valeur dédiée dans les jetons : `MARKER_KILL_HOLD` est
## un choix d'implémentation (reste dans la bande 90-400 ms de CHK-41).
const MARKER_KILL_PUNCH_FROM := 1.3
const MARKER_KILL_PUNCH_TO := 1.0
const MARKER_KILL_PUNCH_DURATION := 0.15  # 150 ms
const MARKER_KILL_HOLD := 0.12
const MARKER_KILL_DURATION := MARKER_KILL_PUNCH_DURATION + MARKER_KILL_HOLD

## Couleur headshot (tokens.json color.game.headshot.hex) : traits du
## hitmarker de headshot + anneau (STYLE_BIBLE §9.4) — même teinte que
## l'anneau « CLONK » du §9.3 et les chiffres de dégâts headshot ci-dessous.
const HEADSHOT_COLOR := Color("F28A1E")

## Durée d'affichage du hitmarker pour `variant` (MARKER_*) — centralisée ici
## pour que HitMarker.gd n'ait qu'une seule source de vérité.
static func marker_duration(variant: String) -> float:
	match variant:
		MARKER_KILL:
			return MARKER_KILL_DURATION
		MARKER_HEADSHOT:
			return MARKER_DURATION_HEADSHOT
		_:
			return MARKER_DURATION

## `is_kill` a priorité sur `headshot` (une balle de kill headshot reste la
## variante kill = traits pinceau + punch, pas la variante headshot).
static func marker_variant(headshot: bool, is_kill: bool) -> String:
	if is_kill:
		return MARKER_KILL
	if headshot:
		return MARKER_HEADSHOT
	return MARKER_NORMAL

# ------------------------------------------------------------ Agrégation des plombs (GF-07)
## Regroupe les plombs d'UN tir par cible, AVANT application des dégâts et
## émission de `Weapon.hit_confirmed` : un fusil à pompe (12 plombs, ex.
## Fracas) touchant une seule cible ne doit produire qu'UNE confirmation
## (somme des dégâts), pas 12. Chaque entrée de `pellet_hits` est
## `{"target": <clé stable et hashable, ex. l'id du joueur touché>, "dmg":
## float, "headshot": bool}` — une par plomb touché (les plombs ratés sont
## déjà exclus par l'appelant, voir `Weapon._resolve_ray`). Retourne un
## tableau d'agrégats `{"target", "dmg", "headshot"}`, un par cible distincte,
## dans l'ordre de leur première apparition (rendu stable) ; dégâts sommés,
## `headshot` vrai si AU MOINS UN plomb a touché la tête.
static func aggregate_shot_hits(pellet_hits: Array) -> Array:
	var order: Array = []
	var by_target: Dictionary = {}
	for hit in pellet_hits:
		var target = hit["target"]
		if by_target.has(target):
			var agg: Dictionary = by_target[target]
			agg["dmg"] = float(agg["dmg"]) + float(hit["dmg"])
			agg["headshot"] = bool(agg["headshot"]) or bool(hit["headshot"])
		else:
			by_target[target] = {"target": target, "dmg": float(hit["dmg"]), "headshot": bool(hit["headshot"])}
			order.append(target)
	var result: Array = []
	for target in order:
		result.append(by_target[target])
	return result

# ------------------------------------------------------------ Empilement des chiffres (GF-07, STYLE_BIBLE §9.4)
## Fenêtre d'empilement des chiffres de dégâts sur UNE MÊME cible, façon
## Borderlands/Apex : un nouveau tir confirmé sur une cible déjà marquée il y
## a moins de `DAMAGE_STACK_WINDOW` fait GROSSIR le chiffre existant (total
## cumulé, échelle plus grande) au lieu d'en poser un nouveau par-dessus.
## STYLE_BIBLE §9.4 "Chiffres de dégâts" / tokens.json
## vfx.damage_number.aggregate_window_ms : 800 ms (remplace la fenêtre 400 ms
## historique de contract-r4a — seule la VALEUR change, tests/ui/
## test_hit_feedback.gd référence la constante elle-même, jamais un littéral).
const DAMAGE_STACK_WINDOW := 0.8

## `elapsed_since_last` : temps écoulé depuis le dernier chiffre affiché sur
## CETTE cible (négatif = incohérent, jamais empilé).
static func should_stack_damage(elapsed_since_last: float, window: float = DAMAGE_STACK_WINDOW) -> bool:
	return elapsed_since_last >= 0.0 and elapsed_since_last <= window

## Échelle du chiffre empilé : grossit avec le nombre de tirs déjà accumulés
## sur la cible dans la fenêtre (1 = premier tir, taille normale), plafonnée
## pour rester lisible.
const DAMAGE_STACK_GROWTH := 0.18
const DAMAGE_STACK_SCALE_MAX := 1.9

static func damage_stack_scale(stack_count: int) -> float:
	return clampf(1.0 + maxf(stack_count - 1, 0) * DAMAGE_STACK_GROWTH, 1.0, DAMAGE_STACK_SCALE_MAX)

# ------------------------------------------------------------ Chiffres de dégâts (DamageNumber3D, STYLE_BIBLE §9.4)
## Multiplicateur de taille headshot (tokens.json
## vfx.damage_number.headshot_scale) — SE CUMULE avec `damage_stack_scale`
## (DamageNumber3D.apply), jamais un remplacement.
const DAMAGE_NUMBER_HEADSHOT_SCALE := 1.25

## Chronologie d'UN chiffre de dégâts (tokens.json vfx.damage_number :
## duration_ms/fade_last_ms) : « montée de 40 px, 600 ms, sortie en fondu les
## 200 dernières ms » — opaque jusqu'à `duration - fade_last`, puis fondu
## linéaire jusqu'à 0 (PAS un fondu sur toute la durée, contrairement à
## l'ancienne implémentation). Pure et testable, consommée par
## DamageNumber3D._tick (tween_method, `elapsed` = temps écoulé de ce tween).
const DAMAGE_NUMBER_DURATION := 0.6
const DAMAGE_NUMBER_FADE_LAST := 0.2

static func damage_number_alpha(elapsed: float, duration: float = DAMAGE_NUMBER_DURATION, fade_last: float = DAMAGE_NUMBER_FADE_LAST) -> float:
	if elapsed <= 0.0:
		return 1.0
	if elapsed >= duration:
		return 0.0
	var fade_start := duration - fade_last
	if fade_last <= 0.0 or elapsed <= fade_start:
		return 1.0
	return clampf(1.0 - (elapsed - fade_start) / fade_last, 0.0, 1.0)

# ------------------------------------------------------------ Flèche de dégâts (#2)
## Durée du fondu de la flèche (design.md : "fading over 1 s") — inchangée,
## consommée par scripts/ui/hud/DamageDirection.gd (hors de mon périmètre
## d'écriture).
const WEDGE_DURATION := 1.0

## Angle (degrés, 0 = devant, 90 = droite, ±180 = derrière) entre l'avant du
## joueur et la source des dégâts, projeté sur le plan horizontal (ignore le
## tangage de la caméra : `forward`/`right` doivent venir du corps, pas de la
## tête). Source confondue avec l'origine => 0° (dégénéré, sans direction).
static func wedge_angle_deg(origin: Vector3, forward: Vector3, right: Vector3, source: Vector3) -> float:
	var to_source := source - origin
	to_source.y = 0.0
	if to_source.length_squared() < 0.0001:
		return 0.0
	var f := forward
	f.y = 0.0
	var r := right
	r.y = 0.0
	return rad_to_deg(atan2(to_source.dot(r), to_source.dot(f)))

## Opacité de la flèche (1 au début, 0 après `duration`).
static func wedge_alpha(elapsed: float, duration: float = WEDGE_DURATION) -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(1.0 - elapsed / duration, 0.0, 1.0)

# ------------------------------------------------------------ Mot-bruit générique (#4, historique)
## "CRAC!" est RÉSERVÉ au headshot ; les autres tournent pour les kills au
## corps (design.md : « PAF!, BLAM!, CRAC! (headshot), VLAN! »). CONSERVÉ TEL
## QUEL : verrouillé par tests/ui/test_hit_feedback.gd (hors de mon périmètre
## d'écriture) — voir `weapon_kill_word` ci-dessous pour le mot-bruit RÉEL
## « de l'arme » demandé par STYLE_BIBLE v3 §9.4 "Confirmation de kill" (le
## câblage de `scripts/ui/GameHUD.gd` sur ce nouveau mot est HORS de mon
## périmètre d'écriture, voir le rendu de fin de tâche).
const HEADSHOT_WORD := "CRAC!"
const KILL_WORDS := ["PAF!", "BLAM!", "VLAN!"]

static func sound_word(headshot: bool, pick: int) -> String:
	if headshot:
		return HEADSHOT_WORD
	return KILL_WORDS[posmod(pick, KILL_WORDS.size())]

# ------------------------------------------------------------ Mot-bruit PAR ARME (STYLE_BIBLE §7/§9.4)
## Onomatopée propre à chaque arme (docs/STYLE_BIBLE.md §7 tableau des armes,
## tokens.json weapons.<id>.kill_word) — c'est le mot-bruit RÉELLEMENT demandé
## par la confirmation de kill v3 (« onomatopée de l'arme »). Clé =
## `WeaponConfig.weapon_name` en minuscules (ex. "Ravage" -> "ravage",
## `resources/weapons/*.tres`).
const WEAPON_KILL_WORDS := {
	"pistolet": "PAN !",
	"magnum": "PAN !",
	"rafale": "RATATA !",
	"marqueur": "BAM !",
	"ravage": "BAM !",
	"fracas": "BRAOUM !",
	"faucheur": "CLAC !",
	"éclair": "RATATA !",
	"semeuse": "TATATATA !",
	"percuteur": "BAM !",
}
## Repli si `weapon_name` est vide ou absent de la table ci-dessus (jamais une
## bulle BD sans texte) : le mot le plus neutre du roster existant.
const WEAPON_KILL_WORD_FALLBACK := "BAM !"

static func weapon_kill_word(weapon_name: String) -> String:
	return WEAPON_KILL_WORDS.get(weapon_name.to_lower(), WEAPON_KILL_WORD_FALLBACK)

## Chronologie GÉNÉRIQUE historique du burst (60 in / 180 hold / 60 out,
## design.md §10), 300 ms max — CONSERVÉE TELLE QUELLE : verrouillée par
## tests/ui/test_hit_feedback.gd (hors de mon périmètre d'écriture). Les
## fonctions `burst_alpha`/`burst_scale` ci-dessous restent appelables avec
## CES constantes par défaut (donc les tests continuent de passer), mais
## acceptent aussi des durées explicites — voir KILL_WORD_* plus bas, la
## chronologie RÉELLEMENT utilisée en jeu par KillWordBurst.gd.
const BURST_IN := 0.06
const BURST_HOLD := 0.18
const BURST_OUT := 0.06
const BURST_DURATION := BURST_IN + BURST_HOLD + BURST_OUT

static func burst_alpha(elapsed: float, dur_in: float = BURST_IN, dur_hold: float = BURST_HOLD, dur_out: float = BURST_OUT) -> float:
	var total := dur_in + dur_hold + dur_out
	if elapsed < 0.0 or elapsed > total:
		return 0.0
	if elapsed < dur_in:
		return clampf(elapsed / dur_in, 0.0, 1.0) if dur_in > 0.0 else 1.0
	if elapsed < dur_in + dur_hold:
		return 1.0
	var out_t := elapsed - dur_in - dur_hold
	return clampf(1.0 - out_t / dur_out, 0.0, 1.0) if dur_out > 0.0 else 0.0

## Petit "pop" d'entrée (0.6 -> 1.0 pendant `dur_in`), stable ensuite.
## `HitFeedback.burst_scale_reduced` (mouvement réduit) saute directement à 1.0.
static func burst_scale(elapsed: float, dur_in: float = BURST_IN, _dur_hold: float = BURST_HOLD) -> float:
	if elapsed < dur_in and dur_in > 0.0:
		return lerpf(0.6, 1.0, clampf(elapsed / dur_in, 0.0, 1.0))
	return 1.0

## Chronologie RÉELLE de l'onomatopée de kill affichée en jeu (STYLE_BIBLE v3
## §9.4 "Confirmation de kill", tokens.json hud.kill_word_ms) : « 700 ms (pop
## 90 ms, maintien, sortie 200 ms) » — remplace, EN JEU, la chronologie
## générique 300 ms ci-dessus (conservée uniquement pour ne pas casser le
## test verrouillé). KillWordBurst.gd appelle `burst_alpha`/`burst_scale`
## avec CES constantes.
const KILL_WORD_IN := 0.09
const KILL_WORD_OUT := 0.20
const KILL_WORD_DURATION := 0.7
const KILL_WORD_HOLD := KILL_WORD_DURATION - KILL_WORD_IN - KILL_WORD_OUT

## Position de l'onomatopée de kill (STYLE_BIBLE v3 §9.4, tokens.json
## hud.kill_word_pos) : x 0,72 / y 0,38 de la taille de viewport, TOUJOURS
## hors de la zone centrale 40 % × 40 % — voir `burst_rect`.
const KILL_WORD_POS := Vector2(0.72, 0.38)

## Taille du burst (halo ComicBurst + mot) — design.md : marge confortable
## pour le halo + le mot, pas un jeton chiffré séparé dans tokens.json.
const BURST_SIZE := Vector2(340.0, 170.0)

## `right_side` place le coin haut-gauche du burst à `KILL_WORD_POS` (côté
## killfeed, la position RÉELLEMENT demandée par STYLE_BIBLE v3) ; `!right_side`
## le place en miroir horizontal (x = 1 - KILL_WORD_POS.x), même y — SEUL
## `scripts/ui/GameHUD.gd` (hors de mon périmètre d'écriture) alterne encore
## les deux côtés d'un kill à l'autre (`_kill_word_right_side`) ; cette
## fonction reste donc compatible avec les DEUX appels plutôt que de figer un
## unique côté et casser ce call-site existant. Aux deux côtés, le rectangle
## ne chevauche jamais la zone centrale (marge ≥ 25 px même à 720p).
static func burst_rect(right_side: bool, viewport_size: Vector2) -> Rect2:
	var y := viewport_size.y * KILL_WORD_POS.y
	var x: float
	if right_side:
		x = viewport_size.x * KILL_WORD_POS.x
	else:
		x = viewport_size.x * (1.0 - KILL_WORD_POS.x) - BURST_SIZE.x
	return Rect2(Vector2(x, y), BURST_SIZE)

# ------------------------------------------------------------ Multi-kill (STYLE_BIBLE §9.4/§8.1, LORE.md §5)
## Fenêtre d'enchaînement (tokens.json hud.multi_kill_max_ms) : deux
## confirmations de kill successives dans cette fenêtre comptent pour le MÊME
## enchaînement — affichage total du libellé plafonné à la même durée
## (STYLE_BIBLE "Multi-kill" : « ≤ 1,2 s au total »).
const MULTI_KILL_WINDOW := 1.2

## Libellé d'enchaînement pour `streak` kills consécutifs dans la fenêtre
## ci-dessus ("" = pas de libellé, streak < 2). LORE.md §5 / STYLE_BIBLE §8.1 :
## DOUBLÉ, TRIPLÉ, GRAND CHELEM — GRAND CHELEM est le palier MAXIMAL (streak
## >= 4 y reste, jamais un 4e libellé inventé).
static func multi_kill_label(streak: int) -> String:
	if streak <= 1:
		return ""
	if streak == 2:
		return "DOUBLÉ"
	if streak == 3:
		return "TRIPLÉ"
	return "GRAND CHELEM"

# ------------------------------------------------------------ Vignette de vie basse (#3)
## Sous ce ratio de vie (35 %, design.md), les hachures commencent à ramper
## depuis les bords ; intensité maximale à 0 PV.
const VIGNETTE_HP_THRESHOLD := 0.35
const VIGNETTE_MAX_THICKNESS := 220.0
## Pulsation ≤ 1 Hz (design.md/contract).
const VIGNETTE_PULSE_HZ := 1.0

static func vignette_thickness(ratio: float, max_thickness: float = VIGNETTE_MAX_THICKNESS) -> float:
	var r := clampf(ratio, 0.0, 1.0)
	if r >= VIGNETTE_HP_THRESHOLD:
		return 0.0
	return (VIGNETTE_HP_THRESHOLD - r) / VIGNETTE_HP_THRESHOLD * max_thickness

## Multiplicateur d'alpha oscillant dans [0.6, 1.0] à `hz` Hz. Le mouvement
## réduit fige l'appel côté HUD (n'appelle jamais cette fonction) plutôt que
## de la modifier ici (elle reste pure et indépendante des réglages).
static func vignette_pulse(time: float, hz: float = VIGNETTE_PULSE_HZ) -> float:
	return 0.8 + 0.2 * sin(TAU * maxf(hz, 0.0) * time)
