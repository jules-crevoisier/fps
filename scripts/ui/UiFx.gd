## UiFx.gd
## Kit de motion UI centralisé (UX-12, docs/style/tokens.json "motion",
## STYLE_BIBLE v3 §8.2) : trois primitives réutilisables par les menus —
## `reveal()` (apparition de panneau/page), `wipe()` (bandeau qui se déploie
## de gauche à droite) et `press()` (bouton qui s'écrase sur son ombre).
## Toutes cubiques (`Tween.TRANS_CUBIC`, `EASE_OUT`), sur les durées verrouillées
## de `Comic.gd` (`DUR_REVEAL` 250 ms, `DUR_WIPE` 280 ms, `DUR_PRESS` 90 ms).
##
## Jamais bloquantes : chaque fabrique rend un `Tween` PORTÉ par le nœud animé
## (`node.create_tween()`, jamais `get_tree().create_timer()` avec un lambda
## qui capture un nœud — règle du projet, CLAUDE.md), et aucun appelant n'a
## besoin d'`await` : le clic reste actif pendant toute l'animation (aucun
## `mouse_filter`/`disabled` n'est jamais touché ici).
##
## `reveal()` translate par les OFFSETS (`offset_top`/`offset_bottom`), jamais
## par `position` seule : sur un enfant de `Container`, changer `position` ne
## bouge que le coin haut-gauche et déforme la taille si les deux ancres
## opposées sont fixées (ex. un panneau plein-écran) ; décaler les deux offsets
## du même delta préserve toujours la taille, dans un `Container` ou non.
## `wipe()`/`press()` utilisent `scale`, une transform de rendu jamais gérée
## par les conteneurs (sûr partout).
##
## Mouvement réduit (`Comic.reduced_motion()`, tokens.json
## "reduced_motion.forbid": scale/rotation/position/shake/pulse/blink,
## "allow": fade) : chaque effet se réduit à un fondu d'opacité seul, sur
## `Comic.DUR_REDUCED_FADE` (120 ms, tokens.json "reduced_motion.fade_ms").
class_name UiFx
extends RefCounted

## Révèle un panneau/contrôle : translation verticale (le bas vers sa position
## d'origine) + fondu, `Comic.DUR_REVEAL`, cubic out. Mouvement réduit : fondu
## seul, la géométrie ne bouge jamais. Sûr à rappeler sur le même nœud (tue le
## tween de révélation précédent) — typiquement à chaque page/onglet affiché.
## `node` DOIT déjà être dans l'arbre (appeler après `add_child`).
static func reveal(node: Control, translate_px: float = Comic.REVEAL_TRANSLATE_PX) -> Tween:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return null
	var tw := _restart_tween(node, "reveal")
	if Comic.reduced_motion():
		node.modulate.a = 0.0
		tw.tween_property(node, "modulate:a", 1.0, Comic.DUR_REDUCED_FADE)
		return tw
	var top0 := node.offset_top
	var bottom0 := node.offset_bottom
	node.modulate.a = 0.0
	node.offset_top = top0 + translate_px
	node.offset_bottom = bottom0 + translate_px
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.set_parallel(true)
	tw.tween_property(node, "modulate:a", 1.0, Comic.DUR_REVEAL)
	tw.tween_property(node, "offset_top", top0, Comic.DUR_REVEAL)
	tw.tween_property(node, "offset_bottom", bottom0, Comic.DUR_REVEAL)
	return tw

## Bandeau qui se déploie de gauche à droite (queue de pinceau, barre
## d'accent, remplissage de jauge…) : mise à l'échelle horizontale 0 -> 1
## depuis le bord gauche (`pivot_offset` posé sur le bord gauche, `scale.x` —
## ne touche jamais `position`/`size`, donc sûr sur un enfant de `Container`),
## `Comic.DUR_WIPE`, cubic out. Mouvement réduit : fondu seul, pleine largeur
## immédiatement (tokens.json interdit "scale" en mouvement réduit).
## `bar` DOIT déjà être dans l'arbre (appeler après `add_child`).
static func wipe(bar: Control) -> Tween:
	if bar == null or not is_instance_valid(bar) or not bar.is_inside_tree():
		return null
	bar.pivot_offset = Vector2(0.0, bar.size.y * 0.5)
	var tw := _restart_tween(bar, "wipe")
	if Comic.reduced_motion():
		bar.scale.x = 1.0
		bar.modulate.a = 0.0
		tw.tween_property(bar, "modulate:a", 1.0, Comic.DUR_REDUCED_FADE)
		return tw
	bar.modulate.a = 1.0
	bar.scale.x = 0.0
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(bar, "scale:x", 1.0, Comic.DUR_WIPE)
	return tw

## Câble un bouton pour qu'il s'écrase sur son ombre pendant l'appui
## (autocollant, `Comic.DUR_PRESS`, cubic out) : échelle 1 -> 0,94 sur
## `button_down`, retour à 1 sur `button_up`. N'ajoute qu'UNE connexion même
## rappelé plusieurs fois sur le même bouton (`has_meta` garde), ne désactive
## jamais le bouton ni ne consomme l'entrée — le clic natif (signal `pressed`,
## styles `hover`/`pressed` du Theme) continue de fonctionner normalement
## pendant l'animation. Mouvement réduit : aucune échelle (tokens.json
## interdit "scale") — le bouton garde son seul retour natif du Theme.
static func press(button: BaseButton) -> void:
	if button == null or not is_instance_valid(button) or button.has_meta("_uifx_press_wired"):
		return
	button.set_meta("_uifx_press_wired", true)
	button.pivot_offset = button.size * 0.5
	button.resized.connect(func():
		if is_instance_valid(button):
			button.pivot_offset = button.size * 0.5)
	button.button_down.connect(_squash.bind(button, true))
	button.button_up.connect(_squash.bind(button, false))
	# Un bouton peut quitter l'arbre en plein "écrasé" (fermeture de page
	# pendant l'appui) : on remet l'échelle à 1 pour ne jamais laisser un
	# contrôle réutilisé ailleurs figé en miniature.
	button.tree_exiting.connect(func():
		if is_instance_valid(button):
			button.scale = Vector2.ONE)

static func _squash(button: BaseButton, down: bool) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree() or Comic.reduced_motion():
		return
	var tw := _restart_tween(button, "press")
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(button, "scale", Vector2(0.94, 0.94) if down else Vector2.ONE, Comic.DUR_PRESS)

## Un tween par nœud ET par effet (`key` : "reveal"/"wipe"/"press") — deux
## effets différents sur le même nœud (ex. un bouton révélé puis pressé
## pendant sa révélation) restent indépendants ; rappeler le MÊME effet tue
## proprement le tween précédent au lieu d'empiler deux animations qui se
## disputent la même propriété.
static func _restart_tween(node: Node, key: String) -> Tween:
	var meta_key := "_uifx_tween_%s" % key
	# `get_meta(key, default)` journalise quand même une ERROR si la clé est
	# absente (le défaut `null` n'est pas distingué de "aucun défaut" côté
	# moteur, vérifié en Godot 4.7) : `has_meta` d'abord évite le bruit.
	if node.has_meta(meta_key):
		var prev: Tween = node.get_meta(meta_key)
		if prev != null and is_instance_valid(prev) and prev.is_valid():
			prev.kill()
	var tw := node.create_tween()
	node.set_meta(meta_key, tw)
	return tw
