## look_probe.gd
## Sonde de calibration WYSIWYG (docs/STYLE_BIBLE.md §7.5, CHK-01 — tâche
## ART-01). Charge scenes/dev/look_probe.tscn (un cube-témoin d'albédo
## `#D2A46C` — docs/style/tokens.json "calibration_probe" — et un second cube
## neutre de 2 m posé à 30 m, repère d'échelle/distance de jeu façon la
## silhouette humaine de tools/blender/turntable.py, sans rôle dans les
## mesures ci-dessous), et le rend SUR CHAQUE CARTE de `MapCatalog.all()` sous
## le VRAI `Environment`/`DirectionalLight3D` de LevelLook.gd (jamais un rig
## de secours) : `LevelLook.build_environment(map_id)` posé sur un
## WorldEnvironment, `LevelLook._apply_key_light` posé sur une
## DirectionalLight3D, exactement comme le fait l'autoload en jeu.
##
## Mesure, par carte :
##   - `lit_L` : L OKLab de la face du cube-témoin la PLUS éclairée -- CETTE
##     face est celle dont la NORMALE pointe exactement vers le soleil de la
##     carte (voir `_orient_calib_cube` : on tourne le cube-témoin, chaque
##     itération de carte, pour aligner sa normale locale +Y sur
##     `-LevelLook._sun_direction(sun_elevation_deg)`, la même fonction que
##     LevelLook.gd utilise pour orienter la DirectionalLight3D -- source
##     unique). RETOUR VÉRIFICATEUR (ART-01, run réel) : un ancien design
##     gardait le cube-témoin fixe (axes du monde) et prenait le MAX des 3
##     candidates dessus/-X/-Z -- mais l'azimut diagonal fixe (X=Z) de
##     `_sun_direction` fait qu'AUCUNE face alignée aux axes du monde ne peut
##     recevoir la pleine composante horizontale du soleil (une face axiale
##     ne capte que sa projection sur UN axe, cos(élévation)*0,7071, jamais
##     cos(élévation) en entier) -- mesuré : même un soleil blanc pur ne
##     dépassait jamais ~0,68 quelle que soit la carte, très en-dessous de la
##     cible 0,75. Une face dont la normale épouse EXACTEMENT la direction 3D
##     du soleil (azimut + élévation) donne NORMAL·LIGHT ~= 1 -- la lecture
##     WYSIWYG qu'une vraie surface du décor optimalement orientée vers le
##     soleil afficherait réellement (un toit en pente, une rampe...). C'est
##     ce que CHK-01 doit vérifier : reste un cube-témoin (contrat ART-01),
##     juste orienté pour que la mesure soit valide sur les 8 élévations
##     (25°-50°) sans jamais sous-éclairer par construction. Doit valoir
##     0,75 ± 0,03 (CHK-01, tokens.json calibration_probe.lit_L/
##     lit_L_tolerance) : critère BLOQUANT (code de sortie 1 si une seule
##     carte échoue).
##     BLOQUÉ (rapport de tâche ART-01, voir `blocked_on`) : même à
##     `NORMAL·LIGHT ~= 1` (banded au plateau haut de la rampe, `ramp =
##     ALBEDO`), `light()` (ink_toon.gdshader) calcule `DIFFUSE_LIGHT =
##     ramp * normalize(LIGHT_COLOR)` -- SEULE la TEINTE du soleil compte
##     (`light_energy`/`ambient_light_energy` n'ont AUCUN effet mesurable,
##     vérifié en faisant varier `ambient_light_energy` de 0,0 à 100,0 sans
##     le moindre changement de pixel). Pour un soleil #D2A46C (l'albédo de
##     la sonde) en pleine lumière blanche, L OKLab ~= 0,749 (quasi la
##     cible) -- mais `Cartoon._MAP_PALETTES` (scripts/core/Cartoon.gd, HORS
##     PÉRIMÈTRE ART-01) donne à 5 des 8 cartes un `sun_color` assez saturé
##     pour que son plafond THÉORIQUE (banded=1, ambiance nulle) reste
##     SOUS 0,72 quel que soit l'Environment/la lumière -- ex. saint_ombre
##     (#FFB870) plafonne à ~0,657. Aucun réglage de LevelLook.gd/
##     tools/look_probe.gd ne peut donc faire passer CHK-01 sur les 8
##     cartes : la correction réelle est dans `Cartoon.gd` (désaturer/
##     blanchir les `sun_color` les plus chauds) ou dans le shader
##     (réintroduire une contribution d'ambiance/énergie réelle) -- tous
##     deux hors de la liste de fichiers ART-01.
##   - `shadow_L` : L OKLab de SA face à l'ombre (§7.5 « sa face à l'ombre »)
##     -- la face EXACTEMENT opposée (normale locale -Y, donc
##     `NORMAL·LIGHT = -1`, clampé à 0 dans `light()`) : elle ne reçoit que
##     l'ambiance du ciel + la bande d'ombre du shader, jamais la lumière
##     directe (voir `light()` dans assets/shaders/ink_toon.gdshader,
##     `banded` tombe à 0 quand `NORMAL·LIGHT <= 0`).
##   - `shadow_ratio` = shadow_L / lit_L ; cible 0,62-0,70 (tokens.json
##     calibration_probe.shadow_ratio). MESURÉE ET RAPPORTÉE seulement --
##     contrat ART-01 : « PASS exigé seulement après ART-02 » (la tâche qui
##     retouchera le ramp/shadow_tint pour l'atteindre) ; ne fait JAMAIS
##     échouer cette sonde.
##
## v3.1 (tâche OPS-11, comble les trous signalés par ART-02/ART-07 dans
## tools/review/style_check.py : CHK-09 « non mesuré », CHK-10/CHK-11 jamais
## mesurés) -- AJOUTE, toujours par carte :
##   - `ground_lit_L`/`ground_shadow_L`/`ground_shadow_ratio` (CHK-09) : une
##     paire d'échantillons RÉELS sur un sol (pas le cube-témoin) -- un au
##     soleil, un dans l'ombre PORTÉE par un occludeur dédié (`_shadow_gnomon`,
##     un cylindre vertical qui ne bouge jamais, jamais réorienté par carte
##     contrairement à `_calib_cube`), posé sur une plaque de sol DÉDIÉE
##     (`_ground_patch`, même albédo de calibration `#D2A46C` que `_calib_cube`
##     -- un albédo FIXE et connu, comparable à CHK-01, plutôt que le vrai
##     ton de sol de la carte). RETOUR VÉRIFICATEUR (run réel, OPS-11) :
##     recolorer `_ground` (le sol PARTAGÉ, utilisé comme arrière-plan des
##     poses "lit"/"shadow" du cube-témoin, §CHK-01) avec la vraie couleur de
##     sol de la carte cassait silencieusement `shadow_L`/`shadow_ratio` de
##     CHK-01 sur les 8 cartes (ratio mesuré > 1 sur 7/8, jusqu'à 1.36 --
##     confirmé par comparaison isolée avec l'algorithme original inchangé,
##     qui redonne bien 0,63-0,66 partout) : la caméra "shadow" du cube-témoin
##     (`_aim_shadow`, INCHANGÉE par cette tâche) peut se retrouver très près
##     du sol RÉEL selon l'élévation/l'orientation du cube, et un sol plus
##     clair que l'ancien gris neutre (`Cartoon.GRAPHITE`) y devenait visible.
##     `_ground` reste donc STRICTEMENT inchangé (toujours `Cartoon.GRAPHITE`,
##     jamais touché par cette tâche) ; `_ground_patch` est un nœud SÉPARÉ,
##     loin de `_calib_cube` (posé au même endroit que le gnomon, §
##     `_GNOMON_CENTER_XZ`), qui ne peut donc jamais apparaître dans les poses
##     "lit"/"shadow" du cube-témoin. Contrairement à CHK-01, le sol garde sa
##     normale RÉELLE (+Y, horizontale) : `NORMAL·LIGHT = sin(élévation)`,
##     jamais 1 -- c'est le point : CHK-09 mesure ce qu'un sol plat affiche
##     vraiment, pas une surface idéalement orientée. Voir `_ground_sample_
##     offset` pour la géométrie (un cylindre projette une ombre = union de
##     disques le long de l'axe du soleil ; un point sur cet axe, à une
##     distance calculée depuis l'élévation RÉELLE de la carte, est TOUJOURS
##     dans l'ombre quelle que soit l'élévation -- pas de coïncidence à
##     espérer). `ground_lit_hue_deg`/`ground_shadow_hue_deg`/`ground_hue_
##     delta_deg` : écart de teinte OKLCH entre les deux échantillons (CHK-09
##     `shadow_hue_tolerance_deg`) -- l'ombre doit rester perceptiblement la
##     MÊME matière (teinte proche), jamais une couleur différente.
##   - `silhouette_widths_px`/`silhouette_min_width_px`/`silhouette_pass_
##     fraction` (CHK-10) et `double_line_detected`/`double_line_span_px`
##     (CHK-11) : mesurés en pixels RÉELS sur l'image post-traitée par
##     `InkPost`/`ink_edges.gdshader` (ajouté comme enfant de la caméra, comme
##     `tools/review/perf_bench.gd::_ensure_ink_post`), sur un objet de
##     calibration DÉDIÉ (`_edge_calib_box`, 2×2×2 m, flottant à 15 m de haut
##     -- jamais `_scale_cube`, au sol : son arête basse serait mesurée contre
##     le SOL, à une profondeur quasi identique à sa propre face avant à cette
##     distance/cet angle de caméra, ce qui affaiblirait ou supprimerait le
##     bord de profondeur juste là où on veut le mesurer proprement -- en
##     l'air, rien d'autre que le ciel n'apparaît derrière l'objet sur ses 4
##     bords, voir `_aim_silhouette`). CHK-10 : vue DE FACE (une seule face
##     visible, 4 arêtes = 4 bords de silhouette purs, aucun pli visible),
##     largeur de trait mesurée à 30 m pile (`outline_min_px_at_30m`) sur 20
##     points répartis sur le pourtour. CHK-11 : vue DE TROIS-QUARTS RASANTE
##     (la face latérale n'est vue que sous un angle très oblique, ~5,7°) --
##     l'arête de coin convexe (un PLI, `crease_response` d'ink_edges.gdshader)
##     tombe alors tout près, en écran, de la vraie silhouette de la face
##     latérale : exactement le cas que `crease *= (1.0 - edge)` (ink_edges.
##     gdshader) doit empêcher de doubler en deux traits parallèles. Mesuré en
##     comptant les composantes connexes « encre » sur une ligne de balayage
##     entre les deux arêtes projetées, à 3 hauteurs.
##   Tout est REPORTÉ (comme `shadow_ratio` déjà), jamais gating : le statut
##   PASS/WARN/FAIL de CHK-09/10/11 est calculé par tools/review/style_check.py
##   depuis docs/style/tokens.json, seule source de vérité des seuils -- cette
##   sonde ne fait JAMAIS échouer sur ces trois contrôles (seul CHK-01 pilote
##   son code de sortie, voir `_finish`).
##
## Écrit un JSON récapitulatif (défaut res://reports/look_probe/look_probe.json,
## `--out=` pour changer) et, par carte, des captures PNG (poses "lit"/"shadow"
## du cube-témoin, "ground" du sol, "silhouette"/"crease" de l'objet de
## calibration d'arête -- défaut res://reports/look_probe/, `--out_dir=` pour
## changer) -- revue visuelle exigée par le CLAUDE.md du projet : « toute
## modification visible (3D, UI, VFX) se vérifie en image ».
##
##   godot --path . -s res://tools/look_probe.gd -- \
##       [--out=C:/chemin/look_probe.json] [--out_dir=C:/dossier] [--wait=N]
##
## Imprime `LOOK_PROBE_MAP <map_id> lit_L=.. pass=.. shadow_L=.. ratio=..
## pass(ART-02)=..`, `LOOK_PROBE_GROUND <map_id> ground_lit_L=..
## ground_shadow_L=.. ratio=.. hue_delta_deg=..` et `LOOK_PROBE_SILHOUETTE
## <map_id> min_width_px=.. pass_fraction=.. double_line=.. span_px=..` par
## carte, puis `LOOK_PROBE_OK <json>` et quitte 0 si CHK-01 (partie éclairée)
## passe sur TOUTES les cartes, ou `LOOK_PROBE_FAIL <raison>` et quitte 1
## sinon.
##
## EN FENÊTRÉ (comme tools/screenshot.gd, tools/map_shots.gd, tools/
## prop_shots.gd -- il faut un vrai swapchain pour lire `root.get_texture()`),
## JAMAIS `--headless`.
extends SceneTree

const _INK_POST_SCRIPT := preload("res://scripts/core/InkPost.gd")

const _SCENE_PATH := "res://scenes/dev/look_probe.tscn"
const _CALIBRATION_ALBEDO := Color("D2A46C")  # tokens.json calibration_probe.albedo
const _TARGET_LIT_L := 0.75
const _TARGET_LIT_L_TOLERANCE := 0.03
const _TARGET_SHADOW_RATIO := Vector2(0.62, 0.70)
const _DEFAULT_OUT_JSON := "res://reports/look_probe/look_probe.json"
const _DEFAULT_OUT_DIR := "res://reports/look_probe"
const _DEFAULT_WAIT_FRAMES := 45
## Demi-côté du cube-témoin (scenes/dev/look_probe.tscn : BoxMesh 1×1×1 m).
const _CALIB_HALF := 0.5
## Décalage caméra (m) le long de `_light_dir` (voir `_orient_calib_cube`) :
## la caméra se place TOUJOURS du côté du soleil pour la pose "lit" (elle
## regarde donc directement la face locale +Y, orientée face au soleil) et
## du côté opposé pour la pose "ombre" (face locale -Y) -- fonctionne pour
## toute élévation/azimut sans caméra par carte codée en dur.
const _CAM_OFFSET := 2.0
## Écart (degrés) entre la normale de la face "lit" et `_light_dir` --
## JAMAIS 0 : à `NORMAL·LIGHT` EXACTEMENT 1,0, `light()` (ink_toon.gdshader)
## calcule `step_pos = bands` (un entier pile), donc `fract(step_pos) = 0`
## -- `frac_edge` retombe à 0 et `banded` RECHUTE à `(bands-1)/bands`
## (0,667 pour bands=3) au lieu du plateau 1,0 juste en-dessous (mesuré :
## alignement exact, `dot=1.0000` imprimé, lit_L très en-dessous de la
## cible sur toutes les cartes -- voir rapport de tâche ART-01). 10° donne
## `NORMAL·LIGHT = cos(10°) ~= 0,985`, large marge au-dessus du seuil du
## plateau (`NORMAL·LIGHT >= (bands*0,5+band_softness)/bands ~= 0,817` pour
## les réglages par défaut de `Cartoon.world()`) sans viser le bord exact.
const _LIT_FACE_TILT_DEG := 10.0

## -- CHK-09 : occludeur dédié pour la paire sol ombre/soleil -------------
## Un CYLINDRE (pas une boîte) : sa projection au sol est un DISQUE de rayon
## constant dans TOUTES les directions, donc l'ombre qu'il porte est l'union
## des disques centrés le long du segment [0, hauteur/tan(élévation)] dans la
## direction du soleil -- un point sur CE segment est dans l'ombre quelle que
## soit sa distance le long de l'axe (contrairement à une boîte alignée aux
## axes du monde, dont l'empreinte projetée sur la diagonale du soleil est un
## losange dont la largeur varie avec la distance -- géométrie inutilement
## compliquée à garantir juste). Ne bouge JAMAIS (contrairement à
## `_calib_cube`, réorienté par carte, §CHK-01) : sa colonne reste verticale à
## chaque itération, seule l'élévation change la longueur de son ombre.
const _GNOMON_HEIGHT := 1.5
const _GNOMON_RADIUS := 0.3
## Position (X, Z monde) du centre du socle du gnomon -- loin de
## `_calib_cube` (origine) et de `_edge_calib_box`/`_scale_cube` (x=30), pour
## qu'aucune ombre ne se croise (voir le calcul de portée dans le commentaire
## de tête de fichier) ET loin de toute pose caméra de `_calib_cube` (voir
## la même note, §CHK-01 -- `_ground_patch` doit rester hors champ de
## `_aim_lit`/`_aim_shadow`).
const _GNOMON_CENTER_XZ := Vector2(20.0, -6.0)
## Plaque de sol DÉDIÉE à CHK-09, posée sous le gnomon -- JAMAIS `_ground`
## (voir la note "RETOUR VÉRIFICATEUR" de l'en-tête de fichier : recolorer le
## sol partagé cassait silencieusement la mesure CHK-01, hors périmètre de
## cette tâche). Assez grande pour couvrir les deux points échantillonnés à
## la pire élévation (±2,5 m suffit, voir `_ground_sample_offset` ; 8 m de
## côté en donne largement plus).
const _GROUND_PATCH_SIZE := Vector3(8.0, 0.2, 8.0)
## Direction HORIZONTALE (monde) dans laquelle les ombres s'allongent --
## l'azimut diagonal fixe de `LevelLook._sun_direction` (X=Z, composante
## horizontale toujours positive sur les deux axes) : IDENTIQUE sur les 8
## cartes, seule l'élévation change la longueur. Documenté une fois ici
## plutôt que recalculé depuis `_sun_direction` à chaque appel.
const _SHADOW_DIR_XZ := Vector3(0.70710678, 0.0, 0.70710678)
## Hauteur de la caméra "sol" au-dessus du gnomon, vue plongeante à la
## verticale : élimine tout risque d'occlusion entre les deux points
## échantillonnés (posés à plat sur le sol, jamais l'un derrière l'autre du
## point de vue de la caméra) et couvre large (voir la justification
## numérique dans le rapport de tâche : ±2,5 m suffit sur les 8 cartes, 10 m
## de hauteur en donne plus du double avec un FOV de 40°).
const _GROUND_CAM_HEIGHT := 10.0
## tokens.json checks.CHK-09 -- mirroir LOCAL, informatif seulement (voir
## l'en-tête de fichier : le statut PASS/WARN/FAIL qui compte est celui que
## tools/review/style_check.py calcule depuis tokens.json, jamais celui-ci).
const _CHK09_SHADOW_RATIO := Vector2(0.62, 0.70)
const _CHK09_SHADOW_MIN_L := 0.30
const _CHK09_HUE_TOLERANCE_DEG := 45.0

## -- CHK-10/CHK-11 : objet de calibration d'arête (silhouette + pli) -----
## Flottant à 15 m de haut (jamais au sol, voir l'en-tête de fichier) :
## `cast_shadow` désactivé (son ombre porterait, à basse élévation, à plus de
## 30 m de portée horizontale -- inoffensif en soi, mais désactivé pour ne
## jamais avoir à s'en soucier).
const _EDGE_BOX_SIZE := Vector3(2.0, 2.0, 2.0)
const _EDGE_BOX_CENTER := Vector3(30.0, 15.0, 0.0)
## Distance caméra <-> face avant pour CHK-10 : EXACTEMENT 30 m
## (`outline_min_px_at_30m`), pas une approximation.
const _SIL_CAM_DIST_M := 30.0
## Écart (m) en Z de la caméra "pli" par rapport à l'axe de la face avant :
## petit -> vue très rasante sur la face latérale (angle ~= atan(3/30) =
## 5,7°) -- c'est justement ce qui rapproche, à l'écran, l'arête de pli (coin
## convexe) de la vraie silhouette (bord lointain de la face latérale),
## LE cas que le masquage mutuel du shader (`crease *= 1.0 - edge`,
## assets/shaders/ink_edges.gdshader) doit empêcher de doubler.
const _CREASE_CAM_Z := 3.0
const _SIL_EDGE_SAMPLES := 5
const _SIL_SCAN_RADIUS_PX := 10
const _CREASE_SCAN_MARGIN_PX := 24
## RETOUR VÉRIFICATEUR (run réel, OPS-11) : un trait d'encre de ~2 px à 30 m
## est fortement anti-crénelé (`blend_mix`, alpha = intensité de bord) --
## mesuré sur `wasteland_silhouette.png`, son pixel le plus proche de l'encre
## pure reste à une distance euclidienne de ~0,15-0,16 du `Cartoon.INK` de
## référence (jamais 0 : jamais un aplat d'encre pur sur un trait aussi fin).
## Une tolérance de 0,14 (calibrée sur un aplat net, comme `safe_ink_
## tolerance` de tools/review/style_check.py) rate donc le trait sur PLUSIEURS
## cartes (0 px mesuré) et ne passe QUE par chance sur les plus sombres. 0,22
## capture confortablement ce mélange anti-crénelé (~0,15-0,16) tout en
## restant loin de la face de l'objet de calibration lui-même (~0,45-0,51 de
## distance, mesuré) et du ciel (~1,0-1,2) -- aucun risque de faux positif.
const _INK_TOL := 0.22
## tokens.json checks.CHK-10/CHK-11 -- mêmes réserves que _CHK09_* ci-dessus.
const _CHK10_MIN_WIDTH_PX := 2.0
const _CHK10_PERIMETER_FRACTION := 0.90
const _CHK11_GAP_PX := 3
const _CHK11_MIN_LEN_PX := 20.0

var _out_json: String = _DEFAULT_OUT_JSON
var _out_dir: String = _DEFAULT_OUT_DIR
var _wait_frames: int = _DEFAULT_WAIT_FRAMES

var _maps: Array = []
var _map_index: int = 0
var _phase: String = "load_map"
var _frame: int = 0
var _started: bool = false
var _failed: bool = false

var _root_inst: Node3D
var _calib_cube: MeshInstance3D
var _scale_cube: MeshInstance3D
var _ground: MeshInstance3D
var _shadow_gnomon: MeshInstance3D
var _ground_patch: MeshInstance3D
var _edge_calib_box: MeshInstance3D
var _world_env: WorldEnvironment
var _sun: DirectionalLight3D
var _cam: Camera3D

var _current_lit_l: float = 0.0
var _current_shadow_l: float = 0.0
var _current_ground_lit_l: float = 0.0
var _current_ground_shadow_l: float = 0.0
var _current_ground_lit_hue: float = 0.0
var _current_ground_shadow_hue: float = 0.0
var _current_silhouette_widths: Array = []
var _current_silhouette_min_width: float = 0.0
var _current_silhouette_pass_fraction: float = 0.0
var _current_double_line_detected: bool = false
var _current_double_line_span_px: float = 0.0
var _results: Array = []
## Direction (unitaire, MONDE) VERS le soleil de la carte COURANTE --
## recalculée par `_orient_calib_cube` à chaque `_load_map`. Sert de
## référence (le "vrai" azimut/élévation du soleil, voir `LevelLook.
## _sun_direction`), pas à viser la caméra -- voir `_lit_face_normal`.
var _light_dir: Vector3 = Vector3.UP
## Normale MONDE de la face "lit" du cube-témoin (= `_light_dir` tournée de
## `_LIT_FACE_TILT_DEG`, voir son commentaire) -- c'est CETTE direction, pas
## `_light_dir`, que la caméra vise dans `_aim_lit`/`_aim_shadow` : la
## caméra doit regarder la face RÉELLEMENT rendue bien en face (sample au
## centre de l'image), jamais avec l'écart de 10° qui existe entre la face
## et le soleil lui-même -- un angle de vue oblique sur cette face plaçait
## le pixel échantillonné trop près d'une arête, où l'anti-aliasing mélange
## un peu de la face voisine (plus sombre) et fausse la mesure (mesuré :
## écart incohérent d'une carte à l'autre à élévation égale -- voir rapport
## de tâche ART-01).
var _lit_face_normal: Vector3 = Vector3.UP


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_json = a.get_slice("=", 1)
		elif a.begins_with("--out_dir="):
			_out_dir = a.get_slice("=", 1)
		elif a.begins_with("--wait="):
			_wait_frames = int(a.get_slice("=", 1))
	# Résolu tout de suite en chemin OS réel : `Image.save_png` (voir
	# `_save_shot`) n'accepte pas `res://`, et ça évite toute ambiguïté avec
	# `DirAccess`/`FileAccess` plus bas (mêmes conventions que tools/
	# screenshot.gd, tools/map_shots.gd — leurs `--out=` sont déjà des chemins
	# OS). `globalize_path` laisse un chemin OS déjà absolu inchangé, donc
	# `--out=C:/...` fourni en ligne de commande passe ici sans effet de bord.
	_out_json = ProjectSettings.globalize_path(_out_json)
	_out_dir = ProjectSettings.globalize_path(_out_dir)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		return _start()
	if _failed:
		return true
	if _cam:
		_cam.current = true

	match _phase:
		"load_map":
			_load_map(_map_index)
			_aim_lit()
			_phase = "settle_lit"
			_frame = 0
			return false
		"settle_lit":
			_frame += 1
			if _frame < _wait_frames:
				return false
			_measure_lit()
			_aim_shadow()
			_phase = "settle_shadow"
			_frame = 0
			return false
		"settle_shadow":
			_frame += 1
			if _frame < _wait_frames:
				return false
			_measure_shadow()
			_aim_ground()
			_phase = "settle_ground"
			_frame = 0
			return false
		"settle_ground":
			_frame += 1
			if _frame < _wait_frames:
				return false
			_measure_ground()
			_aim_silhouette()
			_phase = "settle_silhouette"
			_frame = 0
			return false
		"settle_silhouette":
			_frame += 1
			if _frame < _wait_frames:
				return false
			_measure_silhouette()
			_aim_crease()
			_phase = "settle_crease"
			_frame = 0
			return false
		"settle_crease":
			_frame += 1
			if _frame < _wait_frames:
				return false
			_measure_crease()
			_record_map_result()
			return _advance()
	return false


func _start() -> bool:
	var packed := load(_SCENE_PATH) as PackedScene
	if packed == null:
		return _fail("scène introuvable : %s" % _SCENE_PATH)
	_root_inst = packed.instantiate()
	root.add_child(_root_inst)
	_calib_cube = _root_inst.get_node_or_null("CalibrationCube")
	_scale_cube = _root_inst.get_node_or_null("ScaleCube")
	_ground = _root_inst.get_node_or_null("Ground")
	if _calib_cube == null or _scale_cube == null or _ground == null:
		return _fail("scène %s incomplète (CalibrationCube/ScaleCube/Ground introuvables)" % _SCENE_PATH)

	# `Look` (autoload LevelLook.gd) n'est volontairement PAS simulé ici par
	# son mécanisme `node_added` habituel (tools/screenshot.gd, tools/
	# map_shots.gd) : on veut pouvoir réappliquer un Environment/une lumière
	# DIFFÉRENTS à CHAQUE itération de carte sur les MÊMES nœuds (voir
	# `_load_map`), ce que le signal ne permet pas proprement (il ne se
	# déclenche qu'à l'ENTRÉE dans l'arbre). On appelle donc directement les
	# mêmes fonctions statiques/de construction que `LevelLook._style` et
	# `_apply_key_light` -- exactement ce que `tests/rendering/
	# test_level_look.gd` vérifie déjà unitairement.
	_world_env = WorldEnvironment.new()
	root.add_child(_world_env)
	_sun = DirectionalLight3D.new()
	root.add_child(_sun)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	root.add_child(_cam)
	_cam.current = true
	# InkPost (assets/shaders/ink_edges.gdshader) -- requis pour CHK-10/CHK-11
	# (largeur de trait/absence de double trait) : sans lui, l'image ne
	# contient aucun contour d'encre à mesurer. Même schéma que
	# tools/review/perf_bench.gd::_ensure_ink_post (enfant direct de la
	# caméra active). `Settings.ink_edges` vaut `true` par défaut
	# (scripts/core/Settings.gd) : rien à activer explicitement ici.
	var post: MeshInstance3D = _INK_POST_SCRIPT.new()
	post.name = "InkPost"
	_cam.add_child(post)

	# Plaque de sol dédiée à CHK-09 (voir l'en-tête de fichier, "RETOUR
	# VÉRIFICATEUR") -- JAMAIS `_ground` (partagé avec les poses "lit"/
	# "shadow" du cube-témoin, CHK-01). Même albédo de calibration que
	# `_calib_cube` : comparable à CHK-01, recoloré (teinte d'ombre) à
	# chaque carte dans `_load_map`.
	_ground_patch = MeshInstance3D.new()
	var patch_mesh := BoxMesh.new()
	patch_mesh.size = _GROUND_PATCH_SIZE
	_ground_patch.mesh = patch_mesh
	_ground_patch.position = Vector3(_GNOMON_CENTER_XZ.x, -_GROUND_PATCH_SIZE.y * 0.5, _GNOMON_CENTER_XZ.y)
	root.add_child(_ground_patch)

	# Gnomon dédié (CHK-09, voir l'en-tête de fichier) -- un cylindre debout,
	# jamais réorienté, qui ne sert qu'à porter une ombre sur le sol.
	_shadow_gnomon = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.height = _GNOMON_HEIGHT
	cyl.top_radius = _GNOMON_RADIUS
	cyl.bottom_radius = _GNOMON_RADIUS
	_shadow_gnomon.mesh = cyl
	_shadow_gnomon.position = Vector3(_GNOMON_CENTER_XZ.x, _GNOMON_HEIGHT * 0.5, _GNOMON_CENTER_XZ.y)
	_shadow_gnomon.set_surface_override_material(0, Cartoon.world(Cartoon.GRAPHITE))
	root.add_child(_shadow_gnomon)

	# Objet de calibration d'arête (CHK-10/CHK-11, voir l'en-tête de fichier)
	# -- flottant, jamais au sol : `cast_shadow` désactivé, sa propre couleur
	# n'a aucun rôle (seul son contour d'encre est mesuré).
	_edge_calib_box = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = _EDGE_BOX_SIZE
	_edge_calib_box.mesh = box
	_edge_calib_box.position = _EDGE_BOX_CENTER
	_edge_calib_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_edge_calib_box.set_surface_override_material(0, Cartoon.world(Cartoon.GRAPHITE))
	root.add_child(_edge_calib_box)

	_maps = MapCatalog.all()
	if _maps.is_empty():
		return _fail("MapCatalog.all() est vide")

	_map_index = 0
	_phase = "load_map"
	return false


## Applique la palette/l'Environment/la lumière de `map_id`, et les matériaux
## peints (le cube-témoin doit utiliser le MÊME shader ink_toon.gdshader que
## le vrai décor -- Cartoon.world() -- jamais un aplat non éclairé, sinon la
## sonde ne mesurerait pas ce que le joueur voit réellement).
func _load_map(index: int) -> void:
	var entry: Dictionary = _maps[index]
	var map_id := String(entry["id"])
	MatchConfig.map_id = map_id
	_world_env.environment = LevelLook.build_environment(map_id)
	var look := LevelLook.new()
	look._apply_key_light(_sun)
	look.free()
	_calib_cube.set_surface_override_material(0, Cartoon.world(_CALIBRATION_ALBEDO))
	# `_ground`/`_scale_cube` : STRICTEMENT INCHANGÉS par cette tâche (voir la
	# note "RETOUR VÉRIFICATEUR" de l'en-tête de fichier) -- neutre
	# `Cartoon.GRAPHITE`, sans rôle dans aucune mesure. `_ground_patch`
	# (CHK-09, un nœud SÉPARÉ) reprend le même albédo de calibration que
	# `_calib_cube` -- seule sa TEINTE D'OMBRE doit suivre la carte courante,
	# recolorée ici comme les autres matériaux.
	_ground.set_surface_override_material(0, Cartoon.world(Cartoon.GRAPHITE))
	_scale_cube.set_surface_override_material(0, Cartoon.world(Cartoon.GRAPHITE))
	_ground_patch.set_surface_override_material(0, Cartoon.world(_CALIBRATION_ALBEDO))
	_orient_calib_cube(map_id)


## Tourne le cube-témoin pour que sa normale locale +Y pointe EXACTEMENT vers
## le soleil de `map_id` (voir la remarque `lit_L` de l'en-tête). Réutilise
## `LevelLook._sun_direction` (même fonction que `_apply_key_light` pour la
## DirectionalLight3D -- source unique de la direction du soleil) : le
## soleil VOYAGE selon `_sun_direction(elev)`, donc `LIGHT` (surface ->
## soleil, le vecteur que `light()` lit dans ink_toon.gdshader) est son
## opposé -- c'est cette direction que la normale +Y doit épouser.
## `Quaternion(Vector3, Vector3)` construit la rotation du plus court chemin
## entre les deux vecteurs (tous deux unitaires ici) -- exactement ce qu'il
## faut pour amener +Y (identité) sur `_light_dir`. L'origine (position) du
## cube n'est pas touchée, seule sa base tourne.
func _orient_calib_cube(map_id: String) -> void:
	var elev: float = Cartoon.map_palette(map_id)["sun_elevation_deg"]
	_light_dir = -LevelLook._sun_direction(elev)
	# La face locale +Y vise `_light_dir` À UN PETIT ANGLE PRÈS (`_LIT_FACE_
	# TILT_DEG`), jamais pile dessus -- voir le commentaire de la constante :
	# `NORMAL·LIGHT` EXACTEMENT 1,0 retombe dans le bug de bord de
	# `light()` (ink_toon.gdshader) plutôt que d'y rester.
	var tilt_axis := Vector3(1.0, 0.0, -1.0).normalized()  # horizontal, perpendiculaire à l'azimut diagonal (1,0,1)
	_lit_face_normal = _light_dir.rotated(tilt_axis, deg_to_rad(_LIT_FACE_TILT_DEG))
	var origin := _calib_cube.transform.origin
	_calib_cube.transform = Transform3D(Basis(Quaternion(Vector3.UP, _lit_face_normal)), origin)


## Pose "face au soleil" : caméra droit face à la normale RÉELLE de la face
## "lit" (`_lit_face_normal`, pas `_light_dir` -- voir son commentaire) : le
## centre de la face tombe au centre de l'image, jamais près d'une arête.
func _aim_lit() -> void:
	var center := _calib_cube.global_position
	_cam.global_position = center + _lit_face_normal * _CAM_OFFSET
	_cam.look_at(center, _cam_up())


## Pose "face à l'ombre" : caméra droit face à la normale de la face locale
## -Y, EXACTEMENT opposée à `_lit_face_normal` (`NORMAL·LIGHT` y est négatif,
## clampé à 0 par `light()` -- jamais de lumière directe, voir l'en-tête).
func _aim_shadow() -> void:
	var center := _calib_cube.global_position
	_cam.global_position = center - _lit_face_normal * _CAM_OFFSET
	_cam.look_at(center, _cam_up())


## `Camera3D.look_at` échoue si la direction de visée et le vecteur "up"
## sont (quasi) colinéaires -- n'arrive pas ici pour l'azimut diagonal fixe
## et les élévations 25°-50° du jeu (`_light_dir` reste loin de la
## verticale), mais un `up` de secours (axe X du monde) couvre le cas où
## une future carte ajouterait une élévation proche de 90°.
func _cam_up() -> Vector3:
	if absf(_lit_face_normal.dot(Vector3.UP)) > 0.999:
		return Vector3.RIGHT
	return Vector3.UP


## Face locale +Y (voir `_orient_calib_cube`) : sa normale épouse `_light_dir`
## à `_LIT_FACE_TILT_DEG` près, c'est la face la PLUS éclairée possible pour
## ce soleil (voir le commentaire de la constante).
func _measure_lit() -> void:
	var img := root.get_texture().get_image()
	var pt := _calib_cube.to_global(Vector3(0.0, _CALIB_HALF, 0.0))
	_current_lit_l = _sample_oklab_l(img, pt)
	_save_shot(img, "lit")


## Face locale -Y, exactement opposée à `_measure_lit` -- `NORMAL·LIGHT = -1`
## (clampée à 0 par `light()`) : jamais de lumière directe, voir l'en-tête.
func _measure_shadow() -> void:
	var img := root.get_texture().get_image()
	var pt := _calib_cube.to_global(Vector3(0.0, -_CALIB_HALF, 0.0))
	_current_shadow_l = _sample_oklab_l(img, pt)
	_save_shot(img, "shadow")


## -- CHK-09 : paire d'échantillons sol ombre/soleil (voir l'en-tête) --------

## Distance (m), le long de `_SHADOW_DIR_XZ`, à laquelle placer les deux
## échantillons sol de part et d'autre du gnomon : à mi-chemin entre le bord
## de son empreinte au sol (`_GNOMON_RADIUS`, +marge anti-aliasing) et la
## pointe de son ombre (`_GNOMON_HEIGHT / tan(élévation)`, voir le commentaire
## de `_GNOMON_HEIGHT` ci-dessus) -- ni trop près du gnomon (pénombre de
## contact), ni trop près de la pointe (pénombre de la portée), à n'importe
## quelle élévation de carte (25°-50°).
func _ground_sample_offset(elev_deg: float) -> float:
	var shadow_length := _GNOMON_HEIGHT / tan(deg_to_rad(elev_deg))
	return _GNOMON_RADIUS + 0.1 + 0.5 * shadow_length


func _ground_gnomon_world_center() -> Vector3:
	return Vector3(_GNOMON_CENTER_XZ.x, 0.0, _GNOMON_CENTER_XZ.y)


## Toujours dans l'ombre du gnomon (voir le commentaire de `_GNOMON_HEIGHT`) :
## un point sur l'axe de l'ombre, entre le socle et la pointe, quelle que soit
## l'élévation.
func _ground_shadow_point(elev_deg: float) -> Vector3:
	return _ground_gnomon_world_center() + _SHADOW_DIR_XZ * _ground_sample_offset(elev_deg)


## Symétrique de `_ground_shadow_point` : le soleil n'éclaire QUE le côté
## `+_SHADOW_DIR_XZ` (l'ombre s'y allonge, voir `_SHADOW_DIR_XZ`), donc le
## côté opposé, à la même distance, ne peut JAMAIS être dans l'ombre du
## gnomon -- aucune coïncidence à espérer, une conséquence directe de la
## géométrie.
func _ground_lit_point(elev_deg: float) -> Vector3:
	return _ground_gnomon_world_center() - _SHADOW_DIR_XZ * _ground_sample_offset(elev_deg)


## Vue plongeante verticale sur le gnomon (voir la constante
## `_GROUND_CAM_HEIGHT`) : les deux points échantillonnés, posés à plat sur le
## sol, ne peuvent jamais s'occulter l'un l'autre vus du dessus.
func _aim_ground() -> void:
	var center := _ground_gnomon_world_center()
	_cam.global_position = center + Vector3(0.0, _GROUND_CAM_HEIGHT, 0.0)
	_cam.look_at(center, Vector3(1.0, 0.0, 0.0))


func _measure_ground() -> void:
	var img := root.get_texture().get_image()
	var entry: Dictionary = _maps[_map_index]
	var map_id := String(entry["id"])
	var elev: float = Cartoon.map_palette(map_id)["sun_elevation_deg"]
	var lit_lab := _oklab_lab(_sample_pixel(img, _ground_lit_point(elev)))
	var shadow_lab := _oklab_lab(_sample_pixel(img, _ground_shadow_point(elev)))
	_current_ground_lit_l = lit_lab.x
	_current_ground_shadow_l = shadow_lab.x
	_current_ground_lit_hue = _oklab_hue_deg(lit_lab)
	_current_ground_shadow_hue = _oklab_hue_deg(shadow_lab)
	_save_shot(img, "ground")


## -- CHK-10/CHK-11 : largeur de trait sur l'objet de calibration d'arête ----

## Vue DE FACE (une seule face visible : silhouette pure, aucun pli) --
## distance caméra <-> face avant EXACTEMENT `_SIL_CAM_DIST_M` (30 m).
func _aim_silhouette() -> void:
	var half := _EDGE_BOX_SIZE * 0.5
	var center := _EDGE_BOX_CENTER
	var front_x := center.x - half.x
	_cam.global_position = Vector3(front_x - _SIL_CAM_DIST_M, center.y, center.z)
	_cam.look_at(center, Vector3.UP)


## CHK-10 : largeur de trait sur 4 arêtes (haut/bas/gauche/droite de la face
## avant) × `_SIL_EDGE_SAMPLES` points chacune, en excluant les coins (où la
## largeur d'un trait n'est pas définie sans ambiguïté).
func _measure_silhouette() -> void:
	var img := root.get_texture().get_image()
	var half := _EDGE_BOX_SIZE * 0.5
	var center := _EDGE_BOX_CENTER
	var front_x := center.x - half.x
	var widths: Array = []
	for i in range(1, _SIL_EDGE_SAMPLES + 1):
		var t := float(i) / float(_SIL_EDGE_SAMPLES + 1)  # évite les coins (0/1)
		var z := lerpf(center.z - half.z, center.z + half.z, t)
		var y := lerpf(center.y - half.y, center.y + half.y, t)
		# Haut/bas : lignes HORIZONTALES à l'écran (vue de face, up=Vector3.UP)
		# -> on scanne verticalement (axis=1) pour mesurer leur épaisseur.
		widths.append(_edge_stroke_width_px(img, Vector3(front_x, center.y + half.y, z), 1))
		widths.append(_edge_stroke_width_px(img, Vector3(front_x, center.y - half.y, z), 1))
		# Gauche/droite : lignes VERTICALES à l'écran -> on scanne
		# horizontalement (axis=0).
		widths.append(_edge_stroke_width_px(img, Vector3(front_x, y, center.z - half.z), 0))
		widths.append(_edge_stroke_width_px(img, Vector3(front_x, y, center.z + half.z), 0))
	var pass_count := 0
	var min_w := INF
	for w in widths:
		if w >= _CHK10_MIN_WIDTH_PX:
			pass_count += 1
		min_w = minf(min_w, w)
	_current_silhouette_widths = widths
	_current_silhouette_min_width = min_w if widths.size() > 0 else 0.0
	_current_silhouette_pass_fraction = float(pass_count) / float(maxi(widths.size(), 1))
	_save_shot(img, "silhouette")


## Vue de trois-quarts rasante (voir la constante `_CREASE_CAM_Z`) : montre
## la face latérale +Z de l'objet de calibration à un angle très oblique.
func _aim_crease() -> void:
	_cam.global_position = Vector3(0.0, _EDGE_BOX_CENTER.y, _CREASE_CAM_Z)
	_cam.look_at(_EDGE_BOX_CENTER, Vector3.UP)


## CHK-11 : recherche un double trait (pli + silhouette non fusionnés) entre
## l'arête de coin convexe (un pli) et l'arête lointaine de la face latérale
## (la vraie silhouette), à 3 hauteurs -- voir l'en-tête de fichier pour le
## raisonnement complet. Le défaut n'est retenu que s'il est PERSISTANT
## (présent aux 3 hauteurs, du bas au haut de l'objet) : `double_line_span_px`
## est alors l'écart en pixels-image entre la première et la dernière
## rangée, comparé à `double_line_min_len_px` (CHK-11).
func _measure_crease() -> void:
	var img := root.get_texture().get_image()
	var half := _EDGE_BOX_SIZE * 0.5
	var center := _EDGE_BOX_CENTER
	var corner_x := center.x - half.x
	var far_x := center.x + half.x
	var side_z := center.z + half.z
	var heights := [center.y - half.y * 0.6, center.y, center.y + half.y * 0.6]
	var rows: Array = []
	var all_double := true
	for h in heights:
		var crease_anchor := _project_to_image_px(img, Vector3(corner_x, h, side_z))
		var sil_anchor := _project_to_image_px(img, Vector3(far_x, h, side_z))
		var lo := mini(crease_anchor.x, sil_anchor.x) - _CREASE_SCAN_MARGIN_PX
		var hi := maxi(crease_anchor.x, sil_anchor.x) + _CREASE_SCAN_MARGIN_PX
		var runs := _ink_runs_in_row(img, crease_anchor.y, lo, hi)
		var double_here := _has_double_line(runs, _CHK11_GAP_PX)
		rows.append(crease_anchor.y)
		if not double_here:
			all_double = false
	var span := absf(float(rows[-1]) - float(rows[0])) if rows.size() > 1 else 0.0
	_current_double_line_detected = all_double and span >= _CHK11_MIN_LEN_PX
	_current_double_line_span_px = span
	_save_shot(img, "crease")


## -- Utilitaires bas niveau (pixels/projection) -----------------------------

## `Camera3D.unproject_position` renvoie des coordonnées dans l'espace du
## Viewport (1920×1080 -- `window/size/viewport_width/height`, project.godot),
## alors que la fenêtre RÉELLE (donc `img`, capturé depuis `root.get_texture()`)
## est étirée à 1280×800 (`window_width/height_override`, `stretch/mode
## ="canvas_items"`) : sans remise à l'échelle ici, les points échantillonnés
## tombent hors du cube (mesuré en pratique -- voir rapport de tâche).
func _sample_pixel(img: Image, world_point: Vector3) -> Color:
	var px := _project_to_image_px(img, world_point)
	return img.get_pixel(px.x, px.y)


func _project_to_image_px(img: Image, world_point: Vector3) -> Vector2i:
	var vp_size := _cam.get_viewport().get_visible_rect().size
	var screen := _cam.unproject_position(world_point)
	var scale_x := float(img.get_width()) / maxf(vp_size.x, 1.0)
	var scale_y := float(img.get_height()) / maxf(vp_size.y, 1.0)
	var x := clampi(int(round(screen.x * scale_x)), 0, img.get_width() - 1)
	var y := clampi(int(round(screen.y * scale_y)), 0, img.get_height() - 1)
	return Vector2i(x, y)


func _sample_oklab_l(img: Image, world_point: Vector3) -> float:
	return _oklab_lab(_sample_pixel(img, world_point)).x


func _save_shot(img: Image, tag: String) -> void:
	if not DirAccess.dir_exists_absolute(_out_dir):
		DirAccess.make_dir_recursive_absolute(_out_dir)
	var entry: Dictionary = _maps[_map_index]
	var map_id := String(entry["id"])
	img.save_png("%s/%s_%s.png" % [_out_dir, map_id, tag])


## `abs(dr,dg,db) <= tol` (distance euclidienne au carré, pour éviter une
## racine par pixel scanné) -- même principe que `find_glyph_components`
## (tools/review/style_check.py), tolérance locale pensée pour `Cartoon.INK`
## contre un fond peint saturé (jamais confondu avec les neutres charbon de
## l'UI, hors sujet ici puisqu'on ne scanne que des rendus 3D).
func _color_close(c: Color, target: Color, tol: float) -> bool:
	var dr := c.r - target.r
	var dg := c.g - target.g
	var db := c.b - target.b
	return (dr * dr + dg * dg + db * db) <= tol * tol


func _pixel_is_ink(img: Image, anchor: Vector2i, axis: int, offset: int) -> bool:
	var x := anchor.x + (offset if axis == 0 else 0)
	var y := anchor.y + (offset if axis == 1 else 0)
	if x < 0 or x >= img.get_width() or y < 0 or y >= img.get_height():
		return false
	return _color_close(img.get_pixel(x, y), Cartoon.INK, _INK_TOL)


## Décalage (le long de `axis`, depuis `anchor`) du pixel « encre » le plus
## proche, en spirale (0, +1, -1, +2, -2, ...) jusqu'à `radius` -- une petite
## erreur de projection/anti-aliasing entre l'arête analytique et son rendu
## réel est attendue, jamais un alignement pixel-parfait. Renvoie
## `radius + 1` (sentinelle) si rien n'est trouvé dans la fenêtre.
func _find_nearest_ink_offset(img: Image, anchor: Vector2i, axis: int, radius: int) -> int:
	if _pixel_is_ink(img, anchor, axis, 0):
		return 0
	for r in range(1, radius + 1):
		if _pixel_is_ink(img, anchor, axis, r):
			return r
		if _pixel_is_ink(img, anchor, axis, -r):
			return -r
	return radius + 1


## Étend le run de pixels « encre » qui contient `anchor + found_offset`
## dans les deux sens, jusqu'au premier pixel non-encre (ou au bord de
## l'image) -- la largeur de trait perpendiculaire à l'arête.
func _run_length_at(img: Image, anchor: Vector2i, axis: int, found_offset: int) -> int:
	var lo := found_offset
	while _pixel_is_ink(img, anchor, axis, lo - 1):
		lo -= 1
	var hi := found_offset
	while _pixel_is_ink(img, anchor, axis, hi + 1):
		hi += 1
	return hi - lo + 1


func _edge_stroke_width_px(img: Image, world_point: Vector3, scan_axis: int) -> float:
	var anchor := _project_to_image_px(img, world_point)
	var found := _find_nearest_ink_offset(img, anchor, scan_axis, _SIL_SCAN_RADIUS_PX)
	if found > _SIL_SCAN_RADIUS_PX:
		return 0.0
	return float(_run_length_at(img, anchor, scan_axis, found))


## Composantes connexes horizontales de pixels « encre » sur la rangée `y`,
## restreintes à `[x0, x1]` -- une liste de paires `[début, fin]` (inclusif).
func _ink_runs_in_row(img: Image, y: int, x0: int, x1: int) -> Array:
	var runs: Array = []
	var w := img.get_width()
	var h := img.get_height()
	if y < 0 or y >= h:
		return runs
	var cx0 := clampi(x0, 0, w - 1)
	var cx1 := clampi(x1, 0, w - 1)
	var run_start := -1
	for x in range(cx0, cx1 + 1):
		var is_ink := _color_close(img.get_pixel(x, y), Cartoon.INK, _INK_TOL)
		if is_ink and run_start == -1:
			run_start = x
		elif not is_ink and run_start != -1:
			runs.append([run_start, x - 1])
			run_start = -1
	if run_start != -1:
		runs.append([run_start, cx1])
	return runs


## Vrai si au moins deux runs sont séparés par au moins `gap_px` pixels
## non-encre -- CHK-11 (« double_line_gap_px »).
func _has_double_line(runs: Array, gap_px: int) -> bool:
	if runs.size() < 2:
		return false
	for i in range(runs.size() - 1):
		var gap: int = runs[i + 1][0] - runs[i][1] - 1
		if gap >= gap_px:
			return true
	return false


func _record_map_result() -> void:
	var entry: Dictionary = _maps[_map_index]
	var map_id := String(entry["id"])
	var lit_pass := absf(_current_lit_l - _TARGET_LIT_L) <= _TARGET_LIT_L_TOLERANCE
	var ratio := (_current_shadow_l / _current_lit_l) if _current_lit_l > 0.0 else 0.0
	var ratio_pass := ratio >= _TARGET_SHADOW_RATIO.x and ratio <= _TARGET_SHADOW_RATIO.y

	var ground_ratio := (_current_ground_shadow_l / _current_ground_lit_l) if _current_ground_lit_l > 0.0 else 0.0
	var hue_delta := _hue_delta_deg(_current_ground_lit_hue, _current_ground_shadow_hue)
	# Informatif seulement (voir l'en-tête de fichier) : le gate réel est
	# tools/review/style_check.py, depuis tokens.json.
	var ground_pass := (
		ground_ratio >= _CHK09_SHADOW_RATIO.x and ground_ratio <= _CHK09_SHADOW_RATIO.y
		and _current_ground_shadow_l >= _CHK09_SHADOW_MIN_L
		and hue_delta <= _CHK09_HUE_TOLERANCE_DEG
	)
	var silhouette_pass := (
		_current_silhouette_min_width >= _CHK10_MIN_WIDTH_PX
		and _current_silhouette_pass_fraction >= _CHK10_PERIMETER_FRACTION
	)

	_results.append({
		"map_id": map_id,
		"sun_elevation_deg": Cartoon.map_palette(map_id)["sun_elevation_deg"],
		"lit_L": _current_lit_l,
		"lit_L_pass": lit_pass,
		"shadow_L": _current_shadow_l,
		"shadow_ratio": ratio,
		"shadow_ratio_pass": ratio_pass,
		"ground_lit_L": _current_ground_lit_l,
		"ground_shadow_L": _current_ground_shadow_l,
		"ground_shadow_ratio": ground_ratio,
		"ground_lit_hue_deg": _current_ground_lit_hue,
		"ground_shadow_hue_deg": _current_ground_shadow_hue,
		"ground_hue_delta_deg": hue_delta,
		"ground_pass(OPS-11)": ground_pass,
		"silhouette_widths_px": _current_silhouette_widths,
		"silhouette_min_width_px": _current_silhouette_min_width,
		"silhouette_pass_fraction": _current_silhouette_pass_fraction,
		"silhouette_pass(OPS-11)": silhouette_pass,
		"double_line_detected": _current_double_line_detected,
		"double_line_span_px": _current_double_line_span_px,
	})
	print("LOOK_PROBE_MAP %s lit_L=%.4f pass=%s shadow_L=%.4f ratio=%.4f pass(ART-02)=%s" % [
		map_id, _current_lit_l, lit_pass, _current_shadow_l, ratio, ratio_pass,
	])
	print("LOOK_PROBE_GROUND %s ground_lit_L=%.4f ground_shadow_L=%.4f ratio=%.4f hue_delta_deg=%.1f pass(OPS-11)=%s" % [
		map_id, _current_ground_lit_l, _current_ground_shadow_l, ground_ratio, hue_delta, ground_pass,
	])
	print("LOOK_PROBE_SILHOUETTE %s min_width_px=%.2f pass_fraction=%.2f double_line=%s span_px=%.1f" % [
		map_id, _current_silhouette_min_width, _current_silhouette_pass_fraction, _current_double_line_detected, _current_double_line_span_px,
	])


func _advance() -> bool:
	_map_index += 1
	if _map_index < _maps.size():
		_phase = "load_map"
		return false
	_finish()
	return true


func _finish() -> void:
	var all_lit_pass := true
	for r in _results:
		if not (r["lit_L_pass"] as bool):
			all_lit_pass = false
	var summary := {
		"generated_at": Time.get_datetime_string_from_system(true),
		"calibration": {
			"albedo": "#D2A46C",
			"target_lit_L": _TARGET_LIT_L,
			"target_lit_L_tolerance": _TARGET_LIT_L_TOLERANCE,
			"target_shadow_ratio": [_TARGET_SHADOW_RATIO.x, _TARGET_SHADOW_RATIO.y],
		},
		"maps": _results,
		"summary": {
			"all_lit_L_pass": all_lit_pass,
			"note": "shadow_ratio (CHK-01, partie ombre) et les champs ground_*/silhouette_*/double_line_* (CHK-09/10/11, OPS-11) sont mesurés et rapportés ; leur PASS/WARN/FAIL réel est calculé par tools/review/style_check.py depuis tokens.json -- aucun des trois ne fait jamais échouer cette sonde (seul CHK-01 pilote le code de sortie).",
		},
	}
	if not DirAccess.dir_exists_absolute(_out_json.get_base_dir()):
		DirAccess.make_dir_recursive_absolute(_out_json.get_base_dir())
	var f := FileAccess.open(_out_json, FileAccess.WRITE)
	if f == null:
		print("LOOK_PROBE_FAIL impossible d'écrire %s (err=%s)" % [_out_json, FileAccess.get_open_error()])
		quit(1)
		return
	f.store_string(JSON.stringify(summary, "\t"))
	f.close()
	if all_lit_pass:
		print("LOOK_PROBE_OK ", _out_json)
		quit(0)
	else:
		print("LOOK_PROBE_FAIL CHK-01 (partie éclairée) ne passe pas sur au moins une carte -- voir ", _out_json)
		quit(1)


func _fail(reason: String) -> bool:
	print("LOOK_PROBE_FAIL ", reason)
	_failed = true
	quit(1)
	return true


# ------------------------------------------------------------------ OKLab L
# Conversion standard de Björn Ottosson (https://bottosson.github.io/posts/
# oklab/), auto-contenue ici : aucun utilitaire OKLab partagé n'existe encore
# dans le dépôt (même remarque que tests/agents/test_agent_palette.gd,
# ART-14 -- pas dans mon périmètre de le factoriser, voir la liste de
# fichiers de mon contrat).
static func _srgb_to_linear(c: float) -> float:
	if c <= 0.04045:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)


## (L, a, b) OKLab complet -- `_oklab_lab(color).x` est équivalent à
## l'ancien `_oklab_l(color)` (CHK-01, inchangé) ; `a`/`b` servent au calcul
## de teinte OKLCH de CHK-09 (`_oklab_hue_deg`).
static func _oklab_lab(color: Color) -> Vector3:
	var r := _srgb_to_linear(color.r)
	var g := _srgb_to_linear(color.g)
	var b := _srgb_to_linear(color.b)

	var l := 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
	var m := 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
	var s := 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

	var l_ := signf(l) * pow(absf(l), 1.0 / 3.0)
	var m_ := signf(m) * pow(absf(m), 1.0 / 3.0)
	var s_ := signf(s) * pow(absf(s), 1.0 / 3.0)

	return Vector3(
		0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
	)


static func _oklab_hue_deg(lab: Vector3) -> float:
	var h := rad_to_deg(atan2(lab.z, lab.y))
	return fmod(h + 360.0, 360.0)


## Écart circulaire (jamais > 180°) entre deux teintes OKLCH en degrés.
static func _hue_delta_deg(a: float, b: float) -> float:
	var d := fmod(absf(a - b), 360.0)
	return minf(d, 360.0 - d)
