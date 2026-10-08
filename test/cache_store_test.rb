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
    RecordingStudioCache.configuration.register_entry :api_payload, policy: :api_payload
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

  def test_key_includes_root_recording_generation_and_entry
    root_id = SecureRandom.uuid
    recording = build_recording(id: SecureRandom.uuid, root_id: root_id)
    generation = RecordingStudioCache.root_generation_for(recording)
    key = RecordingStudioCache.key_for(recording, :api_payload)

    assert_match %r{\Arsc_test/v2/r/#{root_id}/rg/#{Regexp.escape(generation)}/rec/#{recording.id}/api_payload\z}, key
  end

  def test_invalidate_tree_changes_keys_and_misses_old_entries
    recording = build_recording
    RecordingStudioCache.write(recording, :api_payload, "v1")
    assert_equal "v1", RecordingStudioCache.read(recording, :api_payload)

    old_key = RecordingStudioCache.key_for(recording, :api_payload)
    old_generation = RecordingStudioCache.root_generation_for(recording)
    new_generation = RecordingStudioCache.invalidate_tree!(recording)
    new_key = RecordingStudioCache.key_for(recording, :api_payload)

    refute_equal old_generation, new_generation
    refute_equal old_key, new_key
    assert_match(/\A[0-9a-f-]{36}\z/, new_generation)
    assert_nil RecordingStudioCache.read(recording, :api_payload)
    event = @events.find { |item| item.name == "invalidate_tree.recording_studio_cache" }
    assert event
    assert_equal new_generation, event.payload[:root_generation]
    refute event.payload.key?(:tree_version)
  end

  def test_policy_options_passed_to_fetch_via_registry
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

  def test_entry_name_does_not_select_policy_without_registry
    recording = build_recording
    RecordingStudioCache.reset_configuration!
    RecordingStudioCache.configuration.cache_store = @memory
    RecordingStudioCache.configuration.namespace = "rsc_test"

    seen = nil
    store = RecordingStudioCache.store
    store.stub(:fetch, lambda { |_key, **options, &block|
      seen = options
      block.call
    }) do
      RecordingStudioCache.fetch(recording, :api_payload) { "x" }
    end

    assert_equal 5 * 60, seen[:expires_in]
    assert_equal 5, seen[:race_condition_ttl]
  end

  def test_explicit_policy_wins_over_registry
    recording = build_recording
    seen = nil
    store = RecordingStudioCache.store
    store.stub(:fetch, lambda { |_key, **options, &block|
      seen = options
      block.call
    }) do
      RecordingStudioCache.fetch(recording, :api_payload, policy: :short) { "x" }
    end

    assert_equal 30, seen[:expires_in]
  end

  def test_vary_digest_is_stable_and_order_independent
    recording = build_recording
    left = RecordingStudioCache.key_for(recording, :api_payload, vary: { locale: "en", format: "json" })
    right = RecordingStudioCache.key_for(recording, :api_payload, vary: { format: "json", locale: "en" })
    other = RecordingStudioCache.key_for(recording, :api_payload, vary: { locale: "fr", format: "json" })

    assert_equal left, right
    refute_equal left, other
    assert_match(%r{/v/[0-9a-f]{16}\z}, left)
  end

  def test_vary_isolates_cached_values
    recording = build_recording
    RecordingStudioCache.write(recording, :api_payload, "en", vary: { locale: "en" })
    RecordingStudioCache.write(recording, :api_payload, "fr", vary: { locale: "fr" })

    assert_equal "en", RecordingStudioCache.read(recording, :api_payload, vary: { locale: "en" })
    assert_equal "fr", RecordingStudioCache.read(recording, :api_payload, vary: { locale: "fr" })
    assert RecordingStudioCache.exist?(recording, :api_payload, vary: { locale: "en" })
    RecordingStudioCache.delete(recording, :api_payload, vary: { locale: "en" })
    refute RecordingStudioCache.exist?(recording, :api_payload, vary: { locale: "en" })
    assert_equal "fr", RecordingStudioCache.read(recording, :api_payload, vary: { locale: "fr" })
  end

  def test_read_hit_distinguishes_cached_nil_from_miss
    recording = build_recording
    RecordingStudioCache.write(recording, :api_payload, nil)

    assert_nil RecordingStudioCache.read(recording, :api_payload)
    assert RecordingStudioCache.exist?(recording, :api_payload)

    read_events = @events.select { |event| event.name == "read.recording_studio_cache" }
    assert_equal true, read_events.last.payload[:hit]

    other = build_recording
    assert_nil RecordingStudioCache.read(other, :api_payload)
    miss_events = @events.select { |event| event.name == "read.recording_studio_cache" }
    assert_equal false, miss_events.last.payload[:hit]
  end

  def test_unknown_keyword_options_raise
    recording = build_recording
    error = assert_raises(ArgumentError) do
      RecordingStudioCache.fetch(recording, :api_payload, bogus: true) { 1 }
    end
    assert_match(/unknown keyword options: bogus/, error.message)
  end

  def test_entry_type_must_be_symbol_or_string
    recording = build_recording
    error = assert_raises(ArgumentError) do
      RecordingStudioCache.fetch(recording, 12) { 1 }
    end
    assert_match(/entry must be a Symbol or String/, error.message)
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
