## HudFormat.gd
## Fonctions PURES (aucun état, aucun nœud) utilisées par le HUD : formatage de
## texte, maths de mise en page, contraste de tokens. Isolées ici pour rester
## testables sans scène (voir tests/ui/test_hud_format.gd).
class_name HudFormat
extends RefCounted

## Munitions : « 25 » (chargeur) — la réserve est un label séparé (« / 90 »).
static func format_ammo(current: int) -> String:
	return "%d" % maxi(0, current)

static func format_reserve(reserve: int) -> String:
	return "/ %d" % maxi(0, reserve)

## Munitions basses (§2.6 STYLE_BIBLE v3 §8.6, tokens.json
## hud.low_ammo_threshold) : seuil du CHARGEUR sous lequel les chiffres
## passent en pinceau (AmmoPanel.update_ammo) — même seuil pour l'invite
## RECHARGER (`should_show_reload_prompt`), une seule source de vérité.
const LOW_AMMO_RATIO := 0.25

## Délai (s) après la dernière rafale avant que l'invite RECHARGER n'apparaisse
## (GF-23 §2.6 : « 1,5 s après la dernière rafale (jamais pendant le tir) »).
const RELOAD_PROMPT_DELAY := 1.5

## État visuel de la RÉSERVE (GF-23 §2.6) : « empty » (0, rouge d'encre + la
## mention VIDE), « low » (il reste ≤ 1 chargeur en réserve, ocre) ou
## « normal » (crème, défaut). `mag_size` <= 0 (arme pas encore annoncée par
## `update_weapon`) : jamais « low » faute de dénominateur connu — seuls
## « empty »/« normal » restent possibles, comme le chargeur (voir
## AmmoPanel._mag_size).
static func reserve_state(reserve: int, mag_size: int) -> String:
	if reserve <= 0:
		return "empty"
	if mag_size > 0 and reserve <= mag_size:
		return "low"
	return "normal"

## Texte de la réserve : « VIDE » à 0 (§2.6), sinon « / N » (`format_reserve`,
## inchangée — un test verrouillé attend « / 90 » pour une réserve positive).
static func format_reserve_label(reserve: int) -> String:
	return "VIDE" if reserve <= 0 else format_reserve(reserve)

## Invite « [touche] RECHARGER » (GF-23 §2.6) : vrai quand le chargeur est à
## ≤ `LOW_AMMO_RATIO`, qu'il reste de la réserve, et qu'au moins
## `RELOAD_PROMPT_DELAY` secondes se sont écoulées depuis la dernière rafale.
## Aucun état « is_firing » séparé n'est nécessaire : une rafale en cours
## consomme le chargeur en continu, ce qui remet `time_since_last_shot` à 0 à
## chaque coup (voir AmmoPanel._mag_prev) — le délai ne peut donc jamais
## s'écouler PENDANT le tir. `mag_size` <= 0 (arme inconnue) : toujours faux.
static func should_show_reload_prompt(mag: int, mag_size: int, reserve: int, time_since_last_shot: float) -> bool:
	if mag_size <= 0 or reserve <= 0:
		return false
	if float(mag) / float(mag_size) > LOW_AMMO_RATIO:
		return false
	return time_since_last_shot >= RELOAD_PROMPT_DELAY

## Invite « [touche] CHANGER D'ARME » (GF-23 §2.6) : chargeur ET réserve à 0.
static func should_show_switch_weapon_prompt(mag: int, reserve: int) -> bool:
	return mag <= 0 and reserve <= 0

## Libellé complet de l'invite RECHARGER — `key_label` est le VRAI libellé de
## touche (UX-13, fourni par l'appelant via `KeyLabel.for_action("reload")`,
## hors de cette fonction PURE pour rester testable sans `DisplayServer`).
static func format_reload_prompt(key_label: String) -> String:
	return "[%s] RECHARGER" % key_label

## Libellé complet de l'invite CHANGER D'ARME — même remarque que
## `format_reload_prompt` sur la provenance de `key_label`.
static func format_switch_weapon_prompt(key_label: String) -> String:
	return "[%s] CHANGER D'ARME" % key_label

## Action d'entrée (project.godot [input]) de l'arme SUIVANTE dans
## l'inventaire, pour alimenter l'invite CHANGER D'ARME avec la bonne touche :
## même cycle que le passage automatique au clic à vide
## (`Weapon._owner_tick`, `(current + 1) % nombre de slots`) —
## « weapon_1 »/« weapon_2 »/… (1-indexées, voir project.godot). `weapon_count`
## <= 0 (inventaire pas encore annoncé par `update_inventory`) : repli sur
## « weapon_2 », l'arme secondaire étant la cible la plus fréquente d'un
## changement d'arme à sec (chargeur ET réserve à 0 sur la primaire).
static func next_weapon_action(current_index: int, weapon_count: int) -> String:
	if weapon_count <= 0:
		return "weapon_2"
	var target := (current_index + 1) % weapon_count
	return "weapon_%d" % (target + 1)

## Toast de ramassage (GF-23 §2.6 : « +N ARME » pendant 1,2 s) — `amount` est
## le nombre de chargeurs ajoutés à la réserve (cartouchière/caisse, GF-22).
static func format_ammo_pickup_toast(amount: int) -> String:
	return "+%d ARME" % amount

## Détecte un ramassage de munitions entre deux appels successifs à
## `AmmoPanel.update_ammo` (§2.6, GF-22 : la cartouchière/caisse augmente la
## RÉSERVE de l'arme active — `Weapon.server_add_reserve_mags`, seule voie qui
## fait grimper la réserve, remonte au HUD par le même signal `ammo_changed`
## que les rafales qui la font baisser ; aucun câblage séparé n'est donc
## nécessaire, seule la DÉTECTION du sens du changement l'est). Renvoie le
## nombre de chargeurs ajoutés (arrondi au plus proche — un ramassage plafonné
## par `Inventory.reserve_for` peut ajouter moins qu'un chargeur plein, jamais
## affiché comme « +1 » trompeur), ou 0 si :
## - `prev_mag` ou `prev_reserve` < 0 : premier appel (`AmmoPanel._mag_prev`/
##   `_reserve_prev` toujours -1 avant le tout premier `update_ammo`, ou juste
##   après un VRAI changement d'arme — voir la doc de `AmmoPanel._weapon_name`) ;
## - `mag_size` <= 0 : arme pas encore annoncée, aucune taille de chargeur
##   connue pour convertir un delta de munitions en « chargeurs » ;
## - `reserve` <= `prev_reserve` : une rafale/un rechargement fait baisser ou
##   laisse égale la réserve, jamais un ramassage ;
## - `mag` != `prev_mag` : le CHARGEUR a changé EN MÊME TEMPS que la réserve —
##   uniquement un respawn/une resynchro serveur (`Weapon._server_respawn_
##   reset`, hors de ce lot de fichiers, qui remplit mag ET réserve ensemble),
##   JAMAIS un ramassage (`server_add_reserve_mags` ne touche QUE la réserve,
##   jamais le chargeur) — sans ce garde, chaque réapparition afficherait à
##   tort « +N ARME ».
static func reserve_pickup_magazines(prev_mag: int, mag: int, prev_reserve: int, reserve: int, mag_size: int) -> int:
	if prev_mag < 0 or prev_reserve < 0 or mag_size <= 0:
		return 0
	if mag != prev_mag or reserve <= prev_reserve:
		return 0
	return int(round(float(reserve - prev_reserve) / float(mag_size)))

## Minuteur mm:ss, jamais négatif.
static func format_timer(seconds: float) -> String:
	var s := maxi(0, int(ceil(seconds)))
	return "%d:%02d" % [s / 60, s % 60]

## Crédits (économie SnD) : « 3 900 ¤ » — espace insécable tous les 3 chiffres.
static func format_credits(credits: int) -> String:
	var n := maxi(0, credits)
	var digits := str(n)
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i != 0:
			out = " " + out
	return "%s ¤" % out

## Score de ligne « ÉQ.1  <a>  —  <b>  ÉQ.2 ».
static func format_score_line(team0: int, team1: int) -> String:
	return "ÉQ.1   %d   —   %d   ÉQ.2" % [team0, team1]

## Zone centrale 40 % x 40 % du HUD (design.md §8 : crosshair/hitmarkers/scope
## uniquement, rien d'autre ne doit s'y dessiner). Retourne le rect en pixels
## de la taille de viewport donnée.
static func center_zone_rect(viewport_size: Vector2) -> Rect2:
	var w := viewport_size.x * 0.4
	var h := viewport_size.y * 0.4
	return Rect2((viewport_size - Vector2(w, h)) * 0.5, Vector2(w, h))

## true si `rect` chevauche la zone centrale (sert à vérifier qu'un élément
## HUD ne s'y dessine jamais, ex. une onomatopée).
static func overlaps_center_zone(rect: Rect2, viewport_size: Vector2) -> bool:
	return rect.intersects(center_zone_rect(viewport_size))

## Luminance relative WCAG (sRGB) d'une couleur.
static func relative_luminance(c: Color) -> float:
	var chans := [c.r, c.g, c.b]
	var lin := []
	for v in chans:
		lin.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]

## Ratio de contraste WCAG entre deux couleurs (1..21). Sert à vérifier les
## tokens de design.md (ex. ink/paper ~14.6:1).
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := relative_luminance(a) + 0.05
	var lb := relative_luminance(b) + 0.05
	return maxf(la, lb) / minf(la, lb)
