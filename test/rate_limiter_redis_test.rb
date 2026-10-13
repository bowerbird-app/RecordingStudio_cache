# frozen_string_literal: true

require "test_helper"
require "securerandom"

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
    result = nil
    3.times do
      result = RecordingStudioCache::RateLimiter.throttle(
        key: "ttl",
        limit: 1,
        period: 30,
        backend: :redis,
        redis: @redis,
        prefix: @prefix,
        strategy: :ttl
      )
    end

    assert result.blocked?
    assert_operator result.retry_after, :>, 0
    assert_operator result.retry_after, :<=, 30
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
