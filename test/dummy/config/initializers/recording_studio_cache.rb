# frozen_string_literal: true

RecordingStudioCache.configure do |config|
  config.namespace = "rsc_dummy"
  config.register_policy :api_payload, expires_in: 1.minute, race_ttl: 2.seconds
end
