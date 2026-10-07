# frozen_string_literal: true

module RecordingStudioCache
  # Thin wrapper around Rails.cache with policy-aware fetch and instrumentation.
  module Store
    module_function

    def fetch(recording, entry, policy: nil, **overrides, &block) # rubocop:disable Metrics/MethodLength
      raise ArgumentError, "block required" unless block

      resolved = resolve_policy(entry, policy, overrides)
      key = KeyBuilder.for(recording, entry)
      hit = true
      payload = notification_payload(recording, entry, key, resolved)

      ActiveSupport::Notifications.instrument("fetch.recording_studio_cache", payload) do |event|
        value = RecordingStudioCache.store.fetch(key, **resolved.fetch_options) do
          hit = false
          block.call
        end
        event[:hit] = hit
        value
      end
    end

    def read(recording, entry)
      key = KeyBuilder.for(recording, entry)
      payload = notification_payload(recording, entry, key, nil)

      ActiveSupport::Notifications.instrument("read.recording_studio_cache", payload) do |event|
        value = RecordingStudioCache.store.read(key)
        event[:hit] = !value.nil?
        value
      end
    end

    def write(recording, entry, value, policy: nil, **overrides)
      resolved = resolve_policy(entry, policy, overrides)
      key = KeyBuilder.for(recording, entry)
      payload = notification_payload(recording, entry, key, resolved)
      options = resolved.fetch_options.except(:race_condition_ttl)

      ActiveSupport::Notifications.instrument("write.recording_studio_cache", payload) do
        RecordingStudioCache.store.write(key, value, **options)
      end
    end

    def delete(recording, entry)
      key = KeyBuilder.for(recording, entry)
      payload = notification_payload(recording, entry, key, nil)

      ActiveSupport::Notifications.instrument("delete.recording_studio_cache", payload) do
        RecordingStudioCache.store.delete(key)
      end
    end

    def exist?(recording, entry)
      RecordingStudioCache.store.exist?(KeyBuilder.for(recording, entry))
    end

    def resolve_policy(entry, policy_name, overrides)
      name = (policy_name || entry).to_sym
      base = RecordingStudioCache.configuration.policy_for(name)
      Policy.new(
        name: name,
        expires_in: override_or(base.expires_in, overrides, :expires_in),
        race_ttl: race_ttl_for(base, overrides)
      )
    end
    private_class_method :resolve_policy

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

    def notification_payload(recording, entry, key, policy)
      {
        key: key,
        entry: entry.to_sym,
        policy: policy&.name,
        root_id: KeyBuilder.root_id_for(recording),
        recording_id: recording.id.to_s,
        expires_in: policy&.expires_in,
        race_ttl: policy&.race_ttl
      }
    end
    private_class_method :notification_payload
  end
end
