## WeaponFoley.gd
## Table PURE temps -> son du foley d'arme façonné à la main (tâche "son",
## 2026-09-27, point 4 "foley revolver") — chaque instant est une FRACTION
## [0,1] déjà normalisée de la durée totale du geste, directement recopiée des
## dictionnaires authored de art/characters/frog_cowboy/anim/pistol.py
## (RELOAD_T pour le rechargement, INSPECT_T pour l'inspection — ces valeurs
## sont déjà des fractions de RELOAD_S=2.4 s / INSPECT_S=2.5 s dans ce
## fichier Python, donc réutilisables telles quelles) et de la liste de clés
## de art/characters/frog_cowboy/anim/rifle.py `build_reload` (Ravage, arme à
## deux mains). Multiplier par la durée RÉELLE (`WeaponConfig.reload_time`,
## jamais la constante authored) garde les événements corrects si une arme
## change de vitesse de rechargement. Aucune dépendance à l'arbre de scène —
## l'appelant (Audio.gd) résout le "maintenant" et vérifie que le geste n'a
## pas été annulé (changement d'arme, mort) avant de jouer chaque son.
class_name WeaponFoley
extends RefCounted

# ---------------------------------------------------------- revolver — rechargement
# Fractions RELOAD_T (pistol.py) : bras du barillet qui jaillit (open0), tige
# d'éjection qui sort les douilles (eject), chargeur rapide qui s'insère
# (insert), bras qui se referme d'un coup sec (close1), petit rebond de
# rotation du barillet une fois refermé (spin1, dernière clé du dict).
const _REV_RELOAD_T := {
	"rev_crane_open": 0.09,
	"rev_eject": 0.26,
	"rev_load": 0.57,
	"rev_crane_close": 0.765,
	"rev_spin": 0.95,
}
const _REV_RELOAD_ORDER := ["rev_crane_open", "rev_eject", "rev_load", "rev_crane_close", "rev_spin"]

## Rechargement du revolver : 5 événements, dans l'ordre chronologique
## authored, mis à l'échelle de `reload_time` (s, réel — `WeaponConfig.reload_time`).
static func revolver_reload_events(reload_time: float) -> Array:
	return _events_from_table(_REV_RELOAD_ORDER, _REV_RELOAD_T, reload_time)

# ---------------------------------------------------------- revolver — inspection
# Fractions INSPECT_T (pistol.py) : bras qui jaillit (open0), la paume gauche
# lance le barillet (spin0), coup sec de fermeture (close1).
const _REV_INSPECT_T := {
	"rev_crane_open": 0.47,
	"rev_spin": 0.56,
	"rev_crane_close": 0.90,
}
const _REV_INSPECT_ORDER := ["rev_crane_open", "rev_spin", "rev_crane_close"]

## Inspection du revolver (touche E) : 3 événements, mis à l'échelle
## d'`inspect_time` (s — durée réelle du geste, voir FPArmsRig/pistol.py INSPECT_S).
static func revolver_inspect_events(inspect_time: float) -> Array:
	return _events_from_table(_REV_INSPECT_ORDER, _REV_INSPECT_T, inspect_time)

# ---------------------------------------------------------- Ravage (fusil deux mains) — rechargement
# rifle.py `build_reload` (clip "Rifle_Reload", authored sur 2,5 s) : le
# chargeur commence à quitter l'arme vers t=0.20 (première clé qui cible le
# point MAG du fusil, main gauche libre) ; il est rentré et la main relâche
# vers t=0.90 (dernière clé "main libre" avant le retour neutre à t=1.00).
# Ni 0.0 ni 1.0 : le tout début/la toute fin du clip ne sont qu'inclinaison
# de l'arme, sans contact avec le chargeur (voir la docstring de fichier).
const _RIFLE_RELOAD_OUT_FRAC := 0.20
const _RIFLE_RELOAD_IN_FRAC := 0.90

## Rechargement du Ravage (et de toute arme générique à deux mains, même
## fractions par défaut faute d'un clip dédié) : reload_out (chargeur qui
## sort) puis reload_in (chargeur qui rentre), mis à l'échelle de `reload_time`.
static func rifle_reload_events(reload_time: float) -> Array:
	return [
		{"time": _RIFLE_RELOAD_OUT_FRAC * reload_time, "sound": "reload_out"},
		{"time": _RIFLE_RELOAD_IN_FRAC * reload_time, "sound": "reload_in"},
	]

static func _events_from_table(order: Array, table: Dictionary, duration: float) -> Array:
	var out: Array = []
	for sound in order:
		out.append({"time": float(table[sound]) * duration, "sound": sound})
	return out
