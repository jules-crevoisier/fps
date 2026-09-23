## HudFormat.gd
## Fonctions PURES (aucun état, aucun nœud) utilisées par le HUD : formatage de
## texte, maths de mise en page, contraste de tokens. Isolées ici pour rester
## testables sans scène (voir tests/ui/test_hud_format.gd).
class_name HudFormat
extends RefCounted

## Munitions : « 25 » (chargeur) — la réserve est un label séparé (« / 90 »).
static func format_ammo(current: int) -> String:
	return "%d" % maxi(0, current)

static func format_reserve(reserve: int) -> String:
	return "/ %d" % maxi(0, reserve)

## Minuteur mm:ss, jamais négatif.
static func format_timer(seconds: float) -> String:
	var s := maxi(0, int(ceil(seconds)))
	return "%d:%02d" % [s / 60, s % 60]

## Crédits (économie SnD) : « 3 900 ¤ » — espace insécable tous les 3 chiffres.
static func format_credits(credits: int) -> String:
	var n := maxi(0, credits)
	var digits := str(n)
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i != 0:
			out = " " + out
	return "%s ¤" % out

## Score de ligne « ÉQ.1  <a>  —  <b>  ÉQ.2 ».
static func format_score_line(team0: int, team1: int) -> String:
	return "ÉQ.1   %d   —   %d   ÉQ.2" % [team0, team1]

## Zone centrale 40 % x 40 % du HUD (design.md §8 : crosshair/hitmarkers/scope
## uniquement, rien d'autre ne doit s'y dessiner). Retourne le rect en pixels
## de la taille de viewport donnée.
static func center_zone_rect(viewport_size: Vector2) -> Rect2:
	var w := viewport_size.x * 0.4
	var h := viewport_size.y * 0.4
	return Rect2((viewport_size - Vector2(w, h)) * 0.5, Vector2(w, h))

## true si `rect` chevauche la zone centrale (sert à vérifier qu'un élément
## HUD ne s'y dessine jamais, ex. une onomatopée).
static func overlaps_center_zone(rect: Rect2, viewport_size: Vector2) -> bool:
	return rect.intersects(center_zone_rect(viewport_size))

## Luminance relative WCAG (sRGB) d'une couleur.
static func relative_luminance(c: Color) -> float:
	var chans := [c.r, c.g, c.b]
	var lin := []
	for v in chans:
		lin.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]

## Ratio de contraste WCAG entre deux couleurs (1..21). Sert à vérifier les
## tokens de design.md (ex. ink/paper ~14.6:1).
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := relative_luminance(a) + 0.05
	var lb := relative_luminance(b) + 0.05
	return maxf(la, lb) / minf(la, lb)
