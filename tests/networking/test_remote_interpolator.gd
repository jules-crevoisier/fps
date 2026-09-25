## test_remote_interpolator.gd
## Spec GF-02 (docs/research/01_game_feel.md §5) : les pairs distants rendent
## position/rotation interpolées entre les deux derniers instantanés reçus,
## avec un délai fixe réglable (défaut 2 ticks @ 60 Hz = 33 ms), exposé pour
## GF-01. Critère principal : snapshots à 60 Hz d'un mouvement rectiligne à
## 8 m/s avec 20 % de gigue -> écart max rendu vs trajectoire vraie < 5 cm,
## aucun saut arrière.
extends GdUnitTestSuite


func test_default_delay_is_two_ticks_at_60hz() -> void:
	assert_int(RemoteInterpolator.DEFAULT_DELAY_TICKS).is_equal(2)
	assert_float(RemoteInterpolator.DEFAULT_TICK_RATE).is_equal_approx(60.0, 0.001)
	var interp := RemoteInterpolator.new()
	assert_float(interp.delay_seconds()).is_equal_approx(2.0 / 60.0, 0.0001)


func test_delay_is_adjustable() -> void:
	# Critère GF-02 : « le délai est exposé (réglable) » — GF-01 doit pouvoir
	# le lire/l'ajuster sans dépendre d'une constante figée.
	var interp := RemoteInterpolator.new()
	interp.delay_ticks = 4
	interp.tick_rate = 30.0
	assert_float(interp.delay_seconds()).is_equal_approx(4.0 / 30.0, 0.0001)


func test_sample_without_any_snapshot_returns_origin() -> void:
	var interp := RemoteInterpolator.new()
	var r := interp.sample(0.0)
	assert_vector(r["position"]).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)
	assert_int(interp.snapshot_count()).is_equal(0)


func test_sample_holds_on_single_snapshot_without_extrapolating() -> void:
	var interp := RemoteInterpolator.new()
	interp.push_snapshot(1.0, Vector3(5, 0, 0), Vector3.ZERO)
	# Avant ET après l'unique instantané connu : on FIGE dessus (pas
	# d'extrapolation), aussi bien en amont qu'en aval.
	assert_vector(interp.sample(0.0)["position"]).is_equal_approx(Vector3(5, 0, 0), Vector3.ONE * 0.001)
	assert_vector(interp.sample(5.0)["position"]).is_equal_approx(Vector3(5, 0, 0), Vector3.ONE * 0.001)


func test_sample_interpolates_linearly_between_two_snapshots() -> void:
	var interp := RemoteInterpolator.new()
	interp.push_snapshot(0.0, Vector3(0, 0, 0), Vector3.ZERO)
	interp.push_snapshot(1.0, Vector3(10, 0, 0), Vector3.ZERO)
	assert_vector(interp.sample(0.25)["position"]).is_equal_approx(Vector3(2.5, 0, 0), Vector3.ONE * 0.001)
	assert_vector(interp.sample(0.75)["position"]).is_equal_approx(Vector3(7.5, 0, 0), Vector3.ONE * 0.001)
	assert_vector(interp.sample(0.5)["position"]).is_equal_approx(Vector3(5.0, 0, 0), Vector3.ONE * 0.001)


func test_sample_interpolates_rotation_by_shortest_path() -> void:
	# Rotation qui traverse la coupure +-PI : un lerp naïf passerait par 0
	# (le long chemin) ; lerp_angle doit passer par +-PI (le court chemin).
	var interp := RemoteInterpolator.new()
	interp.push_snapshot(0.0, Vector3.ZERO, Vector3(0, PI - 0.1, 0))
	interp.push_snapshot(1.0, Vector3.ZERO, Vector3(0, -PI + 0.1, 0))
	var mid_y: float = interp.sample(0.5)["rotation"].y
	assert_float(absf(absf(mid_y) - PI)).is_less(0.05)


func test_push_snapshot_ignores_duplicate_or_out_of_order_timestamps() -> void:
	var interp := RemoteInterpolator.new()
	interp.push_snapshot(1.0, Vector3(10, 0, 0), Vector3.ZERO)
	# Doublon (même horodatage) : ignoré.
	interp.push_snapshot(1.0, Vector3(999, 0, 0), Vector3.ZERO)
	# Paquet en retard, réordonné par UDP (horodatage plus ancien que le
	# dernier connu) : ignoré, sinon `sample` pourrait reculer.
	interp.push_snapshot(0.5, Vector3(-999, 0, 0), Vector3.ZERO)
	assert_int(interp.snapshot_count()).is_equal(1)
	assert_vector(interp.sample(0.0)["position"]).is_equal_approx(Vector3(10, 0, 0), Vector3.ONE * 0.001)


func test_out_of_order_arrival_never_produces_backward_output() -> void:
	# Un instantané "du futur" (t=2) arrive AVANT celui "du présent" (t=1) —
	# réordonnancement UDP classique sous gigue. Le tampon garde t=2 et rejette
	# le t=1 tardif (déjà couvert par le test précédent) : en échantillonnant
	# à des `render_time` strictement croissants, la position rendue ne doit
	# jamais reculer le long de l'axe de déplacement.
	var interp := RemoteInterpolator.new()
	interp.push_snapshot(0.0, Vector3(0, 0, 0), Vector3.ZERO)
	interp.push_snapshot(2.0, Vector3(20, 0, 0), Vector3.ZERO)
	interp.push_snapshot(1.0, Vector3(10, 0, 0), Vector3.ZERO)  # tardif -> ignoré
	assert_int(interp.snapshot_count()).is_equal(2)
	var prev_x := -INF
	var t := 0.0
	while t <= 2.0:
		var x: float = interp.sample(t)["position"].x
		assert_bool(x >= prev_x - 0.0001).is_true()
		prev_x = x
		t += 0.05


func test_reset_clears_buffer() -> void:
	var interp := RemoteInterpolator.new()
	interp.push_snapshot(0.0, Vector3(1, 0, 0), Vector3.ZERO)
	interp.push_snapshot(1.0, Vector3(2, 0, 0), Vector3.ZERO)
	interp.reset()
	assert_int(interp.snapshot_count()).is_equal(0)
	assert_vector(interp.sample(0.5)["position"]).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)


func test_linear_motion_at_8ms_with_jitter_stays_within_5cm_and_never_jumps_backward() -> void:
	# Critère d'acceptation GF-02 : snapshots à 60 Hz d'un mouvement
	# rectiligne à 8 m/s avec 20% de gigue -> écart max rendu vs trajectoire
	# vraie < 5 cm, aucun saut arrière.
	var interp := RemoteInterpolator.new()
	var speed := 8.0
	var tick_dt := 1.0 / interp.tick_rate
	var duration := 3.0

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260924  # déterministe : le test ne doit jamais flaker

	# Chaque instantané est horodaté par sa vraie date d'ÉMISSION (`t`), mais
	# arrive avec une gigue de +-20% d'un tick (jitter réseau) : on modélise
	# ça en calculant un ordre d'ARRIVÉE différent de l'ordre d'émission.
	var events: Array = []
	var k := 0
	while k * tick_dt <= duration:
		var send_t: float = k * tick_dt
		var jitter: float = rng.randf_range(-0.2, 0.2) * tick_dt
		events.append({"arrival": send_t + jitter, "t": send_t, "pos": Vector3(speed * send_t, 0, 0)})
		k += 1
	events.sort_custom(func(a, b): return a["arrival"] < b["arrival"])

	var max_error := 0.0
	var prev_x := -INF
	var no_backward_jump := true
	var event_i := 0
	var render_dt := 1.0 / 240.0
	var render_t := 0.0
	# On s'arrête avant la fin du flux pour toujours avoir un instantané futur
	# disponible au-delà de `render_t - delay` (sinon on testerait le
	# "figeage" de fin de flux, couvert par un autre test).
	while render_t <= duration - tick_dt * 2.0:
		while event_i < events.size() and events[event_i]["arrival"] <= render_t:
			var ev: Dictionary = events[event_i]
			interp.push_snapshot(ev["t"], ev["pos"], Vector3.ZERO)
			event_i += 1
		var sample_time: float = render_t - interp.delay_seconds()
		if sample_time >= 0.0:
			var result: Dictionary = interp.sample(sample_time)
			var rendered_x: float = result["position"].x
			var true_x: float = speed * sample_time
			max_error = max(max_error, absf(rendered_x - true_x))
			if rendered_x < prev_x - 0.0001:
				no_backward_jump = false
			prev_x = rendered_x
		render_t += render_dt

	assert_float(max_error).append_failure_message(
		"écart max rendu vs trajectoire vraie = %.4f m (attendu < 0.05 m)" % max_error
	).is_less(0.05)
	assert_bool(no_backward_jump).is_true()
