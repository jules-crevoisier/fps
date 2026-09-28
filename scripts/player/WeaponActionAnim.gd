## WeaponActionAnim.gd
## Maths PURES de l'animation procédurale du CYCLE D'ACTION (pompe/levier/
## verrou) et du geste d'INSERTION (chargeur/cartouche/balle) — tâche "quatre
## armes" (2026-09-28, Rafale/Fracas/Verdict/Aiguille). Aucun accès à l'arbre
## de scène : consommée par ViewModel.gd, qui applique le décalage calculé ici
## en position/rotation LOCALE sur le nœud enfant nommé du modèle courant
## (PumpGrip/Lever/Bolt/Magazine, voir tools/blender/make_action_weapons.py) —
## même esprit "weapon-feel procédural" que AnimState/FPArmsMath (recul, sway,
## bob, dip de rechargement) : aucune de ces pièces n'a de clip
## AnimationPlayer dédié, juste un aller-retour calculé chaque frame. Testée
## isolément dans tests/player/test_weapon_action_anim.gd.
class_name WeaponActionAnim
extends RefCounted

## Durée (s) du geste BREF d'insertion d'une cartouche/d'une balle pendant un
## rechargement PAR CARTOUCHE (`WeaponConfig.reload_per_round`) — INDÉPENDANTE
## de `reload_round_time` (le geste reste bref même si les cartouches
## s'enchaînent vite, ex. Verdict à 0.4 s/balle).
const INSERT_FLOURISH_S := 0.18

## Progression [0,1] d'un geste (cycle d'action OU insertion) sur `t` secondes
## écoulées depuis son déclenchement, de durée totale `duration` — 0 PILE au
## déclenchement (`t == 0.0`), 1 une fois terminé (`t >= duration`). Repli
## défensif à 1.0 (repos) pour `t < 0.0` (jamais produit par ViewModel en
## pratique — `_cycle_since_fire`/`_insert_since` valent soit `INF` soit un
## delta positif cumulé depuis 0.0 — mais un t négatif garde un sens : "pas de
## geste en cours") ou `duration <= 0.0` (arme sans cycle dédié, ex. le
## Ravage), jamais de division par zéro/geste qui ne finit jamais.
static func progress(t: float, duration: float) -> float:
	if duration <= 0.0 or t < 0.0:
		return 1.0
	if t >= duration:
		return 1.0
	return t / duration

## Décalage LOCAL (mètres/radians selon l'appelant) d'une pièce qui part de
## son repos, atteint son amplitude MAXIMALE à mi-geste (`progress == 0.5`),
## puis y revient (`progress == 1.0`) — `sin(p * PI)` : 0 aux deux bouts, pic
## au milieu. Utilisée aussi bien pour une translation (pompe/culasse, mètres)
## qu'une rotation (levier, radians) : seule l'AMPLITUDE (`amount`) change de
## sens selon l'appelant, la forme reste identique.
static func swing(progress_t: float, amount: float) -> float:
	return sin(clampf(progress_t, 0.0, 1.0) * PI) * amount

## Décalage LOCAL du geste d'insertion — même forme que `swing`, mais sur sa
## PROPRE fenêtre temporelle fixe (`INSERT_FLOURISH_S`), indépendante de la
## durée du cycle d'action. `t_since_insert < 0.0` (aucune insertion en cours,
## sentinel — voir ViewModel._insert_since) -> 0.0 (repos).
static func insert_offset(t_since_insert: float, amount: float) -> float:
	if t_since_insert < 0.0:
		return 0.0
	return swing(progress(t_since_insert, INSERT_FLOURISH_S), amount)
