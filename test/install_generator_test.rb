# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_cache/install/install_generator"

class InstallGeneratorTest < Minitest::Test
  INSTALL_TEMPLATE_PATH = File.expand_path(
    "../lib/generators/recording_studio_cache/install/templates/INSTALL.md",
    __dir__
  )
  INITIALIZER_TEMPLATE_PATH = File.expand_path(
    "../lib/generators/recording_studio_cache/install/templates/recording_studio_cache_initializer.rb",
    __dir__
  )

  def build_generator(destination_root, options = {})
    RecordingStudioCache::Generators::InstallGenerator.new(
      [],
      options,
      destination_root: destination_root
    )
  end

  def test_generator_has_no_mount_or_tailwind_steps
    methods = RecordingStudioCache::Generators::InstallGenerator.instance_methods(false)

    refute_includes methods, :mount_engine
    refute_includes methods, :add_tailwind_source
    assert_includes methods, :copy_initializer
    assert_includes methods, :add_yaml_config
  end

  def test_show_readme_displays_install_guide_for_invoke_behavior
    generator = build_generator("/tmp")
    shown_templates = []

    generator.stub(:behavior, :invoke) do
      generator.stub(:readme, ->(template) { shown_templates << template }) do
        generator.show_readme
      end
    end

    assert_equal ["INSTALL.md"], shown_templates
  end

  def test_install_guide_includes_cache_host_setup_steps
    install_guide = File.read(INSTALL_TEMPLATE_PATH)

    assert_includes install_guide, "Solid Cache"
    assert_includes install_guide, "RecordingStudioCache.fetch"
    assert_includes install_guide, "invalidate_tree!"
    assert_includes install_guide, "register_entry"
    assert_includes install_guide, "headless"
    assert_includes install_guide, "RecordingStudioArtifacts"
    refute_includes install_guide, "RecordingStudio v3"
    refute_match(/mount RecordingStudioCache/, install_guide)
  end

  def test_initializer_template_documents_entry_registry
    contents = File.read(INITIALIZER_TEMPLATE_PATH)

    assert_includes contents, "register_entry"
    assert_includes contents, "Entry names do not imply a policy"
  end

  def test_migrations_generator_removed
    path = File.expand_path(
      "../lib/generators/recording_studio_cache/migrations/migrations_generator.rb",
      __dir__
    )
    refute File.exist?(path)
  end
end
