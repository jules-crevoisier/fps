## test_join_token.gd
## Spec (mission serveur dédié) : quand `MATCH_TOKEN_SECRET` est défini, un
## client doit présenter un jeton HMAC-SHA256 valide, lié à SON player_id et
## à la partie (match_id) en cours, sinon il est refusé (voir
## NetworkManager._server_auth_callback, docs/SERVER.md). `JoinToken` est la
## fonction pure de signature/vérification.
extends GdUnitTestSuite


func test_sign_then_verify_succeeds_for_the_same_inputs() -> void:
	var token := JoinToken.issue("s3cret", "match-1", "player-42")
	assert_bool(JoinToken.verify("s3cret", "match-1", "player-42", token)).is_true()


func test_sign_is_deterministic() -> void:
	var a := JoinToken.issue("s3cret", "match-1", "player-42")
	var b := JoinToken.issue("s3cret", "match-1", "player-42")
	assert_str(a).is_equal(b)


func test_sign_produces_a_non_empty_hex_string() -> void:
	var token := JoinToken.issue("s3cret", "match-1", "player-42")
	assert_str(token).is_not_empty()
	assert_bool(token.is_valid_hex_number()).is_true()


func test_verify_fails_for_wrong_secret() -> void:
	var token := JoinToken.issue("s3cret", "match-1", "player-42")
	assert_bool(JoinToken.verify("autre-secret", "match-1", "player-42", token)).is_false()


func test_verify_fails_for_wrong_match_id() -> void:
	var token := JoinToken.issue("s3cret", "match-1", "player-42")
	assert_bool(JoinToken.verify("s3cret", "match-2", "player-42", token)).is_false()


func test_verify_fails_for_wrong_player_id() -> void:
	var token := JoinToken.issue("s3cret", "match-1", "player-42")
	assert_bool(JoinToken.verify("s3cret", "match-1", "player-43", token)).is_false()


func test_verify_fails_for_tampered_token() -> void:
	var token := JoinToken.issue("s3cret", "match-1", "player-42")
	var tampered := token.substr(0, token.length() - 1) + ("0" if token[token.length() - 1] != "0" else "1")
	assert_bool(JoinToken.verify("s3cret", "match-1", "player-42", tampered)).is_false()


func test_verify_fails_when_secret_is_empty() -> void:
	# Un serveur sans secret n'exige pas de jeton (voir ServerConfig) — mais
	# JoinToken.verify lui-même refuse toujours un secret vide, sans
	# exception : c'est NetworkManager qui décide de ne pas l'appeler.
	var token := JoinToken.issue("s3cret", "match-1", "player-42")
	assert_bool(JoinToken.verify("", "match-1", "player-42", token)).is_false()


func test_verify_fails_when_token_is_empty() -> void:
	assert_bool(JoinToken.verify("s3cret", "match-1", "player-42", "")).is_false()
