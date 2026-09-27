## UtilityThrowInput.gd
## Résolution PURE appui-simple/maintien d'une touche de lancer — même patron
## que PingController.is_hold (tests/player/test_ping.gd) : sous le seuil, un
## relâchement lance immédiatement ; au-delà, l'aperçu de trajectoire (arc +
## marqueur d'impact) est déjà affiché, et le relâchement lance de la même
## façon (contrat lead : "short tap -> throw immediately; hold -> show the
## trajectory arc ... and throw on release" — le lancer a TOUJOURS lieu au
## relâchement, seul l'affichage de l'arc distingue les deux cas). Consommée
## par UtilityThrower.gd (lecture réelle des touches, hors périmètre pur).
class_name UtilityThrowInput
extends RefCounted

## Durée (s) de maintien au-delà de laquelle l'arc de trajectoire s'affiche —
## assez courte pour ne jamais gêner un lancer rapide et nerveux, assez longue
## pour ne pas clignoter sur un simple appui (même ordre de grandeur que
## PingController.HOLD_THRESHOLD_S = 0.25, légèrement plus court : l'arc est
## un simple aperçu continu, pas une roue à choix qui a besoin de temps pour être lue).
const HOLD_THRESHOLD_S := 0.15

## Vrai si l'aperçu de trajectoire doit être affiché MAINTENANT (touche
## maintenue depuis au moins le seuil) — appelé en continu pendant l'appui,
## PAS seulement au relâchement (contrairement à PingController.is_hold, lu
## une fois au relâchement pour choisir appui/roue).
static func should_show_arc(held_duration_s: float, threshold_s: float = HOLD_THRESHOLD_S) -> bool:
	return held_duration_s >= threshold_s

## Frag uniquement (contrat lead : "Frag can be 'cooked': its fuse starts when
## the key goes down; if held past the fuse it explodes in hand") — vrai dès
## que la durée de maintien atteint l'amorce complète, AVANT tout relâchement :
## l'appelant doit alors détoner immédiatement dans la main plutôt qu'attendre
## un relâchement qui ne viendra peut-être jamais.
static func should_explode_in_hand(held_duration_s: float, fuse_time: float) -> bool:
	return held_duration_s >= fuse_time

## Temps d'amorce RESTANT au lancer d'une frag relâchée après `held_duration_s`
## de maintien (l'amorce a démarré au premier appui, contrat lead) — jamais
## négatif (une frag qui explique déjà dans la main ne passe pas par ce chemin,
## voir `should_explode_in_hand`, vérifié en premier par l'appelant).
static func fuse_left_on_release(held_duration_s: float, fuse_time: float) -> float:
	return maxf(fuse_time - held_duration_s, 0.0)
