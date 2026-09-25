## Releve.gd
## Passif de Vanne, "Relevé" (AGT-05, docs/research/10_ammo_kits_input.md §3.3,
## fiche Vanne) : « sa coffreuse mesure les impacts ; tout ennemi qui tire dans
## un de ses murs est marqué pour son équipe » -- marqueur "!" pendant 1,5 s,
## au plus une marque PAR ENNEMI toutes les 4 s.
##
## `on_wall_shot` n'est PAS un hook de Passive.gd (fichier hors périmètre de ce
## contrat) : duck-typé, à appeler via `if passive.has_method("on_wall_shot")`
## -- même convention que `SangFroid.recoil_mult` (AGT-08) et les
## `has_method("cast_barrier")` déjà utilisés dans AbilityController.gd. Le
## câblage réel (les murs de `cast_barrier` doivent porter une métadonnée de
## propriétaire ; `Weapon._resolve_pending_shots` doit signaler un impact sur
## un mur à SON propriétaire) vit dans AbilityController.gd/Weapon.gd, tous
## deux hors des fichiers possédés par ce contrat -- voir le rendu de tâche
## AGT-05 (`blocked_on`). Une fois câblé, l'appelant fournira `player`
## (propriétaire du mur touché), `attacker` (l'ennemi qui vient de tirer
## dedans) et `now`.
##
## Rate-limite PAR COUPLE (propriétaire, ennemi) via `_last_mark_at`, keyée
## par `get_instance_id()` -- nécessaire car cette ressource `Passive` est
## PARTAGÉE entre tous les joueurs d'un même agent (un seul AgentConfig par
## agent, voir AgentDatabase/AbilityController._resolve_agent) : sans cette
## clé composite, deux Vanne différentes (une par équipe) partageraient le
## même compteur de marque, et une ennemie de l'une serait à tort considérée
## "déjà marquée" pour l'autre. Même précaution que `SangFroid._still_since`
## (AGT-08).
extends Passive

## Durée du marqueur "!" côté victime marquée (s).
@export var mark_duration: float = 1.5
## Cooldown minimal entre deux marques pour LE MÊME ennemi (s).
@export var mark_cooldown: float = 4.0

## "instance_id propriétaire:instance_id ennemi" -> horodatage (s) de la
## dernière marque accordée pour ce couple.
var _last_mark_at: Dictionary = {}

func _init() -> void:
	display_name = "Relevé"
	description = "Tout ennemi qui tire dans un de ses murs est marqué pour son équipe (1,5 s, 4 s par ennemi)."

## Logique PURE de limitation : au plus une marque par couple (clé composite
## propriétaire/ennemi) toutes les `cooldown` s. Mute `last_marks` EN PLACE,
## et UNIQUEMENT quand la marque est accordée (jamais sur un refus) --
## testable isolément, sans scène ni joueur (même esprit qu'AssistTracker,
## tests/agents/test_vanne_kit.gd).
static func should_mark(last_marks: Dictionary, key: String, now: float, cooldown: float) -> bool:
	var last: float = last_marks.get(key, -INF)
	if now - last < cooldown:
		return false
	last_marks[key] = now
	return true

## Appelé (une fois câblé, voir docstring du fichier) quand `attacker` vient
## de tirer dans un mur posé par `player`. Ne marque jamais un coéquipier (tir
## ami sur son propre mur, ou sur celui d'un allié). `now` est injectable
## (Time.get_ticks_msec() / 1000.0 chez l'appelant réel) pour rester testable
## sans horloge réelle, comme AssistTracker.record_damage/assists_for_kill.
## Retourne true si la marque a bien été accordée (utile aux tests et à un
## futur appelant qui voudrait, ex., jouer un son uniquement sur une marque
## réellement posée).
func on_wall_shot(player: PlayerController, attacker: PlayerController, now: float) -> bool:
	if player == null or attacker == null:
		return false
	if int(attacker.get("team")) == int(player.get("team")):
		return false
	var key := "%d:%d" % [player.get_instance_id(), attacker.get_instance_id()]
	if not should_mark(_last_mark_at, key, now, mark_cooldown):
		return false
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl == null or not ctrl.has_method("cast_reveal"):
		return false
	var players_root := player.get_parent()
	if players_root == null:
		return false
	ctrl.cast_reveal(players_root, int(player.get("team")), [attacker.global_position], mark_duration)
	return true
