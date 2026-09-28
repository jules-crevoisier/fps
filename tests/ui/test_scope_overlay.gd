## test_scope_overlay.gd
## Spec (tâche "quatre armes", 2026-09-28, Aiguille) : `ScopeOverlay.is_fully_scoped`
## est la SEULE fonction pure de ce fichier (le reste — shader/anneau
## d'encre/croix — n'est vérifiable qu'à l'écran, voir les captures de la
## tâche) : décide quand montrer l'habillage plein écran de la lunette,
## masquer le réticule normal et le viewmodel (`GameHUD._update_scope`/
## `ViewModel._process_arms`/`_process_gloves`).
extends GdUnitTestSuite


func test_not_fully_scoped_when_weapon_has_no_scope() -> void:
	assert_bool(ScopeOverlay.is_fully_scoped(false, true, 1.0)).is_false()


func test_not_fully_scoped_when_not_aiming() -> void:
	assert_bool(ScopeOverlay.is_fully_scoped(true, false, 1.0)).is_false()


func test_not_fully_scoped_mid_ads_transition() -> void:
	assert_bool(ScopeOverlay.is_fully_scoped(true, true, 0.5)).append_failure_message(
		"le cercle de lunette ne doit PAS apparaître avant la fin de la transition ADS"
	).is_false()


func test_fully_scoped_once_ads_progress_reaches_threshold() -> void:
	assert_bool(ScopeOverlay.is_fully_scoped(true, true, 1.0)).is_true()
	assert_bool(ScopeOverlay.is_fully_scoped(true, true, 0.999)).is_true()


func test_custom_threshold_is_respected() -> void:
	assert_bool(ScopeOverlay.is_fully_scoped(true, true, 0.8, 0.5)).is_true()
	assert_bool(ScopeOverlay.is_fully_scoped(true, true, 0.3, 0.5)).is_false()
