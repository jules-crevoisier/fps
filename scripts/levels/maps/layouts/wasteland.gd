## wasteland.gd
## Wasteland — .orchestrator/maps-spec-v2.md §5, transcrit à la main depuis la
## table (map ASYMÉTRIQUE : aucun miroir, chaque pièce est unique, contrairement
## à Cargo Ship/aux six maps v1). Même pipeline PUR que Layouts.gd (aucun nœud),
## mais SANS ses helpers de miroir (inutiles ici) — seuls `Layouts._spawn()`
## est réutilisé pour rester cohérent avec le schéma `{pos, look}` attendu par
## MapSetup._build_markers.
##
## Palette : tons désert §5 (sable/planches/adobe/rock), tous hors des deux
## bandes de teinte réservées (calculs en commentaire à l'endroit où c'est le
## plus serré). Signalétique VIVE (lead override, wave 3) : FUEL bleu, GAS
## rouge — mêmes constantes Cartoon.CONTAINER_BLUE/RED que Cargo Ship pour la
## cohérence entre les deux maps flagship.
class_name WastelandLayout
extends RefCounted

static func data() -> Dictionary:
	var pieces: Array = []
	var A := func(p: Dictionary) -> void: pieces.append(p)

	# ------------------------------------------------------------------
	#  Sol, falaises (bornes de la carte) + périmètre invisible (§7.4)
	# ------------------------------------------------------------------
	A.call({"type": "box", "name": "Ground", "pos": Vector3(0, -1, -3.5), "size": Vector3(80, 2, 43), "color_key": "floor"})
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
	#  FUEL (compound blue, ouest)
	# ------------------------------------------------------------------
	A.call({"type": "building2", "name": "FuelHouse", "pos": Vector3(-30, 3.2, -7.5), "size": Vector3(6, 6.4, 6), "color_key": "wall",
		"floors": 2,
		"doors": [{"side": "S", "floor": 0}, {"side": "E", "floor": 0}, {"side": "E", "floor": 1}],
		"windows": ["S"], "roof_access": true, "parapet": 1.0, "stair_side": "W"})
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

	# ------------------------------------------------------------------
	#  Dune (côté bleu, glissade 15°)
	# ------------------------------------------------------------------
	A.call({"type": "box", "name": "DuneMound", "pos": Vector3(-17.5, 1.6, -12.25), "size": Vector3(7, 3.2, 3.5), "color_key": "rock"})
	A.call({"type": "ramp", "name": "DuneUp", "start": Vector3(-29, 0, -12.25), "end": Vector3(-21, 3.2, -12.25), "width": 3.5, "color_key": "rock"})
	A.call({"type": "ramp", "name": "DuneSlide", "start": Vector3(-14, 3.2, -12.25), "end": Vector3(-2, 0, -12.25), "width": 3.5, "color_key": "rock"})

	# ------------------------------------------------------------------
	#  Réservoir, chapelle, hangar-grue (centre)
	# ------------------------------------------------------------------
	A.call({"type": "building2", "name": "Reservoir", "pos": Vector3(-10.5, 1.6, -7.5), "size": Vector3(5, 3.2, 5), "color_key": "adobe",
		"floors": 1, "doors": [{"side": "S", "floor": 0}, {"side": "W", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0})
	A.call({"type": "stairs", "name": "ResStair", "start": Vector3(-11.5, 0, -0.5), "end": Vector3(-11.5, 3.2, -5), "width": 1.5, "color_key": "platform"})
	A.call({"type": "water_tower", "name": "WaterTower", "pos": Vector3(-10.5, 3.2, -7.5), "color_key": "accent"})
	A.call({"type": "building2", "name": "Chapel", "pos": Vector3(-7.5, 1.6, 0), "size": Vector3(5, 3.2, 6), "color_key": "adobe",
		"floors": 1, "doors": [{"side": "N", "floor": 0}, {"side": "S", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0})
	A.call({"type": "prop", "name": "ChapelRoofPeak", "prop": "shack_roof_peak", "pos": Vector3(-7.5, 3.2, 0), "cover": false})

	A.call({"type": "building2", "name": "CraneShed", "pos": Vector3(3.5, 1.6, -9.5), "size": Vector3(7, 3.2, 8), "color_key": "cover",
		"floors": 1, "doors": [{"side": "S", "floor": 0}, {"side": "E", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0})
	A.call({"type": "stairs", "name": "ShedStairS", "start": Vector3(0.75, 0, -1), "end": Vector3(0.75, 3.2, -5.5), "width": 1.5, "color_key": "platform"})
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
	A.call({"type": "box", "name": "DerrickRise", "pos": Vector3(19, 2.25, -21), "size": Vector3(12, 4.5, 8), "color_key": "rock"})
	A.call({"type": "ramp", "name": "DerrickRamp", "start": Vector3(15, 4.5, -17), "end": Vector3(15, 0, -6), "width": 4.0, "color_key": "platform"})
	A.call({"type": "stairs", "name": "RiseStair", "start": Vector3(31, 0, -19), "end": Vector3(25, 4.5, -19), "width": 2.0, "color_key": "platform"})
	for xz in [Vector2(20.5, -22.5), Vector2(20.5, -19.5), Vector2(23.5, -22.5), Vector2(23.5, -19.5)]:
		A.call({"type": "box", "name": "DerrickLeg%d_%d" % [int(xz.x * 10.0), int(xz.y * 10.0)], "pos": Vector3(xz.x, 9.5, xz.y), "size": Vector3(0.4, 10, 0.4), "color_key": "accent"})
	A.call({"type": "prop", "name": "OilDerrick", "prop": "oil_derrick", "pos": Vector3(22, 4.5, -21), "cover": false})

	# ------------------------------------------------------------------
	#  GAS (compound rouge, est)
	# ------------------------------------------------------------------
	A.call({"type": "building2", "name": "GasOffice", "pos": Vector3(26.5, 1.6, -7), "size": Vector3(7, 3.2, 5), "color_key": "wall",
		"floors": 1, "doors": [{"side": "S", "floor": 0}, {"side": "W", "floor": 0}], "windows": [], "roof_access": false, "parapet": 0.0})
	A.call({"type": "prop", "name": "SignGas", "prop": "sign_gas", "pos": Vector3(26.5, 3.2, -7), "cover": false, "tint": Cartoon.CONTAINER_RED})
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

	# ------------------------------------------------------------------
	#  Rue centrale : voitures, caisses
	# ------------------------------------------------------------------
	A.call({"type": "box", "name": "PlainCrates", "pos": Vector3(8, 0.9, -2), "size": Vector3(2, 1.8, 2), "color_key": "cover"})
	A.call({"type": "box", "name": "CarSedan", "pos": Vector3(-1, 0.7, 4.5), "size": Vector3(2.0, 1.4, 4.4), "color_key": "cover", "skin": "car_sedan_wreck"})
	A.call({"type": "box", "name": "CarPickup", "pos": Vector3(4, 0.9, 9.5), "size": Vector3(5.2, 1.8, 2.1), "color_key": "cover", "rot_y": PI * 0.5})
	A.call({"type": "box", "name": "CarBlue", "pos": Vector3(2.5, 0.8, 13), "size": Vector3(4.4, 1.6, 1.9), "color_key": "cover", "rot_y": PI * 0.5, "tint": Color("3f5fa0")})
	A.call({"type": "box", "name": "DockCrates", "pos": Vector3(16, 0.9, 13), "size": Vector3(3, 1.8, 2), "color_key": "cover"})

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
		"id": "wasteland", "name": "Wasteland",
		# Rôles -> kind peint (Cartoon.painted, lu par Kit.build_piece via
		# "<rôle>_kind"/"<rôle>_roof_kind") — lead review polish : le sol/les
		# murs rendaient plats (gris-lavande/bleu-gris), aucun "kind" n'était
		# jamais posé sur ces deux nouvelles maps. design.md v2 : sol/rue
		# sable ocre, murs planches usées, tôle rouillée (murs "cover" +
		# toits), plateformes/base du derrick béton, accents métal peint.
		"palette": {
			"floor": Color("c4935a"), "wall": Color("8f6a45"), "cover": Color("8f5a3d"),
			"platform": Color("9c9086"), "accent": Color("4a4640"),
			"rock": Color("9c8567"), "adobe": Color("b08f66"),
			"floor_kind": "sand_dirt", "wall_kind": "wood_planks", "cover_kind": "corrugated_metal",
			"platform_kind": "cracked_concrete", "accent_kind": "painted_metal", "rock_kind": "sand_dirt",
			"adobe_kind": "cracked_concrete",
			"wall_roof_kind": "rust", "adobe_roof_kind": "corrugated_metal",
		},
		"pieces": pieces,
		"spawns": {0: sp0, 1: sp1},
		"hardpoints": [Vector3(0, 1.5, 7), Vector3(-13, 1.5, -1), Vector3(1, 4.7, -9.5), Vector3(13, 1.5, 7)],
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
