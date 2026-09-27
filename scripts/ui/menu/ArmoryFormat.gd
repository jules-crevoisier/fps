## ArmoryFormat.gd
## Formatage d'affichage PUR des stats d'ArmoryScreen.gd (reports/ui/mockups/
## armory.html) depuis les VRAIES ressources WeaponConfig/UtilityConfig — jamais
## un nombre recopié à la main : chaque valeur affichée vient d'un champ
## `@export` déjà chargé par WeaponDatabase/UtilityDatabase. Nombres en FR via
## SettingsFormat.format_number (virgule décimale, source unique). Pure,
## testable sans scène (tests/ui/menu/test_armory_format.gd).
class_name ArmoryFormat
extends RefCounted

## Repères des jauges 0..10 de l'armurerie (armory.html ".meter") — un simple
## RENDU VISUEL de la vraie stat, jamais une donnée à part : changer ces
## constantes ne change aucune valeur de jeu.
const DAMAGE_BAR_MAX := 100.0
const FIRE_RATE_BAR_MAX := 10.0
## La jauge « Dispersion » lit comme une PRÉCISION (plus rempli = plus précis) :
## voir armory.html, où le Revolver (1,2°, arme précise) affiche 7 barres
## pleines sur 10, pas 1 ou 2 — un simple report du degré brut se lirait à
## l'envers pour le joueur (plus de barres = arme MOINS précise).
const SPREAD_BAR_MAX_DEG := 4.0

static func _fmt(v: float, decimals: int = 1) -> String:
	return SettingsFormat.format_number(v, decimals)

## {value, note} — "55" / "35 au-delà de 45 m · tête ×2".
static func format_damage(cfg: WeaponConfig) -> Dictionary:
	var notes: Array[String] = []
	if cfg.damage_min < cfg.damage - 0.01:
		notes.append("%s au-delà de %s m" % [_fmt(cfg.damage_min), _fmt(cfg.falloff_end)])
	if cfg.headshot_mult > 1.0:
		notes.append("tête ×%s" % _fmt(cfg.headshot_mult))
	return {"value": _fmt(cfg.damage), "note": " · ".join(notes)}

## {value, note} — "3 / s" / "7,5 / s en éventail" (revolver, fan the hammer).
static func format_fire_rate(cfg: WeaponConfig) -> Dictionary:
	var note := ""
	if cfg.has_fan_fire():
		note = "%s / s en éventail" % _fmt(cfg.fan_fire_rate)
	return {"value": "%s / s" % _fmt(cfg.fire_rate), "note": note}

## {value, note} — "1,2°" / "+4° en éventail".
static func format_spread(cfg: WeaponConfig) -> Dictionary:
	var note := ""
	if cfg.has_fan_fire() and cfg.fan_spread_add_hip > 0.0:
		note = "+%s° en éventail" % _fmt(cfg.fan_spread_add_hip)
	return {"value": "%s°" % _fmt(cfg.spread_hip), "note": note}

## {value, note} — "6 / 36" / "Rechargement 2,4 s". `ammo_rule` (voir
## Inventory.RULE_ROUND/RULE_ARENA) choisit la réserve affichée — round par
## défaut (comportement historique de manche, voir Inventory.reserve_for).
static func format_magazine(cfg: WeaponConfig, ammo_rule: String = Inventory.RULE_ROUND) -> Dictionary:
	var reserve: int = cfg.arena_reserve_ammo if ammo_rule == Inventory.RULE_ARENA else cfg.reserve_ammo
	return {"value": "%d / %d" % [cfg.mag_size, reserve], "note": "Rechargement %s s" % _fmt(cfg.reload_time)}

static func damage_bars(cfg: WeaponConfig) -> int:
	return clampi(int(round(cfg.damage / DAMAGE_BAR_MAX * 10.0)), 0, 10)

static func fire_rate_bars(cfg: WeaponConfig) -> int:
	return clampi(int(round(cfg.fire_rate / FIRE_RATE_BAR_MAX * 10.0)), 0, 10)

static func precision_bars(cfg: WeaponConfig) -> int:
	return clampi(10 - int(round(cfg.spread_hip / SPREAD_BAR_MAX_DEG * 10.0)), 0, 10)

## Indices clavier/souris affichés sous la scène (armory.html ".modes") — dérivés
## de WeaponConfig.has_fan_fire()/aims_on_right_click(), jamais une paire de
## textes à part par arme.
static func fire_mode_hints(cfg: WeaponConfig) -> Array[Dictionary]:
	if cfg.has_fan_fire():
		return [
			{"key": "Clic G", "label": "Coup précis"},
			{"key": "Clic D", "label": "Maintenir : éventail"},
		]
	return [
		{"key": "Clic G", "label": "Tirer"},
		{"key": "Clic D", "label": "Viser"},
	]

## Lignes de stats pour une grenade (UtilityConfig) — un type donné n'affiche
## que SES champs (voir UtilityConfig.Kind), jamais les champs des deux autres.
static func format_utility(cfg: UtilityConfig) -> Array[Dictionary]:
	match cfg.kind:
		UtilityConfig.Kind.FRAG:
			return [
				{"label": "Dégâts", "value": _fmt(cfg.frag_damage), "note": "Rayon %s m" % _fmt(cfg.frag_damage_radius)},
				{"label": "Amorce", "value": "%s s" % _fmt(cfg.fuse_time),
					"note": "Dès le retrait de la goupille" if cfg.fuse_starts_on_press else "Depuis le lancer"},
			]
		UtilityConfig.Kind.FLASH:
			return [
				{"label": "Éblouissement", "value": "%s s" % _fmt(cfg.flash_facing_seconds),
					"note": "Face · %s s de profil · %s s de dos" % [_fmt(cfg.flash_side_seconds), _fmt(cfg.flash_behind_seconds)]},
				{"label": "Rayon", "value": "%s m" % _fmt(cfg.flash_radius), "note": ""},
			]
		UtilityConfig.Kind.SMOKE:
			return [
				{"label": "Rayon", "value": "%s m" % _fmt(cfg.smoke_radius), "note": "Monte en %s s" % _fmt(cfg.smoke_grow_seconds)},
				{"label": "Tient", "value": "%s s" % _fmt(cfg.smoke_hold_seconds), "note": "Se dissipe en %s s" % _fmt(cfg.smoke_fade_seconds)},
			]
	return []
