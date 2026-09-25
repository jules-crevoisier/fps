## FauxDepartAbility.gd
## Signature (E) de Vif, "Faux départ" (docs/research/10_ammo_kits_input.md
## §3.3, remplace Tremplin) : pose une braise à ses pieds ; un second appui
## sur E dans les `RETURN_WINDOW` s qui suivent la ramène instantanément
## dessus. PV et munitions CONSERVÉS : le retour ne fait que déplacer
## `global_position` -- ni Health ni Weapon ne sont touchés. Retour REFUSÉ
## côté serveur si le joueur est trop loin (> `MAX_RETURN_RANGE`) ou si trop
## de temps s'est écoulé (> `RETURN_WINDOW`), et la braise elle-même est
## DESTRUCTIBLE (`EMBER_HEALTH` dégâts -- un enfant "Health" GÉNÉRIQUE,
## résolu par Weapon._resolve_ray exactement comme la vie d'un joueur, SANS
## aucune modification de Weapon.gd, fermé).
##
## `charges = 2` (au lieu d'1) : condition NÉCESSAIRE pour que le second appui
## atteigne seulement le serveur -- AbilityController._activate (fermé depuis
## AGT-01) refuse toute activation côté PROPRIÉTAIRE tant que
## `_owner_state.can_activate(i)` est faux ; avec une seule charge, celle-ci
## tomberait à 0 dès la pose et le second appui ne quitterait jamais le
## client. Les deux appuis partagent le MÊME cooldown de 16 s (§3.3 : "Recharge
## 16 s (lancée à la pose)") : AbilityState.try_activate ne redémarre le
## cooldown QUE quand la capacité repasse de pleine à non pleine, ce qui n'arrive
## qu'à la PREMIÈRE consommation (2 -> 1) ; la seconde (1 -> 0, le retour) ne le
## relance pas.
##
## État "pose en attente" gardé SUR LE JOUEUR (`set_meta`/`get_meta`, même
## motif que AbilityController.net_apply_flash -- métadonnée "blinded_until")
## plutôt que sur cette Resource : une même instance de FauxDepartAbility est
## PARTAGÉE par tous les joueurs qui incarnent Vif (voir AgentDatabase._vif),
## donc aucun état propre à UN joueur ne peut vivre sur `self`.
##
## Réplication réseau (limite connue, hors périmètre AGT-03) : la braise est
## construite directement dans `player.get_tree().current_scene` (même
## squelette que AbilityController._spawn_barrier/_spawn_stun_trap), et le
## retour écrit directement `player.global_position` -- CORRECT pour
## l'hôte-joueur et les bots (autorité serveur partagée, seul mode couvert par
## les tests/probes actuels du dépôt), mais PAS répliqué à un pair humain
## distant : ni AbilityController.gd (les `cast_*` existants ne couvrent pas
## cette forme d'objet) ni PlayerController.gd (`net_respawn`/`server_respawn`
## feraient l'affaire pour le réseau, mais écrasent aussi `spawn_point` --
## effet de bord inacceptable pour un simple retour, pas un vrai respawn)
## n'exposent de point d'entrée adapté, et les deux sont FERMÉS depuis AGT-01
## (hors de la liste de fichiers de cette tâche). Un futur `cast_ember`
## (même patron que `cast_stun_trap`) et un `net_teleport`/`server_teleport`
## (même patron que `net_respawn`/`server_respawn`, SANS toucher `spawn_point`)
## restent à ajouter par une tâche qui possède ces fichiers.
extends Ability

## Fenêtre pendant laquelle un second appui déclenche le retour (§3.3 : "Fenêtre de 5 s").
const RETURN_WINDOW := 5.0
## Portée max entre le joueur et la braise pour que le retour soit accepté (§3.3 : "portée max 30 m").
const MAX_RETURN_RANGE := 30.0
## Durée de vie de la braise si elle n'est ni détruite ni utilisée (s) -- au-delà de
## la fenêtre de décision, elle reste un temps raisonnable avant de disparaître.
const EMBER_LIFETIME := 8.0
## PV de la braise (§3.3 : "détruite à 30 dégâts").
const EMBER_HEALTH := 30.0
## Rayon du mesh (§3.3 : "visible de tous (0,4 m...)").
const EMBER_RADIUS := 0.2
## Fondu de la téléportation (§3.3 : "fondu de 0,15 s") -- cosmétique, écran du
## PROPRIÉTAIRE uniquement, même motif que AbilityController.net_apply_flash.
const RETURN_FADE := 0.15

## Clé de métadonnée sur le joueur (publique, sans underscore, pour rester
## lisible/exploitable directement par les tests -- même esprit que
## AssistTracker.ASSIST_MIN_DAMAGE/ASSIST_WINDOW).
const META_KEY := "faux_depart_ember"

func _init() -> void:
	slot = "E"
	display_name = "Faux départ"
	description = "Pose une braise à ses pieds ; un second appui dans les 5 s la ramène dessus instantanément (PV et munitions conservés)."
	cooldown = 16.0
	charges = 2

## Ignore `_aim_dir` : la braise se pose "à ses pieds" (§3.3), jamais visée.
func activate_server(player: PlayerController, _aim_dir: Vector3) -> void:
	# `get_meta(key, default)` journalise quand même une ERROR si la clé est
	# absente (le défaut `null` n'est pas distingué de "aucun défaut" côté
	# moteur, vérifié en Godot 4.7 -- même piège que scripts/ui/UiFx.gd et
	# scripts/ai/BotBrain.gd) : `has_meta` d'abord évite le bruit, y compris
	# au tout premier appui sur E (cas normal, pas un cas limite).
	if not player.has_meta(META_KEY):
		_pose(player)
	else:
		_attempt_return(player, player.get_meta(META_KEY))

## Première pression : pose la braise à la position ACTUELLE du joueur et
## ouvre la fenêtre de retour.
func _pose(player: PlayerController) -> void:
	var pos := player.global_position
	var ember := _spawn_ember(player, pos)
	player.set_meta(META_KEY, {
		"pos": pos,
		"posed_at": Time.get_ticks_msec() / 1000.0,
		"ember": ember,
	})

## Second appui : valide âge/distance/survie de la braise côté SERVEUR avant
## de téléporter. Consomme la tentative dans tous les cas (une seule chance
## par braise posée), y compris sur un refus -- un appui "raté" ne relance pas
## une pose à l'endroit où le joueur se trouve déjà (ce serait surprenant).
func _attempt_return(player: PlayerController, pending: Dictionary) -> void:
	player.set_meta(META_KEY, null)
	var posed_at: float = pending.get("posed_at", -INF)
	var now := Time.get_ticks_msec() / 1000.0
	if now - posed_at > RETURN_WINDOW:
		return  # refusé : fenêtre de 5 s écoulée (acceptance AGT-03).
	var pos: Vector3 = pending.get("pos", player.global_position)
	if player.global_position.distance_to(pos) > MAX_RETURN_RANGE:
		return  # refusé : plus de 30 m (acceptance AGT-03).
	var ember: Node = pending.get("ember")
	if ember == null or not is_instance_valid(ember):
		return  # refusé : braise déjà disparue (détruite ou expirée).
	var hp := ember.get_node_or_null("Health") as Health
	if hp and hp.is_dead:
		return  # refusé : braise détruite (contre-jeu §3.3, "la détruire pour annuler le retour").
	_teleport_back(player, pos)
	ember.queue_free()

## Téléportation effective -- ne touche NI Health NI Weapon (PV et munitions
## conservés, §3.3). Le fondu cosmétique (`RETURN_FADE`) ne s'affiche que chez
## le PROPRIÉTAIRE humain local (même garde que
## AbilityController.net_apply_flash : un bot n'a pas d'écran).
func _teleport_back(player: PlayerController, pos: Vector3) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = pos
	player.reset_physics_interpolation()
	if not player.is_local_human():
		return  # bot ou pair distant : pas d'écran à faire clignoter ici.
	var layer := CanvasLayer.new()
	layer.layer = 30
	var rect := ColorRect.new()
	rect.color = Color(0.05, 0.03, 0.02)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 1.0
	layer.add_child(rect)
	player.get_tree().root.add_child(layer)
	var tw := layer.create_tween()
	tw.tween_property(rect, "modulate:a", 0.0, RETURN_FADE)
	tw.tween_callback(layer.queue_free)

## Construit la braise -- StaticBody3D visible + enfant "Health" GÉNÉRIQUE :
## Weapon._resolve_ray (fermé) cherche déjà un enfant nommé "Health" sur TOUT
## collider touché par un rayon de tir, quel qu'il soit -- aucune modification
## de Weapon.gd n'est donc nécessaire pour que les balles endommagent/
## détruisent la braise. Ajoutée à "round_props" (BUG-03 : nettoyée au
## changement de manche, même groupe que les murs/fumées/tremplins/pièges).
func _spawn_ember(player: PlayerController, pos: Vector3) -> StaticBody3D:
	var scene := player.get_tree().current_scene
	var body := StaticBody3D.new()
	body.add_to_group("round_props")
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = EMBER_RADIUS
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = EMBER_RADIUS
	sm.height = EMBER_RADIUS * 2.0
	mesh.mesh = sm
	# Braise : orange chaud, hors des teintes réservées à la surbrillance
	# ennemie (STYLE_BIBLE : 300-355° et 105-145° interdits dans le décor).
	mesh.material_override = Cartoon.prop(Color(0.95, 0.45, 0.15))
	body.add_child(mesh)
	var hp := Health.new()
	hp.name = "Health"
	hp.max_health = EMBER_HEALTH  # Health._ready() règle current_health = max_health.
	hp.regen_rate = 0.0
	body.add_child(hp)
	# `died` émet `killer_id` (int) ; `queue_free()` n'attend rien -- `unbind(1)`
	# ignore cet argument au lieu de le transmettre (sinon : "Too many arguments").
	hp.died.connect(body.queue_free.unbind(1))
	scene.add_child(body)
	body.global_position = pos
	var t := scene.get_tree().create_timer(EMBER_LIFETIME)
	t.timeout.connect(body.queue_free)
	return body
