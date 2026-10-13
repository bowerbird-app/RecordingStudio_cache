# frozen_string_literal: true

module RecordingStudioCache
  module RateLimiters
    # Fixed/TTL counter backed by an ActiveSupport::Cache store (default Rails.cache).
    #
    # Mirrors RecordingStudioEmbeddable::RateLimiters::RailsCache: +increment+ with
    # +expires_in+, plus a write-fallback when +increment+ returns nil (Oauth /
    # Downloadable stores that need a seed write).
    class RailsCache
      def initialize(store: nil)
        @store = store
      end

      def increment(storage_key, expires_in:)
        cache = resolve_store
        return { count: 0, retry_after: nil } unless cache

        { count: next_count(cache, storage_key, expires_in), retry_after: nil }
      end

      private

      def resolve_store
        return @store if @store
        return configured_store if configured_store
        return nil unless defined?(Rails) && Rails.respond_to?(:cache) && Rails.cache

        Rails.cache
      end

      def configured_store
        return @configured_store if defined?(@configured_store)

        @configured_store =
          begin
            RecordingStudioCache.store
          rescue StandardError
            nil
          end
      end

      def next_count(cache, storage_key, expires_in)
        count = cache.increment(storage_key, 1, expires_in: expires_in)
        return count.to_i unless count.nil?

        written = cache.write(storage_key, 1, expires_in: expires_in, unless_exist: true)
        return 1 if written

        (cache.read(storage_key) || 1).to_i
      end
    end
  end
end
