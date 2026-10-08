# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/object/blank"
require "active_support/notifications"
require "recording_studio"
require "recording_studio_cache/version"
require "recording_studio_cache/policy"
require "recording_studio_cache/key_builder"
require "recording_studio_cache/root_generation"
require "recording_studio_cache/store"
require "recording_studio_cache/engine"
require "recording_studio_cache/configuration"

# App-side cache primitives over Rails.cache for Recording Studio hosts and addons.
#
# This gem does **not** publish to Cloudflare/R2 and does not serve public embeds.
# Edge/CDN caching belongs to RecordingStudioArtifacts (+ Cloudflare). Prefer this
# gem for authenticated/API/app payloads scoped to recordings and roots.
#
# @example
#   RecordingStudioCache.fetch(recording, :api_payload, policy: :api_payload) { build_payload(recording) }
#   RecordingStudioCache.invalidate_tree!(recording.root_recording_or_self)
module RecordingStudioCache
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    # Underlying ActiveSupport::Cache::Store. Defaults to Rails.cache.
    # Hosts choose the backend (Solid Cache recommended on DO App Platform; Redis optional).
    def store
      configuration.cache_store || rails_cache!
    end

    def fetch(recording, entry, **, &)
      Store.fetch(recording, entry, **, &)
    end

    def read(recording, entry, **)
      Store.read(recording, entry, **)
    end

    def write(recording, entry, value, **)
      Store.write(recording, entry, value, **)
    end

    def delete(recording, entry, **)
      Store.delete(recording, entry, **)
    end

    def exist?(recording, entry, **)
      Store.exist?(recording, entry, **)
    end

    def key_for(recording, entry, root_generation: nil, vary: nil)
      KeyBuilder.for(recording, entry, root_generation: root_generation, vary: vary)
    end

    def root_generation_for(recording)
      RootGeneration.current(KeyBuilder.root_id_for(recording))
    end

    def invalidate_tree!(root_or_recording)
      RootGeneration.invalidate!(root_or_recording)
    end

    private

    def rails_cache!
      unless defined?(Rails) && Rails.respond_to?(:cache) && Rails.cache
        raise "RecordingStudioCache requires Rails.cache (or set configuration.cache_store)"
      end

      Rails.cache
    end
  end
end
