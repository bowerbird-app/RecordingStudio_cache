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
    DEFAULT_SEPARATOR = ":"
    REDIS_CLIENT_REQUIRED = "backend: :redis requires a redis: client that responds to incr"

    # Connection / store failures that follow +fail_closed+ (not programming errors).
    BACKEND_ERRORS = [
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::ETIMEDOUT,
      Errno::EPIPE,
      Errno::EHOSTUNREACH,
      SocketError,
      IOError,
      Timeout::Error
    ].freeze

    attr_reader :key, :limit, :period, :backend, :strategy, :prefix, :separator, :fail_closed

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

    # @param key [String] caller-owned bucket identity (optional when +storage_key:+ set)
    # @param limit [Integer] max allowed hits in the window; +<= 0+ disables limiting
    # @param period [Integer] window length in seconds (alias: +window:+)
    # @param window [Integer] alias for +period:+ (Embeddable naming)
    # @param backend [Symbol] +:null+, +:rails_cache+, or +:redis+
    # @param strategy [Symbol] +:fixed+ (calendar bucket) or +:ttl+ (rolling key TTL)
    # @param store [ActiveSupport::Cache::Store, nil] rails_cache store override
    # @param redis [#incr, #eval] redis client (required when +backend: :redis+)
    # @param fail_closed [Boolean] when the backend errors, block if true (Embeddable)
    # @param prefix [String] storage key prefix before +key+ / window segment
    # @param separator [String] join between prefix, key, and fixed-window bucket (default +":"+)
    # @param storage_key [String, nil] exact base key (skips prefix/key join); fixed still appends bucket
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
    rescue *backend_errors
      failure_result
    end

    # @return [Boolean]
    def allow?
      throttle.allowed?
    end

    private

    def assign_options!(options)
      assign_core_options!(options)
      assign_key_options!(options)
      @store = options[:store]
      @redis = options[:redis]
    end

    def assign_core_options!(options)
      @limit = options.fetch(:limit).to_i
      @period = (options[:period].nil? ? options[:window] : options[:period])
      @backend = (options[:backend] || :rails_cache).to_sym
      @strategy = (options[:strategy] || :fixed).to_sym
      @fail_closed = options.fetch(:fail_closed, false) ? true : false
    end

    def assign_key_options!(options)
      @key = options.key?(:key) ? options[:key].to_s : nil
      @prefix = (options[:prefix] || DEFAULT_PREFIX).to_s
      @separator = options.fetch(:separator, DEFAULT_SEPARATOR).to_s
      @storage_key = options[:storage_key]&.to_s
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
      raise ArgumentError, "period must be positive" unless @period.positive?
      raise ArgumentError, "unknown backend: #{@backend}" unless BACKENDS.include?(@backend)
      raise ArgumentError, "unknown strategy: #{@strategy}" unless STRATEGIES.include?(@strategy)
      raise ArgumentError, "key: or storage_key: is required" if base_key_blank?
    end

    def base_key_blank?
      return @storage_key.strip.empty? if @storage_key

      @key.nil? || @key.strip.empty?
    end

    def build_backend
      case backend
      when :null
        RateLimiters::Null.new
      when :rails_cache
        RateLimiters::RailsCache.new(store: @store)
      when :redis
        require "recording_studio_cache/rate_limiters/redis"
        ensure_redis_client!
        RateLimiters::Redis.new(redis: @redis)
      end
    end

    def ensure_redis_client!
      return if @redis.respond_to?(:incr)

      begin
        RateLimiters::Redis.require_redis!
      rescue LoadError
        raise ArgumentError, REDIS_CLIENT_REQUIRED
      end

      raise ArgumentError, REDIS_CLIENT_REQUIRED
    end

    def storage_key_for(epoch)
      base = @storage_key.presence || [@prefix, @key].join(@separator)
      case strategy
      when :fixed
        "#{base}#{@separator}#{epoch / period}"
      when :ttl
        base
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

    def backend_errors
      errors = BACKEND_ERRORS.dup
      errors << ::Redis::BaseError if defined?(::Redis::BaseError)
      errors
    end
  end
end
