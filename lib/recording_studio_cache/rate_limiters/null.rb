# frozen_string_literal: true

module RecordingStudioCache
  module RateLimiters
    # Always-allow backend (Embeddable `:null` semantics).
    class Null
      def initialize(**); end

      def increment(*)
        { count: 0, retry_after: nil }
      end
    end
  end
end
