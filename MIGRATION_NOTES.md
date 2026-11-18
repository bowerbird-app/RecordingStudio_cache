# Migration Notes

## Current Requirements

- Ruby 3.3 or newer
- Rails 8.1 or newer
- Recording Studio `>= 7.0`, `< 8.0` (root and dummy GitHub tag `v7.7.1`). `root_recording_for` only finds a root. Seeds and other creates call `create_root_recording!`. Dummy `config.authorize_write` allows a persisted user to start a root, then uses Accessible for later writes. Seeds bootstrap owner access before child recordings.
- Dummy includes Recording Studio migration `20261114090000_add_root_recording_id_to_recording_studio_events`. Core 6.9+ requires `recording_studio_events.root_recording_id` before events can be written.
- Dummy does not copy core `20261116120000` (`index_rs_events_on_timeline`), `20261116230000` (`index_rs_recordings_on_root_type_created_at_id`), `20261117120000` (`enforce_recording_studio_recording_root_invariant`), or `20261117200000` (`replace_recording_studio_recordings_root_index`). A host on core `v7.7.1` should still run them.
- Accessible dummy tag `v0.54.0` (requires Recording Studio `>= 7.7.0`, `< 8.0`)
- Trashable dummy tag `v1.2.0` (`require: false` so the engine stays off; Accessible v0.54 does not load it). Kept rows use `Recording.kept`. Trashable 1.x removes its hook registry; register hooks on `RecordingStudio.configuration.hooks`. Trashable `v1.2.0` adds `purge_at`; this dummy does not copy that migration.
- Root Switchable dummy tag `v0.16.0` (switcher lists Accessible `:view` roots). It depends on this gem `>= 0.5`, `< 1.0`, Accessible `>= 0.44.0`, `< 1.0`, and Metrics `>= 0.9.0`, `< 1.0`.
- Metrics dummy tag `v0.9.1` (required by Root Switchable and Trashable; not on RubyGems)
- FlatPack tag `v0.1.378` (`>= 0.1.315`). Not a runtime dependency of this gem.
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
