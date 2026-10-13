# frozen_string_literal: true

module RecordingStudioCache
  module RateLimiters
    # Outcome of one {RecordingStudioCache::RateLimiter#throttle} call.
    class Result
      attr_reader :count, :limit, :period, :retry_after

      def initialize(count:, limit:, period:, allowed:, retry_after:)
        @count = count.to_i
        @limit = limit.to_i
        @period = period.to_i
        @allowed = allowed
        @retry_after = retry_after
      end

      def allowed?
        @allowed
      end

      def blocked?
        !@allowed
      end
    end
  end
end
