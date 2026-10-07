# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "active_support/cache"

class CacheStoreTest < Minitest::Test
  FakeRecording = Struct.new(:id, :root_recording_id, keyword_init: true)

  def setup
    RecordingStudioCache.reset_configuration!
    @memory = ActiveSupport::Cache::MemoryStore.new
    RecordingStudioCache.configuration.cache_store = @memory
    RecordingStudioCache.configuration.namespace = "rsc_test"
    @events = []
    @subscriber = ActiveSupport::Notifications.subscribe(/recording_studio_cache/) do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      @events << event
    end
  end

  def teardown
    ActiveSupport::Notifications.unsubscribe(@subscriber)
    RecordingStudioCache.reset_configuration!
  end

  def test_fetch_caches_and_reports_hit_miss
    recording = build_recording
    calls = 0

    first = RecordingStudioCache.fetch(recording, :api_payload) do
      calls += 1
      { ok: true }
    end
    second = RecordingStudioCache.fetch(recording, :api_payload) do
      calls += 1
      { ok: false }
    end

    assert_equal({ ok: true }, first)
    assert_equal({ ok: true }, second)
    assert_equal 1, calls

    fetch_events = @events.select { |event| event.name == "fetch.recording_studio_cache" }
    assert_equal false, fetch_events.first.payload[:hit]
    assert_equal true, fetch_events.last.payload[:hit]
  end

  def test_key_includes_root_recording_tree_version_and_entry
    root_id = SecureRandom.uuid
    recording = build_recording(id: SecureRandom.uuid, root_id: root_id)
    key = RecordingStudioCache.key_for(recording, :api_payload)

    assert_match %r{\Arsc_test/v1/r/#{root_id}/tv/1/rec/#{recording.id}/api_payload\z}, key
  end

  def test_invalidate_tree_changes_keys_and_misses_old_entries
    recording = build_recording
    RecordingStudioCache.write(recording, :api_payload, "v1")
    assert_equal "v1", RecordingStudioCache.read(recording, :api_payload)

    old_key = RecordingStudioCache.key_for(recording, :api_payload)
    new_version = RecordingStudioCache.invalidate_tree!(recording)
    new_key = RecordingStudioCache.key_for(recording, :api_payload)

    assert_equal 2, new_version
    refute_equal old_key, new_key
    assert_nil RecordingStudioCache.read(recording, :api_payload)
    assert(@events.any? { |event| event.name == "invalidate_tree.recording_studio_cache" })
  end

  def test_policy_options_passed_to_fetch
    recording = build_recording
    seen = nil
    store = RecordingStudioCache.store
    store.stub(:fetch, lambda { |_key, **options, &block|
      seen = options
      block.call
    }) do
      RecordingStudioCache.fetch(recording, :api_payload) { "x" }
    end

    assert_equal 60, seen[:expires_in]
    assert_equal 2, seen[:race_condition_ttl]
  end

  def test_delete_and_exist
    recording = build_recording
    RecordingStudioCache.write(recording, :short, "temp", policy: :short)
    assert RecordingStudioCache.exist?(recording, :short)

    RecordingStudioCache.delete(recording, :short)
    refute RecordingStudioCache.exist?(recording, :short)
  end

  def test_rejects_non_recording
    error = assert_raises(ArgumentError) do
      RecordingStudioCache.fetch(Object.new, :api_payload) { 1 }
    end
    assert_match(/RecordingStudio::Recording/, error.message)
  end

  private

  def build_recording(id: SecureRandom.uuid, root_id: nil)
    FakeRecording.new(id: id, root_recording_id: root_id || id)
  end
end
