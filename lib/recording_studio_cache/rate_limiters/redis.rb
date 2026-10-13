# frozen_string_literal: true

module RecordingStudioCache
  module RateLimiters
    # Counter backed by a Redis-compatible client (+incr+ / +expire+).
    #
    # Pass a client via +redis:+. The +redis+ gem is never required at boot; call
    # {require_redis!} only when you need to construct a real +::Redis+ client.
    class Redis
      def initialize(redis: nil)
        @redis = redis
      end

      def increment(storage_key, expires_in:)
        client = @redis
        return { count: 0, retry_after: nil } unless client.respond_to?(:incr)

        count = client.incr(storage_key)
        client.expire(storage_key, expires_in.to_i) if client.respond_to?(:expire) && expires_in.to_i.positive?

        retry_after = remaining_ttl(client, storage_key, expires_in)
        { count: count.to_i, retry_after: retry_after }
      end

      private

      def remaining_ttl(client, storage_key, expires_in)
        return expires_in.to_i unless client.respond_to?(:ttl)

        ttl = client.ttl(storage_key).to_i
        return expires_in.to_i if ttl.negative?

        ttl
      end

      class << self
        def require_redis!
          return if defined?(::Redis)

          require "redis"
        end
      end
    end
  end
end
