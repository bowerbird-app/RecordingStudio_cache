# frozen_string_literal: true

require "rails/generators"

module RecordingStudioCache
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs RecordingStudioCache into your application (initializer + optional YAML)"

      def copy_initializer
        template "recording_studio_cache_initializer.rb", "config/initializers/recording_studio_cache.rb"
      end

      def add_yaml_config
        prompt = "Would you like to add `config/recording_studio_cache.yml` " \
                 "for environment-specific settings? [y/N]"
        return unless yes?(prompt)

        template "recording_studio_cache.yml", "config/recording_studio_cache.yml"
      end

      def show_readme
        readme "INSTALL.md" if behavior == :invoke
      end
    end
  end
end
