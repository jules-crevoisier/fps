## wasteland_bots.gd
## LD-42 (docs/research/11_wasteland_v4_layout.md) : données bots PURES
## (Dictionary/Vector3, aucun nœud) pour Wasteland v4, fusionnées par-dessus
## `WastelandLayout.data()` (`MapSetup._assemble_wasteland`, hors de mon
## périmètre). Même schéma que LD-24/BOT-22B (`lanes`, `hotspots`,
## `hp_hold_points`, `nav_links`, `danger_spans`, `bot_knowledge`), recalé sur
## la géométrie et la navmesh v4 (sondes `NavigationServer3D`, comme LD-24).
##
## ÉCART ASSUMÉ envers LD-24 : ce fichier ne dépend PLUS de
## `WastelandMarkers` (positions fortes, entrées Hardpoint, tdm_spawns) —
## cette tâche (LD-42) et le renouvellement de `wasteland_markers.gd` pour la
## v4 tournent EN PARALLÈLE dans la même vague (contrat de tâche : « le lead
## traite lui-même... Marqueurs v4... en parallèle »), et au moment d'écrire
## ce fichier `wasteland_markers.gd` porte encore les coordonnées v3 (Crête/
## Ravin/Chapelle/Grue/Hangar). Prendre une dépendance dessus aurait rendu ce
## fichier incorrect selon l'état d'avancement de l'autre tâche. Toutes les
## données qui venaient de là (positions fortes PP1-PP5, entrées de zone
## Hardpoint P1/P2/P3) sont donc dérivées ICI directement depuis les pièces
## RÉELLES et FIXES de `WastelandLayout.data()` (`wasteland.gd`, déjà livré
## v4 par LD-40, immuable pour cette tâche) — jamais réinventées au hasard,
## toujours calées sur les coordonnées `_bld`/`_box` réelles du blockout et
## vérifiées par sonde `NavigationServer3D` (tests/ai/test_wasteland_bot_data.gd).
##
## Cinq clés (même contrat que LD-24) :
##  - `lanes` : 3 polylignes west -> east (`grand_rue`/`interieurs`/`canyon`,
##    docs/research/11_wasteland_v4_layout.md §5), chacune 8-12 points réels.
##  - `hotspots` : 12 points (3 par lane + PP2/PP3/PP4, jamais redéfinis —
##    mêmes valeurs que `_bk_perches()`).
##  - `hp_hold_points` : 5 points par zone Hardpoint (P1 Wagon / P2 Magasin
##    ouest / P3 Gué, `WastelandLayout.data()["hardpoints"]`, ordre LD-40),
##    `covers` indexe `_hp_zone_entries()[zone]` (déclaré ci-dessous, mêmes
##    entrées que consomme `_bk_hp_holds().watch`).
##  - `nav_links` : 6 raccourcis (sauts/chutes hors de portée du bake
##    automatique) — 2 sauts de galerie (SaloonW/E -> place) et 4 chutes de
##    parapet (bord du plateau -> canyon, §6 du doc "la chute de 2m reste
##    sous le seuil d'étourdissement").
##  - `danger_spans` : 4 tronçons exposés (<=6), extrémités reprises des
##    lanes/points déjà réels ci-dessous.
##
## `resources/bot_spots/wasteland.tres` (rebake BotSpots) est un fichier
## SÉPARÉ, produit par `tools/bake_bot_spots.gd -- --map=wasteland` une fois
## ce fichier en place — voir tests/ai/test_wasteland_bot_data.gd.
class_name WastelandBots
extends RefCounted


# ======================================================================
#  Offsets de navmesh (sondes `NavigationServer3D.map_get_closest_point`,
#  tests/ai/test_wasteland_bot_data.gd) : le bake (cell_height=0.25,
#  agent_radius/height, MapSetup._build_geometry) place systématiquement la
#  surface praticable 0,5 m AU-DESSUS du dessus géométrique d'un sol plat,
#  quel que soit ce dessus (vérifié à top=0,0 ET top=-2,0 : les deux
#  retombent à +0,5 m). Constantes réutilisées PARTOUT ci-dessous plutôt que
#  des littéraux dispersés, pour ne calibrer qu'à un seul endroit si le bake
#  change.
# ======================================================================
const _GROUND_Y := 0.5    ## plateau (`G_PlateauW/C/E`, dessus à y=0).
const _CANYON_Y := -1.5   ## fond du ravin (`G_Canyon`, dessus à y=-2).
const _ETAGE_Y := 3.7     ## étage/galerie (dessus de dalle à y=3.2, `floor_h`
                           ## des bâtiments à 2 niveaux, Hotel/Banque/Saloon*).


# ======================================================================
#  Positions fortes PP1-PP5 (§6 du doc) — dérivées directement des pièces
#  RÉELLES de `WastelandLayout.data()` (jamais de `WastelandMarkers`, voir
#  en-tête). PP1 Hotel/PP2 Banque : point d'étage près des fenêtres sud
#  (x=-21/21, milieu du bâtiment x[-26,-16]/[16,26]), à l'écart de la trémie
#  d'escalier (côté nord, stair_side "N", palier vers z=-24). PP3 SaloonW/PP4
#  SaloonE : centre de la dalle `BalconW`/`BalconE` (x[-8,-6]/[6,8],
#  z[-9,-1]), la galerie qui donne sur la place. PP5 Wagon : centre du
#  bâtiment (rez-de-chaussée, `floors=1`, pas d'étage) — c'est aussi le
#  centre de la zone Hardpoint P1.
# ======================================================================
static func _pp_positions() -> Dictionary:
	return {
		"PP1": Vector3(-21.0, _ETAGE_Y, -19.8),
		"PP2": Vector3(21.0, _ETAGE_Y, -19.8),
		"PP3": Vector3(-7.0, _ETAGE_Y, -5.0),
		"PP4": Vector3(7.0, _ETAGE_Y, -5.0),
		"PP5": Vector3(0.0, _GROUND_Y, -1.0),
	}


# ======================================================================
#  Lanes (§5) — 3 polylignes, west -> east, reliant les deux cours de spawn
#  d'équipe (`WastelandLayout.data()["spawns"]`, x=∓41). Chaque point
#  individuel est un point de navmesh valide (sonde `NavigationServer3D`) ;
#  la connexité ENTRE deux points consécutifs n'est PAS le contrat de cette
#  clé (un bot y navigue par pathfinding réel, `NavigationAgent3D`, qui
#  contourne les obstacles seul — seuls `nav_links` ont besoin d'un
#  franchissement simulé bout en bout, voir plus bas).
# ======================================================================
static func _lane_grand_rue() -> Array:
	return [
		Vector3(-41.0, _GROUND_Y, -8.0),   # spawn bleu (spawns[0][0])
		Vector3(-38.0, _GROUND_Y, -20.0),  # devant Forge/Hotel (segment ouest)
		Vector3(-24.0, _GROUND_Y, -17.0),  # sud de l'Hotel
		Vector3(-11.0, _GROUND_Y, -18.0),  # sud du Magasin ouest
		Vector3(-5.5, _GROUND_Y, -13.5),   # bouche ouest (SaloonW <-> Diligence)
		Vector3(0.0, _GROUND_Y, -9.0),     # devant la place, nord du Wagon
		Vector3(5.5, _GROUND_Y, -13.5),    # bouche est
		Vector3(11.0, _GROUND_Y, -18.0),   # sud du Magasin est
		Vector3(24.0, _GROUND_Y, -17.0),   # sud de la Banque
		Vector3(38.0, _GROUND_Y, -20.0),   # devant Forge/Banque (segment est)
		Vector3(41.0, _GROUND_Y, -8.0),    # spawn rouge (spawns[1][0])
	]


static func _lane_interieurs() -> Array:
	return [
		Vector3(-41.0, _GROUND_Y, -8.0),  # spawn bleu
		Vector3(-33.0, _GROUND_Y, -5.0),  # Echoppes ouest, porte O
		Vector3(-22.0, _GROUND_Y, -2.0),  # Echoppes ouest, salle est / sortie
		Vector3(-14.0, _GROUND_Y, -6.0),  # SaloonW, entrée O
		Vector3(-9.0, _GROUND_Y, 0.0),    # SaloonW, porte de place
		Vector3(0.0, _GROUND_Y, -1.0),    # Place, devant le Wagon
		Vector3(9.0, _GROUND_Y, 0.0),     # SaloonE, porte de place
		Vector3(14.0, _GROUND_Y, -6.0),   # SaloonE, entrée E
		Vector3(22.0, _GROUND_Y, -2.0),   # Echoppes est, salle ouest
		Vector3(33.0, _GROUND_Y, -5.0),   # Echoppes est, porte O
		Vector3(41.0, _GROUND_Y, -8.0),   # spawn rouge
	]


static func _lane_canyon() -> Array:
	return [
		Vector3(-41.0, _GROUND_Y, -8.0),   # spawn bleu
		Vector3(-37.0, _CANYON_Y, 14.7),   # après RampeCanyonW1
		Vector3(-25.0, _CANYON_Y, 18.0),   # contournement RocherN1W (sud)
		# BUG-31 : recalé depuis Vector3(-15.0, _CANYON_Y, 14.7) — LD-43 a
		# élargi RampeCanyonW2 de 2 à 4 m (wasteland.gd), la rampe couvre
		# désormais ce point (elle déborde jusqu'à z=15) : la navmesh y suit
		# la pente de la rampe (dessus interpolé ~y=-1,08 à cet endroit) et
		# non plus le sol plat du canyon (_CANYON_Y=-1,5), d'où l'écart de
		# 0,88 m mesuré. Sonde réelle (NavigationServer3D.map_get_closest_
		# point) : (-15.0, -1.5, 14.7) -> (-14.75, -0.6888, 14.6878).
		Vector3(-14.75, -0.69, 14.7),      # RampeCanyonW2 / Ruelle ouest
		Vector3(-8.5, _CANYON_Y, 14.0),    # contournement RocherS2W (nord)
		Vector3(0.0, _CANYON_Y, 17.0),     # le Gué, centre
		Vector3(8.5, _CANYON_Y, 14.0),     # contournement RocherS2E (nord)
		Vector3(15.0, _CANYON_Y, 17.0),    # le Gué, zone Hardpoint P3
		Vector3(25.0, _CANYON_Y, 18.0),    # contournement RocherN1E (sud)
		Vector3(37.0, _CANYON_Y, 14.7),    # avant RampeCanyonE1
		Vector3(41.0, _GROUND_Y, -8.0),    # spawn rouge
	]


static func _lanes() -> Dictionary:
	return {
		"grand_rue": _lane_grand_rue(),
		"interieurs": _lane_interieurs(),
		"canyon": _lane_canyon(),
	}


# ======================================================================
#  Hotspots (12 : 3 par lane + PP2/PP3/PP4, jamais redéfinis — mêmes valeurs
#  que `_pp_positions()`) — cibles de patrouille TDM. Aucun à <= 10 m d'un
#  spawn d'équipe (x=∓41), marge de bon sens (> 3 m) envers les 24
#  `tdm_spawns` neutres de `WastelandLayout._tdm_spawns()`.
# ======================================================================
static func _hotspots() -> Array:
	var out: Array = [
		{"pos": Vector3(-24.0, _GROUND_Y, -17.0), "lane": "grand_rue", "weight": 0.6, "callout": "Magasin Ouest"},
		{"pos": Vector3(5.5, _GROUND_Y, -13.5), "lane": "grand_rue", "weight": 0.7, "callout": "Bouche Est"},
		{"pos": Vector3(24.0, _GROUND_Y, -17.0), "lane": "grand_rue", "weight": 0.6, "callout": "Banque Sud"},
		{"pos": Vector3(-22.0, _GROUND_Y, -2.0), "lane": "interieurs", "weight": 0.6, "callout": "Echoppes Ouest"},
		{"pos": Vector3(0.0, _GROUND_Y, -1.0), "lane": "interieurs", "weight": 0.8, "callout": "Place"},
		{"pos": Vector3(22.0, _GROUND_Y, -2.0), "lane": "interieurs", "weight": 0.6, "callout": "Echoppes Est"},
		{"pos": Vector3(-25.0, _CANYON_Y, 18.0), "lane": "canyon", "weight": 0.5, "callout": "Canyon Ouest"},
		{"pos": Vector3(0.0, _CANYON_Y, 17.0), "lane": "canyon", "weight": 0.6, "callout": "Gue Centre"},
		{"pos": Vector3(25.0, _CANYON_Y, 18.0), "lane": "canyon", "weight": 0.5, "callout": "Canyon Est"},
	]
	var pp := _pp_positions()
	out.append({"pos": pp["PP2"], "lane": "grand_rue", "weight": 0.85, "callout": "Banque"})
	out.append({"pos": pp["PP3"], "lane": "interieurs", "weight": 0.9, "callout": "Galerie Ouest"})
	out.append({"pos": pp["PP4"], "lane": "interieurs", "weight": 0.9, "callout": "Galerie Est"})
	return out


# ======================================================================
#  Entrées par zone Hardpoint (P1 Wagon / P2 Magasin ouest / P3 Gué, même
#  ordre que `WastelandLayout.data()["hardpoints"]`, LD-40) — routes
#  d'approche RÉELLES (portes du Wagon/Magasin ouest, abords du Gué), jamais
#  un comptage radial de portails (une place ouverte n'en a qu'un seul, voir
#  la discipline `WastelandMarkers._hp_entries()` v3, reprise ici en local).
#  Consommées à la fois par `_hp_hold_points().covers` et `_bk_hp_holds().watch`.
# ======================================================================
static func _hp_zone_entries() -> Dictionary:
	return {
		"P1": [
			Vector3(-6.0, _GROUND_Y, -1.0),  # porte ouest du Wagon
			Vector3(6.0, _GROUND_Y, -1.0),   # porte est du Wagon
			# BUG-34 : recalé depuis Vector3(-3.0, _GROUND_Y, 0.5) — la vague
			# toits bas a ajouté un débord de toit au-dessus du seuil sud-ouest
			# du Wagon, qui pousse la navmesh praticable vers le sud à cet
			# endroit (elle ne suit plus z=0.5 mais recule jusqu'à z=-0.12),
			# d'où l'écart de 0,62 m mesuré. Sonde réelle (NavigationServer3D.
			# map_get_closest_point) : (-3.0, 0.5, 0.5) -> (-2.98, 0.5, -0.12).
			Vector3(-2.98, _GROUND_Y, -0.12),  # porte sud-ouest du Wagon
			Vector3(2.98, _GROUND_Y, -0.12),   # porte sud-est du Wagon (miroir)
		],
		"P2": [
			Vector3(-11.5, _GROUND_Y, -19.0),  # porte sud-ouest du Magasin
			Vector3(-5.5, _GROUND_Y, -19.0),   # porte sud-est du Magasin
			Vector3(-13.0, _GROUND_Y, -21.0),  # porte ouest (Passage)
		],
		"P3": [
			Vector3(12.0, _CANYON_Y, 17.0),   # canyon ouest (bord de zone)
			Vector3(18.0, _CANYON_Y, 17.0),   # canyon est (bord de zone)
			Vector3(14.7, -0.6, 13.5),        # rampe nord (RampeCanyonE2, mi-pente)
			Vector3(19.0, _GROUND_Y, 8.6),    # chute depuis l'arrière-cour (quai)
		],
	}


# ======================================================================
#  hp_hold_points (5 points par zone, {pos, facing, stance, covers}) —
#  `covers` indexe `_hp_zone_entries()[zone]` (même ordre). `stance` :
#  "crouch" contre un couvert bas, "stand" en recul à vue dégagée. Chaque
#  `pos` est choisi à <= 2 m d'une pièce RÉELLE qui bloque la vue (murs du
#  Wagon/du Magasin ouest, `Kit.piece_blocks_sight`) POUR P1/P2 — P3 (le Gué,
#  bord de canyon, §12.4 « pas au fond ») est une zone délibérément
#  DÉCOUVERTE par construction (doc §10, risque connu « HP P3 en fosse... à
#  surveiller » : la plus proche pièce qui bloque la vue est le chicane de
#  rochers/le quai de l'arrière-cour, plusieurs mètres plus loin) : la marge
#  de couverture y est donc plus large (voir `HOLD_POINT_COVER_MAX` du test).
# ======================================================================
static func _hp_hold_points() -> Array:
	var out: Array = []
	# --- Zone P1, Wagon (mur ouest/est à x=∓6, mur sud à z=0.5). -----------
	# BOT-30 (revue LD-42) : tenue à 1,5 m à l'INTÉRIEUR du mur (pas à
	# l'extérieur comme avant) — juste derrière le seuil de porte, DANS la
	# boîte de capture Hardpoint RÉELLE (`_REAL_HP_HALF_SIZE.x` = 5 m depuis
	# le centre x=0, cf. test_bot_goals_hardpoint.gd) ; une tenue à l'extérieur
	# du mur (x=∓7,5) ne peut PAS rentrer dans cette boîte (le mur est déjà à
	# 6 m du centre, hors de la demi-largeur de 5 m).
	out.append({"zone": "P1", "pos": Vector3(-4.5, _GROUND_Y, -1.0), "facing": Vector3(-1, 0, 0), "stance": "crouch", "covers": [0]})
	out.append({"zone": "P1", "pos": Vector3(4.5, _GROUND_Y, -1.0), "facing": Vector3(1, 0, 0), "stance": "crouch", "covers": [1]})
	out.append({"zone": "P1", "pos": Vector3(-4.0, _GROUND_Y, 2.0), "facing": Vector3(0, 0, -1), "stance": "crouch", "covers": [2]})
	out.append({"zone": "P1", "pos": Vector3(4.0, _GROUND_Y, 2.0), "facing": Vector3(0, 0, -1), "stance": "crouch", "covers": [3]})
	out.append({"zone": "P1", "pos": Vector3(0.0, _GROUND_Y, -4.4), "facing": Vector3(0, 0, 1), "stance": "stand", "covers": [0, 1]})

	# --- Zone P2, Magasin ouest (murs sud à z=-19, mur ouest à x=-13). -----
	out.append({"zone": "P2", "pos": Vector3(-12.0, _GROUND_Y, -17.2), "facing": Vector3(0, 0, -1), "stance": "crouch", "covers": [0]})
	# BOT-30 (revue LD-42) : z ramené de -16,9 à -17,5 — l'ancienne valeur
	# débordait de 0,1 m la boîte de capture Hardpoint RÉELLE sur l'axe Z
	# (centre P2 z=-22, demi-profondeur 5 m -> plancher z<=-17,0).
	out.append({"zone": "P2", "pos": Vector3(-5.5, _GROUND_Y, -17.5), "facing": Vector3(0, 0, -1), "stance": "crouch", "covers": [1]})
	out.append({"zone": "P2", "pos": Vector3(-14.9, _GROUND_Y, -21.0), "facing": Vector3(1, 0, 0), "stance": "crouch", "covers": [2]})
	out.append({"zone": "P2", "pos": Vector3(-8.5, _GROUND_Y, -23.5), "facing": Vector3(0, 0, 1), "stance": "stand", "covers": [0, 1]})
	out.append({"zone": "P2", "pos": Vector3(-14.9, _GROUND_Y, -24.0), "facing": Vector3(1, 0, 0), "stance": "stand", "covers": [2]})

	# --- Zone P3, Gué (bord du canyon, découvert par construction). -------
	out.append({"zone": "P3", "pos": Vector3(12.0, _CANYON_Y, 17.0), "facing": Vector3(1, 0, 0), "stance": "stand", "covers": [0]})
	out.append({"zone": "P3", "pos": Vector3(18.0, _CANYON_Y, 17.0), "facing": Vector3(-1, 0, 0), "stance": "stand", "covers": [1]})
	out.append({"zone": "P3", "pos": Vector3(15.0, _CANYON_Y, 14.5), "facing": Vector3(0, 0, 1), "stance": "crouch", "covers": [2]})
	out.append({"zone": "P3", "pos": Vector3(16.0, _CANYON_Y, 15.0), "facing": Vector3(0.51, 0, -0.86), "stance": "crouch", "covers": [3]})
	out.append({"zone": "P3", "pos": Vector3(15.0, _CANYON_Y, 18.5), "facing": Vector3(0, 0, 1), "stance": "crouch", "covers": [1]})
	return out


# ======================================================================
#  nav_links (6) — sauts/chutes hors de portée du bake automatique. 2 sauts
#  de galerie (bord ouvert, garde-corps bas seulement, jamais de mur plein en
#  travers) et 4 chutes de parapet (fence de 1,1 m, §6 « se franchit d'un
#  saut », dénivelé 2 m « sous le seuil d'étourdissement ») : sens unique
#  (`bidirectional: false`), on ne remonte pas une chute par le même chemin.
# ======================================================================
static func _nav_links() -> Array:
	var pp := _pp_positions()
	return [
		{"from": pp["PP3"], "to": Vector3(-7.0, _GROUND_Y, -3.0), "bidirectional": false},   # saut Galerie SaloonW -> place
		{"from": pp["PP4"], "to": Vector3(7.0, _GROUND_Y, -3.0), "bidirectional": false},    # saut Galerie SaloonE -> place
		{"from": Vector3(-30.0, _GROUND_Y, 11.5), "to": Vector3(-30.0, _CANYON_Y, 13.0), "bidirectional": false},  # chute parapet -> canyon (ouest, loin)
		{"from": Vector3(-8.0, _GROUND_Y, 11.5), "to": Vector3(-8.0, _CANYON_Y, 13.0), "bidirectional": false},    # chute parapet -> canyon (ouest, Ruelle)
		{"from": Vector3(8.0, _GROUND_Y, 11.5), "to": Vector3(8.0, _CANYON_Y, 13.0), "bidirectional": false},      # chute parapet -> canyon (est, Ruelle)
		{"from": Vector3(30.0, _GROUND_Y, 11.5), "to": Vector3(30.0, _CANYON_Y, 13.0), "bidirectional": false},    # chute parapet -> canyon (est, loin)
	]


# ======================================================================
#  danger_spans (4 <= 6) — tronçons à forte exposition, extrémités reprises
#  des lanes/points déjà réels ci-dessus.
# ======================================================================
static func _danger_spans() -> Array:
	return [
		{"a": Vector3(-38.0, _GROUND_Y, -20.0), "b": Vector3(-11.0, _GROUND_Y, -17.0), "reason": "Grand-Rue segment ouest, ligne longue"},
		{"a": Vector3(11.0, _GROUND_Y, -17.0), "b": Vector3(38.0, _GROUND_Y, -20.0), "reason": "Grand-Rue segment est, ligne longue"},
		{"a": Vector3(-5.5, _GROUND_Y, -13.5), "b": Vector3(5.5, _GROUND_Y, -13.5), "reason": "Bouches de la place, exposees au Poste"},
		{"a": Vector3(-8.5, _CANYON_Y, 14.0), "b": Vector3(8.5, _CANYON_Y, 14.0), "reason": "Gue central, vue degagee nord-sud"},
	]


# ======================================================================
#  bot_knowledge (BOT-22B) — clé consommée par `BotMapKnowledge.gd` (schéma
#  documenté en tête de ce fichier-là) : zones/couloirs/angles/perchoirs/
#  couvertures/tenues Hardpoint, calés sur la navmesh v4 RÉELLE.
# ======================================================================

## >= 14 zones AABB nommées — dérivées des bâtiments RÉELS de
## `WastelandLayout.data()["pieces"]` (marge 0,5-1 m). Déclarées dans un
## ordre qui donne la priorité aux bâtiments les plus petits/spécifiques sur
## les zones englobantes (Wagon avant PlaceGare) : `area_of` renvoie la
## PREMIÈRE zone trouvée, les chevauchements de marge entre boîtes ne sont
## pas un défaut de ce schéma (aucun test n'exige la non-intersection).
static func _bk_zones() -> Array:
	return [
		{"name": "ForgeW", "min": Vector3(-37.0, -0.5, -26.0), "max": Vector3(-28.0, 4.1, -14.0)},
		{"name": "Hotel", "min": Vector3(-27.0, -0.5, -26.0), "max": Vector3(-15.0, 7.0, -18.0)},
		{"name": "MagasinW", "min": Vector3(-14.0, -0.5, -26.0), "max": Vector3(-3.0, 4.1, -18.0)},
		{"name": "EchoppesW", "min": Vector3(-35.0, -0.5, -10.0), "max": Vector3(-19.0, 4.1, 6.0)},
		{"name": "SaloonW", "min": Vector3(-17.0, -0.5, -12.0), "max": Vector3(-7.0, 7.0, 6.0)},
		{"name": "Wagon", "min": Vector3(-7.0, -0.5, -3.5), "max": Vector3(7.0, 4.0, 1.5)},
		{"name": "Poste", "min": Vector3(-5.0, -0.5, -26.0), "max": Vector3(5.0, 7.0, -15.0)},
		{"name": "ForgeE", "min": Vector3(28.0, -0.5, -26.0), "max": Vector3(37.0, 4.1, -14.0)},
		{"name": "Banque", "min": Vector3(15.0, -0.5, -26.0), "max": Vector3(27.0, 7.0, -18.0)},
		{"name": "MagasinE", "min": Vector3(3.0, -0.5, -26.0), "max": Vector3(14.0, 4.1, -18.0)},
		{"name": "EchoppesE", "min": Vector3(19.0, -0.5, -10.0), "max": Vector3(35.0, 4.1, 6.0)},
		{"name": "SaloonE", "min": Vector3(7.0, -0.5, -12.0), "max": Vector3(17.0, 7.0, 6.0)},
		{"name": "PlaceGare", "min": Vector3(-8.0, -0.5, -10.0), "max": Vector3(8.0, 4.1, 6.0)},
		{"name": "RuelleW", "min": Vector3(-21.0, -0.5, -10.0), "max": Vector3(-15.0, 4.1, 6.0)},
		{"name": "RuelleE", "min": Vector3(15.0, -0.5, -10.0), "max": Vector3(21.0, 4.1, 6.0)},
		{"name": "Canyon", "min": Vector3(-44.0, -2.5, 11.0), "max": Vector3(44.0, 1.5, 21.0)},
	]


## Couloirs N (Grand-Rue)/C (Intérieurs)/S (Canyon) — mêmes polylignes que
## `_lanes()` (le schéma de `BotMapKnowledge` impose ces 3 lettres), jamais
## dupliquées à la main : une seule calibration à vérifier sur la navmesh.
static func _bk_corridors() -> Dictionary:
	return {
		"N": _lane_grand_rue(),
		"C": _lane_interieurs(),
		"S": _lane_canyon(),
	}


## >= 20 angles à pré-viser — portes RÉELLES des bâtiments (Wagon, Magasin
## ouest/est, Hotel/Banque rez-de-chaussée, Saloon ouest/est, Echoppes),
## `dir` = direction perpendiculaire au mur (vers le couloir dégagé).
static func _bk_angles() -> Array:
	return [
		# --- Wagon (zone P1), 4 portes. ---------------------------------------
		{"pos": Vector3(-6.0, _GROUND_Y, -1.0), "dir": Vector3(-1, 0, 0)},
		{"pos": Vector3(6.0, _GROUND_Y, -1.0), "dir": Vector3(1, 0, 0)},
		# BUG-34 : recalé, même sonde que _hp_zone_entries()["P1"] ci-dessus
		# (débord de toit bas au-dessus du seuil sud du Wagon).
		{"pos": Vector3(-2.98, _GROUND_Y, -0.12), "dir": Vector3(0, 0, 1)},
		{"pos": Vector3(2.98, _GROUND_Y, -0.12), "dir": Vector3(0, 0, 1)},
		# --- Magasin ouest (zone P2), 3 portes. --------------------------------
		{"pos": Vector3(-11.5, _GROUND_Y, -19.0), "dir": Vector3(0, 0, -1)},
		{"pos": Vector3(-5.5, _GROUND_Y, -19.0), "dir": Vector3(0, 0, -1)},
		{"pos": Vector3(-13.0, _GROUND_Y, -21.0), "dir": Vector3(-1, 0, 0)},
		# --- Magasin est (mirroir), 3 portes. -----------------------------------
		{"pos": Vector3(11.5, _GROUND_Y, -19.0), "dir": Vector3(0, 0, -1)},
		{"pos": Vector3(5.5, _GROUND_Y, -19.0), "dir": Vector3(0, 0, -1)},
		{"pos": Vector3(13.0, _GROUND_Y, -21.0), "dir": Vector3(1, 0, 0)},
		# --- Hotel, 2 portes sud. -------------------------------------------------
		{"pos": Vector3(-23.5, _GROUND_Y, -19.0), "dir": Vector3(0, 0, -1)},
		{"pos": Vector3(-18.5, _GROUND_Y, -19.0), "dir": Vector3(0, 0, -1)},
		# --- Banque (mirroir), 2 portes sud. --------------------------------------
		{"pos": Vector3(23.5, _GROUND_Y, -19.0), "dir": Vector3(0, 0, -1)},
		{"pos": Vector3(18.5, _GROUND_Y, -19.0), "dir": Vector3(0, 0, -1)},
		# --- SaloonW, 3 portes (N, O, porte de place E). --------------------------
		{"pos": Vector3(-12.0, _GROUND_Y, -11.0), "dir": Vector3(0, 0, -1)},
		{"pos": Vector3(-16.0, _GROUND_Y, -6.0), "dir": Vector3(-1, 0, 0)},
		{"pos": Vector3(-8.0, _GROUND_Y, 1.5), "dir": Vector3(1, 0, 0)},
		# --- SaloonE (mirroir), 3 portes. ------------------------------------------
		{"pos": Vector3(12.0, _GROUND_Y, -11.0), "dir": Vector3(0, 0, -1)},
		{"pos": Vector3(16.0, _GROUND_Y, -6.0), "dir": Vector3(1, 0, 0)},
		{"pos": Vector3(8.0, _GROUND_Y, 1.5), "dir": Vector3(-1, 0, 0)},
		# --- Echoppes ouest, 2 portes (nord, est). ---------------------------------
		{"pos": Vector3(-31.0, _GROUND_Y, -9.0), "dir": Vector3(0, 0, -1)},
		{"pos": Vector3(-20.0, _GROUND_Y, -2.0), "dir": Vector3(1, 0, 0)},
	]


## >= 4 perchoirs — PP1-PP5, `watch` documente la vue depuis chacun.
static func _bk_perches() -> Array:
	var pp := _pp_positions()
	return [
		{"name": "PP1", "pos": pp["PP1"], "watch": "Grand-Rue ouest et bouche de place"},
		{"name": "PP2", "pos": pp["PP2"], "watch": "Grand-Rue est et bouche de place"},
		{"name": "PP3", "pos": pp["PP3"], "watch": "place et bouche de la Grand-Rue est"},
		{"name": "PP4", "pos": pp["PP4"], "watch": "place et bouche de la Grand-Rue ouest"},
		{"name": "PP5", "pos": pp["PP5"], "watch": "les 4 ouvertures du Wagon et la place"},
	]


## >= 10 couvertures — position de TENUE (jamais le centre du couvert, qui
## est dans le solide) à côté d'un couvert RÉEL, `dir` = direction visée
## depuis cette tenue (le couvert est DERRIÈRE le bot), `height` = hauteur
## réelle de la pièce (`size.y`).
static func _bk_covers() -> Array:
	return [
		{"pos": Vector3(-30.0, _GROUND_Y, -9.5), "dir": Vector3(0, 0, 1), "height": 1.1},   # AbreuvoirW1, flanc sud
		{"pos": Vector3(-11.0, _GROUND_Y, -15.5), "dir": Vector3(0, 0, 1), "height": 1.1},  # AbreuvoirW2, flanc sud
		{"pos": Vector3(-19.25, _GROUND_Y, -13.5), "dir": Vector3(0, 0, 1), "height": 1.1}, # CaissesW, flanc sud
		{"pos": Vector3(-30.0, _GROUND_Y, 2.0), "dir": Vector3(0, 0, 1), "height": 1.1},    # ComptoirW, flanc sud
		{"pos": Vector3(-6.5, _GROUND_Y, 6.0), "dir": Vector3(0, 0, 1), "height": 2.0},     # TonneauxW, flanc sud
		{"pos": Vector3(-6.0, _GROUND_Y, 1.5), "dir": Vector3(-1, 0, 0), "height": 2.0},    # TraversesW, flanc ouest
		{"pos": Vector3(-5.0, _GROUND_Y, -5.0), "dir": Vector3(0, 0, 1), "height": 2.0},    # PileTraversesNW, flanc sud
		{"pos": Vector3(-19.0, _GROUND_Y, 8.0), "dir": Vector3(0, 0, -1), "height": 2.0},   # CaissesQuaiW, flanc nord
		{"pos": Vector3(-24.5, _GROUND_Y, -8.5), "dir": Vector3(0, 0, 1), "height": 2.2},   # CharretteW, flanc sud
		{"pos": Vector3(-33.25, _GROUND_Y, -2.0), "dir": Vector3(1, 0, 0), "height": 2.2},  # CaisseFUEL, flanc est
		{"pos": Vector3(6.5, _GROUND_Y, 6.0), "dir": Vector3(0, 0, 1), "height": 2.0},      # TonneauxE (mirroir), flanc sud
		{"pos": Vector3(6.0, _GROUND_Y, 1.5), "dir": Vector3(1, 0, 0), "height": 2.0},      # TraversesE (mirroir), flanc est
	]


## Une entrée par zone Hardpoint RÉELLE (P1/P2/P3) — `hold` = 2 positions de
## tenue déjà réelles de `_hp_hold_points()` (stance "crouch", DANS la zone) ;
## `watch` = `_hp_zone_entries()[zone]`.
static func _bk_hp_holds() -> Array:
	var entries := _hp_zone_entries()
	return [
		{"zone": "P1", "hold": [Vector3(-4.5, _GROUND_Y, -1.0), Vector3(4.5, _GROUND_Y, -1.0)], "watch": (entries["P1"] as Array).duplicate()},
		{"zone": "P2", "hold": [Vector3(-12.0, _GROUND_Y, -17.2), Vector3(-5.5, _GROUND_Y, -17.5)], "watch": (entries["P2"] as Array).duplicate()},
		{"zone": "P3", "hold": [Vector3(12.0, _CANYON_Y, 17.0), Vector3(18.0, _CANYON_Y, 17.0)], "watch": (entries["P3"] as Array).duplicate()},
	]


static func _bot_knowledge() -> Dictionary:
	return {
		"zones": _bk_zones(),
		"corridors": _bk_corridors(),
		"angles": _bk_angles(),
		"perches": _bk_perches(),
		"covers": _bk_covers(),
		"hp_holds": _bk_hp_holds(),
	}


static func data() -> Dictionary:
	return {
		"lanes": _lanes(),
		"hotspots": _hotspots(),
		"hp_hold_points": _hp_hold_points(),
		"nav_links": _nav_links(),
		"danger_spans": _danger_spans(),
		"bot_knowledge": _bot_knowledge(),
	}
