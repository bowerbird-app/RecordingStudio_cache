# frozen_string_literal: true

require "test_helper"
require "active_support/cache"
require "active_support/testing/time_helpers"

class RateLimiterTest < Minitest::Test
  include ActiveSupport::Testing::TimeHelpers

  def setup
    RecordingStudioCache.reset_configuration!
    @memory = ActiveSupport::Cache::MemoryStore.new
    RecordingStudioCache.configuration.cache_store = @memory
  end

  def teardown
    travel_back
    RecordingStudioCache.reset_configuration!
  end

  def test_null_backend_always_allows
    5.times do
      result = RecordingStudioCache::RateLimiter.throttle(
        key: "anyone",
        limit: 1,
        period: 60,
        backend: :null
      )
      assert result.allowed?
      refute result.blocked?
      assert_nil result.retry_after
      assert_equal 0, result.count
    end
  end

  def test_rails_cache_allows_until_limit_then_blocks_with_retry_after
    limiter = RecordingStudioCache::RateLimiter.new(
      key: "ip:1.1.1.1",
      limit: 2,
      period: 60,
      backend: :rails_cache,
      store: @memory
    )

    first = limiter.throttle
    second = limiter.throttle
    third = limiter.throttle

    assert first.allowed?
    assert second.allowed?
    assert third.blocked?
    assert_equal 3, third.count
    assert_equal 2, third.limit
    assert_operator third.retry_after, :>, 0
    assert_operator third.retry_after, :<=, 60
  end

  def test_window_alias_matches_period
    result = RecordingStudioCache::RateLimiter.throttle(
      key: "alias",
      limit: 1,
      window: 30,
      backend: :rails_cache,
      store: @memory
    )
    assert result.allowed?
    assert_equal 30, result.period
  end

  def test_allow_predicate_matches_throttle
    opts = { key: "pred", limit: 1, period: 60, backend: :rails_cache, store: @memory }
    assert RecordingStudioCache::RateLimiter.allow?(**opts)
    refute RecordingStudioCache::RateLimiter.allow?(**opts)
  end

  def test_per_key_isolation
    shared = { limit: 1, period: 60, backend: :rails_cache, store: @memory }
    assert RecordingStudioCache::RateLimiter.allow?(key: "a", **shared)
    refute RecordingStudioCache::RateLimiter.allow?(key: "a", **shared)
    assert RecordingStudioCache::RateLimiter.allow?(key: "b", **shared)
  end

  def test_fixed_window_expires_and_resets
    travel_to Time.zone.parse("2026-10-13 12:00:00 UTC")

    opts = { key: "fixed", limit: 1, period: 60, backend: :rails_cache, store: @memory, strategy: :fixed }
    assert RecordingStudioCache::RateLimiter.allow?(**opts)
    refute RecordingStudioCache::RateLimiter.allow?(**opts)

    travel_to Time.zone.parse("2026-10-13 12:01:00 UTC")
    assert RecordingStudioCache::RateLimiter.allow?(**opts)
  end

  def test_fixed_window_uses_epoch_bucket_in_storage_key
    travel_to Time.zone.parse("2026-10-13 12:00:30 UTC")
    epoch = Time.zone.now.to_i
    period = 60
    bucket = epoch / period

    RecordingStudioCache::RateLimiter.throttle(
      key: "bucketed",
      limit: 5,
      period: period,
      backend: :rails_cache,
      store: @memory,
      strategy: :fixed,
      prefix: "rsc:rate"
    )

    expected = "rsc:rate:bucketed:#{bucket}"
    assert @memory.exist?(expected), "expected cache key #{expected}"

    travel_to Time.zone.parse("2026-10-13 12:01:30 UTC")
    next_bucket = Time.zone.now.to_i / period
    refute_equal bucket, next_bucket

    RecordingStudioCache::RateLimiter.throttle(
      key: "bucketed",
      limit: 5,
      period: period,
      backend: :rails_cache,
      store: @memory,
      strategy: :fixed,
      prefix: "rsc:rate"
    )
    assert @memory.exist?("rsc:rate:bucketed:#{next_bucket}")
  end

  def test_fixed_window_retry_after_is_seconds_until_next_bucket
    travel_to Time.zone.parse("2026-10-13 12:00:45 UTC")

    opts = { key: "retry", limit: 1, period: 60, backend: :rails_cache, store: @memory, strategy: :fixed }
    assert RecordingStudioCache::RateLimiter.allow?(**opts)
    blocked = RecordingStudioCache::RateLimiter.throttle(**opts)

    assert blocked.blocked?
    assert_equal 15, blocked.retry_after

    travel_to Time.zone.parse("2026-10-13 12:00:59 UTC")
    blocked_again = RecordingStudioCache::RateLimiter.throttle(**opts)
    assert blocked_again.blocked?
    assert_equal 1, blocked_again.retry_after
  end

  def test_ttl_strategy_blocks_until_key_expires
    travel_to Time.zone.parse("2026-10-13 12:00:00 UTC")

    opts = { key: "ttl", limit: 1, period: 30, backend: :rails_cache, store: @memory, strategy: :ttl }
    assert RecordingStudioCache::RateLimiter.allow?(**opts)
    refute RecordingStudioCache::RateLimiter.allow?(**opts)

    travel 29.seconds
    refute RecordingStudioCache::RateLimiter.allow?(**opts)

    travel 2.seconds
    assert RecordingStudioCache::RateLimiter.allow?(**opts)
  end

  def test_zero_limit_disables_throttling
    3.times do
      assert RecordingStudioCache::RateLimiter.allow?(
        key: "off",
        limit: 0,
        period: 60,
        backend: :rails_cache,
        store: @memory
      )
    end
  end

  def test_fail_closed_blocks_when_store_raises_connection_error
    broken = Object.new
    def broken.increment(*)
      raise Errno::ECONNREFUSED, "cache down"
    end

    open_result = RecordingStudioCache::RateLimiter.throttle(
      key: "err",
      limit: 1,
      period: 60,
      backend: :rails_cache,
      store: broken,
      fail_closed: false
    )
    assert open_result.allowed?

    closed_result = RecordingStudioCache::RateLimiter.throttle(
      key: "err",
      limit: 1,
      period: 60,
      backend: :rails_cache,
      store: broken,
      fail_closed: true
    )
    assert closed_result.blocked?
    assert_equal 60, closed_result.retry_after
  end

  def test_programming_errors_are_not_swallowed_by_fail_closed
    broken = Object.new
    def broken.increment(*)
      raise ArgumentError, "bad cache call"
    end

    assert_raises(ArgumentError) do
      RecordingStudioCache::RateLimiter.throttle(
        key: "err",
        limit: 1,
        period: 60,
        backend: :rails_cache,
        store: broken,
        fail_closed: true
      )
    end
  end

  def test_redis_backend_requires_eval_client
    error = assert_raises(ArgumentError) do
      RecordingStudioCache::RateLimiter.new(
        key: "x",
        limit: 1,
        period: 60,
        backend: :redis,
        redis: nil,
        fail_closed: true
      )
    end
    assert_match(/redis: client that responds to eval/, error.message)

    incr_only = Object.new
    def incr_only.incr(*) = 1

    error = assert_raises(ArgumentError) do
      RecordingStudioCache::RateLimiter.new(
        key: "x",
        limit: 1,
        period: 60,
        backend: :redis,
        redis: incr_only,
        fail_closed: true
      )
    end
    assert_match(/redis: client that responds to eval/, error.message)
  end

  def test_rescue_errors_standard_error_matches_sibling_gems
    broken = Object.new
    def broken.increment(*)
      raise "cache down"
    end

    assert_raises(RuntimeError) do
      RecordingStudioCache::RateLimiter.throttle(
        key: "narrow",
        limit: 1,
        period: 60,
        backend: :rails_cache,
        store: broken,
        fail_closed: true
      )
    end

    result = RecordingStudioCache::RateLimiter.throttle(
      key: "wide",
      limit: 1,
      period: 60,
      backend: :rails_cache,
      store: broken,
      fail_closed: true,
      rescue_errors: [StandardError]
    )
    assert result.blocked?
    assert_equal 60, result.retry_after
  end

  def test_redis_command_error_follows_fail_closed
    skip "redis gem not available" unless redis_base_error_available?

    broken = Object.new
    def broken.eval(*)
      raise Redis::CommandError, "ERR simulated command failure"
    end

    open_result = RecordingStudioCache::RateLimiter.throttle(
      key: "cmd",
      limit: 1,
      period: 60,
      backend: :redis,
      redis: broken,
      fail_closed: false
    )
    assert open_result.allowed?

    closed_result = RecordingStudioCache::RateLimiter.throttle(
      key: "cmd",
      limit: 1,
      period: 60,
      backend: :redis,
      redis: broken,
      fail_closed: true
    )
    assert closed_result.blocked?
    assert_equal 60, closed_result.retry_after
  end

  def test_redis_retry_after_uses_fake_redis_ttl
    travel_to Time.zone.parse("2026-10-13 12:00:00 UTC")
    redis = FakeRedis.new
    opts = {
      key: "retry-ttl",
      limit: 1,
      period: 45,
      backend: :redis,
      redis: redis,
      strategy: :ttl
    }

    assert RecordingStudioCache::RateLimiter.allow?(**opts)
    travel 10.seconds
    blocked = RecordingStudioCache::RateLimiter.throttle(**opts)

    assert blocked.blocked?
    assert_equal redis.ttl("rsc:rate:retry-ttl"), blocked.retry_after
    assert_equal 35, blocked.retry_after
  end

  def test_redis_expires_key_that_has_no_ttl
    redis = FakeRedis.new
    redis.seed_without_expiry("rsc:rate:orphan", 3)

    result = RecordingStudioCache::RateLimiter.throttle(
      key: "orphan",
      limit: 10,
      period: 60,
      backend: :redis,
      redis: redis,
      strategy: :ttl
    )

    assert result.allowed?
    assert_equal 4, result.count
    assert_equal 1, redis.expire_calls
    assert_operator redis.ttl("rsc:rate:orphan"), :>, 0
  end

  def test_redis_backend_with_fake_client
    redis = FakeRedis.new
    opts = { key: "r", limit: 2, period: 60, backend: :redis, redis: redis }

    assert RecordingStudioCache::RateLimiter.allow?(**opts)
    assert RecordingStudioCache::RateLimiter.allow?(**opts)
    result = RecordingStudioCache::RateLimiter.throttle(**opts)
    assert result.blocked?
    assert_equal 3, result.count
    assert_equal 1, redis.expire_calls
  end

  def test_redis_ttl_blocked_hits_do_not_extend_window_like_rails_cache
    travel_to Time.zone.parse("2026-10-13 12:00:00 UTC")
    redis = FakeRedis.new
    period = 3

    redis_opts = {
      key: "ttl-parity",
      limit: 1,
      period: period,
      backend: :redis,
      redis: redis,
      strategy: :ttl,
      prefix: "parity"
    }
    rails_opts = {
      key: "ttl-parity",
      limit: 1,
      period: period,
      backend: :rails_cache,
      store: @memory,
      strategy: :ttl,
      prefix: "parity"
    }

    redis_results = []
    rails_results = []

    [0, 2, 4].each do |offset|
      travel_to Time.zone.parse("2026-10-13 12:00:00 UTC") + offset.seconds
      redis_results << RecordingStudioCache::RateLimiter.allow?(**redis_opts)
      rails_results << RecordingStudioCache::RateLimiter.allow?(**rails_opts)
    end

    assert_equal [true, false, true], rails_results
    assert_equal [true, false, true], redis_results
    assert_equal rails_results, redis_results
    assert_equal 2, redis.expire_calls
  end

  def test_separator_and_storage_key_preserve_oauth_style_keys
    RecordingStudioCache::RateLimiter.throttle(
      key: "1.1.1.1",
      limit: 5,
      period: 60,
      backend: :rails_cache,
      store: @memory,
      strategy: :ttl,
      prefix: "recording_studio_oauth/register",
      separator: "/"
    )
    assert @memory.exist?("recording_studio_oauth/register/1.1.1.1")

    RecordingStudioCache::RateLimiter.throttle(
      storage_key: "recording_studio_oauth/register/2.2.2.2",
      limit: 5,
      period: 60,
      backend: :rails_cache,
      store: @memory,
      strategy: :ttl
    )
    assert @memory.exist?("recording_studio_oauth/register/2.2.2.2")
  end

  def test_storage_key_fixed_strategy_still_appends_bucket
    travel_to Time.zone.parse("2026-10-13 12:00:00 UTC")
    bucket = Time.zone.now.to_i / 60

    RecordingStudioCache::RateLimiter.throttle(
      storage_key: "custom/base",
      limit: 5,
      period: 60,
      backend: :rails_cache,
      store: @memory,
      strategy: :fixed,
      separator: "/"
    )
    assert @memory.exist?("custom/base/#{bucket}")
  end

  def test_memory_store_concurrent_increments_do_not_lose_counts
    limiter_opts = { key: "race", limit: 10_000, period: 60, backend: :rails_cache, store: @memory }
    threads = 8.times.map do
      Thread.new do
        25.times { RecordingStudioCache::RateLimiter.throttle(**limiter_opts) }
      end
    end
    threads.each(&:join)

    final = RecordingStudioCache::RateLimiter.throttle(**limiter_opts)
    assert_equal 201, final.count
  end

  def test_rejects_unknown_backend_and_blank_key
    assert_raises(ArgumentError) do
      RecordingStudioCache::RateLimiter.new(key: "x", limit: 1, period: 1, backend: :memcached)
    end
    assert_raises(ArgumentError) do
      RecordingStudioCache::RateLimiter.new(key: " ", limit: 1, period: 1)
    end
    assert_raises(ArgumentError) do
      RecordingStudioCache::RateLimiter.new(key: "x", limit: 1, period: 0)
    end
  end

  def test_otp_style_cooldown_via_ttl_limit_one
    travel_to Time.zone.parse("2026-10-13 12:00:00 UTC")
    opts = {
      key: "otp:resend:user-1",
      limit: 1,
      period: 45,
      backend: :rails_cache,
      store: @memory,
      strategy: :ttl,
      prefix: "recording_studio_user:otp"
    }

    assert RecordingStudioCache::RateLimiter.allow?(**opts)
    refute RecordingStudioCache::RateLimiter.allow?(**opts)
    travel 46.seconds
    assert RecordingStudioCache::RateLimiter.allow?(**opts)
  end

  def redis_base_error_available?
    require "redis"
    defined?(Redis::CommandError)
  rescue LoadError
    false
  end

  # Minimal Redis duck type: +eval+ for atomic INCR/EXPIRE (+ TTL == -1).
  class FakeRedis
    attr_reader :expire_calls

    def initialize
      @data = {}
      @expires_at = {}
      @expire_calls = 0
    end

    def seed_without_expiry(key, count)
      @data[key] = count
      @expires_at.delete(key)
    end

    def ttl(key)
      remaining_ttl(key)
    end

    def eval(_script, keys:, argv:)
      key = keys.fetch(0)
      expires_in = argv.fetch(0).to_i
      purge_expired!(key)

      @data[key] = @data.fetch(key, 0) + 1
      count = @data[key]
      ttl = remaining_ttl(key)
      if count == 1 || ttl == -1
        @expires_at[key] = Time.now.to_f + expires_in
        @expire_calls += 1
        ttl = remaining_ttl(key)
      end

      [count, ttl]
    end

    private

    def purge_expired!(key)
      expires_at = @expires_at[key]
      return if expires_at.nil?
      return if expires_at > Time.now.to_f

      @data.delete(key)
      @expires_at.delete(key)
    end

    def remaining_ttl(key)
      expires_at = @expires_at[key]
      return -1 if expires_at.nil?

      ttl = (expires_at - Time.now.to_f).ceil
      ttl.positive? ? ttl : -1
    end
  end
end
