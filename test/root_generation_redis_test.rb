# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "active_support/cache"
require "active_support/cache/redis_cache_store"

class RootGenerationRedisTest < Minitest::Test
  FakeRecording = Struct.new(:id, :root_recording_id, keyword_init: true)

  def setup
    skip "REDIS_URL not set" if ENV["REDIS_URL"].to_s.strip.empty?

    begin
      require "redis"
    rescue LoadError
      skip "redis gem not available"
    end

    RecordingStudioCache.reset_configuration!
    @store = ActiveSupport::Cache::RedisCacheStore.new(
      url: ENV.fetch("REDIS_URL"),
      namespace: "rsc_redis_test_#{SecureRandom.hex(4)}",
      error_handler: ->(*) {}
    )
    @store.clear
    RecordingStudioCache.configuration.cache_store = @store
    RecordingStudioCache.configuration.namespace = "rsc_redis"
  end

  def teardown
    @store&.clear
    RecordingStudioCache.reset_configuration!
  end

  def test_seed_uses_unless_exist_and_returns_uuid
    recording = build_recording
    first = RecordingStudioCache.root_generation_for(recording)
    second = RecordingStudioCache.root_generation_for(recording)

    assert_equal first, second
    assert_match(/\A[0-9a-f-]{36}\z/, first)
  end

  def test_concurrent_invalidations_never_repeat_or_go_backwards
    recording = build_recording
    seed = RecordingStudioCache.root_generation_for(recording)
    seen = Queue.new
    threads = 16.times.map do
      Thread.new do
        50.times { seen << RecordingStudioCache.invalidate_tree!(recording) }
      end
    end
    threads.each(&:join)

    tokens = []
    tokens << seen.pop until seen.empty?
    assert_equal 800, tokens.size
    assert_equal 800, tokens.uniq.size
    refute_includes tokens, seed

    final = RecordingStudioCache.root_generation_for(recording)
    assert_includes tokens, final
  end

  def test_generation_key_loss_reseeds_without_resurrecting_old_entries
    recording = build_recording
    RecordingStudioCache.write(recording, :api_payload, "STALE", policy: :api_payload)
    old_generation = RecordingStudioCache.root_generation_for(recording)
    old_key = RecordingStudioCache.key_for(recording, :api_payload, root_generation: old_generation)

    generation_key = RecordingStudioCache::KeyBuilder.root_generation_key(
      RecordingStudioCache::KeyBuilder.root_id_for(recording)
    )
    @store.delete(generation_key)

    reseeded = RecordingStudioCache.root_generation_for(recording)
    refute_equal old_generation, reseeded
    assert_equal "STALE", @store.read(old_key)
    assert_nil RecordingStudioCache.read(recording, :api_payload)
    refute_equal old_key, RecordingStudioCache.key_for(recording, :api_payload)
  end

  private

  def build_recording(id: SecureRandom.uuid, root_id: nil)
    FakeRecording.new(id: id, root_recording_id: root_id || id)
  end
end
