## AbilityBar.gd
## Rangée de badges de capacité (bas-centre), alimentée par
## `AbilityController.slot_info()` (contrat inchangé). Reconstruit les badges
## uniquement quand le nombre de slots change (agent stable en cours de partie).
##
## v4 « Encre, jaune, italique » (UX-31 puis UX-36, UI_DIRECTION_BL3.md §5
## « bas-centre : C · A · E (tuiles penchées 72) + X (88) ; charges =
## barrettes, recharge = chiffre 37 ») -- UX-31 avait laissé `ComicChip`
## dessiner un hexagone Ø72 fixe (hors de sa liste de fichiers). UX-36 possède
## désormais `scripts/ui/ComicChip.gd` : il dessine la tuile penchée 72/88
## décrite ci-dessus (voir sa doc de classe) tout en gardant EXACTEMENT le
## même type public (`class_name ComicChip`, champ `_key`, `setup()`/
## `set_status()`) que lisent tests/ui/test_ability_icons.gd et
## tests/ui/test_key_labels.gd (typage `bar._chips[i]` en `ComicChip`,
## décision du lead 2026-09-25 : « adapter au nouveau type en gardant ce
## qu'ils vérifient » -- rien à changer côté de ces deux suites, le
## renouvellement reste interne à ComicChip.gd).
class_name AbilityBar
extends HBoxContainer

var _chips: Array = []
## UX-21 -- une icône peinte (TextureRect, ou `null`) par chip, superposée sur
## le glyphe abstrait de ComicChip (composition externe : ComicChip.gd dessine
## toujours son losange dessous, hors de mon périmètre d'écriture -- voir sa
## doc de classe, "glyphe abstrait ... jamais un pictogramme figuratif, hors
## périmètre de cette tâche"). Rangée en parallèle de `_chips`.
var _chip_icons: Array = []

func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", Comic.SP_2)
	Comic.anchor(self, Control.PRESET_BOTTOM_WIDE)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Hauteur figée explicitement (ne dépend pas de la taille mini des badges,
	# qui n'existent pas encore au premier `_ready` — voir `refresh`).
	# `ComicChip.SIZE.y` réserve déjà le gabarit du plus grand badge (l'ultime,
	# 88 px + légende + barrettes, voir sa doc de classe) : la rangée entière
	# (C/A/E à 72 px compris) tient dans cette même hauteur.
	custom_minimum_size = Vector2(0, ComicChip.SIZE.y)
	offset_top = -(ComicChip.SIZE.y + Comic.SAFE_MARGIN)
	offset_bottom = -Comic.SAFE_MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## `agent` : AgentConfig du joueur local (GameHUD.gd le lit sur
## `AbilityController.agent`, hors de mon périmètre d'écriture mais un champ
## public déjà exposé) -- sert UNIQUEMENT à retrouver `Ability.cooldown`
## (durée totale, en secondes) par index de slot, pour convertir le ratio
## 0..1 de `slot_info()` en secondes restantes (voir `_apply_state`). Optionnel
## (`null` par défaut) pour ne pas casser les appels existants qui ne
## fournissent que `infos` (tests/ui/test_key_labels.gd) -- retombe alors sur
## le pourcentage, comme avant.
func refresh(infos: Array, agent: AgentConfig = null) -> void:
	if _chips.size() != infos.size():
		for c in get_children():
			c.queue_free()
		_chips.clear()
		_chip_icons.clear()
		for i in infos.size():
			var s: Dictionary = infos[i]
			var chip := ComicChip.new()
			# UX-13 : jamais `s.slot` brut ("C"/"Q"/"E"/"X", identifiant réseau
			# interne) -- le badge affiche le libellé de la VRAIE touche.
			var key_label := KeyLabel.for_action(PlayerInput.action_for_slot(str(s.slot)))
			chip.setup(key_label, str(s.name), bool(s.ult))
			chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			add_child(chip)
			_chips.append(chip)
			_chip_icons.append(_make_icon(chip, agent, str(s.slot)))
		return
	for i in infos.size():
		var cooldown_s := 0.0
		if agent != null and i < agent.abilities.size():
			cooldown_s = float(agent.abilities[i].cooldown)
		var ready_state := _apply_state(_chips[i], infos[i], cooldown_s)
		_apply_icon_state(i, ready_state)

## UX-21 : icône peinte de la capacité `slot` de `agent`, posée au centre de
## la tuile `chip` (`ComicChip.tile_center()`/`tile_diam()`, UX-36 -- suit la
## taille EFFECTIVE de la tuile, 72 ou 88 selon `chip._is_ult`, jamais un
## diamètre fixe supposé identique pour tous les badges). `null` si `agent`
## n'est pas fourni (repli existant des appelants historiques qui ne passent
## que `infos`, voir doc de `refresh`) ou si le PNG n'existe pas encore
## (AgentDatabase.ability_icon renvoie alors `null` -- rien n'est ajouté, le
## losange de ComicChip reste seul visible).
func _make_icon(chip: ComicChip, agent: AgentConfig, slot: String) -> TextureRect:
	if agent == null:
		return null
	var tex := AgentDatabase.ability_icon(agent, slot)
	if tex == null:
		return null
	var icon := TextureRect.new()
	icon.texture = tex
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# AGT-09 (bug déjà rencontré sur le portrait d'AgentSelectScreen.gd) :
	# EXPAND_KEEP_SIZE (défaut) imposerait la taille SOURCE (128x128) comme
	# minimum -- IGNORE_SIZE laisse `.size` ci-dessous gouverner seul.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := chip.tile_diam() * 0.55  # laisse la tuile visible tout autour (touche, barrettes).
	icon.position = chip.tile_center() - Vector2(d, d) * 0.5
	icon.size = Vector2(d, d)
	chip.add_child(icon)
	return icon

## Assourdit l'icône en recharge (garde lisible la tuile dessous, §5
## « Recharge ») ; pleine opacité prête/ultime prêt.
func _apply_icon_state(i: int, ready_state: bool) -> void:
	if i >= _chip_icons.size():
		return
	var icon: TextureRect = _chip_icons[i]
	if icon:
		icon.modulate = Color(1.0, 1.0, 1.0, 1.0 if ready_state else 0.45)

## État de jeu -> rendu (UI_DIRECTION_BL3.md §5, colonne « bas-centre ») :
## Prêt et Ultime prêt n'affichent AUCUNE légende. Recharge (capacité à
## charges, cooldown fixe) affiche le temps restant en SECONDES (`cooldown_s`,
## durée totale reçue de `refresh`, moins ce que le ratio 0..1 de
## `AbilityController.slot_info()` -- hors de mon périmètre d'écriture --
## indique déjà écoulé) plutôt qu'un pourcentage : `AbilityState.cooldown_left`
## est un minuteur pur (tests/agents/test_ability_state.gd), l'inversion est
## donc fidèle. L'ultime en cours de charge reste en pourcentage : sa
## progression (AbilityState.tick/add_ult, hors de mon périmètre d'écriture)
## mélange un gain continu et des bonus irréguliers sur kill/dégâts -- un
## compte à rebours en secondes y serait fabriqué et faux dès le kill suivant,
## et §5 ne documente des secondes que pour la ligne « Recharge » d'une
## capacité à cooldown fixe, pas pour l'accumulation d'ultime. Repli en
## pourcentage aussi si `cooldown_s` est indisponible (agent non fourni).
func _apply_state(chip: ComicChip, s: Dictionary, cooldown_s: float = 0.0) -> bool:
	if bool(s.ult):
		var ready := bool(s.ready)
		# UI_DIRECTION_BL3.md §5 #4 « pas de valeur de debug » : jamais « 0% »
		# à l'instant où l'ultime vient d'être consommé (ratio tombé à 0) --
		# une tuile qui recommence à charger n'a rien à annoncer avant sa
		# première fraction de progression réelle.
		var pct := int(float(s.ratio) * 100.0)
		var txt := "" if (ready or pct <= 0) else "%d%%" % pct
		chip.set_status(txt, ready, float(s.ratio), -1)
		return ready
	elif int(s.charges) > 0:
		chip.set_status("", true, 1.0, int(s.charges))
		return true
	elif cooldown_s > 0.0:
		var seconds_left := int(ceil(cooldown_s * (1.0 - float(s.ratio))))
		chip.set_status("%ds" % maxi(seconds_left, 1), false, float(s.ratio), 0)
		return false
	else:
		chip.set_status("%d%%" % int(float(s.ratio) * 100.0), false, float(s.ratio), 0)
		return false
