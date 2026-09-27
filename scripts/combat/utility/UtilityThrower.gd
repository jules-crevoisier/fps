## UtilityThrower.gd
## Enveloppe RÉSEAU du lancer d'utilitaires (frag/flash/smoke) — même patron
## que Weapon.gd : le PROPRIÉTAIRE prédit localement (charges, équipement,
## animation, aperçu de trajectoire) avec une UtilityInventory + un
## UtilityEquip locaux ; le SERVEUR garde l'inventaire ET l'équipement
## AUTORITAIRES (une paire par joueur, sur ce nœud), valide chaque requête
## (`_server_throw`/`_server_select_utility`), fait naître l'objet volant
## (`ThrownUtility`, déterministe, voir UtilityIntegrator.gd) identiquement
## sur TOUS les pairs via une diffusion "authority/call_local", puis résout la
## détonation lui-même (dégâts/éblouissement/fumée) avant de diffuser la
## détonation (position) pour que tout le monde joue le VFX/l'audio en même
## temps.
## Bots : hors périmètre (aucune lecture d'entrée pour eux, voir
## `_owner_tick` — ils ne lancent jamais de grenade, contrat lead 2026-09-27
## point 9), mais l'API serveur (`_server_throw`) reste utilisable par un
## futur appelant BotBrain (mêmes garanties d'autorité que Weapon._server_fire).
##
## Inventaire façon CS (tâche "inventaire CS-style", 2026-09-27) : ce nœud est
## aussi désormais LE coordinateur de "l'objet actuellement en main" (arme OU
## grenade) — voir UtilityEquip.gd (machine d'état pure) et
## InventorySelection.gd (index unifié 0/1 = armes, 2/3/4 = frag/flash/smoke,
## utilisé pour la molette). Les anciennes actions dédiées par type
## (throw_frag/throw_flash/throw_smoke, touches Q/C/X) sont SUPPRIMÉES : une
## grenade s'équipe désormais par les touches 3/4/5 ou la molette
## (`PlayerInput.grenade_slot_pressed`/`weapon_next_pressed`/
## `weapon_prev_pressed`, comme les armes) et se lance avec la même action
## FIRE qu'une arme (tap = lancer immédiat, maintien = amorce/aperçu d'arc,
## relâchement = lancer — même sémantique qu'avant, simplement pilotée par
## l'action "fire" au lieu d'une action par type, voir `_handle_throw_input`).
## Pendant qu'une grenade est équipée, Weapon.gd bloque lui-même
## tir/rechargement (`UtilityEquip.blocks_weapon_actions`, des DEUX côtés
## propriétaire ET serveur) ; ADS/inspection restent bloquées côté
## ViewModel.gd/PlayerCamera.gd (ce fichier ne les pilote pas).
class_name UtilityThrower
extends Node

## `preload` par CHEMIN (jamais le nom de classe global `BlindIndicator`) —
## même raison que `ThrownUtility._StarburstMesh` : le cache des classes
## globales de Godot n'est pas garanti à jour pour un fichier tout juste
## ajouté lors d'un run gdUnit4/outil `-s` en ligne de commande.
const _BlindIndicator := preload("res://scripts/combat/utility/vfx/BlindIndicator.gd")

## Rayon (m) à l'intérieur duquel une explosion de frag ajoute du trauma de
## caméra à un joueur HUMAIN LOCAL (contrat lead : "camera shake for nearby
## players") — cosmétique pur, décidé PAR PAIR (voir `_on_detonate_broadcast`),
## jamais par le serveur : chaque pair regarde sa propre caméra locale.
const CAMERA_SHAKE_RADIUS_M := 12.0

## Décalage (m) devant la tête d'où part réellement l'objet lancé — évite que
## la sphère de collision de l'intégrateur (UtilityConfig.collision_radius)
## ne touche la propre capsule du lanceur dès le premier pas (ShotValidator.
## ORIGIN_TOLERANCE couvre encore largement cet écart côté serveur).
const THROW_ORIGIN_FORWARD_OFFSET := 0.5
## Le lancer part de la MAIN (gauche, un peu bas), pas de l'œil : parti de l'œil,
## l'arc est dans l'axe du regard et se projette en un bâton vertical au-dessus de
## l'anneau d'impact (retour utilisateur 2026-09-27). Repère caméra, en mètres.
const THROW_ORIGIN_HAND_OFFSET := Vector3(-0.22, -0.2, 0.0)

# ======================================================================
#  Vitesse de lancer (contrat lead 2026-09-27, "short throw on RIGHT click" —
#  CS convention) : LMB = lancer long (throw_speed plein, à plat le long du
#  regard, inchangé) ; RMB = lob COURT, sous-main — même direction de regard
#  mais relevée de +12° (bornée à 85°, jamais totalement vertical) et ralentie
#  par `cfg.short_throw_speed_factor`. UNE SEULE fonction pure calcule cette
#  vitesse (`throw_velocity`) : la prédiction propriétaire (`_update_arc_preview`),
#  le serveur (`_server_throw`, JAMAIS la vitesse annoncée par le client) et
#  chaque pair distant (rejoue le même vol déterministe, UtilityIntegrator)
#  l'appellent tous identiquement — direction/`short`/cfg entièrement connus de
#  chacun, donc même résultat partout sans jamais faire confiance à un vecteur
#  vitesse envoyé par le réseau.
# ======================================================================
const SHORT_THROW_PITCH_UP_DEG := 12.0
const SHORT_THROW_MAX_PITCH_DEG := 85.0

## Relève `dir` de `add_deg` degrés (tangage, jamais le lacet) au-dessus de
## l'horizontale, borné à `max_deg` au-dessus de l'horizontale — repli sur
## l'axe -Z monde si `dir` est déjà quasi vertical (aucune composante
## horizontale à laquelle raccrocher le lacet). Fonction PURE, testée
## directement (tests/combat/utility/test_throw_velocity.gd).
static func pitch_up(dir: Vector3, add_deg: float, max_deg: float) -> Vector3:
	var d := dir.normalized()
	var horiz := Vector3(d.x, 0.0, d.z)
	var yaw_dir := horiz.normalized() if horiz.length() > 0.0001 else Vector3(0.0, 0.0, -1.0)
	var current_pitch := atan2(d.y, horiz.length())
	var target_pitch := clampf(current_pitch + deg_to_rad(add_deg), -PI * 0.5, deg_to_rad(max_deg))
	return (yaw_dir * cos(target_pitch) + Vector3.UP * sin(target_pitch)).normalized()

## Vitesse de lancer RÉELLE (direction + magnitude) pour `dir` (regard, PAS
## encore normalisé nécessairement) — `short = false` : lancer long inchangé
## (plein `throw_speed` le long du regard). `short = true` : lob court (contrat
## point 1) — direction relevée par `pitch_up`, vitesse réduite par
## `cfg.short_throw_speed_factor`. SEULE source de vérité de cette vitesse :
## prédiction propriétaire, serveur ET rejeu par chaque pair distant l'appellent
## tous identiquement (voir la docstring de section ci-dessus) — jamais une
## vitesse recalculée différemment à un seul de ces trois endroits.
static func throw_velocity(dir: Vector3, cfg: UtilityConfig, short: bool) -> Vector3:
	var d := dir.normalized()
	if short:
		d = pitch_up(d, SHORT_THROW_PITCH_UP_DEG, SHORT_THROW_MAX_PITCH_DEG)
		return d * cfg.throw_speed * cfg.short_throw_speed_factor
	return d * cfg.throw_speed

## PROPRIÉTAIRE uniquement : prédiction locale du lancer (FP arms/CharacterAnimator,
## voir ViewModel.gd / CharacterAnimator.gd `_on_utility_fired`).
signal fired(kind: int)
## Diffusé à TOUS les pairs SAUF le lanceur (écho cosmétique pour les
## observateurs, même schéma que Weapon.remote_fired) — anime le corps tiers
## du lanceur vu par les AUTRES.
signal remote_fired(kind: int)
## PROPRIÉTAIRE uniquement : charges à jour (prédiction OU correction serveur)
## — consommé par InventoryHUD.gd.
signal charges_changed(charges: Array)
## PROPRIÉTAIRE uniquement, reçu par CE joueur en tant que VICTIME d'un flash
## (voir `_apply_blind_to_target`) — GameHUD.gd anime l'incrustation blanche.
signal local_blinded(duration_s: float)
## PROPRIÉTAIRE uniquement : l'objet en main a changé (prédiction OU
## correction serveur) — `kind` = UtilityDatabase.FRAG/FLASH/SMOKE, ou -1 pour
## "de retour sur l'arme" (contrat "inventaire CS-style", point 6 : ViewModel.gd
## déclenche FP_Draw sur une transition vers -1 ; InventoryHUD.gd s'en sert
## pour surligner la bonne rangée).
signal equipped_changed(kind: int)

var player: PlayerController
var camera: Camera3D

# ---- Prédiction locale (propriétaire uniquement) ----
var _inv: UtilityInventory
## Objet actuellement en main (arme = -1, ou UtilityDatabase.FRAG/FLASH/SMOKE) —
## copie PRÉDITE, voir UtilityEquip.gd. Toujours -1 pour un BOT (jamais
## touché, `_owner_tick` court-circuite entièrement pour eux).
var _equip := UtilityEquip.new()
## >= 0.0 pendant qu'une pression de "fire" OU "aim" est en cours sur la
## grenade ÉQUIPÉE (secondes de maintien écoulées depuis l'appui) — < 0.0 =
## relâché. Remplace l'ancien `_held_time` (Dictionary par type, un seul type
## possible à la fois de toute façon depuis que `_equip` fixe UN SEUL objet en
## main). Contrat point 1 ("short throw on RIGHT click") : UNE SEULE de ces
## deux touches peut être "en cours de maintien" à la fois — voir `_held_short`
## juste en dessous et `_handle_throw_input` ("if one button is already held,
## ignore the other until release").
var _held_elapsed: float = -1.0
## Vrai si le maintien EN COURS (`_held_elapsed >= 0.0`) a été démarré par
## "aim" (RMB, lob court) plutôt que "fire" (LMB, lancer long) — n'a de sens
## QUE pendant un maintien (`_held_elapsed >= 0.0`), jamais lu autrement.
var _held_short: bool = false
## État de "aim" (RMB) à la frame PRÉCÉDENTE — PlayerInput n'expose que
## `aim_held` (niveau, potentiellement une BASCULE si Settings.hold_to_aim est
## désactivé, voir sa docstring), jamais un front montant dédié comme
## `fire_pressed` : ce champ permet de dériver ce front nous-mêmes
## (`aim_held and not _prev_aim_held`, voir `_handle_throw_input`) sans toucher
## à PlayerInput.gd (hors du périmètre de fichiers de cette tâche).
var _prev_aim_held: bool = false
## Ruban continu de trajectoire (contrat lead 2026-09-27, "la ligne de courbe
## de la grenade" — remplace l'ancien chapelet de points, voir `_ARC_DOT_*`
## d'origine désormais supprimés) : UN SEUL nœud + UN SEUL ImmediateMesh
## alloués une fois (`_ensure_arc_nodes`), reconstruits (jamais réalloués)
## chaque frame de maintien (voir `_update_arc_preview`/`_rebuild_arc_line`).
var _arc_line: MeshInstance3D
var _arc_line_mesh: ImmediateMesh
var _arc_line_mat: StandardMaterial3D
var _landing_ring: MeshInstance3D
var _landing_ring_outline: MeshInstance3D
var _landing_ring_mat: StandardMaterial3D
var _landing_ring_outline_mat: StandardMaterial3D
var _ring_pulse_t: float = 0.0

# ---- Autorité serveur (une instance par joueur, vit sur ce nœud) ----
var _server_inv: UtilityInventory
## Copie AUTORITAIRE de l'objet en main (voir `_equip` ci-dessus) — le
## serveur rejette tout tir d'arme et tout lancer d'un type différent tant
## qu'elle est non-nulle (contrat point 8).
var _server_equip := UtilityEquip.new()
var _limiters: Dictionary = {}     # kind -> RateLimiter
var _server_clock: float = 0.0
## Cadence maximale acceptée par type (jetons/s, rafale 1) — les charges
## limitent déjà à 1 lancer par vie, ce limiteur ne couvre que le sursaut de
## requêtes dupliquées avant que la correction de charge n'arrive (même rôle
## que Weapon._limiter_for pour les tirs).
const THROW_RATE_PER_SEC := 2.0
const THROW_BURST := 1.0

static var _next_uid: int = 1

func _ready() -> void:
	player = get_parent() as PlayerController
	_inv = UtilityInventory.new()
	if multiplayer.is_server():
		_server_inv = UtilityInventory.new()
	charges_changed.emit(_inv.snapshot())

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_clock += delta
		if _server_equip.tick(delta):
			pass  # retour auto à l'arme (copie serveur) : rien à diffuser (voir docstring de classe).
	if player and player.is_multiplayer_authority() and player.is_local_human():
		_owner_tick(delta)

# ======================================================================
#  PROPRIÉTAIRE — entrée, prédiction, aperçu de trajectoire
# ======================================================================
func _owner_tick(delta: float) -> void:
	if camera == null:
		camera = player.camera
	_handle_equip_input()
	if _equip.tick(delta):
		# Retour automatique à l'arme après le geste FP_Throw (contrat point 6) —
		# `tick()` ne renvoie vrai qu'UNE fois, à l'instant précis où le retour
		# se termine (voir UtilityEquip.tick).
		equipped_changed.emit(-1)
	_handle_throw_input(delta)

## Emplacement UNIFIÉ (InventorySelection, 0/1 = armes, 2/3/4 = grenades)
## actuellement en main, côté PROPRIÉTAIRE (`use_server = false`) ou SERVEUR
## (`use_server = true`) — l'arme ne bouge jamais son propre `current` quand
## une grenade est équipée (voir docstring de classe), donc l'index unifié se
## lit soit sur `_equip`/`_server_equip`, soit directement sur `weapon`.
func _current_unified(weapon: Weapon, use_server: bool) -> int:
	var equip := _server_equip if use_server else _equip
	if equip.is_equipped():
		return InventorySelection.slot_of_grenade(equip.kind)
	if weapon == null:
		return 0
	return weapon.server_current_slot() if use_server else weapon.current

## Remplissage des 2 emplacements d'arme (InventorySelection.WEAPON_SLOTS),
## côté PROPRIÉTAIRE ou SERVEUR — voir doc de `_current_unified`.
func _weapon_filled(weapon: Weapon, use_server: bool) -> Array:
	if weapon == null:
		return [false, false]
	if use_server:
		var ids := weapon.server_current_ids()
		var out: Array = []
		for id in ids:
			out.append(id != Inventory.EMPTY)
		return out
	var out2: Array = []
	for cfg in weapon.weapons:
		out2.append(cfg != null)
	return out2

## Pressions directes (1..5) et molette -> équipement d'une arme ou d'une
## grenade (contrat "inventaire CS-style", points 1/2/3). Une pression directe
## sur une touche d'ARME (1/2) dé-équipe toujours une grenade en cours — même
## si `Weapon._handle_switch_input` (inchangé, voir sa docstring) décide
## séparément si le SLOT d'arme lui-même doit changer : les deux réagissent
## au MÊME champ `weapon_slot_pressed` sans jamais se marcher dessus
## (`Inventory.equip` est idempotent sur un slot déjà courant).
func _handle_equip_input() -> void:
	var weapon := player.get_node_or_null("Weapon") as Weapon
	if player.input.weapon_slot_pressed != -1:
		if _equip.is_equipped():
			_request_unequip()
		return
	if player.input.grenade_slot_pressed != -1:
		var requested := InventorySelection.slot_of_grenade(player.input.grenade_slot_pressed)
		var current := _current_unified(weapon, false)
		if InventorySelection.can_select(requested, current, _weapon_filled(weapon, false), _inv.snapshot()):
			_request_equip(player.input.grenade_slot_pressed)
		return
	if player.input.weapon_next_pressed or player.input.weapon_prev_pressed:
		var dir := 1 if player.input.weapon_next_pressed else -1
		var current2 := _current_unified(weapon, false)
		var target := InventorySelection.next_selectable(current2, dir, _weapon_filled(weapon, false), _inv.snapshot())
		if target == current2:
			return
		if InventorySelection.is_weapon_slot(target):
			if _equip.is_equipped():
				_request_unequip()
			if weapon:
				weapon.equip_weapon_slot(InventorySelection.weapon_slot_of(target))
		else:
			_request_equip(InventorySelection.grenade_kind_of(target))

func _request_equip(kind: int) -> void:
	_equip.equip(kind)
	_held_elapsed = -1.0
	_held_short = false
	_hide_arc_preview()
	equipped_changed.emit(kind)
	if multiplayer.is_server():
		_server_select_utility(_owner_id(), kind)
	else:
		request_select_utility.rpc_id(1, kind)

func _request_unequip() -> void:
	_equip.unequip()
	_held_elapsed = -1.0
	_held_short = false
	_hide_arc_preview()
	equipped_changed.emit(-1)
	if multiplayer.is_server():
		_server_select_utility(_owner_id(), -1)
	else:
		request_select_utility.rpc_id(1, -1)

@rpc("any_peer", "call_remote", "reliable")
func request_select_utility(kind: int) -> void:
	_server_select_utility(multiplayer.get_remote_sender_id(), kind)

## Lit "fire" (LMB, lancer long, contrat point 5) ET "aim" (RMB, lob court,
## contrat point 1 — "the SAME tap/hold/release semantics as LMB") pour la
## grenade ACTUELLEMENT équipée — tap = lancer immédiat, maintien au-delà du
## seuil = aperçu d'arc (+ amorce en main pour la frag), relâchement = lancer
## (même sémantique pour les DEUX touches, voir UtilityThrowInput.gd,
## inchangé). Pendant un maintien (`_held_elapsed >= 0.0`), un appui sur l'AUTRE
## bouton bascule le mode (`switched_throw_mode`, retour utilisateur 2026-09-27)
## sans démarrer un second maintien ; seule la touche du mode ACTIF
## (`_held_short`) est relue, et son relâchement lance. Rien n'est
## lu tant que le délai de déploiement (0,25 s après équipement, contrat point
## 4) n'est pas écoulé.
## Mode du lancer en cours de maintien après un appui éventuel sur l'autre bouton :
## LMB (fire) pendant un lob court -> lancer long ; RMB (aim) pendant un lancer long
## -> lob court ; sinon inchangé. Le lancer part au relâchement du bouton ACTIF.
static func switched_throw_mode(held_short: bool, fire_pressed: bool, aim_pressed: bool) -> bool:
	if held_short and fire_pressed:
		return false
	if not held_short and aim_pressed:
		return true
	return held_short

func _handle_throw_input(delta: float) -> void:
	# Front montant de "aim" dérivé nous-mêmes (voir doc de `_prev_aim_held`) —
	# mis à jour à CHAQUE appel, même si les gardes ci-dessous sortent tôt :
	# l'état RMB brut ne doit jamais sauter une frame, quel que soit l'état de
	# la grenade cette frame-là.
	var aim_pressed := player.input.aim_held and not _prev_aim_held
	_prev_aim_held = player.input.aim_held
	if not _equip.is_equipped() or not _equip.can_start_throw():
		_hide_arc_preview()
		return
	var kind := _equip.kind
	var cfg := UtilityDatabase.get_by_id(kind)
	if cfg == null:
		_hide_arc_preview()
		return
	if _held_elapsed < 0.0:
		# Démarrage : LMB gagne en cas d'appui simultané des deux touches (cas
		# non spécifié par le contrat, ordre arbitraire mais déterministe).
		if player.input.fire_pressed:
			_held_elapsed = 0.0
			_held_short = false
		elif aim_pressed:
			_held_elapsed = 0.0
			_held_short = true
		else:
			return
	else:
		# Maintien en cours : appuyer sur L'AUTRE bouton bascule court <-> long sans
		# lancer (retour utilisateur 2026-09-27 : « au cas où c'est loupé la première
		# fois »). L'amorce de la frag continue (pas de remise à zéro du maintien).
		_held_short = switched_throw_mode(_held_short, player.input.fire_pressed, aim_pressed)
	var held_now := player.input.aim_held if _held_short else player.input.fire_held
	if held_now:
		_held_elapsed += delta
		var held := _held_elapsed
		# Frag "cuite" (contrat lead) : l'amorce démarrée au premier appui peut
		# détoner EN MAIN si on tarde trop à relâcher — jamais d'objet volant.
		# Même règle pour le lob court : "the frag fuse starts on press, exactly
		# as with LMB" (contrat point 1).
		if cfg.fuse_starts_on_press and UtilityThrowInput.should_explode_in_hand(held, cfg.fuse_time):
			_held_elapsed = -1.0
			_hide_arc_preview()
			_predict_and_request(kind, cfg, held, true, _held_short)
			return
		if UtilityThrowInput.should_show_arc(held):
			_update_arc_preview(delta, cfg, kind, held, _held_short)
		return
	# Relâchement (front descendant de la touche qui a démarré ce maintien) :
	# lance toujours, tap rapide ou après aperçu d'arc, même sémantique qu'avant.
	var held_at_release := _held_elapsed
	var short := _held_short
	_held_elapsed = -1.0
	_hide_arc_preview()
	_predict_and_request(kind, cfg, held_at_release, false, short)

## Prédiction locale (charge + animation, GF-06/GF-29 même esprit que
## Weapon._fire_local) + requête serveur. L'objet volant lui-même n'est PAS
## prédit ici (contrat lead : "every peer simulates the SAME deterministic
## path... the server's copy is authoritative" — voir `_broadcast_spawn`,
## reçu par CE pair aussi via call_local) : seule l'intention (charge/geste)
## l'est, comme la munition consommée dans Weapon._fire_local.
func _predict_and_request(kind: int, cfg: UtilityConfig, held_duration: float, exploded_in_hand: bool, short: bool) -> void:
	if not _inv.has_charge(kind):
		return
	_inv.consume(kind)
	charges_changed.emit(_inv.snapshot())
	fired.emit(kind)
	# Contrat point 6 : "after the throw animation (FP_Throw) ends, auto-switch
	# back to the last equipped WEAPON slot" — démarre le décompte MAINTENANT
	# (durée fixe UtilityEquip.RETURN_DELAY_S, voir sa doc), pour le lancer
	# RÉEL comme pour une frag qui explose EN MAIN (les deux quittent la main
	# de la même façon).
	_equip.start_return_after_throw()
	var dir := -camera.global_transform.basis.z
	var origin := _throw_origin(dir)
	_do_request_throw(kind, origin, dir, held_duration, exploded_in_hand, short)

## Objet actuellement équipé (copie PRÉDITE) — -1 si aucune grenade (arme en
## main). Consommé par Weapon.gd (bloque tir/rechargement),
## ViewModel.gd/FPArmsRig.gd (pose "prêt à lancer" + modèle d'arme masqué),
## PlayerCamera.gd (bloque le zoom ADS) et InventoryHUD.gd (rangée surlignée).
func is_utility_equipped() -> bool:
	return _equip.is_equipped()

func equipped_kind() -> int:
	return _equip.kind

## Vrai pendant le décompte de retour automatique à l'arme, APRÈS un lancer
## réel (contrat point 6) : `is_utility_equipped()` reste vrai tout du long
## (la pose "prêt à lancer" doit rester affichée jusqu'à la fin du geste
## FP_Throw), mais la grenade a déjà quitté la main — consommé par
## ViewModel._process_arms pour ne pas rattacher le mesh tenu pendant cette
## fenêtre (voir `_update_held_grenade`).
func is_returning() -> bool:
	return _equip.return_left >= 0.0

## Copie AUTORITAIRE (serveur) — consommée par Weapon._server_fire pour
## rejeter un tir tant qu'une grenade est équipée (contrat point 8). Jamais la
## copie prédite : un client modifié pourrait mentir sur son propre état local.
func is_server_utility_equipped() -> bool:
	return _server_equip.is_equipped()

## Charges COURANTES (copie défensive, voir UtilityInventory.snapshot) —
## consommé par GameHUD._acquire_player pour peupler le HUD dès le premier
## affichage, sans attendre le prochain `charges_changed` (émis seulement sur
## un CHANGEMENT, voir `_ready`/`_predict_and_request`/`_apply_sync`).
func snapshot_charges() -> Array:
	return _inv.snapshot() if _inv else []

func _owner_id() -> int:
	return str(player.name).to_int() if player else -1

# ======================================================================
#  Aperçu de trajectoire (ruban continu + marqueur d'impact au sol,
#  PROPRIÉTAIRE uniquement) — contrat lead 2026-09-27, "la ligne de courbe de
#  la grenade" : remplace l'ANCIEN chapelet de points (sphères espacées) par
#  un ruban continu FACE CAMÉRA (`_ribbon_vertices`, triangle strip, un seul
#  ImmediateMesh reconstruit — jamais réalloué — chaque frame de maintien,
#  voir `_rebuild_arc_line`) le long du CHEMIN RÉEL (UtilityIntegrator, même
#  prédiction que le vol réel — voir `_predict_arc`), tronqué au premier
#  impact ET à `_ARC_SKIP_NEAR_M`/`_ARC_TRIM_END_M` des deux bouts (voir
#  `_sub_path_between_distances`), plus un anneau plat posé sur la surface
#  touchée (INCHANGÉ).
# ======================================================================
const _ARC_LINE_NEAR_WIDTH_M := 0.035
const _ARC_LINE_FAR_WIDTH_M := 0.05
## Pas de ruban sur les premiers 0.6 m : le lancer part de la main, ce segment-là
## tombait pile sur/près du réticule (retour utilisateur 2026-09-27).
const _ARC_SKIP_NEAR_M := 0.6
## Ni ruban au-dessus de l'anneau d'impact (retour utilisateur 2026-09-27) :
## l'arc s'arrête 0.6 m avant sa descente finale, l'anneau suffit à marquer l'arrivée.
const _ARC_TRIM_END_M := 0.6
const _RING_DIAMETER_M := 0.6
const _RING_THICKNESS_M := 0.08
const _RING_OUTLINE_SCALE := 1.2
const _RING_PULSE_PERIOD_S := 0.8
const _RING_PULSE_AMOUNT := 0.08
const _RING_SURFACE_EPSILON_M := 0.02
const _INK_COLOR := Color("0E0A12")
## Une couleur par type (contrat lead) — un seul objet peut être équipé à la
## fois (`_equip.kind`, voir UtilityEquip.gd), donc jamais besoin de mélanger
## ces teintes.
const _TYPE_COLORS := {
	UtilityDatabase.FRAG: Color("E8392E"),
	UtilityDatabase.FLASH: Color("FFCE1F"),
	UtilityDatabase.SMOKE: Color("D9DDE3"),
}

func _ensure_arc_nodes() -> void:
	if _arc_line != null:
		return
	var holder := _holder()
	if holder == null:
		return

	_arc_line_mat = StandardMaterial3D.new()
	_arc_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Passe transparente (alpha 1, donc plein) : dessiné APRÈS le décor, sans
	# écrire la profondeur -> pas de contour d'encre du post-traitement (encrés, le
	# ruban serait cerné de noir comme l'étaient les anciens points). Un matériau
	# opaque sans écriture de profondeur passait, lui, sous le sol dessiné ensuite.
	_arc_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arc_line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # visible des deux faces (ruban fin, vu de biais).
	_arc_line_mesh = ImmediateMesh.new()
	_arc_line = MeshInstance3D.new()
	_arc_line.mesh = _arc_line_mesh
	_arc_line.material_override = _arc_line_mat
	_arc_line.visible = false
	holder.add_child(_arc_line)

	_landing_ring_outline_mat = StandardMaterial3D.new()
	_landing_ring_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_landing_ring_outline_mat.albedo_color = _INK_COLOR
	_landing_ring_outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_landing_ring_outline = MeshInstance3D.new()
	_landing_ring_outline.mesh = _build_ring_mesh(
		_RING_DIAMETER_M * 0.5 * _RING_OUTLINE_SCALE - _RING_THICKNESS_M,
		_RING_DIAMETER_M * 0.5 * _RING_OUTLINE_SCALE)
	_landing_ring_outline.material_override = _landing_ring_outline_mat
	_landing_ring_outline.visible = false
	holder.add_child(_landing_ring_outline)

	_landing_ring_mat = StandardMaterial3D.new()
	_landing_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_landing_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_landing_ring = MeshInstance3D.new()
	_landing_ring.mesh = _build_ring_mesh(_RING_DIAMETER_M * 0.5 - _RING_THICKNESS_M, _RING_DIAMETER_M * 0.5)
	_landing_ring.material_override = _landing_ring_mat
	_landing_ring.visible = false
	holder.add_child(_landing_ring)

## Anneau plat (annulus) dans le plan XZ LOCAL, normale +Y — laissé à
## l'appelant de poser la bonne base (voir `_place_landing_ring`) pour
## l'aligner sur la normale de la surface touchée. Fonction PURE (pas de nœud).
static func _build_ring_mesh(inner_r: float, outer_r: float, segments: int = 32) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		var ca := cos(a)
		var sa := sin(a)
		verts.append(Vector3(ca * outer_r, 0.0, sa * outer_r))
		verts.append(Vector3(ca * inner_r, 0.0, sa * inner_r))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	var indices := PackedInt32Array()
	for i in segments:
		var o0 := i * 2
		var i0 := i * 2 + 1
		var o1 := ((i + 1) % segments) * 2
		var i1 := ((i + 1) % segments) * 2 + 1
		indices.append(o0)
		indices.append(o1)
		indices.append(i0)
		indices.append(i0)
		indices.append(o1)
		indices.append(i1)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _holder() -> Node:
	return _attach_root()

## Point d'attache des nœuds cosmétiques (arc de trajectoire, objet volant) :
## `current_scene` normalement, avec repli sur `root` s'il est nul — un outil
## de capture qui remplace la boucle principale par un script `SceneTree`
## (tools/rigging/utility_filmstrip.gd) ajoute la scène directement à `root`
## SANS jamais définir `current_scene`, même cas que Weapon._spawn_tracer
## (voir sa docstring : "`current_scene` est nul quand le jeu tourne depuis un
## script SceneTree (outils de capture)").
func _attach_root() -> Node:
	if player == null or not player.is_inside_tree():
		return null
	var h: Node = player.get_tree().current_scene
	return h if h else player.get_tree().root

## Rejoue la MÊME prédiction que le vol réel (`UtilityIntegrator.step`/
## `integrate_free`, ThrownUtility._physics_process) pas à pas, mais s'arrête
## au PREMIER impact (contrat : "stop at the first collision") plutôt que de
## poursuivre les rebonds suivants comme `UtilityIntegrator.simulate_path` —
## l'arc pointillé et l'anneau au sol montrent tous deux ce même premier point
## de contact, jamais la trajectoire complète après rebond. Le point d'impact
## réel (position + normale de surface) est retrouvé par un second rayon
## EXACTEMENT entre les mêmes deux positions que celles que `step()` a
## utilisées en interne (pré-pas -> vol libre non corrigé), puisque `step()`
## ne renvoie pas la normale lui-même.
func _predict_arc(cfg: UtilityConfig, origin: Vector3, vel: Vector3) -> Dictionary:
	var space := player.get_world_3d().direct_space_state
	var exclude := [player.get_rid()]
	var dt := 1.0 / 60.0
	var max_time := 2.5
	var points: Array = [origin]
	var pre_pos := origin
	var pre_vel := vel
	var t := 0.0
	var landing_pos := origin
	var landing_normal := Vector3.UP
	while t < max_time:
		var res := UtilityIntegrator.step(pre_pos, pre_vel, dt, cfg, space, exclude)
		var new_pos: Vector3 = res["position"]
		points.append(new_pos)
		t += dt
		if res["bounced"]:
			var free_end: Vector3 = UtilityIntegrator.integrate_free(pre_pos, pre_vel, dt)["position"]
			var q := PhysicsRayQueryParameters3D.create(pre_pos, free_end, UtilityIntegrator.BOUNCE_MASK)
			q.exclude = exclude
			q.collide_with_areas = false
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				landing_pos = hit.position
				landing_normal = hit.normal
			else:
				landing_pos = new_pos
			return {"points": points, "landing_pos": landing_pos, "landing_normal": landing_normal}
		if res["at_rest"]:
			return {"points": points, "landing_pos": new_pos, "landing_normal": landing_normal}
		pre_pos = new_pos
		pre_vel = res["velocity"]
	return {"points": points, "landing_pos": points[points.size() - 1], "landing_normal": landing_normal}

## Distance cumulée (m) parcourue le long de `path` à CHAQUE sommet (même
## taille que `path`, `cum[0] == 0.0`) — calcul partagé par
## `_sub_path_between_distances`/`_point_at_distance` ci-dessous.
static func _cumulative_lengths(path: Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.append(0.0)
	for i in range(1, path.size()):
		cum.append(cum[i - 1] + (path[i - 1] as Vector3).distance_to(path[i]))
	return cum

## Point interpolé de `path` à la distance parcourue `d` depuis le début
## (bornée à [0, longueur totale]) — recherche linéaire du segment qui
## contient `d` (chemins courts, quelques centaines de points au pire, jamais
## un goulot de performance ici).
static func _point_at_distance(path: Array, cum: PackedFloat32Array, d: float) -> Vector3:
	var total: float = cum[cum.size() - 1]
	var dd := clampf(d, 0.0, total)
	for i in range(1, cum.size()):
		if dd <= cum[i] or i == cum.size() - 1:
			var seg_len: float = cum[i] - cum[i - 1]
			var f: float = 0.0 if seg_len <= 0.00001 else (dd - cum[i - 1]) / seg_len
			return (path[i - 1] as Vector3).lerp(path[i], f)
	return path[path.size() - 1]

## Portion de `path` strictement entre `start_m` (distance parcourue depuis le
## départ) et `longueur totale - end_trim_m` (voir `_ARC_SKIP_NEAR_M`/
## `_ARC_TRIM_END_M`) — remplace l'ancien `_sample_dots` (chapelet de points
## espacés) : le ruban continu (contrat lead 2026-09-27, "la ligne de courbe
## de la grenade") a besoin d'une POLYLIGNE tronquée, pas de marques
## discrètes. Insère un point interpolé EXACT à chaque borne (jamais de
## coupure à mi-segment) ; vide si la portion utile est nulle ou négative
## (lancer trop court pour laisser quoi que ce soit entre les deux coupes).
static func _sub_path_between_distances(path: Array, start_m: float, end_trim_m: float) -> Array:
	if path.size() < 2:
		return []
	var cum := _cumulative_lengths(path)
	var total: float = cum[cum.size() - 1]
	var start_m_c := maxf(start_m, 0.0)
	var end_m: float = total - maxf(end_trim_m, 0.0)
	if end_m <= start_m_c:
		return []
	var result: Array = [_point_at_distance(path, cum, start_m_c)]
	for i in path.size():
		var d: float = cum[i]
		if d > start_m_c and d < end_m:
			result.append(path[i])
	result.append(_point_at_distance(path, cum, end_m))
	return result

## Sommets gauche/droite du ruban FACE CAMÉRA le long de `points` — technique
## standard de "ruban qui suit la caméra" (trail renderer) : à chaque point, le
## côté est perpendiculaire À LA FOIS à la tangente locale (direction vers le
## point suivant, ou depuis le précédent pour le dernier point) ET à la
## direction vers la caméra, ce qui garde le ruban lisible sous n'importe quel
## angle de vue (contrat : "camera-facing ribbon"). La largeur s'interpole
## linéairement de `near_width` (premier point, `_ARC_SKIP_NEAR_M` après la
## main) à `far_width` (dernier point, juste avant l'anneau d'impact).
## Fonction PURE (aucun nœud, `camera_pos` passé en paramètre) — testée
## directement (tests/combat/utility/test_arc_line.gd). Chaque élément du
## résultat : {"left": Vector3, "right": Vector3}.
static func _ribbon_vertices(points: Array, camera_pos: Vector3, near_width: float, far_width: float) -> Array:
	var n := points.size()
	if n < 2:
		return []
	var result: Array = []
	for i in n:
		var p: Vector3 = points[i]
		var tangent: Vector3 = ((points[i + 1] as Vector3) - p) if i < n - 1 else (p - (points[i - 1] as Vector3))
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var to_cam := camera_pos - p
		if to_cam.length_squared() < 0.000001:
			to_cam = Vector3.UP
		var side := tangent.cross(to_cam.normalized())
		if side.length_squared() < 0.000001:
			# Tangente quasi alignée avec la caméra (rare, bout de trajectoire vu
			# de face) : repli sur un côté horizontal arbitraire plutôt qu'un
			# ruban dégénéré (largeur nulle).
			side = tangent.cross(Vector3.UP)
			if side.length_squared() < 0.000001:
				side = Vector3.RIGHT
		side = side.normalized()
		var half_w := lerpf(near_width, far_width, float(i) / float(n - 1)) * 0.5
		result.append({"left": p + side * half_w, "right": p - side * half_w})
	return result

## Point de départ du lancer (aperçu ET lancer réel, pour que l'arc dise vrai) :
## devant la tête, décalé vers la main qui tient la grenade. Si un mur se trouve
## entre la tête et ce point, on s'arrête juste devant lui (jamais de grenade qui
## naît de l'autre côté d'une paroi collée au joueur).
func _throw_origin(dir: Vector3) -> Vector3:
	var head := player.head.global_position
	var b := camera.global_transform.basis
	var wanted := head + dir.normalized() * THROW_ORIGIN_FORWARD_OFFSET 		+ b.x * THROW_ORIGIN_HAND_OFFSET.x + b.y * THROW_ORIGIN_HAND_OFFSET.y
	return clamp_origin_to_world(player.get_world_3d().direct_space_state, head, wanted, player.get_rid())

## Ramène `wanted` devant le premier obstacle du MONDE sur le segment tête -> wanted
## (5 cm de marge le long de la normale) ; inchangé si le segment est libre.
static func clamp_origin_to_world(space: PhysicsDirectSpaceState3D, head: Vector3, wanted: Vector3,
		exclude_rid: RID) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(head, wanted, PhysicsLayers.WORLD)
	q.exclude = [exclude_rid]
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return wanted
	return hit.position + (hit.normal as Vector3) * 0.05

## Aperçu de trajectoire pour LMB (`short = false`, lancer long) ET RMB
## (`short = true`, lob court, contrat point 1) — chacun avec SA PROPRE
## vitesse (`UtilityThrower.throw_velocity`, jamais un seul calcul partagé qui
## ignorerait le relèvement/ralentissement du lob court).
func _update_arc_preview(delta: float, cfg: UtilityConfig, kind: int, held: float, short: bool) -> void:
	if player == null or not player.is_inside_tree():
		return
	_ensure_arc_nodes()
	if _arc_line == null:
		return
	var dir := -camera.global_transform.basis.z
	var origin := _throw_origin(dir)
	var vel := UtilityThrower.throw_velocity(dir, cfg, short)
	var prediction := _predict_arc(cfg, origin, vel)
	var points: Array = prediction["points"]

	var color: Color = _TYPE_COLORS.get(kind, Color.WHITE)
	var sub_path := _sub_path_between_distances(points, _ARC_SKIP_NEAR_M, _ARC_TRIM_END_M)
	_rebuild_arc_line(sub_path, color)

	# Frag "cuite" (contrat : "the ring's colour shifts to white as the fuse
	# runs out") — seule la frag amorce SON amorce dès l'appui
	# (`fuse_starts_on_press`), donc `held` n'est une fraction de fuse
	# pertinente que pour elle ; flash/smoke gardent leur teinte pleine.
	var cook_frac := 0.0
	if kind == UtilityDatabase.FRAG and cfg.fuse_starts_on_press and cfg.fuse_time > 0.0:
		cook_frac = clampf(held / cfg.fuse_time, 0.0, 1.0)
	_ring_pulse_t += delta
	_place_landing_ring(prediction["landing_pos"], prediction["landing_normal"], color, cook_frac)

## Reconstruit le ruban continu (ImmediateMesh, triangle strip) à partir de
## `sub_path` (déjà tronqué aux deux bouts, voir `_sub_path_between_distances`)
## — `_arc_line.global_transform` remis à l'IDENTITÉ à chaque reconstruction :
## les sommets de `_ribbon_vertices` sont en coordonnées MONDE (comme
## `_predict_arc`), l'identité garantit que l'espace LOCAL de l'ImmediateMesh
## coïncide avec elles quel que soit le parent réel de `_holder()` (même
## garantie que `_place_landing_ring`, qui pose directement `global_transform`).
func _rebuild_arc_line(sub_path: Array, color: Color) -> void:
	_arc_line_mesh.clear_surfaces()
	if sub_path.size() < 2:
		_arc_line.visible = false
		return
	_arc_line.global_transform = Transform3D.IDENTITY
	_arc_line_mat.albedo_color = color
	var verts := _ribbon_vertices(sub_path, camera.global_position, _ARC_LINE_NEAR_WIDTH_M, _ARC_LINE_FAR_WIDTH_M)
	_arc_line_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for v in verts:
		_arc_line_mesh.surface_add_vertex(v["left"])
		_arc_line_mesh.surface_add_vertex(v["right"])
	_arc_line_mesh.surface_end()
	_arc_line.visible = true

## Pose l'anneau (+ son liseré encre) à plat sur `pos`, sa base alignée sur la
## normale `normal` de la surface touchée (l'axe Y LOCAL du maillage — voir
## `_build_ring_mesh` — devient `normal`), avec une pulsation d'échelle douce
## (±8 %, période 0.8 s).
func _place_landing_ring(pos: Vector3, normal: Vector3, color: Color, cook_frac: float) -> void:
	if _landing_ring == null:
		return
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var arbitrary := Vector3.RIGHT if absf(n.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x_axis := arbitrary.cross(n).normalized()
	var z_axis := n.cross(x_axis).normalized()
	var basis := Basis(x_axis, n, z_axis)
	var pulse := 1.0 + sin(_ring_pulse_t * TAU / _RING_PULSE_PERIOD_S) * _RING_PULSE_AMOUNT
	var xform := Transform3D(basis.scaled(Vector3.ONE * pulse), pos + n * _RING_SURFACE_EPSILON_M)

	_landing_ring.global_transform = xform
	_landing_ring_outline.global_transform = xform
	_landing_ring.visible = true
	_landing_ring_outline.visible = true
	_landing_ring_mat.albedo_color = color.lerp(Color.WHITE, cook_frac)

func _hide_arc_preview() -> void:
	if _arc_line:
		_arc_line.visible = false
		_arc_line_mesh.clear_surfaces()
	if _landing_ring:
		_landing_ring.visible = false
	if _landing_ring_outline:
		_landing_ring_outline.visible = false

# ======================================================================
#  REQUÊTES CLIENT -> SERVEUR (même motif que Weapon.gd)
# ======================================================================
func _do_request_throw(kind: int, origin: Vector3, dir: Vector3, held_duration: float, exploded_in_hand: bool, short: bool) -> void:
	if multiplayer.is_server():
		_server_throw(_owner_id(), kind, origin, dir, held_duration, exploded_in_hand, short)
	else:
		request_throw.rpc_id(1, kind, origin, dir, held_duration, exploded_in_hand, short)

@rpc("any_peer", "call_remote", "reliable")
func request_throw(kind: int, origin: Vector3, dir: Vector3, held_duration: float, exploded_in_hand: bool, short: bool) -> void:
	_server_throw(multiplayer.get_remote_sender_id(), kind, origin, dir, held_duration, exploded_in_hand, short)

# ======================================================================
#  SERVEUR — validation puis résolution
# ======================================================================
func _server_throw(sender_id: int, kind: int, origin: Vector3, dir: Vector3, held_duration: float, exploded_in_hand: bool, short: bool) -> void:
	if not multiplayer.is_server() or sender_id != _owner_id() or _server_inv == null:
		return
	var cfg := UtilityDatabase.get_by_id(kind)
	if cfg == null:
		return
	var hp := player.get_node_or_null("Health") as Health
	var alive := not (hp and hp.is_dead)
	if not UtilityValidator.can_throw(alive, _server_inv.has_charge(kind), _round_locked()):
		_push_charge_sync()
		return
	# Inventaire CS-style (contrat point 8) : "rejects a throw whose kind is
	# not the equipped one" — un client modifié pourrait sinon lancer un type
	# qu'il n'a jamais équipé (aucune pose "prêt", aucun délai de déploiement
	# respecté côté serveur). Le délai de déploiement (0,25 s après
	# équipement, point 4) est vérifié séparément juste en dessous.
	if kind != _server_equip.kind:
		_push_charge_sync()
		return
	if not _server_equip.can_start_throw():
		_push_charge_sync()
		return
	var head_pos: Vector3 = player.head.global_position
	if not UtilityValidator.is_valid_request(origin, head_pos, dir, held_duration, cfg, short):
		_push_charge_sync()
		return
	if not _limiter_for(kind).try_take(_server_clock):
		_push_charge_sync()
		return
	_server_inv.consume(kind)
	_push_charge_sync()
	# Contrat point 6 : la copie SERVEUR démarre son propre décompte de retour
	# (indépendant de celui du propriétaire, même valeur fixe
	# UtilityEquip.RETURN_DELAY_S — voir `_physics_process`) : le serveur ne
	# doit jamais dépendre du timing client pour rouvrir le tir/rechargement.
	_server_equip.start_return_after_throw()

	var thrower_id := _owner_id()
	var thrower_team := int(player.team)
	if exploded_in_hand:
		_server_detonate(kind, -1, head_pos, cfg, thrower_id, thrower_team)
		return

	var uid := _next_uid
	_next_uid += 1
	# JAMAIS une vitesse envoyée par le client (contrat point 1) — recalculée
	# ICI, côté serveur, depuis (direction, short, cfg) par la MÊME fonction
	# pure que la prédiction propriétaire (`_update_arc_preview`), pour que
	# prédiction = serveur = pairs distants (voir la docstring de
	# `UtilityThrower.throw_velocity`).
	var vel := UtilityThrower.throw_velocity(dir, cfg, short)
	var fuse_left := cfg.fuse_time if not cfg.fuse_starts_on_press else UtilityThrowInput.fuse_left_on_release(held_duration, cfg.fuse_time)
	_broadcast_spawn.rpc(uid, kind, origin, vel, fuse_left, thrower_id, thrower_team)

## Requête d'équipement/dé-équipement (contrat "inventaire CS-style", RPC
## symétrique à `_server_throw` : le propriétaire prédit localement, le
## serveur garde la vérité et corrige en cas de refus (`_push_equip_sync`,
## jamais sur un succès — même discipline que `Weapon._server_equip`).
## `kind == -1` = retour à l'arme, toujours autorisé (aucune charge à
## vérifier, jamais refusé).
func _server_select_utility(sender_id: int, kind: int) -> void:
	if not multiplayer.is_server() or sender_id != _owner_id() or _server_inv == null:
		return
	if kind == -1:
		_server_equip.unequip()
		return
	var weapon := player.get_node_or_null("Weapon") as Weapon
	var requested := InventorySelection.slot_of_grenade(kind)
	var current := _current_unified(weapon, true)
	if not InventorySelection.can_select(requested, current, _weapon_filled(weapon, true), _server_inv.snapshot()):
		_push_equip_sync()
		return
	_server_equip.equip(kind)

func _limiter_for(kind: int) -> RateLimiter:
	if not _limiters.has(kind):
		_limiters[kind] = RateLimiter.new(THROW_RATE_PER_SEC, THROW_BURST)
	return _limiters[kind]

## Manche verrouillée (BUY/PREROUND) — même règle que Weapon._round_locked.
func _round_locked() -> bool:
	var m := player.get_tree().get_first_node_in_group("match")
	if m == null:
		return false
	var v = m.get("round_locked")
	return false if v == null else bool(v)

func _push_charge_sync() -> void:
	if not multiplayer.is_server() or _server_inv == null:
		return
	var d := _server_inv.to_dict()
	if player.is_multiplayer_authority():
		_apply_sync(d)
	else:
		_sync_charges.rpc_id(_owner_id(), d)

@rpc("authority", "call_remote", "reliable")
func _sync_charges(d: Dictionary) -> void:
	_apply_sync(d)

func _apply_sync(d: Dictionary) -> void:
	_inv = UtilityInventory.from_dict(d)
	charges_changed.emit(_inv.snapshot())

## Même discipline que `_push_charge_sync` (équipement), appelée uniquement
## quand le serveur DOIT corriger la prédiction (refus, ou reset mort/respawn
## ci-dessous) — jamais sur un succès de `_server_select_utility` (le
## propriétaire a déjà prédit exactement la même chose).
func _push_equip_sync() -> void:
	if not multiplayer.is_server() or _server_inv == null:
		return
	var d := _server_equip.to_dict()
	if player.is_multiplayer_authority():
		_apply_equip_sync(d)
	else:
		_sync_equip.rpc_id(_owner_id(), d)

@rpc("authority", "call_remote", "reliable")
func _sync_equip(d: Dictionary) -> void:
	_apply_equip_sync(d)

## N'émet `equipped_changed` QUE si la valeur change réellement (contrat point
## 6 : ViewModel.gd déclenche FP_Draw sur une transition VERS -1 — un signal
## répété sur une valeur inchangée redéclencherait ce tirage sans raison).
func _apply_equip_sync(d: Dictionary) -> void:
	var before := _equip.kind
	_equip = UtilityEquip.from_dict(d)
	if _equip.kind != before:
		equipped_changed.emit(_equip.kind)

# ======================================================================
#  API SERVEUR — appelée par le mode de jeu (spawn/mort, GameWorld.gd)
# ======================================================================
func server_refill_charges() -> void:
	if not multiplayer.is_server() or _server_inv == null:
		return
	_server_inv.refill()
	# Contrat point 7 : "on respawn, the equipped item resets to the primary
	# weapon" — server_refill_charges() est déjà appelé exactement au spawn
	# (voir GameWorld.gd), aucun nouveau point d'appel nécessaire.
	_server_equip.reset_on_death_or_respawn()
	_push_charge_sync()
	_push_equip_sync()

func server_clear_charges() -> void:
	if not multiplayer.is_server() or _server_inv == null:
		return
	_server_inv.clear()
	# Contrat point 7 : "on death, the equipped item resets to the primary
	# weapon" — server_clear_charges() est déjà appelé exactement à la mort
	# (voir GameWorld.gd).
	_server_equip.reset_on_death_or_respawn()
	_push_charge_sync()
	_push_equip_sync()

# ======================================================================
#  DIFFUSION — naissance de l'objet volant (tous les pairs, y compris le
#  serveur via call_local — même schéma que Weapon._broadcast_world_spawn)
# ======================================================================
@rpc("authority", "call_local", "reliable")
func _broadcast_spawn(uid: int, kind: int, origin: Vector3, vel: Vector3, fuse_left: float, thrower_id: int, thrower_team: int) -> void:
	remote_fired.emit(kind)
	var scene := _attach_root()
	if scene == null:
		return
	var is_authority := multiplayer.is_server()
	ThrownUtility.spawn_local(uid, kind, origin, vel, fuse_left, thrower_id, thrower_team, scene, is_authority, self if is_authority else null)

## Appelé UNIQUEMENT par l'instance AUTORITAIRE de ThrownUtility (voir
## ThrownUtility._check_detonate) quand l'amorce (ou le contact au sol pour la
## fumée) est atteinte — résout les effets de jeu puis diffuse la détonation
## (position) pour que tout le monde joue le VFX/l'audio ensemble.
func server_on_thrown_detonate(kind: int, uid: int, pos: Vector3, cfg: UtilityConfig, thrower_id: int, thrower_team: int) -> void:
	_server_detonate(kind, uid, pos, cfg, thrower_id, thrower_team)

func _server_detonate(kind: int, uid: int, pos: Vector3, cfg: UtilityConfig, thrower_id: int, thrower_team: int) -> void:
	match kind:
		UtilityDatabase.FRAG:
			_apply_frag_effects(pos, cfg, thrower_id, thrower_team)
		UtilityDatabase.FLASH:
			_apply_flash_effects(pos, cfg, thrower_id, thrower_team)
		UtilityDatabase.SMOKE:
			pass  # le nuage lui-même est posé cosmétiquement par CHAQUE pair, voir _on_detonate_broadcast.
	_broadcast_detonate.rpc(uid, kind, pos)

## Tous les joueurs vivants (humains + bots), SERVEUR uniquement — même lieu
## de recherche que Health._source_position/BotBrain._visible_enemies
## (conteneur "Players" partagé, GameWorld._spawn_player).
func _all_players() -> Array:
	if player == null or not player.is_inside_tree():
		return []
	var world := player.get_tree().get_first_node_in_group("match")
	if world == null:
		return []
	var root := world.get_node_or_null(world.players_root) if "players_root" in world else null
	return root.get_children() if root else []

func _apply_frag_effects(pos: Vector3, cfg: UtilityConfig, thrower_id: int, thrower_team: int) -> void:
	_apply_frag_effects_to(_all_players(), pos, cfg, thrower_id, thrower_team)

## Dégâts de frag sur `targets` (séparé de la recherche des joueurs pour les tests).
func _apply_frag_effects_to(targets: Array, pos: Vector3, cfg: UtilityConfig, thrower_id: int, thrower_team: int) -> void:
	var space := player.get_world_3d().direct_space_state
	for target in targets:
		var hp := target.get_node_or_null("Health") as Health
		if hp == null or hp.is_dead:
			continue
		var target_id: int = str(target.name).to_int()
		var chest: Vector3 = (target.head.global_position if target.head else target.global_position) - Vector3(0, 0.3, 0)
		var dist := pos.distance_to(chest)
		var has_los := _has_los(space, pos, chest, target.get_rid())
		var is_self := target_id == thrower_id
		var same_team := int(target.team) == thrower_team
		var dmg := FragMath.damage_for_target(dist, cfg, is_self, same_team, has_los)
		if dmg > 0.0:
			hp.apply_damage(dmg, thrower_id, false)
			# Chiffre de dégâts chez le LANCEUR, comme pour une balle (retour utilisateur
			# 2026-09-27 : savoir si la frag a touché, même derrière un mur --
			# DamageNumber3D est dessiné sans test de profondeur). Pas sur soi-même.
			if not is_self:
				var thrower_weapon := player.get_node_or_null("Weapon") as Weapon
				if thrower_weapon:
					thrower_weapon._confirm_hit(thrower_id, chest + Vector3(0, 0.3, 0), dmg, false, hp.is_dead, target_id)

func _apply_flash_effects(pos: Vector3, cfg: UtilityConfig, thrower_id: int, thrower_team: int) -> void:
	var space := player.get_world_3d().direct_space_state
	for target in _all_players():
		var hp := target.get_node_or_null("Health") as Health
		if hp == null or hp.is_dead:
			continue
		var head: Vector3 = target.head.global_position if target.head else target.global_position
		var dist := pos.distance_to(head)
		if dist > cfg.flash_radius:
			continue
		# Une flash ne traverse pas un fumigène (demande utilisateur 2026-09-27) :
		# derrière la fumée, ou flash qui éclate DANS la fumée -> personne n'est ébloui.
		var has_los := _has_los(space, pos, head, target.get_rid()) and not smoke_between(space, pos, head)
		var target_id: int = str(target.name).to_int()
		var is_self := target_id == thrower_id
		var same_team := int(target.team) == thrower_team
		var victim_forward: Vector3 = -target.global_transform.basis.z
		var dot := FlashMath.facing_dot(victim_forward, (pos - head))
		var duration := FlashMath.blind_duration_for_target(dist, dot, cfg, is_self, same_team, has_los)
		if duration <= 0.0:
			continue
		if bool(target.get("is_bot")):
			target.set_meta("blinded_until", Time.get_ticks_msec() / 1000.0 + FlashMath.impaired_seconds(duration))
		else:
			_notify_blind_target(target, duration)
		# Contrat point 4 ("visual tell on a flashed player") : diffusé à TOUS
		# les pairs (bot OU humain visé, `call_local` -> l'hôte le voit aussi
		# pour ses propres bots simulés) — jamais seulement au joueur VISÉ
		# (ci-dessus, son incrustation blanche est un système séparé).
		_broadcast_blind_indicator.rpc(str(target.name), FlashMath.impaired_seconds(duration))

## Notifie le JOUEUR HUMAIN visé (jamais un bot, voir l'appelant) via son
## propre UtilityThrower — appel DIRECT s'il est simulé ICI (hôte), sinon RPC
## ciblée (même distinction que Health._push_damage_direction).
func _notify_blind_target(target: PlayerController, duration: float) -> void:
	var target_utility := target.get_node_or_null("UtilityThrower") as UtilityThrower
	if target_utility == null:
		return
	if target.is_multiplayer_authority():
		target_utility.local_blinded.emit(duration)
	else:
		target_utility._notify_blind.rpc_id(str(target.name).to_int(), duration)

@rpc("authority", "call_remote", "reliable")
func _notify_blind(duration: float) -> void:
	local_blinded.emit(duration)

## Diffusée à TOUS les pairs (contrat point 4, "so you can see whether you
## flashed the enemy") : chaque pair fait pop un tell comique au-dessus de la
## tête DE LA CIBLE (jamais sur la vue de la VICTIME locale elle-même, qui voit
## déjà son incrustation plein écran via `local_blinded`/`_notify_blind`
## ci-dessus — un système entièrement séparé). Résout `target_name` (nom du
## nœud joueur, voir `_all_players`) sur CE pair, jamais transmis comme
## référence de nœud (RPC réseau, seul un nom/id voyage).
@rpc("authority", "call_local", "reliable")
func _broadcast_blind_indicator(target_name: String, duration: float) -> void:
	var target := _find_player_by_name(target_name)
	if target == null:
		return
	if target.is_in_group("local_player"):
		return
	_BlindIndicator.apply_to(target, duration)

func _find_player_by_name(target_name: String) -> Node:
	for p in _all_players():
		if str(p.name) == target_name:
			return p
	return null

## Vrai si un fumigène (collider serveur du calque VISION, voir SmokeCloud) coupe
## le segment `from` -> `to`, y compris quand `from` est DANS la fumée
## (`hit_from_inside`) : une flash qui éclate dans un fumigène n'éblouit personne.
## Requête séparée du monde pour que `hit_from_inside` ne s'applique qu'aux fumées
## (sinon une grenade posée contre un joueur « serait dans » sa capsule).
static func smoke_between(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.VISION)
	q.hit_from_inside = true
	q.collide_with_areas = false
	return not space.intersect_ray(q).is_empty()

## Ligne de vue (raycast contre la géométrie du MONDE seule, contrat lead —
## PhysicsLayers.WORLD, pas SHOT_MASK : une fumée ne protège pas d'une
## explosion, seuls les murs le font ; pour la flash, voir `smoke_between`).
func _has_los(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude_rid: RID) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, PhysicsLayers.WORLD)
	q.exclude = [exclude_rid]
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	return hit.is_empty()

# ======================================================================
#  Diffusion — détonation (VFX/audio + cosmétique caméra, TOUS les pairs)
# ======================================================================
@rpc("authority", "call_local", "reliable")
func _broadcast_detonate(uid: int, kind: int, pos: Vector3) -> void:
	ThrownUtility.on_detonate_broadcast(uid, kind, pos, self)
	_maybe_shake_local_camera(kind, pos)

func _maybe_shake_local_camera(kind: int, pos: Vector3) -> void:
	if kind != UtilityDatabase.FRAG:
		return
	var locals := get_tree().get_nodes_in_group("local_player")
	if locals.is_empty():
		return
	var me := locals[0] as PlayerController
	if me == null or me.camera == null:
		return
	if me.global_position.distance_to(pos) > CAMERA_SHAKE_RADIUS_M:
		return
	var cam := me.camera as PlayerCamera
	if cam:
		cam.add_explosion_trauma()
