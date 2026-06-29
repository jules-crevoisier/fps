## AgentDatabase.gd
## Catalogue des agents (construits en code) + agent sélectionné par le joueur.
class_name AgentDatabase
extends RefCounted

const DASH := preload("res://scripts/agents/abilities/DashAbility.gd")
const HEAL := preload("res://scripts/agents/abilities/HealAbility.gd")
const WALL := preload("res://scripts/agents/abilities/WallAbility.gd")
const SURGE := preload("res://scripts/agents/abilities/SurgeAbility.gd")

const SLOTS := ["C", "Q", "E", "X"]

static var _cache: Array = []
static var selected_index: int = 0

static func all() -> Array:
	if _cache.is_empty():
		_cache.append(_make("Vif", "Duelliste mobile : ruée, soin, mur.", Color(0.92, 0.45, 0.32), [DASH, HEAL, WALL, SURGE]))
		_cache.append(_make("Roc", "Défenseur : mur en premier, plus tanky.", Color(0.38, 0.6, 0.92), [WALL, HEAL, DASH, SURGE]))
	return _cache

static func selected() -> AgentConfig:
	var a := all()
	return a[clampi(selected_index, 0, a.size() - 1)]

static func _make(agent_name: String, desc: String, color: Color, scripts: Array) -> AgentConfig:
	var a := AgentConfig.new()
	a.agent_name = agent_name
	a.description = desc
	a.color = color
	for i in scripts.size():
		var ab: Ability = scripts[i].new()
		# Slot selon la position (C/Q/E/X) — permet de varier l'agencement par agent.
		ab.slot = SLOTS[i] if i < SLOTS.size() else "C"
		a.abilities.append(ab)
	return a
