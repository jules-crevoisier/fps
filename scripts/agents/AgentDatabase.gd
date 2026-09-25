## AgentDatabase.gd
## Catalogue des agents (construits en code) + agent sélectionné par le joueur.
## 6 agents, 3 rôles (Entrée, Contrôle, Soutien) x 2, chacun avec un PASSIF
## (toujours actif, sans touche -- AgentConfig.passive, docs/research/
## 10_ammo_kits_input.md §3.5) et 4 capacités à touche (C/Q/E + ultime X)
## construites à partir des primitives d'effet partagées dans
## scripts/agents/abilities/ (mouvement, soin, mur, fumée, tremplin, piège
## étourdissant, éblouissement, reveal, charge, grappin, glu, zone de soin) et
## des passifs de scripts/agents/passives/ -- voir docs/AGENTS.md pour le
## détail et le contre-jeu de chacun. AGT-09 (docs/research/
## 10_ammo_kits_input.md §3.3, "Kits d'agents : un passif et une signature
## unique chacun") : chaque agent reçoit ici son passif ET sa capacité E
## SIGNATURE, qu'aucun autre agent ne porte -- les primitives partagées
## (mur/fumée/tremplin/piège) restent sur C/Q/X, jamais sur E.
class_name AgentDatabase
extends RefCounted

const DASH := preload("res://scripts/agents/abilities/DashAbility.gd")
const WALL := preload("res://scripts/agents/abilities/WallAbility.gd")
const SURGE := preload("res://scripts/agents/abilities/SurgeAbility.gd")
const FLASH := preload("res://scripts/agents/abilities/FlashAbility.gd")
const SMOKE := preload("res://scripts/agents/abilities/SmokeAbility.gd")
const JUMP_PAD := preload("res://scripts/agents/abilities/JumpPadAbility.gd")
const STUN_TRAP := preload("res://scripts/agents/abilities/StunTrapAbility.gd")
const REVEAL := preload("res://scripts/agents/abilities/RevealAbility.gd")
const STUN_BURST := preload("res://scripts/agents/abilities/StunBurstAbility.gd")
const RENEWAL := preload("res://scripts/agents/abilities/RenewalAbility.gd")
const BASTION := preload("res://scripts/agents/abilities/BastionAbility.gd")
## Signatures E (AGT-09) -- une seule porteuse chacune, voir §3.3.
const BELL_CHARGE := preload("res://scripts/agents/abilities/BellChargeAbility.gd")   # Choc  -- Tape-la-cloche
const FAUX_DEPART := preload("res://scripts/agents/abilities/FauxDepartAbility.gd")   # Vif   -- Faux départ
const GRAPPLE := preload("res://scripts/agents/abilities/GrappleAbility.gd")          # Vanne -- Piquet d'arpenteur
const GLUE := preload("res://scripts/agents/abilities/GlueAbility.gd")                # Verrou-- Glu
const BALM_ZONE := preload("res://scripts/agents/abilities/BalmZoneAbility.gd")       # Roseau-- Baume du Palud

## Passifs (AGT-09, scripts/agents/passives/) -- aucun `class_name` (même
## convention que les capacités concrètes ci-dessus), sauf SangFroid qui en
## porte déjà un (préchargé quand même, par cohérence avec ce catalogue).
const MECHE_COURTE := preload("res://scripts/agents/passives/MecheCourte.gd")     # Vif
const TETE_DE_CLOCHE := preload("res://scripts/agents/passives/TeteDeCloche.gd")  # Choc
const RELEVE := preload("res://scripts/agents/passives/Releve.gd")                # Vanne
const PLANEUR := preload("res://scripts/agents/passives/Planeur.gd")              # Guet
const BAUME_AU_REPOS := preload("res://scripts/agents/passives/BaumeAuRepos.gd")  # Roseau
const SANG_FROID := preload("res://scripts/agents/passives/SangFroid.gd")         # Verrou

const SLOTS := ["C", "Q", "E", "X"]

## UX-21 -- icônes peintes des capacités/passifs (30 : 6 agents x [passif, C,
## Q, E signature, X ultime]), détourées par tools/ui/slice_icon_sheets.py à
## partir des planches Tripo assets/incoming/tripo/icons/. Nommage
## `<agent>_<slot>.png` en ascii minuscule (indépendant des accents/majuscules
## d'`AgentConfig.agent_name`) : c'est ce dictionnaire, propriété exclusive
## d'AgentDatabase, qui fait le lien -- AgentConfig/Ability/Passive (hors de
## mon périmètre d'écriture ici) ne portent aucun champ `icon`.
const ICON_DIR := "res://assets/ui/icons/abilities/"
const _ICON_AGENT_KEY := {
	"Vif": "vif", "Choc": "choc", "Vanne": "vanne",
	"Guet": "guet", "Roseau": "roseau", "Verrou": "verrou",
}
static var _icon_cache: Dictionary = {}  # chemin -> Texture2D | null (résolu une fois)

const ROLE_ENTREE := "Entrée"
const ROLE_CONTROLE := "Contrôle"
const ROLE_SOUTIEN := "Soutien"
## Ordre d'affichage des rôles (bandeau de composition d'équipe, UX-11).
const ROLES := [ROLE_ENTREE, ROLE_CONTROLE, ROLE_SOUTIEN]

## Fichier de persistance DU SEUL "dernier agent joué" (UX-11) — séparé du
## `user://settings.cfg` de Settings.gd (hors du périmètre de cette tâche) :
## un petit ConfigFile autonome, propriété exclusive d'AgentDatabase.
const _LAST_PLAYED_PATH := "user://agent_select.cfg"

static var _cache: Array = []
static var selected_index: int = 0
static var _last_played_loaded: bool = false
static var _last_played_index: int = -1

static func all() -> Array:
	if _cache.is_empty():
		_cache.append(_vif())
		_cache.append(_choc())
		_cache.append(_vanne())
		_cache.append(_guet())
		_cache.append(_roseau())
		_cache.append(_verrou())
	return _cache

static func selected() -> AgentConfig:
	return get_by_index(selected_index)

## Dernier agent avec lequel le joueur a RÉELLEMENT spawn, persistant entre
## deux lancements du jeu (UX-11, docs/research/04_ui_ux.md §2.4 : "à
## l'ouverture, le dernier agent joué est survolé"). -1 si aucune partie n'a
## encore été jouée sur cette machine (AgentSelectScreen garde alors l'index
## par défaut, 0, sans forcer de présélection).
static func last_played_index() -> int:
	_ensure_last_played_loaded()
	return _last_played_index

## Enregistre `index` comme dernier agent joué — appelé par GameWorld au
## moment du spawn RÉEL (jamais pour un simple survol/verrouillage encore non
## confirmé). Écrit immédiatement sur disque : une fermeture brutale du jeu ne
## doit pas perdre la présélection de la prochaine partie. `index` hors des
## bornes connues est ignoré (jamais une présélection inventée).
static func record_played(index: int) -> void:
	if index < 0 or index >= all().size():
		return
	_last_played_index = index
	_last_played_loaded = true
	var cfg := ConfigFile.new()
	cfg.set_value("agent_select", "last_played_index", index)
	cfg.save(_LAST_PLAYED_PATH)

static func _ensure_last_played_loaded() -> void:
	if _last_played_loaded:
		return
	_last_played_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(_LAST_PLAYED_PATH) == OK:
		var idx: int = int(cfg.get_value("agent_select", "last_played_index", -1))
		if idx >= 0 and idx < all().size():
			_last_played_index = idx

## Rôles SANS aucun agent verrouillé parmi `locked_agent_indices` (UX-11 :
## "un bandeau indique les rôles manquants"), dans l'ordre Entrée/Contrôle/
## Soutien. Fonction PURE — testable sans scène : `locked_agent_indices` est
## la liste des index d'agents déjà VERROUILLÉS par l'équipe en cours de
## sélection (jamais les bots, qui ne passent pas par cet écran — voir
## GameWorld._spawn_bot). Un index hors bornes est ignoré (jamais un rôle
## inventé).
static func missing_roles(locked_agent_indices: Array) -> Array:
	var covered := {}
	for i in locked_agent_indices:
		var idx := int(i)
		if idx >= 0 and idx < all().size():
			covered[String(get_by_index(idx).role)] = true
	var missing: Array = []
	for r in ROLES:
		if not covered.has(r):
			missing.append(r)
	return missing

## Agent par index (bornes : replié sur le premier/dernier agent si hors plage).
## Utilisé par AbilityController pour résoudre l'agent RÉPLIQUÉ du joueur
## (PlayerController.agent_index), défini par le serveur au spawn.
static func get_by_index(i: int) -> AgentConfig:
	var a := all()
	return a[clampi(i, 0, a.size() - 1)]

## Icône (128x128, fond détouré en alpha) d'une capacité À TOUCHE de `agent`,
## par `slot` ("C"/"Q"/"E"/"X" -- `Ability.slot`, jamais un libellé de touche
## clavier/manette, voir docs/AGENTS.md §Contrôles). `null` si `agent` est
## `null`, si son nom n'est pas dans le roster connu, ou si le fichier
## correspondant n'existe pas encore -- repli sûr pour l'appelant (UX-21) :
## afficher sans icône plutôt que planter.
static func ability_icon(agent: AgentConfig, slot: String) -> Texture2D:
	return _load_icon(agent, slot.to_lower())

## Icône du PASSIF (toujours actif, sans touche ni slot) de `agent`.
static func passive_icon(agent: AgentConfig) -> Texture2D:
	return _load_icon(agent, "passive")

static func _load_icon(agent: AgentConfig, slot_key: String) -> Texture2D:
	if agent == null:
		return null
	var key: String = _ICON_AGENT_KEY.get(agent.agent_name, "")
	if key.is_empty():
		return null
	var path := "%s%s_%s.png" % [ICON_DIR, key, slot_key]
	if _icon_cache.has(path):
		return _icon_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_icon_cache[path] = tex
	return tex

static func _agent(agent_name: String, role: String, desc: String, color: Color, abilities: Array,
		passive: Passive = null) -> AgentConfig:
	var a := AgentConfig.new()
	a.agent_name = agent_name
	a.role = role
	a.description = desc
	a.color = color
	a.passive = passive
	for i in abilities.size():
		var ab: Ability = abilities[i]
		ab.slot = SLOTS[i] if i < SLOTS.size() else "C"
		a.abilities.append(ab)
	return a

# ------------------------------------------------------------------
#  ENTRÉE — duellistes mobiles, ouvrent l'espace.
# ------------------------------------------------------------------

## Vif, « l'Allumette » -- passif Mèche courte (charge de Ruée + vitesse sur
## élimination/assistance), signature E Faux départ (remplace le Tremplin,
## §3.3 : « pose une braise à ses pieds ; réappuyer E la ramène dessus »).
static func _vif() -> AgentConfig:
	var ruee := DASH.new()  # défauts de DashAbility._init() : Ruée, 17 m/s, 2 charges, 6 s.
	var eblouissement := FLASH.new()  # défauts : mèche 0,3 s, 18 s de recharge (§3.3).
	var faux_depart := FAUX_DEPART.new()  # défauts : fenêtre 5 s, portée 30 m, 16 s, 2 charges (§3.3).
	var resurgence := SURGE.new()
	resurgence.ult_cost = 7  # §3.3 : « coût 8 -> 7 ».
	return _agent("Vif", ROLE_ENTREE,
		"Duelliste mobile : mèche courte, ruée, éblouissement, faux départ, résurgence.",
		Color("ee6a24"), [ruee, eblouissement, faux_depart, resurgence], MECHE_COURTE.new())

## Choc, « la Cloche » -- passif Tête de cloche (-40 % de durée des contrôles
## subis), signature E Tape-la-cloche (fusionne l'ancienne Charge du C :
## charge d'épaule qui étourdit/repousse le premier ennemi touché, ou
## s'étourdit lui-même contre un mur). Mur d'assaut déplacé de E vers C
## (§3.3 : « Mur d'assaut (déplacé de E vers C) »).
static func _choc() -> AgentConfig:
	var mur := WALL.new()
	mur.display_name = "Mur d'assaut"
	mur.description = "Mur de couverture temporaire, plus petit et plus rapide à poser que celui de Vanne."
	mur.size = Vector3(3.2, 2.4, 0.35)
	mur.duration = 5.0
	mur.cooldown = 12.0

	var piege := STUN_TRAP.new()
	piege.display_name = "Piège-choc"

	var tape_la_cloche := BELL_CHARGE.new()  # défauts : 20 m/s, 15 dégâts, étourdit 0,5 s, 14 s (§3.3).

	var deferlante := STUN_BURST.new()

	return _agent("Choc", ROLE_ENTREE,
		"Brise-lignes : tête de cloche, mur d'assaut, piège-choc, tape-la-cloche, déferlante.",
		Color("be2d25"), [mur, piege, tape_la_cloche, deferlante], TETE_DE_CLOCHE.new())

# ------------------------------------------------------------------
#  CONTRÔLE — verrouillent l'espace, coupent les lignes de vue.
# ------------------------------------------------------------------

## Vanne, « la Digue » -- passif Relevé (marque l'ennemi qui tire dans un de
## ses murs), signature E Piquet d'arpenteur (remplace le Piquet-poussée : un
## vrai grappin, ancré sur le décor, jamais sur un joueur).
static func _vanne() -> AgentConfig:
	var mur := WALL.new()  # défauts de WallAbility._init() : Mur, 4x2.6, 8 s, 16 s cd.

	var fumee := SMOKE.new()  # défauts : rayon 3.2, 10 s, 20 s cd.

	var piquet_arpenteur := GRAPPLE.new()  # défauts : portée 18 m, traction 22 m/s, 10 s (§3.3).

	var forteresse := WALL.new()
	forteresse.display_name = "Forteresse"
	forteresse.description = "Mur massif et durable qui ferme complètement un couloir."
	forteresse.size = Vector3(7.0, 3.4, 0.5)
	forteresse.distance = 3.5
	forteresse.height_offset = 1.7
	forteresse.duration = 14.0
	forteresse.color = Color(0.2, 0.42, 0.85)
	forteresse.is_ultimate = true
	forteresse.ult_cost = 9

	return _agent("Vanne", ROLE_CONTROLE,
		"Digue mobile : relevé, mur, fumée, piquet d'arpenteur, forteresse.",
		Color("f2b51d"), [mur, fumee, piquet_arpenteur, forteresse], RELEVE.new())

## Guet, « le Dé » -- passif Planeur (maintenir Saut en l'air plafonne la
## chute et améliore le contrôle aérien), signature E Coup de dé (refonte de
## l'Œil : projectile qui vole 0,5 s avant de révéler, avertit ses victimes).
static func _guet() -> AgentConfig:
	var rideau := SMOKE.new()
	rideau.display_name = "Rideau"
	rideau.description = "Fumée épaisse posée à distance pour couper une ligne de vue longue."
	rideau.throw_range = 22.0

	var poste := JUMP_PAD.new()
	poste.display_name = "Poste avancé"
	poste.description = "Tremplin pour rotation rapide vers les hauteurs."

	var coup_de_de := REVEAL.new()
	coup_de_de.display_name = "Coup de dé"
	coup_de_de.description = "Lance un dé qui vole 0,5 s puis révèle les ennemis proches à travers les murs (2,5 s) et les avertit."
	coup_de_de.throw_range = 22.0
	coup_de_de.reveal_radius = 9.0
	coup_de_de.duration = 2.5
	coup_de_de.cooldown = 20.0  # §3.3 : « recharge 24 -> 20 s ».
	coup_de_de.flight_time = 0.5
	coup_de_de.warn_victims = true

	var vision := REVEAL.new()
	vision.display_name = "Vision totale"
	vision.description = "Révèle TOUS les ennemis de la carte à travers les murs (3 s) et les avertit : « la cote vient de changer »."
	vision.reveal_all = true
	vision.is_ultimate = true
	vision.ult_cost = 7
	vision.warn_victims = true

	return _agent("Guet", ROLE_CONTROLE,
		"Vigie : planeur, rideau, poste avancé, coup de dé, vision totale.",
		Color("5157b8"), [rideau, poste, coup_de_de, vision], PLANEUR.new())

# ------------------------------------------------------------------
#  SOUTIEN — sustentation et information pour l'équipe.
# ------------------------------------------------------------------

## Roseau, « la Passeuse » -- passif Baume au repos (remplace l'ancien C
## Apaisement, désormais redondant : régénération de base plus rapide et plus
## généreuse), signature E Baume du Palud (premier soin D'ALLIÉS du jeu, zone
## qui soigne toute sa cordée). Brume déplacée de E vers C (§3.3).
static func _roseau() -> AgentConfig:
	var brume := SMOKE.new()
	brume.display_name = "Brume"
	brume.description = "Petite fumée défensive pour se mettre à couvert pendant qu'elle se soigne."
	brume.smoke_radius = 2.2
	brume.duration = 7.0
	brume.cooldown = 16.0

	var voile := REVEAL.new()
	voile.display_name = "Voile"
	voile.description = "Révèle les ennemis proches d'un point ciblé pour son équipe (3 s)."
	voile.cooldown = 20.0

	var baume_du_palud := BALM_ZONE.new()  # défauts : portée 12 m, zone 4 m, 12 PV/s, 6 s, 24 s (§3.3).

	var sursaut := RENEWAL.new()

	return _agent("Roseau", ROLE_SOUTIEN,
		"Passeuse du Palud : baume au repos, brume, voile, baume du Palud, sursaut d'équipe.",
		Color("2e9c8a"), [brume, voile, baume_du_palud, sursaut], BAUME_AU_REPOS.new())

## Verrou, « le Crapaud » -- passif Sang-froid (dispersion/recul réduits
## immobile ou accroupi), signature E Glu (refonte de la Chausse-trape : une
## plaque collante persistante qui ralentit, au lieu d'un étourdissement
## ponctuel). Rempart déplacé de E vers C (§3.3).
static func _verrou() -> AgentConfig:
	var rempart := WALL.new()
	rempart.display_name = "Rempart"

	var passerelle := JUMP_PAD.new()
	passerelle.display_name = "Passerelle"
	passerelle.description = "Tremplin partagé pour aider l'équipe à basculer rapidement de position."

	var glu := GLUE.new()  # défauts : rayon 2.5, -50% vitesse, 20 s, 18 s de recharge (§3.3).

	var bastion := BASTION.new()

	return _agent("Verrou", ROLE_SOUTIEN,
		"Ancrage tactique : sang-froid, rempart, passerelle, glu, bastion.",
		Color("2a5fc4"), [rempart, passerelle, glu, bastion], SANG_FROID.new())
