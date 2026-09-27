## GrenadeAudio.gd
## Logique PURE du son des grenades (tâche "son", 2026-09-27, point 5) :
## volume du rebond selon la vitesse d'impact, anti-rafale des rebonds
## rapprochés (un objet qui roule peut toucher le sol plusieurs fois par
## seconde en se stabilisant), et courbe d'assourdissement (lowpass) du
## joueur ébloui — plein étouffement pendant tout l'éblouissement
## (`FlashMath.blind_duration_for_target`), puis retour LINÉAIRE à
## l'ouverture sur `FlashMath.RECOVERY_S` (même fenêtre que le fondu de
## l'écran blanc, GameHUD — le monde redevient net en même temps que la vue).
class_name GrenadeAudio
extends RefCounted

## Coupure (Hz) pleinement étouffée / pleinement ouverte du lowpass appliqué
## aux bus SFX+Shots pendant l'éblouissement local (contrat : "muffle the world").
const MUFFLED_CUTOFF_HZ := 500.0
const OPEN_CUTOFF_HZ := 20000.0
## Intervalle mini (s) entre deux sons de rebond — un objet qui se stabilise
## en fin de course peut rebondir plusieurs fois par frame de simulation
## physique sans que chaque contact mérite son propre son.
const MIN_BOUNCE_INTERVAL_S := 0.08

## Vitesse d'impact (m/s, norme de la vélocité juste AVANT le rebond,
## UtilityIntegrator.step) -> volume (dB, additif pour `Audio.play_at`) —
## interpolation linéaire bornée, un impact mou reste audible mais discret,
## un impact franc (chute d'un toit) sonne plein volume.
static func bounce_volume_db(speed: float, min_speed: float = 0.5, max_speed: float = 10.0,
		min_db: float = -18.0, max_db: float = 0.0) -> float:
	if max_speed <= min_speed:
		return max_db
	var t := clampf((speed - min_speed) / (max_speed - min_speed), 0.0, 1.0)
	return lerpf(min_db, max_db, t)

## Secondes écoulées depuis le DERNIER son de rebond joué (par cette même
## grenade) -> peut-on en jouer un nouveau maintenant ?
static func can_play_bounce(elapsed_since_last: float, min_interval_s: float = MIN_BOUNCE_INTERVAL_S) -> bool:
	return elapsed_since_last >= min_interval_s

## Coupure (Hz) du lowpass des bus SFX/Shots pour le joueur ébloui LOCAL, à
## `elapsed` secondes depuis le début de l'éblouissement plein écran :
## totalement étouffé tant que `elapsed < blind_duration`, puis un fondu
## LINÉAIRE vers `OPEN_CUTOFF_HZ` sur `recovery_s` (même fenêtre que le fondu
## visuel, voir docstring de fichier) — `blind_duration <= 0` : jamais
## assourdi (pas d'éblouissement en cours).
static func muffle_cutoff_hz(elapsed: float, blind_duration: float, recovery_s: float,
		muffled_hz: float = MUFFLED_CUTOFF_HZ, open_hz: float = OPEN_CUTOFF_HZ) -> float:
	if blind_duration <= 0.0 or elapsed >= blind_duration + recovery_s:
		return open_hz
	if elapsed < blind_duration:
		return muffled_hz
	if recovery_s <= 0.0:
		return open_hz
	var t := clampf((elapsed - blind_duration) / recovery_s, 0.0, 1.0)
	return lerpf(muffled_hz, open_hz, t)
