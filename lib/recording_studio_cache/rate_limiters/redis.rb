# frozen_string_literal: true

module RecordingStudioCache
  module RateLimiters
    # Counter backed by a Redis-compatible client.
    #
    # Uses one Lua +EVAL+ so +INCR+ and the first-hit +EXPIRE+ are atomic, and
    # later hits do not refresh the TTL (matches rails_cache +:ttl+ windows).
    # Pass a client via +redis:+ that responds to +eval+ (or +incr+ for the
    # constructor check). The +redis+ gem is never required at boot.
    class Redis
      # KEYS[1] = storage key, ARGV[1] = expires_in seconds
      # Returns { count, ttl }. EXPIRE only when this INCR created the key.
      INCR_EXPIRE_SCRIPT = <<~LUA
        local count = redis.call('INCR', KEYS[1])
        if count == 1 then
          redis.call('EXPIRE', KEYS[1], ARGV[1])
        end
        local ttl = redis.call('TTL', KEYS[1])
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
