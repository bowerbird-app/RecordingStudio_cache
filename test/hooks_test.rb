# frozen_string_literal: true

require "test_helper"

class HooksTest < Minitest::Test
  def test_template_does_not_ship_a_copied_hooks_class
    refute File.exist?(File.expand_path("../lib/recording_studio_cache/hooks.rb", __dir__))
    refute defined?(RecordingStudioCache::Hooks)
  end

  def test_configuration_hooks_are_core_recording_studio_hooks
    configuration = RecordingStudioCache::Configuration.new

    assert_instance_of RecordingStudio::Hooks, configuration.hooks
  end

  def test_engine_runs_addon_hooks_through_configuration
    called = false
    RecordingStudioCache.configuration.hooks.after_initialize { called = true }

    initializer = RecordingStudioCache::Engine.initializers.find do |entry|
      entry.name == "recording_studio_cache.after_initialize"
    end
    initializer.block.call(Object.new)

    assert called
  ensure
    RecordingStudioCache.configuration.hooks.clear!
  end
end
