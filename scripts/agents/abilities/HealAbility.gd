## HealAbility — soin appliqué UNIQUEMENT côté serveur (Health est autoritaire
## serveur ; pas de prédiction visuelle nécessaire). Le soin "de base"
## (`require_out_of_combat = true`) n'agit que si le joueur n'a pris aucun
## dégât depuis `out_of_combat_window` secondes (contract-r2.md, R-B3
## acceptance #2) — vérifié via `can_activate_server` (rejette AVANT de
## consommer la charge, comme un tir refusé). Les variantes d'ultime
## (Résurgence, Sursaut) utilisent `full_heal = true` et
## `require_out_of_combat = false` : voir SurgeAbility/RenewalAbility.
extends Ability

## Montant de soin (PV) si `full_heal` est faux.
@export var amount: float = 60.0
## true = soigne jusqu'au maximum (ignore `amount`).
@export var full_heal: bool = false
## true = exige `out_of_combat_window` secondes sans dégât (soin de base).
@export var require_out_of_combat: bool = true
@export var out_of_combat_window: float = 3.0

func _init() -> void:
	slot = "Q"
	display_name = "Apaisement"
	description = "Se soigne, mais uniquement si elle n'a pris aucun dégât depuis 3 s."
	cooldown = 14.0
	charges = 1

func can_activate_server(player: PlayerController) -> bool:
	var hp := player.get_node_or_null("Health") as Health
	if hp == null or hp.is_dead:
		return false
	if hp.current_health >= hp.max_health:
		return false  # déjà au maximum, rien à soigner.
	if not require_out_of_combat:
		return true
	var ctrl := player.get_node_or_null("Abilities")
	if ctrl and ctrl.has_method("is_out_of_combat"):
		return ctrl.is_out_of_combat(out_of_combat_window)
	return true  # Health.damaged pas encore câblé (guard has_signal côté controller) -> on autorise.

func activate_server(player: PlayerController, _aim_dir: Vector3) -> void:
	var hp := player.get_node_or_null("Health") as Health
	if hp == null:
		return
	if full_heal:
		hp.heal(hp.max_health)
	else:
		hp.heal(amount)
