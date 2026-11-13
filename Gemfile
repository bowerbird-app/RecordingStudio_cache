# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_cache.gemspec
gemspec

# recording_studio is not published to RubyGems; resolve the gemspec pin from GitHub.
gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v6.7.0"
# flat_pack is not published to RubyGems. Recording Studio 6.7 needs >= 0.1.315.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.356"

gem "devise"
gem "puma"
gem "sprockets-rails"

group :development, :test do
  gem "debug"
  gem "minitest-mock"
  gem "redis", ">= 5.0"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
