# frozen_string_literal: true

module RecordingStudioCache
  class Configuration
    DEFAULT_POLICIES = {
      default: { expires_in: 5 * 60, race_ttl: 5 },
      api_payload: { expires_in: 60, race_ttl: 2 },
      short: { expires_in: 30, race_ttl: 2 },
      long: { expires_in: 60 * 60, race_ttl: 10 }
    }.freeze

    attr_accessor :namespace, :cache_store
    attr_reader :hooks, :policies

    def initialize
      @namespace = "rsc"
      @cache_store = nil
      @policies = DEFAULT_POLICIES.each_with_object({}) do |(name, attrs), memo|
        memo[name] = Policy.new(name: name, **attrs)
      end
      @hooks = RecordingStudio::Hooks.new
    end

    def policy_for(name)
      policies.fetch(name.to_sym) { policies.fetch(:default) }
    end

    def register_policy(name, expires_in:, race_ttl: nil, race_condition_ttl: nil)
      policies[name.to_sym] = Policy.new(
        name: name,
        expires_in: expires_in,
        race_ttl: race_ttl || race_condition_ttl
      )
    end

    def policies=(hash)
      @policies = {}
      hash.each do |name, attrs|
        attrs = attrs.to_h.transform_keys(&:to_sym)
        register_policy(
          name,
          expires_in: attrs[:expires_in],
          race_ttl: attrs[:race_ttl] || attrs[:race_condition_ttl]
        )
      end
    end

    def to_h
      {
        namespace: namespace,
        cache_store: cache_store.nil? ? :rails_cache : cache_store.class.name,
        policies: policies.transform_values { |policy| { expires_in: policy.expires_in, race_ttl: policy.race_ttl } },
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each { |key, value| merge_entry!(key, value) }
    end

    def merge_entry!(key, value)
      return self.policies = value if key.to_s == "policies"

      setter = "#{key}="
      public_send(setter, value) if respond_to?(setter)
    end
    private :merge_entry!
  end
end
