# frozen_string_literal: true

require "recording_studio_cache/rate_limiters/result"
require "recording_studio_cache/rate_limiters/null"
require "recording_studio_cache/rate_limiters/rails_cache"
# Redis backend file is required lazily when selected — see {#build_backend}.

module RecordingStudioCache
  # Shared fixed/TTL window rate limiter for Recording Studio sibling gems.
  #
  # Ported from RecordingStudioEmbeddable's null / rails_cache / redis backends,
  # with a small Result surface (allowed/blocked + retry-after) that also covers
  # Downloadable, RootSwitchable, Users OTP, and Oauth register limiters.
  #
  # @example
  #   result = RecordingStudioCache::RateLimiter.new(
  #     key: "embed:#{token_digest}",
  #     limit: 120,
  #     period: 60,
  #     backend: :rails_cache
  #   ).throttle
  #   head :too_many_requests if result.blocked?
  class RateLimiter # rubocop:disable Metrics/ClassLength
    BACKENDS = %i[null rails_cache redis].freeze
    STRATEGIES = %i[fixed ttl].freeze
    DEFAULT_PREFIX = "rsc:rate"

    attr_reader :key, :limit, :period, :backend, :strategy, :prefix, :fail_closed

    class << self
      # @return [RateLimiters::Result]
      def throttle(**)
        new(**).throttle
      end

      # @return [Boolean]
      def allow?(**)
        throttle(**).allowed?
      end
    end

    # @param key [String] caller-owned bucket identity (IP, actor, digest, …)
    # @param limit [Integer] max allowed hits in the window; +<= 0+ disables limiting
    # @param period [Integer] window length in seconds (alias: +window:+)
    # @param window [Integer] alias for +period:+ (Embeddable naming)
    # @param backend [Symbol] +:null+, +:rails_cache+, or +:redis+
    # @param strategy [Symbol] +:fixed+ (calendar bucket) or +:ttl+ (rolling key TTL)
    # @param store [ActiveSupport::Cache::Store, nil] rails_cache store override
    # @param redis [#incr, nil] redis client (required for a reliable redis backend)
    # @param fail_closed [Boolean] when the backend errors, block if true (Embeddable)
    # @param prefix [String] storage key prefix before +key+ / window segment
    def initialize(**options)
      assign_options!(options)
      validate!
      @backend_instance = build_backend
    end

    # Increment the bucket and return whether this hit is allowed.
    #
    # @return [RateLimiters::Result]
    def throttle
      return disabled_result if limit <= 0

      epoch = now_epoch
      payload = @backend_instance.increment(storage_key_for(epoch), expires_in: period)
      build_result(payload, epoch)
    rescue StandardError
      failure_result
    end

    # @return [Boolean]
    def allow?
      throttle.allowed?
    end

    private

    def assign_options!(options) # rubocop:disable Metrics/AbcSize
      @key = options.fetch(:key).to_s
      @limit = options.fetch(:limit).to_i
      @period = (options[:period].nil? ? options[:window] : options[:period])
      @backend = (options[:backend] || :rails_cache).to_sym
      @strategy = (options[:strategy] || :fixed).to_sym
      @fail_closed = options.fetch(:fail_closed, false) ? true : false
      @prefix = (options[:prefix] || DEFAULT_PREFIX).to_s
      @store = options[:store]
      @redis = options[:redis]
    end

    def build_result(payload, epoch)
      count = payload.fetch(:count).to_i
      allowed = count <= limit
      RateLimiters::Result.new(
        count: count,
        limit: limit,
        period: period,
        allowed: allowed,
        retry_after: allowed ? nil : retry_after_for(payload, epoch)
      )
    end

    def validate!
      raise ArgumentError, "period: or window: is required" if @period.nil?

      @period = @period.to_i
      raise ArgumentError, "key must be present" if @key.strip.empty?
      raise ArgumentError, "period must be positive" unless @period.positive?
      raise ArgumentError, "unknown backend: #{@backend}" unless BACKENDS.include?(@backend)
      raise ArgumentError, "unknown strategy: #{@strategy}" unless STRATEGIES.include?(@strategy)
    end

    def build_backend
      case backend
      when :null
        RateLimiters::Null.new
      when :rails_cache
        RateLimiters::RailsCache.new(store: @store)
      when :redis
        require "recording_studio_cache/rate_limiters/redis"
        RateLimiters::Redis.new(redis: @redis)
      end
    end

    def storage_key_for(epoch)
      case strategy
      when :fixed
        "#{prefix}:#{key}:#{epoch / period}"
      when :ttl
        "#{prefix}:#{key}"
      end
    end

    def retry_after_for(payload, epoch)
      from_backend = payload[:retry_after]
      return from_backend.to_i if from_backend&.to_i&.positive?

      case strategy
      when :fixed
        remaining = period - (epoch % period)
        remaining.positive? ? remaining : period
      when :ttl
        period
      end
    end

    def now_epoch
      if defined?(Time.zone) && Time.zone
        Time.zone.now.to_i
      elsif Time.respond_to?(:current)
        Time.current.to_i
      else
        Time.now.to_i
      end
    end

    def disabled_result
      RateLimiters::Result.new(count: 0, limit: limit, period: period, allowed: true, retry_after: nil)
    end

    def failure_result
      RateLimiters::Result.new(
        count: 0,
        limit: limit,
        period: period,
        allowed: !fail_closed,
        retry_after: fail_closed ? period : nil
      )
    end
  end
end
