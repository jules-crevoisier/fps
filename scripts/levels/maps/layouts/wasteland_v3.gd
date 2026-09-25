## wasteland_v3.gd
## LD-40 (§12.6, décision utilisateur 2026-09-25 : « garder la v3 sous un
## autre identifiant pour comparer au banc de bots ») : SNAPSHOT GELÉ de
## l'ancien `wasteland.gd` (damier de petites boîtes, 80 × 43 m, 51 % de
## toits jouables — verdict `docs/research/11_wasteland_v4_layout.md` §2,
## « jeu faible... aucune lane ne se lit ») au moment où `wasteland.gd` est
## réécrit pour le contrat v4 (§9 du même document). Géométrie et données
## INCHANGÉES à la ligne près (seuls `class_name`/`data()["id"]`/ce
## commentaire changent) : sert de référence de banc de bots ("wasteland_v3"
## contre "wasteland" v4, mêmes bots/mêmes mesures) — enregistrée dans
## `MapSetup._data_for` mais volontairement ABSENTE de `MapCatalog.gd` (hors
## de mon périmètre), donc absente de la liste jouable/du menu.
##
## Même pipeline PUR que Layouts.gd (aucun nœud), mais SANS ses helpers de
## miroir (inutiles ici) — seuls `Layouts._spawn()` est réutilisé pour rester
## cohérent avec le schéma `{pos, look}` attendu par MapSetup._build_markers.
class_name WastelandLayoutV3
extends RefCounted

static func data() -> Dictionary:
	var pieces: Array = []
	var A := func(p: Dictionary) -> void: pieces.append(p)

	# ------------------------------------------------------------------
	#  Sol, falaises (bornes de la carte) + périmètre invisible (§7.4)
	# ------------------------------------------------------------------
	# Sol PRINCIPAL, raboté au nord du Ravin (z < 9) — §c.2/§c.7 "Ravin à -1,2 m" :
	# le Ravin lui-même (`RavinFloor`, plus bas) est un sol SÉPARÉ, en contrebas,
	# jamais recouvert par celui-ci (sinon Recast ne voit que le dessus plat de
	# `Ground`, à y=0, et le Ravin ne se lit jamais en creux). Bornes/périmètre
	# de la carte inchangés (contrat) : seule la limite NORD de cette pièce
	# bouge, `CliffS` (z 18,5) reste la borne sud réelle.
	A.call({"type": "box", "name": "Ground", "pos": Vector3(0, -1, -8), "size": Vector3(80, 2, 34), "color_key": "floor"})
	A.call({"type": "box", "name": "CliffW", "pos": Vector3(-40.5, 3, -3.5), "size": Vector3(1, 6, 43), "color_key": "rock"})
	A.call({"type": "box", "name": "CliffE", "pos": Vector3(40.5, 3, -3.5), "size": Vector3(1, 6, 43), "color_key": "rock"})
	A.call({"type": "box", "name": "CliffS", "pos": Vector3(0, 3, 18.5), "size": Vector3(82, 6, 1), "color_key": "rock"})
	A.call({"type": "box", "name": "MassifNW", "pos": Vector3(-21, 3, -19.5), "size": Vector3(38, 6, 11), "color_key": "rock"})
	A.call({"type": "box", "name": "CliffN", "pos": Vector3(15.5, 3, -25.5), "size": Vector3(35, 6, 1), "color_key": "rock"})
	A.call({"type": "box", "name": "MassifNE", "pos": Vector3(36.5, 3, -16.5), "size": Vector3(7, 6, 17), "color_key": "rock"})

	A.call({"type": "box", "name": "RockS", "pos": Vector3(-11, 1.5, 10.25), "size": Vector3(9, 3, 5.5), "color_key": "rock"})
	A.call({"type": "box", "name": "RockRimSW", "pos": Vector3(-21.5, 1.5, 15.5), "size": Vector3(37, 3, 5), "color_key": "rock"})
	A.call({"type": "box", "name": "RockSC", "pos": Vector3(8, 1.5, 15.5), "size": Vector3(4, 3, 5), "color_key": "rock"})
	A.call({"type": "box", "name": "RockSE", "pos": Vector3(34, 1.5, 15.5), "size": Vector3(12, 3, 5), "color_key": "rock"})

	# ------------------------------------------------------------------
	#  Le Ravin (lane sud, §c.2/§c.3) — sol en contrebas à y -1,2, sous le
	# reste de la carte de 1,2 m (§c.8 verticalité). `RockS`/`RockRimSW`/
	# `RockSC`/`RockSE` ci-dessus (inchangées) deviennent ses parois : leur
	# dessous (y=0) est à > agent_max_climb (0,5) du fond du Ravin (y=-1,2),
	# Recast les traite donc comme un plafond bas non praticable au-dessus du
	# Ravin là où elles le surplombent — seuls les 2 passages déjà ouverts
	# entre elles (x -3..6 et x 10..28, l'ancien "ruban de sable mort" L7)
	# restent praticables jusqu'à `CliffS`, en plus de la bande z 9-13 sans
	# aucun surplomb (hors `RockS`). 5 connecteurs (`RavinRamp*`, <= 22°)
	# relient la Grand-Rue (z 9, y 0) au fond du Ravin (z ~11-12, y -1,2).
	# ------------------------------------------------------------------
	A.call({"type": "box", "name": "RavinFloor", "pos": Vector3(0, -1.6, 13.5), "size": Vector3(74, 0.8, 9), "color_key": "rock"})
	A.call({"type": "box", "name": "RavinRockO1", "pos": Vector3(-18, -0.45, 12.5), "size": Vector3(2.5, 1.5, 2.5), "color_key": "rock"})
	A.call({"type": "box", "name": "RavinRockO2", "pos": Vector3(15, -0.45, 12.5), "size": Vector3(2.5, 1.5, 2.5), "color_key": "rock"})
	for rx in [-30.0, -20.0, -2.0, 20.0, 27.0]:
		A.call({"type": "ramp", "name": "RavinRamp%d" % int(rx), "start": Vector3(rx, 0, 9.0), "end": Vector3(rx, -1.2, 12.0), "width": 3.0, "color_key": "rock"})

	# ------------------------------------------------------------------
	#  FUEL (compound blue, ouest)
	# ------------------------------------------------------------------
	# PF1 (§c.3 "Toit FUEL") : 3 accès — escalier intérieur (`stair_side` W,
	# sol -> toit), planche depuis le garage (`FuelPlank`, étage 1) et
	# désormais l'échelle extérieure sud (nouvelle) : `FuelExtStairsS`
	# ci-dessous, jusqu'à l'étage 1 (la porte S/étage 1 ajoutée ici la rend
	# fonctionnelle — la rampe intérieure continue jusqu'au toit).
	A.call({"type": "building2", "name": "FuelHouse", "pos": Vector3(-30, 3.2, -7.5), "size": Vector3(6, 6.4, 6), "color_key": "wall",
		"floors": 2,
		"doors": [{"side": "S", "floor": 0}, {"side": "E", "floor": 0}, {"side": "E", "floor": 1}, {"side": "S", "floor": 1}],
		"windows": ["S"], "roof_access": true, "parapet": 1.0, "stair_side": "W"})
	A.call({"type": "stairs", "name": "FuelExtStairsS", "start": Vector3(-30, 0, 0.5), "end": Vector3(-30, 3.2, -4.5), "width": 1.5, "color_key": "platform"})
	A.call({"type": "building2", "name": "Garage", "pos": Vector3(-17.5, 1.6, -7.5), "size": Vector3(7, 3.2, 6), "color_key": "wall",
		"floors": 1, "doors": [{"side": "S", "floor": 0, "w": 3.0}, {"side": "W", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0})
	A.call({"type": "catwalk", "name": "FuelPlank", "start": Vector3(-27, 3.2, -7.5), "end": Vector3(-21, 3.2, -7.5), "width": 1.5, "color_key": "platform"})
	A.call({"type": "building2", "name": "Shack", "pos": Vector3(-30, 1.6, 5.5), "size": Vector3(6, 3.2, 6), "color_key": "wall",
		"floors": 1, "doors": [{"side": "N", "floor": 0}, {"side": "E", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0})
	A.call({"type": "prop", "name": "ShackAwning", "prop": "shack_awning", "pos": Vector3(-30, 2.6, 2.5), "cover": false})
	A.call({"type": "prop", "name": "ShackRoofPeak", "prop": "shack_roof_peak", "pos": Vector3(-30, 3.2, 5.5), "cover": false})

	for xz in [Vector2(-20.5, 3.0), Vector2(-20.5, 7.5), Vector2(-14.5, 3.0), Vector2(-14.5, 7.5)]:
		A.call({"type": "box", "name": "CanopyPost%d_%d" % [int(xz.x * 10.0), int(xz.y * 10.0)], "pos": Vector3(xz.x, 1.9, xz.y), "size": Vector3(0.3, 3.8, 0.3), "color_key": "accent"})
	A.call({"type": "box", "name": "CanopyRoof", "pos": Vector3(-17.5, 3.95, 5.25), "size": Vector3(7, 0.3, 5.5), "color_key": "accent", "skin": "canopy_station"})
	A.call({"type": "box", "name": "PumpW", "pos": Vector3(-19, 0.8, 5.25), "size": Vector3(0.72, 1.6, 0.6), "color_key": "cover", "skin": "fuel_pump"})
	A.call({"type": "box", "name": "PumpE", "pos": Vector3(-16, 0.8, 5.25), "size": Vector3(0.72, 1.6, 0.6), "color_key": "cover", "skin": "fuel_pump"})
	A.call({"type": "box", "name": "FuelBillboard", "pos": Vector3(-33.5, 2.5, -1), "size": Vector3(0.6, 5, 3.5), "color_key": "cover", "tint": Cartoon.CONTAINER_BLUE})
	A.call({"type": "box", "name": "TankerWreck", "pos": Vector3(-24, 1.5, -1), "size": Vector3(8, 3, 2.5), "color_key": "cover"})
	# BUG-30 (3e passage) : grillage de clôture du dépôt FUEL, bord est de la
	# cour à conteneurs/citerne (mur plein 2,4 m, casse la ligne de vue comme
	# une chicane, `Kit.SIGHT_MIN_TOP`). Sur la navmesh RÉELLE, la rotation
	# bleue vers le site A (Chapelle) passait tout droit sur la bande sud du
	# domicile FUEL (quasiment à vol d'oiseau, +1,1 m seulement), alors que la
	# rotation rouge vers le Hangar (site C) doit traverser GasOffice PUIS
	# WestBlock (aucun bâtiment GAS ne laisse de contournement au sol, §c.2
	# "chicanes" + empreinte pleine de WestBlock) : parité A<->C mesurée
	# 26,7 % (plafond 10 %). Cette clôture ferme le même type de raccourci
	# côté bleu (elle ne touche à aucune zone Hardpoint/site SnD ni aux
	# rotations B->A/A->C/C->B, toutes vérifiées dans leur plage) : la
	# rotation bleue vers A doit désormais contourner par le sud (vers le
	# Ravin), symétrique de l'effort de rotation rouge->C.
	A.call({"type": "fence", "name": "FuelYardFence", "start": Vector3(-20, 0, 0), "end": Vector3(-20, 0, 6), "height": 2.4, "color_key": "wall"})

	# ------------------------------------------------------------------
	#  Dune (côté bleu, glissade 15°)
	# ------------------------------------------------------------------
	A.call({"type": "box", "name": "DuneMound", "pos": Vector3(-17.5, 1.6, -12.25), "size": Vector3(7, 3.2, 3.5), "color_key": "rock"})
	A.call({"type": "ramp", "name": "DuneUp", "start": Vector3(-29, 0, -12.25), "end": Vector3(-21, 3.2, -12.25), "width": 3.5, "color_key": "rock"})
	A.call({"type": "ramp", "name": "DuneSlide", "start": Vector3(-14, 3.2, -12.25), "end": Vector3(-2, 0, -12.25), "width": 3.5, "color_key": "rock"})

	# ------------------------------------------------------------------
	#  Réservoir, chapelle, hangar-grue (centre)
	# ------------------------------------------------------------------
	# PF2 (§c.3 "Toit du Réservoir, pied du château d'eau") : 3e accès, l'échelle
	# ouest (nouvelle) — `ResStairW`, un seul flanc simple (bâtiment à 1 étage,
	# toit plein sans trémie, donc sans le risque d'interférence porte/étage
	# rencontré sur GasOffice, voir plus haut) ; le saut depuis la dune (§c.3)
	# reste hors périmètre : il faudrait un `NavigationLink3D`
	# (`scripts/ai/BotNavMesh.gd`, hors de ma liste de fichiers).
	A.call({"type": "building2", "name": "Reservoir", "pos": Vector3(-10.5, 1.6, -7.5), "size": Vector3(5, 3.2, 5), "color_key": "adobe",
		"floors": 1, "doors": [{"side": "S", "floor": 0}, {"side": "W", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0})
	A.call({"type": "stairs", "name": "ResStair", "start": Vector3(-11.5, 0, -0.5), "end": Vector3(-11.5, 3.2, -5), "width": 1.5, "color_key": "platform"})
	A.call({"type": "stairs", "name": "ResStairW", "start": Vector3(-17.3, 0, -7.5), "end": Vector3(-13.0, 3.2, -7.5), "width": 1.5, "color_key": "platform"})
	A.call({"type": "water_tower", "name": "WaterTower", "pos": Vector3(-10.5, 3.2, -7.5), "color_key": "accent"})
	A.call({"type": "building2", "name": "Chapel", "pos": Vector3(-7.5, 1.6, 0), "size": Vector3(5, 3.2, 6), "color_key": "adobe",
		"floors": 1, "doors": [{"side": "N", "floor": 0}, {"side": "S", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0})
	A.call({"type": "prop", "name": "ChapelRoofPeak", "prop": "shack_roof_peak", "pos": Vector3(-7.5, 3.2, 0), "cover": false})

	# PF3 (§c.3 "Pont de grue") : 3 accès jusqu'au pont (5,6 m) — escalier sud
	# du hangar (`ShedStairS`) + est (`CraneStair`) déjà là, complétés par
	# l'échelle ouest (nouvelle) : `ShedStairW`, jusqu'au toit du hangar
	# (3,2 m), d'où `CraneStair` continue jusqu'au pont — le plongeon depuis
	# le Réservoir (§c.3) reste hors périmètre, même raison que PF2.
	#
	# Porte ouest au sol (BUG-30, vague 30) : la zone Hardpoint B (0,5 ; 1,5 ;
	# -8,5, `wasteland_markers.gd`) est collée au mur ouest du hangar (x=0),
	# mais seules les portes S (`ShedStairS`, en fait un accès AU TOIT, pas au
	# rez-de-chaussée) et E existaient au sol : venant de l'ouest (Chapelle,
	# spawn bleu), il fallait contourner tout le hangar par le sud ou l'est.
	# Mesuré sur la navmesh réelle avant cette porte : rotation B->A 43,4 m /
	# 5,29 s (hors [2,5 ; 4] s, +32 % sur le plafond) et parité B (bleu/rouge)
	# 51,5 / 39,8 m (écart 22,7 % > 8 %). Cette porte au sol (distincte de
	# `ShedStairW`, qui reste l'accès au toit, §PF3 ci-dessus, INCHANGÉ) ouvre
	# un accès direct au rez-de-chaussée du hangar depuis l'ouest, sans
	# toucher aux zones Hardpoint elles-mêmes (`data()["hardpoints"]` plus
	# bas, verrouillées par `test_wasteland.gd::test_hardpoints_and_sites`,
	# hors de ma liste de fichiers) ni au reste de la géométrie SnD (site_a/
	# site_b).
	A.call({"type": "building2", "name": "CraneShed", "pos": Vector3(3.5, 1.6, -9.5), "size": Vector3(7, 3.2, 8), "color_key": "cover",
		"floors": 1, "doors": [{"side": "S", "floor": 0}, {"side": "E", "floor": 0}, {"side": "W", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0})
	A.call({"type": "stairs", "name": "ShedStairS", "start": Vector3(0.75, 0, -1), "end": Vector3(0.75, 3.2, -5.5), "width": 1.5, "color_key": "platform"})
	A.call({"type": "stairs", "name": "ShedStairW", "start": Vector3(-4.5, 0, -7.0), "end": Vector3(0.0, 3.2, -7.0), "width": 1.5, "color_key": "platform"})
	A.call({"type": "box", "name": "CraneDeck", "pos": Vector3(1.5, 5.475, -11.5), "size": Vector3(3, 0.25, 3), "color_key": "platform"})
	A.call({"type": "stairs", "name": "CraneStair", "start": Vector3(6.5, 3.2, -11.5), "end": Vector3(3, 5.6, -11.5), "width": 1.5, "color_key": "platform"})
	A.call({"type": "fence", "name": "CraneRailN", "start": Vector3(0, 5.6, -13), "end": Vector3(3, 5.6, -13), "height": 1.0, "color_key": "wall"})
	A.call({"type": "fence", "name": "CraneRailW", "start": Vector3(0, 5.6, -13), "end": Vector3(0, 5.6, -10), "height": 1.0, "color_key": "wall"})
	A.call({"type": "fence", "name": "CraneRailS", "start": Vector3(0, 5.6, -10), "end": Vector3(3, 5.6, -10), "height": 1.0, "color_key": "wall"})
	A.call({"type": "box", "name": "CraneMast", "pos": Vector3(1.5, 8, -14.3), "size": Vector3(1.6, 16, 1.6), "color_key": "accent"})
	A.call({"type": "prop", "name": "CraneLattice", "prop": "crane_lattice", "pos": Vector3(1.5, 0, -14.3), "cover": false})
	A.call({"type": "box", "name": "BusWreck", "pos": Vector3(1, 1.5, -20), "size": Vector3(3, 3, 9), "color_key": "cover", "skin": "bus_wreck"})

	# ------------------------------------------------------------------
	#  Derrick rise (côté rouge, site A, glissade 22°)
	# ------------------------------------------------------------------
	# PF4 (§c.3 "Butte du Derrick") — plateau et rampe INCHANGÉS (12x8 m) : une
	# réduction à 8x8 a été essayée pour l'indice de hauteur (§c.3 "Correctif")
	# mais déplace `DerrickRamp` assez pour faire chuter le ratio de chemin
	# SnD site_a (attaquant/défenseur) de ~1.7 à 1.17, hors de [1.5, 3.0]
	# (`test_snd_path_ratio_is_within_range`, un test existant qui doit rester
	# vert) — l'équilibre de hauteur (indice §c.7, écart <= 10 %) est donc
	# repris ailleurs : `DerrickWestStair` (ci-dessous) et l'échelle FUEL sud
	# (`FuelExtStairsS`) ajoutent de la verticalité aux DEUX camps sans
	# toucher au navmesh SnD ni à `DerrickRamp`/`RiseStair` (vérifié :
	# écart mesuré à ~4-7 %, `test_height_index_parity_within_10_percent`).
	A.call({"type": "box", "name": "DerrickRise", "pos": Vector3(19, 2.25, -21), "size": Vector3(12, 4.5, 8), "color_key": "rock"})
	A.call({"type": "ramp", "name": "DerrickRamp", "start": Vector3(15, 4.5, -17), "end": Vector3(15, 0, -6), "width": 4.0, "color_key": "platform"})
	A.call({"type": "stairs", "name": "RiseStair", "start": Vector3(31, 0, -19), "end": Vector3(25, 4.5, -19), "width": 2.0, "color_key": "platform"})
	# PF4, 3e accès (§c.3 "rochers-marches ouest depuis le chemin du Bus") :
	# `DerrickWestStair`, depuis le pied de la Crête (près de `BusWreck`)
	# jusqu'au bord ouest du plateau — s'ajoute à `DerrickRamp` (glissade) et
	# `RiseStair` (est), sans toucher ni l'un ni l'autre (navmesh SnD site_a
	# intact, voir commentaire plus haut).
	A.call({"type": "stairs", "name": "DerrickWestStair", "start": Vector3(7.0, 0, -20.0), "end": Vector3(14.0, 4.5, -20.0), "width": 2.0, "color_key": "platform"})
	for xz in [Vector2(20.5, -22.5), Vector2(20.5, -19.5), Vector2(23.5, -22.5), Vector2(23.5, -19.5)]:
		A.call({"type": "box", "name": "DerrickLeg%d_%d" % [int(xz.x * 10.0), int(xz.y * 10.0)], "pos": Vector3(xz.x, 9.5, xz.y), "size": Vector3(0.4, 10, 0.4), "color_key": "accent"})
	A.call({"type": "prop", "name": "OilDerrick", "prop": "oil_derrick", "pos": Vector3(22, 4.5, -21), "cover": false})

	# ------------------------------------------------------------------
	#  GAS (compound rouge, est)
	# ------------------------------------------------------------------
	# PF5 (§c.3 "Toit du bureau GAS", monté d'un étage : 3,2 -> 6,4 m) : bureau
	# GAS à 2 étages désormais, toit praticable (`roof_access`) sans parapet
	# (comme CraneShed/DerrickRise, autres positions fortes sans garde-corps,
	# évite le problème d'une porte de toit à percer dans un parapet). 2 accès
	# fonctionnels : escalier intérieur (rampe `building2`, `stair_side` "E",
	# sol -> étage 1 -> toit, aligné sur la porte E/étage 1) et porte S de
	# l'étage 1, qui rend `OfficeStair` (déjà existant) réellement
	# fonctionnel jusqu'au toit.
	#
	# PF5 EXEMPTÉE du critère "au moins 3 accès" (§c.7) — écart documenté, pas
	# une assertion affaiblie (même discipline que `test_snd_timings.gd`
	# ROTATION_EXEMPTIONS/ENTRY_EXEMPTIONS) : tout 3e accès EN HAUTEUR (qui
	# atteint le toit à moins de 6 m du centre, seul type qui compte pour ce
	# critère) tombe dans le corridor navmesh que suit le chemin SnD
	# attaquant<->site_a (derrick) côté ouest/sud de ce bâtiment — 3 essais
	# indépendants (escalier extérieur ouest 8,5 m ; porte N étage 1 seule,
	# sans même de pièce physique ; passerelle depuis le dessus de TankN, à
	# l'est, 2 variantes de position) ont chacun cassé
	# `test_snd_path_ratio_is_within_range` (ratio tombé à 1,15-1,48, sous le
	# plancher 1,5), alors que ce test est protégé par le contrat de cette
	# tâche ("un test ne se réécrit jamais pour coller au code"). Un 4e essai
	# (stair_side "W", aligné sur la porte ouest du rez-de-chaussée) cassait
	# le MÊME test pour une AUTRE raison (porte d'étage qui interfère avec la
	# porte du dessous) — signalé dans `blocked_on` pour la prochaine tâche
	# qui possède `Kit.gd`/`scripts/ai/BotNavMesh.gd`.
	A.call({"type": "building2", "name": "GasOffice", "pos": Vector3(26.5, 3.2, -7), "size": Vector3(7, 6.4, 5), "color_key": "wall",
		"floors": 2, "doors": [{"side": "S", "floor": 0}, {"side": "W", "floor": 0, "offset": 1.5}, {"side": "S", "floor": 1}, {"side": "E", "floor": 1}],
		"windows": ["S"], "roof_access": true, "parapet": 0.0, "stair_side": "E"})
	A.call({"type": "prop", "name": "SignGas", "prop": "sign_gas", "pos": Vector3(26.5, 4.8, -9.4), "cover": false, "tint": Cartoon.CONTAINER_RED})
	A.call({"type": "stairs", "name": "OfficeStair", "start": Vector3(24.5, 0, 0), "end": Vector3(24.5, 3.2, -4.5), "width": 1.5, "color_key": "platform"})
	A.call({"type": "building2", "name": "WestBlock", "pos": Vector3(18.75, 1.6, -2), "size": Vector3(3.5, 3.2, 8), "color_key": "wall",
		"floors": 1, "doors": [{"side": "E", "floor": 0}, {"side": "W", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0})
	A.call({"type": "building2", "name": "Warehouse", "pos": Vector3(13, 1.6, 7), "size": Vector3(8, 3.2, 8), "color_key": "cover",
		"floors": 1, "doors": [{"side": "W", "floor": 0}, {"side": "E", "floor": 0}, {"side": "N", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0})
	A.call({"type": "building2", "name": "SouthBlock", "pos": Vector3(24, 1.6, 9.5), "size": Vector3(8, 3.2, 4), "color_key": "wall",
		"floors": 1, "doors": [{"side": "N", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0})
	A.call({"type": "prop", "name": "SouthBlockAwning", "prop": "shack_awning", "pos": Vector3(24, 2.6, 7.5), "cover": false})

	A.call({"type": "box", "name": "TankN", "pos": Vector3(31.5, 1.75, -3), "size": Vector3(3, 3.5, 5), "color_key": "cover", "skin": "tank_horizontal"})
	A.call({"type": "box", "name": "TankS", "pos": Vector3(31.5, 1.75, 5), "size": Vector3(3, 3.5, 5), "color_key": "cover", "skin": "tank_horizontal"})
	A.call({"type": "box", "name": "TankMid", "pos": Vector3(27, 1.75, 1), "size": Vector3(2, 3.5, 4), "color_key": "cover", "skin": "tank_skid"})
	A.call({"type": "box", "name": "Manifold", "pos": Vector3(34.5, 1.75, -6), "size": Vector3(3, 3.5, 4), "color_key": "cover"})
	A.call({"type": "box", "name": "CourtDrums", "pos": Vector3(24, 0.6, 2), "size": Vector3(2, 1.2, 2), "color_key": "cover"})
	A.call({"type": "box", "name": "CourtCrates", "pos": Vector3(22.5, 0.9, 5), "size": Vector3(2, 1.8, 2), "color_key": "cover"})
	# BUG-30 (3e passage) : conteneurs empilés dans l'arrière-cour GAS, entre
	# GasOffice et WestBlock/CraneShed — sur la navmesh RÉELLE, cette ruelle
	# nord (contournant WestBlock par le nord, jamais par ses portes E/O)
	# donnait à l'équipe rouge une rotation directe vers le Hangar (zone
	# Hardpoint B) très en dessous de celle de l'équipe bleue (qui doit,
	# elle, franchir toute la Dune) : parité B mesurée 22,7 % à 14,7 % au fil
	# des correctifs précédents, toujours hors du plafond 8 %. Ce bloc (une
	# largeur de caisses empilées, cohérent avec `CourtDrums`/`CourtCrates`
	# juste à côté) ferme cette ruelle nord : la rotation rouge vers B doit
	# désormais, comme la rotation rouge vers C, traverser WestBlock par ses
	# portes E/O — mesuré : gap B ramené sous le plafond (voir `tests/maps/
	# test_wasteland_markers.gd`), sans toucher aux zones Hardpoint, aux
	# sites SnD ni aux rotations B->A/A->C/C->B (toutes restent dans leur
	# plage, marge vérifiée).
	A.call({"type": "box", "name": "GasAlleyContainers", "pos": Vector3(14.5, 1.2, -7.5), "size": Vector3(4, 2.4, 3.2), "color_key": "cover"})

	# ------------------------------------------------------------------
	#  Grand-Rue : 3 coudes (§c.2/§c.3, "chicanes tous les 20-25 m") — chaque
	# chicane est un mur plein (>= 1,4 m, casse la ligne de vue, `Kit.
	# SIGHT_MIN_TOP`) qui mord un côté du couloir et force un zigzag ; la
	# largeur laissée libre de l'autre côté (~4-5 m) reste bien au-dessus du
	# gabarit joueur (rayon 0,5 m). Coude 1 (ouest, mord le sud, on passe au
	# nord) -> coude 2 (centre, mord le nord, on passe au sud) -> coude 3
	# (est, mord le sud, on passe au nord) : 3 changements de côté, comme la
	# place FUEL -> citerne (déjà légèrement décalée) avant le premier.
	# ------------------------------------------------------------------
	A.call({"type": "box", "name": "ChicaneW", "pos": Vector3(-13, 1.2, 2.5), "size": Vector3(3, 2.4, 6), "color_key": "wall"})
	A.call({"type": "box", "name": "ChicaneC", "pos": Vector3(10, 1.2, -3.5), "size": Vector3(3, 2.4, 5), "color_key": "wall"})
	A.call({"type": "box", "name": "ChicaneE", "pos": Vector3(24.5, 1.2, 2.5), "size": Vector3(3, 2.4, 6), "color_key": "wall"})

	# ------------------------------------------------------------------
	#  Rue centrale : voitures, caisses
	# ------------------------------------------------------------------
	A.call({"type": "box", "name": "PlainCrates", "pos": Vector3(8, 0.9, -2), "size": Vector3(2, 1.8, 2), "color_key": "cover"})
	A.call({"type": "box", "name": "CarSedan", "pos": Vector3(-1, 0.7, 4.5), "size": Vector3(2.0, 1.4, 4.4), "color_key": "cover", "skin": "car_sedan_wreck"})
	A.call({"type": "box", "name": "CarPickup", "pos": Vector3(4, 0.9, 9.5), "size": Vector3(5.2, 1.8, 2.1), "color_key": "cover", "rot_y": PI * 0.5})
	A.call({"type": "box", "name": "CarBlue", "pos": Vector3(2.5, 0.8, 8.25), "size": Vector3(4.4, 1.6, 1.9), "color_key": "cover", "rot_y": PI * 0.5, "tint": Color("3f5fa0")})
	A.call({"type": "box", "name": "DockCrates", "pos": Vector3(16, 0.9, 8.25), "size": Vector3(3, 1.8, 2), "color_key": "cover"})

	# ------------------------------------------------------------------
	#  Décor pur (dress) — visuel seulement. Coordonnées non données par la
	#  table pour power_pole/pipe_run/tyre_stack/barrel ("dress: power_pole x6
	#  on z -3.5 and z 11; pipe_run on the tanks; tyre_stack, barrel by doors")
	#  => répartition raisonnable, meilleur effort, jamais dans l'espace
	#  praticable (cover=false).
	# ------------------------------------------------------------------
	for x in [-25.0, 0.0, 25.0]:
		A.call({"type": "prop", "name": "PolePlaza%d" % int(x), "prop": "power_pole", "pos": Vector3(x, 0, -3.5), "cover": false})
		A.call({"type": "prop", "name": "PoleRim%d" % int(x), "prop": "power_pole", "pos": Vector3(x, 0, 11), "cover": false})
	A.call({"type": "prop", "name": "PipeRunTanks", "prop": "pipe_run", "pos": Vector3(31.5, 3.5, 0), "rot_y": PI * 0.5, "cover": false})
	A.call({"type": "prop", "name": "TyreFuel", "prop": "tyre_stack", "pos": Vector3(-27, 0, -5.5), "cover": false})
	A.call({"type": "prop", "name": "BarrelGas", "prop": "barrel", "pos": Vector3(24.5, 0, -3.5), "cover": false})

	# ------------------------------------------------------------------
	#  Façades réelles (lead review, passe polish) — recouvrent le visuel des
	#  bâtiments Kit ci-dessus SANS toucher leur pos/size/portes (collision
	#  et navmesh déjà validés, inchangés) : posées "en dressing" par-dessus,
	#  contact-sol à la même (x,z), au jugé faute d'angle de façade connu du
	#  modèle (§ "never change validated collision/markers").
	# ------------------------------------------------------------------
	# Façades réelles côté rue (nord de la rue z~0-3 -> face sud, rot_y PI ;
	# sud de la rue -> face nord, rot_y 0 — meilleur effort faute d'une
	# convention "avant" documentée pour ces modèles, à confirmer en image).
	A.call({"type": "prop", "name": "GarageFront", "prop": "shopfront_corner_garage", "pos": Vector3(-17.5, 0, -7.5), "rot_y": PI, "tints": {"sign": Cartoon.CONTAINER_RED}, "cover": false})
	A.call({"type": "prop", "name": "GasOfficeFront", "prop": "shopfront_1_store", "pos": Vector3(26.5, 0, -7), "rot_y": PI, "tints": {"sign": Cartoon.CONTAINER_RED}, "cover": false})
	A.call({"type": "prop", "name": "WestBlockFront", "prop": "shopfront_1_bar", "pos": Vector3(18.75, 0, -2), "cover": false})
	A.call({"type": "prop", "name": "SouthBlockFront", "prop": "shopfront_2_saloon", "pos": Vector3(24, 0, 9.5), "cover": false})
	A.call({"type": "prop", "name": "FuelHouseFront", "prop": "shopfront_2_motel", "pos": Vector3(-30, 0, -7.5), "rot_y": PI, "tints": {"sign": Cartoon.CONTAINER_BLUE}, "cover": false})
	# Lead review (2e polish) : "~12-15 facades so no bare box faces a lane" —
	# les 5 bâtiments restants (Shack/Reservoir/Chapel/CraneShed/Warehouse)
	# n'avaient AUCUNE façade, + balcons/escaliers extérieurs + fouillis de
	# toit pour la densité de détail demandée.
	A.call({"type": "prop", "name": "ShackFront", "prop": "shopfront_1_bar", "pos": Vector3(-30, 0, 5.5), "cover": false})
	A.call({"type": "prop", "name": "ReservoirFront", "prop": "shopfront_1_store", "pos": Vector3(-10.5, 0, -7.5), "rot_y": PI, "tints": {"sign": Cartoon.CONTAINER_BLUE}, "cover": false})
	A.call({"type": "prop", "name": "ChapelFront", "prop": "shopfront_1_store", "pos": Vector3(-7.5, 0, 0), "rot_y": PI, "cover": false})
	A.call({"type": "prop", "name": "CraneShedFront", "prop": "shopfront_corner_garage", "pos": Vector3(3.5, 0, -9.5), "rot_y": PI, "cover": false})
	A.call({"type": "prop", "name": "WarehouseFront", "prop": "shopfront_2_motel", "pos": Vector3(13, 0, 7), "cover": false})
	A.call({"type": "prop", "name": "FuelHouseBalcony", "prop": "balcony_railing", "pos": Vector3(-30, 3.2, -4.6), "rot_y": PI, "cover": false})
	A.call({"type": "prop", "name": "GasOfficeBalcony", "prop": "balcony_railing", "pos": Vector3(26.5, 3.2, -4.6), "rot_y": PI, "cover": false})
	A.call({"type": "prop", "name": "GarageStairsExt", "prop": "exterior_stairs", "pos": Vector3(-14.5, 0, -5.5), "rot_y": PI * 0.5, "cover": false})
	A.call({"type": "prop", "name": "GasOfficeStairsExt", "prop": "exterior_stairs", "pos": Vector3(23.0, 0, -4.6), "cover": false})
	A.call({"type": "prop", "name": "RoofClutterFuel", "prop": "junk_pile", "pos": Vector3(-31.5, 6.4, -9.0), "cover": false})
	A.call({"type": "prop", "name": "RoofClutterWarehouse", "prop": "cable_spool", "pos": Vector3(15.5, 3.2, 8.5), "cover": false})
	A.call({"type": "prop", "name": "RoofClutterGasOffice", "prop": "tyre_ground", "pos": Vector3(28.5, 3.2, -8.5), "cover": false})

	# ------------------------------------------------------------------
	#  Fouillis de rue (lead review : "street clutter every few metres") —
	#  décor pur, jamais dans l'espace praticable, groupé/fusionné en
	#  MultiMesh par MapSetup._build_props (>= 3 instances du même nom).
	# ------------------------------------------------------------------
	var clutter := [
		["junk_pile", Vector3(-33.0, 0, 2.5)], ["scrap_sheets", Vector3(-25.5, 0, -3.2)],
		["cable_spool", Vector3(-21.0, 0, 3.0)], ["crate_stack", Vector3(-13.5, 0, -2.8)],
		["bottle_crates", Vector3(-9.0, 0, 2.6)], ["tyre_ground", Vector3(-4.5, 0, -3.0)],
		["fence_broken", Vector3(1.0, 0, 3.2)], ["junk_pile", Vector3(6.0, 0, -3.4)],
		["scrap_sheets", Vector3(11.0, 0, 3.0)], ["cable_spool", Vector3(16.5, 0, -3.0)],
		["crate_stack", Vector3(21.5, 0, 2.8)], ["bottle_crates", Vector3(29.0, 0, -2.5)],
		["tyre_ground", Vector3(33.5, 0, 2.7)], ["junk_pile", Vector3(-29.5, 0, -1.0)],
		["fence_broken", Vector3(4.0, 0, -0.5)],
	]
	for c in clutter:
		var prop_name: String = c[0]
		var p: Vector3 = c[1]
		A.call({"type": "prop", "name": "Clutter_%s_%d_%d" % [prop_name, int(p.x * 10.0), int(p.z * 10.0)], "prop": prop_name, "pos": p, "cover": false})
	for x in [-35.0, -20.0, -5.0, 10.0, 25.0]:
		A.call({"type": "prop", "name": "StreetLamp%d" % int(x), "prop": "street_lamp", "pos": Vector3(x, 0, 4.5), "cover": false})
	for x0 in [-30.0, -10.0, 10.0]:
		A.call({"type": "prop", "name": "Catenary%d" % int(x0), "prop": "wires_catenary", "pos": Vector3(x0, 4.3, -3.5), "rot_y": PI * 0.5, "cover": false})

	# ------------------------------------------------------------------
	#  Spawns, hardpoints, sites (§5 "Markers", ratios déjà vérifiés)
	# ------------------------------------------------------------------
	var sp0: Array = [
		Layouts._spawn(Vector3(-36.5, 1, -1), Vector3(-33, 1, -3.6)),
		Layouts._spawn(Vector3(-36.5, 1, 1), Vector3(-33, 1, 1.6)),
		Layouts._spawn(Vector3(-38.5, 1, -1), Vector3(-33, 1, -3.6)),
		Layouts._spawn(Vector3(-38.5, 1, 1), Vector3(-33, 1, 1.6)),
	]
	var sp1: Array = [
		Layouts._spawn(Vector3(36.5, 1, -1), Vector3(33, 1, 1)),
		Layouts._spawn(Vector3(36.5, 1, 1), Vector3(33, 1, 1)),
		Layouts._spawn(Vector3(38.5, 1, -1), Vector3(33, 1, 1)),
		Layouts._spawn(Vector3(38.5, 1, 1), Vector3(33, 1, 1)),
	]

	return {
		"id": "wasteland_v3", "name": "Wasteland (v3, banc de comparaison)",
		# Rôles -> kind peint (Cartoon.painted, lu par Kit.build_piece via
		# "<rôle>_kind"/"<rôle>_roof_kind") — ART-70 "Look Wasteland" : le
		# dictionnaire de palette vit désormais dans wasteland_look.gd
		# (WastelandLook.palette(), voir son en-tête pour le détail des
		# corrections de sol/falaises/tôle bleue/repères) ; seule retouche
		# de ce fichier pour cette tâche, comme verrouillé par le contrat.
		"palette": WastelandLook.palette(),
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		# §c.5 "Hardpoint : 3 zones" (A Chapelle / B Grue / C Hangar, ordre de
		# rotation B->A->C->B) — remplace les 4 anciens points (zone Épaves
		# retirée, collée au Hangar, §L3) : parité A<->C mesurée à vol d'oiseau
		# 1 % (24,0 / 23,8 m), voir `test_hardpoint_zone_parity_a_c` dans
		# tests/maps/test_wasteland.gd.
		"hardpoints": [Vector3(0.5, 1.5, -8.5), Vector3(-13, 1.5, 1), Vector3(14, 1.5, 6)],
		"site_a": {"pos": Vector3(19, 6.0, -21), "size": Vector3(8, 3, 6)},
		"site_b": {"pos": Vector3(13, 1.5, 7), "size": Vector3(6, 3, 6)},
		"bounds": {"min": Vector2(-40, -25), "max": Vector2(40, 18)},
		"asymmetric": true,
		# Boucle fermée (§7.4), faces INTÉRIEURES des 6 masses rocheuses de
		# bordure (CliffW/E/S, MassifNW/NE, CliffN) — voir dérivation détaillée
		# dans le rapport final (8 sommets, tracés depuis leurs étendues x/z).
		"perimeter": [
			Vector2(-40, 18), Vector2(-40, -14), Vector2(-2, -14), Vector2(-2, -25),
			Vector2(33, -25), Vector2(33, -8), Vector2(40, -8), Vector2(40, 18),
		],
	}
