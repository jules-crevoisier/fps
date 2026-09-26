## HudFormat.gd
## Fonctions PURES (aucun état, aucun nœud) de géométrie/contraste du HUD —
## isolées ici pour rester testables sans scène (voir tests/ui/test_hud_format.gd).
## Prototype à un seul weapon/HUD minimal (2026-09-26) : les formatteurs de
## munitions/réserve/minuteur/crédits/score, propres aux panneaux AmmoPanel/
## RoundPanel/ScorePanel (supprimés), sont partis avec eux — ne restent que la
## géométrie de zone centrale (Crosshair/HitMarker, CHK-35) et le contraste
## WCAG (palette des agents, docs/style/tokens.json).
class_name HudFormat
extends RefCounted

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
