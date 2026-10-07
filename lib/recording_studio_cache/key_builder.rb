# frozen_string_literal: true

module RecordingStudioCache
  # Builds stable Rails.cache keys scoped by root, tree version, and recording.
  #
  # Shape:
  #   {namespace}/v{schema}/r/{root_id}/tv/{tree_version}/rec/{recording_id}/{entry}
  #
  # Tree-version invalidation bumps +tree_version+ so prior keys become unreachable
  # without deleting every entry under the root.
  class KeyBuilder
    SCHEMA_VERSION = 1

    class << self
      def for(recording, entry, tree_version: nil)
        recording = normalize_recording!(recording)
        root_id = root_id_for(recording)
        version = tree_version || TreeVersion.current(root_id)
        segments_for(root_id, version, recording.id, normalize_entry!(entry)).join("/")
      end

      def segments_for(root_id, version, recording_id, entry)
        [
          RecordingStudioCache.configuration.namespace,
          "v#{SCHEMA_VERSION}",
          "r", root_id,
          "tv", version,
          "rec", recording_id,
          entry
        ]
      end
      private :segments_for

      def tree_version_key(root_id)
        [
          RecordingStudioCache.configuration.namespace,
          "v#{SCHEMA_VERSION}",
          "r", root_id,
          "tv"
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
        name = entry.to_s.strip
        raise ArgumentError, "entry name is required" if name.empty?
        raise ArgumentError, "entry name must not contain '/'" if name.include?("/")

        name
      end
    end
  end
end
