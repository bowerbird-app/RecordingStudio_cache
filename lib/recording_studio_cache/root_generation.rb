# frozen_string_literal: true

require "securerandom"

module RecordingStudioCache
  # Per-root generation token stored in Rails.cache.
  #
  # Keys embed the current generation so writing a new token makes every prior
  # entry under that root unreachable without deleting each key.
  #
  # Tokens are opaque random strings (not counters). Counters + RedisCacheStore
  # are unsafe: a non-raw +write+ of an integer cannot be +increment+ed, which
  # forced a non-atomic read/write fallback and lost versions under concurrency.
  #
  # == Expiry
  #
  # Generation keys are written without +expires_in+, so they only expire if the
  # underlying store applies a global default TTL. If the generation key is lost
  # (eviction, flush, TTL), the next +current+ reseeds a new token — equivalent
  # to an invalidation: old entry keys stay unreachable. Prefer stores that keep
  # generation keys durable (or omit a short global TTL) when stale resurrection
  # of orphaned entry keys would be a problem.
  module RootGeneration
    module_function

    def current(root_id)
      key = KeyBuilder.root_generation_key(root_id)
      store = RecordingStudioCache.store
      value = store.read(key)
      return value if value

      token = new_token
      store.write(key, token, unless_exist: true)
      store.read(key) || token
    end

    def invalidate!(root_or_recording)
      root_id = KeyBuilder.root_id_for(root_or_recording)
      key = KeyBuilder.root_generation_key(root_id)
      store = RecordingStudioCache.store
      token = new_token
      store.write(key, token)
      instrument_invalidate(root_id, token)
      token
    end

    def new_token
      SecureRandom.uuid
    end
    private_class_method :new_token

    def instrument_invalidate(root_id, root_generation)
      ActiveSupport::Notifications.instrument(
        "invalidate_tree.recording_studio_cache",
        root_id: root_id,
        root_generation: root_generation
      )
    end
    private_class_method :instrument_invalidate
  end
end
