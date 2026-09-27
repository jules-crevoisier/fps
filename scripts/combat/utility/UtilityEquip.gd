## UtilityEquip.gd
## Machine à états PURE de "l'objet en main façon CS" (contrat lead
## 2026-09-27, inventaire CS-style, points 4/6/7/8) : quelle grenade (si
## aucune) est actuellement ÉQUIPÉE, le délai de déploiement avant de pouvoir
## commencer un lancer, et le minuteur de retour automatique à l'arme après le
## geste de lancer. Aucune dépendance à l'arbre de scène : même patron que
## Inventory.gd/UtilityInventory.gd -- c'est la copie PRÉDITE côté
## propriétaire ET la copie AUTORITAIRE côté serveur de
## scripts/combat/utility/UtilityThrower.gd (une instance de chaque, comme
## `_inv`/`_server_inv`).
class_name UtilityEquip
extends RefCounted

const NONE := -1

## Délai (s) après équipement avant qu'un lancer puisse COMMENCER (contrat
## point 4 : "a 0.25 s deploy delay applies before a throw can start") --
## même valeur que Weapon.SWITCH_DELAY (même sensation de "sortie d'objet"),
## simple coïncidence de valeur plutôt qu'une dépendance entre les deux fichiers.
const DEPLOY_DELAY_S := 0.25

## Durée (s) du geste de lancer FP_Throw (voir FPArmsRig._THROW_CLIPS,
## ≈0,4 s authored -- docstring UtilityThrower.gd) : contrat point 6, "after
## the throw animation (FP_Throw) ends, auto-switch back to the last equipped
## WEAPON slot". Un délai FIXE plutôt que la longueur réelle du clip (lue
## uniquement côté FPArmsRig, un Node3D hors de portée d'une classe PURE) :
## les deux copies (propriétaire ET serveur, qui n'a d'ailleurs aucun rig à
## interroger) doivent compter EXACTEMENT le même temps pour rester en accord.
const RETURN_DELAY_S := 0.4

var kind: int = NONE
var deploy_left: float = 0.0
## >= 0.0 : un retour à l'arme est en cours de décompte (lancer effectué,
## geste FP_Throw en cours). < 0.0 (repli par défaut) : aucun retour en cours.
var return_left: float = -1.0

func is_equipped() -> bool:
	return kind != NONE

## Contrat point 4 : "the gun cannot fire, reload, ADS or inspect" tant qu'une
## grenade est équipée -- nommée séparément de `is_equipped()` pour que
## chaque appelant (Weapon.gd, ViewModel.gd) documente POURQUOI il consulte
## cet état, même s'il s'agit exactement de la même valeur aujourd'hui.
func blocks_weapon_actions() -> bool:
	return is_equipped()

## Contrat point 4 : le délai de déploiement (0,25 s) doit être écoulé avant
## qu'un lancer puisse COMMENCER (amorce/aperçu d'arc) -- `false` si rien
## n'est équipé (aucun lancer possible de toute façon).
func can_start_throw() -> bool:
	return is_equipped() and deploy_left <= 0.0

## Équipe `new_kind` (UtilityDatabase.FRAG/FLASH/SMOKE) : redémarre le délai
## de déploiement, annule tout retour en cours (contrat : re-sélectionner une
## grenade alors qu'un retour était en cours n'a plus de sens, le joueur
## reprend une grenade EN MAIN).
func equip(new_kind: int) -> void:
	kind = new_kind
	deploy_left = DEPLOY_DELAY_S
	return_left = -1.0

## Revient à l'arme IMMÉDIATEMENT (pression directe 1/2, molette vers un
## emplacement d'arme) -- contrairement à `start_return_after_throw`, aucun
## délai : CS ne fait pas attendre un demi-geste d'animation quand le joueur
## a explicitement redemandé son arme.
func unequip() -> void:
	kind = NONE
	deploy_left = 0.0
	return_left = -1.0

## Un lancer vient d'avoir lieu (jet réel OU explosion en main, contrat point
## 6) : démarre le décompte du retour automatique. Ne change PAS `kind` tout
## de suite -- la main continue de montrer la pose de lancer jusqu'à la fin
## du geste (voir `tick`), exactement comme le clip FP_Throw joue en entier
## avant que les bras ne redeviennent ceux de l'arme.
func start_return_after_throw() -> void:
	return_left = RETURN_DELAY_S

## Mort/respawn (contrat point 7 : "the equipped item resets to the primary
## weapon") -- alias explicite de `unequip`, nommé séparément pour que
## l'appelant documente le déclencheur plutôt que de rappeler `unequip()` à
## l'aveugle.
func reset_on_death_or_respawn() -> void:
	unequip()

## Avance les minuteurs de `delta` secondes. Renvoie VRAI uniquement au tick
## où le retour automatique se termine (même convention que Inventory.tick
## pour la fin de rechargement) -- l'appelant (UtilityThrower._owner_tick/
## _server_tick) s'en sert pour déclencher le tirage "FP_Draw"/la levée du
## blocage de tir, une seule fois.
func tick(delta: float) -> bool:
	if deploy_left > 0.0:
		deploy_left = maxf(deploy_left - delta, 0.0)
	if return_left < 0.0:
		return false
	return_left -= delta
	if return_left > 0.0:
		return false
	return_left = -1.0
	unequip()
	return true

func to_dict() -> Dictionary:
	return {"kind": kind, "deploy_left": deploy_left, "return_left": return_left}

static func from_dict(d: Dictionary) -> UtilityEquip:
	var e := UtilityEquip.new()
	e.kind = int(d.get("kind", NONE))
	e.deploy_left = float(d.get("deploy_left", 0.0))
	e.return_left = float(d.get("return_left", -1.0))
	return e
