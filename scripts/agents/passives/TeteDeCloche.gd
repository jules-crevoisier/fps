## TeteDeCloche.gd
## Passif de Choc, "Tête de cloche" (docs/research/10_ammo_kits_input.md §3.3,
## fiche Choc) : durée des contrôles SUBIS (étourdissement, éblouissement,
## ralentissement) réduite de 40 % -- modèle Stalwart d'Overwatch (§1, constat
## 13 : "réduit de 40 % les repoussées et les ralentissements subis"). Aucun
## effet sur les PV max ni les dégâts d'arme (§3.2, "Aucun passif ne touche
## aux PV max ni aux dégâts d'arme") : ce passif ne touche QUE la durée d'un
## contrôle reçu par Choc lui-même, jamais un ennemi.
##
## Branché via AgentConfig.passive (hors fichiers possédés par ce contrat --
## voir AgentDatabase.gd) ; appliqué par
## AbilityController._resolve_cc_duration/net_apply_stun/net_apply_flash CHEZ
## LA VICTIME (donc chez Choc quand IL subit un contrôle), avant application
## de la durée reçue -- se combine par MULTIPLICATION avec le multiplicateur
## générique de statut (StatusEffects.cc_mult), jamais un remplacement.
extends Passive

## Multiplicateur appliqué à la durée d'un contrôle SUBI : -40 % (docs §3.3 --
## étourdissement 2,2 -> 1,3 s, éblouissement 1,3 -> 0,8 s, Glu 1,5 -> 0,9 s).
const CC_MULT := 0.6

func _init() -> void:
	display_name = "Tête de cloche"
	description = "Durée des étourdissements, éblouissements et ralentissements subis réduite de 40 %."

func modify_cc_duration(duration: float) -> float:
	return duration * CC_MULT
