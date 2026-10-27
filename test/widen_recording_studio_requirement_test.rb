# frozen_string_literal: true

require "test_helper"
require_relative "support/widen_recording_studio_requirement"

class WidenRecordingStudioRequirementTest < Minitest::Test
  def test_widens_requirements_that_reject_recording_studio_6_1
    dependency = Gem::Dependency.new("recording_studio", "~> 4.2")

    assert dependency.requirement.satisfied_by?(Gem::Version.new("6.1.0"))
    refute dependency.requirement.satisfied_by?(Gem::Version.new("4.7.0"))
  end

  def test_widens_gemspec_dependencies_declared_below_recording_studio_5
    spec = Gem::Specification.new
    spec.name = "example"
    spec.version = "0.1.0"
    spec.add_dependency "recording_studio", "~> 4.1"

    dependency = spec.dependencies.find { |dep| dep.name == "recording_studio" }

    assert dependency.requirement.satisfied_by?(Gem::Version.new("6.1.0"))
  end

  def test_leaves_compatible_recording_studio_requirements_alone
    dependency = Bundler::Dependency.new("recording_studio", ">= 6.1.0")

    assert_equal Gem::Requirement.new(">= 6.1.0"), dependency.requirement
  end

  def test_leaves_other_gems_alone
    dependency = Bundler::Dependency.new("rails", "~> 4.2")

    assert_equal Gem::Requirement.new("~> 4.2"), dependency.requirement
  end
end
