## SettingsFormat.gd
## Formatage d'affichage PUR pour les curseurs de SettingsPanel.gd
## (reports/ui/mockups/settings.html) — jamais de bornage/persistance ici : ces
## deux responsabilités restent dans Settings.gd (clamp_mouse_sensitivity,
## clamp_fov, clamp_ads_sensitivity_multiplier, save_all…), SOURCE UNIQUE des
## règles de jeu. Ce fichier ne fait que transformer une valeur déjà valide en
## texte FR (virgule décimale) et en remplissage de curseur (0..1). Pure,
## testable sans scène (tests/ui/menu/test_settings_format.gd).
class_name SettingsFormat
extends RefCounted

## Plage AFFICHÉE du curseur de sensibilité — même borne que
## Settings.clamp_mouse_sensitivity (voir sa doc : « Même plage que le slider
## Options »).
const SENSITIVITY_MIN := 0.0005
const SENSITIVITY_MAX := 0.01
## Plage AFFICHÉE du curseur de sensibilité ADS — Settings.clamp_ads_sensitivity_multiplier.
const ADS_MULT_MIN := 0.3
const ADS_MULT_MAX := 2.0
## Plage AFFICHÉE du curseur de FOV (UX-02, doc Settings.gd : « OptionsMenu._build_kb : 80..120 ») —
## Settings.clamp_fov autorise 70..120 (filet de sécurité plus large), le curseur reste 80..120.
const FOV_MIN := 80.0
const FOV_MAX := 120.0

## Remplissage 0..1 d'une valeur dans [min_v, max_v] — jamais hors bornes même
## si `value` dépasse la plage (curseur toujours dessinable).
static func percent(value: float, min_v: float, max_v: float) -> float:
	if max_v <= min_v:
		return 0.0
	return clampf((value - min_v) / (max_v - min_v), 0.0, 1.0)

## "1,00" — sensibilité relative à `reference` (Settings.MOUSE_SENSITIVITY_DEFAULT).
## TOUJOURS 2 décimales (jamais "1" pour la valeur par défaut, contrairement à
## `format_number`/`format_seconds` — un ratio de sensibilité reste un ratio,
## voir settings.html ".v" : "1,00", pas "1").
static func format_ratio(value: float, reference: float) -> String:
	if is_zero_approx(reference):
		return "0,00"
	return _fmt_fixed(value / reference, 2)

## "×0,85" — multiplicateur (sensibilité ADS), toujours 2 décimales.
static func format_multiplier(value: float) -> String:
	return "×%s" % _fmt_fixed(value, 2)

## "103°" — degrés entiers (FOV).
static func format_degrees(value: float) -> String:
	return "%d°" % int(round(value))

## "2,4 s" — secondes, 1 décimale (rechargement, amorces…). Réutilisé hors
## SettingsPanel (ArmoryFormat) pour la même convention d'écriture FR.
static func format_seconds(value: float, decimals: int = 1) -> String:
	return "%s s" % _fmtn(value, decimals)

## Nombre FR générique (virgule décimale, entier si quasi-entier) — réutilisé
## par ArmoryFormat.gd pour rester sur UNE seule règle d'écriture des nombres
## dans tout le salon.
static func format_number(v: float, decimals: int = 1) -> String:
	return _fmtn(v, decimals)

## Nombre FR à décimales FIXES (jamais raccourci) — "1,00", "0,85".
static func _fmt_fixed(v: float, decimals: int) -> String:
	return ("%.*f" % [decimals, v]).replace(".", ",")

## Nombre FR : entier sans décimale si `v` est (quasi) entier, sinon
## `decimals` chiffres après une VIRGULE (jamais un point).
static func _fmtn(v: float, decimals: int) -> String:
	var r := snappedf(v, pow(10.0, -decimals))
	if is_equal_approx(r, roundf(r)):
		return str(int(round(r)))
	return ("%.*f" % [decimals, r]).replace(".", ",")
