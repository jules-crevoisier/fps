## JoinToken.gd
## Jeton de connexion HMAC-SHA256 (Godot `Crypto.hmac_digest`, voir docs
## Godot 4.7 classe Crypto) — lie un joueur (`player_id`, identifiant opaque
## fourni par le service de matchmaking externe, PAS l'id de pair ENet qui
## n'est connu qu'après connexion) à une partie (`match_id`) sous un secret
## partagé (env `MATCH_TOKEN_SECRET` — voir ServerConfig/ServerBoot). N'exige
## rien si le serveur n'a pas de secret configuré (LAN/host, voir
## NetworkManager) : le jeton est un mécanisme OPTIONNEL. Pur, testable sans
## réseau (tests/networking/test_join_token.gd).
class_name JoinToken
extends RefCounted

## Jeton hexadécimal (HMAC-SHA256 de "match_id:player_id" sous `secret`).
## Nommé `issue` (pas `sign`) : `sign` collisionne avec la fonction globale
## GDScript `@GlobalScope.sign(x)` et empêche la compilation de la classe.
static func issue(secret: String, match_id: String, player_id: String) -> String:
	var mac := Crypto.new().hmac_digest(
		HashingContext.HASH_SHA256, secret.to_utf8_buffer(), _message(match_id, player_id))
	return mac.hex_encode()

## Vérifie `token` pour (`match_id`, `player_id`) sous `secret`. Toujours faux
## si `secret` ou `token` est vide (jamais de jeton "vide accepté").
static func verify(secret: String, match_id: String, player_id: String, token: String) -> bool:
	if secret == "" or token == "":
		return false
	return _constant_time_eq(issue(secret, match_id, player_id), token)

static func _message(match_id: String, player_id: String) -> PackedByteArray:
	return ("%s:%s" % [match_id, player_id]).to_utf8_buffer()

## Comparaison en temps constant sur la LONGUEUR COMMUNE (limite l'exploitation
## d'un canal auxiliaire par mesure de temps ; la longueur du jeton elle-même
## n'est pas secrète, seul son contenu l'est).
static func _constant_time_eq(a: String, b: String) -> bool:
	var ba := a.to_utf8_buffer()
	var bb := b.to_utf8_buffer()
	if ba.size() != bb.size():
		return false
	var diff := 0
	for i in ba.size():
		diff |= ba[i] ^ bb[i]
	return diff == 0
