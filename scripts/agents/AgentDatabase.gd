## AgentDatabase.gd
## Catalogue des agents (construits en code) + agent sélectionné par le joueur.
## 6 agents, 3 rôles (Entrée, Contrôle, Soutien) x 2, chacun avec 4 capacités
## (C/Q/E + ultime X) construites à partir des primitives d'effet partagées
## dans scripts/agents/abilities/ (mouvement, soin, mur, fumée, tremplin,
## piège étourdissant, éblouissement, reveal — voir docs/AGENTS.md pour le
## détail et le contre-jeu de chacune).
class_name AgentDatabase
extends RefCounted

const DASH := preload("res://scripts/agents/abilities/DashAbility.gd")
const HEAL := preload("res://scripts/agents/abilities/HealAbility.gd")
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

const SLOTS := ["C", "Q", "E", "X"]

const ROLE_ENTREE := "Entrée"
const ROLE_CONTROLE := "Contrôle"
const ROLE_SOUTIEN := "Soutien"

static var _cache: Array = []
static var selected_index: int = 0

static func all() -> Array:
	if _cache.is_empty():
		_cache.append(_vif())
		_cache.append(_choc())
		_cache.append(_roc())
		_cache.append(_guet())
		_cache.append(_baume())
		_cache.append(_verrou())
	return _cache

static func selected() -> AgentConfig:
	return get_by_index(selected_index)

## Agent par index (bornes : replié sur le premier/dernier agent si hors plage).
## Utilisé par AbilityController pour résoudre l'agent RÉPLIQUÉ du joueur
## (PlayerController.agent_index), défini par le serveur au spawn.
static func get_by_index(i: int) -> AgentConfig:
	var a := all()
	return a[clampi(i, 0, a.size() - 1)]

static func _agent(agent_name: String, role: String, desc: String, color: Color, abilities: Array) -> AgentConfig:
	var a := AgentConfig.new()
	a.agent_name = agent_name
	a.role = role
	a.description = desc
	a.color = color
	for i in abilities.size():
		var ab: Ability = abilities[i]
		ab.slot = SLOTS[i] if i < SLOTS.size() else "C"
		a.abilities.append(ab)
	return a

# ------------------------------------------------------------------
#  ENTRÉE — duellistes mobiles, ouvrent l'espace.
# ------------------------------------------------------------------

static func _vif() -> AgentConfig:
	var ruee := DASH.new()  # défauts de DashAbility._init() : Ruée, 17 m/s, 2 charges.
	var eblouissement := FLASH.new()
	var tremplin := JUMP_PAD.new()
	var resurgence := SURGE.new()
	return _agent("Vif", ROLE_ENTREE,
		"Duelliste mobile : ruée, éblouissement, tremplin, soin d'urgence.",
		Color(0.92, 0.45, 0.32), [ruee, eblouissement, tremplin, resurgence])

static func _choc() -> AgentConfig:
	var charge := DASH.new()
	charge.display_name = "Charge"
	charge.description = "Charge puissante en ligne droite, franchit les petits obstacles."
	charge.force = 20.0
	charge.hop = 1.5
	charge.use_facing = true
	charge.cooldown = 7.0
	charge.charges = 1

	var piege := STUN_TRAP.new()
	piege.display_name = "Piège-choc"

	var mur := WALL.new()
	mur.display_name = "Mur d'assaut"
	mur.description = "Mur de couverture temporaire, plus petit et plus rapide à poser que celui de Roc."
	mur.size = Vector3(3.2, 2.4, 0.35)
	mur.duration = 5.0
	mur.cooldown = 12.0

	var deferlante := STUN_BURST.new()

	return _agent("Choc", ROLE_ENTREE,
		"Brise-lignes : charge, piège étourdissant, mur d'assaut, déferlante.",
		Color(0.85, 0.28, 0.24), [charge, piege, mur, deferlante])

# ------------------------------------------------------------------
#  CONTRÔLE — verrouillent l'espace, coupent les lignes de vue.
# ------------------------------------------------------------------

static func _roc() -> AgentConfig:
	var mur := WALL.new()  # défauts de WallAbility._init() : Mur, 8 s, 16 s cd.

	var fumee := SMOKE.new()

	var piquet := DASH.new()
	piquet.display_name = "Piquet"
	piquet.description = "Petite poussée pour se replacer sans quitter sa position de contrôle."
	piquet.force = 9.0
	piquet.hop = 0.5
	piquet.use_facing = true
	piquet.cooldown = 8.0
	piquet.charges = 2

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

	return _agent("Roc", ROLE_CONTROLE,
		"Bastion défensif : mur, fumée, repositionnement, forteresse.",
		Color(0.38, 0.6, 0.92), [mur, fumee, piquet, forteresse])

static func _guet() -> AgentConfig:
	var rideau := SMOKE.new()
	rideau.display_name = "Rideau"
	rideau.description = "Fumée épaisse posée à distance pour couper une ligne de vue longue."
	rideau.throw_range = 22.0

	var poste := JUMP_PAD.new()
	poste.display_name = "Poste avancé"
	poste.description = "Tremplin pour rotation rapide vers les hauteurs."

	var oeil := REVEAL.new()  # défauts de RevealAbility._init() : Œil, rayon 10 m, 3 s.

	var vision := REVEAL.new()
	vision.display_name = "Vision totale"
	vision.description = "Révèle TOUS les ennemis de la carte à travers les murs (3 s)."
	vision.reveal_all = true
	vision.is_ultimate = true
	vision.ult_cost = 7

	return _agent("Guet", ROLE_CONTROLE,
		"Vigie : fumée longue portée, tremplin, marqueur, vision totale.",
		Color(0.55, 0.75, 0.42), [rideau, poste, oeil, vision])

# ------------------------------------------------------------------
#  SOUTIEN — sustentation et information pour l'équipe.
# ------------------------------------------------------------------

static func _baume() -> AgentConfig:
	var apaisement := HEAL.new()  # défauts de HealAbility._init() : Apaisement, 60 PV, hors-combat.

	var voile := REVEAL.new()
	voile.display_name = "Voile"
	voile.description = "Révèle les ennemis proches d'un point ciblé pour son équipe (3 s)."
	voile.cooldown = 20.0

	var brume := SMOKE.new()
	brume.display_name = "Brume"
	brume.description = "Petite fumée défensive pour se mettre à couvert pendant qu'elle se soigne."
	brume.smoke_radius = 2.2
	brume.duration = 7.0
	brume.cooldown = 16.0

	var sursaut := RENEWAL.new()

	return _agent("Baume", ROLE_SOUTIEN,
		"Soigneuse : soin conditionnel, révélation, fumée défensive, soin total.",
		Color(0.95, 0.8, 0.35), [apaisement, voile, brume, sursaut])

static func _verrou() -> AgentConfig:
	var chausse_trape := STUN_TRAP.new()  # défauts de StunTrapAbility._init() : Chausse-trape.

	var passerelle := JUMP_PAD.new()
	passerelle.display_name = "Passerelle"
	passerelle.description = "Tremplin partagé pour aider l'équipe à basculer rapidement de position."

	var rempart := WALL.new()
	rempart.display_name = "Rempart"

	var bastion := BASTION.new()

	return _agent("Verrou", ROLE_SOUTIEN,
		"Ancrage tactique : piège, tremplin d'équipe, mur, bastion.",
		Color(0.5, 0.42, 0.68), [chausse_trape, passerelle, rempart, bastion])
