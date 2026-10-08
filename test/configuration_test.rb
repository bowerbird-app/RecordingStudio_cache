# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioCache::Configuration.new
  end

  def test_defaults
    assert_equal "rsc", @configuration.namespace
    assert_nil @configuration.cache_store
    assert_equal 60, @configuration.policy_for(:api_payload).expires_in
    assert_equal 2, @configuration.policy_for(:api_payload).race_ttl
    assert_instance_of RecordingStudio::Hooks, @configuration.hooks
  end

  def test_merge_updates_namespace
    @configuration.merge!(namespace: "app")

    assert_equal "app", @configuration.namespace
  end

  def test_merge_ignores_unknown_keys
    @configuration.merge!(unknown_key: "ignored", namespace: "x")

    refute_respond_to @configuration, :unknown_key
    assert_equal "x", @configuration.namespace
  end

  def test_merge_with_non_enumerable_is_noop
    original = @configuration.namespace

    @configuration.merge!(nil)

    assert_equal original, @configuration.namespace
  end

  def test_merge_accepts_string_keys_and_policies
    @configuration.merge!(
      "namespace" => "from_yaml",
      "policies" => { "custom" => { "expires_in" => 15, "race_ttl" => 1 } }
    )

    assert_equal "from_yaml", @configuration.namespace
    assert_equal 15, @configuration.policy_for(:custom).expires_in
    assert_equal 1, @configuration.policy_for(:custom).race_ttl
  end

  def test_policies_assignment_merges_with_built_ins
    @configuration.policies = {
      "custom" => { "expires_in" => 15, "race_ttl" => 1 },
      "api_payload" => { "expires_in" => 90, "race_ttl" => 3 }
    }

    assert_equal 5 * 60, @configuration.policy_for(:default).expires_in
    assert_equal 15, @configuration.policy_for(:custom).expires_in
    assert_equal 90, @configuration.policy_for(:api_payload).expires_in
    assert_equal 30, @configuration.policy_for(:short).expires_in
  end

  def test_register_entry_maps_policy_and_rejects_unknown_policy
    @configuration.register_entry :api_payload_en, policy: :api_payload

    assert_equal :api_payload, @configuration.policy_name_for_entry(:api_payload_en)
    assert_nil @configuration.policy_name_for_entry(:missing)

    error = assert_raises(ArgumentError) do
      @configuration.register_entry :broken, policy: :nope
    end
    assert_match(/unknown policy/, error.message)
  end

  def test_merge_entry_policies_from_yaml
    @configuration.merge!(
      "entry_policies" => { "api_payload" => "api_payload" }
    )

    assert_equal :api_payload, @configuration.policy_name_for_entry(:api_payload)
  end

  def test_unknown_policy_falls_back_to_default
    policy = @configuration.policy_for(:missing)

    assert_equal :default, policy.name
  end

  def test_register_policy
    @configuration.register_policy(:dashboard, expires_in: 12, race_condition_ttl: 3)

    assert_equal 12, @configuration.policy_for(:dashboard).expires_in
    assert_equal 3, @configuration.policy_for(:dashboard).race_ttl
  end

  def test_to_h_reports_registered_hook_counts
    @configuration.hooks.before_initialize { nil }
    @configuration.hooks.before_initialize { nil }
    @configuration.hooks.after_service { nil }

    result = @configuration.to_h

    assert_equal "rsc", result.fetch(:namespace)
    assert_equal :rails_cache, result.fetch(:cache_store)
    assert_equal 2, result.fetch(:hooks_registered).fetch(:before_initialize)
    assert_equal 1, result.fetch(:hooks_registered).fetch(:after_service)
  end

  def test_configure_without_block_is_safe
    RecordingStudioCache.configure

    assert_kind_of RecordingStudioCache::Configuration, RecordingStudioCache.configuration
  end
end
