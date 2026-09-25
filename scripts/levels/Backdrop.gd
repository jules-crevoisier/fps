## Backdrop.gd
## Coulisses d'horizon (STYLE_BIBLE.md SS6.3 "Coulisses (nouveau, obligatoire)",
## tâche ART-06) : un anneau de silhouettes PLATES et UNSHADED entre 150 et
## 600 m autour du centre de la carte, qui ferme l'horizon à 100 % sous 5°
## d'élévation -- "plus aucune vue où la carte flotte dans le vide". Un
## thème par famille de carte (désert / port-cargo / ville / montagne),
## choisi depuis `MatchConfig.map_id` (`theme_for_map`), posé automatiquement
## par `LevelLook._style()` (même mécanique que l'Environment/le ciel : tout
## par CODE au runtime, aucune scène .tscn n'est modifiée -- voir LevelLook.gd
## en tête de fichier). Deux nœuds seulement :
##   - "Wall"      : un MeshInstance3D, le mur continu qui GARANTIT la
##                   fermeture d'horizon (`build_wall_mesh`/`closes_horizon`).
##   - "Landmarks" : un MultiMeshInstance3D, des accents plus hauts qui
##                   donnent au thème sa silhouette propre (derricks/mesas,
##                   grues/coques, toits/cheminées, crêtes) -- un seul maillage
##                   par carte, dupliqué par instance (`landmark_transforms`).
## Budget "au plus 40 draw calls ajoutés" (perf_bench) : MESURÉ (pas déduit
## du seul nombre de nœuds), sur les 8 cartes, avec `tools/review/run_review.ps1
## -Only perf_bench` lancé deux fois DE SUITE (même session, sans autre
## changement entre les deux passes -- des agents tournent en parallèle sur
## d'autres fichiers du dépôt pendant le développement, donc seul un A/B
## immédiat isole vraiment le coût de CE fichier) : une fois avec
## `LevelLook._add_backdrop` neutralisé (`return` ajouté en tête, retiré
## juste après la mesure), une fois avec le comportement réel. RECALIBRÉ
## (relance QA, 2026-09-24) : la mesure précédente (+11,9 à +18,8 draw calls)
## datait d'AVANT le fix `add_child.call_deferred` de LevelLook.gd -- le bug
## « Parent node is busy setting up children » empêchait alors l'anneau
## d'être posé sur les 8 cartes (vérifié sur map_shots), donc ce nombre
## mesurait en réalité un delta proche de zéro contaminé par d'autres
## changements du dépôt entre les deux passes, pas le coût réel de ce
## fichier. Une fois le bug corrigé, delta constant sur les 8 cartes : +2
## draw calls (+3 sur La Fosse) -- cohérent avec la géométrie (un
## MeshInstance3D "Wall" + un MultiMeshInstance3D "Landmarks", chacun un
## seul draw call quel que soit le nombre d'instances/segments), largement
## sous le budget. Seule une mesure réelle avant/après (jamais une lecture
## de code) fait foi ici.
##
## Géométrie procédurale déterministe par défaut (aucune RNG, aucun fichier
## requis -- même philosophie de repli que PropCatalog.gd : "aucun test n'a
## besoin d'un .glb pour passer"). Si `tools/blender/make_backdrops.py` a
## exporté `assets/models/backdrops/<thème>/landmark.glb`, ce maillage est
## utilisé à la place du repli boîte/pyramide pour la silhouette des
## "Landmarks" (le mur reste toujours procédural : sa hauteur par segment
## DOIT rester calculée depuis `wall_height_for_radius`, jamais bakée dans un
## fichier externe, pour que la garantie "ferme l'horizon sous 5°" tienne
## quel que soit le contenu de assets/models/backdrops/).
##
## Fonctions statiques pures partout où c'est possible (mêmes valeurs à
## chaque appel pour les mêmes arguments, aucun état/horloge/RNG lu) --
## testables sans arbre de scène, comme LevelLook.build_environment().
##
## Tâche ART-76 (docs/research/09_wasteland_vertical_slice.md SS d.6,
## "Coulisses en 3 couches" + "Repères directionnels d'horizon", CHK-12) --
## deux nœuds de plus, ajoutés SEULEMENT si utiles pour le thème :
##   - "Skirt"       : un MeshInstance3D, une "jupe" de sol (dunes/chaos de
##                     roches) qui comble le vide entre le bord practicable
##                     d'une carte (40 m) et le mur ("Wall", 170 m) -- sans
##                     cette nappe, une vue aérienne voit un fond de scène
##                     NOIR (aucune géométrie, aucun ciel) dans cet anneau,
##                     ce que CHK-12 mesure comme du "vide" (voir
##                     `build_skirt_mesh`). Va TOUJOURS jusqu'à
##                     `RING_WALL_RADIUS_M` (jamais seulement jusqu'à
##                     `SKIRT_RADIUS_MAX_M`, qui ne borne que la teinte, voir
##                     `_skirt_vertex_color`) -- continuité stricte avec
##                     "Wall", aucun trou radial. Matériau SANS brouillard de
##                     scène (`disable_fog`, CORRIGÉ revue QA 2026-09-24) :
##                     sinon une vue aérienne (caméra très haute, distance à
##                     la jupe quasi constante quel que soit le rayon) sature
##                     le brouillard en un voile uniforme qui écrase le
##                     dégradé peint -- voir `_unshaded_material`.
##   - "Directional" : un MeshInstance3D, les silhouettes NOMMÉES par point
##                     cardinal du thème désert (mesa à l'ouest, raffinerie
##                     à l'est, ligne de pylônes au nord -- `R15`) --
##                     `null`/absent pour les thèmes sans jeu de données
##                     directionnel (`directional_landmarks`).
## Le mur ("Wall") du thème désert gagne en plus un profil de "plateaux à
## flancs verticaux" (mesas, `wall_plateau_segment_width`) qui remplace les
## anciennes pointes à un seul segment, et un dégradé de couleur PAR SOMMET
## (`strata_color`, 3 teintes de roche STYLE_BIBLE) plutôt que l'aplat
## unique des 3 autres thèmes -- voir `build_wall_mesh`.
class_name Backdrop
extends Node3D

const THEME_DESERT := "desert"
const THEME_PORT_CARGO := "port_cargo"
const THEME_CITY := "city"
const THEME_MOUNTAIN := "mountain"

## Carte -> thème (STYLE_BIBLE.md SS6.3 : "Désert / Port et cargo / Ville /
## Montagne"). Deux cartes par thème, appariées par famille de décor propre
## (MapCatalog.all()/docs/STYLE_BIBLE.md SS6.4) :
##  - désert       : Val-Poussière (ville-frontière désertique) + Wasteland
##                    (relais pétrolier désertique) -- mesas, derricks, poteaux.
##  - port_cargo    : Port-Ferraille (quais, grue portuaire) + Cargo Ship
##                    (porte-conteneurs) -- mer, quais lointains, grues, cargos.
##  - ville         : Saint-Ombre (pavés, piliers industriels) + Le Belvédère
##                    (toits à l'aube) -- toits, cheminées.
##  - montagne      : Col du Vautour (base alpine enneigée) + La Fosse
##                    (carrière encaissée dans la roche) -- crêtes enneigées.
const _THEME_BY_MAP: Dictionary = {
	"val_poussiere": THEME_DESERT,
	"wasteland": THEME_DESERT,
	"port_ferraille": THEME_PORT_CARGO,
	"cargo_ship": THEME_PORT_CARGO,
	"saint_ombre": THEME_CITY,
	"le_belvedere": THEME_CITY,
	"col_du_vautour": THEME_MOUNTAIN,
	"la_fosse": THEME_MOUNTAIN,
}
## Carte par défaut de StyleTokens.DEFAULT_MAP_ID ("wasteland") -> désert :
## même repli que Cartoon.map_palette() pour un map_id vide/inconnu.
const _DEFAULT_THEME := THEME_DESERT

const RING_RADIUS_MIN_M := 150.0
const RING_RADIUS_MAX_M := 600.0
const HORIZON_ELEVATION_DEG := 5.0
## Hauteur d'œil (perf_bench.gd EYE_HEIGHT, tools/review/perf_bench.gd) :
## même référence que la sonde de performance qui rejoue une vue joueur.
const EYE_HEIGHT_M := 1.6

## Mur de fermeture : posé au bord le plus proche de la bande (150 m) --
## le rayon le plus économe en géométrie (petite circonférence) qui reste
## dans la bande "coulisses" -- avec une hauteur par segment calculée pour
## dépasser `wall_height_for_radius(RING_WALL_RADIUS_M)` (donc largement audit
## au-delà de 5° d'élévation vue depuis le centre de la carte). 64 segments :
## silhouette assez fine pour lire un profil de crête/toits sans faceter.
const RING_WALL_RADIUS_M := 170.0
const WALL_SEGMENTS := 64

## Accents (derricks/grues/cheminées/crêtes) répartis entre ces deux rayons,
## à l'intérieur de la bande 150-600 m, en dehors du mur lui-même.
const LANDMARK_RADIUS_MIN_M := 230.0
const LANDMARK_RADIUS_MAX_M := 580.0
const LANDMARK_COUNT := 20
## Hauteur de référence (m) bakée dans le maillage de repli ; le facteur par
## instance (voir `landmark_transforms`) vient ensuite la mettre à l'échelle
## avec la hauteur de clôture d'horizon réelle à son propre rayon.
const _LANDMARK_REF_HEIGHT := 1.0

## `shape` ("box"/"pyramid"), largeur/profondeur bakées dans le maillage de
## repli (m, à `_LANDMARK_REF_HEIGHT` de haut) et multiplicateur de hauteur
## (appliqué par-dessus `wall_height_for_radius(radius)` par instance) --
## voir la doc de `_THEME_BY_MAP` pour la famille de silhouette par thème.
const _LANDMARK_SHAPE: Dictionary = {
	THEME_DESERT: {"shape": "box", "w": 6.0, "d": 6.0, "h_mul": 1.6},        # derrick/poteau : haut et fin
	THEME_PORT_CARGO: {"shape": "box", "w": 5.0, "d": 20.0, "h_mul": 1.25},  # mât de grue/silhouette de coque : allongé
	THEME_CITY: {"shape": "box", "w": 15.0, "d": 15.0, "h_mul": 1.05},       # bloc de toit + cheminée : carré, trapu
	THEME_MOUNTAIN: {"shape": "pyramid", "w": 34.0, "d": 34.0, "h_mul": 1.85}, # crête : large base, pointe haute
}

static var _mesh_cache: Dictionary = {}  # thème -> Mesh (repli ou .glb, un seul maillage par thème pour le MultiMesh)

## "Jupe" de sol (ART-76, docs/research/09 SS d.6 "Jupe de 40 à 150 m") :
## nappe de dunes/roches basses qui comble le sol entre le bord practicable
## d'une carte et l'anneau -- `SKIRT_RADIUS_MAX_M` ne borne que la teinte
## (voir `_skirt_vertex_color`, dont le dégradé SATURE sur sa couleur
## lointaine dès ce rayon puis reste plat jusqu'au mur), le maillage lui-même
## va jusqu'à `RING_WALL_RADIUS_M` (continuité stricte avec "Wall", CHK-12
## "0 pixel de vide"). CORRIGÉ (revue QA, 2026-09-24) : `SKIRT_RADIUS_MAX_M`
## n'était référencé nulle part -- `_skirt_vertex_color` bornait alors (à
## tort) tout son dégradé sur `RING_WALL_RADIUS_M`, du code mort avec une
## documentation qui ne correspondait plus à l'implémentation réelle ; voir
## `_skirt_vertex_color` pour le câblage corrigé. 40 m suppose qu'aucune
## carte n'a de sol practicable au-delà de ce rayon (vérifié : "les 8 cartes
## tiennent largement dans un rayon de 150 m", doc de `wall_height_for_radius`)
## -- la jupe est alors entièrement recouverte par le vrai sol de la carte à
## l'intérieur de la zone jouable, et seulement visible dans le vide au-delà.
const SKIRT_RADIUS_MIN_M := 40.0
const SKIRT_RADIUS_MAX_M := 150.0
const SKIRT_SEGMENTS := 48
const SKIRT_RINGS := 3

## Relief de la jupe par thème -- désert (dunes + chaos de roches) plus
## accidenté, port-cargo (quai/vasière) presque plat, ville (gravats) bas,
## montagne (éboulis) le plus accidenté. `rock_every`/`rock_extra` : une
## bosse plus marquée (rocher) toutes les `rock_every` colonnes.
const _SKIRT_PROFILE_CFG: Dictionary = {
	THEME_DESERT: {"base": 0.6, "jitter": 2.2, "rock_every": 5, "rock_extra": 3.5},
	THEME_PORT_CARGO: {"base": 0.15, "jitter": 0.5, "rock_every": 9, "rock_extra": 0.9},
	THEME_CITY: {"base": 0.3, "jitter": 0.8, "rock_every": 6, "rock_extra": 1.4},
	THEME_MOUNTAIN: {"base": 1.0, "jitter": 3.0, "rock_every": 4, "rock_extra": 4.5},
}

## Teintes de "roche à strates" (ART-76, docs/research/09 SS d.2, table
## "Falaises et roches" : roche `#8C6B55` (L 0,56), strates `#A0715A` et
## `#B89A7A`) -- utilisées par `strata_color` pour le mur/les repères
## directionnels du thème désert, dégradé au sol (`DESERT_STRATA_BASE`)
## jusqu'au sommet (`DESERT_STRATA_TOP`) puis voilées vers l'horizon avec
## `tint_for_radius` (mêmes tokens backdrop_near/backdrop_far par carte,
## aucune duplication de la logique de carte ici).
const DESERT_STRATA_BASE := Color("8c6b55")
const DESERT_STRATA_MID := Color("a0715a")
const DESERT_STRATA_TOP := Color("b89a7a")

## Profil du mur par thème (`wall_profile_heights`) -- désert : plateaux
## ("mesas") de `plateau_width` segments consécutifs qui PARTAGENT la même
## hauteur (flancs verticaux à chaque frontière de plateau, jamais de pointe
## à un seul segment) ; les 3 autres thèmes gardent l'ancien profil "pointes
## rares" (`spike_every`/`spike_extra`), INCHANGÉ.
const _WALL_PROFILE_CFG: Dictionary = {
	THEME_DESERT: {"base": 8.0, "jitter": 20.0, "plateau_width": 5},
	THEME_PORT_CARGO: {"base": 3.0, "jitter": 3.0, "spike_every": 8, "spike_extra": 15.0},
	THEME_CITY: {"base": 9.0, "jitter": 6.0, "spike_every": 4, "spike_extra": 14.0},
	THEME_MOUNTAIN: {"base": 16.0, "jitter": 18.0, "spike_every": 2, "spike_extra": 24.0},
}

## Repères directionnels du thème désert (ART-76, docs/research/09 SS d.6
## "Repères directionnels d'horizon", R15) -- une silhouette NOMMÉE par
## point cardinal, en plus des accents génériques dispersés
## (`landmark_transforms`). Convention d'angle partagée avec
## `landmark_transforms`/`directional_landmarks` (position =
## `cos(angle)*rayon, 0, sin(angle)*rayon`) : 0°=est (+X), 90°=sud (+Z),
## 180°=ouest (-X), 270°=nord (-Z) -- vérifiée sur les spawns réels de
## Wasteland (scripts/levels/maps/layouts/wasteland.gd : équipe bleue
## x ≈ -37, équipe rouge x ≈ +37), donc bleu=ouest, rouge=est. `h_mul` > 1,0
## sur les pièces "repère" (mesa/torchères/pylônes) -- même contrat que
## `landmark_transforms` : la silhouette DOIT dépasser
## `wall_height_for_radius(rayon)` pour rester visible au-dessus du mur à
## son propre azimut. `h_mul` < 1,0 sur les pièces d'appoint (cuves, dune,
## panneau) : elles n'ont pas besoin de percer l'horizon, seulement d'exister
## en silhouette basse autour des repères hauts.
const _DESERT_DIRECTIONAL: Array = [
	{"name": "west_mesa", "angle_deg": 180.0, "radius_m": 260.0, "w": 70.0, "d": 55.0, "h_mul": 1.7},
	{"name": "east_flare_a", "angle_deg": -8.0, "radius_m": 248.0, "w": 3.0, "d": 3.0, "h_mul": 1.8},
	{"name": "east_flare_b", "angle_deg": 7.0, "radius_m": 256.0, "w": 3.2, "d": 3.2, "h_mul": 1.9},
	{"name": "east_tank_a", "angle_deg": -3.0, "radius_m": 234.0, "w": 14.0, "d": 14.0, "h_mul": 0.5},
	{"name": "east_tank_b", "angle_deg": 3.0, "radius_m": 233.0, "w": 12.0, "d": 12.0, "h_mul": 0.45},
	{"name": "north_pylon_0", "angle_deg": 270.0, "radius_m": 240.0, "w": 2.2, "d": 2.2, "h_mul": 1.6},
	{"name": "north_pylon_1", "angle_deg": 272.0, "radius_m": 300.0, "w": 2.2, "d": 2.2, "h_mul": 1.6},
	{"name": "north_pylon_2", "angle_deg": 268.0, "radius_m": 360.0, "w": 2.2, "d": 2.2, "h_mul": 1.6},
	{"name": "north_pylon_3", "angle_deg": 271.0, "radius_m": 430.0, "w": 2.2, "d": 2.2, "h_mul": 1.6},
	{"name": "north_pylon_4", "angle_deg": 269.0, "radius_m": 500.0, "w": 2.2, "d": 2.2, "h_mul": 1.6},
	{"name": "south_dune", "angle_deg": 90.0, "radius_m": 260.0, "w": 60.0, "d": 40.0, "h_mul": 0.4},
	{"name": "south_road_sign", "angle_deg": 96.0, "radius_m": 238.0, "w": 1.5, "d": 4.0, "h_mul": 0.85},
]

# ------------------------------------------------------------------------
#  Thème et couleurs
# ------------------------------------------------------------------------

## Thème de coulisses pour `map_id` (STYLE_BIBLE.md SS6.3) -- un id vide ou
## inconnu retombe sur le thème de la carte par défaut, comme
## `Cartoon.map_palette()`.
static func theme_for_map(map_id: String) -> String:
	return _THEME_BY_MAP.get(map_id, _DEFAULT_THEME)

## Teinte à `radius_m` (m, depuis le centre) pour `map_id` : dégradé entre
## `backdrop_near` (bord proche, 150 m) et `backdrop_far` (bord loin,
## 600 m, quasi fondu dans `sky_horizon`) -- Cartoon.map_palette() (tâche
## ART-05) porte déjà ces deux clés pour les 8 cartes. C'est ce dégradé qui
## réalise "voilées vers l'horizon" (SS6.3) : nul besoin de peindre un
## gradient dans la géométrie, le brouillard de scène (LevelLook,
## fog_light_color/fog_density) fait le reste au rendu.
static func tint_for_radius(map_id: String, radius_m: float) -> Color:
	var palette := Cartoon.map_palette(map_id)
	var t: float = clamp((radius_m - RING_RADIUS_MIN_M) / (RING_RADIUS_MAX_M - RING_RADIUS_MIN_M), 0.0, 1.0)
	var near: Color = palette["backdrop_near"]
	var far: Color = palette["backdrop_far"]
	return near.lerp(far, t)


## Couleur d'un sommet à `height_fraction` (0 = base au sol, 1 = sommet) du
## mur/d'un repère directionnel désert, à `radius_m` du centre (ART-76,
## docs/research/09 SS d.6 "Anneau à 170 m : mesas à strates, 2 à 3 teintes
## chaudes voilées"). Tout thème != désert retombe EXACTEMENT sur
## `tint_for_radius` (aplat unique, comportement des 3 autres thèmes
## inchangé). Désert : dégradé roche `DESERT_STRATA_BASE` (sol, sombre) ->
## `DESERT_STRATA_MID` -> `DESERT_STRATA_TOP` (sommet, pâle) SELON LA
## HAUTEUR, puis voilé vers `tint_for_radius` selon LE RAYON -- le même
## calcul de `t` que `tint_for_radius` (entre `RING_RADIUS_MIN_M` et
## `RING_RADIUS_MAX_M`), pour que l'anneau (170 m, `veil_t` proche de 0 --
## presque pure roche, lisible de près) se voile progressivement jusqu'au
## fond (580 m, `veil_t` proche de 1 -- mesas pâles fondues dans l'horizon,
## SS d.6 "Fond de 400 à 600 m"), SANS dupliquer la logique de carte
## (backdrop_near/backdrop_far restent la seule source de l'atmosphère par
## carte, voir `tint_for_radius`).
static func strata_color(map_id: String, theme: String, height_fraction: float, radius_m: float) -> Color:
	var veil: Color = tint_for_radius(map_id, radius_m)
	if theme != THEME_DESERT:
		return veil
	var t: float = clamp(height_fraction, 0.0, 1.0)
	var rock: Color
	if t < 0.5:
		rock = DESERT_STRATA_BASE.lerp(DESERT_STRATA_MID, t / 0.5)
	else:
		rock = DESERT_STRATA_MID.lerp(DESERT_STRATA_TOP, (t - 0.5) / 0.5)
	var veil_t: float = clamp((radius_m - RING_RADIUS_MIN_M) / (RING_RADIUS_MAX_M - RING_RADIUS_MIN_M), 0.0, 1.0)
	return rock.lerp(veil, veil_t)

# ------------------------------------------------------------------------
#  Géométrie : hauteur de clôture d'horizon
# ------------------------------------------------------------------------

## Hauteur (m au-dessus du sol, y=0) qu'une silhouette PLEINE posée à
## `radius_m` doit atteindre pour que son sommet soit vu à au moins
## `elevation_deg` d'élévation depuis un œil à `eye_height_m`, au centre de
## la carte (origine du monde -- les 8 cartes tiennent largement dans un
## rayon de 150 m, voir les tables de périmètre de Layouts.gd/wasteland.gd) :
## simple trigonométrie (tan de l'angle × la distance, plus la hauteur
## d'œil). Un mur de CETTE hauteur, SANS TROU sur 360°, ferme donc
## GARANTIT l'horizon sous `elevation_deg` -- c'est tout le contrat de
## `build_wall_mesh`/`closes_horizon`.
static func wall_height_for_radius(radius_m: float, elevation_deg: float = HORIZON_ELEVATION_DEG, eye_height_m: float = EYE_HEIGHT_M) -> float:
	return eye_height_m + radius_m * tan(deg_to_rad(elevation_deg))

## Hash déterministe [0, 1) -- AUCUNE RNG/horloge : mêmes `a`/`b` -> même
## résultat à chaque appel (même contrat "pur" que
## MapDressing.group_entries()). Sert à varier la silhouette du mur/les
## landmarks sans jamais changer d'une exécution à l'autre.
static func _hash01(a: int, b: int) -> float:
	var h: int = hash("%d:%d" % [a, b])
	return float(h % 1000000) / 1000000.0

## Largeur (en segments) des plateaux de mesa du thème désert
## (`_WALL_PROFILE_CFG["plateau_width"]`, ART-76) -- 0 pour tout thème sans
## profil "plateaux" (les 3 autres thèmes gardent l'ancien profil "pointes
## rares" par segment). Utile aux tests/à l'appelant pour regrouper le
## profil en clusters sans dupliquer `_WALL_PROFILE_CFG` (privé).
static func wall_plateau_segment_width(theme: String) -> int:
	var cfg: Dictionary = _WALL_PROFILE_CFG.get(theme, _WALL_PROFILE_CFG[_DEFAULT_THEME])
	return int(cfg.get("plateau_width", 0))


## Profil de hauteur du mur (un flottant par segment, `segments` valeurs) :
## `wall_height_for_radius(radius_m)` (le PLANCHER qui ferme l'horizon,
## jamais descendu en dessous) + une silhouette propre au thème par-dessus.
## Désert (ART-76, docs/research/09 SS d.6 "le profil pyramides est
## remplacé par des plateaux à flancs verticaux") : `plateau_width`
## segments CONSÉCUTIFS partagent exactement la même hauteur -- un plateau
## plat (mesa), jamais une pointe à un seul segment -- la hauteur ne varie
## QUE D'UN CLUSTER À L'AUTRE, ce qui dessine une frontière quasi verticale
## entre deux mesas voisines (un seul panneau du mur, `build_wall_mesh`,
## relie directement deux hauteurs de cluster différentes). Les 3 autres
## thèmes gardent l'ANCIEN profil, inchangé : bosses basses + pointes rares
## (spike_every/spike_extra) par segment indépendant -- port-cargo presque
## plat, ville en redans, montagne en dents-de-scie hautes et fréquentes.
## Pur (voir `_hash01`) : mêmes `theme`/`segments`/`radius_m` -> même Array
## à chaque appel.
static func wall_profile_heights(theme: String, segments: int, radius_m: float = RING_WALL_RADIUS_M) -> Array:
	var floor_h := wall_height_for_radius(radius_m)
	var cfg: Dictionary = _WALL_PROFILE_CFG.get(theme, _WALL_PROFILE_CFG[_DEFAULT_THEME])
	var seed: int = theme.hash()
	var heights: Array = []
	heights.resize(segments)
	if cfg.has("plateau_width"):
		var plateau_w: int = int(cfg["plateau_width"])
		for i in segments:
			var cluster: int = i / plateau_w
			# `_hash01(seed, cluster)` à cluster CONSÉCUTIF (0, 1, 2...) ne
			# suffit pas ici : les chaînes hachées ("seed:0", "seed:1", ...)
			# ne diffèrent que par leur dernier caractère, et `_hash01`
			# renvoie alors des valeurs quasi identiques d'un cluster au
			# suivant (vérifié : delta ~0,000001) -- aucun relief de mesa
			# lisible. Faire varier le PREMIER argument d'un grand pas
			# impair (92821, mesuré pour bien disperser sur [0, 1)) corrige
			# ça sans toucher `_hash01` lui-même (partagé avec le profil
			# "pointes rares" des 3 autres thèmes, ci-dessous, inchangé).
			var extra: float = float(cfg["base"]) + _hash01(seed + cluster * 92821, 1) * float(cfg["jitter"])
			heights[i] = floor_h + extra
	else:
		for i in segments:
			var extra: float = float(cfg["base"]) + _hash01(seed, i) * float(cfg["jitter"])
			if i % int(cfg["spike_every"]) == 0:
				extra += float(cfg["spike_extra"]) * _hash01(seed + 1, i)
			heights[i] = floor_h + extra
	return heights

## Vrai si un mur de ce profil ferme bien l'horizon à 100 % sous 5°
## (aucun segment sous le plancher `wall_height_for_radius`) -- encode
## directement le critère d'acceptation ART-06/CHK-12 pour ce mur.
static func closes_horizon(theme: String, segments: int = WALL_SEGMENTS, radius_m: float = RING_WALL_RADIUS_M) -> bool:
	var floor_h := wall_height_for_radius(radius_m)
	for h in wall_profile_heights(theme, segments, radius_m):
		if float(h) < floor_h - 0.001:
			return false
	return true

# ------------------------------------------------------------------------
#  Maillages
# ------------------------------------------------------------------------

## Mur continu (anneau complet, aucun trou en azimut) : `segments` panneaux
## trapézoïdaux radiaux, chacun du sol (y=0) jusqu'à sa propre hauteur de
## profil -- deux hauteurs voisines différentes ne laissent PAS de trou
## (chaque panneau relie directement les deux sommets voisins, quelle que
## soit leur hauteur). `cull_disabled` côté matériau (voir `_unshaded_material`)
## puisque la caméra est TOUJOURS à l'intérieur de cet anneau.
## `map_id` (ART-76, défaut "" -- même repli que `tint_for_radius`) : thème
## désert SEULEMENT, chaque panneau reçoit une couleur PAR SOMMET
## (`strata_color`, sol -> mi-hauteur -> sommet, un panneau de plus par
## segment pour porter le point milieu) au lieu de l'aplat unique posé
## ensuite par le matériau (voir `build()`) -- "2 à 3 teintes chaudes"
## lisibles sur une même mesa. Les 3 autres thèmes gardent EXACTEMENT
## l'ancienne géométrie (aucune couleur posée ici, aplat matériau inchangé).
static func build_wall_mesh(theme: String, segments: int = WALL_SEGMENTS, radius_m: float = RING_WALL_RADIUS_M, map_id: String = "") -> ArrayMesh:
	var heights := wall_profile_heights(theme, segments, radius_m)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var strata: bool = theme == THEME_DESERT
	var c_base: Color
	var c_mid: Color
	var c_top: Color
	if strata:
		c_base = strata_color(map_id, theme, 0.0, radius_m)
		c_mid = strata_color(map_id, theme, 0.5, radius_m)
		c_top = strata_color(map_id, theme, 1.0, radius_m)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var h0: float = float(heights[i])
		var h1: float = float(heights[(i + 1) % segments])
		var p0 := Vector3(cos(a0) * radius_m, 0.0, sin(a0) * radius_m)
		var p1 := Vector3(cos(a1) * radius_m, 0.0, sin(a1) * radius_m)
		var t0 := p0 + Vector3.UP * h0
		var t1 := p1 + Vector3.UP * h1
		if strata:
			var m0 := p0 + Vector3.UP * (h0 * 0.5)
			var m1 := p1 + Vector3.UP * (h1 * 0.5)
			# Bande basse : sol -> mi-hauteur.
			st.set_color(c_base); st.add_vertex(p0)
			st.set_color(c_mid); st.add_vertex(m1)
			st.set_color(c_base); st.add_vertex(p1)
			st.set_color(c_base); st.add_vertex(p0)
			st.set_color(c_mid); st.add_vertex(m0)
			st.set_color(c_mid); st.add_vertex(m1)
			# Bande haute : mi-hauteur -> sommet.
			st.set_color(c_mid); st.add_vertex(m0)
			st.set_color(c_top); st.add_vertex(t1)
			st.set_color(c_mid); st.add_vertex(m1)
			st.set_color(c_mid); st.add_vertex(m0)
			st.set_color(c_top); st.add_vertex(t0)
			st.set_color(c_top); st.add_vertex(t1)
		else:
			st.add_vertex(p0)
			st.add_vertex(t1)
			st.add_vertex(p1)
			st.add_vertex(p0)
			st.add_vertex(t0)
			st.add_vertex(t1)
	st.generate_normals()
	return st.commit()

# ------------------------------------------------------------------------
#  Jupe de sol (ART-76, CHK-12 "0 pixel de vide")
# ------------------------------------------------------------------------

## Bosse de relief déterministe (m, >= 0) à la colonne angulaire `seg_i` et
## à l'anneau radial `ring_j` de la jupe, pour `theme` -- même contrat que
## `_hash01` (aucune RNG/horloge, mêmes arguments -> même résultat). `seg_i`
## DOIT déjà être réduit modulo le nombre de segments par l'appelant (voir
## `build_skirt_mesh`) pour que le relief se raccorde SANS trou à l'azimut
## 0°/360°.
static func _skirt_height(theme: String, seg_i: int, ring_j: int, cfg: Dictionary) -> float:
	var seed: int = theme.hash()
	var extra: float = float(cfg["base"]) + _hash01(seed + 100, seg_i * 31 + ring_j) * float(cfg["jitter"])
	if seg_i % int(cfg["rock_every"]) == 0:
		extra += float(cfg["rock_extra"]) * _hash01(seed + 101, seg_i * 31 + ring_j)
	return extra

## Couleur de la jupe à `radius_m` : part du token `ground` de la carte (le
## SABLE/sol réel de cette carte, déjà défini pour les 8 cartes --
## Cartoon.map_palette) près du bord practicable, et se fond vers la teinte
## de "roche à strates" du thème désert (`DESERT_STRATA_BASE`) ou vers
## `tint_for_radius` pour les 3 autres thèmes, à mesure qu'on approche du
## mur -- la jupe se lit alors comme la continuation du sol de la carte,
## pas comme un disque plaqué dessous. Le dégradé SATURE sur sa couleur
## lointaine dès `SKIRT_RADIUS_MAX_M` (150 m, CORRIGÉ revue QA 2026-09-24 --
## `SKIRT_RADIUS_MAX_M` n'était câblé nulle part, code mort) : entre
## `SKIRT_RADIUS_MAX_M` et le mur (`RING_WALL_RADIUS_M`, 170 m) la teinte
## reste plate, seul le MAILLAGE (voir `build_skirt_mesh`) continue jusqu'au
## mur -- exactement le contrat documenté sur `SKIRT_RADIUS_MAX_M`.
static func _skirt_vertex_color(map_id: String, theme: String, radius_m: float) -> Color:
	var t: float = clamp((radius_m - SKIRT_RADIUS_MIN_M) / max(SKIRT_RADIUS_MAX_M - SKIRT_RADIUS_MIN_M, 0.001), 0.0, 1.0)
	var palette := Cartoon.map_palette(map_id)
	var near_color: Color = palette["ground"]
	var far_color: Color = DESERT_STRATA_BASE if theme == THEME_DESERT else tint_for_radius(map_id, RING_WALL_RADIUS_M)
	return near_color.lerp(far_color, t)

## Nappe de sol comblant le vide entre le bord practicable d'une carte
## (`radius_min`) et le mur (`radius_outer`, TOUJOURS `RING_WALL_RADIUS_M`
## par défaut -- continuité stricte, CHK-12) : une grille pleine
## `segments` x `rings`, un léger relief de dunes/roches par thème
## (`_skirt_height`) et une couleur par sommet (`_skirt_vertex_color`).
## `map_id` (pas seulement `theme`, comme `tint_for_radius`) pour que la
## teinte proche colle au sol réel de CETTE carte. Pure/déterministe :
## même `map_id` -> même maillage à chaque appel.
static func build_skirt_mesh(map_id: String, segments: int = SKIRT_SEGMENTS, rings: int = SKIRT_RINGS, radius_min: float = SKIRT_RADIUS_MIN_M, radius_outer: float = RING_WALL_RADIUS_M) -> ArrayMesh:
	var theme := theme_for_map(map_id)
	var cfg: Dictionary = _SKIRT_PROFILE_CFG.get(theme, _SKIRT_PROFILE_CFG[_DEFAULT_THEME])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring_j in rings:
		var r0: float = lerp(radius_min, radius_outer, float(ring_j) / float(rings))
		var r1: float = lerp(radius_min, radius_outer, float(ring_j + 1) / float(rings))
		var c0 := _skirt_vertex_color(map_id, theme, r0)
		var c1 := _skirt_vertex_color(map_id, theme, r1)
		for seg_i in segments:
			var seg_i1 := (seg_i + 1) % segments
			var a0 := TAU * float(seg_i) / float(segments)
			var a1 := TAU * float(seg_i + 1) / float(segments)
			var h00 := _skirt_height(theme, seg_i, ring_j, cfg)
			var h10 := _skirt_height(theme, seg_i1, ring_j, cfg)
			var h01 := _skirt_height(theme, seg_i, ring_j + 1, cfg)
			var h11 := _skirt_height(theme, seg_i1, ring_j + 1, cfg)
			var p00 := Vector3(cos(a0) * r0, h00, sin(a0) * r0)
			var p10 := Vector3(cos(a1) * r0, h10, sin(a1) * r0)
			var p01 := Vector3(cos(a0) * r1, h01, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, h11, sin(a1) * r1)
			st.set_color(c0); st.add_vertex(p00)
			st.set_color(c1); st.add_vertex(p11)
			st.set_color(c0); st.add_vertex(p10)
			st.set_color(c0); st.add_vertex(p00)
			st.set_color(c1); st.add_vertex(p01)
			st.set_color(c1); st.add_vertex(p11)
	st.generate_normals()
	return st.commit()

# ------------------------------------------------------------------------
#  Repères directionnels (ART-76, R15)
# ------------------------------------------------------------------------

## Jeu de données des repères directionnels de `theme` (voir la doc de
## `_DESERT_DIRECTIONAL`) -- tableau vide pour tout thème sans silhouette
## nommée (les 3 autres thèmes aujourd'hui). Fonction publique séparée de la
## constante privée pour rester le seul point d'accès testable, comme
## `landmark_transforms` l'est pour `_LANDMARK_SHAPE`.
static func directional_landmarks(theme: String) -> Array:
	if theme == THEME_DESERT:
		return _DESERT_DIRECTIONAL
	return []

## Ajoute une boîte ORIENTÉE (rotation `xf.basis`, position `xf.origin`,
## taille `size` en mètres -- déjà à l'échelle finale, PAS le repli
## "1 m de haut" de `_build_box`/`landmark_mesh_for_theme`) au `SurfaceTool`
## `st`, une couleur par sommet (`color_base` au sol, `color_top` au
## sommet) -- même disposition de faces que `_build_box` (aucune face de
## dessous), pour fusionner plusieurs pièces en UN seul maillage/appel de
## rendu (voir `build_directional_mesh`).
static func _append_box(st: SurfaceTool, xf: Transform3D, size: Vector3, color_base: Color, color_top: Color) -> void:
	var hw := size.x * 0.5
	var hd := size.z * 0.5
	var h := size.y
	var c := [
		Vector3(-hw, 0.0, -hd), Vector3(hw, 0.0, -hd), Vector3(hw, 0.0, hd), Vector3(-hw, 0.0, hd),
		Vector3(-hw, h, -hd), Vector3(hw, h, -hd), Vector3(hw, h, hd), Vector3(-hw, h, hd),
	]
	var col := [color_base, color_base, color_base, color_base, color_top, color_top, color_top, color_top]
	var faces := [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]
	for f in faces:
		var a: Vector3 = xf * c[f[0]]
		var b: Vector3 = xf * c[f[1]]
		var cc: Vector3 = xf * c[f[2]]
		var d: Vector3 = xf * c[f[3]]
		var ca: Color = col[f[0]]
		var cb: Color = col[f[1]]
		var ccol: Color = col[f[2]]
		var cd: Color = col[f[3]]
		st.set_color(ca); st.add_vertex(a)
		st.set_color(cb); st.add_vertex(b)
		st.set_color(ccol); st.add_vertex(cc)
		st.set_color(ca); st.add_vertex(a)
		st.set_color(ccol); st.add_vertex(cc)
		st.set_color(cd); st.add_vertex(d)

## Maillage fusionné (UN seul draw call) des repères directionnels de la
## carte `map_id` -- `null` si `directional_landmarks(theme_for_map(map_id))`
## est vide (aucun nœud posé alors, voir `build()`). Position/taille depuis
## les données de `_DESERT_DIRECTIONAL` (même convention d'angle que
## `landmark_transforms`), hauteur finale TOUJOURS dérivée de
## `wall_height_for_radius(rayon) * h_mul` (jamais une valeur bakée), couleur
## par sommet via `strata_color` (sol -> sommet, voilée par rayon).
static func build_directional_mesh(map_id: String) -> ArrayMesh:
	var theme := theme_for_map(map_id)
	var entries := directional_landmarks(theme)
	if entries.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for entry in entries:
		var angle := deg_to_rad(float(entry["angle_deg"]))
		var radius: float = float(entry["radius_m"])
		var pos := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var xf := Transform3D(Basis(Vector3.UP, angle), pos)
		var h := wall_height_for_radius(radius) * float(entry["h_mul"])
		var size := Vector3(float(entry["w"]), h, float(entry["d"]))
		var c_base := strata_color(map_id, theme, 0.0, radius)
		var c_top := strata_color(map_id, theme, 1.0, radius)
		_append_box(st, xf, size, c_base, c_top)
	st.generate_normals()
	return st.commit()

## Boîte simple, origine à la base centrée au sol (STYLE_BIBLE.md SS7.9
## "Origine = base centrée au sol") : x/z centrés sur 0, y de 0 à `size.y`.
## Pas de face de dessous (jamais vue -- la caméra ne descend jamais sous le
## sol) : 5 faces, 10 triangles.
static func _build_box(size: Vector3) -> ArrayMesh:
	var hw := size.x * 0.5
	var hd := size.z * 0.5
	var h := size.y
	var c := [
		Vector3(-hw, 0.0, -hd), Vector3(hw, 0.0, -hd), Vector3(hw, 0.0, hd), Vector3(-hw, 0.0, hd),
		Vector3(-hw, h, -hd), Vector3(hw, h, -hd), Vector3(hw, h, hd), Vector3(-hw, h, hd),
	]
	var faces := [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = c[f[0]]
		var b: Vector3 = c[f[1]]
		var cc: Vector3 = c[f[2]]
		var d: Vector3 = c[f[3]]
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(cc)
		st.add_vertex(a); st.add_vertex(cc); st.add_vertex(d)
	st.generate_normals()
	return st.commit()

## Pyramide à base rectangulaire, même convention d'origine que `_build_box`
## (base au sol, pointe à `size.y`) -- silhouette de crête pour le thème
## montagne. Pas de face de dessous, pour la même raison.
static func _build_pyramid(size: Vector3) -> ArrayMesh:
	var hw := size.x * 0.5
	var hd := size.z * 0.5
	var base := [Vector3(-hw, 0.0, -hd), Vector3(hw, 0.0, -hd), Vector3(hw, 0.0, hd), Vector3(-hw, 0.0, hd)]
	var apex := Vector3(0.0, size.y, 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Vector3 = base[i]
		var b: Vector3 = base[(i + 1) % 4]
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(apex)
	st.generate_normals()
	return st.commit()

static func _landmark_glb_path(theme: String) -> String:
	return "res://assets/models/backdrops/%s/landmark.glb" % theme

static func _find_mesh_instances(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		_find_mesh_instances(child, out)

## Maillage `.glb` exporté par `tools/blender/make_backdrops.py` pour ce
## thème, ou `null` si absent (aucune build Blender lancée, ou test headless
## sans assets -- même repli que PropCatalog._load_scene/`info()`, "aucun
## test n'a besoin d'un .glb pour passer").
static func _load_glb_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate()
	var found: Array = []
	_find_mesh_instances(inst, found)
	var mesh: Mesh = null
	if not found.is_empty():
		mesh = (found[0] as MeshInstance3D).mesh
	inst.queue_free()
	return mesh

## Maillage de landmark pour `theme` (un seul, réutilisé par toutes les
## instances du MultiMesh -- seule la transformation varie par instance,
## voir `landmark_transforms`) : le `.glb` du thème s'il existe, sinon une
## boîte/pyramide de repli aux proportions de `_LANDMARK_SHAPE`, bakée à
## `_LANDMARK_REF_HEIGHT` de haut (mis à l'échelle par instance ensuite).
## Mis en cache par thème (4 entrées au plus, jamais invalidé -- comme
## `PropCatalog._mesh_cache`).
static func landmark_mesh_for_theme(theme: String) -> Mesh:
	if _mesh_cache.has(theme):
		return _mesh_cache[theme]
	var mesh: Mesh = _load_glb_mesh(_landmark_glb_path(theme))
	if mesh == null:
		var cfg: Dictionary = _LANDMARK_SHAPE.get(theme, _LANDMARK_SHAPE[_DEFAULT_THEME])
		var size := Vector3(float(cfg["w"]), _LANDMARK_REF_HEIGHT, float(cfg["d"]))
		mesh = _build_pyramid(size) if String(cfg["shape"]) == "pyramid" else _build_box(size)
	_mesh_cache[theme] = mesh
	return mesh

# ------------------------------------------------------------------------
#  Placement des accents (landmarks)
# ------------------------------------------------------------------------

## `count` transformations pour les accents de `theme`, réparties sur les
## 360° entre `LANDMARK_RADIUS_MIN_M` et `LANDMARK_RADIUS_MAX_M` (angle
## régulier + gigue déterministe, rayon dérivé du même hash) : chaque
## transformation pose le maillage de repère (SS7.9 "origine = base centrée
## au sol", donc `origin.y = 0` suffit, aucun décalage vertical à ajouter) à
## sa position sur l'anneau, mis à l'échelle en Y jusqu'à
## `wall_height_for_radius(rayon) * h_mul_du_thème` (dépasse donc TOUJOURS
## le mur à ce même rayon, pour bien lire comme un accent qui perce
## l'horizon) et en X/Z par une légère gigue de gabarit (0,8 à 1,3) pour ne
## pas répéter un accent identique 20 fois. Pur (voir `_hash01`).
static func landmark_transforms(theme: String, count: int = LANDMARK_COUNT) -> Array:
	var cfg: Dictionary = _LANDMARK_SHAPE.get(theme, _LANDMARK_SHAPE[_DEFAULT_THEME])
	var h_mul: float = float(cfg["h_mul"])
	var seed: int = theme.hash()
	var transforms: Array = []
	for i in count:
		var angle := TAU * float(i) / float(count) + (_hash01(seed, i * 3) - 0.5) * (TAU / float(count)) * 0.6
		var radius: float = lerp(LANDMARK_RADIUS_MIN_M, LANDMARK_RADIUS_MAX_M, _hash01(seed, i * 3 + 1))
		var target_h := wall_height_for_radius(radius) * h_mul
		var girth: float = lerp(0.8, 1.3, _hash01(seed, i * 3 + 2))
		var pos := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var basis := Basis(Vector3.UP, angle).scaled(Vector3(girth, target_h / _LANDMARK_REF_HEIGHT, girth))
		transforms.append(Transform3D(basis, pos))
	return transforms

# ------------------------------------------------------------------------
#  Matériau et assemblage
# ------------------------------------------------------------------------

## Matériau plat "unshaded" (STYLE_BIBLE.md SS6.3 "Rendu : unshaded") :
## aucune bande de lumière/ombre (contrairement à Cartoon.world(), qui
## applique toujours ink_toon) -- une silhouette plate à toute heure, quel
## que soit l'angle du soleil de la carte. `cull_disabled` : la caméra est
## à l'intérieur de l'anneau, elle doit voir la face interne du mur comme
## celle des accents. Pas d'ombre projetée/reçue ni de GI (décor de fond
## sans interaction gameplay, uniquement coûteux à calculer pour rien).
## `no_fog` (CORRIGÉ, revue QA 2026-09-24, CHK-12) : `false` partout SAUF
## pour "Skirt" (voir `build()`) -- le brouillard de profondeur de
## LevelLook.gd est calibré pour une caméra au niveau du joueur
## (`EYE_HEIGHT_M`) ; depuis une caméra AÉRIENNE, très haute au-dessus du
## centre de la carte, la distance caméra->jupe varie à peine avec le rayon
## (40-170 m face à une hauteur de caméra bien plus grande), donc ce
## brouillard y sature en un voile QUASI UNIFORME qui écrase le dégradé peint
## par sommet de `_skirt_vertex_color` -- constaté en capture réelle
## (map_shots) : un disque gris-bleu plat au lieu du dégradé sable->roche.
## `disable_fog` (BaseMaterial3D, doc Godot 4.7 via Context7 : "Disabling fog
## prevents an object from being affected by ... depth fog. This is
## especially useful for unshaded ... materials") règle exactement ce cas
## sans toucher LevelLook.gd (hors périmètre de cette tâche). "Wall" /
## "Landmarks" / "Directional" GARDENT le brouillard (inchangé, aucune
## régression ART-06/76) : à leurs rayons plus grands (150-600 m), même une
## caméra aérienne voit une vraie variation de distance selon le rayon --
## le voile atmosphérique y reste un signal de profondeur voulu, pas un
## artefact (voir la doc de `tint_for_radius`, qui compte explicitement sur
## ce brouillard réel en plus du dégradé bakée dans les sommets).
static func _unshaded_material(color: Color, use_vertex_color: bool = false, no_fog: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	m.vertex_color_use_as_albedo = use_vertex_color
	m.disable_fog = no_fog
	return m

static func _style_instance(g: GeometryInstance3D) -> void:
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

## Construit l'anneau complet pour `map_id` : un nœud "Backdrop" avec
## "Wall" + "Landmarks" (voir la doc de tête de fichier) et, depuis ART-76,
## "Skirt" (toujours) + "Directional" (thème désert seulement -- voir
## `directional_landmarks`). Fonction PURE côté résultat (mêmes objets
## Godot fraîchement créés à chaque appel, aucun état externe autre que
## MatchConfig lu) -- ne dépend d'aucun arbre de scène, comme
## LevelLook.build_environment(). Posé par `LevelLook._style()` en enfant du
## même parent que le WorldEnvironment.
static func build(map_id: String) -> Node3D:
	var theme := theme_for_map(map_id)
	# ART-76 : le mur désert porte sa couleur PAR SOMMET (`strata_color`,
	# posée dans `build_wall_mesh`) -- l'albédo du matériau doit alors rester
	# WHITE (neutre pour la multiplication `vertex_color_use_as_albedo`,
	# même convention que "Landmarks" ci-dessous), sinon la couleur du
	# sommet serait multipliée par l'aplat et doublement teintée.
	var wall_is_strata: bool = theme == THEME_DESERT

	var root := Node3D.new()
	root.name = "Backdrop"

	var wall := MeshInstance3D.new()
	wall.name = "Wall"
	wall.mesh = build_wall_mesh(theme, WALL_SEGMENTS, RING_WALL_RADIUS_M, map_id)
	if wall_is_strata:
		wall.material_override = _unshaded_material(Color.WHITE, true)
	else:
		wall.material_override = _unshaded_material(tint_for_radius(map_id, RING_WALL_RADIUS_M))
	_style_instance(wall)
	root.add_child(wall)

	var transforms := landmark_transforms(theme)
	if not transforms.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = landmark_mesh_for_theme(theme)
		mm.instance_count = transforms.size()
		for i in transforms.size():
			var xf: Transform3D = transforms[i]
			mm.set_instance_transform(i, xf)
			var radius := Vector2(xf.origin.x, xf.origin.z).length()
			mm.set_instance_color(i, tint_for_radius(map_id, radius))

		var landmarks := MultiMeshInstance3D.new()
		landmarks.name = "Landmarks"
		landmarks.multimesh = mm
		landmarks.material_override = _unshaded_material(Color.WHITE, true)
		_style_instance(landmarks)
		root.add_child(landmarks)

	# ART-76 : "jupe" de sol, toujours posée -- comble le vide entre le bord
	# practicable d'une carte et "Wall" (CHK-12). Couleur par sommet
	# (`_skirt_vertex_color`) -> albédo WHITE, même raison que "Wall" ci-dessus.
	# `no_fog = true` (CORRIGÉ, revue QA 2026-09-24, CHK-12) : voir la doc de
	# `_unshaded_material` -- sans ça, une vue aérienne voit un disque
	# gris-bleu uniforme au lieu du dégradé sable->roche peint par sommet.
	var skirt := MeshInstance3D.new()
	skirt.name = "Skirt"
	skirt.mesh = build_skirt_mesh(map_id)
	skirt.material_override = _unshaded_material(Color.WHITE, true, true)
	_style_instance(skirt)
	root.add_child(skirt)

	# ART-76 : silhouettes directionnelles nommées (mesa ouest, raffinerie
	# est, pylônes nord -- R15), thème désert seulement. `null` pour tout
	# autre thème (`directional_landmarks` vide) : aucun nœud posé.
	var directional_mesh := build_directional_mesh(map_id)
	if directional_mesh != null:
		var directional := MeshInstance3D.new()
		directional.name = "Directional"
		directional.mesh = directional_mesh
		directional.material_override = _unshaded_material(Color.WHITE, true)
		_style_instance(directional)
		root.add_child(directional)

	return root
