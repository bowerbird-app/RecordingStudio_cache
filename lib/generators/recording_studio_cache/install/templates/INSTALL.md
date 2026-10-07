RecordingStudioCache install complete.

Next steps:

1. Review `config/initializers/recording_studio_cache.rb` (namespace + policies).
2. Configure the host `Rails.cache` backend (Solid Cache recommended on DO App Platform; Redis optional).
3. Optional: `config/recording_studio_cache.yml` for environment-specific settings.
4. Use `RecordingStudioCache.fetch(recording, :api_payload) { … }` from host code or sibling gems.
5. Call `RecordingStudioCache.invalidate_tree!(root)` after tree mutations.

This gem does not publish to Cloudflare/R2. Public/edge caching belongs to RecordingStudioArtifacts.
