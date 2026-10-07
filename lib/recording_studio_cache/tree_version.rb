# frozen_string_literal: true

module RecordingStudioCache
  # Per-root version token stored in Rails.cache. Incrementing (or replacing) it
  # invalidates every key that embeds the previous version.
  module TreeVersion
    INITIAL = 1

    module_function

    def current(root_id)
      key = KeyBuilder.tree_version_key(root_id)
      store = RecordingStudioCache.store
      value = store.read(key)
      return value if value

      store.write(key, INITIAL)
      INITIAL
    end

    def invalidate!(root_or_recording)
      root_id = KeyBuilder.root_id_for(root_or_recording)
      key = KeyBuilder.tree_version_key(root_id)
      store = RecordingStudioCache.store
      current(root_id)
      next_version = bump_version(store, key)
      instrument_invalidate(root_id, next_version)
      next_version
    end

    def bump_version(store, key)
      return write_fallback(store, key) unless store.respond_to?(:increment)

      store.increment(key) || write_fallback(store, key)
    rescue NotImplementedError, ArgumentError
      write_fallback(store, key)
    end
    private_class_method :bump_version

    def write_fallback(store, key)
      next_version = (store.read(key) || INITIAL).to_i + 1
      store.write(key, next_version)
      next_version
    end
    private_class_method :write_fallback

    def instrument_invalidate(root_id, tree_version)
      ActiveSupport::Notifications.instrument(
        "invalidate_tree.recording_studio_cache",
        root_id: root_id,
        tree_version: tree_version
      )
    end
    private_class_method :instrument_invalidate
  end
end
