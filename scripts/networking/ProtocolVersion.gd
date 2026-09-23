## ProtocolVersion.gd
## Version du PROTOCOLE réseau (pas la version du jeu/build) — à incrémenter
## à chaque changement de format des messages RPC/handshake. Un client compilé
## avec une version différente est rejeté à la connexion par le serveur dédié
## (voir NetworkManager, handshake d'authentification). Pur, testable sans
## scène (tests/networking/test_protocol_version.gd).
class_name ProtocolVersion
extends RefCounted

const CURRENT := "1.0.0"

## Compatibilité stricte (pas de tolérance partielle : un mineur/patch
## différent peut avoir changé la forme d'un message RPC).
static func is_compatible(client_version: String) -> bool:
	return client_version == CURRENT

## Compare deux versions "x.y.z" : -1 (a < b), 0 (égales), 1 (a > b). Composant
## manquant ou non numérique compté comme 0 — utile pour le tri/diagnostic en
## journal ; la compatibilité de connexion, elle, passe par `is_compatible`.
static func compare(a: String, b: String) -> int:
	var pa := _parts(a)
	var pb := _parts(b)
	for i in 3:
		if pa[i] != pb[i]:
			return -1 if pa[i] < pb[i] else 1
	return 0

static func _parts(v: String) -> Array:
	var raw := v.split(".")
	var out := [0, 0, 0]
	for i in mini(3, raw.size()):
		var s := String(raw[i])
		out[i] = s.to_int() if s.is_valid_int() else 0
	return out
