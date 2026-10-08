===============================================================================

RecordingStudioCache has been installed.

This gem wraps Rails.cache for recording-scoped app payloads. It is headless
(no engine mount or product UI) and does not configure Cloudflare/R2
(see RecordingStudioArtifacts for CDN publish).

Next steps:
1. Ensure the host sets a cache store (Solid Cache recommended on DO App Platform).
2. Edit config/initializers/recording_studio_cache.rb for namespace/policies/entries.
3. Call RecordingStudioCache.fetch(recording, :api_payload, policy: :api_payload) { … }.

===============================================================================
