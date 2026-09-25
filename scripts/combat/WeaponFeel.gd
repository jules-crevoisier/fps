## WeaponFeel.gd
## Calculs PURS de la "sensation d'arme" (contract-r3.md, R3-IN#4 ; continu
## façon Valorant, MV-02) : motif de recul fixe puis pseudo-aléatoire,
## dispersion additionnelle en mouvement (continue, avec zone morte)/en l'air,
## délai avant de pouvoir tirer après une glissade/un plongeon (le sprint est
## automatique et n'impose plus aucun délai, BUG-K01), progression de la
## transition de visée (ADS), et ralentissement du déplacement en ADS. Aucun
## accès à l'arbre de scène — consommé par Weapon.gd (prédiction PROPRIÉTAIRE ;
## le serveur ne revalide pas la dispersion/le recul, seulement l'origine/la
## direction du tir via ShotValidator, donc prédiction et serveur restent
## cohérents par construction) et par les states de mouvement Sprint.gd/Walk.gd
## (vitesse cible ralentie en ADS). Testé isolément dans
## tests/combat/test_weapon_feel.gd. Étendu par AGT-08 (Sang-froid de Verrou,
## docs/research/10_ammo_kits_input.md §3.3) : `total_spread_deg`/
## `recoil_for_shot` acceptent un multiplicateur de passif optionnel (défaut
## neutre, 1.0 — aucun appelant existant n'est affecté), et `is_steady`/
## `steady_spread_mult`/`steady_recoil_mult` calculent PUREMENT la condition
## et les multiplicateurs de Sang-froid (scripts/agents/passives/SangFroid.gd
## fournit `time_still`/`speed`/`crouching` depuis un joueur réel). Testé dans
## tests/agents/test_verrou_kit.gd (fichier possédé par AGT-08, pas
## test_weapon_feel.gd, hors périmètre de ce contrat).
## Étendu par GF-29 (docs/research/01_game_feel.md, câblage GF-08/MV-03) :
## `shot_trauma_amount` dérive un trauma de tir borné PAR ARME
## (CameraShake.SHOT_TRAUMA_MIN/MAX) sans nouveau champ sur WeaponConfig (hors
## de mon périmètre de fichiers pour cette tâche — voir son rendu), et
## `total_spread_deg` accepte un `stun_spread` optionnel (MV-03 :
## +stun_fire_spread_add pendant l'état "Stun", MovementConfig.
## stun_fire_spread_add). Testés dans tests/player/test_camera_shake_wiring.gd
## (fichier possédé par GF-29).
class_name WeaponFeel
extends RefCounted

## Plage de référence de `WeaponConfig.recoil_vertical` observée dans
## resources/weapons/*.tres (0.35 pistolet/SMG -> 2.2 sniper Faucheur) —
## calibration de `shot_trauma_amount` ci-dessous.
const _RECOIL_TRAUMA_MIN_REF := 0.3
const _RECOIL_TRAUMA_MAX_REF := 2.2

## Trauma de tir (GF-29, CameraShake.add_shot_trauma) PAR ARME : dérivé du
## recul vertical existant de l'arme (`WeaponConfig.recoil_vertical`, proxy
## déjà présent de la "punch" ressentie par arme) plutôt que d'un nouveau champ
## dédié sur WeaponConfig.gd (hors de mon périmètre de fichiers pour cette
## tâche — voir le rendu de tâche GF-29). Linéaire sur la plage observée
## `_RECOIL_TRAUMA_MIN_REF`/`_RECOIL_TRAUMA_MAX_REF`, reborné à
## [CameraShake.SHOT_TRAUMA_MIN, CameraShake.SHOT_TRAUMA_MAX] (0.08-0.25,
## contrat GF-08) — `CameraShake.add_shot_trauma`/`shot_trauma` rebornent de
## toute façon défensivement en cas de dérive. `null` (défensif seul, Weapon.gd
## ne tire jamais sans WeaponConfig résolu) -> minimum de la plage.
static func shot_trauma_amount(c: WeaponConfig) -> float:
	if c == null:
		return CameraShake.SHOT_TRAUMA_MIN
	var t := inverse_lerp(_RECOIL_TRAUMA_MIN_REF, _RECOIL_TRAUMA_MAX_REF, c.recoil_vertical)
	return lerp(CameraShake.SHOT_TRAUMA_MIN, CameraShake.SHOT_TRAUMA_MAX, clampf(t, 0.0, 1.0))

## Décalage de recul pour le `shot_index`-ième tir (0-based) DEPUIS le début
## du spray courant : x = déviation horizontale (yaw, deg), y = montée
## verticale (pitch, deg). Sous `pattern_shots`, suit `recoil_pattern`
## (motif FIXE, façon Valorant) ; au-delà, retombe sur le recul
## pseudo-aléatoire (recoil_horizontal aléatoire, recoil_vertical constant —
## comportement pré-existant). `rng` optionnel pour rendre le tirage
## déterministe en test ; par défaut le RNG global (randf_range).
## `recoil_mult` (AGT-08, Sang-froid de Verrou — voir steady_recoil_mult
## ci-dessous) : multiplie UNIQUEMENT la composante VERTICALE (montée, `y`) —
## la déviation horizontale (`x`, aléatoire) n'est jamais réduite par ce
## passif ("recul vertical -20 %", docs/research/10_ammo_kits_input.md §3.3).
## 1.0 par défaut (aucun effet, comportement inchangé pour tout appelant
## existant).
static func recoil_for_shot(c: WeaponConfig, shot_index: int, rng: RandomNumberGenerator = null,
		recoil_mult: float = 1.0) -> Vector2:
	var kick: Vector2
	if shot_index >= 0 and shot_index < c.pattern_shots and shot_index < c.recoil_pattern.size():
		var p: Vector2 = c.recoil_pattern[shot_index]
		kick = Vector2(p.x, p.y)
	else:
		var rh := c.recoil_horizontal
		var yaw := rng.randf_range(-rh, rh) if rng else randf_range(-rh, rh)
		kick = Vector2(yaw, c.recoil_vertical)
	return Vector2(kick.x, kick.y * recoil_mult)

## Dispersion de mouvement CONTINUE (deg, MV-02, façon Valorant) : monte
## progressivement de 0 (sous la zone morte `move_spread_deadzone` × vitesse
## de sprint) à `move_spread_add` (à la vitesse de sprint et au-delà), via
## smoothstep — remplace l'ancien "moving" booléen qui ne distinguait pas
## 1 m/s de 12 m/s. En glissade (slide), la pénalité est majorée de
## `slide_spread_mult` (corps instable). `speed`/`sprint_speed` en m/s.
static func move_spread_deg(c: WeaponConfig, speed: float, sprint_speed: float, sliding: bool) -> float:
	var ratio := speed / maxf(sprint_speed, 0.001)
	var t := smoothstep(c.move_spread_deadzone, 1.0, ratio)
	var s := c.move_spread_add * t
	if sliding:
		s *= c.slide_spread_mult
	return s

## Dispersion totale (deg) = dispersion de base (hanche ou visée, choisie par
## l'appelant) + pénalité de mouvement (déjà calculée par move_spread_deg,
## continue) + pénalité aérienne (déjà résolue par l'appelant : en l'air ou
## non, pas de dégradé utile ici — air_spread_add ou 0.0). Simple addition
## PURE, testée pour la régression. `passive_mult` (AGT-08, Sang-froid de
## Verrou — voir steady_spread_mult ci-dessous) multiplie le TOUT : en
## pratique move_spread/air_spread sont déjà nuls quand Sang-froid s'active
## (immobile et au sol), donc ce multiplicateur ne réduit dans les faits que
## `base_deg`. 1.0 par défaut (aucun effet, comportement inchangé pour tout
## appelant existant). `stun_spread` (GF-29/MV-03, MovementConfig.
## stun_fire_spread_add) : pénalité additionnelle pendant l'état "Stun", même
## traitement additif que `move_spread`/`air_spread` (résolue par l'appelant —
## `player.config.stun_fire_spread_add` si `state_machine.current_name ==
## "Stun"`, sinon 0.0, voir Weapon._fire_local) ; 0.0 par défaut (aucun effet,
## comportement inchangé pour tout appelant existant, dont GameHUD.gd).
static func total_spread_deg(base_deg: float, move_spread: float, air_spread: float,
		passive_mult: float = 1.0, stun_spread: float = 0.0) -> float:
	return (base_deg + move_spread + air_spread + stun_spread) * passive_mult

## Vitesse cible (m/s) ralentie en visée (ADS, MV-02) : `ads_move_mult`
## (défaut 0.7, voir MovementConfig) s'applique tant que `aiming` est vrai ;
## sinon `base_speed` inchangée. Consommée par Sprint.gd (le sprint auto est
## ainsi "suspendu" en visée : la vitesse cible retombe au palier de marche
## ralenti) et Walk.gd (marche encore ralentie si on vise en plus).
static func ads_move_speed(base_speed: float, aiming: bool, ads_move_mult: float) -> float:
	if aiming:
		return base_speed * ads_move_mult
	return base_speed

## Délai (s) restant avant de pouvoir tirer, selon le temps écoulé (s) depuis
## la fin d'une glissade/d'un plongeon (INF si l'action n'a jamais eu lieu —
## pas de pénalité). Le sprint est automatique (docs/MOVEMENT.md) et n'impose
## plus de délai (BUG-K01 : sprint_to_fire retiré, mécanique inopérante). Le
## délai le plus contraignant des deux domine (slide_to_fire/dive_to_fire) ;
## jamais négatif.
static func fire_delay_left(c: WeaponConfig, since_slide: float, since_dive: float) -> float:
	var left := 0.0
	left = maxf(left, c.slide_to_fire - since_slide)
	left = maxf(left, c.dive_to_fire - since_dive)
	return left

## Progression ADS (0 = hanche, 1 = visée pleine), avancée sur `ads_time` s
## (au lieu d'une vitesse fixe) — voir ViewModel.AnimState.ads_blend.
static func ads_progress(current: float, aiming: bool, delta: float, ads_time: float) -> float:
	var t := maxf(ads_time, 0.001)
	return move_toward(current, 1.0 if aiming else 0.0, delta / t)

## Direction dispersée en DISQUE (pas en carré), dans le repère CAMÉRA (GF-13,
## docs/research/01_game_feel.md #7) : remplace l'ancienne dispersion de
## `Weapon._apply_spread`, qui tirait deux `randf_range` indépendants (carré
## [-spread, spread]², coins surreprésentés) et tournait autour de
## `Vector3.UP` MONDIAL — à un pitch caméra proche de la verticale, cet axe
## devient quasi parallèle à `base_dir` et le cône s'aplatit (plus circulaire).
## Ici : angle azimutal `theta` uniforme sur [0, TAU), rayon `r = sqrt(u) *
## spread_rad` (densité uniforme sur le DISQUE, pas sur le carré — u uniforme
## sur [0,1[), puis rotation de `base_dir` autour de l'axe DROIT de la caméra
## (`cam_basis.x`, déviation "pitch") puis de son axe HAUT (`cam_basis.y`,
## déviation "yaw") : les deux sont TOUJOURS perpendiculaires à `base_dir`
## quelle que soit l'orientation de la caméra, donc le cône reste circulaire
## même à pitch extrême (+-80°). L'angle entre le résultat et `base_dir` est
## borné par construction : jamais > `r`, donc jamais > `spread_rad` — 100 %
## des tirages restent dans le cône. `rng` optionnel pour un tirage
## déterministe en test ; par défaut le RNG global. Consommée par
## `Weapon._fire_local` (prédiction PROPRIÉTAIRE, un tirage par plomb) ; l'écho
## cosmétique (`Weapon._remote_shot_fx`) réutilise les `dirs` déjà tirés reçus
## du serveur, donc ne rappelle jamais cette fonction.
static func spread_dir(base_dir: Vector3, cam_basis: Basis, spread_rad: float, rng: RandomNumberGenerator = null) -> Vector3:
	if spread_rad <= 0.0:
		return base_dir.normalized()
	var u := rng.randf() if rng else randf()
	var theta := (rng.randf() if rng else randf()) * TAU
	var r := sqrt(u) * spread_rad
	var pitch := r * sin(theta)
	var yaw := r * cos(theta)
	var right := cam_basis.x.normalized()
	var up := cam_basis.y.normalized()
	return base_dir.rotated(right, pitch).rotated(up, yaw).normalized()

## Écart (px, demi-distance entre les deux traits opposés du réticule, GF-09,
## docs/research/01_game_feel.md #8) pour une dispersion `spread_rad` (rad,
## demi-angle du cône de tir — MÊME valeur que celle passée à `WeaponFeel.spread_dir`
## dans Weapon._fire_local, jamais une approximation locale au HUD) : projette
## le cône sur l'écran via la FOV VERTICALE de la caméra (`fov_v_rad`,
## Camera3D.fov en keep-height, voir PlayerCamera.gd) et la hauteur d'écran
## (px) — tan(spread)/tan(fov_v/2) × hauteur_écran/2. `fov_v_rad` est borné à
## un minimum non nul pour ne jamais diviser par tan(0) = 0 (caméra mal
## configurée, cas défensif seulement).
static func crosshair_gap_px(spread_rad: float, fov_v_rad: float, screen_height: float) -> float:
	var half_fov := maxf(fov_v_rad, 0.001) * 0.5
	return tan(spread_rad) / tan(half_fov) * (screen_height * 0.5)

## Alpha (0..1) du "bloom" cosmétique du réticule (GF-09 : "bloom visible au
## spray") : plein au moment du tir (`t_since_shot` = 0), fondu LINÉAIRE
## jusqu'à 0 en `duration` s — pur fondu (aucun déplacement/échelle animée),
## conforme à la règle "reduced motion: fades only" (design.md) : jamais
## désactivé par Settings.reduced_motion, juste un fondu comme le reste du
## HUD. Ne modifie PAS l'écart réel du réticule (`crosshair_gap_px`) : rend le
## spray visible sans fausser la dispersion affichée.
static func crosshair_bloom_alpha(t_since_shot: float, duration: float) -> float:
	if t_since_shot <= 0.0:
		return 1.0
	if duration <= 0.0 or t_since_shot >= duration:
		return 0.0
	return 1.0 - t_since_shot / duration

## Sang-froid (Verrou, AGT-08, docs/research/10_ammo_kits_input.md §3.3) :
## « immobile ou accroupi, il vise plus juste ». Vrai après `threshold` s
## SOUTENUES sous `speed_limit` (un joueur qui vient tout juste de s'arrêter
## n'en bénéficie pas encore — l'immobilité doit tenir), ou IMMÉDIATEMENT s'il
## est accroupi (choix délibéré du joueur, pas un état transitoire à filtrer).
## Fonction PURE (aucun accès joueur) : `time_still`/`speed` sont fournis par
## l'appelant — voir scripts/agents/passives/SangFroid.gd, qui calcule
## `time_still` PAR JOUEUR (cette ressource `Passive` est PARTAGÉE entre tous
## les joueurs de Verrou, donc aucun état par-joueur ne peut vivre ici).
static func is_steady(time_still: float, speed: float, crouching: bool,
		threshold: float = 0.4, speed_limit: float = 0.5) -> bool:
	if crouching:
		return true
	return time_still >= threshold and speed < speed_limit

## Multiplicateur de dispersion de Sang-froid (0.7 = -30 %) quand `is_steady`,
## sinon neutre (1.0) — consommé par `total_spread_deg` (`passive_mult`).
static func steady_spread_mult(time_still: float, speed: float, crouching: bool,
		threshold: float = 0.4, speed_limit: float = 0.5, mult: float = 0.7) -> float:
	return mult if is_steady(time_still, speed, crouching, threshold, speed_limit) else 1.0

## Multiplicateur de recul VERTICAL de Sang-froid (0.8 = -20 %), même
## condition que `steady_spread_mult` — consommé par `recoil_for_shot`
## (`recoil_mult`).
static func steady_recoil_mult(time_still: float, speed: float, crouching: bool,
		threshold: float = 0.4, speed_limit: float = 0.5, mult: float = 0.8) -> float:
	return mult if is_steady(time_still, speed, crouching, threshold, speed_limit) else 1.0
