## NetAddress.gd
## Validation pure d'une adresse IP saisie dans le panneau « Rejoindre / héberger »
## de l'accueil (reports/ui/mockups/home.html) — jamais de résolution réseau ici,
## juste de quoi activer/désactiver le bouton JOIN avant d'appeler
## MatchLauncher.join(). Accepte les quatre octets décimaux d'une IPv4 ainsi que
## "localhost" (hébergement/test sur la même machine). Pure, testable sans arbre
## de scène (tests/ui/menu/test_net_address.gd).
class_name NetAddress
extends RefCounted

const DEFAULT_IP := "127.0.0.1"

static func is_valid_ip(text: String) -> bool:
	var t := text.strip_edges()
	if t == "":
		return false
	if t == "localhost":
		return true
	var parts := t.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if part.is_empty() or not part.is_valid_int():
			return false
		var n := int(part)
		if n < 0 or n > 255:
			return false
	return true
