# Migration Notes

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `>= 7.0`, `< 8.0` (root and dummy GitHub tag `v7.0.0`). `root_recording_for` only finds a root. Seeds and other creates call `create_root_recording!`. Dummy `config.authorize_write` allows a persisted user to start a root, then uses Accessible for later writes. Seeds bootstrap owner access before child recordings.
- Dummy includes Recording Studio migration `20261114090000_add_root_recording_id_to_recording_studio_events`. Core 6.9+ requires `recording_studio_events.root_recording_id` before events can be written. Core 7.0.0 adds no migration for the root split.
- Accessible dummy tag `v0.43.1`
- Trashable dummy tag `v0.16.1` (`require: false`; Accessible loads `recording_studio_trashable/query` only). Kept rows use `Recording.kept`.
- Root Switchable dummy tag `v0.15.1` (switcher lists Accessible `:view` roots)
- Metrics dummy tag `v0.8.0` (required by Root Switchable and Trashable; not on RubyGems)
- FlatPack tag `v0.1.366` (`>= 0.1.315`). Not a runtime dependency of this gem.
- `view_component` `>= 4.14, < 5` (via FlatPack)
- Public RubyGems and GitHub access for dependency installation
- For Redis-backed generation tests: `REDIS_URL` and the `redis` gem (dev/test)

## Verification

Install both bundles and run the complete gem and dummy app test path:

```bash
bundle install
BUNDLE_GEMFILE=test/dummy/Gemfile bundle install
bundle exec rake test:all
```

Run the dummy app from its directory for browser verification:

```bash
cd test/dummy
bin/dev
```

Use the [FlatPack repository](https://github.com/bowerbird-app/flatpack) and the live FlatPack demo linked from the top-level README for current component documentation.
