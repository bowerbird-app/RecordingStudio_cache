# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "active_support/cache"

class RateLimiterRedisTest < Minitest::Test
  def setup
    skip "REDIS_URL not set" if ENV["REDIS_URL"].to_s.strip.empty?

    begin
      require "redis"
    rescue LoadError
      skip "redis gem not available"
    end

    @redis = Redis.new(url: ENV.fetch("REDIS_URL"))
    @redis.ping
    @prefix = "rsc:rate_test:#{SecureRandom.hex(4)}"
    @memory = ActiveSupport::Cache::MemoryStore.new
  rescue Redis::BaseError, SocketError, Errno::ECONNREFUSED => e
    skip "redis unavailable: #{e.message}"
  end

  def teardown
    return unless @redis && @prefix

    keys = @redis.keys("#{@prefix}*")
    @redis.del(*keys) if keys.any?
  end

  def test_redis_backend_enforces_limit_and_isolates_keys
    shared = { limit: 2, period: 60, backend: :redis, redis: @redis, prefix: @prefix }

    assert RecordingStudioCache::RateLimiter.allow?(key: "one", **shared)
    assert RecordingStudioCache::RateLimiter.allow?(key: "one", **shared)
    refute RecordingStudioCache::RateLimiter.allow?(key: "one", **shared)
    assert RecordingStudioCache::RateLimiter.allow?(key: "two", **shared)
  end

  def test_redis_retry_after_uses_key_ttl
    key = "ttl"
    storage_key = "#{@prefix}:#{key}"
    opts = {
      key: key,
      limit: 1,
      period: 30,
      backend: :redis,
      redis: @redis,
      prefix: @prefix,
      strategy: :ttl
    }

    assert RecordingStudioCache::RateLimiter.allow?(**opts)
    sleep 1
    blocked = RecordingStudioCache::RateLimiter.throttle(**opts)

    assert blocked.blocked?
    redis_ttl = @redis.ttl(storage_key)
    assert_operator redis_ttl, :>, 0
    assert_operator redis_ttl, :<, 30
    assert_in_delta redis_ttl, blocked.retry_after, 1
  end

  def test_redis_command_error_is_rescued_as_base_error
    broken = Object.new
    def broken.eval(*)
      raise Redis::CommandError, "ERR simulated command failure"
    end

    result = RecordingStudioCache::RateLimiter.throttle(
      key: "cmd",
      limit: 1,
      period: 60,
      backend: :redis,
      redis: broken,
      fail_closed: true
    )
    assert result.blocked?
  end

  def test_redis_expires_when_existing_key_has_no_ttl
    storage_key = "#{@prefix}:orphan"
    @redis.set(storage_key, 5)
    assert_equal(-1, @redis.ttl(storage_key))

    result = RecordingStudioCache::RateLimiter.throttle(
      key: "orphan",
      limit: 10,
      period: 20,
      backend: :redis,
      redis: @redis,
      prefix: @prefix,
      strategy: :ttl
    )

    assert result.allowed?
    assert_equal 6, result.count
    assert_operator @redis.ttl(storage_key), :>, 0
    assert_operator @redis.ttl(storage_key), :<=, 20
  end

  def test_redis_ttl_blocked_hits_do_not_extend_window_matching_rails_cache
    period = 2
    redis_opts = {
      key: "ttl-parity",
      limit: 1,
      period: period,
      backend: :redis,
      redis: @redis,
      strategy: :ttl,
      prefix: @prefix
    }
    rails_opts = {
      key: "ttl-parity",
      limit: 1,
      period: period,
      backend: :rails_cache,
      store: @memory,
      strategy: :ttl,
      prefix: @prefix
    }

    redis_key = "#{@prefix}:ttl-parity"

    assert RecordingStudioCache::RateLimiter.allow?(**redis_opts)
    assert RecordingStudioCache::RateLimiter.allow?(**rails_opts)

    refute RecordingStudioCache::RateLimiter.allow?(**redis_opts)
    refute RecordingStudioCache::RateLimiter.allow?(**rails_opts)

    ttl_after_block = @redis.ttl(redis_key)
    assert_operator ttl_after_block, :>, 0
    assert_operator ttl_after_block, :<=, period

    sleep(period + 0.2)

    assert RecordingStudioCache::RateLimiter.allow?(**redis_opts)
    assert RecordingStudioCache::RateLimiter.allow?(**rails_opts)
    assert_equal 1, @redis.get(redis_key).to_i
  end

  def test_redis_expire_only_on_first_incr
    key_suffix = "expire-once"
    opts = {
      key: key_suffix,
      limit: 5,
      period: 30,
      backend: :redis,
      redis: @redis,
      strategy: :ttl,
      prefix: @prefix
    }
    storage_key = "#{@prefix}:#{key_suffix}"

    RecordingStudioCache::RateLimiter.throttle(**opts)
    first_ttl = @redis.ttl(storage_key)
    sleep 1
    RecordingStudioCache::RateLimiter.throttle(**opts)
    second_ttl = @redis.ttl(storage_key)

    assert_operator first_ttl, :>, 0
    assert_operator second_ttl, :<, first_ttl
    assert_equal 2, @redis.get(storage_key).to_i
  end

  def test_redis_concurrent_increments_are_atomic
    opts = {
      key: "race",
      limit: 10_000,
      period: 60,
      backend: :redis,
      redis: @redis,
      prefix: @prefix
    }
    threads = 8.times.map do
      Thread.new do
        25.times { RecordingStudioCache::RateLimiter.throttle(**opts) }
      end
    end
    threads.each(&:join)

    final = RecordingStudioCache::RateLimiter.throttle(**opts)
    assert_equal 201, final.count
  end
end
