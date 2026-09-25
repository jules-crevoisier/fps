## vfx_reel.gd
## Reel fenêtré des 6 effets peints SIGNATURE (tâche VFX-20, docs/AGENTS.md,
## docs/STYLE_BIBLE.md §9.6) : UNE séquence d'images PAR CAPACITÉ (« reel
## fenêtré par capacité », critère d'acceptation de la tâche) — braise de
## Faux départ (Vif), Tape-la-cloche (Choc), Piquet d'arpenteur (Vanne),
## Coup de dé (Guet, « révélation »), Baume du Palud (Roseau), Glu (Verrou).
## Ne joue PAS les vraies capacités réseau (scripts/agents/abilities/*.gd,
## hors fichiers possédés par ce contrat — voir l'en-tête d'AbilityVfx.gd) :
## comme tools/review/anim_reel.gd ne passe pas par PlayerController pour
## jouer un clip, ce script appelle directement `AbilityVfx.spawn_*` aux
## positions du plateau de démonstration — c'est la bibliothèque VFX elle-même
## qui est mise en image, pas le réseau/la logique de jeu qui la déclenche.
##
## Fenêtré obligatoire (lecture du swapchain), même motif que
## tools/map_shots.gd/tools/review/anim_reel.gd. Chaque effet tourne en
## TEMPS RÉEL (Tween/GPUParticles3D natifs, pas un seek déterministe comme
## anim_reel.gd — rien à "avancer à la main" ici, contrairement à un
## AnimationPlayer) : ce script capture `FRAMES_PER_ABILITY` images
## consécutives par capacité pendant qu'elle joue.
##
##   godot --path . -s tools/review/vfx_reel.gd -- --out=DIR [--ids=faux_depart,glu]
##
## Écrit "<out>/<ability_id>/<frame_%03d>.png" par capacité, imprime
## "VFX_REEL_ABILITY <ability_id> <label>" au début de chacune puis
## "VFX_REEL_DONE <n_abilities> <frames_per_ability>" et quitte (0).
extends SceneTree

const DEFAULT_OUT := "reports/vfx_reel"
const FPS := 30.0
## ~1,2 s par capacité à 30 i/s : assez pour montrer la pose ET le
## retour/l'impact/l'atterrissage de chaque effet (aucun des 6 ne dépasse
## 0,8 s d'après docs/AGENTS.md/STYLE_BIBLE.md §9.6).
const FRAMES_PER_ABILITY := 36
## Images "à vide" avant la toute première capture d'une capacité (laisse le
## moteur stabiliser l'affichage — même rôle que `_warm` dans anim_reel.gd) :
## le déclenchement de l'effet a lieu sur la DERNIÈRE image de warm-up (voir
## `_process`), pour que la toute première image SAUVÉE montre déjà l'effet
## en train de naître plutôt qu'un plateau encore vide.
const WARM_FRAMES := 4

## id, libellé FR (affiché en incrustation), couleur-clé de l'agent (copiée
## depuis docs/style/tokens.json "agents".<id>.key, comme AgentDatabase.gd).
const ABILITIES := [
	{"id": "faux_depart", "label": "Faux départ — Vif", "agent_color": Color("ee6a24")},
	{"id": "tape_la_cloche", "label": "Tape-la-cloche — Choc", "agent_color": Color("be2d25")},
	{"id": "piquet_arpenteur", "label": "Piquet d'arpenteur — Vanne", "agent_color": Color("f2b51d")},
	{"id": "coup_de_de", "label": "Coup de dé — Guet", "agent_color": Color("5157b8")},
	{"id": "baume_du_palud", "label": "Baume du Palud — Roseau", "agent_color": Color("2e9c8a")},
	{"id": "glu", "label": "Glu — Verrou", "agent_color": Color("2a5fc4")},
]

var _out := DEFAULT_OUT
var _id_filter: Array = []

var _stage: Node3D
var _cam: Camera3D
var _ability_index := -1
var _frame := -1
var _warm := 0
var _fired: Dictionary = {}  # {trigger_frame: true} déjà déclenchés pour la capacité en cours.


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.get_slice("=", 1)
		elif a.begins_with("--ids="):
			_id_filter = a.get_slice("=", 1).split(",")
	DisplayServer.window_set_size(Vector2i(1280, 720))


func _process(_delta: float) -> bool:
	if _stage == null:
		_setup()
		return _next_ability()
	if _warm < WARM_FRAMES:
		_warm += 1
		if _warm == WARM_FRAMES:
			_fire_triggers(0)  # la toute première image sauvée montre déjà l'effet naître.
		return false
	if _frame >= 0:
		_save(_current().id, _frame)
	_frame += 1
	if _frame >= FRAMES_PER_ABILITY:
		return _next_ability()
	_fire_triggers(_frame)
	return false


func _active() -> Array:
	if _id_filter.is_empty():
		return ABILITIES
	var out: Array = []
	for a in ABILITIES:
		if _id_filter.has(a.id):
			out.append(a)
	return out


func _current() -> Dictionary:
	return _active()[_ability_index]


func _next_ability() -> bool:
	_ability_index += 1
	if _ability_index >= _active().size():
		print("VFX_REEL_DONE %d %d" % [_active().size(), FRAMES_PER_ABILITY])
		quit(0)
		return true
	_begin_ability(_current())
	return false


func _setup() -> void:
	root.add_child(load("res://scripts/core/LevelLook.gd").new())
	root.add_child(WorldEnvironment.new())
	root.add_child(DirectionalLight3D.new())
	_stage = Node3D.new()
	root.add_child(_stage)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 12)
	ground.mesh = plane
	ground.material_override = Cartoon.world(Cartoon.PAPER_SHADE)
	root.add_child(ground)
	_cam = Camera3D.new()
	root.add_child(_cam)
	# Gros plan volontaire : chaque effet ne mesure que quelques cm (échelle
	# cohérente avec ComicFx/ImpactFx, STYLE_BIBLE §9.1-9.3 — étincelles,
	# éclats, bouffées ne sont jamais énormes) ; à la distance "vue d'ensemble"
	# d'un premier essai (6,6 m, fov 46°), les formes ne faisaient que
	# quelques pixels — illisible. Le joueur voit ces effets à portée de
	# combat rapproché, pas depuis une caméra de suivi de map : ce plateau se
	# cadre donc à ~2,9 m, comme un plan de tir à la ceinture.
	_cam.fov = 36.0
	_cam.global_position = Vector3(0, 0.9, 2.0)
	_cam.look_at(Vector3(0, 0.35, 0), Vector3.UP)
	_cam.current = true


func _clear_stage() -> void:
	for c in _stage.get_children():
		c.queue_free()
	_frame = -1
	_warm = 0
	_fired.clear()


func _begin_ability(entry: Dictionary) -> void:
	_clear_stage()
	_add_title(entry.label)


func _add_title(text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 34
	l.outline_size = 10
	l.modulate = Color(0.96, 0.93, 0.86)
	l.outline_modulate = Color(0.1, 0.08, 0.07)
	l.position = Vector3(0, 0.95, 0)  # dans le cadre du gros plan (voir _setup, cam à 2,0 m).
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.0016
	_stage.add_child(l)


## Déclenche les `AbilityVfx.spawn_*` propres à la capacité en cours à
## `frame` (une seule fois par valeur de `frame`, `_fired` empêche un double
## déclenchement si `_process` boucle sur la même image) — voir le plateau de
## positions au fil du `match`, à hauteur de la caméra fixe de `_setup()`.
func _fire_triggers(frame: int) -> void:
	if _fired.has(frame):
		return
	_fired[frame] = true
	var id: String = _current().id
	match id:
		"faux_depart":
			_fire_faux_depart(frame)
		"tape_la_cloche":
			_fire_tape_la_cloche(frame)
		"piquet_arpenteur":
			if frame == 0:
				AbilityVfx.spawn_piquet_arpenteur(_stage, Vector3(-1.0, 0.5, 0.0), Vector3(1.0, 0.5, 0.0), 1.0)
		"coup_de_de":
			if frame == 0:
				AbilityVfx.spawn_coup_de_de(_stage, Vector3(-1.1, 0.65, 0.0), Vector3(0.9, 0.25, 0.0))
		"baume_du_palud":
			_fire_baume(frame)
		"glu":
			_fire_glu(frame)


func _fire_faux_depart(frame: int) -> void:
	const POSE := Vector3(-0.8, 0.0, 0.0)
	const RETURN_TO := Vector3(0.8, 0.0, 0.0)
	if frame == 0:
		AbilityVfx.spawn_faux_depart_pose(_stage, POSE)
		AbilityVfx.spawn_ember_glow(_stage, POSE, FRAMES_PER_ABILITY / FPS)
	elif frame == int(FRAMES_PER_ABILITY * 0.55):
		AbilityVfx.spawn_faux_depart_return(_stage, POSE, RETURN_TO)


## Retour QA du 2026-09-25 : à un seul déclenchement en frame 0, la charge +
## le « DING » (durée de vie 0,3 s + 0,18 s, AbilityVfx.MOVEMENT_TRAIL_S/
## BELL_DING_S) s'éteignent vers la frame 11 — 24 des 36 images du reel
## (67 %) restaient un plateau vide et identique d'une image à l'autre,
## contrairement à `faux_depart`/`baume_du_palud` qui couvrent toute la
## fenêtre (braise en boucle, gouttes en boucle). Tape-la-cloche n'a pas
## d'équivalent "en boucle" dans le jeu réel (c'est un aller ponctuel), donc
## ce plateau de démo le rejoue plusieurs fois — un charge/DING toutes les
## RETRIGGER_FRAMES (~0,4 s, la durée mesurée d'un cycle), en alternant le
## sens, pour que le reel reste rempli sur toute sa fenêtre sans jamais
## suggérer une capacité qui "couve" en continu.
##
## ORIGIN/IMPACT à ±0,65 m sur l'axe X (recentrés depuis -1,1/0,9 m, revue QA :
## l'ancien point d'impact à 0,9 m + l'anneau à 1,2 m débordait du cadre en
## bas à droite) et à y=0,35 m (hauteur du `look_at` de `_setup`, jamais 0) :
## avec l'anneau à 0,6 m (voir AbilityVfx.bell_ding_spec) les deux positions
## restent visibles avec marge dans le gros plan à 2 m/fov 36°.
func _fire_tape_la_cloche(frame: int) -> void:
	const ORIGIN := Vector3(-0.65, 0.35, 0.0)
	const IMPACT := Vector3(0.65, 0.35, 0.0)
	const RETRIGGER_FRAMES := 12
	if frame % RETRIGGER_FRAMES != 0:
		return
	if (frame / RETRIGGER_FRAMES) % 2 == 0:
		AbilityVfx.spawn_tape_la_cloche(_stage, ORIGIN, IMPACT)
	else:
		AbilityVfx.spawn_tape_la_cloche(_stage, IMPACT, ORIGIN)


func _fire_baume(frame: int) -> void:
	const POS := Vector3(0.0, 0.0, 0.0)
	const RADIUS := 0.6
	if frame == 0:
		AbilityVfx.spawn_baume_du_palud(_stage, POS, RADIUS, FRAMES_PER_ABILITY / FPS)
		AbilityVfx.spawn_balm_plus_pop(_stage, POS + Vector3(0.3, 0.0, 0.2))
	elif frame == int(FRAMES_PER_ABILITY * 0.5):
		AbilityVfx.spawn_balm_plus_pop(_stage, POS + Vector3(-0.3, 0.0, -0.15))


func _fire_glu(frame: int) -> void:
	const POS := Vector3(0.0, 0.0, 0.0)
	const RADIUS := 0.55
	var color: Color = _current().agent_color
	if frame == 0:
		AbilityVfx.spawn_glu_pose(_stage, POS, RADIUS, color)
		AbilityVfx.spawn_glu_bubbles(_stage, POS, RADIUS, color, FRAMES_PER_ABILITY / FPS)


func _save(ability_id: String, frame: int) -> void:
	var dir := "%s/%s" % [_out, ability_id]
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if frame == 0:
		print("VFX_REEL_ABILITY %s %s" % [ability_id, _current().label])
	root.get_texture().get_image().save_png("%s/frame_%03d.png" % [dir, frame])
