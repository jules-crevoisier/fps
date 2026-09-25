## AmmoPack.gd
## Cartouchière lâchée à la mort d'un joueur, en arène (GF-22, docs/research/
## 10_ammo_kits_input.md §2.4). RÉSEAU : l'uid est alloué par le SERVEUR et le
## spawn/despawn est DIFFUSÉ à tous les pairs par GameWorld.gd (autorité
## serveur — voir sa section « CARTOUCHIÈRE » et `_broadcast_ammo_pack_spawn`/
## `_broadcast_ammo_pack_despawn`), même patron que WorldWeapon.gd pour les
## armes au sol. Ce script fait la présentation locale (objet crème et bleu
## qui tourne, STYLE_BIBLE — tokens `enamel_cream`/`ally`) ET, côté SERVEUR
## uniquement, la validation du ramassage : contrairement à WorldWeapon (le
## CLIENT détecte le survol et ENVOIE une demande), ici aucune prédiction
## n'est nécessaire (pas de slot à choisir, pas de feedback de visée) — le
## serveur seul décide, en surveillant directement les corps qui entrent dans
## sa zone (même motif que HealZone.gd, aucune RPC de demande de ramassage).
##
## Ramassage : tout joueur VIVANT à <= PICKUP_RANGE (1,2 m, §2.4) reçoit
## `mags_per_pickup` chargeur(s) de réserve sur CHACUNE de ses armes
## (`Weapon.server_add_reserve_mags`, plafonné à la réserve de la règle
## courante) ; si au moins une réserve a réellement augmenté, la cartouchière
## disparaît (diffusion via `GameWorld.server_despawn_ammo_pack`, trouvé par le
## groupe "match" — GameWorld.gd s'y ajoute dans son `_ready()`). Sans effet
## (toutes les réserves déjà pleines), elle reste au sol pour un autre joueur.
class_name AmmoPack
extends Area3D

## Distance MAXIMALE (m) validée côté serveur pour un ramassage effectif —
## §2.4 : « Ramassage serveur à <= 1,2 m ». Volontairement DISTINCTE du rayon
## de la zone de détection (`_DETECTION_RADIUS` ci-dessous, plus large) : la
## zone ne sert qu'à obtenir des candidats via `get_overlapping_bodies()`, la
## VRAIE limite de ramassage est ce contrôle de distance explicite — testable
## indépendamment de la taille réelle des capsules de joueur.
const PICKUP_RANGE := 1.2

## Rayon (m) de la zone de détection (Area3D) — plus large que `PICKUP_RANGE`
## pour qu'un joueur soit bien remonté par `get_overlapping_bodies()` avant
## d'appliquer le contrôle de distance strict ci-dessus (marge de capsule).
const _DETECTION_RADIUS := 2.5

## Vitesse de rotation cosmétique (rad/s) — purement visuelle, tourne sur
## TOUS les pairs (contrairement à la logique de ramassage, serveur seul).
const _SPIN_SPEED := 2.4

## Durée de vie (s) avant disparition automatique — §2.4 : « reste 20 s ».
## Exporté (comme `HealZone.duration`) pour rester overridable en test sans
## attendre 20 s réelles.
@export var lifetime: float = 20.0
## Chargeurs (`WeaponConfig.mag_size`) accordés PAR ARME possédée à chaque
## ramassage — §2.4 : « +1 chargeur par arme, plafonné ».
@export var mags_per_pickup: int = 1

## Registre statique uid -> instance, alimenté uniquement par spawn_local/
## despawn_local (appelés depuis les RPC de diffusion de GameWorld.gd, y
## compris sur le serveur lui-même via "call_local") — même patron que
## WorldWeapon._registry. L'ORDRE D'INSERTION (préservé par Dictionary en
## Godot 4) donne directement l'ordre de spawn, exploité par `oldest_uid()`.
static var _registry: Dictionary = {}

var uid: int = -1


## Retrouve une cartouchière au sol par son uid.
static func find(search_uid: int) -> AmmoPack:
	return _registry.get(search_uid, null)


## Nombre de cartouchières ENCORE VIVANTES sur CE pair (plafond §2.4, appelé
## par GameWorld._server_spawn_ammo_pack AVANT d'allouer un nouvel uid).
static func active_count() -> int:
	return _registry.size()


## uid de la cartouchière la plus ANCIENNE encore vivante (première insertion
## du registre, voir sa doc ci-dessus), -1 si aucune. Sert à l'éviction du
## plafond de 16 (§2.4 : « la plus ancienne disparaît »).
static func oldest_uid() -> int:
	if _registry.is_empty():
		return -1
	return _registry.keys()[0]


## Instancie et enregistre localement une cartouchière (appelé par la
## diffusion serveur, reçue sur CHAQUE pair — y compris le serveur via
## call_local).
static func spawn_local(new_uid: int, pos: Vector3, scene: Node) -> AmmoPack:
	if scene == null or new_uid < 0 or _registry.has(new_uid):
		return null
	var pack := AmmoPack.new()
	pack.uid = new_uid
	scene.add_child(pack)
	pack.global_position = pos
	return pack


## Retire localement la cartouchière correspondant à `uid` (diffusion de
## ramassage OU éviction du plafond).
static func despawn_local(uid_to_remove: int) -> void:
	var pack: AmmoPack = _registry.get(uid_to_remove, null)
	if pack and is_instance_valid(pack):
		pack.queue_free()


func _ready() -> void:
	if uid != -1:
		_registry[uid] = self

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = _DETECTION_RADIUS
	col.shape = shape
	add_child(col)

	_spawn_model()

	# §2.4 : « reste 20 s » — connexion à SOI-MÊME (`queue_free`, méthode du
	# nœud propriétaire du timer, jamais un nœud tiers capturé dans une
	# fermeture) : conforme à la règle du projet sur les minuteries, même
	# patron que HealZone.gd.
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func _exit_tree() -> void:
	if uid != -1 and _registry.get(uid) == self:
		_registry.erase(uid)


## Objet crème et bleu de la Commission qui tourne (STYLE_BIBLE, tokens
## `enamel_cream`/`ally` — le bleu `ally` (~215°) n'est ni 300-355° ni
## 105-145°, les teintes réservées à la surbrillance ennemie). Capsule
## crème (le corps de la cartouchière) cerclée d'un anneau bleu (le liseré de
## la Commission) — matériaux Cartoon.prop (contour encre fin, "objet du
## monde", pas de teinte d'équipe).
func _spawn_model() -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.18
	capsule.height = 0.4
	body.mesh = capsule
	body.position.y = 0.3
	body.material_override = Cartoon.prop(Color(0.902, 0.882, 0.839))  # enamel_cream #E6E1D6
	add_child(body)

	var band := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.14
	torus.outer_radius = 0.2
	band.mesh = torus
	band.position.y = 0.3
	band.rotation.x = deg_to_rad(90.0)
	band.material_override = Cartoon.prop(Color(0.231, 0.545, 1.0))  # ally #3B8BFF
	add_child(band)


func _process(delta: float) -> void:
	rotation.y += delta * _SPIN_SPEED


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	for body in get_overlapping_bodies():
		if not (body is PlayerController):
			continue
		if global_position.distance_to((body as Node3D).global_position) > PICKUP_RANGE:
			continue
		var hp := body.get_node_or_null("Health") as Health
		if hp == null or hp.is_dead:
			continue
		var w := body.get_node_or_null("Weapon") as Weapon
		if w == null:
			continue
		if w.server_add_reserve_mags(mags_per_pickup):
			_notify_picked_up()
			return


## Prévient GameWorld (groupe "match") qu'un ramassage EFFECTIF a eu lieu, pour
## diffuser la disparition à tous les pairs. Ne fait RIEN si aucun GameWorld
## n'est trouvé (test isolé sans monde de jeu) — la cartouchière reste alors
## visible sur CE pair de test, sans conséquence : seul l'effet sur l'arme
## (déjà appliqué ci-dessus) est vérifié dans ce cas.
func _notify_picked_up() -> void:
	var world := get_tree().get_first_node_in_group("match")
	if world and world.has_method("server_despawn_ammo_pack"):
		world.server_despawn_ammo_pack(uid)
