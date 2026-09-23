## TrainingLayout.gd
## Données PURES (aucun nœud, aucun moteur nécessaire) du terrain
## d'entraînement (.orchestrator/contract-r4a.md, R4-TRAIN) : géométrie au
## format `Kit.build_piece()` (mêmes dictionnaires que `Layouts.gd`) + les
## marqueurs (checkpoints du contre-la-montre, mannequins, mannequins
## mobiles, portique de départ) consommés par
## `scripts/training/TrainingBuilder.gd`.
##
## Disposition (hall central en (0,*,0), joueur tourné vers -Z) :
##   - PARCOURS (nord, -Z) : sprint -> glissade en pente -> annulation/
##     slide-jump -> vide "air-strafe" (7 m) -> vide "dolphin dive" (8 m) ->
##     tour + chute avec roulade d'atterrissage. Double comme circuit du
##     contre-la-montre (CP0 = portique de départ ... CP4 = arrivée).
##   - STAND DE TIR (ouest, -X) : ligne de tir, mannequins statiques à
##     5/15/30/50 m + 2 mobiles, pare-balles.
##   - CAPACITÉS (est, +X) : petite arène avec mannequins pour tester les
##     capacités de chaque agent.
class_name TrainingLayout
extends RefCounted

## Palette neutre "encre et papier" (design.md §3 : chroma décor <= 0.05,
## AUCUNE des six teintes de map — ce n'est le territoire d'aucune d'elles).
## `accent` reste réservé aux éléments INTERACTIFS (checkpoints, bouton de
## reset) — bleu allié (design.md §5, seul accent verrouillé de l'UI).
static func palette() -> Dictionary:
	return {
		"floor": Color("c7bfa8"),
		"wall": Color("5c5548"),
		"platform": Color("8a8172"),
		"cover": Color("9c8f78"),
		"accent": Color("2f6fe4"),
	}

## Vide (à vol d'oiseau, XZ) du vide "dolphin dive" — doit rester en phase
## avec `StepRules.DIVE_GAP_MIN` (marge en moins, mesuré depuis l'entrée de
## l'état Dive, pas exactement le bord du vide).
const DIVE_GAP_Z_NEAR := -82.0
const DIVE_GAP_Z_FAR := -90.0  ## 8 m tout rond (contract : "an 8 m gap").

## Hauteur de chute tour -> aire d'atterrissage (m) — dans la fenêtre
## [fall_min_height=4, fall_max_height=14] de MovementConfig : assez haut
## pour stun si raté, roulade si le timing (V) est bon.
const TOWER_TOP_Y := 5.0
const TOWER_LANDING_Y := -3.0

static func pieces() -> Array:
	var p: Array = []
	var pal := palette()

	# ---- Dalle de base : hall + parcours + stand de tir + capacités ----
	p.append({"type": "box", "name": "BasePlate", "pos": Vector3(-5, -0.5, -30), "size": Vector3(180, 1, 220), "color_key": "floor"})

	# ---- Hall central (repères visuels, pas de collision dédiée : la dalle suffit) ----
	p.append({"type": "box", "name": "HubRing", "pos": Vector3(0, 0.05, 0), "size": Vector3(14, 0.1, 14), "color_key": "platform", "visual_only": true})

	# Bandes de sol teintées (accent) pointant vers chaque zone depuis le
	# hall — repère de direction fiable (voir TrainingBuilder.gd : un texte
	# `Label3D` ici ne s'affichait jamais, remplacé par ce marquage au sol).
	p.append({"type": "box", "name": "PathToCourse", "pos": Vector3(0, 0.06, -3), "size": Vector3(1.2, 0.1, 6), "color_key": "accent", "visual_only": true})
	p.append({"type": "box", "name": "PathToRange", "pos": Vector3(-4, 0.06, 0), "size": Vector3(6, 0.1, 1.2), "color_key": "accent", "visual_only": true})
	p.append({"type": "box", "name": "PathToAbilities", "pos": Vector3(4, 0.06, 0), "size": Vector3(6, 0.1, 1.2), "color_key": "accent", "visual_only": true})

	# ================================================================
	#  PARCOURS (nord, -Z) — double comme circuit du contre-la-montre.
	# ================================================================
	# Ligne de sprint (z: -6 -> -26), sur la dalle de base (y=0) — aucune
	# pièce dédiée nécessaire, juste des garde-fous latéraux.
	p.append({"type": "invisible_wall", "name": "CourseGuardW1", "start": Vector3(-5, 0, -6), "end": Vector3(-5, 0, -60), "height": 6.0})
	p.append({"type": "invisible_wall", "name": "CourseGuardE1", "start": Vector3(5, 0, -6), "end": Vector3(5, 0, -60), "height": 6.0})

	# Pente de glissade (z: -26 -> -40), largeur 8 m, pente ~12° (glissable,
	# sous le plafond "walkable" 52° et dans la fourchette slide 11-27° des
	# vraies maps).
	p.append({"type": "ramp", "name": "SlideRamp", "start": Vector3(0, 0, -26), "end": Vector3(0, -3, -40), "width": 8.0, "color_key": "platform"})

	# Piste plate d'annulation / slide-jump (z: -40 -> -60), y haut = -3.
	p.append({"type": "box", "name": "SlideRunway", "pos": Vector3(0, -3.5, -50), "size": Vector3(10, 1, 20), "color_key": "floor"})

	# Filet de rattrapage sous les deux vides (air-strafe + dolphin dive) :
	# une chute ratée n'est jamais punitive, juste un aller-retour (VRAIE
	# collision, contrairement aux pièces `visual_only` — c'est un vrai sol
	# de secours, pas un décor). + une rampe douce côté est (dans le
	# couloir gardé, x in [-5,5]) pour remonter sans sortir de la piste.
	p.append({"type": "box", "name": "CatchNet", "pos": Vector3(0, -6.5, -83), "size": Vector3(10, 1, 42), "color_key": "wall"})
	p.append({"type": "ramp", "name": "CatchNetRampBack", "start": Vector3(3, -6, -64), "end": Vector3(3, -3, -98), "width": 3.0, "color_key": "platform"})

	# Plateforme A (avant le vide "air-strafe").
	p.append({"type": "box", "name": "PlatformA", "pos": Vector3(0, -3.5, -64), "size": Vector3(10, 1, 6), "color_key": "floor"})
	# Vide "air-strafe" : z -67 -> -74 (7 m).
	# Plateforme B (entre les deux vides).
	p.append({"type": "box", "name": "PlatformB", "pos": Vector3(0, -3.5, -78), "size": Vector3(10, 1, 8), "color_key": "floor"})
	# Vide "dolphin dive" : z DIVE_GAP_Z_NEAR -> DIVE_GAP_Z_FAR (8 m pile).
	# Plateforme C (atterrissage de la plongée, pied de la tour).
	p.append({"type": "box", "name": "PlatformC", "pos": Vector3(0, -3.5, -94), "size": Vector3(10, 1, 8), "color_key": "floor"})

	p.append({"type": "invisible_wall", "name": "CourseGuardW2", "start": Vector3(-5, -3, -64), "end": Vector3(-5, -3, -98), "height": 6.0})
	p.append({"type": "invisible_wall", "name": "CourseGuardE2", "start": Vector3(5, -3, -64), "end": Vector3(5, -3, -98), "height": 6.0})

	# Escalier vers le sommet de la tour (rampe unique + marches visuelles,
	# Kit._ramp_with_treads via `stairs`) : montée douce (~30°, walkable).
	p.append({"type": "stairs", "name": "TowerStairs", "start": Vector3(0, -3, -98), "end": Vector3(0, TOWER_TOP_Y, -112), "width": 4.0, "steps": 12, "color_key": "platform"})

	# Sommet de tour : plateforme + garde-corps sur les longs côtés, OUVERT
	# à l'entrée (escalier) et au bord de saut (face -Z, vers l'aire d'atterrissage).
	p.append({"type": "box", "name": "TowerTop", "pos": Vector3(0, TOWER_TOP_Y - 0.5, -116), "size": Vector3(6, 1, 8), "color_key": "platform"})
	p.append({"type": "fence", "name": "TowerRailW", "start": Vector3(-3, TOWER_TOP_Y, -112), "end": Vector3(-3, TOWER_TOP_Y, -120), "height": 1.0, "color_key": "wall"})
	p.append({"type": "fence", "name": "TowerRailE", "start": Vector3(3, TOWER_TOP_Y, -112), "end": Vector3(3, TOWER_TOP_Y, -120), "height": 1.0, "color_key": "wall"})

	# Aire d'atterrissage (chute tour -> ici = TOWER_TOP_Y - TOWER_LANDING_Y).
	p.append({"type": "box", "name": "LandingPad", "pos": Vector3(0, TOWER_LANDING_Y - 0.5, -126), "size": Vector3(10, 1, 10), "color_key": "floor"})
	p.append({"type": "invisible_wall", "name": "CourseGuardW3", "start": Vector3(-5, TOWER_LANDING_Y, -112), "end": Vector3(-5, TOWER_LANDING_Y, -131), "height": 6.0})
	p.append({"type": "invisible_wall", "name": "CourseGuardE3", "start": Vector3(5, TOWER_LANDING_Y, -112), "end": Vector3(5, TOWER_LANDING_Y, -131), "height": 6.0})
	p.append({"type": "invisible_wall", "name": "CourseGuardN", "start": Vector3(-5, TOWER_LANDING_Y, -131), "end": Vector3(5, TOWER_LANDING_Y, -131), "height": 6.0})

	# ================================================================
	#  STAND DE TIR (ouest, -X).
	# ================================================================
	p.append({"type": "invisible_wall", "name": "RangeGuardN", "start": Vector3(-10, 0, -8), "end": Vector3(-65, 0, -8), "height": 6.0})
	p.append({"type": "invisible_wall", "name": "RangeGuardS", "start": Vector3(-10, 0, 8), "end": Vector3(-65, 0, 8), "height": 6.0})
	p.append({"type": "box", "name": "RangeBackstop", "pos": Vector3(-66, 3, 0), "size": Vector3(2, 6, 18), "color_key": "wall"})
	p.append({"type": "box", "name": "RangeFiringLine", "pos": Vector3(-10, 0.05, 0), "size": Vector3(1.2, 0.1, 6), "color_key": "accent", "visual_only": true})

	# Râtelier d'armes (décor — l'achat réel se fait via le menu d'achat
	# gratuit du training, déjà câblé : contract-r4a.md, intro R4-TRAIN
	# "free buy").
	p.append({"type": "box", "name": "RackPost1", "pos": Vector3(-9, 1, 4.5), "size": Vector3(0.2, 2, 0.2), "color_key": "wall"})
	p.append({"type": "box", "name": "RackPost2", "pos": Vector3(-11, 1, 4.5), "size": Vector3(0.2, 2, 0.2), "color_key": "wall"})
	p.append({"type": "box", "name": "RackShelf1", "pos": Vector3(-10, 1.6, 4.5), "size": Vector3(2.4, 0.1, 0.5), "color_key": "cover"})
	p.append({"type": "box", "name": "RackShelf2", "pos": Vector3(-10, 0.9, 4.5), "size": Vector3(2.4, 0.1, 0.5), "color_key": "cover"})

	# Bouton de réinitialisation (plaque au sol, visuel — le déclenchement
	# est un Area3D construit par ShootingRange.gd, pas ici).
	p.append({"type": "box", "name": "ResetPlate", "pos": Vector3(-10, 0.06, -4.5), "size": Vector3(1.6, 0.12, 1.6), "color_key": "accent", "visual_only": true})

	# ================================================================
	#  CAPACITÉS (est, +X).
	# ================================================================
	p.append({"type": "invisible_wall", "name": "AbilityGuardN", "start": Vector3(10, 0, -10), "end": Vector3(35, 0, -10), "height": 6.0})
	p.append({"type": "invisible_wall", "name": "AbilityGuardS", "start": Vector3(10, 0, 10), "end": Vector3(35, 0, 10), "height": 6.0})
	p.append({"type": "box", "name": "AbilityBackWall", "pos": Vector3(36, 2.5, 0), "size": Vector3(1, 5, 20), "color_key": "wall"})
	p.append({"type": "box", "name": "AbilityCover1", "pos": Vector3(24, 0.9, -5), "size": Vector3(1.6, 1.8, 1.6), "color_key": "cover"})
	p.append({"type": "box", "name": "AbilityCover2", "pos": Vector3(28, 0.9, 5), "size": Vector3(1.6, 1.8, 1.6), "color_key": "cover"})

	return p

## ---- Marqueurs (consommés par TrainingBuilder.gd, pas par Kit) ----

static func player_spawn() -> Vector3:
	return Vector3(0, 1, 10)

## Portique de départ (CP0) -> arrivée (CP4), dans l'ordre. Chaque entrée :
## {name, pos, radius}. Un `body_entered` dans l'ordre fait avancer
## `TimeTrialRules.advance_checkpoint`.
static func checkpoints() -> Array:
	return [
		{"name": "CP0", "pos": Vector3(0, 1, -6)},
		{"name": "CP1", "pos": Vector3(0, -2, -60)},
		{"name": "CP2", "pos": Vector3(0, -2, -82)},
		{"name": "CP3", "pos": Vector3(0, -2, -96)},
		{"name": "CP4", "pos": Vector3(0, TOWER_LANDING_Y + 1, -128)},
	]

## Mannequins statiques du stand de tir : distance annoncée depuis la ligne
## de tir (x=-10), pas depuis l'origine de la scène.
static func static_dummies() -> Array:
	return [
		{"name": "Dummy5m", "pos": Vector3(-15, 0, 0), "distance_m": 5},
		{"name": "Dummy15m", "pos": Vector3(-25, 0, -2), "distance_m": 15},
		{"name": "Dummy30m", "pos": Vector3(-40, 0, 3), "distance_m": 30},
		{"name": "Dummy50m", "pos": Vector3(-60, 0, -3), "distance_m": 50},
	]

## Mannequins mobiles : patrouille latérale (axe Z) autour de `pos`.
static func moving_dummies() -> Array:
	return [
		{"name": "MovingDummy1", "pos": Vector3(-20, 0, -6), "axis": Vector3(0, 0, 1), "distance": 3.0, "speed": 1.4},
		{"name": "MovingDummy2", "pos": Vector3(-35, 0, 6), "axis": Vector3(0, 0, 1), "distance": 3.0, "speed": 1.8},
	]

## Zones rectangulaires (XZ, min/max) — bien plus fidèles qu'un cercle pour
## un parcours tout en longueur : utilisées pour n'afficher le panneau
## d'une zone QUE sur place (jamais les quatre à l'écran en même temps, donc
## jamais de conflit avec les coins déjà pris par GameHUD — vie bas-gauche,
## munitions bas-droite, barre de capacités bas, voir design.md §8) et,
## pour le stand de tir, pour ne compter dans les stats que les touches qui
## y tombent réellement (RangeStats, position du `hit_confirmed`).
static func point_in_zone(p: Vector2, zone: Dictionary) -> bool:
	var mn: Vector2 = zone["min"]
	var mx: Vector2 = zone["max"]
	return p.x >= mn.x and p.x <= mx.x and p.y >= mn.y and p.y <= mx.y

static func range_zone() -> Dictionary:
	return {"min": Vector2(-68, -10), "max": Vector2(-7, 10)}

static func range_reset_zone() -> Dictionary:
	return {"pos": Vector3(-10, 0.5, -4.5), "radius": 1.2}

## Mannequins de la corniche "Capacités".
static func ability_dummies() -> Array:
	return [
		{"name": "AbilityDummy1", "pos": Vector3(20, 0, -4)},
		{"name": "AbilityDummy2", "pos": Vector3(20, 0, 4)},
		{"name": "AbilityDummy3", "pos": Vector3(28, 0, 0)},
	]

static func ability_zone() -> Dictionary:
	return {"min": Vector2(7, -12), "max": Vector2(38, 12)}

## Zone d'affichage des indications du parcours de mouvement + contre-la-montre.
## Collée aux murs invisibles réels du couloir (x = ±5, `CourseGuardW*/E*`)
## avec juste assez de marge pour ne PAS chevaucher `range_zone`/`ability_zone`
## (bord le plus proche à x=∓7 — vérifié en isolant le chevauchement : un
## joueur au bord de la ligne de tir (x=-9, la marge initiale) déclenchait
## À LA FOIS ce panneau ET celui du stand de tir).
static func course_zone() -> Dictionary:
	return {"min": Vector2(-6, -134), "max": Vector2(6, 3)}
