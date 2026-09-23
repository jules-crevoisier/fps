## test_rate_limiter.gd
## Spec (contract-p0.md, RateLimiter): token bucket. Starts full. Refill =
## min(burst, tokens + (now-last)*rate), no refill if now < last, cost taken
## only if available.
extends GdUnitTestSuite


func test_starts_full_allows_burst_worth_of_takes() -> void:
	var rl := RateLimiter.new(5.0, 3.0)
	assert_bool(rl.try_take(0.0)).is_true()
	assert_bool(rl.try_take(0.0)).is_true()
	assert_bool(rl.try_take(0.0)).is_true()
	# bucket exhausted, no time passed -> no refill
	assert_bool(rl.try_take(0.0)).is_false()


func test_refill_over_time_allows_additional_take() -> void:
	var rl := RateLimiter.new(5.0, 3.0)
	rl.try_take(0.0)
	rl.try_take(0.0)
	rl.try_take(0.0)
	# 0.2s later at 5/s -> +1.0 token
	assert_bool(rl.try_take(0.2)).is_true()
	# no additional time elapsed since last take -> refused
	assert_bool(rl.try_take(0.2)).is_false()


func test_refill_caps_at_burst() -> void:
	var rl := RateLimiter.new(100.0, 2.0)
	# huge elapsed time must not overfill beyond burst
	assert_bool(rl.try_take(1000.0)).is_true()
	assert_bool(rl.try_take(1000.0)).is_true()
	assert_bool(rl.try_take(1000.0)).is_false()


func test_no_refill_when_time_goes_backwards() -> void:
	var rl := RateLimiter.new(10.0, 2.0)
	assert_bool(rl.try_take(5.0)).is_true()
	# 1 token left; time goes backwards -> must not refill
	assert_bool(rl.try_take(2.0, 2.0)).is_false()
	# the remaining single token is still available at cost 1
	assert_bool(rl.try_take(2.0, 1.0)).is_true()


func test_cost_greater_than_one() -> void:
	var rl := RateLimiter.new(1.0, 5.0)
	assert_bool(rl.try_take(0.0, 3.0)).is_true()
	# 2 tokens left, cost 3 -> refused
	assert_bool(rl.try_take(0.0, 3.0)).is_false()
	# 2 tokens left, cost 2 -> ok
	assert_bool(rl.try_take(0.0, 2.0)).is_true()
