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

## Rate limiter

Shared fixed/TTL window limiter for sibling gems (`RecordingStudioCache::RateLimiter`).
Backends: `:null`, `:rails_cache`, `:redis`. Redis is optional — pass a client that
responds to `eval`; this gem does not hard-require the `redis` gem.

```ruby
result = RecordingStudioCache::RateLimiter.new(
  key: "embed:#{digest}",
  limit: 120,
  period: 60,              # or window: (Embeddable name)
  backend: :rails_cache,   # :null | :rails_cache | :redis
  strategy: :fixed,        # :fixed calendar bucket | :ttl rolling key
  store: Rails.cache,      # rails_cache only
  redis: redis_client,     # required for :redis (must respond to eval)
  fail_closed: false,
  prefix: "rsc:rate",
  separator: ":",          # join for prefix/key(/bucket); use "/" for Oauth-style keys
  storage_key: nil         # optional exact base key (skips prefix/key join)
).throttle

result.allowed?      # under the limit?
result.blocked?      # opposite of allowed?
result.retry_after   # Integer seconds when blocked, else nil
result.count         # hits after this call
```

Class helpers: `RateLimiter.throttle(...)` → `Result`, `RateLimiter.allow?(...)` → boolean.

`limit <= 0` disables throttling (always allowed). Rescued backend errors follow
`fail_closed:` (allow when false, block when true). Default `rescue_errors:` is the
narrow connection/IO/timeout list (plus `Redis::BaseError` when the gem is loaded).
Pass `rescue_errors: [StandardError]` to match siblings that rescue `StandardError`
today. `ArgumentError` from this gem’s own validation still raises before throttle.

`backend: :redis` raises `ArgumentError` unless `redis:` responds to `eval` (same
message if the optional `redis` gem cannot be loaded). Redis increments use one Lua
`EVAL` (INCR; EXPIRE when `count == 1` or `TTL == -1`) so `:ttl` windows are not
refreshed by blocked hits, and keys left without expiry get a TTL.

Key shape: `prefix + separator + key` (+ `separator + bucket` for `:fixed`). For exact
legacy keys, pass `separator: "/"` or `storage_key: "recording_studio_oauth/register/1.2.3.4"`.

### Sibling gem mapping

How each existing limiter would call this API (this gem only adds the shared
limiter; siblings switch in follow-up PRs):

| Gem / limiter | `key` | `limit` / `period` | `backend` / `strategy` | `rescue_errors:` |
| --- | --- | --- | --- | --- |
| **Embeddable** `RateLimiters::*` | digest(`token:ip`) | config `rate_limit` / `rate_limit_window` | `:null`, `:rails_cache`, or `:redis` + client; **`:fixed`**; `fail_closed:` from config; `prefix: "recording_studio_embeddable:rate"` | `[StandardError]` |
| **Downloadable** `RateLimiter` | per bucket `action:bucket:id` (ip / actor / recording) | each bucket’s `limit` / `period` | `:rails_cache` + config `cache_store`; **`:fixed`**; `prefix: "rs_downloadable:rate"` | `[StandardError]` |
| **RootSwitchable** `SwitchRateLimiter` | `actor_identity:device_key` | config `switch_rate_limit` | `:rails_cache`; **`:ttl`**; `prefix: "recording_studio_root_switchable:switch_rate"` | `[StandardError]` |
| **Users** `OtpRateLimiter` | `scope:key` (e.g. `resend:…`) | `limit: 1`, cooldown as `period` | `:rails_cache`; **`:ttl`**; `fail_closed: true`; block ⇒ raise their `RateLimited` | default (narrow) |
| **Oauth** `RegisterRateLimit` | client IP (`"unknown"` if blank) | `self_registered_apps_per_minute` / `1.minute` | `:rails_cache` (+ injectable store); **`:ttl`**; `prefix: "recording_studio_oauth/register"`, `separator: "/"` (or `storage_key:`) | default (narrow) |

**OTP switch note:** prefer `fail_closed: true` so a cache outage does not skip the
cooldown. The current Users limiter stores `true` under
`recording_studio_user:otp:#{scope}:#{key}`. A counter `increment` on that value
raises `NoMethodError`. The OTP migration PR must use a **new key** (or clear /
migrate the old boolean) before calling this limiter.

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
root-generation and redis rate-limiter tests).
