# RecordingStudioCache

App-side cache primitives for Recording Studio hosts and sibling gems. Thin wrappers
around **Rails.cache** with recording/root scoped keys, root-generation invalidation,
named TTL policies (including stampede-friendly `race_condition_ttl`), first-class
`vary:` variants, and ActiveSupport::Notifications instrumentation.

Headless gem: add it to the Gemfile, run the install generator for an optional
initializer/YAML, and call the API. No engine mount, no UI, no migrations.

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

## Install

```ruby
# Gemfile
gem "recording_studio", "~> 4.2"
gem "recording_studio_cache", github: "bowerbird-app/RecordingStudio_cache"
```

```bash
bin/rails generate recording_studio_cache:install
# → config/initializers/recording_studio_cache.rb
# → optional config/recording_studio_cache.yml
```

```ruby
# config/initializers/recording_studio_cache.rb
RecordingStudioCache.configure do |config|
  config.namespace = "rsc"
  config.register_policy :api_payload, expires_in: 1.minute, race_ttl: 2.seconds
  # Entry names never imply a policy — map them, or pass policy: per call.
  config.register_entry :api_payload, policy: :api_payload
end
```

YAML `policies:` merges into the built-ins (keeps `:default` and other defaults
unless you override a name).

## Consumer API

```ruby
payload = RecordingStudioCache.fetch(recording, :api_payload, policy: :api_payload) do
  expensive_api_payload_for(recording)
end

# Locale / format variants (digested into the key):
RecordingStudioCache.fetch(recording, :api_payload, policy: :api_payload, vary: { locale: "en" }) { … }

RecordingStudioCache.write(recording, :api_payload, payload, policy: :api_payload)
RecordingStudioCache.read(recording, :api_payload)
RecordingStudioCache.delete(recording, :api_payload)

# After mutating a tree (create/revise/move/trash), replace the root generation:
RecordingStudioCache.invalidate_tree!(recording.root_recording_or_self)
```

Unknown keyword options raise `ArgumentError`. Entry must be a `Symbol` or `String`.

Policy resolution order:

1. Explicit `policy:` on the call
2. Entry→policy registry (`register_entry` / YAML `entry_policies`)
3. Built-in `:default`

Per-call TTL overrides still work:

```ruby
RecordingStudioCache.fetch(recording, :stats, policy: :short) { … }
RecordingStudioCache.fetch(recording, :stats, expires_in: 10.seconds, race_ttl: 1.second) { … }
```

### Key shape

```
{namespace}/v2/r/{root_id}/rg/{root_generation}/rec/{recording_id}/{entry}
{namespace}/v2/r/{root_id}/rg/{root_generation}/rec/{recording_id}/{entry}/v/{vary_digest}
```

Example: `rsc/v2/r/43a6…/rg/550e8400-e29b-41d4-a716-446655440000/rec/9f2c…/api_payload`

- **root** — `recording.root_recording_or_self` id (workspace tree)
- **root generation** — opaque UUID token in Rails.cache at `{namespace}/v2/r/{root_id}/rg`
- **recording** — the recording the payload belongs to
- **entry** — logical name (`:api_payload`, `:nav`, …)
- **vary digest** — first 16 hex chars of SHA256 over stable sorted JSON pairs from `vary:`

`invalidate_tree!` writes a new random generation token. Old keys become unreachable;
no need to delete every entry under the root. Generation keys are written without
`expires_in` (see module docs if the store applies a global TTL).

Public helpers:

- `RecordingStudioCache.root_generation_for(recording)`
- `RecordingStudioCache.key_for(recording, entry, root_generation: nil, vary: nil)`

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
- `invalidate_tree.recording_studio_cache` (payload includes `root_generation`)

Fetch/read payloads include `key`, `entry`, `policy`, `root_id`, `recording_id`, `vary`, and `hit`.
Read `hit` uses `exist?` so a cached `nil` is still a hit.

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

CI runs the suite against PostgreSQL and a Redis service container (concurrent
root-generation tests).
