# frozen_string_literal: true

# App-side cache helpers over Rails.cache. This gem does not configure the
# cache backend — the host chooses Solid Cache (recommended on DO App Platform),
# Redis, memory, or null. Do not hard-require Redis for this gem.
#
# Public/edge caching and R2 publish belong to RecordingStudioArtifacts + Cloudflare.
RecordingStudioCache.configure do |config|
  # Key namespace prefix (default: "rsc")
  # config.namespace = "rsc"

  # Optional dedicated store; defaults to Rails.cache
  # config.cache_store = Rails.cache

  # Named policies (ttl + race_condition_ttl for stampede-friendly fetch)
  # config.register_policy :api_payload, expires_in: 1.minute, race_ttl: 2.seconds
  # config.register_policy :dashboard, expires_in: 30.seconds, race_ttl: 2.seconds

  # Entry names do not imply a policy. Map them explicitly, or pass policy: per call.
  # config.register_entry :api_payload, policy: :api_payload
end
