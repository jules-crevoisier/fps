## capture_frog_cowboy.gd
## Captures in-game de Frog Cowboy (requirement 9) : héberge Shipment avec 1
## bot (donc 1 corps tiers visible, le bot -- le joueur local cache son
## propre corps, voir PlayerLook), laisse l'IA bouger un peu, écrit 3 PNG
## (survol tiers avec arme en main, gros plan main+arme, mi-course). Même
## famille que tools/style/capture_shipment.gd (SceneTree, _process, FENÊTRÉ
## -- pas headless : il faut un vrai swapchain pour une capture).
##
## ThirdPersonWeapon.gd est inerte pour le joueur dont CE process a
## l'autorité (voir sa doc de classe, "inerte pour le joueur LOCAL") -- un bot
## simulé en quick-start solo (host+bots dans le MÊME process, comme ici) a
## justement authority_id=1=local (contract-p0.md "hôte et bots simulés côté
## serveur"), donc ne montre normalement JAMAIS son arme tierce à SA PROPRE
## fenêtre (seul un AUTRE pair/client la verrait -- voir la doc de
## tests/player/test_frog_cowboy_character.gd::_remote_player, qui contourne
## la même chose pour les tests). `_force_third_person_weapon()` rejoue donc
## à la main l'initialisation que ce nœud ferait pour un vrai pair distant,
## uniquement pour cette capture -- AUCUN changement de ThirdPersonWeapon.gd
## lui-même.
##
## Usage :
##   "%GODOT%" --path . -s res://tools/rigging/capture_frog_cowboy.gd -- --out=reports/checkpoints/2026-09-26_frog_cowboy
extends SceneTree

const _SHIPMENT := "res://scenes/levels/maps/shipment.tscn"
const _SETTLE_FRAMES := 110    ## laisse le bot spawn/tomber au sol/s'équiper.
const _RUN_WAIT_FRAMES := 260  ## laisse l'IA du bot se mettre en mouvement (chasse/patrouille réelle).

var _out_dir: String = "res://reports/checkpoints/2026-09-26_frog_cowboy"
var _frame: int = 0
var _world: Node = null
var _bot: PlayerController = null
var _shots_done: bool = false
var _quit_at_frame: int = -1  ## laisse le temps à la DERNIÈRE capture différée (_present_and_save, 6 frames) de finir avant de quitter -- appeler quit() la même frame que le dernier tir la coupait court.

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.get_slice("=", 1)

func _process(_delta: float) -> bool:
	if _frame == 0:
		_boot()
	_frame += 1
	if _shots_done:
		if _frame == _quit_at_frame:
			call_deferred("quit", 0)
		return false
	if _frame == _SETTLE_FRAMES:
		_find_bot()
		_force_third_person_weapon()
		_shoot_third_person_overview()
	elif _frame == _SETTLE_FRAMES + 6:
		_shoot_hand_closeup()
	elif _frame == _RUN_WAIT_FRAMES:
		_shoot_mid_run()
		_shots_done = true
		_quit_at_frame = _frame + 10  # laisse _present_and_save (6 frames) finir avant de quitter.
	return false

func _boot() -> void:
	MatchConfig.mode_id = "tdm"
	MatchConfig.map_id = "shipment"
	MatchConfig.bots_enabled = true
	MatchConfig.team_size = 1
	var packed := load(_SHIPMENT) as PackedScene
	_world = packed.instantiate()
	get_root().add_child(_world)

func _find_bot() -> void:
	_bot = _find_bot_in(get_root()) as PlayerController
	if _bot == null:
		push_error("capture_frog_cowboy: aucun PlayerController bot trouvé dans l'arbre")
		return
	print("capture_frog_cowboy: bot trouvé à ", _bot.global_position)

func _find_bot_in(node: Node) -> Node:
	var pc := node as PlayerController
	if pc and pc.is_bot:
		return pc
	for c in node.get_children():
		var r := _find_bot_in(c)
		if r:
			return r
	return null

func _bot_character_body() -> CharacterBody:
	if _bot == null:
		return null
	return _bot.get_node_or_null("%CharacterModel") as CharacterBody

## Voir la doc de classe : rejoue l'initialisation que ThirdPersonWeapon.gd
## ferait pour un vrai pair distant (elle ne tourne pas ici -- ce bot est
## localement autoritaire, cf. contract-p0.md).
func _force_third_person_weapon() -> void:
	if _bot == null:
		return
	var tp := _bot.get_node_or_null("ThirdPersonWeapon") as ThirdPersonWeapon
	var body := _bot_character_body()
	var weapon := _bot.get_node_or_null("Weapon") as Weapon
	if tp == null or body == null or weapon == null:
		push_error("capture_frog_cowboy: ThirdPersonWeapon/CharacterBody/Weapon introuvable(s)")
		return
	tp.visible = true
	tp.set_process(true)
	tp.player = _bot
	tp.set("_character_body", body)
	tp.weapon = weapon
	if body.is_model_ready():
		tp.call("_on_body_ready")
	weapon.current_id_changed.connect(tp._on_current_id_changed)
	tp._on_current_id_changed(WeaponDatabase.id_of(weapon.cfg()))
	print("capture_frog_cowboy: ThirdPersonWeapon forcé, _model=", tp.get("_model"))

func _save(img: Image, name: String) -> void:
	var path := _out_dir.path_join(name)
	var abs_dir := ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var err := img.save_png(path)
	print("capture_frog_cowboy: ", name, " -> ", path, " (err=", err, ")")

func _spawn_capture_camera() -> Camera3D:
	var cam := Camera3D.new()
	get_root().add_child(cam)
	cam.current = true
	return cam

## Vue tierce à trois-quarts : même cadrage (distance/hauteur) que
## _shoot_mid_run, confirmé au rendu -- le bot y remplit bien le cadre sans
## que la caméra ne traverse un mur/une caisse du corridor Shipment.
func _shoot_third_person_overview() -> void:
	if _bot == null:
		return
	var cam := _spawn_capture_camera()
	var p := _bot.global_position
	cam.global_position = p + Vector3(2.6, 1.6, 0.6)
	cam.look_at(p + Vector3(0, 1.1, 0), Vector3.UP)
	call_deferred("_present_and_save", cam, "bot_third_person_weapon.png")

## Gros plan main droite + arme (BoneAttachment3D "RightHand" -> WeaponSocket).
func _shoot_hand_closeup() -> void:
	if _bot == null:
		return
	var body := _bot_character_body()
	if body == null:
		return
	var socket := body.find_child("WeaponSocket", true, false) as Node3D
	if socket == null:
		push_error("capture_frog_cowboy: WeaponSocket introuvable pour le gros plan")
		return
	print("capture_frog_cowboy: WeaponSocket à ", socket.global_position)
	var cam := _spawn_capture_camera()
	var p := socket.global_position
	cam.global_position = p + Vector3(0.55, 0.4, 0.75)
	cam.look_at(p, Vector3.UP)
	cam.fov = 50.0
	call_deferred("_present_and_save", cam, "hand_weapon_closeup.png")

## Mi-course : après quelques secondes l'IA du bot a normalement commencé à
## se déplacer (patrouille/poursuite réelle, voir scripts/ai/BotBrain.gd) --
## capture sa locomotion telle qu'elle est RÉELLEMENT au lieu de forcer un
## état. Même cadrage que _shoot_third_person_overview (confirmé au rendu).
func _shoot_mid_run() -> void:
	if _bot == null:
		return
	var cam := _spawn_capture_camera()
	var p := _bot.global_position
	cam.global_position = p + Vector3(2.6, 1.6, 0.6)
	cam.look_at(p + Vector3(0, 1.1, 0), Vector3.UP)
	call_deferred("_present_and_save", cam, "bot_mid_run.png")

## Le swapchain a besoin de quelques frames après le changement de caméra
## pour présenter une image qui reflète VRAIMENT le nouveau point de vue
## (get_root().get_texture() renvoie la dernière frame PRÉSENTÉE) -- même
## piège documenté par tools/style/capture_shipment.gd.
func _present_and_save(cam: Camera3D, name: String) -> void:
	for i in 6:
		await process_frame
	var img := get_root().get_texture().get_image()
	if img:
		_save(img, name)
	else:
		push_error("capture_frog_cowboy: pas d'image (lancé --headless ? voir l'en-tête)")
	cam.queue_free()
