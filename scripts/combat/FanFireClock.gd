## FanFireClock.gd
## Horloge de tir à DEUX DÉCLENCHEURS distincts (design verrouillé
## utilisateur, tâche "revolver", révisé 2026-09-27 après playtest — pivot
## "Valorant Classic") :
## - LMB (`tap_trigger`, front `fire_pressed` — jamais un maintien) = tir
##   précis, au plus `tap_rate` tirs/s (WeaponConfig.fire_rate). "Holding LMB
##   does NOT fan anymore; it fires nothing more until release" : LMB ne
##   déclenche donc JAMAIS le mode fan, quelle que soit la durée du maintien.
## - RMB (`fan_trigger`, MAINTENU — `PlayerInput.alt_fire_held`, jamais
##   `aim_held`) = "fan the hammer" à `fan_rate` tirs/s (WeaponConfig.
##   fan_fire_rate), dispersion/recul majorés (voir WeaponConfig.fan_spread_
##   add_*/fan_recoil_mult, appliqués par Weapon.gd — cette classe ne gère que
##   le RYTHME). Premier tir immédiat dès l'appui, tant que RMB reste tenu.
##
## "Partagent... la cadence" (design) : un tir produit par L'UN des deux
## déclencheurs remet à VIDE (`FireClock.start_empty`, jamais `.reset()`) le
## cooldown de l'AUTRE — un joueur ne peut donc jamais alterner LMB/RMB pour
## dépasser la cadence prévue de l'un ou l'autre déclencheur (chaque tir,
## quelle que soit son origine, retarde le PROCHAIN tir de l'autre type d'au
## moins son propre intervalle).
##
## Réutilise DEUX `FireClock` internes (même discipline "reste fractionnaire à
## 60 Hz" que le reste du projet). `fan_rate <= 0.0` désactive le mode fan
## (arme sans `WeaponConfig.has_fan_fire()`, ex. le Ravage — qui n'utilise de
## toute façon jamais cette classe, voir Weapon.gd) : `fan_trigger` est alors
## purement ignoré, jamais de tir fan produit.
##
## Testé isolément dans tests/combat/test_fan_fire_clock.gd.
class_name FanFireClock
extends RefCounted

var _tap: FireClock
var _fan: FireClock
var _has_fan: bool

func _init(tap_rate: float, fan_rate: float) -> void:
	_tap = FireClock.new(tap_rate)
	_has_fan = fan_rate > 0.0
	_fan = FireClock.new(fan_rate if _has_fan else tap_rate)

## Repasse les deux horloges à "prêtes" (ex. changement d'arme, comme
## FireClock.reset()).
func reset() -> void:
	_tap.reset()
	_fan.reset()

## Avance l'horloge de `delta` secondes. `tap_trigger` = LMB (déjà ANDé avec
## `Inventory.can_fire()` par l'appelant, front `fire_pressed`/`fire_held`
## selon `WeaponConfig.automatic` — même convention que Weapon._owner_tick).
## `fan_trigger` = RMB tenu (`PlayerInput.alt_fire_held`, également ANDé avec
## `can_fire()`), ignoré si `fan_rate <= 0.0`. Renvoie {"tap": int, "fan": int} —
## nombre de tirs produits CE tick pour chaque déclencheur (jamais plus d'1-2
## à ces cadences/60 Hz, mais généralisé comme FireClock).
func tick(delta: float, tap_trigger: bool, fan_trigger: bool) -> Dictionary:
	var tap_shots := _tap.tick(delta, tap_trigger)
	var fan_shots := 0
	if _has_fan:
		fan_shots = _fan.tick(delta, fan_trigger)
	else:
		_fan.tick(delta, false)  # horloge inerte, jamais utilisée pour cette arme.
	# Cadence PARTAGÉE (voir docstring de classe) : un tir de L'UN des deux
	# déclencheurs retarde le PROCHAIN tir de l'AUTRE d'au moins son propre
	# intervalle — jamais de double-tir immédiat en alternant LMB/RMB.
	if tap_shots > 0:
		_fan.start_empty()
	if fan_shots > 0:
		_tap.start_empty()
	return {"tap": tap_shots, "fan": fan_shots}
