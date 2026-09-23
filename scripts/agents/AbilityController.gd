## AbilityController.gd
## Gère les capacités de l'agent du joueur : entrées (C/Q/E/X), cooldowns,
## charges et points d'ultime. À mettre en enfant du joueur (nom "Abilities").
## Nœud SERVEUR-AUTORITAIRE (authority = peer 1, réglé par
## PlayerController._enter_tree) : le serveur garde l'AbilityState
## AUTORITAIRE (`_server_state`) ; le propriétaire garde une copie PRÉDICTIVE
## (`_charges/_state`) pour la réactivité, corrigée par le serveur après
## chaque activation (voir `_sync_state`). Les effets de mouvement/cosmétique
## s'exécutent côté propriétaire (`Ability.activate_local`) ; les effets de
## jeu (vie, spawn répliqué...) s'exécutent côté serveur (`Ability.activate_server`).
##
## Réseau (contract-r2.md, R-B3) : le propriétaire envoie
## `request_activate(i, aim_dir)` — `aim_dir` = direction de visée caméra,
## validée côté serveur (finie, normalisée, AimValidator) avant tout calcul de
## cible. Les capacités qui posent un objet dans le monde (mur, fumée,
## tremplin, piège) passent par les `cast_*` de ce nœud, qui diffusent un RPC
## d'autorité à TOUS les pairs (objet visible/bloquant partout, comme
## `cast_barrier`). Les effets ciblés sur une victime précise (étourdissement,
## éblouissement) ou une équipe (reveal) utilisent des RPC ciblées
## (`net_apply_stun`, `net_apply_flash`, `net_show_markers`) envoyées
## directement par la capacité au nœud "Abilities" du/des joueur(s) concerné(s).
class_name AbilityController
extends Node

## Émis côté PROPRIÉTAIRE dès l'activation locale (prédiction) — sert au HUD
## et à l'audio (contract-r2.md : "Emit ability_used(slot, name) on the owner").
signal ability_used(slot: String, ability_name: String)

var player: PlayerController
var agent: AgentConfig

## Copie prédictive, uniquement instanciée chez le PROPRIÉTAIRE.
var _owner_state: AbilityState
## Copie autoritaire, uniquement instanciée côté SERVEUR.
var _server_state: AbilityState
## Suivi "hors-combat" (soin de base) — alimenté par Health.damaged côté
## SERVEUR uniquement (voir `_ready`, guard `has_signal`).
var _out_of_combat := OutOfCombatTracker.new()

func _ready() -> void:
	player = get_parent() as PlayerController
	agent = _resolve_agent()
	if agent == null:
		return
	if player != null and player.is_multiplayer_authority():
		_owner_state = AbilityState.new(agent.abilities)
	if multiplayer.is_server():
		_server_state = AbilityState.new(agent.abilities)
		var hp := player.get_node_or_null("Health") as Health
		# Health.damaged est ajouté par R-B1 (contract-r2.md) : peut ne pas
		# encore exister selon l'ordre de chargement des slices -> guard.
		if hp and hp.has_signal("damaged"):
			hp.damaged.connect(_on_damaged)

func _on_damaged(_amount: float, _attacker_id: int) -> void:
	_out_of_combat.mark_damaged(Time.get_ticks_msec() / 1000.0)

## Lu par HealAbility.can_activate_server (soin de base : hors-combat depuis
## `window` s). SERVEUR uniquement (le propriétaire n'a pas besoin de le savoir).
func is_out_of_combat(window: float = 3.0) -> bool:
	return _out_of_combat.is_out_of_combat(Time.get_ticks_msec() / 1000.0, window)

## Agent RÉPLIQUÉ (PlayerController.agent_index, défini par le serveur au
## spawn). Repli sur la sélection locale quand l'index n'est pas valide
## (ex. entraînement hors-ligne, sans passer par GameWorld._spawn_player).
func _resolve_agent() -> AgentConfig:
	if player == null or player.agent_index < 0:
		return AgentDatabase.selected()
	return AgentDatabase.get_by_index(player.agent_index)

func _physics_process(delta: float) -> void:
	if agent == null:
		return
	if _server_state:
		_server_state.tick(delta)
	if _owner_state:
		_owner_state.tick(delta)
		_handle_input()

## Lit `player.input.ability_pressed` ("" ou "C"/"Q"/"E"/"X" — voir
## PlayerInput.gd, déjà gaté "souris capturée" pour un humain local ; un bot
## écrit ce champ directement, voir BotBrain._tick_ability). Le mappage
## touche -> slot vit désormais dans PlayerInput (ability_from_presses) :
## ici on associe juste le symbole pressé à L'AGENT du joueur (slot == "X"
## pour l'ultime, comme les capacités C/Q/E — cf. Ability.slot).
func _handle_input() -> void:
	if player == null or player.input == null:
		return
	var hp := player.get_node_or_null("Health") as Health
	if hp and hp.is_dead:
		return
	var pressed := player.input.ability_pressed
	if pressed == "":
		return
	for i in agent.abilities.size():
		if agent.abilities[i].slot == pressed:
			_activate(i)
			return

## true si les capacités sont désactivées par le mode de jeu courant (Duel,
## Duo — contract-r2.md : propriété `abilities_enabled` sur le nœud du groupe
## "game_mode"). Absent ou sans cette propriété -> activées par défaut.
func _abilities_enabled() -> bool:
	var mode := get_tree().get_first_node_in_group("game_mode")
	if mode == null:
		return true
	var v = mode.get("abilities_enabled")
	if v == null:
		return true
	return bool(v)

## Direction de visée caméra (monde), envoyée au serveur avec chaque
## activation — utilisée par les capacités qui calculent une cible (fumée,
## tremplin, piège, œil, éblouissement...). Toujours finie/normalisée.
func _current_aim_dir() -> Vector3:
	var cam: Camera3D = player.camera if player else null
	if cam == null:
		return Vector3.FORWARD
	var d := -cam.global_transform.basis.z
	if d.length() < 0.01:
		return Vector3.FORWARD
	return d.normalized()

## Activation côté PROPRIÉTAIRE : prédiction locale (mouvement/cosmétique +
## décompte optimiste de la charge) puis requête au serveur pour validation
## et exécution des effets de jeu.
func _activate(i: int) -> void:
	if _owner_state == null or not _owner_state.can_activate(i):
		return
	if not _abilities_enabled():
		return
	var ab: Ability = agent.abilities[i]
	var aim_dir := _current_aim_dir()
	ab.activate_local(player)
	_owner_state.try_activate(i)
	ability_used.emit(ab.slot, ab.display_name)
	if multiplayer.is_server():
		# `str(player.name).to_int()`, JAMAIS `multiplayer.get_unique_id()` :
		# pour un BOT (id >= PlayerController.BOT_ID_START), get_unique_id()
		# resterait l'id du SERVEUR (1), pas celui du bot — voir Weapon.gd,
		# même motif documenté en détail dans ses requêtes _do_request_*.
		_server_activate(str(player.name).to_int(), i, aim_dir)
	else:
		request_activate.rpc_id(1, i, aim_dir)

## Requête client -> serveur : ne fait que transférer vers `_server_activate`
## avec l'id réel de l'expéditeur (jamais fait confiance au client).
@rpc("any_peer", "call_remote", "reliable")
func request_activate(i: int, aim_dir: Vector3) -> void:
	if multiplayer.is_server():
		_server_activate(multiplayer.get_remote_sender_id(), i, aim_dir)

## Valide et exécute l'activation côté SERVEUR : vérifie que l'expéditeur est
## bien le propriétaire du joueur, que celui-ci est vivant, que les capacités
## sont activées pour le mode courant, qu'`aim_dir` est sain (AimValidator),
## puis que l'état autoritaire ET la capacité elle-même (can_activate_server,
## ex. hors-combat) permettent l'activation. Pousse ensuite l'état corrigé au
## propriétaire dans tous les cas (aussi sur refus, pour corriger la
## prédiction optimiste).
func _server_activate(sender_id: int, i: int, aim_dir: Vector3) -> void:
	if not multiplayer.is_server() or player == null or _server_state == null:
		return
	var owner_id := str(player.name).to_int()
	if sender_id != owner_id:
		return
	if not _abilities_enabled():
		return
	var hp := player.get_node_or_null("Health") as Health
	if hp and hp.is_dead:
		return
	if not AimValidator.is_valid(aim_dir):
		return
	if i < 0 or i >= agent.abilities.size():
		return
	var ab: Ability = agent.abilities[i]
	if not ab.can_activate_server(player):
		_push_state(owner_id)  # refus (ex. soin en combat) : resynchronise sans consommer.
		return
	if not _server_state.try_activate(i):
		_push_state(owner_id)  # refus : corrige la charge consommée par la prédiction
		return
	ab.activate_server(player, aim_dir.normalized())
	_push_state(owner_id)

## Charge l'ultime autoritaire (appelé par le serveur, ex. sur un kill via
## GameWorld._charge_ult), puis pousse l'état corrigé au propriétaire.
func server_add_ult(points: float) -> void:
	if not multiplayer.is_server() or player == null or _server_state == null:
		return
	_server_state.add_ult(points)
	_push_state(str(player.name).to_int())

func _push_state(owner_id: int) -> void:
	if _server_state == null:
		return
	# Appel DIRECT si le joueur est simulé ICI (hôte-joueur OU bot — les deux
	# partagent l'autorité serveur, voir PlayerController.is_local_human) :
	# un RPC vers l'id d'un bot (>= 9001) n'atteindrait aucun pair réel.
	if player and player.is_multiplayer_authority():
		if _owner_state:
			_owner_state.apply_dict(_server_state.to_dict())
	else:
		_sync_state.rpc_id(owner_id, _server_state.to_dict())

## Correction serveur -> propriétaire (RPC d'autorité : seul le serveur, qui
## détient l'autorité de ce nœud, peut l'appeler).
@rpc("authority", "call_local", "reliable")
func _sync_state(d: Dictionary) -> void:
	if _owner_state:
		_owner_state.apply_dict(d)

# ======================================================================
#  OBJETS RÉPLIQUÉS (mur, fumée, tremplin, piège) — construits UNIQUEMENT
#  côté serveur (voir chaque Ability.activate_server), diffusés à TOUS les
#  pairs (visibles/bloquants partout, serveur inclus). Construits en code
#  (pas de scène séparée), comme le faisait déjà `cast_barrier`.
# ======================================================================

## Spawn d'une barrière (mur) RÉPLIQUÉE : appelé par une capacité côté
## SERVEUR (voir WallAbility.activate_server), construit le mur sur TOUS les
## pairs (visible + bloquant partout, serveur inclus).
func cast_barrier(pos: Vector3, fwd: Vector3, size: Vector3, duration: float, color: Color) -> void:
	_spawn_barrier.rpc(pos, fwd, size, duration, color)

## RPC d'autorité (seul le serveur peut l'émettre) : plus aucune taille ni
## position choisie par le client, tout vient de la vue serveur du joueur.
@rpc("authority", "call_local", "reliable")
func _spawn_barrier(pos: Vector3, fwd: Vector3, size: Vector3, duration: float, color: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var wall := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	wall.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = Cartoon.prop(color)
	wall.add_child(mesh)
	scene.add_child(wall)
	wall.global_position = pos
	wall.look_at(pos + fwd, Vector3.UP)
	var t := scene.get_tree().create_timer(duration)
	t.timeout.connect(wall.queue_free)

## Spawn d'une sphère de fumée RÉPLIQUÉE (SmokeAbility) : opaque, bloque
## vraiment la vue et les tirs (StaticBody3D + collision, comme le mur).
func cast_smoke(pos: Vector3, radius: float, duration: float, color: Color) -> void:
	_spawn_smoke.rpc(pos, radius, duration, color)

@rpc("authority", "call_local", "reliable")
func _spawn_smoke(pos: Vector3, radius: float, duration: float, color: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	# Calque VISION uniquement : bloque les regards (raycasts de vue des bots)
	# mais ni les corps (masque joueur = calque 1) ni les balles (SHOT_MASK).
	var body := StaticBody3D.new()
	body.collision_layer = PhysicsLayers.VISION
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	col.shape = sphere
	body.add_child(col)
	var mat := Cartoon.prop(color)
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mesh.mesh = sm
	mesh.material_override = mat
	body.add_child(mesh)
	# Faces intérieures : depuis l'intérieur de la fumée on ne voit rien non plus.
	var inner := MeshInstance3D.new()
	var inner_sm := SphereMesh.new()
	inner_sm.radius = radius * 0.98
	inner_sm.height = radius * 1.96
	inner_sm.flip_faces = true
	inner.mesh = inner_sm
	inner.material_override = mat
	body.add_child(inner)
	scene.add_child(body)
	body.global_position = pos
	var t := scene.get_tree().create_timer(duration)
	t.timeout.connect(body.queue_free)

## Spawn d'un tremplin RÉPLIQUÉ (JumpPadAbility). La détection de contact
## (Area3D.body_entered) tourne sur TOUS les pairs (géométrie répliquée), mais
## seule la machine du joueur concerné applique la poussée (mouvement
## local-autoritaire, cf. contract-p0.md) : `body.is_multiplayer_authority()`.
func cast_jump_pad(pos: Vector3, duration: float, boost: float) -> void:
	_spawn_jump_pad.rpc(pos, duration, boost)

@rpc("authority", "call_local", "reliable")
func _spawn_jump_pad(pos: Vector3, duration: float, boost: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var pad := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.1
	shape.height = 0.6
	col.shape = shape
	pad.add_child(col)
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.1
	cm.bottom_radius = 1.1
	cm.height = 0.15
	mesh.mesh = cm
	mesh.material_override = Cartoon.prop(Color(0.35, 0.85, 0.55))
	pad.add_child(mesh)
	scene.add_child(pad)
	pad.global_position = pos
	var cooldowns: Dictionary = {}  # id instance -> horodatage (anti-spam par joueur)
	pad.body_entered.connect(func(body: Node3D):
		if not (body is PlayerController) or not body.is_multiplayer_authority():
			return
		var now := Time.get_ticks_msec() / 1000.0
		var last: float = cooldowns.get(body.get_instance_id(), -INF)
		if now - last < 0.5:
			return
		cooldowns[body.get_instance_id()] = now
		body.velocity.y = maxf(body.velocity.y, boost)
	)
	var t := scene.get_tree().create_timer(duration)
	t.timeout.connect(pad.queue_free)

## Spawn d'un piège étourdissant RÉPLIQUÉ (StunTrapAbility). Comme le
## tremplin, l'objet existe sur tous les pairs, mais SEULE la copie SERVEUR
## effectue la détection + envoie le stun (`net_apply_stun`) : le contact ne
## déclenche rien côté clients.
func cast_stun_trap(pos: Vector3, owner_team: int, trap_duration: float, stun_duration: float) -> void:
	_spawn_stun_trap.rpc(pos, owner_team, trap_duration, stun_duration)

@rpc("authority", "call_local", "reliable")
func _spawn_stun_trap(pos: Vector3, owner_team: int, trap_duration: float, stun_duration: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var trap := Area3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 0.15, 1.4)
	col.shape = shape
	trap.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.3, 0.05, 1.3)
	mesh.mesh = bm
	mesh.material_override = Cartoon.prop(Color(0.85, 0.25, 0.3))
	trap.add_child(mesh)
	scene.add_child(trap)
	trap.global_position = pos
	var triggered := false
	trap.body_entered.connect(func(body: Node3D):
		if triggered or not multiplayer.is_server():
			return  # seule la copie SERVEUR détecte/déclenche (anti-triche).
		if not (body is PlayerController):
			return
		if int(body.get("team")) == owner_team:
			return
		var victim_ctrl := body.get_node_or_null("Abilities")
		if victim_ctrl == null or not victim_ctrl.has_method("net_apply_stun"):
			return
		var vhp := body.get_node_or_null("Health") as Health
		if vhp and vhp.is_dead:
			return
		triggered = true
		# Appel DIRECT si la VICTIME est simulée ICI (hôte-joueur ou BOT — les
		# deux partagent l'autorité serveur, contrairement à un vrai client
		# distant) : un RPC vers l'id d'un bot (>= 9001) n'atteindrait aucun
		# pair réel (contract-r3.md, "Cross-slice interfaces").
		if body.is_multiplayer_authority():
			victim_ctrl.net_apply_stun(stun_duration)
		else:
			var vid := str(body.name).to_int()
			victim_ctrl.net_apply_stun.rpc_id(vid, stun_duration)
		mesh.visible = false
		col.set_deferred("disabled", true)
	)
	var t := scene.get_tree().create_timer(trap_duration)
	t.timeout.connect(trap.queue_free)

# ======================================================================
#  EFFETS CIBLÉS (étourdissement, éblouissement, reveal) — appelés
#  DIRECTEMENT par la capacité côté serveur sur le nœud "Abilities" du/des
#  joueur(s) concerné(s), via RPC ciblée (`rpc_id`). "authority" == seul le
#  serveur (autorité de CE nœud, y compris pour la copie d'un autre joueur)
#  peut les émettre.
# ======================================================================

## Reçu par la VICTIME d'un piège étourdissant ou d'une Déferlante : fait
## transitionner son propre state_machine vers "Stun" (contract-r2.md :
## "victim's owner receives transition_to('Stun', {'duration': d})").
@rpc("authority", "call_local", "reliable")
func net_apply_stun(duration: float) -> void:
	if player and player.state_machine:
		player.state_machine.transition_to("Stun", {"duration": duration})

## Reçu par la VICTIME d'un Éblouissement : écran blanc papier qui s'estompe
## sur `duration` (<= 1,5 s), CanvasLayer construite ici (contract-r2.md :
## "a CanvasLayer you create from your scripts").
@rpc("authority", "call_local", "reliable")
func net_apply_flash(duration: float) -> void:
	if player == null:
		return
	if player.is_bot:
		# Un bot ébloui ne voit plus rien pendant la durée (BotBrain lit ce méta).
		player.set_meta("blinded_until", Time.get_ticks_msec() / 1000.0 + duration)
		return
	if not player.is_local_human():
		return  # l'écran blanc n'a de sens que chez la victime elle-même.
	var layer := CanvasLayer.new()
	layer.layer = 30
	var rect := ColorRect.new()
	rect.color = Color(0.97, 0.96, 0.9)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	player.get_tree().root.add_child(layer)
	var tw := layer.create_tween()
	tw.tween_property(rect, "modulate:a", 0.0, duration)
	tw.tween_callback(layer.queue_free)

## Diffuse les positions révélées (RevealAbility/RenewalAbility) UNIQUEMENT
## aux coéquipiers du lanceur (RPC ciblée par joueur, pas de broadcast global
## — contract-r2.md : "team sees ink '!' markers"). Appelé côté SERVEUR par la
## capacité, depuis la racine des joueurs (siblings de `player`).
func cast_reveal(players_root: Node, team: int, marks: Array, duration: float) -> void:
	for child in players_root.get_children():
		if int(child.get("team")) != team:
			continue
		if bool(child.get("is_bot")):
			continue  # marqueur purement cosmétique : un bot n'a pas d'écran.
		var ctrl := child.get_node_or_null("Abilities")
		if ctrl == null or not ctrl.has_method("net_show_markers"):
			continue
		# Appel DIRECT pour l'hôte-joueur (simulé ICI), RPC ciblée sinon —
		# même motif que `net_apply_stun` (contract-r3.md).
		if child.is_multiplayer_authority():
			ctrl.net_show_markers(marks, duration)
		else:
			ctrl.net_show_markers.rpc_id(str(child.name).to_int(), marks, duration)

## Reçu par un COÉQUIPIER du lanceur d'un reveal : affiche un marqueur "!" en
## encre à chaque position révélée, visible à travers les murs
## (no_depth_test), pendant `duration` (<= 3 s).
@rpc("authority", "call_local", "reliable")
func net_show_markers(marks: Array, duration: float) -> void:
	if player == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	for m in marks:
		var pos: Vector3 = m
		var label := Label3D.new()
		label.text = "!"
		label.modulate = Color(0.95, 0.93, 0.88)
		label.outline_modulate = Color(0.1, 0.08, 0.06)
		label.font_size = 96
		label.outline_size = 14
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.double_sided = true
		scene.add_child(label)
		label.global_position = pos + Vector3(0, 1.6, 0)
		var t := scene.get_tree().create_timer(duration)
		t.timeout.connect(label.queue_free)

## Pour le HUD : état de chaque capacité (API inchangée). Lit la copie
## prédictive chez le propriétaire (réactive), sinon la copie autoritaire en
## repli (ex. inspection côté serveur).
func slot_info() -> Array:
	var out: Array = []
	if agent == null:
		return out
	var state: AbilityState = _owner_state if _owner_state != null else _server_state
	if state == null:
		return out
	for i in agent.abilities.size():
		var ab: Ability = agent.abilities[i]
		if ab.is_ultimate:
			out.append({
				"slot": ab.slot, "name": ab.display_name, "ult": true,
				"ready": state.can_activate(i),
				"ratio": state.ult_points() / float(ab.ult_cost), "charges": 0,
			})
		else:
			var charges_left := state.charges(i)
			var ratio := 1.0
			if ab.cooldown > 0.0 and charges_left < ab.charges:
				ratio = 1.0 - clampf(state.cooldown_left(i) / ab.cooldown, 0.0, 1.0)
			out.append({
				"slot": ab.slot, "name": ab.display_name, "ult": false,
				"ready": charges_left > 0, "ratio": ratio, "charges": charges_left,
			})
	return out
