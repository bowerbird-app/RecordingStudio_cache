# frozen_string_literal: true

module RecordingStudioCache
  # Named TTL / race_condition_ttl settings for stampede-friendly fetches.
  Policy = Data.define(:name, :expires_in, :race_ttl) do
    def initialize(name:, expires_in:, race_ttl: nil)
      super(name: name.to_sym, expires_in: expires_in, race_ttl: race_ttl)
    end

    def fetch_options
      options = {}
      options[:expires_in] = expires_in if expires_in
      options[:race_condition_ttl] = race_ttl if race_ttl
      options
    end
  end
end
