# frozen_string_literal: true

module RecordingStudioCache
  # Thin wrapper around Rails.cache with policy-aware fetch and instrumentation.
  module Store # rubocop:disable Metrics/ModuleLength
    KNOWN_OPTIONS = %i[policy vary expires_in race_ttl race_condition_ttl].freeze

    module_function

    def fetch(recording, entry, **options, &block) # rubocop:disable Metrics/MethodLength
      raise ArgumentError, "block required" unless block

      KeyBuilder.normalize_entry!(entry)
      policy_name, vary, overrides = unpack_options!(options)
      resolved = resolve_policy(entry, policy_name, overrides)
      key = KeyBuilder.for(recording, entry, vary: vary)
      hit = true
      payload = notification_payload(recording, entry, key, resolved, vary: vary)

      ActiveSupport::Notifications.instrument("fetch.recording_studio_cache", payload) do |event|
        value = RecordingStudioCache.store.fetch(key, **resolved.fetch_options) do
          hit = false
          block.call
        end
        event[:hit] = hit
        value
      end
    end

    def read(recording, entry, **options)
      key, vary = key_without_policy_overrides!(recording, entry, options)
      payload = notification_payload(recording, entry, key, nil, vary: vary)

      ActiveSupport::Notifications.instrument("read.recording_studio_cache", payload) do |event|
        store = RecordingStudioCache.store
        value = store.read(key)
        event[:hit] = store.exist?(key)
        value
      end
    end

    def write(recording, entry, value, **options)
      KeyBuilder.normalize_entry!(entry)
      policy_name, vary, overrides = unpack_options!(options)
      resolved = resolve_policy(entry, policy_name, overrides)
      key = KeyBuilder.for(recording, entry, vary: vary)
      payload = notification_payload(recording, entry, key, resolved, vary: vary)
      write_options = resolved.fetch_options.except(:race_condition_ttl)

      ActiveSupport::Notifications.instrument("write.recording_studio_cache", payload) do
        RecordingStudioCache.store.write(key, value, **write_options)
      end
    end

    def delete(recording, entry, **options)
      key, vary = key_without_policy_overrides!(recording, entry, options)
      payload = notification_payload(recording, entry, key, nil, vary: vary)

      ActiveSupport::Notifications.instrument("delete.recording_studio_cache", payload) do
        RecordingStudioCache.store.delete(key)
      end
    end

    def exist?(recording, entry, **options)
      key, = key_without_policy_overrides!(recording, entry, options)
      RecordingStudioCache.store.exist?(key)
    end

    def key_without_policy_overrides!(recording, entry, options)
      KeyBuilder.normalize_entry!(entry)
      _policy_name, vary, overrides = unpack_options!(options)
      raise ArgumentError, "unknown keyword options: #{overrides.keys.sort.join(', ')}" if overrides.any?

      [KeyBuilder.for(recording, entry, vary: vary), vary]
    end
    private_class_method :key_without_policy_overrides!

    def unpack_options!(options)
      unknown = options.keys - KNOWN_OPTIONS
      raise ArgumentError, "unknown keyword options: #{unknown.sort.join(', ')}" if unknown.any?

      [
        options[:policy],
        options[:vary],
        options.slice(:expires_in, :race_ttl, :race_condition_ttl)
      ]
    end
    private_class_method :unpack_options!

    def resolve_policy(entry, policy_name, overrides)
      name = resolve_policy_name(entry, policy_name)
      base = RecordingStudioCache.configuration.policy_for(name)
      Policy.new(
        name: name,
        expires_in: override_or(base.expires_in, overrides, :expires_in),
        race_ttl: race_ttl_for(base, overrides)
      )
    end
    private_class_method :resolve_policy

    def resolve_policy_name(entry, policy_name)
      return policy_name.to_sym if policy_name

      RecordingStudioCache.configuration.policy_name_for_entry(entry) || :default
    end
    private_class_method :resolve_policy_name

    def race_ttl_for(base, overrides)
      return overrides[:race_ttl] if overrides.key?(:race_ttl)
      return overrides[:race_condition_ttl] if overrides.key?(:race_condition_ttl)

      base.race_ttl
    end
    private_class_method :race_ttl_for

    def override_or(default, overrides, key)
      overrides.key?(key) ? overrides[key] : default
    end
    private_class_method :override_or

    def notification_payload(recording, entry, key, policy, vary:)
      {
        key: key,
        entry: entry.to_sym,
        policy: policy&.name,
        root_id: KeyBuilder.root_id_for(recording),
        recording_id: recording.id.to_s,
        expires_in: policy&.expires_in,
        race_ttl: policy&.race_ttl,
        vary: vary
      }
    end
    private_class_method :notification_payload
  end
end
