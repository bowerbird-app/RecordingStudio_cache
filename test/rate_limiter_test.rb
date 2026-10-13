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

  def test_fail_closed_blocks_when_store_raises
    broken = Object.new
    def broken.increment(*)
      raise "cache down"
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

  def test_redis_backend_with_fake_client
    redis = FakeRedis.new
    opts = { key: "r", limit: 2, period: 60, backend: :redis, redis: redis }

    assert RecordingStudioCache::RateLimiter.allow?(**opts)
    assert RecordingStudioCache::RateLimiter.allow?(**opts)
    result = RecordingStudioCache::RateLimiter.throttle(**opts)
    assert result.blocked?
    assert_equal 3, result.count
    assert_equal 60, redis.ttls.values.first
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

  # Minimal Redis duck type used when the redis gem is not needed.
  class FakeRedis
    attr_reader :ttls

    def initialize
      @data = Hash.new(0)
      @ttls = {}
    end

    def incr(key)
      @data[key] += 1
    end

    def expire(key, seconds)
      @ttls[key] = seconds
    end

    def ttl(key)
      @ttls.fetch(key, -1)
    end
  end
end
