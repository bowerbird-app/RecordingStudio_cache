# RecordingStudioCache

App-side cache primitives for Recording Studio hosts and sibling gems. Thin wrappers
around **Rails.cache** with recording/root scoped keys, tree-version invalidation,
named TTL policies (including stampede-friendly `race_condition_ttl`), and
ActiveSupport::Notifications instrumentation.

## Boundary (read this first)

| Concern | Owner |
| --- | --- |
| Authenticated / API / app payload caching | **This gem** (`Rails.cache`) |
| Public HTML/JSON/YAML publish + stable CDN URL | [RecordingStudioArtifacts](https://github.com/bowerbird-app/RecordingStudio_artifacts) (Cloudflare R2) |
| Edge cache / CF purge / embeds | Cloudflare + Artifacts / Embeddable — **out of scope here** |

This gem never talks to Cloudflare, R2, or Artifacts. It does **not** hard-require Redis.
The host chooses the cache backend.

**Recommended default on DigitalOcean App Platform:** [Solid Cache](https://github.com/rails/solid_cache)
(database-backed `Rails.cache`). Redis remains optional later if a host needs it.

## Consumer API

```ruby
# Gemfile
gem "recording_studio", "~> 4.2"
gem "recording_studio_cache", github: "bowerbird-app/RecordingStudio_cache"
```

```bash
bin/rails generate recording_studio_cache:install
```

```ruby
# config/initializers/recording_studio_cache.rb
RecordingStudioCache.configure do |config|
  config.namespace = "rsc"
  config.register_policy :api_payload, expires_in: 1.minute, race_ttl: 2.seconds
end
```

```ruby
payload = RecordingStudioCache.fetch(recording, :api_payload) do
  expensive_api_payload_for(recording)
end

RecordingStudioCache.write(recording, :api_payload, payload)
RecordingStudioCache.read(recording, :api_payload)
RecordingStudioCache.delete(recording, :api_payload)

# After mutating a tree (create/revise/move/trash), bump the root version:
RecordingStudioCache.invalidate_tree!(recording.root_recording_or_self)
```

Entry names may match a registered policy (`:api_payload`). Override per call:

```ruby
RecordingStudioCache.fetch(recording, :stats, policy: :short) { … }
RecordingStudioCache.fetch(recording, :stats, expires_in: 10.seconds, race_ttl: 1.second) { … }
```

### Key shape

```
{namespace}/v1/r/{root_id}/tv/{tree_version}/rec/{recording_id}/{entry}
```

Example: `rsc/v1/r/43a6…/tv/3/rec/9f2c…/api_payload`

- **root** — `recording.root_recording_or_self` id (workspace tree)
- **tree version** — integer token in Rails.cache at `{namespace}/v1/r/{root_id}/tv`
- **recording** — the recording the payload belongs to
- **entry** — logical name (`:api_payload`, `:nav`, …)

`invalidate_tree!` increments the tree-version token. Old keys become unreachable;
no need to delete every entry under the root.

### Built-in policies

| Name | `expires_in` | `race_ttl` (`race_condition_ttl`) |
| --- | --- | --- |
| `:default` | 5 minutes | 5 seconds |
| `:api_payload` | 1 minute | 2 seconds |
| `:short` | 30 seconds | 2 seconds |
| `:long` | 1 hour | 10 seconds |

### Instrumentation

Subscribe with ActiveSupport::Notifications:

- `fetch.recording_studio_cache`
- `read.recording_studio_cache`
- `write.recording_studio_cache`
- `delete.recording_studio_cache`
- `invalidate_tree.recording_studio_cache`

Fetch/read payloads include `key`, `entry`, `policy`, `root_id`, `recording_id`, and `hit`.

```ruby
ActiveSupport::Notifications.subscribe(/recording_studio_cache/) do |name, start, finish, _id, payload|
  Rails.logger.info("[cache] #{name} hit=#{payload[:hit]} key=#{payload[:key]}")
end
```

### Host backend (Solid Cache sketch)

```ruby
# Gemfile (host app — not this gem)
gem "solid_cache"

# config/environments/production.rb
config.cache_store = :solid_cache_store
```

Optional later: `config.cache_store = :redis_cache_store, { url: ENV["REDIS_URL"] }`.
Point `RecordingStudioCache.configuration.cache_store` only if you need a store
other than `Rails.cache`.

## Dummy app

`test/dummy` is a host validation surface (Devise, Recording Studio, FlatPack).

| Field | Value |
| --- | --- |
| Email | admin@admin.com |
| Password | Password |

- `/` — cache demo: fetch workspace API payload + invalidate tree
- Cache store: `:memory_store` in development/test

Dummy credentials use the shared RecordingStudio_* development master key. Set
`RAILS_MASTER_KEY` or `test/dummy/config/master.key` (gitignored).

## Development

```bash
bundle exec rubocop
bundle exec rake test:all
```

Engine install/config conventions from the gem template remain under
`docs/gem_template/` as architectural reference.
