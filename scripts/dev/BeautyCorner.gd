## BeautyCorner.gd (dev-only, scripts/dev/ -- excluded from exports)
## ART-82 (docs/art/WASTELAND_ART_RESET.md "Coin beauté d'abord") : ~30 m de
## Grand-Rue amenés au niveau visuel FINAL, cadrés comme la moitié basse de
## .orchestrator/refs/wasteland_hero.png -- scène de dev AUTONOME (n'importe
## jamais scripts/levels/maps/layouts/wasteland.gd, ne touche à aucune vraie
## map), bâtie avec les mêmes briques qu'un vrai niveau :
##   - le LOOK de wasteland_look.gd (WastelandLook.palette(), lu seul) via
##     Kit.gd (sol peint, ornières, porches/escaliers "kit v2") ;
##   - les 4 bâtiments peints d'ART-83 installés par CE contrat + les 7
##     repères Tripo d'ART-80 (assets/models/props/wasteland/tripo/*.glb),
##     repeints par le même flux que test_cartoon_painted_props.gd::
##     test_end_to_end_from_a_standard_material_surface (extraction de la
##     texture importée -> Cartoon.painted_texture_prop) ;
##   - la bibliothèque de props générique (PropKit.gd, lu seul) pour poteaux,
##     câbles, caisses, fûts, planches.
## `MatchConfig.map_id = "wasteland"` avant tout WorldEnvironment/
## DirectionalLight3D : LevelLook.gd (autoload "Look", ou simulé par
## tools/review/beauty_shot.gd comme tools/screenshot.gd/tools/map_shots.gd
## le font déjà) restyle alors ciel/soleil/brouillard EXACTEMENT comme la
## vraie carte -- rien de tout ça n'est codé ici.
##
## Collisions (contrat : "boîtes simples, jamais le maillage IA") : une seule
## StaticBody3D/BoxShape3D par bâtiment/repère, dimensionnée sur l'AABB réelle
## de son maillage importé (jamais de cote devinée à la main).
##
## ART-88 (« Coin beauté v2 ») : retour utilisateur du 2026-09-25 -- « le
## terrain, tout ce qu'il y a autour est encore nul, on dirait uniquement des
## modèles 3D positionnés, il faut faire le reste ». Diagnostic (capture
## reports/beauty/beauty_corner.png d'ART-85) : le sol de `_build_ground` (34 m
## de rue) s'arrête net à `x=34`/`z=±7`, alors que les repères de fond
## (`_LANDMARKS`) sont posés jusqu'à `x=44`/`z=7.5` -- ILS FLOTTENT AU-DESSUS
## DU VIDE au-delà du bord du maillage, et l'horizon au-delà n'affiche que le
## dégradé plat du ciel (`ink_sky.gdshader`), jamais de sol peint : exactement
## le "on dirait des modèles 3D posés" du retour. `_build_backdrop_ground`
## (sol GroundBuilder identique en nature -- même shader/mêmes matières
## peintes ART-85 -- mais à grille plus grossière, contrat "sol ART-85
## partout") comble ce vide jusqu'à `x=182`/`z=±45`, piste comprise (elle
## continue jusqu'à l'horizon plutôt que de s'arrêter à `x=34`). Par-dessus :
## `_build_midground`/`_build_skyline` posent des bâtiments (Tripo réutilisés
## + bibliothèque PropKit générique, jamais de nouvel asset) en plans de plus
## en plus éloignés pour qu'aucun cadrage n'affiche plus d'horizon désertique
## vide (densité cible : celle de wasteland_hero.png), et `_build_dressing`
## est densifié (clôtures, grappes caisses/fûts/pneus à CHAQUE façade,
## épaves) pour la même raison au sol.
extends Node3D

const _TRIPO := "res://assets/models/props/wasteland/tripo/"
const _PROP := "res://assets/models/props/wasteland/"

## Empreinte de la scène (contrat ART-82 : "30 m de rue", "piste de terre de
## 8 m"). La piste occupe l'axe +X (même convention que la pose caméra
## "grand_rue" de tools/map_shots.gd::_wasteland_poses, direction Vector3(1,0,0)
## depuis Vector3(0,0,0)) -- même azimut de soleil déjà calibré pour cette
## orientation (LevelLook._SUN_AZIMUTH_DEG_WASTELAND = 70°, "aucune équipe ne
## sort de spawn à contre-jour"), donc le même rasant chaud à contre-jour
## partiel que le contrat demande ("soleil chaud rasant arrière-gauche") sort
## du même calibrage, sans rien recoder ici.
const STREET_LENGTH := 34.0
const TRACK_WIDTH := 8.0
const TRACK_HALF := TRACK_WIDTH * 0.5

var _batcher: Kit.GeoBatcher


func _ready() -> void:
	MatchConfig.map_id = "wasteland"
	add_child(WorldEnvironment.new())
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	add_child(sun)

	# Sol AVANT tout le reste (ART-85) : `GroundBuilder` lit `MatchConfig.
	# map_id` (déjà "wasteland" ci-dessus) pour sa palette, et les jupes de
	# terre des bâtiments n'ont besoin que de leurs POSITIONS (`_BUILDINGS`,
	# constantes, pas encore instanciées à cet instant -- l'ordre de
	# construction n'a donc pas d'importance ici).
	_build_ground()
	_build_backdrop_ground()

	_batcher = Kit.GeoBatcher.new()
	# "Le look de wasteland_look.gd" (contrat) : source des porches --
	# WastelandLook a un `class_name` global, résolu directement (même
	# convention que TrainingBuilder.gd::TrainingLayout). Le SOL lui-même
	# vient désormais de `GroundBuilder` (ART-85, `_build_ground` plus bas) ;
	# `palette` ne sert plus qu'à `_build_kit_modules`.
	var palette: Dictionary = WastelandLook.palette()
	_build_kit_modules(palette)
	_batcher.flush(self)

	_build_buildings()
	_build_background_landmarks()
	_build_midground()
	_build_skyline()
	_build_dressing()
	_build_camera()


# ============================================================== sol / piste
## Sol procédural (`scripts/levels/ground/GroundBuilder.gd`, ART-85) :
## relief doux + piste de 8 m creusée à deux ornières (±1,4 m de l'axe,
## empreinte réaliste d'un véhicule de gabarit routier) + bourrelets de bord
## + une jupe de terre au pied de CHAQUE bâtiment peint (contrat : « chaque
## bâtiment posé sur une jupe de terre ») -- remplace l'ancienne dalle plate
## + bandes d'ornières peintes en aplat (verdict utilisateur 2026-09-25 :
## « le terrain [...] on dirait des modèles 3D posés »).
##
## Empreinte (`size`/`center`) EXACTEMENT celle de l'ancienne dalle
## (`Vector3(STREET_LENGTH*0.5-2.0, ...)` / `Vector3(STREET_LENGTH+4.0, ...,
## TRACK_WIDTH+6.0)`) : le contrat demande de remplacer le sol « sans
## toucher au reste de la scène » (cadrage caméra, porches, bâtiments
## inchangés).
const _RUT_OFFSET := 1.4
const _RUT_WIDTH := 0.9
const _RUT_DEPTH := 0.05
const _ROAD_DEPTH := 0.15
## Jupe de terre au pied de chaque bâtiment : hauteur modeste -- la
## silhouette du bâtiment ne change pas, seul son pied "plante" dans le sol.
##
## RETOUR VÉRIFICATEUR (ART-85) : à 1,8 (l'ancien rayon), le centre de la
## jupe (au bâtiment, `TRACK_HALF + _PORCH_DEPTH + 0.2` = 1,8 au-delà du bord
## de piste `TRACK_HALF`) retombait EXACTEMENT à 0 au bord de piste --
## `_mound_delta`/`weights_at` : `falloff = 1 - smoothstep(0, radius, dist)`
## s'annule pile à `dist == radius`. 3.0 laisse une influence nette
## (~0,35 de falloff, vérifié par test_ground_builder.gd) juste avant le
## bord de piste plutôt qu'un 0 mathématique pile à la couture visible ---
## MAIS la face avant de la jupe reste de toute façon cachée par le trottoir
## de bois opaque (_build_kit_modules, occupe tout `[TRACK_HALF, TRACK_HALF +
## _PORCH_DEPTH]`, quel que soit le rayon de la jupe) : ce qui rend la jupe
## RÉELLEMENT visible à l'écran, c'est l'ARRIÈRE de chaque bâtiment (rien ne
## l'y recouvre) -- voir `_build_camera`/`_FOOT_CLOSEUP_ARG` pour la capture
## de vérification "gros plan du pied d'un bâtiment" (contrat, captures).
## 3.0 reste modeste : son bord d'influence nulle tombe à
## `TRACK_HALF + _PORCH_DEPTH + 0.2 - 3.0` = `TRACK_HALF - 1.2`, donc encore
## 1,2 m À L'INTÉRIEUR de la piste (côté piste du bord, pas au-delà) sans
## mordre sur les ornières (`_RUT_OFFSET` +/-1,4, largeur 0,9, donc bande
## [0,95, 1,85]) -- juste un dégradé large et doux en bord de piste, jamais
## un second relief au milieu de la chaussée.
const _BUILDING_MOUND_RADIUS := 3.0
const _BUILDING_MOUND_HEIGHT := 0.12

var _ground: Node3D

## ART-88 : `size.y` élargi de `TRACK_WIDTH + 6.0` (14 m, z dans [-7, 7]) à
## `TRACK_WIDTH + 12.0` (20 m, z dans [-10, 10]) -- l'ancienne largeur
## laissait DÉJÀ `wl_fuel_billboard` (`_LANDMARKS`, z=7.5) déborder du
## maillage de 0,5 m (flottant sur le vide, voir le retour utilisateur en
## tête de fichier) ; la nouvelle marge (2,2 m au-delà du bâtiment le plus
## large, z=±5,8 + moitié profondeur) couvre aussi les clôtures de fond de
## `_build_dressing` (z=±9,0) SANS toucher `x`/la piste/les porches (contrat
## ART-85 : "sans toucher au reste de la scène").
func _build_ground() -> void:
	var center := Vector2(STREET_LENGTH * 0.5 - 2.0, 0.0)
	var size := Vector2(STREET_LENGTH + 4.0, TRACK_WIDTH + 12.0)
	var mounds: Array = []
	for entry in _BUILDINGS:
		var pos: Vector3 = entry["pos"]
		mounds.append({"pos": Vector2(pos.x, pos.z), "radius": _BUILDING_MOUND_RADIUS, "height": _BUILDING_MOUND_HEIGHT})
	var spec := {
		"size": size, "center": center, "cell": 0.5,
		"roads": [{
			"points": [Vector2(center.x - size.x * 0.5, 0.0), Vector2(center.x + size.x * 0.5, 0.0)],
			"width": TRACK_WIDTH, "depth": _ROAD_DEPTH,
			"ruts": {"offset": _RUT_OFFSET, "width": _RUT_WIDTH, "depth": _RUT_DEPTH},
		}],
		"mounds": mounds,
		"noise_amp": 0.03,
		"seed": 85,
	}
	_ground = GroundBuilder.build(spec)
	add_child(_ground)
	# Navmesh (contrat : "navmesh bakée sur le sol") -- synchrone, même
	# instant que `BOT_NAV.ensure_baked(self)` dans GameWorld.gd (le nœud
	# est déjà dans l'arbre : `self` l'est, `add_child` ci-dessus y place
	# `_ground` immédiatement).
	GroundBuilder.bake_navmesh(_ground)


## ART-88 : sol de fond, MÊME module/matières peintes que `_build_ground`
## (contrat "sol ART-85 partout") mais grille grossière (`cell` 1,5 m contre
## 0,5 m -- plan éloigné, jamais vu de près, voir `_build_camera` : la caméra
## de rue ne s'approche jamais de `x > 34`) pour un coût de triangles modeste
## (≈ 99×60 cases). Comble EXACTEMENT le vide diagnostiqué en tête de
## fichier : démarre à `x = 34` (bord droit du sol de `_build_ground`, AUCUN
## recouvrement -- deux grilles à `cell` différent qui se chevauchraient
## produiraient un bruit/relief différent au même point du monde, donc une
## couture visible ; `height_at`/`weights_at` sont des fonctions PURES du
## point (x, z) seul, un simple bord-à-bord suffit à rester continu en sable
## plat des deux côtés) jusqu'à `x = 182` / `z = ±45` -- au-delà de CHAQUE
## bâtiment de `_MIDGROUND`/`_SKYLINE` et des repères de `_LANDMARKS` situés
## par-delà `x = 34` (le seul en-deçà, `wl_fuel_billboard` à x=25, reste sur
## le sol de `_build_ground`). La piste continue dedans (mêmes `ruts`) : la
## rue file jusqu'à l'horizon au lieu de s'arrêter net à 34 m, comme la
## référence (wasteland_hero.png, point de fuite visible loin dans le cadre).
const _BACKDROP_X_START := 34.0
const _BACKDROP_X_END := 182.0
const _BACKDROP_Z_HALF := 45.0
const _BACKDROP_MOUND_RADIUS := 4.0
const _BACKDROP_MOUND_HEIGHT := 0.1

func _build_backdrop_ground() -> void:
	var size := Vector2(_BACKDROP_X_END - _BACKDROP_X_START, _BACKDROP_Z_HALF * 2.0)
	var center := Vector2((_BACKDROP_X_START + _BACKDROP_X_END) * 0.5, 0.0)
	var mounds: Array = []
	# Une jupe de terre modeste sous chaque bâtiment de fond (`_LANDMARKS` déjà
	# posés par `_build_background_landmarks`, `_MIDGROUND`/`_SKYLINE` pas
	# encore construits à cet instant -- seules leurs POSITIONS comptent ici,
	# comme `_build_ground`/`_BUILDINGS`) : aucun ne "flotte" plus sur du sable
	# parfaitement plat, même loin de la caméra.
	for entry in _LANDMARKS:
		var pos: Vector3 = entry["pos"]
		if pos.x >= _BACKDROP_X_START:
			mounds.append({"pos": Vector2(pos.x, pos.z), "radius": _BACKDROP_MOUND_RADIUS, "height": _BACKDROP_MOUND_HEIGHT})
	for entry in _MIDGROUND:
		var pos: Vector3 = entry["pos"]
		mounds.append({"pos": Vector2(pos.x, pos.z), "radius": _BACKDROP_MOUND_RADIUS, "height": _BACKDROP_MOUND_HEIGHT})
	for entry in _SKYLINE:
		var pos: Vector3 = entry["pos"]
		mounds.append({"pos": Vector2(pos.x, pos.z), "radius": _BACKDROP_MOUND_RADIUS, "height": _BACKDROP_MOUND_HEIGHT})
	var spec := {
		"size": size, "center": center, "cell": 1.5,
		"roads": [{
			"points": [Vector2(_BACKDROP_X_START, 0.0), Vector2(_BACKDROP_X_END, 0.0)],
			"width": TRACK_WIDTH, "depth": _ROAD_DEPTH,
			"ruts": {"offset": _RUT_OFFSET, "width": _RUT_WIDTH, "depth": _RUT_DEPTH},
		}],
		"mounds": mounds,
		"noise_amp": 0.04,
		"seed": 88,
	}
	var backdrop := GroundBuilder.build(spec)
	add_child(backdrop)
	# Pas de `bake_navmesh` ici : plan de fond jamais foulé (la caméra de rue
	# de `_build_camera` ne s'en approche jamais), scène de dev sans bots --
	# lui bâtir une navmesh coûterait du temps de démarrage pour rien.


# ==================================================== porches / escaliers
## "Modules du kit v2 en raccord" (contrat) : un trottoir de bois surélevé
## (boardwalk) devant chaque rangée de bâtiments, raccordé à la piste par une
## volée de marches `Kit.stairs()` -- même limon plein/contremarche que le
## reste du jeu (Kit.gd §ART-71), jamais des marches "flottantes".
const _PORCH_HEIGHT := 0.35
const _PORCH_DEPTH := 1.6
const _PORCH_STEPS := 3

func _build_kit_modules(palette: Dictionary) -> void:
	var batcher := _batcher
	var wood: Color = Color("9c6a42")
	for side in [-1.0, 1.0]:
		var porch_z: float = side * (TRACK_HALF + _PORCH_DEPTH * 0.5)
		Kit.box(self, batcher, Vector3(STREET_LENGTH * 0.5 - 2.0, _PORCH_HEIGHT * 0.5, porch_z),
			Vector3(STREET_LENGTH, _PORCH_HEIGHT, _PORCH_DEPTH), wood, "Boardwalk", 0.0, false, "wood_planks")
		# Deux volées de marches par rangée (une devant chaque bâtiment),
		# perpendiculaires au trottoir, qui redescendent vers la piste.
		for step_x in [6.0, 16.0]:
			var track_edge_z: float = side * TRACK_HALF
			var porch_edge_z: float = side * (TRACK_HALF + _PORCH_DEPTH)
			Kit.stairs(self, batcher, Vector3(step_x, 0.0, track_edge_z),
				Vector3(step_x, _PORCH_HEIGHT, porch_edge_z), 1.8, _PORCH_STEPS, wood,
				"Steps%d_%s" % [int(step_x), "N" if side < 0 else "S"], "wood_planks")


# ====================================================================== bâtiments
## Les 4 bâtiments Tripo peints installés par ce contrat
## (tools/ai3d/manifests/painted_env.yaml). `rot_y` aligne leur façade sur la
## piste (0°/-90°/90°/180° : les concepts Tripo sortent face à leur propre
## "avant", jamais garanti aligné à la carte -- vérifié/ajusté à l'image,
## comme toute pièce visible de ce dépôt).
## `rot_y` : l'export glTF de `ai_import_painted.py` (conversion Z-up -> Y-up
## standard de l'exporteur Blender) sort chaque concept Tripo face à +Z SANS
## rotation -- vérifié à l'image (0°/180° montrent la façade détaillée avec
## porche/fenêtres, 90°/-90° un flanc nu) : 0° pour les bâtiments côté -Z (la
## rue est devant eux, en +Z), 180° pour ceux côté +Z (la rue est en -Z).
const _BUILDINGS := [
	{"file": "wl_saloon", "pos": Vector3(6.0, 0.0, -TRACK_HALF - _PORCH_DEPTH - 0.2), "rot_y": 0.0},
	{"file": "wl_fuel_store", "pos": Vector3(16.5, 0.0, -TRACK_HALF - _PORCH_DEPTH - 0.2), "rot_y": 0.0},
	{"file": "wl_garage", "pos": Vector3(9.0, 0.0, TRACK_HALF + _PORCH_DEPTH + 0.2), "rot_y": 180.0},
	{"file": "wl_shack", "pos": Vector3(19.0, 0.0, TRACK_HALF + _PORCH_DEPTH + 0.2), "rot_y": 180.0},
]

func _build_buildings() -> void:
	for entry in _BUILDINGS:
		var inst := _load_painted_tripo(_TRIPO + String(entry["file"]) + ".glb")
		if inst == null:
			continue
		inst.position = entry["pos"]
		inst.rotation_degrees.y = entry["rot_y"]
		add_child(inst)
		_add_box_collision_from_aabb(inst, String(entry["file"]))


# =========================================================== repères en fond
## "Château d'eau + derrick + panneau FUEL Tripo peints en fond" (contrat),
## complétés par la grue (déjà le repère central neutre de la vraie carte,
## docs/research/09_wasteland_vertical_slice.md) pour la même densité de
## silhouette que wasteland_hero.png. Positions choisies/vérifiées à l'image
## (`reports/beauty/beauty_corner.png`) pour que les 4 tombent dans le cadre
## de `_build_camera` plutôt que masqués par le saloon au premier plan ou
## hors champ -- le point de fuite centre-gauche du contrat vient, lui, du
## LÉGER virage de visée de la caméra (`_build_camera`), pas de la position
## de ces repères ; le sol/la piste restent bien droits sur l'axe +X.
const _LANDMARKS := [
	{"file": "wl_water_tower", "pos": Vector3(36.0, 0.0, 4.0), "rot_y": 0.0},
	{"file": "wl_oil_derrick", "pos": Vector3(44.0, 0.0, 7.0), "rot_y": 20.0},
	{"file": "wl_fuel_billboard", "pos": Vector3(25.0, 0.0, 7.5), "rot_y": 25.0},
	{"file": "wl_crane_lattice", "pos": Vector3(42.0, 0.0, -2.5), "rot_y": -15.0},
]

func _build_background_landmarks() -> void:
	for entry in _LANDMARKS:
		var inst := _load_painted_tripo(_TRIPO + String(entry["file"]) + ".glb")
		if inst == null:
			continue
		inst.position = entry["pos"]
		inst.rotation_degrees.y = entry["rot_y"]
		add_child(inst)


# ================================================================ plan moyen
## ART-88 : bloc de rue "suivant", entre les 4 bâtiments du premier plan
## (`_BUILDINGS`, x <= 19) et les repères isolés de `_LANDMARKS` (x >= 25) --
## comble le "bloc vide" intermédiaire tout en réutilisant les 3 Tripo
## peints d'ART-83/ART-80 restés inutilisés par ART-82 (`wl_canopy_station`,
## `wl_gas_billboard`, `wl_tank_horizontal` -- présents dans
## `assets/models/props/wasteland/tripo/`, jamais posés avant ce contrat) et
## le saloon/garage déjà posés en premier plan, réinstanciés ici plus loin
## (note du contrat : "bâtiments Tripo réutilisés en plans éloignés"). Même
## chargeur/repaint que `_BUILDINGS` (`_load_painted_tripo`), pas de
## collision (jamais foulé par une caméra de rue, même traitement que
## `_LANDMARKS`).
##
## POSITIONS (x/z) : contrainte découverte à l'image (capture réelle de ce
## contrat, `reports/beauty/beauty_corner.png`) -- `_build_camera` est TRÈS
## proche des 4 bâtiments du premier plan (6-8 m, `_BUILDINGS`), qui
## occupent donc une part énorme du champ (le saloon, à ~7 m, sature déjà
## toute la moitié gauche du cadre) : tout plan éloigné posé à grand |z|
## (loin de l'axe de la rue) tombe DERRIÈRE cette silhouette proche et
## disparaît, invisible à la capture malgré une position "correcte" sur le
## papier. Seul le corridor de la rue elle-même reste dégagé jusqu'à
## l'horizon -- EXACTEMENT le couloir déjà occupé par `_LANDMARKS`
## (z entre -2,5 et 7,5, les 4 repères tombent bien dans le cadre, voir leur
## propre commentaire "vérifiées à l'image"). `_MIDGROUND`/`_SKYLINE`
## reprennent donc ce même couloir (z entre -4 et 8,5) plutôt que de
## s'étaler large, en commençant à x=46 (au-delà du dernier repère,
## `wl_oil_derrick` x=44) pour ne chevaucher aucun des 4.
const _MIDGROUND := [
	{"file": "wl_gas_billboard", "pos": Vector3(46.0, 0.0, -3.5), "rot_y": -10.0},
	{"file": "wl_canopy_station", "pos": Vector3(51.0, 0.0, 8.5), "rot_y": 12.0},
	{"file": "wl_tank_horizontal", "pos": Vector3(56.0, 0.0, -4.0), "rot_y": 0.0},
	{"file": "wl_saloon", "pos": Vector3(61.0, 0.0, 7.5), "rot_y": -15.0},
	{"file": "wl_garage", "pos": Vector3(66.0, 0.0, -3.0), "rot_y": 160.0},
]

func _build_midground() -> void:
	for entry in _MIDGROUND:
		var inst := _load_painted_tripo(_TRIPO + String(entry["file"]) + ".glb")
		if inst == null:
			continue
		inst.position = entry["pos"]
		inst.rotation_degrees.y = entry["rot_y"]
		add_child(inst)


# =================================================== silhouette de ville (fond)
## ART-88, critère d'acceptation "aucun horizon vide dans le cadre" : au-delà
## du plan moyen, une VRAIE silhouette de ville plutôt que 4 repères isolés --
## bâtiments génériques peints de la bibliothèque `PropKit` (jamais vus de
## près, contrat "densité cible : celle de la référence") + deux Tripo déjà
## posés au premier plan réinstanciés très loin (même note "réutilisés en
## plans éloignés" que `_MIDGROUND`). Même couloir dégagé que `_MIDGROUND`
## (voir son commentaire) -- z entre -4 et 8,5, x=[71, 137], à la suite de
## `_MIDGROUND` (dernier x=66) -- posés par-dessus `_build_backdrop_ground`
## (qui les couvre déjà d'une jupe de terre, voir ses `mounds`), sans
## collision (silhouette pure, hors de portée de toute caméra de rue).
## `"kind"` distingue le chargeur : "generic" -> `PropKit.instance` (props/
## manifest.json, tinté `accent`), "tripo" -> `_load_painted_tripo` (dossier
## wasteland/tripo/, jamais tinté, comme `_BUILDINGS`/`_LANDMARKS`).
##
## ART-89 (« 4 grappes de décor Tripo ») : verdict utilisateur/lead du 2026-09-25 -- les
## props PROCÉDURAUX du dressing (épaves sedan_wreck/truck_wreck "en blocs rouges",
## clôture fence_chainlink "panneaux bleus") faisaient jouet. Remplacés/complétés par les 4
## grosses pièces peintes Tripo installées par ce contrat (`DressingKit.gd` §5,
## tools/ai3d/manifests/painted_env.yaml) : `_build_wrecks` (épave), `_build_fences`
## (clôture cassée, rangée sud), `_build_market_and_junk` (étal de marché + bric-à-brac,
## nouveaux). Ces 4 sortes vivent HORS `PropCatalog`/PropKit (chaque instance charge et
## repeint directement sa PROPRE scène, comme `_load_painted_tripo`/`_repaint_painted`
## ci-dessous -- dupliqué dans `DressingKit.gd` à dessein, voir son en-tête §5), donc jamais
## tintées `accent` : leur teinte vient de `DressingKit.tripo_variants` (légère variation
## par instance, contrat "jamais deux voisins identiques").
const _SKYLINE := [
	{"kind": "generic", "file": "corrugated_shed", "pos": Vector3(71.0, 0.0, 8.0), "rot_y": -10.0},
	{"kind": "generic", "file": "shopfront_2_saloon", "pos": Vector3(77.0, 0.0, -3.5), "rot_y": 15.0},
	{"kind": "generic", "file": "wooden_shack", "pos": Vector3(83.0, 0.0, 8.5), "rot_y": 40.0},
	{"kind": "generic", "file": "shopfront_1_store", "pos": Vector3(89.0, 0.0, -4.0), "rot_y": -20.0},
	{"kind": "generic", "file": "shopfront_corner_garage", "pos": Vector3(95.0, 0.0, 8.0), "rot_y": 30.0},
	{"kind": "tripo", "file": "wl_shack", "pos": Vector3(102.0, 0.0, -3.5), "rot_y": 55.0},
	{"kind": "generic", "file": "shopfront_2_motel", "pos": Vector3(109.0, 0.0, 8.5), "rot_y": -35.0},
	{"kind": "generic", "file": "shopfront_1_bar", "pos": Vector3(116.0, 0.0, -3.0), "rot_y": 20.0},
	{"kind": "tripo", "file": "wl_fuel_store", "pos": Vector3(123.0, 0.0, 8.0), "rot_y": 100.0},
	{"kind": "generic", "file": "shopfront_1_store", "pos": Vector3(130.0, 0.0, -3.5), "rot_y": -55.0},
	{"kind": "generic", "file": "corrugated_shed", "pos": Vector3(137.0, 0.0, 8.0), "rot_y": 10.0},
]

func _build_skyline() -> void:
	var accent: Color = (WastelandLook.palette() as Dictionary)["accent"]
	for entry in _SKYLINE:
		var pos: Vector3 = entry["pos"]
		var rot: float = entry["rot_y"]
		var inst: Node3D = null
		if entry["kind"] == "generic":
			inst = PropKit.instance(_PROP + String(entry["file"]) + ".glb", pos, rot, {"accent": accent})
		else:
			inst = _load_painted_tripo(_TRIPO + String(entry["file"]) + ".glb")
			if inst:
				inst.position = pos
				inst.rotation_degrees.y = rot
		if inst:
			add_child(inst)


## Charge un repère/bâtiment Tripo déjà importé (assets/models/props/
## wasteland/tripo/*.glb -- un `StandardMaterial3D` par surface, ce que
## l'import glTF de Godot construit pour un Principled BSDF <- Image Texture,
## voir tests/rendering/test_cartoon_painted_props.gd) et reconstruit
## chaque surface avec le shader encré du jeu, texture peinte conservée :
## EXACTEMENT le flux "bout-en-bout" documenté par ce test (hors périmètre
## avant ce contrat), jamais `Cartoon.painted()`/un kind partagé (chaque
## repère porte sa PROPRE texture bakée, unique).
func _load_painted_tripo(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("BeautyCorner: repère introuvable %s" % path)
		return null
	var inst := packed.instantiate() as Node3D
	_repaint_painted(inst)
	return inst

func _repaint_painted(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		for i in range(mi.mesh.get_surface_count()):
			var src: Material = mi.get_surface_override_material(i)
			if src == null:
				src = mi.mesh.surface_get_material(i)
			var tex := Cartoon.texture_from_imported_material(src)
			mi.set_surface_override_material(i, Cartoon.painted_texture_prop(tex))
	for c in node.get_children():
		_repaint_painted(c)


## Collision "boîte simple" (contrat : "jamais le maillage IA") dimensionnée
## sur l'AABB RÉELLE du maillage importé -- jamais une cote devinée à la
## main, qui dériverait à la première retouche de hauteur du manifeste
## (`tools/ai3d/manifests/painted_env.yaml`). Même calcul d'AABB fusionnée
## que `tools/review/model_preview.gd::_load_model` (merge des AABB globales
## de chaque MeshInstance3D), mais consommé ici pour poser UNE StaticBody3D
## par bâtiment plutôt que pour recaler une échelle.
func _add_box_collision_from_aabb(root_node: Node3D, nm: String) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root_node, meshes)
	if meshes.is_empty():
		return
	var box := AABB()
	var first := true
	for mi in meshes:
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var body := StaticBody3D.new()
	body.name = "Collision_%s" % nm
	body.position = box.get_center()
	add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	body.add_child(col)

func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		_collect_meshes(c, out)


# ============================================================ habillage
## ART-88 (« Coin beauté v2 », note du contrat "grappes de caisses/fûts/
## pneus au pied des façades" + "poteaux et câbles" + "clôtures" + "débris" +
## "épaves") -- bibliothèque de props générique (PropKit.gd, lue seule),
## mêmes teintes que `wasteland_look.gd` (accent grue ocre-orange) plutôt
## qu'une couleur inventée ici. Densifié par rapport à ART-82 : une grappe
## dédiée au pied de CHACUN des 4 bâtiments de `_BUILDINGS` (avant : deux
## grappes seulement, aucune au pied du fuel_store ni du saloon), plutôt
## qu'une poignée d'objets épars.
func _build_dressing() -> void:
	var accent: Color = (WastelandLook.palette() as Dictionary)["accent"]
	var poles := [8.0, 18.0, 28.0]
	for x in poles:
		var pole := PropKit.instance(_PROP + "power_pole.glb", Vector3(x, 0.0, -TRACK_HALF - 0.6), 0.0, {"accent": accent})
		if pole:
			add_child(pole)
	for i in range(poles.size() - 1):
		var wire := PropKit.instance(_PROP + "wires_catenary.glb",
			Vector3(poles[i], 0.0, -TRACK_HALF - 0.6), 0.0, {"accent": accent})
		if wire:
			add_child(wire)

	# Grappes caisses/fûts/pneus/débris au pied de CHAQUE bâtiment (contrat) --
	# `wl_saloon` x=6/`wl_fuel_store` x=16.5 côté nord (z<0), `wl_garage` x=9/
	# `wl_shack` x=19 côté sud (z>0), voir `_BUILDINGS`. Le sol ART-85 (ornières
	# à ±1,4 m) reste dégagé : tout reste au-delà de |z| >= 2,0.
	## ART-90 (« Coin beauté v4 ») : verdict utilisateur/lead du 2026-09-25 -- capture
	## reports/checkpoints/2026-09-25_ART-89/beauty_corner_apres.jpg : il restait des panneaux
	## bleu vif penchés `scrap_sheets` (gauche, pied du saloon ; droite, pied du garage) et une
	## pile `crate_stack` beige AU CENTRE (pied du garage), tous procéduraux (texture
	## `corrugated`/`wood` hors palette du coin beauté, contrat "cassent le rendu peint") --
	## retirés ci-dessous. Les 2 `wooden_crate` du premier plan gauche (saloon) sortaient déjà
	## quasiment du cadre (calcul d'angle caméra, voir `_build_camera` : à ~-44°/-58° pour un
	## demi-champ ~51° à 1920x1080) et se recouvraient en un seul bloc cadré/rogné plutôt qu'une
	## caisse lisible -- retirés aussi (contrat "la caisse unie au premier plan gauche").
	## `crate_stack` du fuel store (loin, plan différent) et le `wooden_crate` du Shack (est,
	## hors du cadre de rue standard) restent : ni "au centre" ni "au premier plan gauche" du
	## cadrage `_build_camera`, pas visés par le verdict.
	var clutter := [
		# Saloon (x=6, nord).
		{"file": "oil_drum", "pos": Vector3(7.2, 0.0, -2.8), "rot": 0.0},
		{"file": "tyre_stack", "pos": Vector3(7.8, 0.0, -2.3), "rot": 0.0},
		{"file": "junk_pile", "pos": Vector3(2.6, 0.0, -3.2), "rot": -30.0},
		# Fuel store (x=16.5, nord) -- inhabité par ART-82, contrat note
		# explicitement une grappe manquante ici. Pas de `crate_stack` ici (ART-90 :
		# retombait quasi pile derrière le `wl_junk_pile` déplacé ci-dessous depuis la
		# même caméra -- l'un des deux resterait "une caisse unie dans le cadre" dès que
		# l'autre bouge, voir la sonde `unproject_position` du contrat).
		{"file": "oil_drum", "pos": Vector3(17.6, 0.0, -2.7), "rot": 0.0},
		{"file": "oil_drum", "pos": Vector3(18.1, 0.0, -2.4), "rot": 0.0},
		{"file": "bottle_crates", "pos": Vector3(18.6, 0.0, -2.1), "rot": 15.0},
		{"file": "sandbags", "pos": Vector3(15.8, 0.0, -3.1), "rot": 0.0},
		# Garage (x=9, sud).
		{"file": "oil_drum", "pos": Vector3(11.0, 0.0, 2.6), "rot": 0.0},
		{"file": "oil_drum", "pos": Vector3(11.5, 0.0, 2.3), "rot": 0.0},
		{"file": "pallet", "pos": Vector3(8.4, 0.0, 2.9), "rot": -10.0},
		# Shack (x=19, sud).
		{"file": "pallet", "pos": Vector3(21.0, 0.0, -3.0), "rot": 10.0},
		{"file": "tyre_stack", "pos": Vector3(13.5, 0.0, 3.2), "rot": 0.0},
		{"file": "bottle_crates", "pos": Vector3(19.8, 0.0, 2.5), "rot": 0.0},
		{"file": "cable_spool", "pos": Vector3(18.2, 0.0, 2.9), "rot": 10.0},
		{"file": "wooden_crate", "pos": Vector3(20.4, 0.0, 2.1), "rot": -20.0},
		# Débris épars (rochers) hors des ornières, en bord de piste.
		{"file": "rock_medium", "pos": Vector3(2.0, 0.0, 2.7), "rot": 0.0},
		{"file": "rock_small", "pos": Vector3(23.4, 0.0, 3.6), "rot": 0.0},
		{"file": "rock_small", "pos": Vector3(23.9, 0.0, 3.9), "rot": 0.0},
	]
	for entry in clutter:
		var inst := PropKit.instance(_PROP + String(entry["file"]) + ".glb",
			entry["pos"], entry["rot"], {"accent": accent})
		if inst:
			add_child(inst)

	_build_fences(accent)
	_build_wrecks()
	_build_market_and_junk()


## Clôtures de fond de parcelle (contrat "clôtures") -- ferment le vide
## derrière la rangée de bâtiments plutôt que de le laisser en sable nu,
## SANS chevaucher les bâtiments eux-mêmes (`_BUILDINGS`, profondeur ~5 m
## centrée sur z=±5,8 -- une clôture à z=±9,0 reste 3,2 m au-delà de leur face
## arrière). `rot_y=0.0` : la largeur locale (2,2 m) du prop est déjà le long
## de son axe X (vérifié à l'image, comme tout prop de ce dépôt), donc alignée
## sur la rue SANS rotation.
const _FENCE_SPACING := 2.3
const _FENCE_NORTH_Z := -(TRACK_HALF + _PORCH_DEPTH + 3.4)
const _FENCE_SOUTH_Z := TRACK_HALF + _PORCH_DEPTH + 3.4
## Largeur RÉELLE de wl_fence_broken.glb une fois à l'échelle (dims mesurées au turntable,
## voir tools/ai3d/manifests/painted_env.yaml) -- espacement de `DressingKit.tripo_row`
## ci-dessous, pas de PropCatalog.footprint() à interroger pour ces 4 sortes (elles vivent
## hors du catalogue, voir l'en-tête de DressingKit.gd §5).
const _FENCE_BROKEN_SPACING := 2.2

## ART-89 : la rangée sud passait par `fence_chainlink.glb` (PropKit, matériau par défaut --
## "panneaux bleus" du verdict utilisateur/lead) -- remplacée par la clôture cassée peinte
## Tripo installée par ce contrat, en grappe (`DressingKit.tripo_row`, variation par
## instance -- rotation/miroir/teinte, jamais deux voisins identiques, voir son en-tête).
## La rangée nord (bois, déjà correcte) est inchangée.
func _build_fences(accent: Color) -> void:
	var x := 1.0
	while x <= 25.0:
		var inst := PropKit.instance(_PROP + "fence_wood.glb", Vector3(x, 0.0, _FENCE_NORTH_Z), 0.0, {"accent": accent})
		if inst:
			add_child(inst)
		x += _FENCE_SPACING
	DressingKit.tripo_row(self,
		[Vector3(3.0, 0.0, _FENCE_SOUTH_Z), Vector3(27.0, 0.0, _FENCE_SOUTH_Z)],
		"fence_broken", _FENCE_BROKEN_SPACING, 89, 0.0)


## Épaves (contrat "épaves", référence wasteland_hero.png : deux véhicules
## posés bien EN VUE au milieu de la rue, pas contre une façade) -- dans le
## couloir dégagé de la piste plutôt qu'en bord de trottoir (RETOUR
## VÉRIFICATEUR : une position en bord de façade, même hors ornière, tombait
## DERRIÈRE la grappe caisses/fûts la plus proche depuis la caméra -- fût
## invisible à la capture malgré une position "correcte" sur le papier, même
## cause que `_MIDGROUND`/`_SKYLINE`, voir leur commentaire). `x=12`/`x=23` :
## deux poches dégagées entre les grappes de `_build_dressing` (saloon
## x<=7,8, fuel store x>=14,6) plutôt que dans l'axe direct de la caméra
## (qui les masquerait totalement l'une l'autre).
## `rot_y` proche de 0 (pas ~90°) : RETOUR VÉRIFICATEUR -- `footprint.d`
## (longueur, 4,9-5,0 m) dépasse largement `footprint.w` (largeur, 2,0-2,45 m,
## voir manifest.json) le long de l'axe LOCAL Z ; une rotation proche de 90°
## présente donc l'épave presque de face/dos à la caméra (un pavé compact,
## silhouette peu lisible, capture réelle) plutôt que de profil (silhouette
## de véhicule reconnaissable, comme la référence) -- une rotation MODESTE
## (20-25°) garde le profil long tourné vers la caméra.
## ART-89 : les 2 épaves procédurales "en blocs rouges" (sedan_wreck/truck_wreck, verdict
## utilisateur/lead du 2026-09-25) sont remplacées par l'épave peinte Tripo installée par ce
## contrat -- MÊMES positions/rotations que la note "RETOUR VÉRIFICATEUR" ci-dessus (couloir
## dégagé de la piste, rotation modeste pour garder le profil tourné vers la caméra) : seul
## le modèle change. `tripo_variants(..., yaw_jitter_deg=0.0)` ne sert ici qu'au
## miroir/à la teinte (jitter nul : les rotations restent celles déjà vérifiées à l'image) --
## contrat "jamais deux voisins identiques" : les 2 épaves sont déjà loin l'une de l'autre
## (x=10,5/x=27), le miroir/la teinte suffisent à les distinguer sans dépendre d'un hasard de
## rotation qui romprait le cadrage vérifié.
func _build_wrecks() -> void:
	var wrecks := [
		{"pos": Vector3(10.5, 0.0, 0.5), "rot": 15.0},
		{"pos": Vector3(27.0, 0.0, -0.8), "rot": -20.0},
	]
	var variants: Array = DressingKit.tripo_variants("car_wreck", wrecks.size(), 89, 0.0, 0.0)
	for i in wrecks.size():
		var entry: Dictionary = wrecks[i]
		var variant: Dictionary = variants[i]
		var inst := DressingKit.load_tripo("car_wreck", variant["tint"])
		if inst == null:
			continue
		inst.position = entry["pos"]
		inst.rotation_degrees.y = entry["rot"]
		if variant["mirror"]:
			inst.scale.x = -1.0
		add_child(inst)
		_add_box_collision_from_aabb(inst, "car_wreck_%d" % i)


## ART-89 : 2 des 4 grappes installées par ce contrat, posées dans les poches encore
## dégagées entre les grappes caisses/fûts déjà posées par `_build_dressing` ci-dessus --
## nord : entre le saloon (x<=7,8) et le fuel store (x>=14,6) ; sud : au-delà des débris
## épars (rock_small x=23,4/23,9), avant la fin de la clôture (x=27). Aucun chevauchement
## avec le reste de la scène (contrat).
##
## ART-90 : le stand nord (9.0, -2.8) retombait à ~-28° de l'axe caméra, PILE dans le
## corridor des poteaux de la véranda du saloon (calcul d'angle caméra, `_build_camera`)
## -- lisible seulement comme un fouillis de poutres sombres à contre-jour du porche,
## jamais reconnaissable comme un étal (verdict "remettre à leur place... visibles").
## Repris à l'emplacement (7.8, 2.2) libéré par le `crate_stack` retiré de `_build_dressing`
## ci-dessus (contrat "au centre") -- angle caméra ~+12° (quasi centre-cadre), côté garage,
## en plein soleil, sans porche pour le masquer. Le stand sud (24.5, 3.3, ~-2° -- quasi
## centre-cadre lui aussi, mais loin dans l'axe de la rue) reste inchangé.
func _build_market_and_junk() -> void:
	var stalls := [
		{"pos": Vector3(7.8, 0.0, 2.2), "rot": 15.0},
		{"pos": Vector3(24.5, 0.0, 3.3), "rot": -10.0},
	]
	var stall_variants: Array = DressingKit.tripo_variants("market_stall", stalls.size(), 89, 0.0, 0.0)
	for i in stalls.size():
		var entry: Dictionary = stalls[i]
		var variant: Dictionary = stall_variants[i]
		var inst := DressingKit.load_tripo("market_stall", variant["tint"])
		if inst == null:
			continue
		inst.position = entry["pos"]
		inst.rotation_degrees.y = entry["rot"]
		if variant["mirror"]:
			inst.scale.x = -1.0
		add_child(inst)
		_add_box_collision_from_aabb(inst, "market_stall_%d" % i)

	## ART-90 : (13.2, -2.6) se projetait à l'écran à 34,8 % de la largeur -- quasi pile
	## derrière le 2e poteau de la véranda du saloon (`Camera3D.unproject_position`, sondé
	## depuis un script `SceneTree` jetable pendant ce contrat) : silhouette sombre, à peine
	## reconnaissable comme un tas de bric-à-brac (verdict "visibles dans le cadrage").
	## (10.0, -3.5) (nord, plan intermédiaire) et (12.3, 3.4) (sud, entre le garage et la
	## cabane) essayés d'abord : le premier retombe dans l'ombre portée de la véranda du
	## saloon (soleil rasant), le second derrière l'étal `market_stall` juste posé plus haut
	## (même angle caméra à quelques mètres près, l'étal -- large et proche -- masque tout ce
	## qui tombe derrière lui) -- même sonde `unproject_position`. (4.0, -2.1) reprend
	## EXACTEMENT l'emplacement du second `wooden_crate` retiré ci-dessus (`_build_dressing`)
	## -- confirmé en PLEINE LUMIÈRE sur la toute première capture de ce contrat (avant
	## retrait), contrairement à (5.5, -3.2) essayé d'abord, encore dans l'ombre portée de
	## l'escalier voisin (`Kit.stairs`, step_x=6.0, `_build_kit_modules`) -- vérifié à l'image
	## (`reports/beauty/beauty_corner.png` de ce contrat).
	var junk_variants: Array = DressingKit.tripo_variants("junk_pile", 1, 89, 0.0, 0.0)
	var junk_variant: Dictionary = junk_variants[0]
	var junk := DressingKit.load_tripo("junk_pile", junk_variant["tint"])
	if junk:
		junk.position = Vector3(4.0, 0.0, -2.1)
		junk.rotation_degrees.y = -20.0
		add_child(junk)
		_add_box_collision_from_aabb(junk, "junk_pile_0")


# ============================================================== caméra
## 1,7 m d'œil (contrat). Point de fuite centre-gauche comme
## wasteland_hero.png : la cible visée a un Z sensiblement PLUS GRAND que la
## position caméra (5.5 contre -0.6) -- la caméra vise donc légèrement de
## biais par rapport à l'axe +X pur de la piste (qui reste, elle, bien
## droite) -- vérifié à l'image (`reports/beauty/beauty_corner.png`) : ce
## sens précis (et pas l'inverse) porte le point de fuite/les repères de
## fond côté GAUCHE du cadre, jamais à droite.
##
## Gros plan optionnel du pied d'un bâtiment (ART-85, critère d'acceptation
## "chaque bâtiment posé sur une jupe de terre" + capture requise "gros plan
## du pied d'un bâtiment") : la jupe reste, depuis la caméra RUE ci-dessus,
## cachée derrière le trottoir de bois opaque (_build_kit_modules) quel que
## soit son rayon (voir _BUILDING_MOUND_RADIUS) -- mais rien ne la recouvre
## vue d'EN HAUT (voir `_frame_building_foot`). `--foot-closeup=<x>` (lu via
## `OS.get_cmdline_user_args()`, GLOBAL -- pas besoin de toucher
## tools/review/beauty_shot.gd, hors périmètre de cette tâche) cadre ainsi le
## bâtiment de `_BUILDINGS` le plus proche de `pos.x == <x>`, à la place de
## la vue de rue standard. SANS cet argument : comportement INCHANGÉ
## (contrat "sans toucher au reste de la scène").
const _FOOT_CLOSEUP_ARG := "--foot-closeup="

func _build_camera() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var closeup_arg := _foot_closeup_arg()
	if not closeup_arg.is_empty():
		_frame_building_foot(cam, float(closeup_arg))
		return
	cam.fov = 70.0
	cam.look_at_from_position(Vector3(1.5, 1.7, -0.6), Vector3(30.0, 2.2, 5.5), Vector3.UP)
	cam.current = true


## "" si `--foot-closeup=` absent de la ligne de commande (String, pas
## Variant : un `var := ...` typé Variant est un avertissement -> erreur ici,
## `warnings_as_errors` du projet), sinon sa valeur X demandée (`float(...)`
## côté appelant).
func _foot_closeup_arg() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(_FOOT_CLOSEUP_ARG):
			return a.substr(_FOOT_CLOSEUP_ARG.length())
	return ""


## Cadre le bâtiment de `_BUILDINGS` le plus proche de `target_x` en PLONGÉE
## depuis au-dessus : la jupe de terre (mound centré sur `pos`, radius 3.0,
## voir `_build_ground`) y est visible tout autour du bâtiment (le trottoir
## ne la recouvre que vue de côté, pas vue d'en haut), contrairement à la
## vue de rue standard.
##
## Le sol procédural de `_build_ground` s'arrête à `TRACK_HALF + _PORCH_DEPTH
## + 0.2 + 4.2` = 10,0 m = moitié de `TRACK_WIDTH + 12.0` (ART-88 : marge
## élargie de 1,2 m à 4,2 m au-delà du bâtiment côté Z, voir le commentaire
## de `_build_ground` -- l'ancienne marge de 1,2 m laissait déjà
## `wl_fuel_billboard` déborder du maillage) -- plusieurs essais À GRAND
## ANGLE (fov 45-70°, à hauteur d'œil ET en plongée) cadraient encore le ciel
## hors maillage sur un bord de l'image MALGRÉ cette marge élargie : même
## sans décalage Z explicite (caméra ET cible à `pos.z`), l'empreinte au sol
## d'un grand angle dépasse largement une marge de quelques mètres dès qu'on
## s'élève un peu (empreinte ~ hauteur x tan(fov/2), qui CROÎT avec la
## hauteur même si l'angle depuis la verticale, lui, diminue). Fov ÉTROIT
## (25°) et caméra basse/proche à la place : empreinte au sol de l'ordre de
## 1 m, confortablement sous la marge disponible.
func _frame_building_foot(cam: Camera3D, target_x: float) -> void:
	var closest: Dictionary = _BUILDINGS[0]
	var closest_dist := INF
	for entry in _BUILDINGS:
		var pos: Vector3 = entry["pos"]
		var d: float = absf(pos.x - target_x)
		if d < closest_dist:
			closest_dist = d
			closest = entry
	var pos: Vector3 = closest["pos"]
	cam.fov = 25.0
	cam.look_at_from_position(
		Vector3(pos.x - 1.5, 2.5, pos.z),
		Vector3(pos.x, 0.1, pos.z),
		Vector3.UP)
	cam.current = true
