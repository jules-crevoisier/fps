## SangFroid.gd
## Passif de Verrou (AGT-08, docs/research/10_ammo_kits_input.md §3.3) :
## « immobile ou accroupi, il vise plus juste » — dispersion -30 % et recul
## vertical -20 % après 0.4 s au sol sous 0.5 m/s, ou IMMÉDIATEMENT accroupi.
## Le calcul PUR (condition + multiplicateurs) vit dans WeaponFeel.is_steady/
## steady_spread_mult/steady_recoil_mult (testé isolément, sans joueur réel —
## voir tests/agents/test_verrou_kit.gd, "test pur" de l'acceptance AGT-08).
## Cette classe ne fait que suivre, PAR JOUEUR (clé = instance_id), depuis
## quand chacun est repassé sous le seuil de vitesse : nécessaire car cette
## ressource `Passive` est PARTAGÉE entre tous les joueurs d'un même agent
## (un seul AgentConfig par agent, voir AgentDatabase/AbilityController.
## _resolve_agent), donc aucun état par-joueur ne peut vivre directement sur
## `self` sans être keyé par joueur.
##
## `recoil_mult` n'est PAS un hook de Passive.gd (fichier hors périmètre de ce
## contrat) : duck-typé, à appeler via `if passive.has_method("recoil_mult")`
## — même convention que les `has_method("cast_barrier")` déjà utilisés dans
## AbilityController.gd. `spread_mult`, lui, surcharge bien le hook existant
## de Passive.gd (câblage réel dans Weapon.gd laissé à un contrat futur : ce
## dernier est hors périmètre de ce contrat, voir blocked_on du rendu AGT-08).
class_name SangFroid
extends Passive

const STILL_SPEED_LIMIT := 0.5
const STILL_TIME_THRESHOLD := 0.4
const SPREAD_MULT := 0.7
const RECOIL_MULT := 0.8

## instance_id du joueur -> horodatage (s, Time.get_ticks_msec() / 1000.0)
## depuis lequel il est repassé sous STILL_SPEED_LIMIT. Absent = vient de
## bouger (ou jamais encore observé).
var _still_since: Dictionary = {}

func _init() -> void:
	display_name = "Sang-froid"
	description = "Immobile ou accroupi : dispersion -30 %, recul vertical -20 %."

## Temps (s) écoulé depuis que `player` est repassé sous le seuil de vitesse
## — 0.0 s'il vient d'y repasser ou le dépasse. Met à jour `_still_since` à
## CHAQUE appel. `now` est injectable pour un test déterministe (défaut :
## horloge réelle) — jamais utilisé par un appelant de jeu, uniquement par
## tests/agents/test_verrou_kit.gd pour simuler un délai sans attente réelle.
func _time_still(player: PlayerController, now: float = -1.0) -> float:
	if player == null:
		return 0.0
	var t := (Time.get_ticks_msec() / 1000.0) if now < 0.0 else now
	var id := player.get_instance_id()
	if player.horizontal_speed() >= STILL_SPEED_LIMIT:
		_still_since.erase(id)
		return 0.0
	if not _still_since.has(id):
		_still_since[id] = t
	return t - float(_still_since[id])

func spread_mult(player: PlayerController) -> float:
	if player == null:
		return 1.0
	return WeaponFeel.steady_spread_mult(_time_still(player), player.horizontal_speed(), player.is_crouching,
		STILL_TIME_THRESHOLD, STILL_SPEED_LIMIT, SPREAD_MULT)

## Duck-typé (voir docstring du fichier) : futur appelant côté Weapon.gd.
func recoil_mult(player: PlayerController) -> float:
	if player == null:
		return 1.0
	return WeaponFeel.steady_recoil_mult(_time_still(player), player.horizontal_speed(), player.is_crouching,
		STILL_TIME_THRESHOLD, STILL_SPEED_LIMIT, RECOIL_MULT)
