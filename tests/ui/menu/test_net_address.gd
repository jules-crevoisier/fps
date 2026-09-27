## test_net_address.gd
## Spec (brief lead 2026-09-27, panneau "Rejoindre / héberger") : valide une
## IPv4 (4 octets 0-255) ou "localhost" avant d'activer le bouton JOIN.
extends GdUnitTestSuite

const NetAddress := preload("res://scripts/ui/menu/NetAddress.gd")


func test_default_ip_is_valid() -> void:
	assert_bool(NetAddress.is_valid_ip(NetAddress.DEFAULT_IP)).is_true()


func test_localhost_is_valid() -> void:
	assert_bool(NetAddress.is_valid_ip("localhost")).is_true()


func test_valid_ipv4_addresses() -> void:
	assert_bool(NetAddress.is_valid_ip("192.168.1.42")).is_true()
	assert_bool(NetAddress.is_valid_ip("0.0.0.0")).is_true()
	assert_bool(NetAddress.is_valid_ip("255.255.255.255")).is_true()


func test_strips_surrounding_whitespace() -> void:
	assert_bool(NetAddress.is_valid_ip("  127.0.0.1  ")).is_true()


func test_rejects_empty() -> void:
	assert_bool(NetAddress.is_valid_ip("")).is_false()
	assert_bool(NetAddress.is_valid_ip("   ")).is_false()


func test_rejects_wrong_octet_count() -> void:
	assert_bool(NetAddress.is_valid_ip("127.0.1")).is_false()
	assert_bool(NetAddress.is_valid_ip("127.0.0.0.1")).is_false()


func test_rejects_out_of_range_octet() -> void:
	assert_bool(NetAddress.is_valid_ip("256.0.0.1")).is_false()
	assert_bool(NetAddress.is_valid_ip("127.0.0.-1")).is_false()


func test_rejects_non_numeric() -> void:
	assert_bool(NetAddress.is_valid_ip("abc.def.ghi.jkl")).is_false()
	assert_bool(NetAddress.is_valid_ip("127.0.0.")).is_false()
