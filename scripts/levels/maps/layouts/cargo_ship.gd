## cargo_ship.gd
## Cargo Ship — .orchestrator/maps-spec-v2.md §4, transcrit à la main depuis la
## table (pas de skeleton partagé, pas d'invention de disposition). Même
## pipeline PUR que Layouts.gd (Dictionary/Vector3/Vector2, aucun nœud) —
## réutilise SES helpers de miroir (`_add`/`_mirror_pos`/`_mirror_spawn`/
## `_spawn`), publics par convention GDScript même préfixés `_`, plutôt que
## de les dupliquer : ce fichier ne touche PAS Layouts.gd (hors périmètre
## cette manche, "don't change Layouts.gd geometry of the six maps").
##
## Palette : la table §4 donne des teintes de conteneur MUETTES (slate/ochre/
## teal/bone/rust, C<=0.05, pensées pour la DA v1 désaturée). Le lead a
## explicitement renversé cette clause pour cette carte : "containers and
## signs are VIVID (red/blue/orange/white)... the world only avoids hues
## 300-355° et 105-145°" — les 5 clés `mat` ci-dessous portent donc les
## teintes VIVES (Cartoon.CONTAINER_RED/BLUE/ORANGE/WHITE + un cyan-sarcelle
## dédié, teal, hue ~187° : hors des deux bandes réservées), le sol/mur/plate-
## forme/accent restent proches des tons acier/rouille d'origine (déjà hors
## bandes, cf. calcul de teinte en commentaire).
class_name CargoShipLayout
extends RefCounted

const MODE := "x"

## Pose une série de `ship_railing` (deck_railing, 2 m/segment réel, manifest.json)
## le long de start->end, purement visuelle (cover:false — le garde-corps
## RÉEL, collision comprise, reste le `fence()` Kit déjà posé ailleurs ;
## §7.2 "dress is visual only", jamais de double collision). Appelé deux
## fois par paire de bastingage (côté ouest tel quel + côté est, coordonnées
## X déjà inversées par l'appelant) plutôt que de s'appuyer sur le miroir
## générique de Layouts._add : celui-ci ne corrige PAS `rot_y` pour un angle
## arbitraire (seuls pos/start/end/doors/windows sont réfléchis), donc un
## simple `mirror:true` aurait posé les balustrades du côté est à l'envers.
static func _railing_run(pieces: Array, start: Vector3, end: Vector3) -> void:
	var diff := end - start
	var flat_len := Vector2(diff.x, diff.z).length()
	if flat_len < 0.05:
		return
	var seg_len := 2.0
	var n := maxi(1, int(round(flat_len / seg_len)))
	var yaw := atan2(diff.x, diff.z)
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		var p: Vector3 = start.lerp(end, t)
		pieces.append({
			"type": "prop", "name": "Rail_%d_%d_%d" % [int(p.x * 10.0), int(p.y * 10.0), int(p.z * 10.0)],
			"prop": "ship_railing", "pos": p, "rot_y": yaw, "cover": false,
		})

static func data() -> Dictionary:
	var mode := MODE
	var pieces: Array = []
	var A := func(p: Dictionary, m: bool = false) -> void: Layouts._add(pieces, p, mode, m)

	# ------------------------------------------------------------------
	#  Ponts (§4 table, ligne "floor")
	# ------------------------------------------------------------------
	A.call({"type": "box", "name": "SideDeck", "pos": Vector3(-19.5, -1.55, 0), "size": Vector3(11, 3.1, 44), "color_key": "floor"}, true)
	A.call({"type": "box", "name": "AftDeck", "pos": Vector3(0, -1.55, -18.5), "size": Vector3(28, 3.1, 7), "color_key": "floor"})
	A.call({"type": "box", "name": "Spine", "pos": Vector3(0, -1.55, 0), "size": Vector3(28, 3.1, 8), "color_key": "floor"})
	A.call({"type": "box", "name": "ForeDeck", "pos": Vector3(0, -1.55, 19.5), "size": Vector3(28, 3.1, 5), "color_key": "floor"})
	A.call({"type": "box", "name": "Stern", "pos": Vector3(0, -1.55, -29), "size": Vector3(26, 3.1, 14), "color_key": "floor"})
	A.call({"type": "box", "name": "Bow", "pos": Vector3(0, -1.55, 25), "size": Vector3(34, 3.1, 6), "color_key": "floor"})
	A.call({"type": "box", "name": "Forecastle", "pos": Vector3(0, -0.25, 30), "size": Vector3(18, 5.7, 4), "color_key": "wall"})
	A.call({"type": "box", "name": "HoldFloorN", "pos": Vector3(0, -3.1, -9.5), "size": Vector3(28, 1, 11), "color_key": "platform"})
	A.call({"type": "box", "name": "HoldFloorS", "pos": Vector3(0, -3.1, 10.5), "size": Vector3(28, 1, 13), "color_key": "platform"})

	# ------------------------------------------------------------------
	#  Pavois (bulwark) — pourtour extérieur réel de la coque (mer/eau), PAS
	#  les bords internes des cales (couverts par Coaming + les îlots
	#  conteneur, qui servent déjà de garde-corps). h1.1, sauf gaillard 2.6.
	# ------------------------------------------------------------------
	A.call({"type": "fence", "name": "BulwarkSideOuter", "start": Vector3(-25, 0, -22), "end": Vector3(-25, 0, 22), "height": 1.1, "color_key": "wall"}, true)
	A.call({"type": "fence", "name": "BulwarkSternShoulder", "start": Vector3(-25, 0, -22), "end": Vector3(-13, 0, -22), "height": 1.1, "color_key": "wall"}, true)
	A.call({"type": "fence", "name": "BulwarkSternSide", "start": Vector3(-13, 0, -22), "end": Vector3(-13, 0, -36), "height": 1.1, "color_key": "wall"}, true)
	A.call({"type": "fence", "name": "BulwarkSternCap", "start": Vector3(-13, 0, -36), "end": Vector3(13, 0, -36), "height": 1.1, "color_key": "wall"})
	A.call({"type": "fence", "name": "BulwarkBowShoulder", "start": Vector3(-25, 0, 22), "end": Vector3(-17, 0, 22), "height": 1.1, "color_key": "wall"}, true)
	A.call({"type": "fence", "name": "BulwarkBowSide", "start": Vector3(-17, 0, 22), "end": Vector3(-17, 0, 28), "height": 1.1, "color_key": "wall"}, true)
	A.call({"type": "fence", "name": "BulwarkBowStep", "start": Vector3(-17, 0, 28), "end": Vector3(-9, 0, 28), "height": 1.1, "color_key": "wall"}, true)
	A.call({"type": "fence", "name": "BulwarkForecastleStep", "start": Vector3(-12.2, 2.6, 28), "end": Vector3(-9, 2.6, 28), "height": 1.1, "color_key": "wall"}, true)
	A.call({"type": "fence", "name": "BulwarkForecastleSide", "start": Vector3(-9, 2.6, 28), "end": Vector3(-9, 2.6, 32), "height": 1.1, "color_key": "wall"}, true)
	A.call({"type": "fence", "name": "BulwarkForecastleCap", "start": Vector3(-9, 2.6, 32), "end": Vector3(9, 2.6, 32), "height": 1.1, "color_key": "wall"})

	# Garde-corps `ship_railing` (deck_railing) le long du MÊME tracé que le
	# bastingage ci-dessus — visuel seulement (voir _railing_run) ; côté est
	# posé explicitement (x inversé) pour chaque segment côté ouest.
	for seg in [
		[Vector3(-25, 0, -22), Vector3(-25, 0, 22)],
		[Vector3(-25, 0, -22), Vector3(-13, 0, -22)],
		[Vector3(-13, 0, -22), Vector3(-13, 0, -36)],
		[Vector3(-25, 0, 22), Vector3(-17, 0, 22)],
		[Vector3(-17, 0, 22), Vector3(-17, 0, 28)],
		[Vector3(-17, 0, 28), Vector3(-9, 0, 28)],
		[Vector3(-12.2, 2.6, 28), Vector3(-9, 2.6, 28)],
		[Vector3(-9, 2.6, 28), Vector3(-9, 2.6, 32)],
	]:
		var s: Vector3 = seg[0]
		var e: Vector3 = seg[1]
		_railing_run(pieces, s, e)
		_railing_run(pieces, Vector3(-s.x, s.y, s.z), Vector3(-e.x, e.y, e.z))
	_railing_run(pieces, Vector3(-13, 0, -36), Vector3(13, 0, -36))
	_railing_run(pieces, Vector3(-9, 2.6, 32), Vector3(9, 2.6, 32))

	# ------------------------------------------------------------------
	#  Coaming (rebord des cales, 4 m d'écart à x0 entre les deux moitiés)
	# ------------------------------------------------------------------
	for z in [-15.0, -4.0, 4.0, 17.0]:
		A.call({"type": "fence", "name": "Coaming%d" % int(z * 10.0), "start": Vector3(-14, 0, z), "end": Vector3(-2, 0, z), "height": 1.0, "color_key": "platform"}, true)

	# ------------------------------------------------------------------
	#  Rampes de glissade (18°, 8 m) + escaliers de lashing
	# ------------------------------------------------------------------
	A.call({"type": "ramp", "name": "HoldRampN", "start": Vector3(-14, 0, -13.5), "end": Vector3(-6, -2.6, -13.5), "width": 2.5, "color_key": "platform"}, true)
	A.call({"type": "ramp", "name": "HoldRampS", "start": Vector3(-14, 0, 15), "end": Vector3(-6, -2.6, 15), "width": 3.0, "color_key": "platform"}, true)
	for z in [-9.5, 10.5]:
		A.call({"type": "stairs", "name": "LashStair%d" % int(z * 10.0), "start": Vector3(-20.5, 0, z), "end": Vector3(-16.54, 2.6, z), "width": 2.0, "color_key": "platform"}, true)

	# Passerelle ancre -> îlot (cale nord uniquement, table §4)
	A.call({"type": "catwalk", "name": "GangwayN", "start": Vector3(-14.1, 2.6, -9.5), "end": Vector3(-6.1, 2.6, -9.5), "width": 2.0, "color_key": "platform"}, true)

	# ------------------------------------------------------------------
	#  Pieds de grue de pont (pas de skin : "deck_crane" -> cargo_crane du
	#  manifeste est une grue ENTIÈRE 3.2x10x8.5, bien trop grande pour un
	#  simple socle 2x5.6x3.5 — l'étirer violerait §8.15 "skin scale 0.8-1.25"
	#  ET rendrait mal ; boîte peinte plate, fidèle à la taille/couleur "wall"
	#  de la table).
	# ------------------------------------------------------------------
	for z in [-5.75, 5.75]:
		A.call({"type": "box", "name": "Pedestal%d" % int(z * 100.0), "pos": Vector3(-13, 0.2, z), "size": Vector3(2, 5.6, 3.5), "color_key": "wall"}, true)

	# ------------------------------------------------------------------
	#  Îlots (conteneurs pleins, centrés sur l'axe : pas de miroir X)
	#  "2h" = un 2e niveau empilé (y += 2.6) au-dessus du niveau donné.
	# ------------------------------------------------------------------
	for z in [-10.72, -8.28]:
		for y in [-1.3, 1.3]:
			A.call({"type": "container", "name": "IslandN_%d_%d" % [int(z * 100.0), int(y * 100.0)], "pos": Vector3(0, y, z), "size": Vector3(12.2, 2.6, 2.44), "axis": "x", "solid": true, "color_key": "slate", "skin": "container_40", "skin_rot_y": PI * 0.5})
	for z in [9.28, 11.72]:
		for y in [-1.3, 1.3]:
			A.call({"type": "container", "name": "IslandS_%d_%d" % [int(z * 100.0), int(y * 100.0)], "pos": Vector3(0, y, z), "size": Vector3(12.2, 2.6, 2.44), "axis": "x", "solid": true, "color_key": "ochre", "skin": "container_40", "skin_rot_y": PI * 0.5})

	# Ancres (2 positions z, chacune miroitée en x)
	for z in [-9.5, 10.5]:
		A.call({"type": "container", "name": "Anchor%d" % int(z * 10.0), "pos": Vector3(-15.32, 1.3, z), "size": Vector3(2.44, 2.6, 6.1), "axis": "z", "solid": true, "color_key": "teal", "skin": "container_20"}, true)

	# Coins (2 positions z, 2h, chacun miroité en x)
	for z in [-15.6, 16.6]:
		for y in [1.3, 3.9]:
			A.call({"type": "container", "name": "Corner%d_%d" % [int(z * 10.0), int(y * 10.0)], "pos": Vector3(-15.32, y, z), "size": Vector3(2.44, 2.6, 6.1), "axis": "z", "solid": true, "color_key": "rust", "skin": "container_20"}, true)

	# Bordées extérieures (∓16, 2h, chacune miroitée en x)
	for z in [-16.0, 16.0]:
		for y in [1.3, 3.9]:
			A.call({"type": "container", "name": "Outboard%d_%d" % [int(z * 10.0), int(y * 10.0)], "pos": Vector3(-23.78, y, z), "size": Vector3(2.44, 2.6, 6.1), "axis": "z", "solid": true, "color_key": "bone", "skin": "container_20"}, true)

	# Bouclier rayé (3h, palier du milieu en slate) — centré en z0, miroité en x
	A.call({"type": "container", "name": "ShieldLow", "pos": Vector3(-19.22, 1.3, 0), "size": Vector3(2.44, 2.6, 12.2), "axis": "z", "solid": true, "color_key": "rust", "skin": "container_40"}, true)
	A.call({"type": "container", "name": "ShieldMid", "pos": Vector3(-19.22, 3.9, 0), "size": Vector3(2.44, 2.6, 12.2), "axis": "z", "solid": true, "color_key": "slate", "skin": "container_40"}, true)
	A.call({"type": "container", "name": "ShieldHigh", "pos": Vector3(-19.22, 6.5, 0), "size": Vector3(2.44, 2.6, 12.2), "axis": "z", "solid": true, "color_key": "rust", "skin": "container_40"}, true)

	# ------------------------------------------------------------------
	#  Échine (spine) — hardpoint 1
	# ------------------------------------------------------------------
	A.call({"type": "container", "name": "SpineMid", "pos": Vector3(0, 1.3, 0), "size": Vector3(12.2, 2.6, 2.44), "axis": "x", "solid": true, "color_key": "ochre", "skin": "container_40", "skin_rot_y": PI * 0.5})
	A.call({"type": "container", "name": "SpineEnd", "pos": Vector3(-9.15, 1.3, 0), "size": Vector3(6.1, 2.6, 2.44), "axis": "x", "solid": true, "color_key": "ochre", "skin": "container_20", "skin_rot_y": PI * 0.5}, true)
	A.call({"type": "container", "name": "SpineCap", "pos": Vector3(0, 3.9, 0), "size": Vector3(6.1, 2.6, 2.44), "axis": "x", "solid": true, "color_key": "bone", "skin": "container_20", "skin_rot_y": PI * 0.5})
	A.call({"type": "stairs", "name": "SpineStair", "start": Vector3(-16.5, 0, 0), "end": Vector3(-12.2, 2.6, 0), "width": 2.0, "color_key": "platform"}, true)

	# Caisses de passage + chicane
	for z in [-1.97, 1.97]:
		A.call({"type": "box", "name": "PassCrate%d" % int(z * 100.0), "pos": Vector3(-6, 0.9, z), "size": Vector3(1.5, 1.8, 1.5), "color_key": "cover"}, true)
	for z in [-3.19, 3.19]:
		A.call({"type": "box", "name": "PassCrateC%d" % int(z * 100.0), "pos": Vector3(0, 0.9, z), "size": Vector3(1.5, 1.8, 1.5), "color_key": "cover"})

	# Escalier avant, par-dessus la tranchée sud jusqu'au sommet de l'îlot S
	A.call({"type": "stairs", "name": "ForeStair", "start": Vector3(0, 0, 17.5), "end": Vector3(0, 2.6, 12.94), "width": 2.0, "color_key": "platform"})

	# ------------------------------------------------------------------
	#  Proue — rangée, perchoir, escaliers
	# ------------------------------------------------------------------
	A.call({"type": "container", "name": "BowRow", "pos": Vector3(0, 1.3, 26.78), "size": Vector3(12.2, 2.6, 2.44), "axis": "x", "solid": true, "color_key": "slate", "skin": "container_40", "skin_rot_y": PI * 0.5})
	A.call({"type": "container", "name": "BowRowSide", "pos": Vector3(-9.15, 1.3, 26.78), "size": Vector3(6.1, 2.6, 2.44), "axis": "x", "solid": true, "color_key": "slate", "skin": "container_20", "skin_rot_y": PI * 0.5}, true)
	A.call({"type": "container", "name": "BowPerch", "pos": Vector3(0, 3.9, 26.78), "size": Vector3(6.1, 2.6, 2.44), "axis": "x", "solid": true, "color_key": "rust", "skin": "container_20", "skin_rot_y": PI * 0.5})
	A.call({"type": "stairs", "name": "BowStair", "start": Vector3(-11, 0, 21.5), "end": Vector3(-11, 2.6, 25.56), "width": 2.0, "color_key": "platform"}, true)
	A.call({"type": "stairs", "name": "PerchStair", "start": Vector3(-7.5, 2.6, 26.78), "end": Vector3(-3.05, 5.2, 26.78), "width": 2.0, "color_key": "platform"}, true)
	A.call({"type": "box", "name": "Windlass", "pos": Vector3(-14.5, 0.7, 26), "size": Vector3(2.5, 1.4, 2.5), "color_key": "cover", "skin": "windlass"}, true)

	# ------------------------------------------------------------------
	#  Passerelle (bridge), ailerons
	# ------------------------------------------------------------------
	A.call({"type": "building2", "name": "Bridge", "pos": Vector3(0, 3.2, -30), "size": Vector3(12, 6.4, 10), "color_key": "accent",
		"floors": 2,
		"doors": [
			{"side": "S", "floor": 0},
			{"side": "W", "floor": 0, "offset": -3.0},
			{"side": "E", "floor": 0, "offset": -3.0},
			{"side": "W", "floor": 1, "offset": 3.5},
			{"side": "E", "floor": 1, "offset": 3.5},
		],
		"windows": ["S"], "roof_access": true, "parapet": 1.0, "stair_side": "N"})
	A.call({"type": "box", "name": "WingW", "pos": Vector3(-9.5, 3.075, -26.5), "size": Vector3(7, 0.25, 3), "color_key": "platform"}, true)
	A.call({"type": "fence", "name": "WingRailA", "start": Vector3(-13, 3.2, -28), "end": Vector3(-6, 3.2, -28), "height": 1.0, "color_key": "wall"}, true)
	A.call({"type": "fence", "name": "WingRailB", "start": Vector3(-13, 3.2, -28), "end": Vector3(-13, 3.2, -25), "height": 1.0, "color_key": "wall"}, true)
	A.call({"type": "stairs", "name": "WingStair", "start": Vector3(-11.5, 0, -20.5), "end": Vector3(-11.5, 3.2, -25), "width": 2.0, "color_key": "platform"}, true)
	for y in [1.3, 3.9]:
		A.call({"type": "container", "name": "SternStack%d" % int(y * 10.0), "pos": Vector3(-10, y, -32.9), "size": Vector3(2.44, 2.6, 6.1), "axis": "z", "solid": true, "color_key": "teal", "skin": "container_20"}, true)

	# ------------------------------------------------------------------
	#  Écoutilles, caisses de pont, fûts
	# ------------------------------------------------------------------
	A.call({"type": "box", "name": "HatchAft", "pos": Vector3(-8, 1.25, -19.5), "size": Vector3(4, 2.5, 3), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "HatchFore", "pos": Vector3(-6, 1.25, 19.5), "size": Vector3(4, 2.5, 3), "color_key": "cover"}, true)
	A.call({"type": "box", "name": "HatchPile", "pos": Vector3(0, 0.6, -19.5), "size": Vector3(4, 1.2, 1.6), "color_key": "cover"})
	for z in [-9.5, 10.5]:
		A.call({"type": "box", "name": "DeckCrate%d" % int(z * 10.0), "pos": Vector3(-22.5, 0.9, z), "size": Vector3(2, 1.8, 2), "color_key": "cover"}, true)
	for z in [-13.5, 15.0]:
		A.call({"type": "box", "name": "Drums%d" % int(z * 10.0), "pos": Vector3(0, -1.7, z), "size": Vector3(2.4, 1.8, 1.2), "color_key": "cover"})

	# ------------------------------------------------------------------
	#  Mer + volume de mise à mort (kill_volumes, §7.3)
	# ------------------------------------------------------------------
	A.call({"type": "box", "name": "Sea", "pos": Vector3(0, -6.5, -2), "size": Vector3(160, 1, 160), "color_key": "sea", "visual_only": true})

	# ------------------------------------------------------------------
	#  Décor pur (dress) — visuel seulement, jamais de collision "cover"
	# ------------------------------------------------------------------
	# NOTE lead review (wave 3 polish) : l'ancien "ShipHull" (skin ship_hull ->
	# hull_mid, footprint réel 7x9x5 — voir manifest.json) posé en pos-contact-
	# sol y=-3.1 débordait jusqu'à y=1.9, AU-DESSUS du pont (0), en PLEIN sur
	# l'échine centrale : la grande dalle sombre qui traversait les vues à
	# hauteur d'œil. hull_bow/mid/stern ne sont d'ailleurs pas utilisés par
	# scripts/dev/TargetCargo.gd (la scène de calibration approuvée par le
	# lead) — la coque extérieure ne se voit jamais depuis le pont en jeu.
	# Supprimé ; remplacé par les mêmes petits accents de pont que
	# TargetCargo.gd (bollard/life_ring/stairs_ladder), au bon endroit.
	A.call({"type": "prop", "name": "ShipBridgeDress", "prop": "ship_bridge_dress", "pos": Vector3(0, 0, -30), "cover": false})
	A.call({"type": "prop", "name": "ShipMastBridge", "prop": "ship_mast", "pos": Vector3(0, 6.4, -33), "cover": false})
	A.call({"type": "prop", "name": "ShipMastBow", "prop": "ship_mast", "pos": Vector3(0, 2.6, 30.5), "cover": false})
	A.call({"type": "prop", "name": "Lifeboat", "prop": "lifeboat", "pos": Vector3(-14.5, 3, -31), "cover": false}, true)
	A.call({"type": "prop", "name": "Gangway", "prop": "gangway", "pos": Vector3(-26, -2, 0), "cover": false}, true)
	A.call({"type": "prop", "name": "StairsLadderBridge", "prop": "stairs_ladder", "pos": Vector3(0, 0, -27.5), "cover": false})
	A.call({"type": "prop", "name": "LifeRing", "prop": "life_ring", "pos": Vector3(-9.3, 1.3, 26), "tint": Cartoon.CONTAINER_RED, "cover": false}, true)
	for z in [-31.0, -19.5, -9.5, 9.5, 19.5, 31.0]:
		A.call({"type": "prop", "name": "Bollard%d" % int(z * 10.0), "prop": "bollard", "pos": Vector3(-24.3, 0, z), "cover": false}, true)

	# Grues de quai à l'arrière-plan (hero ref: "cranes overhead"), hors de
	# l'emprise jouable (au-delà du bastingage, x -25) — pur décor de skyline,
	# jamais de collision.
	A.call({"type": "prop", "name": "DockCrane", "prop": "deck_crane", "pos": Vector3(-31, 0, -6), "tint": Color("f2b51d"), "cover": false}, true)

	# Piles irrégulières décalées (§ lead review "irregular offset stacks with
	# open containers, hatches, lashing bars, pipe manifolds") — pur décor
	# hors des cases déjà validées (Island/Anchor/Corner/…), jamais de
	# collision : ne touche à rien de déjà testé.
	A.call({"type": "prop", "name": "OpenStackN", "prop": "container_open20", "pos": Vector3(-22.6, 1.3, -6.0), "rot_y": PI * 0.5, "tint": Cartoon.CONTAINER_ORANGE, "cover": false}, true)
	A.call({"type": "prop", "name": "OffsetStack2", "prop": "container_stack2", "pos": Vector3(-22.2, 0, -16.5), "rot_y": PI * 0.5, "tint": Cartoon.CONTAINER_WHITE, "cover": false}, true)
	A.call({"type": "prop", "name": "OffsetStack3", "prop": "container_stack3", "pos": Vector3(-22.2, 0, 17.0), "rot_y": PI * 0.5, "tint": Cartoon.CONTAINER_BLUE, "cover": false}, true)
	A.call({"type": "prop", "name": "DeckHatchExtra", "prop": "deck_hatch", "pos": Vector3(-4.0, 0.05, -19.5), "cover": false}, true)
	A.call({"type": "prop", "name": "PipeManifold", "prop": "pipe_manifold", "pos": Vector3(-23.0, 0, -1.0), "cover": false}, true)
	for lb in [Vector3(-14.9, 2.6, -8.7), Vector3(-14.9, 2.6, -10.3), Vector3(9.15, 1.3, -0.5), Vector3(9.15, 3.9, -0.5)]:
		A.call({"type": "prop", "name": "Lashing_%d_%d" % [int(lb.x * 10.0), int(lb.z * 10.0)], "prop": "lashing_bar", "pos": lb, "cover": false})

	# ------------------------------------------------------------------
	#  Spawns (§4 "Markers") — équipe 0 flanc ouest, équipe 1 = miroir.
	# ------------------------------------------------------------------
	var sp0: Array = []
	for z in [-3.0, -1.0, 1.0, 3.0]:
		var look := Vector3(-18, 1, -12) if z < 0 else Vector3(-18, 1, 12)
		sp0.append(Layouts._spawn(Vector3(-22.7, 1, z), look))
	var sp1: Array = []
	for s in sp0:
		sp1.append(Layouts._mirror_spawn(s, mode))

	return {
		"id": "cargo_ship", "name": "Cargo Ship",
		# Rôles -> kind peint (lead review polish, même motif que Wasteland) :
		# pont "ship_deck" gris chaud clair, muret/coque "painted_metal" rouge
		# coque sombre, superstructure (accent) "painted_metal" blanc.
		"palette": {
			"floor": Color("c4bdae"), "wall": Color("7a2820"), "cover": Color("8e6e66"),
			"platform": Color("9c9690"), "accent": Color("e8e4d8"),
			"slate": Cartoon.CONTAINER_BLUE, "ochre": Cartoon.CONTAINER_ORANGE,
			"teal": Color("1c93a3"), "bone": Cartoon.CONTAINER_WHITE, "rust": Cartoon.CONTAINER_RED,
			"sea": Color("54606a"),
			"floor_kind": "ship_deck", "wall_kind": "painted_metal", "platform_kind": "cracked_concrete",
			"accent_kind": "painted_metal", "cover_kind": "rust",
		},
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		"hardpoints": [Vector3(0, 1.5, 0), Vector3(-10, -1.1, 10.5), Vector3(0, 4.2, -30), Vector3(10, -1.1, 10.5)],
		"site_a": {"pos": Vector3(18, 1.5, -19), "size": Vector3(8, 3, 6)},
		"site_b": {"pos": Vector3(18, 1.5, 19), "size": Vector3(8, 3, 6)},
		"bounds": {"min": Vector2(-25, -36), "max": Vector2(25, 32)},
		"asymmetric": false,
		"kill_volumes": [{"pos": Vector3(0, -8, -2), "size": Vector3(160, 6, 160)}],
	}
