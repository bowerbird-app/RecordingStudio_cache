RecordingStudioCache install complete.

Next steps:

1. Review `config/initializers/recording_studio_cache.rb` (namespace, policies, entry→policy registry).
2. Configure the host `Rails.cache` backend (Solid Cache recommended on DO App Platform; Redis optional).
3. Optional: `config/recording_studio_cache.yml` for environment-specific settings.
4. Use `RecordingStudioCache.fetch(recording, :api_payload, policy: :api_payload) { … }` from host code or sibling gems.
5. Or `config.register_entry :api_payload, policy: :api_payload` so the entry name maps to a policy.
6. Call `RecordingStudioCache.invalidate_tree!(root)` after tree mutations.

This gem is headless (no engine mount, no UI). It does not publish to Cloudflare/R2.
Public/edge caching belongs to RecordingStudioArtifacts.
