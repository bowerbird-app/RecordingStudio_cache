# frozen_string_literal: true

# Sibling git gems may still declare recording_studio < 5. Relax those
# requirements so this bundle can activate recording_studio 6.1.0.
# Load this file before Bundler.setup.
module WidenRecordingStudioRequirement
  GEM_NAME = "recording_studio"
  TARGET = Gem::Version.new("6.1.0")
  FLOOR = ">= 6.1.0"

  module DependencyPatch
    def requirement
      original = super
      return original unless name == WidenRecordingStudioRequirement::GEM_NAME
      return original if original.satisfied_by?(WidenRecordingStudioRequirement::TARGET)

      Gem::Requirement.new(WidenRecordingStudioRequirement::FLOOR)
    end
  end

  module SpecificationPatch
    def add_dependency(name, *requirements)
      super(name, *WidenRecordingStudioRequirement.widen_requirements(name, requirements))
    end
  end

  def self.widen_requirements(name, requirements)
    return requirements unless name.to_s == GEM_NAME

    requirement = Gem::Requirement.new(requirements)
    return requirements if requirement.satisfied_by?(TARGET)

    [FLOOR]
  end

  def self.install!
    return if defined?(@installed) && @installed

    Gem::Dependency.prepend(DependencyPatch)
    Gem::Specification.prepend(SpecificationPatch)
    @installed = true
  end
end

WidenRecordingStudioRequirement.install!
