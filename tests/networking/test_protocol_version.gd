## test_protocol_version.gd
## Spec (mission serveur dédié, ServerBoot/NetworkManager) : le handshake de
## connexion rejette un client dont la version de protocole ne correspond pas
## exactement à celle du serveur (voir docs/SERVER.md). `ProtocolVersion` est
## la fonction pure qui porte cette règle.
extends GdUnitTestSuite


func test_current_version_is_compatible_with_itself() -> void:
	assert_bool(ProtocolVersion.is_compatible(ProtocolVersion.CURRENT)).is_true()


func test_different_version_is_incompatible() -> void:
	assert_bool(ProtocolVersion.is_compatible("0.9.0")).is_false()
	assert_bool(ProtocolVersion.is_compatible("1.0.1")).is_false()
	assert_bool(ProtocolVersion.is_compatible("2.0.0")).is_false()


func test_empty_or_garbage_version_is_incompatible() -> void:
	assert_bool(ProtocolVersion.is_compatible("")).is_false()
	assert_bool(ProtocolVersion.is_compatible("n'importe quoi")).is_false()


func test_compare_orders_semver_components() -> void:
	assert_int(ProtocolVersion.compare("1.0.0", "1.0.0")).is_equal(0)
	assert_int(ProtocolVersion.compare("1.0.0", "1.0.1")).is_equal(-1)
	assert_int(ProtocolVersion.compare("1.1.0", "1.0.9")).is_equal(1)
	assert_int(ProtocolVersion.compare("2.0.0", "1.9.9")).is_equal(1)


func test_compare_treats_missing_or_invalid_component_as_zero() -> void:
	assert_int(ProtocolVersion.compare("1.0", "1.0.0")).is_equal(0)
	assert_int(ProtocolVersion.compare("1.x.0", "1.0.0")).is_equal(0)
