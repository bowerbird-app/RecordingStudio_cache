# frozen_string_literal: true

require_relative "lib/recording_studio_cache/version"

Gem::Specification.new do |spec|
  spec.name        = "recording_studio_cache"
  spec.version     = RecordingStudioCache::VERSION
  spec.authors     = ["Bowerbird"]
  spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_cache"
  spec.summary     = "App-side Rails.cache primitives for Recording Studio"
  spec.description = "Thin Recording Studio helpers over Rails.cache: recording/root scoped keys, " \
                     "root-generation invalidation, named TTL policies, vary digests, and " \
                     "ActiveSupport instrumentation. Headless (no UI). Does not publish to " \
                     "Cloudflare/R2 (see RecordingStudioArtifacts)."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bowerbird-app/RecordingStudio_cache"
  spec.metadata["changelog_uri"] = "https://github.com/bowerbird-app/RecordingStudio_cache/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"].reject do |path|
      path == ".cursor" || path.start_with?(".cursor/")
    end
  end

  spec.add_dependency "rails", "~> 8.1.0"
  spec.add_dependency "recording_studio", "~> 4.2"
end
