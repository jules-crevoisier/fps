## test_frame_stats.gd
## Spec (contract-p0.md, FrameStats): fixed-capacity ring buffer of frame times
## (ms) feeding avg fps, p99 frame time (nearest-rank) and the derived 1% low
## fps. Empty buffer reports zero for every getter.
extends GdUnitTestSuite


func test_empty_stats_return_zero() -> void:
	var stats := FrameStats.new()
	assert_int(stats.count()).is_equal(0)
	assert_float(stats.avg_fps()).is_equal_approx(0.0, 0.001)
	assert_float(stats.p99_ms()).is_equal_approx(0.0, 0.001)
	assert_float(stats.low_1pct_fps()).is_equal_approx(0.0, 0.001)


func test_avg_fps_computed_from_uniform_frame_times() -> void:
	var stats := FrameStats.new()
	for i in range(5):
		stats.add(10.0)
	assert_int(stats.count()).is_equal(5)
	assert_float(stats.avg_fps()).is_equal_approx(100.0, 0.001)


func test_avg_fps_computed_from_mixed_frame_times() -> void:
	var stats := FrameStats.new()
	stats.add(20.0)
	stats.add(10.0)
	# avg frame time = 15.0 ms -> avg fps = 1000/15
	assert_float(stats.avg_fps()).is_equal_approx(1000.0 / 15.0, 0.01)


func test_p99_ms_nearest_rank_and_derived_low_1pct_fps() -> void:
	var stats := FrameStats.new()
	for ms in range(1, 101):
		stats.add(float(ms))
	# nearest-rank p99 over 100 sorted samples 1..100 -> rank ceil(0.99*100)=99 -> 99.0 ms
	assert_float(stats.p99_ms()).is_equal_approx(99.0, 0.001)
	assert_float(stats.low_1pct_fps()).is_equal_approx(1000.0 / 99.0, 0.001)


func test_ring_buffer_overwrites_oldest_beyond_capacity() -> void:
	var stats := FrameStats.new(3)
	stats.add(1.0)
	stats.add(2.0)
	stats.add(3.0)
	stats.add(4.0)  # oldest (1.0) must be overwritten
	assert_int(stats.count()).is_equal(3)
	# remaining samples: 2, 3, 4 -> avg = 3.0 ms -> avg fps = 1000/3
	assert_float(stats.avg_fps()).is_equal_approx(1000.0 / 3.0, 0.01)
	# nearest-rank p99 over 3 samples -> rank ceil(0.99*3)=3 -> highest value = 4.0
	assert_float(stats.p99_ms()).is_equal_approx(4.0, 0.001)


func test_clear_resets_to_empty() -> void:
	var stats := FrameStats.new()
	stats.add(10.0)
	stats.add(20.0)
	stats.clear()
	assert_int(stats.count()).is_equal(0)
	assert_float(stats.avg_fps()).is_equal_approx(0.0, 0.001)
	assert_float(stats.p99_ms()).is_equal_approx(0.0, 0.001)
	assert_float(stats.low_1pct_fps()).is_equal_approx(0.0, 0.001)
