## MainMenu.gd — Lobby v4 « Encre, jaune, italique » (UX-32/UX-37,
## docs/UI_DIRECTION_BL3.md §4/§6, sur les fondations UX-30 : Comic.gd
## title_font_v4/SIZE_*/plate_style/ink_label, KitSwash, KitSlantTile —
## remplace la mise en page v3 « Bric-à-brac peint », jugée « amateur,
## illisible, encombrée » par l'utilisateur le 2026-09-25).
##
## Pile de navigation alignée à gauche (x = 120, §6 « Menu principal ») :
## JOUER en 118 px, encre sur UN SEUL pinceau jaune (KitSwash) + résumé
## 28 px, puis AGENTS/ARSENAL/OPTIONS/QUITTER en 66 px papier — remplace la
## barre d'onglets + le logo autocollant v3. JOUER reste le CTA « 1 clic »
## (UX-08, `_host_btn`, inchangé pour les tests verrouillés) : son panneau
## « Partie personnalisée » (mode/carte/bots/difficulté/IP, repliée par
## défaut) vit directement sous le résumé, sans plaque autour (§4.5 « zéro
## fond » étendu à ce panneau : les widgets qu'il contient — KitSlantBar/
## KitCard, ART-31, INCHANGÉS — portent déjà leur propre relief).
##
## Décor : UN SEUL agent (le sélectionné) debout à droite, encre 4 px
## (`Cartoon.character()`, contour d'équipe désactivé — `Color(0,0,0,0)`),
## devant un fond peint (`_build_backdrop()`, ci-dessous) — pas trois podiums
## neutres comme en v3.
##
## UX-37 (retour lead 2026-09-25, §1) : le fond était une rue procédurale
## codée à la main (5-40 `BoxMesh`/`CylinderMesh`) qui ne ressemblait à aucune
## VRAIE carte, alors que la carte affichée en dessous annonçait
## PORT-FERRAILLE — « le fond doit être la VRAIE Wasteland (vue Grand-Rue) ».
## Décision (direction §6 : « scène réelle chargée en arrière-plan OU capture
## peinte pré-rendue... menu interactif < 3 s ») : la capture pré-rendue,
## jamais la scène réelle. Charger `scenes/levels/maps/wasteland.tscn` (ou
## même juste `MapSetup.gd` seul, hors de mon périmètre) chargerait une
## géométrie ET un `GameMode` couplés au réseau/à `MatchConfig.mode_id`
## (`_build_game_mode`, `TDMMode`/`HardpointMode`) — un couplage de gameplay
## hors sujet et risqué pour un simple décor de menu, pour un gain de fidélité
## marginal face à une capture RÉELLE de la carte. `_build_backdrop()` pose
## donc un grand quad texturé, loin derrière l'agent, avec la capture la plus
## récente de la vue "Grand-Rue" de Wasteland (`tools/map_shots.gd`, lu jamais
## modifié — `reports/checkpoints/2026-09-25_LD-43/wasteland_grand_rue.jpg`,
## copiée telle quelle dans `assets/ui/menu/`, liste de fichiers de cette
## tâche) : une texture à charger, pas une scène à construire — largement sous
## les 3 s exigés par le critère d'acceptation, et vraiment "la vraie
## Wasteland" plutôt qu'une reconstitution approximative.
##
## Le ciel/l'éclairage procéduraux (`_build_world()`, INCHANGÉS) restent pour
## l'éclairage ambiant de l'agent (`Environment.ambient_light_source`) — le
## quad de fond les recouvre visuellement, voir `_build_backdrop()`.
##
## Dégradé d'encre à gauche (`InkGradient`, §6) sous tout le reste : assure
## la lisibilité du texte papier par-dessus le fond sans jamais poser de
## boîte derrière (§5 règle 1, étendue au menu).
extends Node3D

## Repli tant que R3-MAPS n'a pas livré MapCatalog.gd (chargement dynamique :
## voir `_map_catalog()` — pas de dépendance statique pour ne jamais casser
## le boot si le fichier n'existe pas encore).
const MAP_CATALOG_PATH := "res://scripts/levels/maps/MapCatalog.gd"
const FALLBACK_SCENES := {
	"tdm": "res://scenes/levels/tdm_map.tscn",
	"hardpoint": "res://scenes/levels/comp_map.tscn",
	"snd": "res://scenes/levels/snd_map.tscn",
	"duel": "res://scenes/levels/duel_arena.tscn",
	"duo": "res://scenes/levels/duel_arena.tscn",
}
const MODE_LABELS := {
	"tdm": "Arène — Match à mort",
	"hardpoint": "Arène — Hardpoint",
	"snd": "Tactique — Recherche & Destruction",
	"duel": "Duel (1v1)",
	"duo": "Duo (2v2)",
}
## Étiquettes courtes pour le sélecteur segmenté (compact, 1 ligne par mode —
## retour lead R3 : la liste verticale à description faisait déborder la carte).
const SHORT_MODE_LABELS := {
	"tdm": "Arène",
	"hardpoint": "Hardpoint",
	"snd": "Tactique",
	"duel": "Duel",
	"duo": "Duo",
}
const MODE_DESCRIPTIONS := {
	"tdm": "4v4 sans économie, capacités actives. Premier à 40 éliminations.",
	"hardpoint": "4v4, capture un point qui se déplace toutes les 60 s.",
	"snd": "4v4 par manches, achat d'armes, pose/désamorçage de bombe.",
	"duel": "1 contre 1, sans capacités, équipement imposé.",
	"duo": "2 contre 2, sans capacités, équipement imposé.",
}
const DIFFICULTY_LABELS := ["Recrue", "Vétéran", "Élite"]

## Numérotation des cartes (design.md v2 §7, ordre du catalogue "flagship
## d'abord") — affichage "07 · WASTELAND" (direction v4 §6). Indépendant de
## l'ORDRE de MapCatalog.all() (lu, jamais modifié ici) : reste correct même
## si une carte listée ici n'existe pas encore côté MapCatalog.
const MAP_NUMBERS := {
	"port_ferraille": 1, "val_poussiere": 2, "saint_ombre": 3,
	"col_du_vautour": 4, "la_fosse": 5, "le_belvedere": 6,
	"wasteland": 7, "cargo_ship": 8,
}

const OPTIONS_SCRIPT := preload("res://scripts/ui/OptionsMenu.gd")
const ARSENAL_SCRIPT := preload("res://scripts/ui/ArsenalMenu.gd")
const AGENT_SCRIPT := preload("res://scripts/ui/AgentMenu.gd")

const TAB_PLAY := 0
const TAB_AGENTS := 1
const TAB_ARSENAL := 2
const TAB_OPTIONS := 3
const TAB_LABELS := ["JOUER", "AGENTS", "ARSENAL", "OPTIONS"]

const CHAR_MODEL_DIR := "res://assets/models/characters/"
## Contour d'encre de l'agent affiché (direction v4 §6 « agent choisi debout
## en 3D à droite, encre 4 px ») — `Cartoon.character()` (API PUBLIQUE,
## scripts/core/Cartoon.gd, hors périmètre de cette tâche) plutôt que
## `Cartoon.character_surface()` (v3, sans passe de contour).
const AGENT_INK_OUTLINE_PX := 4.0

const MODE_BAR_HEIGHT := 56.0
## Colonnes du sélecteur de mode (QA ART-32 : 5 barres sur 1 seule ligne dans
## le panneau tronquaient « Hardpoint »/« Tactique ») — 3 colonnes (2 rangées)
## laisse une marge ≥ 16 % même pour « HARDPOINT ». INCHANGÉ par UX-32 (le
## panneau « Partie personnalisée » garde ses widgets v3 KitSlantBar/KitCard
## tels quels, voir la docstring d'en-tête).
const MODE_GRID_COLUMNS := 3
const MAP_CARD_HEIGHT := 92.0
## Colonnes de la grille de cartes (QA ART-32 : à 2 colonnes, une carte ne
## laissait pas assez de place aux noms longs) — INCHANGÉ par UX-32.
const MAP_GRID_COLUMNS := 1
const MAP_GRID_VISIBLE_H := MAP_CARD_HEIGHT * 2.0 + Comic.SP_1

## Pile de navigation (direction v4 §6 « Pile à x = 120 ») : marge gauche et
## largeur de colonne, aux jetons `Comic.SP_*`/`Comic.SAFE_MARGIN` existants
## (aucune valeur de couleur ad hoc — seules des positions/largeurs, comme
## `MODE_BAR_HEIGHT`/`MAP_CARD_HEIGHT` ci-dessus, déjà des constantes libres
## en v3).
const NAV_X := 120.0
const NAV_WIDTH := 640.0
## Mesuré (UX-38, capture 1080p, APRÈS le correctif `_finalize_swash_host_
## size()` ci-dessous — le bug qu'il corrige sous-dimensionnait le host de
## JOUER d'environ 100 px, ce qui masquait à tort tout le budget vertical
## manquant ici) : JOUER (118 px, host réel ~186 px avec pinceau + anneau de
## focus) + résumé + le panneau « Partie personnalisée » replié (qui réserve
## sa hauteur même replié, ses enfants masqués compris) + AGENTS/ARSENAL/
## OPTIONS/QUITTER (66 px) tiennent sur ~765 px avec un espacement
## `Comic.SP_3` — `NAV_TOP` (jeton `Comic.SAFE_MARGIN`, même marge que la
## plaque joueur en haut à droite) laisse une marge confortable sous la
## plaque « carte courante » (bas-gauche, ancrée à `Comic.SAFE_MARGIN` du
## bas) pour qu'ELLE NE RECOUVRE JAMAIS QUITTER, la dernière entrée de la pile
## (~32 px de marge à 1080p).
const NAV_TOP := Comic.SAFE_MARGIN
const NAV_SEPARATION := Comic.SP_3
const MAP_PLATE_WIDTH := 460.0
const PLAYER_PLATE_WIDTH := 300.0

var _mode_id: String = MatchConfig.mode_id
var _map_choice: Dictionary = {}
var _mode_cards: Array = []
var _map_cards: Array = []
var _map_list: GridContainer
var _diff_buttons: Array = []
var _bots_check: CheckButton
var _host_btn: Button
var _play_summary: Label
## Bascule « Partie personnalisée » (UX-08) : mode/carte/bots/difficulté et le
## multijoueur (IP + Rejoindre) restent repliés par défaut — le joueur qui ne
## touche à rien n'a qu'UNE surface cliquable (le bouton JOUER), et retrouve
## sa dernière configuration mémorisée (MatchConfig.load_last()) sans avoir à
## rouvrir ce panneau. Ne s'ouvre que sur demande explicite.
var _custom_panel: VBoxContainer
var _custom_toggle_btn: Button
var _custom_open: bool = false
var _ip_field: LineEdit
var _join_btn: Button
var _status: ComicPanel
var _status_label: Label
var _retry_btn: Button
var _retry_action: Callable = Callable()
var _net: NetworkManager
var _loading_t: float = -1.0

# UI
var _tab_index: int = TAB_PLAY
var _content: Control
## Chrome complet du menu (pile de navigation, carte courante, plaque joueur,
## touches) — un SEUL nœud plein-cadre, montré pour TAB_PLAY et masqué pour
## les autres onglets (AGENTS/ARSENAL/OPTIONS prennent tout l'écran via
## `_embedded`) : garantit qu'un SEUL pinceau jaune (le JOUER de cette pile)
## est visible à la fois, jamais un second en même temps qu'un swash propre à
## un écran embarqué (critère d'acceptation « un seul swash »).
var _play_panel: Control
var _embedded: Control
var _map_plate_title: Label
var _map_plate_desc: Label
var _player_plate_agent: Label
## Référencé par tests/ui/test_main_menu.gd (critère d'acceptation « garder
## toutes les entrées actuelles » : QUITTER, ex-bouton de la barre du haut
## v3, doit rester atteignable clavier/manette dans la pile v4).
var _quit_btn: Button

# Décor
var _cam: Camera3D
var _char_root: Node3D
var _char: Node3D
var _last_agent_shown: int = -1
var _t: float = 0.0
## Environnement du ciel (`_build_world()`) — référencé par
## `test_sky_gradient_is_not_a_near_flat_band` pour vérifier que le dégradé a
## assez d'écart de valeur pour ne pas bander (éclairage ambiant de l'agent,
## voir la docstring de tête « UX-37 »).
var _environment: Environment
## Fond peint (`_build_backdrop()`) — référencé par
## `test_backdrop_uses_the_real_wasteland_capture` (UX-37) pour vérifier que
## le fond du menu est bien la capture RÉELLE de Wasteland, jamais un décor
## procédural.
var _backdrop: MeshInstance3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Settings.load_all()
	# Dernier mode/carte/bots/difficulté joués (UX-08) — fichier absent au
	# premier lancement : les défauts de MatchConfig restent (TDM, bots
	# activés, Vétéran = « Arène vs bots »). Resynchronise `_mode_id` : son
	# initialisation de champ (au-dessus) a figé `MatchConfig.mode_id` AVANT
	# que ce chargement n'ait pu s'exécuter.
	MatchConfig.load_last()
	_mode_id = MatchConfig.mode_id
	_net = NetworkManager.get_net(get_tree())
	_net.disconnect_from_game()
	_net.connection_succeeded.connect(_on_connected)
	_net.connection_failed.connect(_on_failed)
	_build_world()
	_build_ui()
	_show_tab(TAB_PLAY)
	call_deferred("_focus_play")

func _process(delta: float) -> void:
	_t += delta
	if _cam:
		var sway := sin(_t * 0.22) * 1.2
		_cam.position = Vector3(0.4 + sway, 2.3, 7.6)
		_cam.look_at(Vector3(0.9 + sway * 0.2, 1.35, 0.0))
	if is_instance_valid(_char):
		_char.position.y = 0.06 + sin(_t * 1.8) * 0.05
		_char.rotation.y = sin(_t * 0.5) * 0.1
	if _tab_index == TAB_PLAY and AgentDatabase.selected_index != _last_agent_shown:
		_refresh_lobby_characters()
	if _loading_t >= 0.0:
		_loading_t += delta
		if _loading_t > 1.0:
			_status_label.text = "Connexion au serveur… %d s" % int(_loading_t)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_tab_next"):
		_show_tab((_tab_index + 1) % TAB_LABELS.size())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_tab_prev"):
		_show_tab((_tab_index - 1 + TAB_LABELS.size()) % TAB_LABELS.size())
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- Décor
func _build_world() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -35, 0)
	key.light_energy = 1.1
	key.light_color = Color(0.98, 0.94, 0.86)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, 150, 0)
	rim.light_energy = 1.3
	rim.light_color = Color(0.7, 0.76, 0.9)
	add_child(rim)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skymat := ProceduralSkyMaterial.new()
	# Ciel bleu d'après-midi -> horizon ocre (mockup `bl3_menu.png` ; l'ocre
	# reprend `WastelandLook.FOG_TINT_OCRE`, même ton que la vraie carte) —
	# remplace les jetons `plate`/`plate_hi` (quasi noirs, trop proches en
	# valeur : c'est l'écart de valeur trop faible entre les arrêts du
	# dégradé qui rendait la quantification 8 bits visible en bandes).
	skymat.sky_top_color = Color("3e6fa6")
	skymat.sky_horizon_color = Color("e8c179")
	skymat.sky_curve = 0.12
	skymat.ground_horizon_color = Color("e8c179")
	skymat.ground_bottom_color = Color("5c4a34")
	skymat.ground_curve = 0.12
	sky.sky_material = skymat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	_environment = env
	add_child(we)

	_build_backdrop()

	_char_root = Node3D.new()
	add_child(_char_root)

	_cam = Camera3D.new()
	_cam.fov = _CAM_FOV_DEG
	_cam.position = Vector3(0.4, 2.3, 7.6)
	add_child(_cam)
	_cam.current = true

	_refresh_lobby_characters()

## Fond peint = capture RÉELLE de Wasteland (voir la docstring de tête
## « UX-37 ») : un grand quad texturé, loin derrière l'agent (`_BACKDROP_
## DISTANCE`), assez grand pour dépasser tout le cadre de la caméra (`_cam`,
## fov 50°, position/balancement fixés dans `_build_world()`/`_process()` —
## marge ×1.25 pour ne jamais laisser un bord de l'image visible malgré le
## balancement) et cadré dans le RATIO RÉEL de la capture (`_BACKDROP_
## IMAGE_ASPECT`, jamais l'aspect de la caméra : une texture étirée à un
## aspect différent du sien déformerait la rue peinte).
const _BACKDROP_IMAGE := "res://assets/ui/menu/wasteland_grand_rue.jpg"
## UX-38 (retour lead 2026-09-25, §1) : recadré depuis une NOUVELLE capture
## `tools/map_shots.gd` (vue nommée "grand_rue", lue jamais modifiée ; voir
## reports/checkpoints/2026-09-25_UX-38/) — la capture UX-37 collait un
## accessoire de décor à texture fissurée sur toute la moitié droite du cadre
## (« gros bloc à texture de béton fissuré étirée collé à la caméra »),
## recadré ici à 760x800 (`grand_rue.png`, x 0-760) pour ne garder que la rue,
## les façades peintes, le ciel et le repère (grue + réservoir) — jamais cet
## accessoire.
const _BACKDROP_IMAGE_ASPECT := 760.0 / 800.0
const _BACKDROP_DISTANCE := 20.0
const _BACKDROP_MARGIN := 1.25
const _BACKDROP_HEIGHT_Y := 2.3  # centré sur la hauteur de la caméra (voir _build_world).
## `_cam` n'existe pas encore au moment de `_build_backdrop()` (construite
## AVANT dans `_build_world()`) : FOV vertical de la caméra du lobby, dupliqué
## ici une seule fois plutôt que de réordonner `_build_world()` — DOIT rester
## égal à `_cam.fov`, posé juste après dans `_build_world()`.
##
## UX-38 (retour lead §1 « agent à taille héroïque, ~70 % de la hauteur
## d'écran ») : mesuré à 50° (v3/UX-37), l'agent Tripo (~1,8 m) n'occupait
## qu'un quart de la hauteur d'écran à sa distance de caméra actuelle — une
## FOV resserrée grossit l'agent SANS toucher un seul autre paramètre de
## scène : le fond (`_build_backdrop()`, ci-dessus) recalcule déjà la taille
## de son quad à partir de CETTE MÊME constante (`tan(fov/2)`), donc il reste
## TOUJOURS cadré pile sur le bord de caméra, quelle que soit la FOV — seul
## l'agent (une géométrie 3D à taille RÉELLE fixe, contrairement au quad du
## fond qui s'auto-ajuste) grossit à l'écran. Vérifié en capture 1080p
## (reports/checkpoints/2026-09-25_UX-38/) : ~73 % de la hauteur d'écran à 21°.
const _CAM_FOV_DEG := 21.0

func _build_backdrop() -> void:
	var cam_to_plane := _BACKDROP_DISTANCE + 7.6  # 7.6 == Camera3D.position.z, fixé ci-dessous.
	var half_h := cam_to_plane * tan(deg_to_rad(_CAM_FOV_DEG * 0.5)) * _BACKDROP_MARGIN
	# Largeur = cadre horizontal réel (16:9, même marge) ; hauteur dérivée du
	# ratio de la CAPTURE (1280x800 = 1,6 — plus « carré » que 16:9 = 1,778),
	# donc TOUJOURS plus grande que `half_h * 2` — jamais besoin d'un second
	# calcul pour couvrir la hauteur, un seul ratio (celui de la capture)
	# gouverne tout le quad, jamais d'étirement de la rue peinte.
	var width := half_h * 2.0 * (16.0 / 9.0)
	var height := width / _BACKDROP_IMAGE_ASPECT

	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	_backdrop = MeshInstance3D.new()
	_backdrop.mesh = quad
	_backdrop.position = Vector3(0.0, _BACKDROP_HEIGHT_Y, -_BACKDROP_DISTANCE)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(_BACKDROP_IMAGE)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_backdrop.material_override = mat
	add_child(_backdrop)

## Reconstruit le modèle d'agent affiché (direction v4 §6 : UN SEUL agent,
## le sélectionné, debout à droite — pas trois podiums v3). Recalculé au
## retour sur l'onglet JOUER si la sélection a changé dans l'onglet Agents.
func _refresh_lobby_characters() -> void:
	if is_instance_valid(_char):
		_char.queue_free()
	_char = null
	_last_agent_shown = AgentDatabase.selected_index
	var agents := AgentDatabase.all()
	if agents.is_empty() or _char_root == null:
		return
	var idx := posmod(AgentDatabase.selected_index, agents.size())
	var agent: AgentConfig = agents[idx]
	var node := _load_character_model(agent)
	if node == null:
		return
	node.position = Vector3(2.4, 0.0, 0.4)
	_char_root.add_child(node)
	_char = node
	_refresh_player_plate_agent(agent)

## Instancie assets/models/characters/<id>.glb, joue "Idle", recolore chaque
## slot matériau via `Cartoon.character(color, AGENT_INK_OUTLINE_PX, ...)`
## (même convention de suffixe que tools/character_shots.gd : "<id>_<slot>").
##
## `selected` (UX-38, tests/ui/test_agent_portraits.gd) : `_refresh_lobby_
## characters()` n'appelle JAMAIS cette fonction qu'avec le défaut (`true`) —
## un seul agent, toujours le choisi, reste affiché dans la vitrine (UX-32,
## voir la docstring de `_apply_character_materials`). Le paramètre existe
## pour garder une signature à deux arguments STABLE avec ces tests (qui
## vérifient qu'un modèle chargé `selected=false` garde sa texture peinte mais
## désature sa teinte) : utile si un futur écran affiche plusieurs modèles
## côte à côte (ex. sélection 3D multi-agents), sans dupliquer cette fonction.
func _load_character_model(agent: AgentConfig, selected: bool = true) -> Node3D:
	var id := agent.agent_name.to_lower()
	var path := "%s%s.glb" % [CHAR_MODEL_DIR, id]
	if not ResourceLoader.exists(path):
		push_warning("MainMenu: modèle agent introuvable (%s)" % path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate() as Node3D
	if root == null:
		return null
	var anim := _find_typed(root, "AnimationPlayer") as AnimationPlayer
	if anim:
		_play_idle(anim)
	_apply_character_materials(root, id, agent.color, selected)
	return root

## `Animation.has_animation("Idle")` ne couvre que la bibliothèque "" (globale) ;
## le glTF importe parfois les clips dans une bibliothèque nommée — on essaie
## le nom nu puis un suffixe qui correspond dans toutes les bibliothèques
## (même repli que tools/character_shots.gd::_play).
func _play_idle(anim: AnimationPlayer) -> void:
	if anim.has_animation("Idle"):
		anim.play("Idle")
		return
	for lib_name in anim.get_animation_library_list():
		var lib := anim.get_animation_library(lib_name)
		if lib and lib.has_animation("Idle"):
			anim.play("Idle" if lib_name == "" else "%s/Idle" % lib_name)
			return

## UX-20 — un agent Tripo riggé (docs/3D_PIPELINE.md, ex. Verrou) porte UN
## SEUL matériau nommé `<id>_tex`, pas de slots outfit/cloth/gear/skin/accent
## — sa texture 2K déjà peinte porte TOUTE la couleur.
## `mat_name.ends_with("_tex")` est testé EN PREMIER (même priorité que
## PlayerLook.gd::_apply_character_materials / tools/character_shots.gd::
## _apply_cartoon_materials) et garde `albedo_texture` au lieu de le jeter :
## `character()`/`character_surface()` posent `albedo_color` comme un
## MULTIPLICATEUR de la texture (`ink_toon.gdshader` `base *= tex_color`),
## donc blanc = texture inchangée. UX-32 : la vitrine du menu (`_refresh_
## lobby_characters()`) affiche toujours pleine couleur + contour 4 px
## (`Cartoon.character()`, PUBLIQUE) — un seul agent affiché, toujours le
## choisi, plus de podiums voisins. `selected` (UX-38) reste néanmoins
## honoré ici (jamais un paramètre mort : `Color.WHITE`/`accent_color` restent
## la texture/le slot INCHANGÉS quand `selected` est vrai, exactement le
## comportement UX-32 par défaut) — un modèle chargé `selected=false` désature
## sa teinte vers `Comic.paper_dim_color()` SANS jamais perdre sa texture
## peinte (`use_albedo_texture` reste vrai), pour un futur écran à plusieurs
## modèles (voir la docstring de `_load_character_model`).
func _apply_character_materials(model: Node3D, id: String, accent_color: Color, selected: bool = true) -> void:
	var dim := Comic.paper_dim_color()
	for mesh in _find_mesh_instances(model):
		if mesh.mesh == null:
			continue
		mesh.extra_cull_margin = 2.0
		for i in mesh.mesh.get_surface_count():
			var mat: Material = mesh.mesh.surface_get_material(i)
			var mat_name: String = mat.resource_name if mat else ""
			var base: BaseMaterial3D = mat as BaseMaterial3D
			if mat_name.ends_with("_tex"):
				var tex_tint := Color.WHITE if selected else dim
				var textured := Cartoon.character(tex_tint, AGENT_INK_OUTLINE_PX, Color(0, 0, 0, 0), mesh.mesh)
				if base and base.albedo_texture != null:
					textured.set_shader_parameter("use_albedo_texture", true)
					textured.set_shader_parameter("use_triplanar", false)
					textured.set_shader_parameter("albedo_texture", base.albedo_texture)
				mesh.set_surface_override_material(i, textured)
				continue
			if not mat_name.begins_with(id + "_"):
				continue
			var slot := mat_name.substr(id.length() + 1)
			var exported_color: Color = base.albedo_color if base else Color.WHITE
			var tint := (accent_color if slot == "cloth" else exported_color) if selected else dim
			mesh.set_surface_override_material(i, Cartoon.character(tint, AGENT_INK_OUTLINE_PX, Color(0, 0, 0, 0), mesh.mesh))

func _find_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_mesh_instances(c))
	return out

func _find_typed(n: Node, class_name_str: String) -> Node:
	if n.get_class() == class_name_str:
		return n
	for c in n.get_children():
		var r := _find_typed(c, class_name_str)
		if r:
			return r
	return null

# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_build_ink_gradient(root)

	_content = Control.new()
	Comic.anchor(_content, Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_content)

	# Chrome plein-cadre du menu (voir la docstring de `_play_panel`) : un
	# SEUL nœud, montré/masqué en bloc par `_show_tab()`.
	_play_panel = Control.new()
	Comic.anchor(_play_panel, Control.PRESET_FULL_RECT)
	_play_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_play_panel)

	_build_nav(_play_panel)
	_build_current_map_plate(_play_panel)
	_build_player_plate(_play_panel)
	_build_key_hints(_play_panel)

## Dégradé d'encre à gauche (direction v4 §6) : lisibilité du texte papier
## posé sur la 3D, sans jamais de boîte derrière (§5 règle 1).
func _build_ink_gradient(root: Control) -> void:
	var grad := InkGradient.new()
	Comic.anchor(grad, Control.PRESET_FULL_RECT)
	root.add_child(grad)

## Pile de navigation (direction v4 §6 « Pile à x = 120 ») : JOUER (encre sur
## pinceau jaune, 118 px) + résumé, panneau « Partie personnalisée » replié,
## puis AGENTS/ARSENAL/OPTIONS/QUITTER (66 px papier) — remplace la barre
## d'onglets + le logo autocollant v3.
func _build_nav(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", NAV_SEPARATION)
	Comic.anchor(col, Control.PRESET_LEFT_WIDE)
	col.offset_left = NAV_X
	col.offset_top = NAV_TOP
	col.custom_minimum_size = Vector2(NAV_WIDTH, 0)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(col)

	_host_btn = _build_host_button()
	var host := _wrap_with_swash(_host_btn, _host_btn.text)
	col.add_child(host)
	_finalize_swash_host_size(host, _host_btn)

	_play_summary = Comic.body_label_v4("", Comic.SIZE_28, Comic.paper_dim_color())
	col.add_child(_play_summary)

	col.add_child(_build_play_extra_panel())

	col.add_child(_build_nav_item("AGENTS", _on_tab.bind(TAB_AGENTS)))
	col.add_child(_build_nav_item("ARSENAL", _on_tab.bind(TAB_ARSENAL)))
	col.add_child(_build_nav_item("OPTIONS", _on_tab.bind(TAB_OPTIONS)))
	_quit_btn = _build_nav_item("QUITTER", func(): get_tree().quit())
	col.add_child(_quit_btn)

	_select_mode(_mode_id)

## Débordement visuel qui n'entre JAMAIS dans `get_minimum_size()` (marge de
## style peinte, pas de layout) : l'anneau de focus manette (`_nav_focus_
## style()`, `expand_margin_*`) déborde du bouton de EXACTEMENT `FOCUS_RING_
## OFFSET_PX` (un `StyleBoxFlat` dessine son trait à l'INTÉRIEUR du rectangle
## déjà étendu par `expand_margin_*` — `STROKE_FOCUS`, l'épaisseur du trait,
## ne rajoute donc rien au-delà) ; `SHADOW_HARD_OFFSET.y` couvre l'ombre dure
## du texte (`shadow_offset_y`), qui déborde pareillement sans jamais compter
## dans `get_minimum_size()`. JOUER a le focus PAR DÉFAUT au démarrage
## (`_focus_play`, appelé depuis `_ready()`), donc cet anneau est TOUJOURS
## visible sur la toute première capture du menu — sans en réserver l'espace
## ici, son bord bas mord sur le résumé juste en dessous (retour lead
## 2026-09-25, §2 : « texte superposé sous JOUER »).
const _SWASH_HOST_BLEED_PX := Comic.FOCUS_RING_OFFSET_PX + Comic.SHADOW_HARD_OFFSET.y

## Enveloppe `control` (déjà construit par l'appelant) d'un `KitSwash`
## DERRIÈRE lui — même montage que `KitSwash.wrap(label: Label)` (UX-30),
## généralisé à un `Control` quelconque (ici un `Button`, pour garder JOUER
## cliquable/focalisable nativement) : jamais un second swash ailleurs dans
## ce fichier (critère d'acceptation « un seul swash »). Le dimensionnement
## final (`_finalize_swash_host_size`) reste à faire par l'appelant APRÈS
## `add_child` — voir sa docstring.
func _wrap_with_swash(control: Control, seed_text: String) -> Control:
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var swash := KitSwash.new()
	swash.seed_text = seed_text
	swash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	swash.offset_left = -KitSwash.PAD_X
	swash.offset_right = KitSwash.PAD_X
	swash.offset_top = -KitSwash.PAD_Y
	swash.offset_bottom = KitSwash.PAD_Y
	host.add_child(swash)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(control)
	return host

## Réserve la hauteur du `host` (swash + `control` + débordement du focus,
## §2 ci-dessus) — DOIT être appelée APRÈS que `host` (donc `control`) est
## entré dans l'arbre : `control.get_minimum_size()`, juste après sa
## construction et ses overrides de police (`_build_host_button`) mais AVANT
## `add_child`, renvoie encore l'ancienne taille minimale du thème par défaut
## (mesuré : (125, 58) au lieu de (419, 158) pour JOUER, SIZE_118) — la propagation
## du thème (`NOTIFICATION_THEME_CHANGED`) qui recalcule le cache de taille
## minimale d'un `Button` n'a lieu qu'à l'entrée dans l'arbre. Un `host` sous-
## dimensionné laissait l'anneau de focus (bleed 4 px) déborder de PLUS de
## 50 px sous JOUER (la propre taille minimale du bouton, 158 px, dépassant
## alors les 104 px réservés par `host` — un `Control` `PRESET_FULL_RECT` dont
## la taille minimale dépasse celle de son parent grandit au-delà, ici vers le
## bas) — jusque dans le résumé juste en dessous (retour lead 2026-09-25, §2).
func _finalize_swash_host_size(host: Control, control: Control) -> void:
	var swash_pad := Vector2(KitSwash.PAD_X, KitSwash.PAD_Y) * 2.0
	var focus_bleed := Vector2(0.0, _SWASH_HOST_BLEED_PX * 2.0)  # anneau déborde en haut ET en bas.
	host.custom_minimum_size = control.get_minimum_size() + swash_pad + focus_bleed

## Anneau de focus manette v4 (direction §4.6 « focus manette : contour
## paper 3 px décalé de 4 px, lisible même sur un élément choisi ») — jamais
## `Comic.focus_style()` (v3, contour `BULLET` rouge : le rouge n'est plus la
## marque en v4, réservé à `vital`).
func _nav_focus_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	s.border_color = Comic.paper_color()
	s.set_border_width_all(Comic.STROKE_FOCUS)
	s.expand_margin_left = Comic.FOCUS_RING_OFFSET_PX
	s.expand_margin_top = Comic.FOCUS_RING_OFFSET_PX
	s.expand_margin_right = Comic.FOCUS_RING_OFFSET_PX
	s.expand_margin_bottom = Comic.FOCUS_RING_OFFSET_PX
	return s

## Survol v4 (direction §4.6 « survol : plate_hi ») — plaque plate_hi
## derrière le texte, jamais un second panneau ni une couleur ad hoc.
func _nav_hover_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Comic.plate_hi_color()
	s.expand_margin_left = Comic.SP_2
	s.expand_margin_right = Comic.SP_2
	s.expand_margin_top = Comic.SP_1
	s.expand_margin_bottom = Comic.SP_1
	return s

## CTA JOUER (direction v4 §4.1/§4.6 « choisi : texte ink, ombre (6,6) ») —
## `flat`, zéro fond propre (le fond jaune vient de `KitSwash`, posé derrière
## par `_wrap_with_swash`). `.text` reste EXACTEMENT "▶  JOUER"
## (tests/ui/test_main_menu.gd::test_play_button_label_carries_no_hosting_or_ip_jargon).
func _build_host_button() -> Button:
	var b := Button.new()
	b.text = "▶  JOUER"
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_override("font", Comic.title_font_v4())
	b.add_theme_font_size_override("font_size", Comic.SIZE_118)
	b.add_theme_color_override("font_color", Comic.ink_color())
	b.add_theme_color_override("font_hover_color", Comic.ink_color())
	b.add_theme_color_override("font_focus_color", Comic.ink_color())
	b.add_theme_color_override("font_pressed_color", Comic.ink_color())
	b.add_theme_color_override("font_shadow_color", Comic.ink_color())
	b.add_theme_constant_override("shadow_offset_x", int(Comic.SHADOW_HARD_OFFSET.x))
	b.add_theme_constant_override("shadow_offset_y", int(Comic.SHADOW_HARD_OFFSET.y))
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("focus", _nav_focus_style())
	b.pressed.connect(_on_host)
	UiFx.press(b)
	return b

## Entrée de la pile secondaire (AGENTS/ARSENAL/OPTIONS/QUITTER, direction v4
## §4.1 « titres et labels en capitales italiques », §4.6 états) — capitales
## italiques papier 66 px par défaut, zéro fond au repos, plate_hi au survol/
## pressé, anneau papier au focus manette. `focus_mode = ALL` : atteignable
## clavier ET manette (critère d'acceptation), `UiFx.press` pour le retour
## tactile standard du kit (autocollant qui s'écrase, §4.7). `size` :
## réutilisé à `Comic.SIZE_37` pour « Terrain d'entraînement (solo) » (UX-38,
## retour lead §3 « ligne de pile 37 » — remplace son cadre rouge v3).
func _build_nav_item(text: String, on_press: Callable, size: int = Comic.SIZE_66) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", Comic.title_font_v4())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Comic.paper_color())
	b.add_theme_color_override("font_hover_color", Comic.paper_color())
	b.add_theme_color_override("font_focus_color", Comic.paper_color())
	b.add_theme_color_override("font_pressed_color", Comic.signal_color())
	b.add_theme_color_override("font_disabled_color", Comic.DISABLED)
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", _nav_hover_style())
	b.add_theme_stylebox_override("pressed", _nav_hover_style())
	b.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("focus", _nav_focus_style())
	b.pressed.connect(on_press)
	UiFx.press(b)
	return b

## Contenu du panneau « Partie personnalisée » (UX-08, inchangé fonctionnellement) :
## bascule + mode/carte/bots/difficulté/IP/Rejoindre + Entraînement + état
## réseau. Ses widgets internes (KitSlantBar/KitCard, ART-31) gardent leur
## `accent_color` v3 (`Comic.BRUSH`) : leur texte est câblé en dur sur
## `Comic.TEXT_ON_BRUSH` (blanc), qui n'a pas un contraste suffisant sur
## `Comic.SIGNAL` (jaune v4) — les migrer vers v4 appartient à qui possède
## scripts/ui/kit/ (hors périmètre de cette tâche), pas à ce fichier.
func _build_play_extra_panel() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Comic.SP_2)

	_custom_toggle_btn = Button.new()
	_custom_toggle_btn.flat = true
	_custom_toggle_btn.custom_minimum_size = Vector2(0, 44)
	_custom_toggle_btn.text = _custom_toggle_text()
	_custom_toggle_btn.focus_mode = Control.FOCUS_ALL
	_custom_toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_custom_toggle_btn.add_theme_font_override("font", Comic.body_font_v4())
	_custom_toggle_btn.add_theme_font_size_override("font_size", Comic.SIZE_28)
	_custom_toggle_btn.add_theme_color_override("font_color", Comic.paper_dim_color())
	_custom_toggle_btn.add_theme_color_override("font_hover_color", Comic.paper_color())
	_custom_toggle_btn.add_theme_color_override("font_focus_color", Comic.paper_color())
	_custom_toggle_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_custom_toggle_btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	_custom_toggle_btn.add_theme_stylebox_override("focus", _nav_focus_style())
	_custom_toggle_btn.pressed.connect(_on_toggle_custom)
	box.add_child(_custom_toggle_btn)
	UiFx.press(_custom_toggle_btn)

	# ---- Repliée par défaut (design.md v2 §11, docs/research/04_ui_ux.md #5 :
	# « on doit pouvoir lancer une partie sans traverser plusieurs niveaux de
	# menus ») : mode/carte/bots/difficulté ET le multijoueur (IP + Rejoindre,
	# critère d'acceptation UX-08) n'apparaissent QUE dans cette section.
	_custom_panel = VBoxContainer.new()
	_custom_panel.add_theme_constant_override("separation", Comic.SP_2)
	_custom_panel.visible = false
	box.add_child(_custom_panel)

	_custom_panel.add_child(Comic.bullet_row("Mode"))
	# Sélecteur segmenté (grille MODE_GRID_COLUMNS colonnes, 5 modes) — tient
	# toujours à l'écran (voir la docstring de MODE_GRID_COLUMNS), la
	# description complète reste disponible en info-bulle.
	var mode_row := GridContainer.new()
	mode_row.columns = MODE_GRID_COLUMNS
	mode_row.add_theme_constant_override("h_separation", Comic.SP_1)
	mode_row.add_theme_constant_override("v_separation", Comic.SP_1)
	_custom_panel.add_child(mode_row)
	var mgroup := ButtonGroup.new()
	for id in MatchConfig.MODES:
		var btn := _mode_card(id, mgroup)
		mode_row.add_child(btn)
		# `KitSlantBar._ready()` (ART-31, hors périmètre) impose SON PROPRE
		# `DEFAULT_SIZE` dès l'entrée dans l'arbre, écrasant toute valeur
		# posée avant `add_child` — se réapplique donc APRÈS.
		btn.custom_minimum_size = Vector2(0, MODE_BAR_HEIGHT)
		_mode_cards.append({"button": btn, "id": id})

	_custom_panel.add_child(HSeparator.new())
	_custom_panel.add_child(Comic.bullet_row("Carte"))
	# Grille de cartes-vignette (MAP_GRID_COLUMNS colonne(s)) dans un
	# défilement borné à 2 rangées.
	var map_scroll := ScrollContainer.new()
	map_scroll.custom_minimum_size = Vector2(0, MAP_GRID_VISIBLE_H)
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_custom_panel.add_child(map_scroll)
	_map_list = GridContainer.new()
	_map_list.columns = MAP_GRID_COLUMNS
	_map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_list.add_theme_constant_override("h_separation", Comic.SP_1)
	_map_list.add_theme_constant_override("v_separation", Comic.SP_1)
	map_scroll.add_child(_map_list)

	_custom_panel.add_child(HSeparator.new())
	var bots_row := HBoxContainer.new()
	bots_row.add_theme_constant_override("separation", Comic.SP_3)
	_custom_panel.add_child(bots_row)
	_bots_check = CheckButton.new()
	_bots_check.text = "Bots"
	_bots_check.button_pressed = MatchConfig.bots_enabled
	_bots_check.toggled.connect(_on_bots_toggled)
	bots_row.add_child(_bots_check)
	for i in DIFFICULTY_LABELS.size():
		var db := Button.new()
		db.text = DIFFICULTY_LABELS[i]
		db.toggle_mode = true
		db.custom_minimum_size = Vector2(0, 38)
		db.pressed.connect(_on_difficulty.bind(i))
		bots_row.add_child(db)
		UiFx.press(db)
		_diff_buttons.append(db)
	_refresh_difficulty_ui()

	_custom_panel.add_child(HSeparator.new())

	var mp := Comic.label("Partie personnalisée — rejoindre une IP", Comic.SIZE_BODY, Comic.TEXT_DIM, Comic.FONT_LABEL)
	_custom_panel.add_child(mp)

	_ip_field = LineEdit.new()
	_ip_field.text = "127.0.0.1"
	_ip_field.placeholder_text = "IP du serveur"
	_custom_panel.add_child(_ip_field)

	_join_btn = Button.new()
	_join_btn.text = "Rejoindre"
	_join_btn.custom_minimum_size = Vector2(0, 46)
	_join_btn.pressed.connect(_on_join)
	_custom_panel.add_child(_join_btn)
	UiFx.press(_join_btn)

	box.add_child(HSeparator.new())

	# UX-38 (retour lead 2026-09-25, §3) : « Terrain d'entraînement (solo) »
	# gardait le cadre rouge v3 (`Button.new()` nu, thème par défaut du
	# projet) — passé en ligne de pile v4 (`_build_nav_item`, même grammaire
	# que AGENTS/ARSENAL/OPTIONS/QUITTER : capitales italiques papier, zéro
	# fond au repos), à `Comic.SIZE_37` (§3 « ligne de pile 37 ») plutôt que
	# 66 : action secondaire, jamais au même poids que JOUER/la pile
	# principale.
	var train_btn := _build_nav_item("Terrain d'entraînement (solo)", _on_training, Comic.SIZE_37)
	box.add_child(train_btn)

	_status = ComicPanel.new()
	_status.bg_color = Comic.PANEL_HI
	_status.border_width = Comic.RULE_W
	_status.content_margin = Comic.SP_2
	_status.visible = false
	box.add_child(_status)
	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", Comic.SP_1)
	_status.body.add_child(status_box)
	_status_label = Comic.label("", Comic.SIZE_BODY, Comic.TEXT, Comic.FONT_LABEL)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	status_box.add_child(_status_label)
	_retry_btn = Button.new()
	_retry_btn.text = "Réessayer"
	_retry_btn.custom_minimum_size = Vector2(0, 40)
	_retry_btn.visible = false
	_retry_btn.pressed.connect(func():
		if _retry_action.is_valid():
			_retry_action.call())
	status_box.add_child(_retry_btn)
	UiFx.press(_retry_btn)
	if _net.last_disconnect_reason != "":
		_show_error(_net.last_disconnect_reason)
		_net.last_disconnect_reason = ""

	return box

## Barre inclinée autocollant (ART-31, KitSlantBar) — accent v3 `Comic.BRUSH`
## conservé, voir la docstring de `_build_play_extra_panel`.
func _mode_card(id: String, group: ButtonGroup) -> KitSlantBar:
	var b := KitSlantBar.new()
	b.toggle_mode = true
	b.button_group = group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.accent_color = Comic.BRUSH
	b.bar_text = SHORT_MODE_LABELS.get(id, id)
	b.tooltip_text = "%s\n%s" % [MODE_LABELS.get(id, id), MODE_DESCRIPTIONS.get(id, "")]
	b.pressed.connect(_select_mode.bind(id))
	return b

# ---------------------------------------------------------------- Sélection mode/carte
func _select_mode(id: String) -> void:
	_mode_id = id
	for c in _mode_cards:
		var is_current: bool = c.id == id
		c.button.button_pressed = is_current
		c.button.selected = is_current
	MatchConfig.set_mode(id)
	_refresh_maps()

func _map_catalog() -> Object:
	if ResourceLoader.exists(MAP_CATALOG_PATH):
		return load(MAP_CATALOG_PATH)
	return null

## Cartes disponibles pour `_mode_id`. Repli sur la scène historique tant que
## MapCatalog (R3-MAPS) n'existe pas ou ne couvre pas encore ce mode.
## UX-37 (proto une seule carte) : Duel/Duo passent `include_dev_maps=true` —
## Wasteland (4v4) ne les couvre pas (`MapCatalog.default_for`, MÊME
## contrat), la liste réduite au proto serait donc VIDE pour ces deux modes
## et retomberait sur "Terrain standard" générique au lieu de garder
## La Fosse/Le Belvédère ; Arène/Hardpoint/Tactique (4v4, la cible du proto)
## restent, eux, bornés à Wasteland par le catalogue.
func _maps_for_mode() -> Array:
	var cat := _map_catalog()
	var out: Array = []
	if cat:
		var bypass_proto_filter: bool = _mode_id in ["duel", "duo"]
		for m in cat.all(bypass_proto_filter):
			if _mode_id in m.modes:
				out.append(m)
	if out.is_empty():
		out.append({
			"id": "default", "name": "Terrain standard", "description": "",
			"scene": FALLBACK_SCENES.get(_mode_id, FALLBACK_SCENES["tdm"]),
		})
	return out

## "07 · WASTELAND" (direction v4 §6 — carte bas-gauche du menu). Une carte
## sans numéro connu (nouvelle carte pas encore dans MAP_NUMBERS) garde juste
## son nom, jamais un numéro inventé.
func _map_display_name(m: Dictionary) -> String:
	var id := str(m.get("id", ""))
	var name := str(m.get("name", id))
	if MAP_NUMBERS.has(id):
		return "%02d · %s" % [MAP_NUMBERS[id], name.to_upper()]
	return name.to_upper()

## Reconstruit la grille de cartes pour `_mode_id`. Restaure la DERNIÈRE carte
## mémorisée (MatchConfig.map_id, UX-08) si elle existe pour ce mode ; sinon
## (première visite de ce mode, carte inconnue/retirée) retombe sur la
## première de la liste — jamais un choix vide.
func _refresh_maps() -> void:
	for c in _map_list.get_children():
		c.queue_free()
	_map_cards.clear()
	var maps := _maps_for_mode()
	var group := ButtonGroup.new()
	var remembered_index := -1
	for i in maps.size():
		var m: Dictionary = maps[i]
		var card := _build_map_card(m, group)
		_map_list.add_child(card)
		# `KitCard._ready()` (ART-31, hors périmètre) impose SON PROPRE
		# `DEFAULT_SIZE` dès l'entrée dans l'arbre, écrasant toute valeur
		# posée avant `add_child` — se réapplique donc APRÈS.
		card.custom_minimum_size = Vector2(0, MAP_CARD_HEIGHT)
		_map_cards.append(card)
		if MatchConfig.map_id != "" and str(m.get("id", "")) == MatchConfig.map_id:
			remembered_index = i
	if not maps.is_empty():
		var chosen_index := remembered_index if remembered_index != -1 else 0
		_map_cards[chosen_index].button_pressed = true
		_select_map(maps[chosen_index])

## Carte de carte en autocollant à vignette (KitCard, ART-31) — accent v3
## `Comic.BRUSH` conservé, voir la docstring de `_build_play_extra_panel`.
func _build_map_card(m: Dictionary, group: ButtonGroup) -> KitCard:
	var id := str(m.get("id", ""))
	var card := KitCard.new()
	card.toggle_mode = true
	card.button_group = group
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.accent_color = Comic.BRUSH
	card.card_title = _map_display_name(m)
	var size_tag: String = str(m.get("size", ""))
	var desc: String = str(m.get("description", ""))
	card.tooltip_text = ("%s — %s" % [size_tag, desc]) if size_tag != "" else desc
	card.set_meta("map_id", id)
	card.pressed.connect(_select_map.bind(m))

	var vignette := MapVignette.new()
	vignette.sky_color = _map_sky_color(id)
	vignette.seed_value = hash(id)
	Comic.anchor(vignette, Control.PRESET_FULL_RECT)
	vignette.offset_left = Comic.SP_1
	vignette.offset_right = -Comic.SP_1
	vignette.offset_top = Comic.SP_1
	vignette.offset_bottom = -(Comic.SIZE_SUBTITLE + Comic.SP_3)
	card.add_child(vignette)
	return card

## Couleur de ciel déterministe de la vignette : dérivée de l'identifiant de
## carte (jamais un vrai random instable), parmi des jetons Comic DÉJÀ
## vérifiés — aucune couleur ad hoc, seul le choix parmi ces trois varie.
func _map_sky_color(map_id: String) -> Color:
	var palette := [Comic.OBJECTIVE, Comic.ALLY, Comic.BULLET]
	return palette[abs(hash(map_id)) % palette.size()]

## Mémorise la carte choisie (MatchConfig.save_last(), UX-08) et rafraîchit le
## résumé affiché sous JOUER ainsi que la carte « courante » bas-gauche
## (direction v4 §6). Retrouve la carte sélectionnée par son identifiant
## (meta "map_id", posée dans `_build_map_card`) plutôt que par index.
func _select_map(m: Dictionary) -> void:
	_map_choice = m
	MatchConfig.map_id = str(m.get("id", ""))
	MatchConfig.save_last()
	for c in _map_cards:
		if is_instance_valid(c):
			c.selected = str(c.get_meta("map_id", "")) == MatchConfig.map_id
	_update_play_summary()
	_refresh_current_map_plate()

func _on_bots_toggled(on: bool) -> void:
	MatchConfig.bots_enabled = on
	_refresh_difficulty_ui()
	MatchConfig.save_last()

func _on_difficulty(i: int) -> void:
	MatchConfig.bot_difficulty = i
	_refresh_difficulty_ui()
	MatchConfig.save_last()

## CHK-37 (« chaque contrôle désactivé expose une raison ») : sans bots, la
## difficulté n'a pas de sens — l'infobulle porte la raison plutôt que de
## laisser un bouton grisé muet.
func _refresh_difficulty_ui() -> void:
	for i in _diff_buttons.size():
		_diff_buttons[i].button_pressed = i == MatchConfig.bot_difficulty
		_diff_buttons[i].disabled = not MatchConfig.bots_enabled
		_diff_buttons[i].tooltip_text = "Indisponible — active les bots pour choisir une difficulté" if _diff_buttons[i].disabled else ""

## Bascule le panneau « Partie personnalisée » (UX-08) : mode/carte/bots/
## difficulté et le multijoueur (IP + Rejoindre) n'apparaissent QUE quand ce
## panneau est ouvert.
func _on_toggle_custom() -> void:
	_custom_open = not _custom_open
	_custom_panel.visible = _custom_open
	_custom_toggle_btn.text = _custom_toggle_text()
	if _custom_open:
		_fade_in(_custom_panel)

func _custom_toggle_text() -> String:
	return "▾  Partie personnalisée" if _custom_open else "▸  Partie personnalisée"

## Fondu d'opacité seul (jamais `UiFx.reveal`, qui translate les OFFSETS) :
## `_custom_panel` vit dans un `VBoxContainer`, qui réattribue la
## position/taille de ses enfants à chaque re-tri de mise en page (déclenché,
## entre autres, par `visible = true` juste au-dessus) — un `Tween` qui parte
## des offsets lus AVANT ce re-tri les ramène ensuite vers ces valeurs
## PÉRIMÉES pendant toute l'animation. `modulate:a` seul ne touche ni
## position ni taille : sûr sur un enfant de Container.
func _fade_in(node: CanvasItem) -> void:
	node.modulate.a = 0.0
	var tw := node.create_tween()
	tw.tween_property(node, "modulate:a", 1.0, Comic.DUR_REDUCED_FADE if Comic.reduced_motion() else Comic.DUR_REVEAL)

## Rappelle sous JOUER ce que « 1 clic » va lancer (mode + carte mémorisés)
## — la sélection reste repliée par défaut (_custom_panel), mais le joueur
## sait toujours ce qu'il va rejouer avant d'appuyer.
func _update_play_summary() -> void:
	if _play_summary == null:
		return
	var mode_label: String = SHORT_MODE_LABELS.get(_mode_id, _mode_id)
	var map_label := _map_display_name(_map_choice) if not _map_choice.is_empty() else ""
	_play_summary.text = "%s — %s" % [mode_label, map_label] if map_label != "" else mode_label

# ---------------------------------------------------------------- Carte courante (bas-gauche)
## Plaque « CARTE » à coins coupés (direction v4 §6, `Comic.plate_style()`) —
## rappelle la carte actuellement mémorisée, mise à jour par `_select_map()`.
func _build_current_map_plate(parent: Control) -> void:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", Comic.plate_style(Comic.plate_color()))
	Comic.anchor(wrap, Control.PRESET_BOTTOM_LEFT)
	wrap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	wrap.offset_left = NAV_X
	wrap.offset_bottom = -Comic.SAFE_MARGIN
	wrap.custom_minimum_size = Vector2(MAP_PLATE_WIDTH, 0.0)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(wrap)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Comic.SP_1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(box)

	box.add_child(Comic.meta_label_v4("Carte", Comic.SIZE_21, Comic.paper_dim_color()))
	_map_plate_title = Comic.title_label_v4("", Comic.SIZE_37, Comic.paper_color())
	box.add_child(_map_plate_title)
	_map_plate_desc = Comic.body_label_v4("", Comic.SIZE_28, Comic.paper_dim_color())
	_map_plate_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_map_plate_desc.custom_minimum_size = Vector2(MAP_PLATE_WIDTH - Comic.SP_4 * 2.0, 0.0)
	box.add_child(_map_plate_desc)

	_refresh_current_map_plate()

func _refresh_current_map_plate() -> void:
	if _map_plate_title == null:
		return
	_map_plate_title.text = _map_display_name(_map_choice) if not _map_choice.is_empty() else ""
	_map_plate_desc.text = str(_map_choice.get("description", ""))

# ---------------------------------------------------------------- Plaque joueur (haut-droite)
## Plaque « JOUEUR 1 / AGENT : <NOM> » (direction v4 §6) — mise à jour avec
## l'agent affiché (`_refresh_lobby_characters()`), jamais désynchronisée de
## la vitrine 3D.
func _build_player_plate(parent: Control) -> void:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", Comic.plate_style(Comic.plate_color()))
	Comic.anchor(wrap, Control.PRESET_TOP_RIGHT)
	wrap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wrap.offset_right = -Comic.SAFE_MARGIN
	wrap.offset_top = Comic.SAFE_MARGIN
	wrap.custom_minimum_size = Vector2(PLAYER_PLATE_WIDTH, 0.0)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(wrap)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(box)

	box.add_child(Comic.meta_label_v4("Joueur 1", Comic.SIZE_21, Comic.paper_color()))
	_player_plate_agent = Comic.meta_label_v4("", Comic.SIZE_21, Comic.paper_dim_color())
	box.add_child(_player_plate_agent)
	# `_build_player_plate()` s'exécute APRÈS le premier `_refresh_lobby_
	# characters()` (appelé depuis `_build_world()`, avant `_build_ui()`) :
	# à ce moment-là `_player_plate_agent` n'existait pas encore, donc cet
	# appel-là n'a rien pu écrire (`_refresh_player_plate_agent` sort tôt sur
	# `null`) — on relit l'agent COURANT ici pour ne jamais laisser la
	# plaque vide au premier affichage.
	var agents := AgentDatabase.all()
	if not agents.is_empty():
		_refresh_player_plate_agent(agents[posmod(AgentDatabase.selected_index, agents.size())])

func _refresh_player_plate_agent(agent: AgentConfig) -> void:
	if _player_plate_agent == null:
		return
	_player_plate_agent.text = "Agent : %s" % agent.agent_name

# ---------------------------------------------------------------- Touches (bas-droite)
## Rappel des touches (direction v4 §6 « touches en bas à droite ») — jamais
## un fond (§5 règle 1), sauf la touche elle-même (rayon 4 px, seule
## exception au rayon 0, direction §4.3).
func _build_key_hints(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Comic.SP_4)
	Comic.anchor(row, Control.PRESET_BOTTOM_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_right = -Comic.SAFE_MARGIN
	row.offset_bottom = -Comic.SAFE_MARGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	row.add_child(_build_key_hint("Entrée", "Sélectionner"))
	row.add_child(_build_key_hint("Échap", "Retour"))

func _build_key_hint(key: String, action: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", Comic.SP_2)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Comic.plate_color()
	chip_style.set_corner_radius_all(4)
	chip_style.content_margin_left = Comic.SP_2
	chip_style.content_margin_right = Comic.SP_2
	chip_style.content_margin_top = Comic.SP_1
	chip_style.content_margin_bottom = Comic.SP_1

	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", chip_style)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key_label := Comic.meta_label_v4(key, Comic.SIZE_21, Comic.paper_color())
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(key_label)
	hb.add_child(chip)

	var action_label := Comic.body_label_v4(action, Comic.SIZE_21, Comic.paper_dim_color())
	action_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(action_label)
	return hb

# ---------------------------------------------------------------- Onglets
func _on_tab(idx: int) -> void:
	_show_tab(idx)

func _show_tab(idx: int) -> void:
	_tab_index = idx
	if _embedded and is_instance_valid(_embedded):
		_embedded.queue_free()
	_embedded = null

	if idx == TAB_PLAY:
		_play_panel.visible = true
		UiFx.reveal(_play_panel)
		if AgentDatabase.selected_index != _last_agent_shown:
			_refresh_lobby_characters()
		call_deferred("_focus_play")
		return

	_play_panel.visible = false
	var script: Script = null
	match idx:
		TAB_AGENTS: script = AGENT_SCRIPT
		TAB_ARSENAL: script = ARSENAL_SCRIPT
		TAB_OPTIONS: script = OPTIONS_SCRIPT
	if script == null:
		return
	_embedded = script.new()
	_embedded.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _embedded.has_signal("closed"):
		_embedded.closed.connect(func(): _show_tab(TAB_PLAY))
	_content.add_child(_embedded)
	UiFx.reveal(_embedded)

func _focus_play() -> void:
	if _host_btn and is_instance_valid(_host_btn) and _play_panel.visible:
		_host_btn.grab_focus()

# ---------------------------------------------------------------- Réseau / jeu
func _on_host() -> void:
	_apply_match_config()
	if _net.host() == OK:
		_loading_t = -1.0
		_status.visible = false
		_start_game()
	else:
		_show_error("Échec de l'hébergement.", _on_host)

func _on_join() -> void:
	if _ip_field.text.strip_edges() == "":
		_show_empty("Aucune adresse — saisis une IP de serveur.")
		_ip_field.grab_focus()
		return
	_apply_match_config()
	_loading_t = 0.0
	_status.visible = true
	UiFx.reveal(_status)
	_status.bg_color = Comic.PANEL_HI
	_retry_btn.visible = false
	_status_label.add_theme_color_override("font_color", Comic.TEXT)
	_status_label.text = "Connexion à %s…" % _ip_field.text
	_net.join(_ip_field.text)

func _on_connected() -> void:
	_loading_t = -1.0
	_status.visible = false
	_start_game()

func _on_failed() -> void:
	_loading_t = -1.0
	_show_error("Connexion échouée.", _on_join)

## `code` : contexte pour le joueur (design.md v2 §11 "Error: ⚠ ÉCHEC, code,
## Réessayer"). `retry` : action rejouée par le bouton Réessayer.
func _show_error(msg: String, retry: Callable = Callable()) -> void:
	_status.visible = true
	UiFx.reveal(_status)
	_status.bg_color = Comic.PANEL_HI
	_status.border_color = Comic.BRUSH
	_status_label.add_theme_color_override("font_color", Comic.BRUSH)
	_status_label.text = "⚠ ÉCHEC — %s" % msg
	_retry_action = retry
	_retry_btn.visible = retry.is_valid()

func _show_empty(msg: String) -> void:
	_status.visible = true
	UiFx.reveal(_status)
	_status.bg_color = Comic.PANEL_HI
	_status.border_color = Comic.RULE
	_status_label.add_theme_color_override("font_color", Comic.TEXT_DIM)
	_status_label.text = msg
	_retry_btn.visible = false

func _on_training() -> void:
	get_tree().change_scene_to_file("res://scenes/levels/training/training_ground.tscn")

func _apply_match_config() -> void:
	MatchConfig.set_mode(_mode_id)
	MatchConfig.map_id = str(_map_choice.get("id", ""))
	MatchConfig.save_last()

func _start_game() -> void:
	get_tree().change_scene_to_file(_resolve_start_scene())

## Hôte : sa propre sélection (`_map_choice`), il EST le serveur qui décide.
## Client : la scène transmise par le serveur pendant l'authentification
## (`_net.received_scene`, voir NetworkManager._client_apply_server_decision)
## — jamais `_map_choice`, qui reste sa sélection LOCALE et peut désigner une
## carte différente de celle de l'hôte (voir BUG-02, docs/audit/bugs.md).
func _resolve_start_scene() -> String:
	if _net.received_scene != "":
		return _net.received_scene
	return str(_map_choice.get("scene", FALLBACK_SCENES.get(_mode_id, FALLBACK_SCENES["tdm"])))

## ---------------------------------------------------------------- Dégradé d'encre
## Dégradé horizontal (encre -> transparent, direction v4 §6) posé sous toute
## la 2D pour garder le texte papier lisible sur la 3D, sans jamais de boîte
## pleine derrière (§5 règle 1, même principe étendu au menu).
##
## UX-38 (retour lead 2026-09-25, §2 « bandes verticales sur toute la moitié
## gauche ») : l'ancienne version peignait le dégradé en 24 `draw_rect` à plat
## côte à côte (un ruban d'alpha CONSTANT par tranche) — chaque tranche est
## une bande visible à l'œil, exactement le défaut signalé. Remplacé par une
## VRAIE texture de dégradé (`GradientTexture2D`, interpolée en continu par le
## GPU entre les points du `Gradient`), dessinée en un seul `draw_texture_
## rect` : aucun palier d'alpha, un flou de valeur lisse du bord gauche
## jusqu'à transparent (direction §6 « dégradé lisse »).
class InkGradient extends Control:
	var _gradient_tex: GradientTexture2D

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		resized.connect(queue_redraw)
		_build_gradient_texture()

	## Une seule colonne de dégradé (`width` 2 px, suffisant pour une rampe
	## purement horizontale — Godot interpole le `Gradient` en continu à
	## l'échantillonnage, pas seulement à ses points de contrôle) étirée par
	## `draw_texture_rect` sur toute la largeur du fondu : c'est cette
	## interpolation GPU, jamais un pas discret peint à la main, qui supprime
	## les bandes.
	func _build_gradient_texture() -> void:
		var ink := Comic.ink_color()
		var grad := Gradient.new()
		grad.colors = PackedColorArray([Color(ink.r, ink.g, ink.b, 0.86), Color(ink.r, ink.g, ink.b, 0.0)])
		grad.offsets = PackedFloat32Array([0.0, 1.0])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_LINEAR
		tex.fill_from = Vector2(0.0, 0.0)
		tex.fill_to = Vector2(1.0, 0.0)
		tex.width = 2
		tex.height = 2
		_gradient_tex = tex

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0 or _gradient_tex == null:
			return
		var fade_w := size.x * 0.62
		draw_texture_rect(_gradient_tex, Rect2(0.0, 0.0, fade_w, size.y), false)

## ---------------------------------------------------------------- Vignette de carte
## Miniature procédurale posée dans la moitié haute d'un `KitCard` de carte
## (§8.6 "vignettes rendu argile ... radius 6, ciel de la carte en bandeau
## haut" + "callouts", cf. la maquette de référence `.orchestrator/refs/
## pinterest/pin_20.jpg` : rendu clair/"argile" et repères à pastille ronde
## reliés par une tige fine). Aucun rendu de carte n'est encore livré à ce
## niveau du menu (MapCatalog ne fournit ni couleur ni image) : ce fond reste
## un aplat + une silhouette de toits déterministe (seed = hash de l'id de
## carte), jamais un chiffre/texte inventé. `mouse_filter` ignore : le clic
## reste porté par le `KitCard` parent (BaseButton), cette vignette n'est
## qu'un dessin.
class MapVignette extends Control:
	var sky_color: Color = Comic.OBJECTIVE
	var seed_value: int = 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		# Fond argile : le seul neutre CLAIR du jeton v3 (Comic.TEXT_DIM),
		# lisible en encre foncée par-dessus (contraste CHK-33).
		draw_rect(Rect2(Vector2.ZERO, size), Comic.TEXT_DIM)

		var sky_h := size.y * 0.38
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, sky_h)), sky_color)

		# Silhouette de toits en aplat encre — déterministe (même seed =
		# toujours la même silhouette pour une carte donnée, jamais un vrai
		# random instable entre deux redraws).
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var blocks := 5
		var bw := size.x / float(blocks)
		for i in blocks:
			var bh: float = size.y * rng.randf_range(0.16, 0.34)
			var r := Rect2(Vector2(bw * i, size.y - bh), Vector2(maxf(bw - 2.0, 1.0), bh))
			draw_rect(r, Comic.HARD_SHADOW_COLOR)

		# Callout (repère du point chaud de la carte, épingle Pinterest #20) :
		# pastille pinceau cerclée d'encre + tige fine.
		var pin := Vector2(size.x * 0.66, size.y * 0.42)
		var tip := pin + Vector2(size.x * 0.18, -size.y * 0.22)
		draw_line(pin, tip, Comic.HARD_SHADOW_COLOR, 1.5)
		draw_circle(pin, 4.0, Comic.BRUSH)
		draw_arc(pin, 4.0, 0.0, TAU, 10, Comic.HARD_SHADOW_COLOR, 1.5, true)
