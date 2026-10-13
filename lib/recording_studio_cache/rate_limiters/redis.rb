# frozen_string_literal: true

module RecordingStudioCache
  module RateLimiters
    # Counter backed by a Redis-compatible client.
    #
    # Uses one Lua +EVAL+ so +INCR+ and +EXPIRE+ (first hit, or key with no TTL)
    # are atomic. Later hits with a live TTL do not refresh the window (matches
    # rails_cache +:ttl+). Pass a client via +redis:+ that responds to +eval+.
    # The +redis+ gem is never required at boot.
    class Redis
      # KEYS[1] = storage key, ARGV[1] = expires_in seconds
      # Returns { count, ttl }. EXPIRE when this INCR created the key or TTL is -1.
      INCR_EXPIRE_SCRIPT = <<~LUA
        local count = redis.call('INCR', KEYS[1])
        local ttl = redis.call('TTL', KEYS[1])
        if count == 1 or ttl == -1 then
          redis.call('EXPIRE', KEYS[1], ARGV[1])
          ttl = redis.call('TTL', KEYS[1])
        end
        return { count, ttl }
      LUA

      def initialize(redis:)
        @redis = redis
      end

      def increment(storage_key, expires_in:)
        count, ttl = eval_incr_expire(storage_key, expires_in.to_i)
        retry_after = ttl.to_i.negative? ? expires_in.to_i : ttl.to_i
        { count: count.to_i, retry_after: retry_after }
      end

      class << self
        def require_redis!
          return if defined?(::Redis)

          require "redis"
        end
      end

      private

      def eval_incr_expire(storage_key, expires_in)
        result = @redis.eval(INCR_EXPIRE_SCRIPT, keys: [storage_key], argv: [expires_in])
        Array(result)
      end
    end
  end
end
