# frozen_string_literal: true

require "digest"
require "json"

module RecordingStudioCache
  # Builds stable Rails.cache keys scoped by root, generation, and recording.
  #
  # Shape:
  #   {namespace}/v{schema}/r/{root_id}/rg/{root_generation}/rec/{recording_id}/{entry}
  #   {namespace}/v{schema}/r/{root_id}/rg/{root_generation}/rec/{recording_id}/{entry}/v/{vary_digest}
  #
  # Root-generation invalidation replaces the generation token so prior keys
  # become unreachable without deleting every entry under the root.
  class KeyBuilder
    SCHEMA_VERSION = 2
    VARY_DIGEST_LENGTH = 16

    class << self
      def for(recording, entry, root_generation: nil, vary: nil)
        recording = normalize_recording!(recording)
        entry_name = normalize_entry!(entry)
        root_id = root_id_for(recording)
        generation = root_generation || RootGeneration.current(root_id)
        segments = segments_for(root_id, generation, recording.id, entry_name)
        digest = vary_digest(vary)
        segments.push("v", digest) if digest
        segments.join("/")
      end

      def segments_for(root_id, generation, recording_id, entry)
        [
          RecordingStudioCache.configuration.namespace,
          "v#{SCHEMA_VERSION}",
          "r", root_id,
          "rg", generation,
          "rec", recording_id,
          entry
        ]
      end
      private :segments_for

      def root_generation_key(root_id)
        [
          RecordingStudioCache.configuration.namespace,
          "v#{SCHEMA_VERSION}",
          "r", root_id,
          "rg"
        ].join("/")
      end

      def root_id_for(recording)
        recording = normalize_recording!(recording)
        # Prefer the column so key building never loads associations.
        (recording.root_recording_id.presence || recording.id).to_s
      end

      def normalize_recording!(recording)
        unless recording.respond_to?(:id) && recording.id.present? && recording.respond_to?(:root_recording_id)
          raise ArgumentError,
                "Expected a persisted RecordingStudio::Recording (id + root_recording_id), got #{recording.class}"
        end

        recording
      end

      def normalize_entry!(entry)
        unless entry.is_a?(Symbol) || entry.is_a?(String)
          raise ArgumentError, "entry must be a Symbol or String, got #{entry.class}"
        end

        name = entry.to_s.strip
        raise ArgumentError, "entry name is required" if name.empty?
        raise ArgumentError, "entry name must not contain '/'" if name.include?("/")

        name
      end

      def vary_digest(vary)
        return nil if vary.nil?
        raise ArgumentError, "vary must be a Hash, got #{vary.class}" unless vary.is_a?(Hash)
        return nil if vary.empty?

        normalized = vary.transform_keys(&:to_s)
        pairs = normalized.keys.sort.map { |key| [key, normalized[key]] }
        Digest::SHA256.hexdigest(JSON.generate(pairs))[0, VARY_DIGEST_LENGTH]
      end
    end
  end
end
