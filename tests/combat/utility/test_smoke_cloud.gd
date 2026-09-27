## test_smoke_cloud.gd
## Spec (contrat lead 2026-09-27, "smoke must BLOCK VISION — critical
## gameplay bug") : le nuage remplace les sphères translucides par un dôme de
## 16-22 puffs OPAQUES (ToonStyle, jamais de transparence -- c'est justement
## la transparence qui laissait l'ennemi visible au travers). Ce fichier ne
## peut pas vérifier l'ABSENCE d'interstice visuel (il faudrait un rendu réel,
## voir la capture d'écran manuelle v2_d_smoke_outside.png du contrat) : il
## vérifie seulement ces propriétés structurelles, jamais affaiblies par un
## test qui se contenterait de refléter l'implémentation.
extends GdUnitTestSuite

var _next_offset_index := 0


func _offset() -> Vector3:
	var o := Vector3(float(_next_offset_index) * 200.0, 0.0, 0.0)
	_next_offset_index += 1
	return o


func _cfg() -> UtilityConfig:
	return UtilityDatabase.get_by_id(UtilityDatabase.SMOKE)


func _spawn_cloud(pos: Vector3) -> SmokeCloud:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	SmokeCloud.spawn_local(pos, _cfg(), false, root)
	return root.get_child(0) as SmokeCloud


func _puffs_of(cloud: SmokeCloud) -> Array:
	var out: Array = []
	for child in cloud.get_children():
		if child is MeshInstance3D:
			out.append(child)
	return out


func test_puff_count_within_contract_range() -> void:
	var cloud := _spawn_cloud(_offset())
	var count := _puffs_of(cloud).size()
	# Contrat révisé par le lead (revue 2026-09-27) : 24-30 puffs plus petits.
	assert_int(count).append_failure_message(
		"le dôme doit compter au moins 24 puffs (contrat lead)"
	).is_greater_equal(24)
	assert_int(count).append_failure_message(
		"le dôme doit compter au plus 30 puffs (contrat lead)"
	).is_less_equal(30)


func test_puffs_use_opaque_toon_material() -> void:
	var cloud := _spawn_cloud(_offset())
	for puff in _puffs_of(cloud):
		assert_object(puff.material_override).append_failure_message(
			"chaque puff doit avoir un matériau shader OPAQUE (smoke_puff.gdshader) -- jamais de sphère alpha translucide"
		).is_instanceof(ShaderMaterial)


func test_puffs_start_at_zero_scale_before_any_growth_tick() -> void:
	var cloud := _spawn_cloud(_offset())
	for puff in _puffs_of(cloud):
		var mi := puff as MeshInstance3D
		assert_vector(mi.scale).append_failure_message(
			"un puff doit démarrer à l'échelle 0 au point de détonation (contrat : ease-out vers son emplacement)"
		).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)


func test_puffs_reach_a_visible_scale_after_growth_window() -> void:
	var cloud := _spawn_cloud(_offset())
	var cfg := _cfg()
	# Avance au-delà de la croissance + la plus longue gigue de départ possible
	# (STAGGER_GROW_MAX_S) pour que TOUS les puffs aient fini de pousser.
	var settle_s: float = cfg.smoke_grow_seconds + 0.35
	var steps := int(settle_s / (1.0 / 60.0)) + 1
	for i in steps:
		cloud._process(1.0 / 60.0)
	for puff in _puffs_of(cloud):
		var mi := puff as MeshInstance3D
		assert_float(mi.scale.x).append_failure_message(
			"un puff doit avoir une échelle visible une fois la fenêtre de croissance passée"
		).is_greater(0.5)


## Revue lead 2026-09-27 : le nuage est un dôme POSÉ au sol (la grenade repose
## au sol) -- un puff sous le sol n'apparaissait que comme une ellipse plate.
func test_puffs_sit_above_the_ground_once_grown() -> void:
	var cloud := _spawn_cloud(_offset())
	var cfg := _cfg()
	var steps := int((cfg.smoke_grow_seconds + 0.35) / (1.0 / 60.0)) + 1
	for i in steps:
		cloud._process(1.0 / 60.0)
	for puff in _puffs_of(cloud):
		var mi := puff as MeshInstance3D
		assert_float(mi.position.y).append_failure_message(
			"chaque puff doit être centré au-dessus du point de détonation (sol)"
		).is_greater_equal(SmokeCloud.PUFF_HEIGHT_MIN - 0.01)


## Le shader des bouffées ne doit jamais écrire ALPHA : une seule transparence et
## l'ennemi redevient visible au travers du fumigène.
func test_puff_shader_never_writes_alpha() -> void:
	var cloud := _spawn_cloud(_offset())
	var puffs := _puffs_of(cloud)
	assert_int(puffs.size()).is_greater(0)
	var mat := (puffs[0] as MeshInstance3D).material_override as ShaderMaterial
	assert_object(mat).is_not_null()
	assert_str(mat.shader.code).not_contains("ALPHA")


# ======================================================================
#  Cache plein écran local (bug corrigé 2026-09-27, "lingers after leaving the
#  smoke") : plus AUCUN critère de distance au centre du nuage -- le cache
#  n'est actif QUE dans la sphère COURANTE d'un puff réel. `camera_inside_puff`
#  est une fonction PURE (voir SmokeCloud.gd), testée directement ici, sans
#  passer par un vrai SmokeCloud/caméra locale.
# ======================================================================

func test_camera_inside_a_puffs_current_sphere_is_on() -> void:
	var puff_pos := Vector3(1.0, 1.0, 0.0)
	var radius := 2.0
	var cam := puff_pos + Vector3(0.5, 0.0, 0.0)  # 0.5 m du centre du puff, bien dans radius*0.95.
	assert_bool(SmokeCloud.camera_inside_puff(cam, puff_pos, radius)).append_failure_message(
		"la caméra DANS la sphère courante d'un puff doit activer le cache"
	).is_true()


func test_camera_just_outside_a_puffs_safety_margin_is_off() -> void:
	var puff_pos := Vector3.ZERO
	var radius := 1.0
	var cam := puff_pos + Vector3(0.96, 0.0, 0.0)  # > radius * 0.95 (marge de sécurité).
	assert_bool(SmokeCloud.camera_inside_puff(cam, puff_pos, radius)).is_false()


## Spec exacte du bug corrigé : une caméra à ~3 m du CENTRE de détonation
## (donc "dans les 4 m" de l'ancien critère supprimé) mais hors de TOUS les
## puffs réels (posés loin du centre, comme un dôme réel) ne doit JAMAIS
## activer le cache.
func test_camera_outside_every_puff_even_within_4m_of_the_detonation_centre_is_off() -> void:
	var puffs := [
		{"pos": Vector3(3.5, 2.0, 0.0), "radius": 1.5},
		{"pos": Vector3(-3.0, 1.5, 2.0), "radius": 1.4},
	]
	var cam := Vector3(0.0, 0.1, 0.0)  # à l'origine (le "centre"), 3-3.6 m de chaque puff.
	for p in puffs:
		assert_bool(SmokeCloud.camera_inside_puff(cam, p["pos"], p["radius"])).append_failure_message(
			"la caméra hors de CE puff (même proche du centre de détonation) ne doit jamais activer le cache"
		).is_false()


func test_overlay_fade_in_and_fade_out_durations_differ() -> void:
	assert_float(SmokeCloud.OVERLAY_FADE_OUT_S).append_failure_message(
		"le fondu de SORTIE doit être plus rapide (0.1 s) que l'entrée (0.15 s)"
	).is_less(SmokeCloud.OVERLAY_FADE_S)
	assert_float(SmokeCloud.OVERLAY_FADE_S).is_equal_approx(0.15, 0.001)
	assert_float(SmokeCloud.OVERLAY_FADE_OUT_S).is_equal_approx(0.1, 0.001)
